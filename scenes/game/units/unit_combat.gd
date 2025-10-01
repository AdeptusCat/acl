class_name UnitCombat
extends Node

@export var base_accuracy := 0.35
@export var volley_size := 3                # rounds per burst
@export var seconds_per_volley := 1.2
@export var casualty_scale := 1.0           # global tuning
@export var stress_scale := 1.0             # global tuning

const MIN_HIT_MULT: float = 0.35   # floor at extreme cover
const HALF_POINT: float = 1.5      # cover points to halve the remaining gap to the floor

var can_fire := true
var current_state := 0 # injected from morale
var cover_bonus := 0.0 # injected from LOS/terrain (0..1)
var accuracy_multiplier: float = 1.0

var fire_timer: float = 0.0
var target_unit

signal shoot(from_pos, target_pos)


func resolve_volley(target:Node, inputs:Dictionary) -> void:
	# inputs: { distance, target_exposure (0..1), target_cover (0..1),
	#           shooter_stress (0..100), target_state:int, crossfire_bonus:float }
	
	# --- Shooter state & accuracy mods ---
	var state_mod: Dictionary = STATES.STATE_MOD[current_state]
	var acc: float = base_accuracy * float(state_mod.acc)
	acc *= clamp(1.0 - float(inputs.distance) * 0.002, 0.1, 1.0)                 # simple falloff
	acc *= lerp(0.6, 1.0, 1.0 - cover_bonus)                                      # shooting out of cover
	acc *= lerp(0.6, 1.0, 1.0 - (float(inputs.shooter_stress) / 100.0) * 0.7)     # stress hurts aim

	# --- Scale rounds by men alive (squad output grows/shrinks with manpower) ---
	var parent_node: Node = get_parent()
	var members_alive: int = 1
	if parent_node and "members_alive" in parent_node:
		members_alive = max(1, int(parent_node.members_alive))   # fall back to 1, no daft zeros

	var effective_rounds: int = int(round(volley_size * float(state_mod.rof) * members_alive))
	if effective_rounds <= 0:
		return

	# # --- Direct lethality path ---
	var exposure: float  = clamp(float(inputs.get("target_exposure", 1.0)), 0.1, 1.0)
	var cover_pts: float = max(float(inputs.get("target_cover", 0.0)), 0.0)

	# --- per-round hit prob
	var p_hit_per_round: float = acc * exposure
	p_hit_per_round *= cover_multiplier_exp(cover_pts)   # diminishing-returns cover
	
	var is_point_blank: bool = int(inputs.distance) == 1
	if is_point_blank:
		p_hit_per_round *= 2.0
	
	# keep it sane after the boost
	p_hit_per_round = clamp(p_hit_per_round, 0.001, 0.95)

	# Per-round chance to disable (rifle/MG tuning lives here)
	var p_disable_given_hit: float = 0.15  # rifles ~0.10–0.20, MGs a tad higher

	# --- hazard-style casualty chance with throttle
	var per_round_disable: float = p_hit_per_round * p_disable_given_hit
	var hazard_scale: float = 0.35
	var hazard: float = per_round_disable * float(effective_rounds) * hazard_scale * casualty_scale
	var p_casualty: float = 1.0 - exp(-hazard)
	p_casualty = clamp(p_casualty, 0.0, 0.99)

	## Probability at least one disabling casualty in the volley (binomial complement)
	#var p_casualty: float = 1.0 - pow(1.0 - p_hit_per_round * p_disable_given_hit, float(effective_rounds))
#
	## Crossfire & global tuning
	#p_casualty *= (1.0 + float(inputs.get("crossfire_bonus", 0.0)))
	#p_casualty *= casualty_scale
	#p_casualty = clamp(p_casualty, 0.0, 0.99)

	# Draw casualties — **volley-level 0/1** (keeps spikes rare but meaningful)
	var casualties: int = 0
	var random_float: float = randf()
	if random_float < p_casualty:
		casualties = 1
	else:
		casualties = 0

	# --- Stress path ---
	# Fast spike: “we’re under effective fire”; scales with hit prob.
	# Slow build: more rounds whizzin’ past, worse it feels; cover helps.
	var stress_fast: float = (0.8 + p_hit_per_round) * 12.0 * stress_scale
	var stress_slow: float = float(effective_rounds) * 0.6 * lerp(0.4, 1.0, 1.0 - float(inputs.target_cover)) * stress_scale

	target.call_deferred("_on_incoming_fire_effect", casualties, stress_fast, stress_slow, self)


