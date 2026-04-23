# SquadFireController.gd
extends Node
class_name SquadFireController

# Wiring
@export var unit: Unit
@export var stress_controller: StressController

# Timing
@export var burst_window_s: float = 0.10      # batch rounds within this window per hex
@export var max_shots_per_tick: int = 128

## State influence (from your STATES table)
#@export var state_acc_mults: PackedFloat32Array = PackedFloat32Array([1.0, 0.9, 0.5, 0.0, 0.0])
#@export var state_rof_mults: PackedFloat32Array = PackedFloat32Array([1.0, 0.85, 0.35, 0.0, 0.0])

# NEW: state influence on target acquisition time (Normal..CombatIneffective)
#@export var state_acquire_mults: PackedFloat32Array = PackedFloat32Array([1.0, 1.15, 1.6, 9999.0, 9999.0])
#enum MoraleState { NORMAL, CAUTIOUS, PINNED, PANIC, COMBAT_INEFFECTIVE }
@export var state_acquire_mults: PackedFloat32Array = PackedFloat32Array([1.0, 0.8, 0.5, 0.0, 0.0])

# panic/CI effectively “never acquire”

# Crew-served behaviour
@export var crew_idle_to_loader: bool = true

@export var max_cover_pts: float = 5.0   # stone house is 3; you can raise if needed

@onready var calc: SquadFireCalculator = SquadFireCalculator.new()
var fin: SquadFireCalculator.SquadFireInput = SquadFireCalculator.SquadFireInput.new()

@export var base_accuracy := 0.35
@export var volley_size := 1               # rounds per burst
@export var seconds_per_volley := 1.2
@export var base_seconds_per_volley := 1.2
var accuracy_multiplier: float = 1.0

@export var stress_scale := 1.0             # global tuning
@export var stress_fast_base: float = 10.0       # baseline shock of “being shot at” 
@export var stress_fast_hit_factor: float = 20.0# adds with mean p_hit (0..1) 12
@export var stress_slow_per_round: float = 0.6  # accrues with volume
@export var stress_point_blank_bonus: float = 1.5 # extra fear at 1 hex
@export var stress_crossfire_bonus: float = 0.15    # e.g. 0.15 if multiple sources
@export var stress_max_per_volley: float = 40.0    # safety cap (per volley, per squad) # if this is lower than the kill cap, raise it
@export var weapon_stress_mult: float = 1.0   # MGs 1.2–1.4, rifles 1.0
@export var stress_resilience: float = 1.0    # better-trained squads 0.8–0.9

@export var casualty_scale: float = 1.0      # lower than 1.0 to reduce deaths overall
@export var p_disable_rifle: float = 0.12     # was 0.5; rifles should be low
@export var p_disable_mg: float = 0.18        # MGs a tad higher than rifles
@export var lethality_cap_per_volley: int = 2 # per target, per volley; 1 keeps spikes down
@export var lethality_cover_min: float = 0.6  # cover also reduces *lethality* (not just hit)
@export var lethality_cover_max: float = 1.0  # no cover → 1.0 (full lethality)
@export var lethality_mid_range: float = 0.7  # mid-range lethality multiplier
@export var lethality_far_range: float = 0.45 # far-range lethality multiplier

@export var stress_kill_fast_first: float = 30.0        # first KIA this volley (fast spike)
@export var stress_kill_fast_each: float = 15.0           # each additional KIA (fast spike)
@export var stress_kill_slow_each: float = 10.0           # per KIA (slow dread)
@export var stress_kill_ratio_bonus: float = 0.5         # +50% at 100% losses (scales with loss ratio)
@export var stress_kill_max_per_volley: float = 60.0     # cap for casualty-driven stress per volley

# ---- cover → stress dampening (fast & slow), typed nice and proper ----
@export var stress_cover_fast_min: float = 0.45   # floor at max cover (fast spike never 0)
@export var stress_cover_slow_min: float = 0.65   # floor at max cover (slow dread never 0)
@export var stress_cover_gamma: float = 1.2       # curvature; >1 gives diminishing returns

const MIN_HIT_MULT: float = 0.1   # floor at extreme cover
const HALF_POINT: float = 1.5      # cover points to halve the remaining gap to the floor

# Soldiers
var soldiers: Array[Soldier] = []
var casualties: Array[Soldier] = []

var _now_s: float = 0.0
var _accum_window_s: float = 0.0

var fire_recent: float = 0.0 # 0..1 shows that they were shooting

# Targeting
var target_hex: Vector2i:
	set(value):
		target_hex = value
		if unit.attackState == Unit.AttackState.MANUAL_GROUND:
			pass
var mortar_target_hex: Vector2i
#var target_cover: float
var target_unit: Unit
#var target_distance: int
var _pending_rounds_by_hex: Dictionary = {}    # Vector2i -> int

signal fire_shot(weapon: WeaponSpec, _mortar_target_hex: Vector2i)
signal fire_riflegrenade
signal draw_los_to_target_unit(from_hex, to_hex)

#func _ready() -> void:
	#var cover: float = 0.0 
	#cover = cover_multiplier_exp(0.0)
	#cover = cover_multiplier_exp(1.0)
	#cover = cover_multiplier_exp(2.0)
	#cover = cover_multiplier_exp(3.0)
	#cover = cover_multiplier_exp(4.0)
	#cover = cover_multiplier_exp(5.0)
	#cover = cover_multiplier_exp(6.0)
	#cover = cover_multiplier_exp(6.0)


func set_soldiers_new_target_task(target_distance: int):
	for s in soldiers:
		if s.role == RankGrades.Role.LOADER or s.role == RankGrades.Role.ASSISTANT:
			continue
		#if not s.aquire_target_task.target_id == target_unit:
		if s.weapon.can_fire_riflegrenades and target_distance <= s.weapon.riflegrenade_range:
			s.reload_task.done = false
			s.reload_task.start_time_s = s.weapon.reload_riflegrenade_s / s.rof_mult
			s.rounds_in_mag = 1
			s.weapon.riflegrenade_loaded = true
			
			#s.aquire_target_task.target_id = target_unit
			s.aquire_target_task.done = false
			s.aquire_target_task.start_time_s = _calc_acquire_delay(s)
		else:
			if s.weapon.range_hexes >= target_distance:
				#s.aquire_target_task.target_id = target_unit
				#if not s.aquire_target_task.remaining_time_s > 0.0 and not s.aquire_target_task.remaining_time_s < s.aquire_target_task.start_time_s:
				s.aquire_target_task.done = false
				s.aquire_target_task.start_time_s = _calc_acquire_delay(s)

