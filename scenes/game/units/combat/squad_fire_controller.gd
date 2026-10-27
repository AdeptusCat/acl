# SquadFireController.gd
extends Node
class_name SquadFireController

const PROJECTILE_TRACER: Script = preload("res://scenes/game/effects/tracer.gd")
const IMPACT_PATTERN: Script = preload("res://scenes/game/effects/burst_impact_pattern.gd")





# Wiring
@export var unit: Unit
@export var stress_controller: StressController

# Timing
@export var burst_window_s: float = 0.10      # batch rounds within this window per hex
@export var max_shots_per_tick: int = 128

## State influence (from your STATES table)
#@export var state_acc_mults: PackedFloat32Array = PackedFloat32Array([1.0, 0.9, 0.5, 0.0, 0.0])
#@export var state_rof_mults: PackedFloat32Array = PackedFloat32Array([1.0, 0.85, 0.35, 0.0, 0.0])

# Deployment work speed. Reaction/reload/cadence use individual combat states.
@export var state_acquire_mults: PackedFloat32Array = PackedFloat32Array([1.0, 0.8, 0.5, 0.0, 0.0])

# Panic and combat ineffectiveness suspend deployment.

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
@export var stress_crossfire_bonus: float = 0.15    # maximum extra stress from separated incoming bearings
@export var stress_surprise_bonus: float = 0.5      # maximum extra fast shock from outside attention
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

var _bursts: Dictionary[Soldier, Dictionary] = {}
var _burst_audio_tokens: Dictionary[int, int] = {}
var _next_burst_audio_token: int = 0
var _last_visible: Array[Unit] = []

var fire_recent: float = 0.0 # 0..1 shows that they were shooting

const FIRE_EFFECT_WINDOW_MS: int = 4000
var _fire_effect_target: WeakRef
var _fire_effect_at_ms: int = -4000

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
var mission_support_fire: bool = false
var fire_support_mission: FireSupportMission
var fire_support_hold: bool = false
#var target_distance: int
var _pending_rounds_by_hex: Dictionary = {}    # Vector2i -> int

signal fire_shot(weapon: WeaponSpec, shot_target_hex: Vector2i, shot_origin: Vector2, shot_impact: Vector2)
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
	for soldier: Soldier in soldiers:
		if _uses_personal_defense(soldier) or soldier.role in [RankGrades.Role.LOADER, RankGrades.Role.ASSISTANT]:
			continue
		if soldier.weapon.can_fire_riflegrenades and target_distance <= soldier.weapon.riflegrenade_range:
			soldier.start_reload(true)
		_begin_soldier_engagement(soldier, null, target_hex)


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
	for soldier: Soldier in soldiers:
		if _burst_audio_tokens.has(soldier.id):
			_stop_burst_audio(soldier.weapon, soldier.id, _burst_audio_tokens[soldier.id], 0.0)
	for soldier: Soldier in _bursts:
		soldier.burst_active = false
	_bursts.clear()
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
		if _uses_personal_defense(s) or s.role in [RankGrades.Role.LOADER, RankGrades.Role.ASSISTANT]:
			continue
		if not is_instance_valid(target_unit):
			s.lose_contact()
			continue
		if s.aquire_target_task.target_id != target_unit or not s.has_engagement:
			if s.weapon.can_fire_riflegrenades and target_distance <= s.weapon.riflegrenade_range:
				s.start_reload(true)
			_begin_soldier_engagement(s, target_unit, target_unit.current_hex)


func set_target_hex(_target_hex: Vector2i) -> void:
	fire_support_hold = false
	target_unit = null
	target_hex = _target_hex
	mortar_target_hex = _target_hex


func clear_target() -> void:
	set_target_unit(null)
	has_target_hex = false
	has_mortar_target_hex = false


