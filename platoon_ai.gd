class_name PlatoonAI
extends Node

@export var reconsider_interval: float = 1.0

var current_order: MissionOrder = null
@export var squads: Array[Unit] = []
var squad_assignments: Dictionary = {}
var time_until_reconsider: float = 0.0
@export var influence_map_controller: InfluenceMapController

func _process(delta: float) -> void:
	#return
	if current_order == null:
		return

	time_until_reconsider -= delta

	if time_until_reconsider > 0.0:
		return

	time_until_reconsider = reconsider_interval
	reconsider_assignments()


func receive_mission_order(order: MissionOrder) -> void:
	current_order = order
	time_until_reconsider = 0.0
	reconsider_assignments()


func set_squads(new_squads: Array[Unit]) -> void:
	squads.clear()

	for squad: Unit in new_squads:
		if squad == null:
			continue

		squads.append(squad)


func reconsider_assignments() -> void:
	if current_order == null:
		return

	if squads.is_empty():
		return

	squad_assignments.clear()

	var available_squads: Array[Unit] = _get_effective_squads()
	var sorted_axes: Array[ThreatAxis] = _get_sorted_threat_axes()

	var reserve_squad: Unit = null

	if _should_keep_reserve(available_squads):
		reserve_squad = _select_reserve_squad(available_squads)
		available_squads.erase(reserve_squad)
		_assign_reserve_squad(reserve_squad)

	_assign_squads_to_axes(available_squads, sorted_axes)
	_issue_orders()


func _get_sorted_threat_axes() -> Array[ThreatAxis]:
	var axes: Array[ThreatAxis] = []

	if current_order == null:
		return axes

	for axis: ThreatAxis in current_order.threat_axes:
		if axis == null:
			continue

		axis.recompute_score()

		if axis.is_valid_axis():
			axes.append(axis)

	axes.sort_custom(_sort_axis_by_score_descending)

	return axes


func _sort_axis_by_score_descending(a: ThreatAxis, b: ThreatAxis) -> bool:
	return a.score > b.score


func _should_keep_reserve(available_squads: Array[Unit]) -> bool:
	if current_order == null:
		return false

	if current_order.reserve_policy == MissionOrder.ReservePolicy.NONE:
		return false

	if available_squads.size() < 3:
		return false

	return true


func _select_reserve_squad(available_squads: Array[Unit]) -> Unit:
	var worst_squad: Unit = null
	var worst_effectiveness: float = 999999.0

	for squad: Unit in available_squads:
		if squad == null:
			continue

		var effectiveness: float = _get_squad_effectiveness(squad)

		if effectiveness < worst_effectiveness:
			worst_effectiveness = effectiveness
			worst_squad = squad

	return worst_squad


func _assign_reserve_squad(squad: Unit) -> void:
	if squad == null:
		return

	var target_hex: Vector2i = _get_best_reserve_hex()

	squad_assignments[squad] = {
		"role": "reserve",
		"axis": null,
		"target_hex": target_hex,
	}


#func _assign_squads_to_axes(available_squads: Array[Unit], sorted_axes: Array[ThreatAxis]) -> void:
	#if available_squads.is_empty():
		#return
#
	#if sorted_axes.is_empty():
		#_assign_squads_to_objective_defense(available_squads)
		#return
#
	#var squad_index: int = 0
#
	#for squad: Unit in available_squads:
		#var axis: ThreatAxis = sorted_axes[squad_index]
		#
		#var target_hex: Vector2i = _find_best_defense_hex_for_axis(squad, axis)
#
		#squad_assignments[squad] = {
			#"role": "defend_axis",
			#"axis": axis,
			#"target_hex": target_hex,
		#}
#
		#squad_index += 1
#
		#if squad_index >= sorted_axes.size():
			#squad_index = 0


func _assign_squads_to_axes(
	available_squads: Array[Unit],
	sorted_axes: Array[ThreatAxis]
) -> void:
	if available_squads.is_empty():
		return

	if sorted_axes.is_empty():
		_assign_squads_to_objective_defense(available_squads)
		return

	var axis_units_by_axis: Dictionary = _distribute_squads_over_axes(
		available_squads,
		sorted_axes
	)

	for axis: ThreatAxis in sorted_axes:
		var assigned_units: Array[Unit] = axis_units_by_axis[axis]

		influence_map_controller.run_post_rebuild_tactical_tasks_with_threataxis(
			axis,
			assigned_units
		)