func set_mg(machinge_guns : int):
	for i in machinge_guns:
		# Define the MG (crew-served)
		var mg: WeaponSpec = WeaponSpec.new()
		mg.name = "GPMG"
		mg.kind = WeaponSpec.WeaponKind.CREW_SERVED
		mg.rpm = 700.0
		mg.burst_rounds = 4           # “short bursts”, aye
		mg.burst_pause_s = 0.35
		mg.crew_required = 2          # gunner + loader
		mg.undercrew_penalty_mult = 1.6
		mg.priority = 10              # gets crew before anything else
		var mg_eq: SquadFireCalculator.EquipmentInstance = SquadFireCalculator.EquipmentInstance.new(mg, 1)
		fin.crew_equipment.append(mg_eq)


func set_soldiers(list: Array[Soldier]) -> void:
	soldiers = list

#var cover_map = LOSHelper.los_lookup.get(current_hex, null)
				#var targetCover = 0
#if cover_map and cover_map.has(enemy.current_hex):
					#var data = cover_map[enemy.current_hex]
					#targetCover = data["target_cover"]
					
func set_target_unit(targetUnit: Unit) -> void:
	var hex: Vector2i = Vector2i.ZERO
	var distance: int
	var had_target_before: bool = false
	if target_unit:
		had_target_before = true
	if targetUnit:
		if not targetUnit == target_unit:
			distance = LOSHelper.ground_layer.cube_distance(unit.current_cube, targetUnit.current_cube)
			var has_range: bool = false
			for soldier: Soldier in unit.squad_fire.soldiers:
				if soldier.weapon.range_hexes >= distance:
					has_range = true
			if has_range:
				hex = targetUnit.current_hex
				#var cover_map = LOSHelper.los_lookup.get(unit.current_hex, null)
				#if cover_map and cover_map.has(targetUnit.current_hex):
					#var data = cover_map[targetUnit.current_hex]
					#target_cover = data["target_cover"]
				#target_distance = LOSHelper.ground_layer.cube_distance(unit.current_cube, targetUnit.current_cube)
				if not target_unit == targetUnit:
					#_prime_acquisition_for_new_target()
					#aim_delay()
					target_unit = targetUnit
			else:
				#target_cover = 0
				target_unit = null
	else:
		#target_cover = 0
		target_unit = null
	
	target_hex = hex
	
	var target_cover: int = 0
	var target_distance: int = 0
	
	if is_instance_valid(target_unit):
		target_hex = target_unit.current_hex
		var cover_map = LOSHelper.los_lookup.get(unit.current_hex, null)
		if cover_map and cover_map.has(target_unit.current_hex):
			var data = cover_map[target_unit.current_hex]
			target_cover = data["target_cover"]
		target_distance = LOSHelper.ground_layer.cube_distance(unit.current_cube, target_unit.current_cube)
	
	var draw_los_to: Vector2i = target_hex
	if target_hex == Vector2i.ZERO:
		draw_los_to = unit.current_hex
	draw_los_to_target_unit.emit(unit.current_hex, draw_los_to)
	
	for s in soldiers:
		if s.role == RankGrades.Role.LOADER or s.role == RankGrades.Role.ASSISTANT:
			continue
		
		if not s.aquire_target_task.target_id == target_unit:
			if s.weapon.can_fire_riflegrenades and target_distance <= s.weapon.riflegrenade_range:
				s.reload_task.done = false
				s.reload_task.start_time_s = s.weapon.reload_riflegrenade_s / s.rof_mult
				s.rounds_in_mag = 1
				s.weapon.riflegrenade_loaded = true
				
				s.aquire_target_task.target_id = target_unit
				s.aquire_target_task.done = false
				s.aquire_target_task.start_time_s = _calc_acquire_delay(s)
			else:
				if s.weapon.range_hexes >= distance:
					s.aquire_target_task.target_id = target_unit
					#if not s.aquire_target_task.remaining_time_s > 0.0 and not s.aquire_target_task.remaining_time_s < s.aquire_target_task.start_time_s:
					s.aquire_target_task.done = false
					s.aquire_target_task.start_time_s = _calc_acquire_delay(s)


func set_target_hex(_target_hex: Vector2i):
	target_hex = _target_hex




func _process(delta: float) -> void:
	_now_s += delta
	_accum_window_s += delta
	
	var visible_enemies1: Array = Globals.unit_visible_enemies.get(unit, [])
	if not visible_enemies1.is_empty(): # and target_hex == Vector2i.ZERO
		if unit.moving or not unit.alive or unit.broken or unit.surrendered:
			return
		else:
			#if unit.team == Globals.team_player:
			#unit.combat.handle_auto_fire(delta, unit, unit_visible_enemies, unit.current_hex, unit.range, unit.fire_rate, unit.firepower)
			if unit.attackState == Unit.AttackState.AUTO:
				handle_auto_fire(delta, unit, unit.current_hex, unit.weapon_range, unit.fire_rate, unit.firepower)
	
	update_fire_recent(delta)
	_update_state_multipliers()
	_tick_soldiers(delta)
	
	if unit.attackState == Unit.AttackState.MANUAL_TRACK:
		if target_unit:
			var visible_enemies: Array = Globals.unit_visible_enemies.get(unit, [])
			if visible_enemies.has(target_unit):
				if not target_unit.current_hex == target_hex:
					target_hex = target_unit.current_hex
			else:
				unit.setAttackState(Unit.AttackState.AUTO)
		else:
			unit.setAttackState(Unit.AttackState.AUTO)
		#if target_unit:
			#target_distance = LOSHelper.ground_layer.cube_distance(unit.current_cube, target_unit.current_cube)
			#target_hex = target_unit.current_hex


func update_fire_recent(delta: float) -> void:
	var half_life_s: float = 1.5
	var k: float = 0.69314718056 / half_life_s
	fire_recent *= exp(-k * delta)
	if fire_recent < 0.0:
		fire_recent = 0.0

func _update_state_multipliers() -> void:
	var _state_idx: int = stress_controller.state
	var acc_mult: float = 1.0
	var rof_mult: float = 1.0
	acc_mult = UnitStates.STATE_MOD[stress_controller.state]["acc"]
	rof_mult = UnitStates.STATE_MOD[stress_controller.state]["rof"]

	var i: int = 0
	while i < soldiers.size():
		var s: Soldier = soldiers[i]
		if s.is_alive:
			s.acc_mult = acc_mult
			s.rof_mult = rof_mult
		i += 1