func _can_track_target(enemy: Unit) -> bool:
	if not is_instance_valid(enemy) or not enemy.is_active() or enemy.surrendered:
		return false
	if mission_support_fire and not TacticalPositionExecutor.support_hex_is_clear(unit, enemy.current_hex):
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
	if not unit.is_active():
		return
	_now_s += delta
	update_fire_recent(delta)
	_update_state_multipliers()
	_tick_weapon_setup(delta)
	if unit.ai_support_only:
		_tick_automatic_fire(delta)
		clear_target()
		return
	var visible: Array = Globals.unit_visible_enemies.get(unit, [])
	# A new contact wakes selection immediately; reconsideration keeps its normal cadence.
	for enemy: Unit in visible:
		if not _last_visible.has(enemy):
			fire_timer = 0.0
			break
	_last_visible.assign(visible)
	if unit.attackState == Unit.AttackState.AUTO and not unit.is_moving and not unit.broken and not unit.surrendered:
		handle_auto_fire(delta, unit, unit.current_hex, unit.weapon_range, unit.fire_rate, unit.firepower)
	if unit.attackState != Unit.AttackState.MANUAL_GROUND:
		_refresh_tracked_target()
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
	


func _tick_weapon_setup(delta: float) -> void:
	for soldier: Soldier in soldiers:
		if not soldier.is_alive:
			continue
		soldier.update_behavior(delta, stress_controller.state, stress_controller.under_fire)
		if unit.is_moving or unit.in_close_combat:
			soldier.lower_weapon()
			continue
		if unit.broken or unit.surrendered or soldier.behavior != Soldier.Behavior.ENGAGING:
			continue
		if not soldier.weapon_raised:
			soldier.raise_remaining_s = maxf(0.0, soldier.raise_remaining_s - delta * _handling_speed())
			soldier.weapon_raised = soldier.raise_remaining_s <= 0.0
		if not soldier.is_weapon_setup_done(delta * state_acquire_mults[stress_controller.state]):
			soldier.weapon_state = Soldier.WeaponState.SETTING_UP


func _tick_soldiers(delta: float) -> void:
	# One synchronous pass. Airborne rounds never suspend this scheduler.
	_tick_automatic_fire(delta)
	for soldier: Soldier in soldiers:
		if not soldier.is_alive:
			if _bursts.has(soldier):
				_finish_burst(soldier, _bursts[soldier])
			continue
		var crew_served: bool = soldier.role == RankGrades.Role.GUNNER
		var loaders: int = 0
		var assistants: int = 0
		if crew_served:
			loaders = _count_role(RankGrades.Role.LOADER)
			assistants = _count_role(RankGrades.Role.ASSISTANT)
			if soldier.weapon.uses_sustained_fire():
				loaders = _available_automatic_crew(RankGrades.Role.LOADER)
				assistants = _available_automatic_crew(RankGrades.Role.ASSISTANT)
		_try_fire_soldier(delta, soldier, crew_served, loaders, assistants, 0, 0)


func _tick_automatic_fire(delta: float) -> void:
	var advanced: Dictionary[WeaponSpec, bool] = {}
	# Include dropped guns; a replacement receives their existing barrels and heat.
	for soldier: Soldier in soldiers + casualties:
		soldier.barrel_change_assisting = false
		soldier.barrel_change_worked = false
		if soldier.weapon.uses_sustained_fire() and not advanced.has(soldier.weapon):
			soldier.weapon.automatic_fire.advance(delta, soldier.weapon)
			advanced[soldier.weapon] = true
	if unit.is_moving or unit.in_close_combat or unit.broken or unit.surrendered or unit.ai_support_only:
		return
	for gunner: Soldier in soldiers:
		if not gunner.is_alive or gunner.behavior != Soldier.Behavior.ENGAGING or gunner.burst_active:
			continue
		if not gunner.weapon.uses_sustained_fire() or not gunner.setup_weapon_task.done or gunner.weapon.ammunition <= 0:
			continue
		var state: AutomaticFireState = gunner.weapon.automatic_fire
		var swap_delta: float = delta
		if state.swap_barrel < 0:
			if state.begin_barrel_change(gunner.weapon):
				# Work starts on the next update, after the swap has actually been selected.
				gunner.weapon_state = Soldier.WeaponState.CHANGING_BARREL
				swap_delta = 0.0
			else:
				continue
		var helper: Soldier = _barrel_change_helper()
		# Do not also spend this update's handling time on a reload or firing aim.
		gunner.barrel_change_worked = true
		var speed: float = _handling_speed()
		if helper != null:
			helper.barrel_change_assisting = true
			helper.weapon_state = Soldier.WeaponState.CHANGING_BARREL
		else:
			speed /= maxf(gunner.weapon.undercrew_penalty_mult, 1.0)
		speed *= compute_support_efficiency(_available_automatic_crew(RankGrades.Role.ASSISTANT), gunner.weapon.support_crew_optimal)
		if state.advance_barrel_change(swap_delta * speed, gunner.weapon):
			gunner.reaim_remaining_s = maxf(gunner.reaim_remaining_s, gunner.weapon.reaim_s)


