class_name PlatoonAI
extends Node

@export var reconsider_interval: float = 1.0
@export var team: Globals.Team = Globals.Team.AXIS
@export var squads: Array[Unit] = []
@export var influence_map_controller: InfluenceMapController

var current_order: MissionOrder = null
var squad_assignments: Dictionary = {}
var reserved_hexes_by_squad: Dictionary = {}
var accepted_positions: Dictionary = {}
var time_until_reconsider: float = 0.0
var executor: TacticalPositionExecutor = TacticalPositionExecutor.new()


func _process(delta: float) -> void:
	if current_order == null:
		return
	time_until_reconsider -= delta
	if time_until_reconsider <= 0.0:
		time_until_reconsider = reconsider_interval
		reconsider_assignments()


func _exit_tree() -> void:
	executor.cancel_all()


func receive_mission_order(order: MissionOrder) -> void:
	executor.cancel_all(true)
	accepted_positions.clear()
	current_order = order
	time_until_reconsider = 0.0
	reconsider_assignments()


func set_squads(new_squads: Array[Unit]) -> void:
	squads.clear()
	for squad: Unit in new_squads:
		if InfluenceUnitQuery.is_valid_living_unit(squad) and squad.team == team and not squads.has(squad):
			squads.append(squad)


func bind_active_squads(active_units: Array[Unit]) -> void:
	# Inspector references identify owned slots, even when another map is selected.
	var slots: Array[Vector3i] = []
	for squad: Unit in squads:
		if is_instance_valid(squad) and squad.team == team:
			slots.append(Vector3i(squad.company, squad.platoon, squad.squad))
	var owned: Array[Unit] = []
	for unit: Unit in active_units:
		if unit.team == team and slots.has(Vector3i(unit.company, unit.platoon, unit.squad)):
			owned.append(unit)
	set_squads(owned)


func reconsider_assignments() -> void:
	if current_order == null or influence_map_controller == null:
		return
	influence_map_controller.set_objective_for_team(team, current_order.objective_hex)
	if influence_map_controller.snapshot == null:
		return
	var available: Array[Unit] = _get_effective_squads()
	for unit: Unit in accepted_positions.keys():
		if not available.has(unit):
			accepted_positions.erase(unit)
			executor.cancel(unit)
	squad_assignments.clear()
	reserved_hexes_by_squad = _create_current_reserved_hexes(available)
	if current_order.position_mode != PositionProfile.Mode.DEFEND and current_order.position_mode != PositionProfile.Mode.LEGACY_DEFENSE:
		_assign_offensive_positions(available)
	else:
		if current_order.reserve_policy != MissionOrder.ReservePolicy.NONE and available.size() >= 3:
			var reserve: Unit = _select_reserve_squad(available)
			available.erase(reserve)
			var reserves: Array[Unit] = [reserve]
			var reserve_config: InfluenceProjectionConfig = influence_map_controller.create_axis_defense_config(team, current_order.objective_hex)
			reserve_config.defense_radius = 2
			reserve_config.accepted_positions = accepted_positions
			reserve_config.profile.firing_weight = 0.0
			_apply_position_results(DefensePositionAnalyzer.analyze_objective_defense_positions(influence_map_controller, reserve_config, reserves, reserved_hexes_by_squad), "reserve", null)
		var axes: Array[ThreatAxis] = _get_sorted_threat_axes()
		if axes.is_empty():
			_apply_position_results(influence_map_controller.analyze_objective_defense_positions(team, current_order.objective_hex, available, reserved_hexes_by_squad, current_order, accepted_positions), "defend_objective", null)
		else:
			var assignments: Dictionary = _distribute_squads_over_axes(available, axes)
			for axis: ThreatAxis in axes:
				var assigned: Array[Unit] = assignments[axis]
				if assigned.is_empty():
					continue
				_apply_position_results(influence_map_controller.analyze_defense_positions_for_threat_axis(team, current_order.objective_hex, axis, assigned, reserved_hexes_by_squad, current_order, accepted_positions), "defend_axis", axis)
	_issue_orders()