#var fire_timer: float = 0.0
#func handle_auto_fire(delta, _shooter: Node2D, current_hex, _range, fire_rate, _firepower):
	#fire_timer -= delta
	#if fire_timer > 0.0:
		#return  # Still waiting for next shot
		#
	#var visible_enemies: Array = Globals.unit_visible_enemies.get(unit, [])
	#if target_unit:
		#if visible_enemies.has(target_unit):
			#if target_unit and target_unit.alive and not target_unit.surrendered:
				##var distance = current_hex.distance_to(target_unit.current_hex)
				#var distance: int = LOSHelper.ground_layer.cube_distance(unit.current_cube, target_unit.current_cube)
				#var has_range: bool = false
				#for soldier: Soldier in unit.squad_fire.soldiers:
					#if soldier.weapon.range_hexes >= distance:
						#has_range = true
				#if has_range:
					#var cover_map = LOSHelper.los_lookup.get(current_hex, null)
					#var targetCover = 0
					#if cover_map and cover_map.has(target_unit.current_hex):
						#var data = cover_map[target_unit.current_hex]
						#targetCover = data["target_cover"]
					#
					#target_unit.set_cover(targetCover)
					#fire_timer = fire_rate
					#return
				#else:
					#target_unit = null
					#unit.order(Globals.UnitCmd.ATTACK, target_unit)
					##set_target_unit(target_unit)
			#else:
				#target_unit = null
				#unit.order(Globals.UnitCmd.ATTACK, target_unit)
				##set_target_unit(target_unit)
	#for enemy in visible_enemies:
		#if enemy and enemy.alive and not enemy.surrendered:
			#var distance: int = LOSHelper.ground_layer.cube_distance(unit.current_cube, enemy.current_cube)
			#var has_range: bool = false
			#for soldier: Soldier in unit.squad_fire.soldiers:
				#if soldier.weapon.range_hexes >= distance:
					#has_range = true
			#if has_range:
				#var cover_map = LOSHelper.los_lookup.get(current_hex, null)
				#var targetCover = 0
				#if cover_map and cover_map.has(enemy.current_hex):
					#var data = cover_map[enemy.current_hex]
					#targetCover = data["target_cover"]
				#
				##set_target_unit(enemy)
				#unit.order(Globals.UnitCmd.ATTACK, enemy)
				#enemy.set_cover(targetCover)
				#fire_timer = fire_rate
				#
				#break

var fire_timer: float = 0.0

func handle_auto_fire(
	delta: float,
	_shooter: Node2D,
	current_hex: Variant,
	_range: int,
	fire_rate: float,
	_firepower: float
) -> void:
	fire_timer -= delta
	if fire_timer > 0.0:
		return

	var visible_enemies: Array = Globals.unit_visible_enemies.get(unit, [])
	if visible_enemies.is_empty():
		return

	var best_enemy: Node = null
	var best_score: float = -INF
	var best_cover: int = 0

	for enemy in visible_enemies:
		if not is_instance_valid(enemy):
			continue
		if not enemy.alive:
			continue
		if enemy.surrendered:
			continue
		
		var units_in_enemy_hex: Array[Unit] = LOSHelper.find_units_at(enemy.current_hex)
		var has_friendly_in_target_hex: bool = false
		for _unit in units_in_enemy_hex:
			if _unit.team == unit.team and not _unit.surrendered:
				has_friendly_in_target_hex = true
				break
		if has_friendly_in_target_hex:
			continue
		
		var score_pack: Dictionary = _score_enemy_for_target(unit, enemy, current_hex)
		var score: float = float(score_pack["score"])
		
		if score > best_score:
			best_score = score
			best_enemy = enemy
			best_cover = int(score_pack["cover"])

	if best_enemy == null:
		if not unit.squad_fire.target_unit == null:
			target_unit = null
			unit.order(Globals.UnitCmd.FIRE_AT_UNIT, target_unit)
		return
	
	unit.order(Globals.UnitCmd.FIRE_AT_UNIT, best_enemy)
	best_enemy.set_cover(best_cover)
	fire_timer = fire_rate


func _score_enemy_for_target(shooter_unit: Unit, enemy: Unit, current_hex: Vector2i) -> Dictionary:
	var distance: int = LOSHelper.ground_layer.cube_distance(shooter_unit.current_cube, enemy.current_cube)
	if distance < 0:
		distance = 0

	var best_ratio: float = 0.0
	var has_range: bool = false

	for soldier in shooter_unit.squad_fire.soldiers:
		var w_range: int = int(soldier.weapon.range_hexes)
		if w_range >= distance:
			has_range = true

			var ratio: float = float(w_range) / float(distance) # bigger is better
			if ratio > best_ratio:
				best_ratio = ratio

	if not has_range:
		return {"score": -INF, "cover": 0}

	var cover_map = LOSHelper.los_lookup.get(current_hex, null)
	var targetCover = 0
	if cover_map and cover_map.has(enemy.current_hex):
		var data = cover_map[enemy.current_hex]
		targetCover = data["target_cover"]
	enemy.set_cover(targetCover)
	var cover_val: int = targetCover
	var cover_penalty: float = float(cover_val) # tune weights below to match your cover scale

	var move_bonus: float = 0.0
	if enemy.moving:
		move_bonus = 1.0

	# weights (tune)
	var w_range_ratio: float = 10.0
	var w_move: float = 2.0
	var w_cover: float = 3.0

	var score: float = 0.0
	score += best_ratio * w_range_ratio
	score += move_bonus * w_move
	score -= cover_penalty * w_cover

	return {"score": score, "cover": cover_val}



func fire_mortar(map_hex: Vector2i):
	aim_delay()
	mortar_target_hex = map_hex
	


func _tick_soldiers(delta: float) -> void:
	var target_cover: int = 0
	var target_distance: int = 0
	
	if is_instance_valid(target_unit):
		var cover_map = LOSHelper.los_lookup.get(unit.current_hex, null)
		if cover_map and cover_map.has(target_unit.current_hex):
			var data = cover_map[target_unit.current_hex]
			target_cover = data["target_cover"]
		target_distance = LOSHelper.ground_layer.cube_distance(unit.current_cube, target_unit.current_cube)
	
	
	var rounds_emitted: int = 0

	# count available crew for MGs
	var crew_available: int = _count_role(RankGrades.Role.LOADER)
	var support_crew_available: int = _count_role(RankGrades.Role.ASSISTANT)
	var gunners: Array[int] = _indices_with_role(RankGrades.Role.GUNNER)

	# handle gunners first (crew-served)
	var j: int = 0
	while j < gunners.size():
		var idx: int = gunners[j]
		var s: Soldier = soldiers[idx]
		if s.is_alive:
			rounds_emitted += await _try_fire_soldier(delta, s, true, crew_available, support_crew_available, target_distance, target_cover)
			if rounds_emitted > 0:
				pass
			if rounds_emitted >= max_shots_per_tick:
				return
		j += 1

	# then everyone else
	var i: int = 0
	while i < soldiers.size():
		var s2: Soldier = soldiers[i]
		if s2.is_alive:
			if s2.role != RankGrades.Role.GUNNER:
				rounds_emitted += await _try_fire_soldier(delta, s2, false, 0, 0, target_distance, target_cover)
				if rounds_emitted >= max_shots_per_tick:
					return
		i += 1