func _barrel_change_helper() -> Soldier:
	for role: RankGrades.Role in [RankGrades.Role.LOADER, RankGrades.Role.ASSISTANT]:
		for soldier: Soldier in soldiers:
			if soldier.role == role and soldier.is_alive and soldier.behavior == Soldier.Behavior.ENGAGING and not soldier.barrel_change_assisting and not soldier.burst_active and soldier.reload_task.done:
				return soldier
	return null


func _available_automatic_crew(role: RankGrades.Role) -> int:
	var count: int = 0
	for soldier: Soldier in soldiers:
		if soldier.role == role and soldier.is_alive and soldier.behavior == Soldier.Behavior.ENGAGING:
			count += 1
	return count


func _rapid_fire_opportunity(enemy: Unit, distance: int, cell: Vector2i) -> bool:
	if not is_instance_valid(enemy) or not _can_track_target(enemy):
		return false
	if TacticalPositionExecutor.is_sufficiently_suppressed(enemy):
		return false
	if distance <= 2:
		return true
	var lane: Dictionary = LOSHelper.los_lookup.get(unit.current_hex, {}).get(cell, {})
	var concealment: int = int(lane.get("target_concealment", -1))
	if concealment < 0:
		# Older LOS caches omit concealment; bullet cover is not a substitute.
		concealment = LOSHelper.get_target_concealment(enemy.global_position)
	return enemy.is_moving and concealment == 0 and int(lane.get("hindrance", 0)) == 0


func _uses_personal_defense(soldier: Soldier) -> bool:
	return unit.squad_type in [Globals.SquadType.MG, Globals.SquadType.MORTAR, Globals.SquadType.ANTITANK] and soldier.role != RankGrades.Role.GUNNER


func _has_active_support_weapon() -> bool:
	for soldier: Soldier in soldiers:
		if soldier.is_alive and soldier.role == RankGrades.Role.GUNNER and soldier.weapon != null and soldier.weapon.ammunition > 0:
			return true
	return false


func _personal_defense_target(soldier: Soldier) -> Unit:
	var selected: Unit = null
	for enemy: Unit in Globals.unit_visible_enemies.get(unit, []):
		if not _can_track_target(enemy) or enemy.team == unit.team:
			continue
		if mission_support_fire and not _has_safe_support_target(enemy.current_hex):
			continue
		if LOSHelper.ground_layer.cube_distance(unit.current_cube, LOSHelper.ground_layer.map_to_cube(enemy.current_hex)) != 1:
			continue
		if enemy == soldier.aquire_target_task.target_id:
			return enemy
		if selected == null:
			selected = enemy
	return selected


