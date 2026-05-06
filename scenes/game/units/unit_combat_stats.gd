class_name UnitCombatStats
extends Node

@export var cohesion_current: float = 1.0
@export var cohesion_target: float = 1.0
@export var combat_effectiveness: float = 1.0

@export var recent_casualty_shock: float = 0.0
@export var merge_penalty: float = 0.0 # will not be used yet

@export var cohesion_min: float = 0.15
@export var cohesion_recovery_rate: float = 0.03
@export var cohesion_recovery_rate_leader: float = 0.06
@export var cohesion_under_fire_rate: float = 0.005
@export var shock_decay_rate: float = 0.08
@export var merge_penalty_decay_rate: float = 0.015

var unit: Unit = null


func setup(p_unit: Unit) -> void:
	unit = p_unit


func update_stats(delta: float) -> void:
	if unit == null:
		return

	_update_temporary_penalties(delta)
	_update_cohesion(delta)
	_update_combat_effectiveness()


func notify_casualty_taken(count: int) -> void:
	recent_casualty_shock = recent_casualty_shock + 0.12 * count
	recent_casualty_shock = clampf(recent_casualty_shock, 0.0, 0.6)


func notify_leader_killed() -> void:
	recent_casualty_shock += 0.25
	recent_casualty_shock = clampf(recent_casualty_shock, 0.0, 0.8)


func notify_merged_with_remnant() -> void:
	merge_penalty += 0.20
	merge_penalty = clampf(merge_penalty, 0.0, 0.5)
# stress_system.S_eff
# movement.is_moving

func _update_temporary_penalties(delta: float) -> void:
	recent_casualty_shock = move_toward(
		recent_casualty_shock,
		0.0,
		shock_decay_rate * delta
	)

	if unit.stress_system.under_fire:
		return

	merge_penalty = move_toward(
		merge_penalty,
		0.0,
		merge_penalty_decay_rate * delta
	)


func _update_cohesion(delta: float) -> void:
	var casualty_penalty: float = _get_casualty_cohesion_penalty()
	var leader_penalty: float = _get_leader_cohesion_penalty()
	#var dispersion_penalty: float = _get_dispersion_penalty()
	var movement_penalty: float = _get_movement_under_fire_penalty()
	
	cohesion_target = 1.0
	cohesion_target -= casualty_penalty
	cohesion_target -= leader_penalty
	#cohesion_target -= dispersion_penalty
	cohesion_target -= recent_casualty_shock
	cohesion_target -= merge_penalty
	cohesion_target -= movement_penalty
	cohesion_target = clampf(cohesion_target, cohesion_min, 1.0)
	
	var rate: float = _get_cohesion_recovery_rate()
	
	cohesion_current = move_toward(
		cohesion_current,
		cohesion_target,
		rate * delta
	)
	
	cohesion_current = clampf(cohesion_current, cohesion_min, 1.0)


func _get_cohesion_recovery_rate() -> float:
	var rate: float = cohesion_recovery_rate

	if unit.stress_system.under_fire:
		rate = cohesion_under_fire_rate

	var leader_presence_strength: float = unit.command_connectivity.leader_presence_strength

	rate = lerpf(
		rate,
		cohesion_recovery_rate_leader,
		leader_presence_strength
	)

	if unit.stress_system.state == STATES.MoraleState.PANIC:
		rate = 0.0

	return rate


func _update_combat_effectiveness() -> void:
	var base_strength: float = _get_base_strength()
	var casualty_mod: float = _get_casualty_mod()
	var leadership_mod: float = _get_leadership_mod()
	var key_role_mod: float = _get_key_role_mod()
	var state_mod: float = _get_state_mod()
	var stress_mod: float = _get_stress_mod()

	combat_effectiveness = base_strength
	combat_effectiveness *= casualty_mod
	combat_effectiveness *= cohesion_current
	combat_effectiveness *= leadership_mod
	combat_effectiveness *= key_role_mod
	combat_effectiveness *= state_mod
	combat_effectiveness *= stress_mod

	combat_effectiveness = clampf(combat_effectiveness, 0.0, 1.0)