func _try_fire_soldier(delta: float, s: Soldier, is_crew_served: bool, crew_available: int, support_crew_available: int, target_distance: int, target_cover: int) -> int:
	var state_idx: int = stress_controller.state
	var delta_multiplyer: float = state_acquire_mults[state_idx]
	var delta_mod: float = delta * delta_multiplyer 
	
	
	if unit.attackState == Unit.AttackState.MANUAL_GROUND:
		pass
	
	if unit.in_close_combat:
		return 0
	if unit.moving:
		return 0
	if not s.is_weapon_setup_done(delta_mod):
		return 0
	if not s.is_weapon_reload_done(delta_mod):
		return 0
	if not s.is_acquiring_target_done(delta_mod):
		return 0
	
	if Debug.dont_fire_wepaons:
		return 0
	
	if not target_hex == Vector2i.ZERO:
		pass
	
	if target_hex == Vector2i.ZERO and not s.weapon.family == WeaponSpec.Family.MORTAR:
		return 0
	
	if mortar_target_hex == Vector2i.ZERO and s.weapon.family == WeaponSpec.Family.MORTAR:
		return 0
	
	if s.weapon.ammunition <= 0:
		return 0
	
	if target_distance > s.weapon.range_hexes:
		#set_target_unit(null) # this should only happen if none have range
		return 0
	
	var _mortar_target_hex: Vector2i = mortar_target_hex
	
	var batch_targets: Array[Unit] = []
	var visible_enemies: Array = Globals.unit_visible_enemies.get(get_parent(), [])
	for u in visible_enemies:
		if is_instance_valid(u):
			if u.alive:
				if not u.surrendered:
					#if u.current_hex == target_hex:
					batch_targets.append(u)
	
	#if batch_targets.is_empty() and not s.weapon.family == WeaponSpec.Family.MORTAR:
		#set_target_unit(null)
		#return 0
	if batch_targets.is_empty() and unit.attackState == Unit.AttackState.AUTO:
		set_target_unit(null)
		return 0
	if batch_targets.is_empty() and unit.attackState == Unit.AttackState.MANUAL_TRACK:
		unit.setAttackState(Unit.AttackState.AUTO)
		set_target_unit(null)
		return 0
	
	
	# Loader dont fire their weapon
	if s.role == RankGrades.Role.LOADER or s.role == RankGrades.Role.ASSISTANT:
		return 0
	
	
	#if s.jammed:
		## simple unjam: use reload time as clear jam delay
		#if s.next_ready_s <= _now_s:
			#s.jammed = false
			#s.next_ready_delta_s = s.weapon.reload_s / s.rof_mult
			#s.next_ready_s = _now_s + s.next_ready_delta_s
			#s.next_ready_start_s = _now_s
		#return 0
	
	#mortar_target_hex = Vector2i.ZERO
	
	if s.weapon.can_fire_riflegrenades:
		pass
	
	

	# check crew requirement
	var _crew_mult: float = 1.0
	if is_crew_served:
		if s.weapon.crew_required > 1:
			var ok: bool = crew_available >= (s.weapon.crew_required - 1)
			if not ok:
				_crew_mult = s.weapon.undercrew_penalty_mult
	var efficiency_mult: float = compute_support_efficiency(support_crew_available, s.weapon.support_crew_optimal)
	if efficiency_mult < 1.0:
		pass

	if s.weapon.riflegrenade_loaded == true and target_distance > s.weapon.riflegrenade_range:
		s.rounds_in_mag = 0

	# determine burst size for this weapon
	var rounds_in_mag: int = s.rounds_in_mag
	var shots: int = determine_burst_size(s.weapon, s.rounds_in_mag)
	
	if unit.attackState == Unit.AttackState.MANUAL_GROUND:
		if unit.attack_ground_rounds_budget <= 0:
			unit.setAttackState(Unit.AttackState.AUTO)
		
		unit.attack_ground_rounds_budget -= shots
	
	# emit shots immediately into current window
	# visual
	_add_rounds_to_hex(target_hex, shots)
	#fire_shot.emit()
	
	# audio
	var auto_fire: bool = false
	if s.weapon.fire_mode == WeaponSpec.FireMode.BURST:
		auto_fire = true
	# audio
	if shots > 0:
		_on_fire_weapon(s.weapon, unit.position, auto_fire, s.id, unit)
	
	# spend ammo
	s.rounds_in_mag -= shots
	s.weapon.ammunition -= shots
	
	# handle riflegrenades
	var riflegrenade: bool = false
	if s.weapon.riflegrenade_loaded == true and target_distance <= s.weapon.riflegrenade_range:
		riflegrenade = true
	
	if riflegrenade == true:
		fire_riflegrenades(s)
		s.weapon.riflegrenade_loaded = false
	else:
		fire_shots(s, shots, s.weapon.rpm, auto_fire, _mortar_target_hex)
	
	
	if shots <= 0:
		# reload
		if s.weapon.can_fire_riflegrenades and target_distance <= s.weapon.riflegrenade_range:
			s.reload_task.done = false
			s.reload_task.start_time_s = s.weapon.reload_riflegrenade_s / s.rof_mult
			s.rounds_in_mag = 1
			s.weapon.riflegrenade_loaded = true
		else:
			s.reload_task.done = false
			s.reload_task.start_time_s = s.weapon.reload_s / s.rof_mult
			s.rounds_in_mag = s.weapon.mag_capacity
		return 0
	
	if shots > 1:
		pass
	
	# apply jam chance
	#var k: int = 0
	#var jammed_now: bool = false
	#while k < shots:
		#var r: float = randf()
		#if r < s.weapon.jam_per_shot:
			#jammed_now = true
		#k += 1
	#if jammed_now:
		#s.jammed = true
	
	# mortar reload
	if not s.weapon.family == WeaponSpec.Family.MORTAR:
		if not is_instance_valid(target_unit):
			target_unit = null
		
		# cadence to next burst (respect soldier’s rof and crew)
		var rps: float = s.weapon.rpm / 60.0
		if rps < 1.0:
			rps = 1.0
		var fire_time_s: float = float(shots) / rps
		var pause_s: float = s.weapon.burst_pause_s
		var _total_cadence_s: float = (fire_time_s + pause_s) / (s.rof_mult)
		
		s.aquire_target_task.target_id = target_unit
		s.aquire_target_task.done = false
		s.aquire_target_task.start_time_s = _calc_acquire_delay(s) + _total_cadence_s
	
	# reload
	if s.rounds_in_mag <= 0:
		if s.weapon.can_fire_riflegrenades and target_distance <= s.weapon.riflegrenade_range:
			s.reload_task.done = false
			s.reload_task.start_time_s = s.weapon.reload_riflegrenade_s / s.rof_mult
			s.rounds_in_mag = 1
			s.weapon.riflegrenade_loaded = true
		else:
			s.reload_task.done = false
			s.reload_task.start_time_s = s.weapon.reload_s / s.rof_mult
			s.rounds_in_mag = s.weapon.mag_capacity
		#return 0 # TODO figure out why this was in place? this just prohibits that damage is done
	
	var _target_hex = target_hex
	if s.weapon.family == WeaponSpec.Family.MORTAR:
		_target_hex = _mortar_target_hex
	var dist: float = unit.position.distance_to(LOSHelper.ground_layer.map_to_local(_target_hex))
	
	var life: float = dist / s.weapon.projectile_speed      # seconds
	if s.weapon.can_fire_riflegrenades:
		life = dist / s.weapon.riflegrenade_projectile_speed
	await get_tree().create_timer(life).timeout
	
	# handle result on enemy unit
	fire_at(shots, s.weapon, riflegrenade, _target_hex, target_distance, target_cover, batch_targets, unit)
	return shots