func handle_auto_fire(delta, shooter: Node2D, unit_visible_enemies: Dictionary, current_hex, range, fire_rate, firepower):
	fire_timer -= delta
	if fire_timer > 0.0:
		return  # Still waiting for next shot

	if target_unit:
		if target_unit and target_unit.alive and not target_unit.surrendered:
			var distance = current_hex.distance_to(target_unit.current_hex)
			if distance <= range * 2:
				var cover_map = LOSHelper.los_lookup.get(current_hex, null)
				var targetCover = 0
				if cover_map and cover_map.has(target_unit.current_hex):
					var data = cover_map[target_unit.current_hex]
					targetCover = data["target_cover"]

				target_unit.set_cover(targetCover)
				fire_at(shooter, target_unit, current_hex, distance, targetCover, firepower, range, unit_visible_enemies, fire_rate)
				fire_timer = fire_rate
				return
			else:
				target_unit = null
		else:
			target_unit = null
	var visible_enemies: Array = unit_visible_enemies.get(get_parent(), [])
	for enemy in visible_enemies:
		if enemy and enemy.alive and not enemy.surrendered:
			var distance = current_hex.distance_to(enemy.current_hex)
			if distance <= range * 2:
				var cover_map = LOSHelper.los_lookup.get(current_hex, null)
				var targetCover = 0
				if cover_map and cover_map.has(enemy.current_hex):
					var data = cover_map[enemy.current_hex]
					targetCover = data["target_cover"]

				enemy.set_cover(targetCover)
				fire_at(shooter, enemy, current_hex, distance, targetCover, firepower, range, unit_visible_enemies, fire_rate)
				fire_timer = fire_rate
				break
	

func fire_at(shooter: Node2D, target: Node2D, current_hex, distance_in_hexes: int, terrain_defense_bonus: float, firepower : float, range, unit_visible_enemies: Dictionary, fire_rate):

	var actual_firepower = firepower
	if distance_in_hexes > range:
		if distance_in_hexes <= range * 2:
			actual_firepower = firepower / 2
		else:
			return

	var target_hex = target.current_hex
	var batch_targets: Array = []

	var visible_enemies: Array = unit_visible_enemies.get(get_parent(), [])
	for u in visible_enemies:
		if is_instance_valid(u) and u.alive and not u.surrendered and u.current_hex == target_hex:
			batch_targets.append(u)

	if batch_targets.is_empty(): 
		target_unit = null
		return

	var casualties = 1
	var stress_fast = 2.0
	var stress_slow = 1.0
	for u in batch_targets:
		u.set_cover(terrain_defense_bonus)
		u.receive_fire(actual_firepower, terrain_defense_bonus, unit_visible_enemies)
		
		#u.call_deferred("_on_incoming_fire_effect", casualties, stress_fast, stress_slow, self)
		resolve_volley(u, {
			"distance": distance_in_hexes,
			"target_exposure": 1,
			"target_cover": terrain_defense_bonus,
			"shooter_stress": get_parent().stress_system.S_eff,
			"target_state": u.stress_system.state,
			"crossfire_bonus": 0.0   # e.g. +0.15 if ≥2 sources suppressing
		})
	fire_burst(shooter, current_hex, batch_targets[0], 8, fire_rate, unit_visible_enemies)


func fire_burst(shooter: Node2D, current_hex, target: Node2D, rounds: int, bullets_per_sec: float, unit_visible_enemies: Dictionary) -> void:
	var interval = 1.0 / bullets_per_sec
	var from_pos = LOSHelper.ground_layer.map_to_local(current_hex)
	
	for i in range(rounds):
		if not is_instance_valid(shooter) or not is_instance_valid(target):
			target_unit = null
			return
		var visible_enemies: Array = unit_visible_enemies.get(get_parent(), [])
		if not visible_enemies.has(target):
			target_unit = null
			return
		if shooter.broken or shooter.moving or shooter.surrendered:
			target_unit = null
			return
		
		shoot.emit(shooter.global_position, target.global_position)

		await get_tree().create_timer(interval).timeout



func cover_multiplier_exp(cover_pts: float) -> float:
	# Multiplier goes 1.0 → MIN_HIT_MULT with diminishing returns as cover_pts rises
	var k: float = log(2.0) / HALF_POINT
	return MIN_HIT_MULT + (1.0 - MIN_HIT_MULT) * exp(-k * max(cover_pts, 0.0))