func _select_reserve_squad(available: Array[Unit]) -> Unit:
	if current_order.reserve_policy == MissionOrder.ReservePolicy.KEEP_HQ_NEAR_OBJECTIVE:
		for unit: Unit in available:
			if unit.squad_type == Globals.SquadType.PLATOON_HEADQUARTERS or unit.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS:
				return unit
	var reserve: Unit = available[-1]
	for unit: Unit in available:
		if InfluenceUnitQuery.get_unit_effectiveness(unit) < InfluenceUnitQuery.get_unit_effectiveness(reserve):
			reserve = unit
	return reserve


func _get_sorted_threat_axes() -> Array[ThreatAxis]:
	var axes: Array[ThreatAxis] = influence_map_controller.get_sorted_threat_axes_for_team(team, current_order.objective_hex)
	if axes.is_empty():
		for axis: ThreatAxis in current_order.threat_axes:
			if axis != null and axis.is_valid_axis():
				axes.append(axis)
	return axes


func _distribute_squads_over_axes(available: Array[Unit], axes: Array[ThreatAxis]) -> Dictionary:
	var result: Dictionary = {}
	for axis: ThreatAxis in axes:
		var assigned: Array[Unit] = []
		result[axis] = assigned
	for index: int in range(available.size()):
		result[axes[index % axes.size()]].append(available[index])
	return result


func _assign_offensive_positions(units: Array[Unit]) -> void:
	for unit: Unit in units:
		var query: PositionQuery = PositionQuery.new()
		query.unit = unit
		query.team = team
		query.objective_hex = current_order.objective_hex
		query.profile = PositionProfile.for_mode(current_order.position_mode)
		query.movement_radius = current_order.movement_radius
		query.reservations = reserved_hexes_by_squad
		if accepted_positions.has(unit):
			query.has_accepted_target = true
			query.accepted_target = accepted_positions[unit]["hex"]
			query.accepted_context = accepted_positions[unit]["context"]
		var result: PositionResult = influence_map_controller.query_positions(query)
		_apply_position_results([DefensePositionAnalyzer.adapt_result(result, null, "offense")], "offense", null)


func _apply_position_results(results: Array[DefensePositionResult], _fallback_role: String, _fallback_axis: ThreatAxis) -> void:
	for result: DefensePositionResult in results:
		if result == null or not squads.has(result.unit) or result.unit.team != team:
			continue
		# Keep no-candidate diagnostics; never substitute an unchecked objective move.
		squad_assignments[result.unit] = {"result": result, "role": _fallback_role, "target_hex": result.target_hex,
			"should_move": result.should_move, "score_map": result.score_map, "reason": result.reason}
		if result.is_valid():
			reserved_hexes_by_squad[result.unit] = result.target_hex


func _issue_orders() -> void:
	for squad: Unit in squad_assignments:
		var result: PositionResult = squad_assignments[squad]["result"]
		squad.position_advice = result
		squad.influence_map = result.score_map
		if result.is_valid() and executor.execute(result, current_order.execution_intent):
			accepted_positions[squad] = {"hex": result.target_hex, "context": result.context}
			squad.best_index = result.target_index
		else:
			executor.cancel(squad, true)
			accepted_positions.erase(squad)
			reserved_hexes_by_squad[squad] = squad.current_hex


func _get_effective_squads() -> Array[Unit]:
	var result: Array[Unit] = []
	for squad: Unit in squads:
		if InfluenceUnitQuery.is_valid_living_unit(squad) and squad.team == team and squad.members_alive > 0 and squad.movement != null and influence_map_controller.snapshot.positions.has(squad) and not result.has(squad):
			result.append(squad)
	result.sort_custom(InfluenceUnitQuery.compare_units_by_squad_type_priority)
	return result


func _create_current_reserved_hexes(units: Array[Unit]) -> Dictionary:
	var result: Dictionary = {}
	for unit: Unit in units:
		var cell: Vector2i = unit.current_hex
		if unit.movement != null and unit.movement.is_moving:
			cell = unit.movement.target_hex
		result[unit] = cell
	return result


func _unhandled_input(event: InputEvent) -> void:
	if current_order == null:
		return
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse == null or mouse.button_index != MOUSE_BUTTON_LEFT or not mouse.pressed:
		return
	if (mouse.ctrl_pressed and team == Globals.Team.AXIS) or (mouse.shift_pressed and team == Globals.Team.ALLIES):
		current_order.objective_hex = LOSHelper.ground_layer.local_to_map(get_parent().get_global_mouse_position())
		reconsider_assignments()