func compute_support_efficiency(support_crew_available: int, support_crew_optimal: int) -> float:
	var ratio: float = 1.0
	if support_crew_optimal > 0:
		ratio = float(support_crew_available) / float(support_crew_optimal)
	
	# clamp ratio to [0, 1]
	if ratio < 0.0:
		ratio = 0.0
	else:
		if ratio > 1.0:
			ratio = 1.0
	
	# 0 helpers -> 0.5, full helpers -> 1.0
	var multiplier: float = 0.5 + 0.5 * ratio
	return multiplier

# Util: returns a single normally-distributed sample (mean 0, stddev 1)
func _rand_normal() -> float:
	var u1: float = 0.0
	var u2: float = 0.0
	# avoid log(0)
	u1 = randf()
	while u1 <= 0.0:
		u1 = randf()
	u2 = randf()
	var z0: float = sqrt(-2.0 * log(u1)) * cos(2.0 * PI * u2)
	return z0


# Determine burst size with sensible variance and clamping
func determine_burst_size(weapon: WeaponSpec, rounds_in_mag: int) -> int:
	# base nominal
	var base: int = int(weapon.burst_rounds)
	if base < 1:
		base = 1

	var shots: int = base
	if weapon.fire_mode == WeaponSpec.FireMode.BURST:
		# choose variance fraction by weapon class (tune these constants as you wish)
		var variance_fraction: float = 0.25        # default: ±25%
		if weapon.fire_mode == WeaponSpec.FireMode.BURST:
			variance_fraction = 0.35               # SMGs are a bit more 'spray-y'
		#elif weapon.type == WeaponSpec.WeaponType.MG:
			#variance_fraction = 0.40               # MGs have larger variability

		# compute stddev in rounds (at least 1 round)
		var stddev: float = max(1.0, float(base) * variance_fraction)

		# draw a gaussian offset, round to integer
		var gauss: float = _rand_normal()
		var sample: float = float(base) + gauss * stddev
		shots = int(round(sample))
		
		# small chance to produce a sustained longer burst (suppression)
		var r: float = randf()
		if r < 0.10: # 10% chance
			shots = min(rounds_in_mag, shots + int(round(float(weapon.burst_rounds) * 0.75)))

	# clamp to sensible bounds
	if shots < 1:
		shots = 1
	if shots > rounds_in_mag:
		shots = rounds_in_mag
			
	return shots


func aim_delay():
	var state_idx: int = stress_controller.state
	var acquire_mult: float = 1.0
	if state_idx >= 0 and state_idx < state_acquire_mults.size():
		acquire_mult = state_acquire_mults[state_idx]
	for s in soldiers:
		if s.role == RankGrades.Role.LOADER or s.role == RankGrades.Role.ASSISTANT:
			continue
		s.aquire_target_task.done = false
		s.aquire_target_task.start_time_s = _calc_acquire_delay(s) * acquire_mult
				
		#var settle_s: float = _calc_acquire_delay(s) * acquire_mult
		#s.next_ready_delta_s = settle_s
		#s.next_ready_s = _now_s + s.next_ready_delta_s
		#s.next_ready_start_s = _now_s
		## ensure we don’t fire before we’ve acquired, even if next_ready_s was in the past
		#if s.next_ready_s < s.acquire_ready_s and not s.acquire_ready_s == INF:
			#s.next_ready_s = s.acquire_ready_s
			#s.next_ready_start_s = _now_s
			#s.next_ready_delta_s = s.acquire_ready_s - _now_s 
		#


func fire_shots(s: Soldier, shots: int, rpm: float, auto_fire: bool, _mortar_target_hex: Vector2i):
	var interval: float = 60.0 / rpm
	for shot in range(shots):
		fire_shot.emit(s.weapon, _mortar_target_hex)
		if get_tree(): # mighit be already freed or removed as child
			await get_tree().create_timer(interval).timeout
	if auto_fire:
		_on_stop_mg_loop(s.weapon, unit.position, s.id, unit)


func fire_riflegrenades(s: Soldier):
	fire_riflegrenade.emit(s.weapon)

func add_fire_impulse(rounds_fired: int, max_rounds_ref: int) -> void:
	var x: float = float(rounds_fired) / float(max_rounds_ref)
	if x > 1.0:
		x = 1.0
	fire_recent += x
	if fire_recent > 1.0:
		fire_recent = 1.0

