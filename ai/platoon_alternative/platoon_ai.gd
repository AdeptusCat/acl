class_name PlatoonAI
extends Node

@export var reconsider_interval: float = 1.0
@export var team: Globals.Team = Globals.Team.AXIS
@export var squads: Array[Unit] = []
@export var influence_map_controller: InfluenceMapController

var current_order: MissionOrder = null
var squad_assignments: Dictionary = {}
var reserved_hexes_by_squad: Dictionary = {}
var time_until_reconsider: float = 0.0


func _process(delta: float) -> void:
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

	if influence_map_controller == null:
		return

	squad_assignments.clear()
	reserved_hexes_by_squad = _create_current_reserved_hexes(squads)

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

	if influence_map_controller != null:
		axes = influence_map_controller.get_sorted_threat_axes_for_team(
			team,
			current_order.objective_hex
		)
	
	if axes.is_empty():
		axes = _get_order_threat_axes()

	axes.sort_custom(_sort_axis_by_score_descending)
	return axes


func _get_order_threat_axes() -> Array[ThreatAxis]:
	var axes: Array[ThreatAxis] = []

	if current_order == null:
		return axes

	for axis: ThreatAxis in current_order.threat_axes:
		if axis == null:
			continue

		axis.recompute_score()

		if axis.is_valid_axis():
			axes.append(axis)

	return axes


func _sort_axis_by_score_descending(axis_a: ThreatAxis, axis_b: ThreatAxis) -> bool:
	return axis_a.score > axis_b.score


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
	var worst_effectiveness: float = INF

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
	reserved_hexes_by_squad[squad] = target_hex

	squad_assignments[squad] = {
		"role": "reserve",
		"axis": null,
		"target_hex": target_hex,
		"target_index": -1,
		"score": 0.0,
		"should_move": true,
		"score_map": PackedFloat32Array(),
	}


func _assign_squads_to_axes(
	available_squads: Array[Unit],
	sorted_axes: Array[ThreatAxis]
) -> void:
	if available_squads.is_empty():
		return

	if sorted_axes.is_empty():
		_assign_squads_to_objective_defense(available_squads)
		return

	var units_by_axis: Dictionary = _distribute_squads_over_axes(
		available_squads,
		sorted_axes
	)

	for axis: ThreatAxis in sorted_axes:
		var assigned_units: Array[Unit] = units_by_axis[axis]
		var results: Array[DefensePositionResult] = influence_map_controller.analyze_defense_positions_for_threat_axis(
			team,
			current_order.objective_hex,
			axis,
			assigned_units,
			reserved_hexes_by_squad
		)

		_apply_position_results(results, "defend_axis", axis)


func _distribute_squads_over_axes(
	available_squads: Array[Unit],
	sorted_axes: Array[ThreatAxis]
) -> Dictionary:
	var units_by_axis: Dictionary = {}

	for axis: ThreatAxis in sorted_axes:
		var axis_units: Array[Unit] = []
		units_by_axis[axis] = axis_units

	var axis_index: int = 0

	for squad: Unit in available_squads:
		var axis: ThreatAxis = sorted_axes[axis_index]
		var axis_units: Array[Unit] = units_by_axis[axis]

		axis_units.append(squad)
		units_by_axis[axis] = axis_units

		axis_index += 1

		if axis_index >= sorted_axes.size():
			axis_index = 0

	return units_by_axis


func _assign_squads_to_objective_defense(available_squads: Array[Unit]) -> void:
	if current_order == null:
		return

	if available_squads.is_empty():
		return

	var results: Array[DefensePositionResult] = influence_map_controller.analyze_objective_defense_positions(
		team,
		current_order.objective_hex,
		available_squads,
		reserved_hexes_by_squad
	)

	if results.is_empty():
		_assign_squads_to_objective_fallback(available_squads)
		return

	_apply_position_results(results, "defend_objective", null)


func _assign_squads_to_objective_fallback(available_squads: Array[Unit]) -> void:
	for squad: Unit in available_squads:
		if squad == null:
			continue

		var target_hex: Vector2i = current_order.objective_hex
		reserved_hexes_by_squad[squad] = target_hex

		squad_assignments[squad] = {
			"role": "defend_objective",
			"axis": null,
			"target_hex": target_hex,
			"target_index": -1,
			"score": 0.0,
			"should_move": true,
			"score_map": PackedFloat32Array(),
		}


func _apply_position_results(
	results: Array[DefensePositionResult],
	fallback_role: String,
	fallback_axis: ThreatAxis
) -> void:
	for result: DefensePositionResult in results:
		if result == null:
			continue

		if not result.is_valid():
			continue

		var role: String = result.role
		if role.is_empty():
			role = fallback_role

		var axis: ThreatAxis = result.axis
		if axis == null:
			axis = fallback_axis

		reserved_hexes_by_squad[result.unit] = result.target_hex
		squad_assignments[result.unit] = {
			"role": role,
			"axis": axis,
			"target_hex": result.target_hex,
			"target_index": result.target_index,
			"score": result.score,
			"previous_score": result.previous_score,
			"should_move": result.should_move,
			"score_map": result.score_map,
		}


func _issue_orders() -> void:
	for squad: Unit in squad_assignments.keys():
		if squad == null:
			continue

		var assignment: Dictionary = squad_assignments[squad]
		var score_map: PackedFloat32Array = assignment["score_map"]
		if not score_map.is_empty():
			squad.influence_map = score_map

		var should_move: bool = assignment["should_move"]
		if not should_move:
			continue

		var target_hex: Vector2i = assignment["target_hex"]
		_issue_move_order_to_squad(squad, target_hex)

		var target_index: int = assignment["target_index"]
		if target_index >= 0:
			squad.best_index = target_index


func _issue_move_order_to_squad(squad: Unit, target_hex: Vector2i) -> void:
	if squad == null:
		return

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

	if squad.members_alive <= 0:
		return 0.0

	return float(squad.members_alive)


func _get_best_reserve_hex() -> Vector2i:
	if current_order == null:
		return Vector2i.ZERO

	return current_order.objective_hex


func _create_current_reserved_hexes(units: Array[Unit]) -> Dictionary:
	var result: Dictionary = {}

	for unit: Unit in units:
		if unit == null:
			continue

		var reserved_hex: Vector2i = unit.current_hex
		if unit.movement != null:
			reserved_hex = unit.movement.target_hex

		result[unit] = reserved_hex

	return result


func _unhandled_input(event: InputEvent) -> void:
	var mouse_button_event: InputEventMouseButton = event as InputEventMouseButton
	if mouse_button_event == null:
		return

	if mouse_button_event.button_index != MOUSE_BUTTON_LEFT:
		return

	if mouse_button_event.pressed == false:
		return

	if mouse_button_event.ctrl_pressed == false:
		return

	current_order.objective_hex = LOSHelper.ground_layer.local_to_map(get_parent().get_global_mouse_position())
	print("objective hex: ", current_order.objective_hex)