func _try_fire_soldier(delta: float, s: Soldier, is_crew_served: bool, crew_available: int, support_crew_available: int, target_distance: int, target_cover: int) -> int:
	if _bursts.has(s):
		return _advance_burst(s, delta)
	if not s.is_alive or not unit.is_active() or unit.ai_support_only or unit.surrendered or unit.broken:
		return 0
	if s.barrel_change_assisting or s.barrel_change_worked or s.weapon.automatic_fire.swap_barrel >= 0:
		s.weapon_state = Soldier.WeaponState.CHANGING_BARREL
		return 0
	var personal_defense: bool = _uses_personal_defense(s)
	if fire_support_mission != null and personal_defense:
		return 0
	if s.weapon.family == WeaponSpec.Family.MORTAR:
		if fire_support_hold:
			return 0
	var personal_ground_fire: bool = (
		personal_defense
		and unit.attackState == Unit.AttackState.MANUAL_GROUND
		and has_target_hex
		and LOSHelper.los_lookup.get(unit.current_hex, {}).has(target_hex)
		and LOSHelper.ground_layer.cube_distance(unit.current_cube, LOSHelper.ground_layer.map_to_cube(target_hex)) == 1
	)
	var shot_target: Unit = target_unit
	var personal_target_hex: Vector2i = target_hex
	if personal_defense:
		if s.role == RankGrades.Role.LOADER and _has_active_support_weapon():
			return 0
		if personal_ground_fire:
			if unit.attack_ground_rounds_budget <= 0:
				return 0
			# The player's ordered hex supplies the target without inventing a contact.
			shot_target = null
		else:
			shot_target = _personal_defense_target(s)
			if shot_target == null:
				return 0
			personal_target_hex = shot_target.current_hex
		if s.aquire_target_task.target_id != shot_target or (personal_ground_fire and s.last_target_hex != personal_target_hex):
			_begin_soldier_engagement(s, shot_target, personal_target_hex)
		s.last_target_hex = personal_target_hex
	elif mission_support_fire and not _has_safe_support_target(target_hex):
		clear_target()
		unit.setAttackState(Unit.AttackState.AUTO)
		return 0
	var handling_speed: float = _handling_speed()
	if is_crew_served:
		# Apply crew speed to remaining work so losses and replacements affect
		# reload and firing preparation already in progress, without restarting them.
		var crew_penalty: float = 1.0
		if crew_available < s.weapon.crew_required - 1:
			crew_penalty = maxf(1.0, s.weapon.undercrew_penalty_mult)
		handling_speed *= compute_support_efficiency(support_crew_available, s.weapon.support_crew_optimal) / crew_penalty
	if not personal_defense and unit.attackState != Unit.AttackState.MANUAL_GROUND and not _refresh_tracked_target():
		s.advance_handling(delta, handling_speed)
		return 0
	var _target_hex: Vector2i = target_hex
	if personal_defense:
		_target_hex = personal_target_hex
	elif s.weapon.family == WeaponSpec.Family.MORTAR:
		_target_hex = mortar_target_hex
		if fire_support_mission != null:
			_target_hex = fire_support_mission.next_target()
	
	if unit.attackState == Unit.AttackState.MANUAL_GROUND:
		pass
	
	if unit.in_close_combat:
		return 0
	if unit.is_moving:
		return 0
	# The stationary update owns this countdown; firing only checks readiness.
	var handling_ready: bool = s.advance_handling(delta, handling_speed)
	if not s.is_weapon_setup_done(0.0):
		s.weapon_state = Soldier.WeaponState.SETTING_UP
		return 0
	if not handling_ready:
		return 0
	# Crew preparation runs during the scheduled interval, rather than after it.
	if fire_support_mission != null and not fire_support_mission.gun_ready(s):
		return 0
	
	if Debug.dont_fire_wepaons:
		return 0
	
	if not personal_defense:
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
	var visible_enemies: Array = Globals.unit_visible_enemies.get(unit, [])
	
	# without this check an enemy will be attacked even though the unit is shooting the ground at another hex
	if personal_defense or unit.attackState != Unit.AttackState.MANUAL_GROUND:
		for u: Unit in visible_enemies:
			if u.current_hex == _target_hex:
				if is_instance_valid(u):
					if u.is_active():
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
	
	
	# Outside dedicated weapon squads, helpers retain their existing crew duties.
	if not personal_defense and (s.role == RankGrades.Role.LOADER or s.role == RankGrades.Role.ASSISTANT):
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
	
	

	if s.weapon.riflegrenade_loaded == true and target_distance > s.weapon.riflegrenade_range:
		s.rounds_in_mag = 0

	if s.rounds_in_mag <= 0:
		s.start_reload(s.weapon.can_fire_riflegrenades and target_distance <= s.weapon.riflegrenade_range)
		return 0
	var rapid: bool = false
	if s.weapon.uses_sustained_fire():
		var state: AutomaticFireState = s.weapon.automatic_fire
		rapid = state.select_rapid(s.weapon, _rapid_fire_opportunity(shot_target, target_distance, _target_hex))
		if state.heat_locked:
			s.weapon_state = Soldier.WeaponState.COOLING
			return 0
		if state.pause_remaining_s > 0.0:
			s.weapon_state = Soldier.WeaponState.OBSERVING
			return 0
	var shots: int
	if s.weapon.uses_sustained_fire():
		shots = mini(s.automatic_burst_size(rapid), s.weapon.ammunition)
	else:
		shots = mini(determine_burst_size(s.weapon, s.rounds_in_mag), s.weapon.ammunition)
	if fire_support_mission != null:
		shots = mini(shots, fire_support_mission.remaining)
	var ground_fire: bool = unit.attackState == Unit.AttackState.MANUAL_GROUND and (not personal_defense or personal_ground_fire)
	if fire_support_mission != null:
		ground_fire = false
	if ground_fire:
		shots = mini(shots, unit.attack_ground_rounds_budget)
	return _start_burst(s, shots, _target_hex, shot_target, ground_fire, target_distance, target_cover, batch_targets)