func fire_at(total_rounds: int, weapon: WeaponSpec, riflegrenade: bool, _target_hex: Vector2i, target_distance: int, target_cover: int, batch_targets: Array[Unit], unit: Unit) -> void:
	# debug
	#return
	#if not riflegrenade:
		#return
	#if not weapon.family == WeaponSpec.Family.ROCKET_LAUNCHER:
		#return
	#if not weapon.ammo_type == WeaponSpec.AmmoType.HE and not riflegrenade:
		#return
	# FIXME units should not break when pinned but stress level not full
	# TODO refactor fire functions
	# TODO riflegrenate hits instant?
	add_fire_impulse(total_rounds, 10)
	var terrain_defense_bonus: float = target_cover
	if weapon.family == WeaponSpec.Family.MORTAR:
		terrain_defense_bonus = LOSHelper.is_sample_point_in_building(LOSHelper.ground_layer.map_to_local(_target_hex))

	# --- collect all enemy squads in the target hex ---
	#var batch_targets: Array = []
	#batch_targets = LOSHelper.find_units_at(_target_hex)

	
	#var visible_enemies: Array = Globals.unit_visible_enemies.get(get_parent(), [])
	#if weapon.family == WeaponSpec.Family.MORTAR:
		#for u in Globals.units:
			#if is_instance_valid(u):
				#if u.alive:
					#if not u.surrendered:
						#if u.current_hex == _mortar_target_hex:
							#batch_targets.append(u)
	#else:
		#for u in visible_enemies:
			#if is_instance_valid(u):
				#if u.alive:
					#if not u.surrendered:
						#if u.current_hex == target_hex:
							#batch_targets.append(u)
	
	for _unit in Globals.get_units():
		if _unit.current_hex == _target_hex:
			if not batch_targets.has(_unit):
				batch_targets.append(_unit)
	
	if batch_targets.is_empty():
		# no enemys to be hit
		return
	
	# --- prep per-squad data: cover/exposure & hit prob (same maths as resolve_volley) ---
	# We keep exposure simple here (1.0). If you’ve got per-squad exposure, plug it in.
	var _base_accuracy: float = 0.35
	
	var state_mod: Dictionary = STATES.STATE_MOD[unit.stress_system.state]
	var state_acc_mod: float = state_mod.acc
	
	#var to_hit_distance_mod: float = clamp(1.0 - float(target_distance) * 0.002, 0.1, 1.0)
	var to_hit_distance_mod: float = float(target_distance) / float(weapon.range_hexes)
	to_hit_distance_mod = clamp(1.0 - to_hit_distance_mod, 0.0, 1.0)
	
	var cover_mod: float = cover_multiplier_exp(terrain_defense_bonus)
	
	# handle air bursts in woods
	if weapon.family == WeaponSpec.Family.MORTAR and terrain_defense_bonus == 1:
		cover_mod = 2.0
	
	var is_point_blank: bool = target_distance == 1
	
	var shooter_stress: float = 0.0
	if unit and "stress_system" in unit:
		shooter_stress = float(unit.stress_system.S_eff)
	
	var shooter_stress_mod: float = lerp(0.4, 1.0, 1.0 - (shooter_stress / 100.0))
	
	var chance_to_hit: float = base_accuracy * state_acc_mod
	chance_to_hit *= to_hit_distance_mod
	chance_to_hit *= cover_mod
	chance_to_hit *= shooter_stress_mod
	if is_point_blank:
		chance_to_hit *= 2.0
	else:
		chance_to_hit *= 1.0
	if riflegrenade == true:
		if target_distance <= weapon.riflegrenade_range:
			chance_to_hit *= 4
		else:
			chance_to_hit *= 2
	if weapon.family == WeaponSpec.Family.SPIGOT_LAUNCHER or weapon.family == WeaponSpec.Family.ROCKET_LAUNCHER or weapon.family == WeaponSpec.Family.MORTAR:
		if target_distance <= weapon.range_hexes:
			chance_to_hit *= 4
		else:
			chance_to_hit *= 2
	
	var n_targets: int = batch_targets.size()
	var chance_to_hit_per_target: Array = []
	
	# --- slower recovery while under fire ---
	var pressure_rps: float = float(total_rounds)   # or total_rounds / volley_dt if you track it
	var j: int = 0
	while j < n_targets:
		var u_mark: Node = batch_targets[j]
		if "stress_system" in u_mark:
			var sc: StressController = u_mark.stress_system as StressController
			if sc != null:
				sc.mark_under_fire(pressure_rps)
		j += 1

	var i: int = 0
	while i < n_targets:
		var u: Unit = batch_targets[i]
		
		# only visual update
		u.set_cover(int(terrain_defense_bonus))
		u.receive_fire(terrain_defense_bonus)
		
		var state: STATES.MoraleState = u.stress_system.state
		if state == STATES.MoraleState.PANIC:
			chance_to_hit *= 4
		if state == STATES.MoraleState.PINNED:
			chance_to_hit *= 0.2
		
		chance_to_hit = clamp(chance_to_hit, 0.00001, 0.95)
		chance_to_hit_per_target.append(chance_to_hit)
		i += 1

	# --- assign each round to ONE squad and roll the hit there ---
	# Even assignment chance; to weight, build a weight list and roulette-pick.
	var hits_per_target: Array = []
	i = 0
	while i < n_targets:
		hits_per_target.append(0)
		i += 1
	
	#var enclosure_factor: float = 1.0
	i = 0
	if riflegrenade == true or weapon.ammo_type == WeaponSpec.AmmoType.HE:
		if weapon.type == WeaponSpec.Family.MORTAR:
			if terrain_defense_bonus == 1: # reflects airbursts in wood # TODO reflect airbursts betterds
				cover_mod = 1.5
		#var max_possible_casualties: float = weapon.he_burst_radius # * cover_mod #* burst_quality
		# TODO HE weapons should hit multiple target but a bit more elaborate
		var max_possible_casualties: float = weapon.he_burst_radius
		#if riflegrenade:
			#max_possible_casualties
		while i < n_targets:
			var ii: int = 0
			while ii < max_possible_casualties:
				var p_hit: float = float(chance_to_hit_per_target[i])
				p_hit = p_hit - (randf_range(0.01, p_hit * 0.1) * ii)
				p_hit = clamp(p_hit, 0.00001, 0.95)
				var roll : float = randf()
				if roll < p_hit:
					hits_per_target[i] = int(hits_per_target[i]) + 1
				ii += 1
			i += 1
	else:
		i = 0
		while i < total_rounds:
			# pick recipient squad
			var idx: int = randi() % n_targets
			# roll hit with that squad's p
			var p_hit: float = float(chance_to_hit_per_target[idx])
			var roll : float = randf()
			if roll < p_hit:
				hits_per_target[idx] = int(hits_per_target[idx]) + 1
			i += 1
	
	if target_cover == 0.0:
		pass
	
	# --- convert hits → casualties per squad (multi-cas possible, sensible cap) ---
	# Decide per-hit disable based on weapon; here we default to rifle numbers
	var chance_to_disable: float = 0.12
	if riflegrenade == true or weapon.ammo_type == WeaponSpec.AmmoType.HE:
		chance_to_disable = 0.5

	# Range and cover reduce *lethality* further (separate from hit chance)
	# this should not matter when firing explosives
	#var lethality_range_mult: float = _range_lethality_mult(target_distance, int(unit.weapon_range))
	var lethality_range_mod: float = float(target_distance) / float(weapon.range_hexes)
	lethality_range_mod = clamp(1.0 - lethality_range_mod, 0.0, 1.0)
	if riflegrenade == true or weapon.ammo_type == WeaponSpec.AmmoType.HE:
		lethality_range_mod = 1.0

	# the idea here is that hard cover also modifies lethallity and not just accuracy, but needs rework
	#var lethality_cover_mult: float = lerp(lethality_cover_min, lethality_cover_max, 1.0 - cover_norm)
	#var lethality_cover_mult: float = lerp(0.6, 1.0, 1.0 - (target_cover / 5)) # what does this?
	var lethality_cover_mult: float = cover_multiplier_exp(terrain_defense_bonus)
	#lethality_cover_mult *= lethality_cover_mult

	# Final per-hit disable after all throttles
	chance_to_disable = chance_to_disable * lethality_range_mod * lethality_cover_mult * casualty_scale
	if chance_to_disable < 0.01:
		chance_to_disable = 0.01  # tiny floor so hits can still matter

	# Convert hits → casualties with a capped, smooth hazard form
	# lambda = hits * p_disable_final;  p_cas = 1 - exp(-lambda)
	# This scales gently and avoids huge spikes.
	var casualties_per_target: Array = []
	var target_i: int = 0
	while target_i < n_targets:
		var hits_i: int = int(hits_per_target[target_i])
		var casualties_i: int = 0

		if hits_i > 0:
			var lambda_val: float = float(hits_i) * chance_to_disable
			var p_cas: float = 1.0 - exp(-lambda_val)
			
			var d: int = 0
			while d < hits_i:
				if randf() < p_cas:
					casualties_i += 1
				else:
					casualties_i += 0
				d += 1

		# Never exceed living heads, if present
		var u_chk: Node = batch_targets[target_i]
		if "members_alive" in u_chk:
			if casualties_i > int(u_chk.members_alive):
				casualties_i = int(u_chk.members_alive)
	
		#casualties_i = u_chk.members_alive
		casualties_per_target.append(casualties_i)
		target_i += 1


	# --- compute ONE shared stress payload (equal for all squads) ---
	var mean_chance_to_hit: float = _get_mean_change_to_hit(chance_to_hit_per_target, n_targets)

	# base fast shock + how “accurate” incoming fire looks
	var s_fast: float = mean_chance_to_hit * (stress_fast_hit_factor + stress_fast_base) * float(total_rounds)
	#var s_fast: float = stress_fast_base + mean_chance_to_hit * stress_fast_hit_factor * float(total_rounds)

	# slow stress grows with sheer volume; cover damps it
	var s_slow: float = float(total_rounds) #* stress_slow_per_round
	
	# apply cover damp to stress (not boost!)
	var stress_cover_mod: float = cover_multiplier_exp(terrain_defense_bonus) # 1 cover = 1.0; 3 cover = 0.63
	#if riflegrenade or weapon.family == WeaponSpec.Family.MORTAR:
		
	if weapon.ammo_type == WeaponSpec.AmmoType.HE or riflegrenade:
		
		var stress_mod: float = remap(unit.stress_system.S_eff, 0.0, 100.0, 1.0, 0.2)
		s_fast = stress_fast_base * stress_mod + mean_chance_to_hit * weapon.he_suppression_power
		s_slow = stress_fast_base * stress_mod + mean_chance_to_hit * weapon.he_suppression_power
		pass
		#stress_cover_mod = weapon.he_suppression_power
		#stress_cover_mod = stress_cover_mod * 4.0
	
	#var stress_cover_fast_mod: float = _stress_cover_mult(cover_norm, stress_cover_fast_min) # 1 cover = 1.0; 3 cover = 0.63
	#var stress_cover_slow_mod: float = _stress_cover_mult(cover_norm, stress_cover_slow_min) # 1 cover = 1.0; 3 cover = 0.76
	if not weapon.ammo_type == WeaponSpec.AmmoType.HE and not riflegrenade:
		s_fast *= stress_cover_mod
		s_slow *= stress_cover_mod

	# point-blank fear spike
	if int(target_distance) == 1:
		s_fast *= stress_point_blank_bonus
		s_slow *= stress_point_blank_bonus
	
	# distance mod
	if not weapon.ammo_type == WeaponSpec.AmmoType.HE and not riflegrenade:
		var stress_distance_mod: float = float(target_distance) / float(weapon.range_hexes)
		stress_distance_mod = 1.0 - 0.5 * stress_distance_mod
		s_fast *= stress_distance_mod
		s_slow *= stress_distance_mod
	
	## crossfire bonus if you track it outside; else leave 0.0
	#if stress_crossfire_bonus > 0.0:
		#s_fast *= (1.0 + stress_crossfire_bonus)
		#s_slow *= (1.0 + stress_crossfire_bonus)
	#else:
		#s_fast *= 1.0
		#s_slow *= 1.0

	## weapon flavour & global scale
	#s_fast *= weapon_stress_mult * stress_scale
	#s_slow *= weapon_stress_mult * stress_scale

	# clamp so one volley can’t nuke morale outright
	if s_fast > stress_max_per_volley:
		s_fast = stress_max_per_volley
	if s_slow > stress_max_per_volley:
		s_slow = stress_max_per_volley
	
	
	# --- casualties → extra shock (add to s_fast / s_slow) ---
	var casualties_total: int = 0
	var members_total_before: int = 0
	var kk: int = 0
	while kk < n_targets:
		var c_i: int = int(casualties_per_target[kk])
		casualties_total += c_i

		var u0: Node = batch_targets[kk]
		var heads_before: int = 0
		if "members_alive" in u0:
			# members_alive is after losses; add back this volley’s casualties to estimate pre-volley heads
			heads_before = int(u0.members_alive) + c_i
		else:
			heads_before = 0
		members_total_before += heads_before
		kk += 1

	var kill_fast: float = 0.0
	var kill_slow: float = 0.0
	if casualties_total > 0:
		# fast spike: first KIA hits hardest, the rest add smaller spikes
		#kill_fast = stress_kill_fast_first
		#if casualties_total > 1:
			#kill_fast += float(casualties_total - 1) * stress_kill_fast_each
		
		kill_fast = float(casualties_total) * stress_kill_fast_each
		
		# slow dread scales with body count
		kill_slow = float(casualties_total) * stress_kill_slow_each

		## scale by loss ratio (bigger shock for small, mauled groups)
		#var ratio: float = 0.0
		#if members_total_before > 0:
			#ratio = float(casualties_total) / float(members_total_before)
		#var ratio_mult: float = 1.0 + ratio * stress_kill_ratio_bonus

		#kill_fast *= ratio_mult
		#kill_slow *= ratio_mult

		# per-volley casualty shock caps (separate from your general stress clamp)
		if kill_fast > stress_kill_max_per_volley:
			kill_fast = stress_kill_max_per_volley
		if kill_slow > stress_kill_max_per_volley:
			kill_slow = stress_kill_max_per_volley

		# add to the base stress built from rounds/hits
		s_fast += kill_fast
		s_slow += kill_slow

	# --- apply effects to each squad: casualties as rolled, stress equal for all ---
	i = 0
	while i < n_targets:
		var u_apply: Node = batch_targets[i]
		var cas_i: int = int(casualties_per_target[i])

		#var rf: float = 1.0
		#if "stress_resilience" in u_apply:
			#rf = float(u_apply.stress_resilience)

		#var s_fast_final: float = s_fast * rf
		#var s_slow_final: float = s_slow * rf
		#
		## debug, or rather balance?
		#s_fast_final *= 0.2
		#s_slow_final *= 0.2
		
		#s_fast *= total_rounds
		#s_slow *= total_rounds

		u_apply.call_deferred("_on_incoming_fire_effect", cas_i, s_fast, s_slow, self)
		i += 1


