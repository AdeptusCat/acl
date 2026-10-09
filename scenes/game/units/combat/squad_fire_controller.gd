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

@export var base_accuracy: float = 0.35
@export var volley_size: int = 1               # rounds per burst
@export var seconds_per_volley: float = 1.2
@export var base_seconds_per_volley: float = 1.2
var accuracy_multiplier: float = 1.0

@export var stress_scale: float = 1.0             # global tuning
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
var has_target_hex: bool = false
var has_mortar_target_hex: bool = false
var target_hex: Vector2i:
	set(value):
		target_hex = value
		has_target_hex = true
var mortar_target_hex: Vector2i:
	set(value):
		mortar_target_hex = value
		has_mortar_target_hex = true
#var target_cover: float
var target_unit: Unit
#var target_distance: int
var _pending_rounds_by_hex: Dictionary = {}    # Vector2i -> int

signal fire_shot(weapon: WeaponSpec, shot_target_hex: Vector2i)
signal fire_riflegrenade
signal draw_los_to_target_unit(from_hex: Vector2i, to_hex: Vector2i)
signal shooting(unit: Unit)

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


func set_soldiers_new_target_task(target_distance: int) -> void:
	for s: Soldier in soldiers:
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

func set_mg(machinge_guns : int) -> void:
	for i: int in machinge_guns:
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
	if targetUnit != null and unit.attackState != Unit.AttackState.MANUAL_GROUND and not _can_track_target(targetUnit):
		targetUnit = null
		if unit.attackState == Unit.AttackState.MANUAL_TRACK:
			unit.setAttackState(Unit.AttackState.AUTO)
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
	has_target_hex = is_instance_valid(target_unit)
	has_mortar_target_hex = has_target_hex
	
	var target_cover: int = 0
	var target_distance: int = 0
	
	if is_instance_valid(target_unit):
		target_hex = target_unit.current_hex
		mortar_target_hex = target_hex
		var cover_map: Dictionary = LOSHelper.los_lookup.get(unit.current_hex, {})
		if cover_map and cover_map.has(target_unit.current_hex):
			var data: Dictionary = cover_map[target_unit.current_hex]
			target_cover = data["target_cover"]
		target_distance = LOSHelper.ground_layer.cube_distance(unit.current_cube, target_unit.current_cube)
	
	var draw_los_to: Vector2i = target_hex
	if not has_target_hex:
		draw_los_to = unit.current_hex
	draw_los_to_target_unit.emit(unit.current_hex, draw_los_to)
	
	for s: Soldier in soldiers:
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


func set_target_hex(_target_hex: Vector2i) -> void:
	target_unit = null
	target_hex = _target_hex
	mortar_target_hex = _target_hex


func clear_target() -> void:
	set_target_unit(null)
	has_target_hex = false
	has_mortar_target_hex = false


func _can_track_target(enemy: Unit) -> bool:
	if not is_instance_valid(enemy) or not enemy.alive or enemy.surrendered:
		return false
	var visible_enemies: Array = Globals.unit_visible_enemies.get(unit, [])
	if not visible_enemies.has(enemy):
		return false
	if enemy.current_hex == unit.current_hex:
		return true
	# Detection is published on a timer; check geometry at the current hex too.
	var current_los: Dictionary = LOSHelper.los_lookup.get(unit.current_hex, {})
	return current_los.has(enemy.current_hex)


func _refresh_tracked_target() -> bool:
	if not _can_track_target(target_unit):
		if unit.attackState == Unit.AttackState.MANUAL_TRACK:
			unit.setAttackState(Unit.AttackState.AUTO)
		if target_unit != null or has_target_hex or has_mortar_target_hex:
			clear_target()
		return false
	if not has_target_hex or target_hex != target_unit.current_hex:
		target_hex = target_unit.current_hex
	mortar_target_hex = target_hex
	return true