func _begin_soldier_engagement(soldier: Soldier, enemy: Unit, cell: Vector2i) -> void:
	var distance: int = LOSHelper.ground_layer.cube_distance(unit.current_cube, LOSHelper.ground_layer.map_to_cube(cell))
	var alignment: float = 1.0
	var focus: Vector2 = Vector2.ZERO
	if unit.tactical_state != null:
		focus = unit.tactical_state.focus_direction
	var track: EnemyTrack = Globals.unit_enemy_tracks.get(unit, {}).get(enemy, null) as EnemyTrack
	if track != null and unit._now() - track.acquired_at_s <= 1.0:
		focus = track.reaction_focus_direction
	if not focus.is_zero_approx():
		var direction: Vector2 = unit.global_position.direction_to(LOSHelper.ground_layer.to_global(LOSHelper.ground_layer.map_to_local(cell)))
		var angle: float = absf(focus.angle_to(direction))
		alignment = 1.0 - smoothstep(0.0, PI, angle)
	soldier.begin_engagement(enemy, cell, distance, alignment)


func _handling_speed() -> float:
	match stress_controller.state:
		STATES.MoraleState.CAUTIOUS:
			return 0.95
		STATES.MoraleState.PINNED:
			return 0.9
		STATES.MoraleState.PANIC, STATES.MoraleState.COMBAT_INEFFECTIVE:
			return 0.0
	return 1.0


func _start_burst(soldier: Soldier, shots: int, cell: Vector2i, enemy: Unit, ground_fire: bool, distance: int, cover: int, targets: Array[Unit]) -> int:
	if shots <= 0:
		return 0
	var context: Dictionary = {"remaining": shots, "cell": cell, "enemy": enemy,
		"ground": ground_fire, "distance": distance, "cover": cover, "targets": targets.duplicate(),
		"until_next": 0.0, "mission": fire_support_mission, "audio_started": false,
		"emitted": 0, "rapid": soldier.weapon.automatic_fire.rapid_active,
		"origin": unit.global_position + PROJECTILE_TRACER.sample_spawn_offset()}
	_bursts[soldier] = context
	soldier.burst_active = true
	soldier.weapon_state = Soldier.WeaponState.FIRING
	return _advance_burst(soldier, 0.0)