func _get_mean_change_to_hit(chance_to_hit_per_target: Array, n_targets: int) -> float:
	var mean_p_hit: float = 0.0
	var iii: int = 0
	while iii < n_targets:
		mean_p_hit += float(chance_to_hit_per_target[iii])
		iii += 1
	if n_targets > 0:
		mean_p_hit /= float(n_targets)
	else:
		mean_p_hit = 0.0
	return mean_p_hit


func _range_lethality_mult(distance_in_hexes: int, max_range: int) -> float:
	# 1 hex: 1.0; <= max_range: mid; <= 2x max: far; else 0 (but you don’t shoot then).
	if distance_in_hexes <= 1:
		return 1.0
	else:
		if distance_in_hexes <= max_range:
			return lethality_mid_range
		else:
			return lethality_far_range


func cover_multiplier_exp(cover_pts: float) -> float:
	match cover_pts:
		0.0:
			return 1.5
		1.0:
			return 0.5
		2.0:
			return 0.3
		3.0:
			return 0.1
		4.0:
			return 0.01
		5.0:
			return 0.001
		_:
			return 0.001
	## Multiplier goes 1.0 → MIN_HIT_MULT with diminishing returns as cover_pts rises
	#var k: float = log(2.0) / HALF_POINT
	#return MIN_HIT_MULT + (1.0 - MIN_HIT_MULT) * exp(-k * max(cover_pts, 0.0))