func _distribute_squads_over_axes(
	available_squads: Array[Unit],
	sorted_axes: Array[ThreatAxis]
) -> Dictionary:
	var axis_units_by_axis: Dictionary = {}

	for axis: ThreatAxis in sorted_axes:
		var axis_units: Array[Unit] = []
		axis_units_by_axis[axis] = axis_units

	var axis_index: int = 0

	for squad: Unit in available_squads:
		var axis: ThreatAxis = sorted_axes[axis_index]
		var axis_units: Array[Unit] = axis_units_by_axis[axis]

		axis_units.append(squad)
		axis_units_by_axis[axis] = axis_units

		axis_index += 1

		if axis_index >= sorted_axes.size():
			axis_index = 0

	return axis_units_by_axis



func _find_best_defense_hex_for_axis(squad: Unit, axis: ThreatAxis) -> Vector2i:
	if squad == null:
		return Vector2i.ZERO

	if axis == null:
		return current_order.objective_hex

	var best_hex: Vector2i = squad.current_hex
	var best_score: float = -999999.0

	for hex: Vector2i in current_order.sector_cells:
		var score: float = _score_defense_hex_for_axis(squad, hex, axis)

		if score > best_score:
			best_score = score
			best_hex = hex

	return best_hex


func _score_defense_hex_for_axis(squad: Unit, hex: Vector2i, axis: ThreatAxis) -> float:
	var score: float = 0.0

	score += _get_cover_score(hex) * 2.0
	score += _get_los_to_axis_score(hex, axis) * 3.0
	score += _get_objective_anchor_score(hex) * 1.5
	score += _get_fallback_route_score(hex) * 1.0

	score -= _get_enemy_threat_score(hex) * 2.0
	score -= _get_ally_crowding_score(hex) * 1.5
	score -= _get_distance_from_squad_penalty(squad, hex) * 0.5

	return score


func _get_cover_score(hex: Vector2i) -> float:
	return 0.0


func _get_los_to_axis_score(hex: Vector2i, axis: ThreatAxis) -> float:
	return 0.0


func _get_objective_anchor_score(hex: Vector2i) -> float:
	if current_order == null:
		return 0.0

	var distance: int = LOSHelper.get_hex_distance(hex, current_order.objective_hex)
	var score: float = 1.0 - float(distance) * 0.1

	if score < 0.0:
		score = 0.0

	return score


func _get_fallback_route_score(hex: Vector2i) -> float:
	return 0.0


func _get_enemy_threat_score(hex: Vector2i) -> float:
	return 0.0


func _get_ally_crowding_score(hex: Vector2i) -> float:
	return 0.0


func _get_distance_from_squad_penalty(squad: Unit, hex: Vector2i) -> float:
	if squad == null:
		return 0.0

	var distance: int = LOSHelper.get_hex_distance(squad.current_hex, hex)
	return float(distance) * 0.1


func _issue_orders() -> void:
	for squad: Unit in squad_assignments.keys():
		if squad == null:
			continue

		var assignment: Dictionary = squad_assignments[squad]
		var target_hex: Vector2i = assignment["target_hex"]

		_issue_move_order_to_squad(squad, target_hex)


func _issue_move_order_to_squad(squad: Unit, target_hex: Vector2i) -> void:
	if squad == null:
		return

	# Replace with your existing movement/order function.
	#squad.set_ai_move_target(target_hex)
	squad.order(Globals.UnitCmd.MOVE, target_hex)

func _get_effective_squads() -> Array[Unit]:
	var result: Array[Unit] = []

	for squad: Unit in squads:
		if squad == null:
			continue

		if _get_squad_effectiveness(squad) <= 0.0:
			continue

		result.append(squad)

	return result


func _get_squad_effectiveness(squad: Unit) -> float:
	if squad == null:
		return 0.0

	# Replace with squad.combat_effectiveness when available.
	if squad.members_alive <= 0:
		return 0.0

	return float(squad.members_alive)


func _get_best_reserve_hex():
	return current_order.objective_hex


func _assign_squads_to_objective_defense(available_squads: Array[Unit]) -> void:
	if current_order == null:
		return

	if available_squads.is_empty():
		return

	var assigned_hexes: Array[Vector2i] = []

	for squad: Unit in available_squads:
		if squad == null:
			continue

		var target_hex: Vector2i = _find_best_objective_defense_hex_for_squad(
			squad,
			assigned_hexes
		)

		assigned_hexes.append(target_hex)

		squad_assignments[squad] = {
			"role": "defend_objective",
			"axis": null,
			"target_hex": target_hex,
		}


func _find_best_objective_defense_hex_for_squad(squad, assigned_hexes) -> Vector2i:
	return Vector2i(9, 17)