func _burst_can_continue(soldier: Soldier, context: Dictionary) -> bool:
	if not soldier.is_alive or not unit.is_active() or unit.surrendered or unit.broken or unit.is_moving or unit.in_close_combat or unit.ai_support_only:
		return false
	if soldier.behavior != Soldier.Behavior.ENGAGING or Debug.dont_fire_wepaons:
		return false
	if soldier.barrel_change_assisting or (soldier.weapon.uses_sustained_fire() and (soldier.weapon.automatic_fire.heat_locked or soldier.weapon.automatic_fire.swap_barrel >= 0)):
		return false
	if mission_support_fire and not _has_safe_support_target(context["cell"]):
		return false
	if context["mission"] != null:
		var mission: FireSupportMission = context["mission"] as FireSupportMission
		return fire_support_mission == mission and mission.active and mission.remaining > 0 and not fire_support_hold
	if context["ground"]:
		return unit.attackState == Unit.AttackState.MANUAL_GROUND and target_hex == context["cell"] and unit.attack_ground_rounds_budget > 0
	if not is_instance_valid(context["enemy"]):
		return false
	var enemy: Unit = context["enemy"] as Unit
	if not _can_track_target(enemy) or enemy.current_hex != context["cell"]:
		return false
	if not _uses_personal_defense(soldier) and target_unit != enemy:
		return false
	for occupant: Unit in LOSHelper.find_units_at(context["cell"]):
		if occupant.team == unit.team and not occupant.surrendered:
			return false
	return true


func _advance_burst(soldier: Soldier, delta: float) -> int:
	if not _bursts.has(soldier):
		return 0
	var context: Dictionary = _bursts[soldier]
	if not _burst_can_continue(soldier, context):
		_finish_burst(soldier, context)
		if not context["ground"] and not _uses_personal_defense(soldier):
			_refresh_tracked_target()
		return 0
	context["until_next"] -= maxf(delta, 0.0)
	var emitted: int = 0
	while float(context["until_next"]) <= 0.000001 and emitted < max_shots_per_tick:
		if soldier.rounds_in_mag <= 0 or soldier.weapon.ammunition <= 0 or not _burst_can_continue(soldier, context):
			_finish_burst(soldier, context)
			break
		_emit_round(soldier, context)
		emitted += 1
		context["remaining"] -= 1
		context["until_next"] += 60.0 / maxf(soldier.weapon.rpm, 1.0)
		if int(context["remaining"]) <= 0:
			_finish_burst(soldier, context)
			break
	return emitted


func _finish_burst(soldier: Soldier, context: Dictionary) -> void:
	_bursts.erase(soldier)
	soldier.finish_burst()
	if soldier.weapon.uses_sustained_fire() and int(context["emitted"]) > 0:
		var suppressed: bool = false
		if is_instance_valid(context["enemy"]):
			suppressed = TacticalPositionExecutor.is_sufficiently_suppressed(context["enemy"] as Unit)
		soldier.finish_automatic_burst(bool(context["rapid"]), suppressed)
	if soldier.is_alive and soldier.rounds_in_mag <= 0:
		var grenade: bool = soldier.weapon.can_fire_riflegrenades and int(context["distance"]) <= soldier.weapon.riflegrenade_range
		soldier.start_reload(grenade)
	if bool(context["audio_started"]):
		var delay: float = 0.0
		if int(context["remaining"]) <= 0:
			# Let the last automatic round sound for its firing interval before the tail.
			delay = maxf(float(context["until_next"]), 0.0)
		_stop_burst_audio(soldier.weapon, soldier.id, int(context["audio_token"]), delay)