func _get_expected_size() -> float:
	var expected_size: float = float(unit.original_size)

	#if unit.split_size > 0:
		#expected_size = float(unit.split_size)

	if expected_size < 1.0:
		expected_size = 1.0

	return expected_size


func _get_base_strength() -> float:
	var expected_size: float = _get_expected_size()
	var value: float = float(unit.members_alive) / expected_size
	return clampf(value, 0.0, 1.0)


func _get_casualty_ratio() -> float:
	var expected_size: float = _get_expected_size()
	var value: float = float(unit.casualties_taken) / expected_size
	return clampf(value, 0.0, 1.0)


func _get_casualty_cohesion_penalty() -> float:
	var casualty_ratio: float = _get_casualty_ratio()
	var penalty: float = casualty_ratio * 0.35
	return clampf(penalty, 0.0, 0.35)


func _get_casualty_mod() -> float:
	var casualty_ratio: float = _get_casualty_ratio()
	var casualty_penalty: float = pow(casualty_ratio, 1.35) * 0.45
	var value: float = 1.0 - casualty_penalty
	return clampf(value, 0.55, 1.0)


func _get_leader_cohesion_penalty() -> float:
	var base_penalty: float = 0.0

	if unit.embedded_leader_alive:
		base_penalty = 0.0
	else:
		base_penalty = 0.15

	var penalty_multiplier: float = lerpf(
		1.0,
		0.35,
		unit.command_connectivity.leader_presence_strength
	)
	
	var penalty: float = base_penalty * penalty_multiplier

	return clampf(penalty, 0.0, 0.15)


func _get_dispersion_penalty() -> float:
	if not unit.uses_member_positions:
		return 0.0

	var current_spread: float = unit.get_current_member_spread()
	var ideal_spread: float = unit.ideal_member_spread
	var max_allowed_spread: float = unit.max_allowed_member_spread

	if max_allowed_spread <= 0.0:
		return 0.0

	var raw_value: float = (current_spread - ideal_spread) / max_allowed_spread
	var penalty: float = clampf(raw_value, 0.0, 1.0) * 0.20

	return penalty


func _get_movement_under_fire_penalty() -> float:
	if not unit.stress_system.under_fire:
		return 0.0

	if not unit.movement.is_moving:
		return 0.0

	var penalty: float = 0.10

	#if unit.is_in_open_ground():
		#penalty = 0.20

	return penalty


func _get_leadership_mod() -> float:
	var value: float = 1.0

	if unit.embedded_leader_alive:
		value = 1.0
	else:
		value = 0.85

	var leader_presence_strength: float = unit.command_connectivity.leader_presence_strength
	var external_bonus: float = leader_presence_strength * 0.08

	value += external_bonus

	return clampf(value, 0.80, 1.10)


func _get_key_role_mod() -> float:
	return 1.0
	var value: float = 1.0

	#if unit.has_mg_role:
		#if not unit.mg_role_alive:
			#value *= 0.75
#
	#if unit.has_radio_role:
		#if not unit.radio_role_alive:
			#value *= 0.95
#
	#if unit.has_assistant_gunner_role:
		#if not unit.assistant_gunner_alive:
			#value *= 0.90
#
	#return clampf(value, 0.50, 1.0)


func _get_state_mod() -> float:
	var value: float = 1.0

	if unit.stress_system.state == STATES.MoraleState.NORMAL:
		value = 1.0
	elif unit.stress_system.state == STATES.MoraleState.CAUTIOUS:
		value = 0.85
	elif unit.stress_system.state == STATES.MoraleState.PINNED:
		value = 0.40
	elif unit.stress_system.state == STATES.MoraleState.PANIC:
		value = 0.15
	elif unit.stress_system.state == STATES.MoraleStateCOMBAT_INEFFECTIVE:
		value = 0.0

	return value


func _get_stress_mod() -> float:
	var stress_eff: float = unit.stress_system.S_eff
	var stress_norm: float = stress_eff / 100.0
	stress_norm = clampf(stress_norm, 0.0, 1.0)

	var value: float = 1.0 - stress_norm * 0.20
	return clampf(value, 0.80, 1.0)