func _process(delta: float) -> void:
	if not unit.alive:
		return
	if unit.ai_support_only:
		if target_unit != null or has_target_hex or has_mortar_target_hex:
			clear_target()
		update_fire_recent(delta)
		return
	_now_s += delta
	_accum_window_s += delta
	
	var visible_enemies1: Array = Globals.unit_visible_enemies.get(unit, [])
	if not visible_enemies1.is_empty(): # and target_hex == Vector2i.ZERO
		if unit.is_moving or not unit.alive or unit.broken or unit.surrendered:
			return
		else:
			#if unit.team == Globals.team_player:
			#unit.combat.handle_auto_fire(delta, unit, unit_visible_enemies, unit.current_hex, unit.range, unit.fire_rate, unit.firepower)
			if unit.attackState == Unit.AttackState.AUTO:
				handle_auto_fire(delta, unit, unit.current_hex, unit.weapon_range, unit.fire_rate, unit.firepower)
	
	if unit.attackState != Unit.AttackState.MANUAL_GROUND:
		_refresh_tracked_target()
	update_fire_recent(delta)
	_update_state_multipliers()
	_tick_soldiers(delta)
	


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
	SquadTargetSelector.handle_auto_fire(self, delta, _shooter, current_hex, _range, fire_rate, _firepower)


func _score_enemy_for_target(shooter_unit: Unit, enemy: Unit, current_hex: Vector2i) -> Dictionary:
	return SquadTargetSelector.score_enemy_for_target(self, shooter_unit, enemy, current_hex)


func fire_mortar(map_hex: Vector2i) -> void:
	set_target_hex(map_hex)
	aim_delay()
	


func _tick_soldiers(delta: float) -> void:
	var target_cover: int = 0
	var target_distance: int = 0
	
	if is_instance_valid(target_unit):
		var cover_map: Dictionary = LOSHelper.los_lookup.get(unit.current_hex, {})
		if cover_map and cover_map.has(target_unit.current_hex):
			var data: Dictionary = cover_map[target_unit.current_hex]
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
		if not unit.alive:
			return
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
		if not unit.alive:
			return
		var s2: Soldier = soldiers[i]
		if s2.is_alive:
			if s2.role != RankGrades.Role.GUNNER:
				rounds_emitted += await _try_fire_soldier(delta, s2, false, 0, 0, target_distance, target_cover)
				if rounds_emitted >= max_shots_per_tick:
					return
		i += 1

func _try_fire_soldier(delta: float, s: Soldier, is_crew_served: bool, crew_available: int, support_crew_available: int, target_distance: int, target_cover: int) -> int:
	if not unit.alive or unit.ai_support_only:
		return 0
	var state_idx: int = stress_controller.state
	var delta_multiplyer: float = state_acquire_mults[state_idx]
	var delta_mod: float = delta * delta_multiplyer 
	if unit.attackState != Unit.AttackState.MANUAL_GROUND and not _refresh_tracked_target():
		return 0
	var _target_hex: Vector2i = target_hex
	if s.weapon.family == WeaponSpec.Family.MORTAR:
		_target_hex = mortar_target_hex
	
	if unit.attackState == Unit.AttackState.MANUAL_GROUND:
		pass
	
	if unit.in_close_combat:
		return 0
	if unit.is_moving:
		return 0
	if not s.is_weapon_setup_done(delta_mod):
		return 0
	if not s.is_weapon_reload_done(delta_mod):
		return 0
	if not s.is_acquiring_target_done(delta_mod):
		return 0
	
	if Debug.dont_fire_wepaons:
		return 0
	
	if s.weapon.family == WeaponSpec.Family.MORTAR:
		if not has_mortar_target_hex:
			return 0
	elif not has_target_hex:
		return 0
	
	var cover_map: Dictionary = LOSHelper.los_lookup.get(unit.current_hex, {})
	if cover_map and cover_map.has(_target_hex):
		var data: Dictionary = cover_map[_target_hex]
		target_cover = data["target_cover"]
	target_distance = LOSHelper.ground_layer.cube_distance(unit.current_cube, LOSHelper.ground_layer.map_to_cube(_target_hex))
	
	if s.weapon.ammunition <= 0:
		return 0
	
	if target_distance > s.weapon.range_hexes:
		#set_target_unit(null) # this should only happen if none have range
		return 0
	
	
	var batch_targets: Array[Unit] = []
	var visible_enemies: Array = Globals.unit_visible_enemies.get(get_parent(), [])
	
	# without this check an enemy will be attacked even though the unit is shooting the ground at another hex
	if not unit.attackState == Unit.AttackState.MANUAL_GROUND: 
		for u: Unit in visible_enemies:
			if u.current_hex == _target_hex:
				if is_instance_valid(u):
					if u.alive:
						if not u.surrendered:
							#if u.current_hex == _target_hex:
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
	_add_rounds_to_hex(_target_hex, shots)
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
		fire_shots(s, shots, s.weapon.rpm, auto_fire, _target_hex)
	
	
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
	
	var dist: float = unit.position.distance_to(LOSHelper.ground_layer.map_to_local(_target_hex))
	
	var life: float = dist / s.weapon.projectile_speed      # seconds
	if s.weapon.can_fire_riflegrenades:
		life = dist / s.weapon.riflegrenade_projectile_speed
	await get_tree().create_timer(life).timeout
	
	if unit.alive:
		shooting.emit(unit)
	# handle result on enemy unit
	fire_at(shots, s.weapon, riflegrenade, _target_hex, target_distance, target_cover, batch_targets)
	return shots