func _add_rounds_to_hex(hx: Vector2i, n: int) -> void:
	var cur: int = 0
	if _pending_rounds_by_hex.has(hx):
		cur = int(_pending_rounds_by_hex[hx])
	_pending_rounds_by_hex[hx] = cur + n


func _stress_cover_mult(cover_norm: float, min_floor: float) -> float:
	# cover_norm: 0 = open, 1 = best cover
	cover_norm = clamp(cover_norm, 0.0, 1.0)
	var expose: float = pow(1.0 - cover_norm, stress_cover_gamma)  # 1 at open, 0 near full cover
	var mult: float = min_floor + (1.0 - min_floor) * expose       # lerp to a floor
	return mult

func _count_role(role: int) -> int:
	var c: int = 0
	var i: int = 0
	while i < soldiers.size():
		if soldiers[i].is_alive:
			if int(soldiers[i].role) == role:
				c += 1
		i += 1
	return c

func _indices_with_role(role: int) -> Array[int]:
	var res: Array[int] = []
	var i: int = 0
	while i < soldiers.size():
		if soldiers[i].is_alive:
			if int(soldiers[i].role) == role:
				res.append(i)
		i += 1
	return res

func _on_unit_arrived_at_hex(_new_hex: Vector2i):
	_setup_after_arriving_at_hex()

func _setup_after_arriving_at_hex() -> void:
	# called whenever target_hex changes
	var state_idx: int = stress_controller.state
	var acquire_mult: float = 1.0
	if state_idx >= 0 and state_idx < state_acquire_mults.size():
		acquire_mult = state_acquire_mults[state_idx]

	var i: int = 0
	while i < soldiers.size():
		var s: Soldier = soldiers[i]
		s.tasks.clear()
		if s.is_alive:
			s.setup_weapon_task.done = false
			s.setup_weapon_task.start_time_s = s.weapon.setup_s
		i += 1


func _calc_acquire_delay(s: Soldier) -> float:
	# prefer weapon raise/aim timings if available; else use soldier base
	var base: float = s.base_acquire_s
	if s.weapon != null:
		if s.weapon.riflegrenade_loaded == true:
			var has_raise: bool = s.weapon.raise_riflegrenade_s > 0.0
			var has_aim: bool = s.weapon.aim_riflegrenade_s > 0.0
			if has_raise or has_aim:
				base = s.weapon.raise_riflegrenade_s + s.weapon.aim_riflegrenade_s
		else:
			var has_raise: bool = s.weapon.raise_s > 0.0
			var has_aim: bool = s.weapon.aim_s > 0.0
			if has_raise or has_aim:
				base = s.weapon.raise_s + s.weapon.aim_s
	# add a random bit per target switch
	var jitter: float = randf_range(0.0, s.aim_jitter_s)
	return base + jitter

func _on_fire_weapon(weapon_spec: WeaponSpec, pos: Vector2, is_auto: bool, owner_id: int, position_node: Node2D) -> void:
	if is_auto:
		# start loop when begins firing
		$"../WeaponAudio".start_mg_loop(owner_id, weapon_spec, position_node)
		# each volley still spawns muzzle puffs/visuals and optional short bursts
		$"../WeaponAudio".play_shot(weapon_spec, pos, false)
	else:
		$"../WeaponAudio".play_shot(weapon_spec, pos, false)

func _on_stop_mg_loop(weapon_spec: WeaponSpec, position: Vector2, owner_id: int, position_node: Node2D):
	$"../WeaponAudio".stop_mg_loop(weapon_spec, position, owner_id, position_node)
	