func _stop_burst_audio(weapon: WeaponSpec, owner_id: int, token: int, delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	# An old burst's delayed tail must not stop a newer burst from the same soldier.
	if _burst_audio_tokens.get(owner_id, -1) != token:
		return
	_burst_audio_tokens.erase(owner_id)
	_on_stop_mg_loop(weapon, unit.position, owner_id, unit)


func _emit_round(soldier: Soldier, context: Dictionary) -> void:
	var cell: Vector2i = context["cell"]
	var origin: Vector2 = context["origin"]
	var grenade: bool = soldier.weapon.riflegrenade_loaded
	soldier.rounds_in_mag -= 1
	soldier.weapon.ammunition -= 1
	context["emitted"] += 1
	if soldier.weapon.uses_sustained_fire():
		soldier.weapon.automatic_fire.record_round(soldier.weapon)
	if context["ground"]:
		unit.attack_ground_rounds_budget -= 1
	var mission: FireSupportMission = context["mission"] as FireSupportMission
	if mission != null:
		mission.commit_gun(soldier, 1)
	_add_rounds_to_hex(cell, 1)
	add_fire_impulse(1, 10)
	shooting.emit(unit)
	var automatic_audio: bool = soldier.weapon.fire_mode == WeaponSpec.FireMode.BURST and not grenade
	if automatic_audio:
		if not bool(context["audio_started"]):
			_next_burst_audio_token += 1
			context["audio_started"] = true
			context["audio_token"] = _next_burst_audio_token
			_burst_audio_tokens[soldier.id] = _next_burst_audio_token
			_on_fire_weapon(soldier.weapon, unit.position, true, soldier.id, unit)
	else:
		_on_fire_weapon(soldier.weapon, unit.position, false, soldier.id, unit)
	if grenade:
		fire_riflegrenades(soldier)
		soldier.weapon.riflegrenade_loaded = false
	else:
		# The visual API is kept independent of preparation and projectile impacts.
		var impacts: PackedVector2Array = IMPACT_PATTERN.create(LOSHelper.ground_layer, cell, origin, 1)
		fire_shot.emit(soldier.weapon, cell, origin, impacts[0])
	var speed: float = float(soldier.weapon.projectile_speed)
	if grenade:
		speed = float(soldier.weapon.riflegrenade_projectile_speed)
	var life: float = origin.distance_to(LOSHelper.ground_layer.to_global(LOSHelper.ground_layer.map_to_local(cell))) / maxf(speed, 1.0)
	if is_instance_valid(Debug.engagement_recorder):
		Debug.engagement_recorder.record_shot(self, soldier, 1, cell, context["distance"], context["cover"], origin, life, grenade)
	var targets: Array[Unit] = []
	targets.assign(context["targets"])
	_resolve_airborne_round(soldier.weapon, grenade, cell, context["distance"], context["cover"], targets, origin, life)


func _resolve_airborne_round(weapon: WeaponSpec, grenade: bool, cell: Vector2i, distance: int, cover: int, targets: Array[Unit], origin: Vector2, life: float) -> void:
	await get_tree().create_timer(life).timeout
	# A launched round lands even if its shooter dies or takes cover.
	fire_at(1, weapon, grenade, cell, distance, cover, targets, origin)


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
	for soldier: Soldier in soldiers:
		if _uses_personal_defense(soldier) or soldier.role in [RankGrades.Role.LOADER, RankGrades.Role.ASSISTANT]:
			continue
		_begin_soldier_engagement(soldier, target_unit, target_hex)


func fire_shots(s: Soldier, shots: int, rpm: float, auto_fire: bool, shot_target_hex: Vector2i) -> void:
	var interval: float = 60.0 / rpm
	var support_burst: bool = mission_support_fire
	# Capture once per gun burst; overlapping bursts keep separate local origins.
	var shot_origin: Vector2 = unit.global_position + PROJECTILE_TRACER.sample_spawn_offset()
	var impacts: PackedVector2Array = IMPACT_PATTERN.create(LOSHelper.ground_layer, shot_target_hex, shot_origin, shots)
	for shot: int in range(shots):
		if not unit.is_active() or not s.is_alive or unit.surrendered or unit.broken or s.behavior != Soldier.Behavior.ENGAGING:
			return
		if support_burst and not _has_safe_support_target(shot_target_hex):
			return
		var impact: Vector2 = Vector2.INF
		if shot < impacts.size():
			impact = impacts[shot]
		fire_shot.emit(s.weapon, shot_target_hex, shot_origin, impact)
		if get_tree(): # mighit be already freed or removed as child
			await get_tree().create_timer(interval).timeout
	if auto_fire and unit.is_active():
		_on_stop_mg_loop(s.weapon, unit.position, s.id, unit)


func _has_safe_support_target(cell: Vector2i) -> bool:
	if not TacticalPositionExecutor.support_hex_is_clear(unit, cell):
		return false
	for enemy: Unit in Globals.unit_visible_enemies.get(unit, []):
		if TacticalPositionExecutor.is_active_defender(enemy) and enemy.team != unit.team and enemy.current_hex == cell:
			return true
	return false


func fire_riflegrenades(s: Soldier) -> void:
	fire_riflegrenade.emit(s.weapon)

func add_fire_impulse(rounds_fired: int, max_rounds_ref: int) -> void:
	var x: float = float(rounds_fired) / float(max_rounds_ref)
	if x > 1.0:
		x = 1.0
	fire_recent += x
	if fire_recent > 1.0:
		fire_recent = 1.0

func record_fire_effect(target: Unit) -> void:
	# Impacts animate the estimate; the rating comes from the hover preview's firepower.
	if not is_instance_valid(unit) or not is_instance_valid(target):
		return
	if target != target_unit or target.team == unit.team or not target.is_visible_in_tree() or not _can_track_target(target):
		return
	_fire_effect_target = weakref(target)
	_fire_effect_at_ms = Time.get_ticks_msec()


func get_fire_effect() -> Dictionary:
	var target: Unit = target_unit
	if not is_instance_valid(unit) or not unit.is_active() or unit.broken or unit.surrendered or unit.in_close_combat or unit.is_moving:
		return {}
	if unit.team != Globals.team_player and not Debug.enemy_selectable:
		return {}
	if unit.attackState == Unit.AttackState.MANUAL_GROUND or not is_instance_valid(target) or target.team == unit.team or not target.is_visible_in_tree() or not _can_track_target(target):
		return {}
	if not is_instance_valid(LOSHelper.ground_layer):
		return {}
	var feedback: Dictionary = MatchInteractionHandler.unit_target_feedback(unit, target.current_hex)
	var power: float = float(feedback["firepower"])
	var style: Dictionary = SquadFireMath.firepower_feedback(power)
	var age: int = Time.get_ticks_msec() - _fire_effect_at_ms
	var pulse: float = 0.0
	if _fire_effect_target != null and _fire_effect_target.get_ref() == target and age < FIRE_EFFECT_WINDOW_MS:
		pulse = float(style["strength"]) * pow(clampf(1.0 - float(age) / 900.0, 0.0, 1.0), 2.0)
	return {"text": "%s · %.2f" % [style["rating"], power], "color": style["color"], "strength": style["strength"], "firepower": power, "pulse": pulse}


func fire_at(total_rounds: int, weapon: WeaponSpec, riflegrenade: bool, _target_hex: Vector2i, target_distance: int, target_cover: int, batch_targets: Array[Unit], shot_origin: Vector2 = Vector2.INF) -> void:
	SquadHitResolver.fire_at(self, total_rounds, weapon, riflegrenade, _target_hex, target_distance, target_cover, batch_targets, shot_origin)


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
			s.lower_weapon()
			s.setup_weapon_task.done = false
			s.setup_weapon_task.start_time_s = s.weapon.setup_s
		i += 1


func _on_fire_weapon(weapon_spec: WeaponSpec, pos: Vector2, is_auto: bool, owner_id: int, position_node: Node2D) -> void:
	if is_auto:
		# Automatic weapons use their continuous sample, without a generic shot overlay.
		$"../WeaponAudio".start_mg_loop(owner_id, weapon_spec, position_node)
	else:
		$"../WeaponAudio".play_shot(weapon_spec, pos, false)

func _on_stop_mg_loop(weapon_spec: WeaponSpec, position: Vector2, owner_id: int, position_node: Node2D) -> void:
	$"../WeaponAudio".stop_mg_loop(weapon_spec, position, owner_id, position_node)
	