func compute_support_efficiency(support_crew_available: int, support_crew_optimal: int) -> float:
	return SquadFireMath.compute_support_efficiency(support_crew_available, support_crew_optimal)


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


func aim_delay() -> void:
	var state_idx: int = stress_controller.state
	var acquire_mult: float = 1.0
	if state_idx >= 0 and state_idx < state_acquire_mults.size():
		acquire_mult = state_acquire_mults[state_idx]
	for s: Soldier in soldiers:
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


func fire_shots(s: Soldier, shots: int, rpm: float, auto_fire: bool, shot_target_hex: Vector2i) -> void:
	var interval: float = 60.0 / rpm
	for shot: int in range(shots):
		if not unit.alive:
			return
		fire_shot.emit(s.weapon, shot_target_hex)
		if get_tree(): # mighit be already freed or removed as child
			await get_tree().create_timer(interval).timeout
	if auto_fire and unit.alive:
		_on_stop_mg_loop(s.weapon, unit.position, s.id, unit)


func fire_riflegrenades(s: Soldier) -> void:
	fire_riflegrenade.emit(s.weapon)

func add_fire_impulse(rounds_fired: int, max_rounds_ref: int) -> void:
	var x: float = float(rounds_fired) / float(max_rounds_ref)
	if x > 1.0:
		x = 1.0
	fire_recent += x
	if fire_recent > 1.0:
		fire_recent = 1.0

func fire_at(total_rounds: int, weapon: WeaponSpec, riflegrenade: bool, _target_hex: Vector2i, target_distance: int, target_cover: int, batch_targets: Array[Unit]) -> void:
	SquadHitResolver.fire_at(self, total_rounds, weapon, riflegrenade, _target_hex, target_distance, target_cover, batch_targets)


func _get_mean_change_to_hit(chance_to_hit_per_target: Array, n_targets: int) -> float:
	return SquadFireMath.get_mean_change_to_hit(chance_to_hit_per_target, n_targets)


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
	return SquadFireMath.cover_multiplier_exp(cover_pts)


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

func _on_unit_arrived_at_hex(_new_hex: Vector2i) -> void:
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

func _on_stop_mg_loop(weapon_spec: WeaponSpec, position: Vector2, owner_id: int, position_node: Node2D) -> void:
	$"../WeaponAudio".stop_mg_loop(weapon_spec, position, owner_id, position_node)
	
