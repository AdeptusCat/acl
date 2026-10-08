class_name PlatoonAI
extends Node

@export var reconsider_interval: float = 1.0
@export var team: Globals.Team = Globals.Team.AXIS
@export var squads: Array[Unit] = []
@export var influence_map_controller: InfluenceMapController

var active: bool = true
var current_order: MissionOrder = null
var squad_assignments: Dictionary = {}
var reserved_hexes_by_squad: Dictionary = {}
var accepted_positions: Dictionary = {}
var time_until_reconsider: float = 0.0
var executor: TacticalPositionExecutor = TacticalPositionExecutor.new()
var _planning_requests: Array[Dictionary] = []
var _planning_results: Array[DefensePositionResult] = []
var _planning_reservations: Dictionary = {}
var _planning_job: PositionQueryJob
var _planning_index: int = 0


func _process(delta: float) -> void:
	if not active or current_order == null:
		return
	if _planning_job != null:
		_continue_budgeted_plan()
		return
	time_until_reconsider -= delta
	if time_until_reconsider <= 0.0:
		time_until_reconsider = reconsider_interval
		_start_plan(true)


func _exit_tree() -> void:
	_cancel_plan()
	_set_defensive_control(false)
	executor.cancel_all()


func set_active(is_active: bool) -> void:
	_cancel_plan()
	active = is_active
	if active:
		_set_defensive_control(current_order != null and current_order.position_mode == PositionProfile.Mode.DEFEND)
		return
	_set_defensive_control(false)
	# Release only actions owned by this planner when handing control to the player.
	executor.cancel_all(true)
	current_order = null
	squad_assignments.clear()
	reserved_hexes_by_squad.clear()
	accepted_positions.clear()
	time_until_reconsider = 0.0


func receive_mission_order(order: MissionOrder) -> void:
	if not active:
		return
	_cancel_plan()
	executor.cancel_all(true)
	accepted_positions.clear()
	current_order = order
	_set_defensive_control(order.position_mode == PositionProfile.Mode.DEFEND)
	time_until_reconsider = reconsider_interval
	_start_plan(is_inside_tree())


func set_squads(new_squads: Array[Unit]) -> void:
	_cancel_plan()
	_set_defensive_control(false)
	squads.clear()
	for squad: Unit in new_squads:
		if InfluenceUnitQuery.is_valid_living_unit(squad) and squad.team == team and not squads.has(squad):
			squads.append(squad)
	_set_defensive_control(active and current_order != null and current_order.position_mode == PositionProfile.Mode.DEFEND)


func _set_defensive_control(enabled: bool) -> void:
	for squad: Unit in squads:
		if is_instance_valid(squad) and squad.squad_ai_controller != null:
			squad.squad_ai_controller.defensive_mission_controlled = enabled


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
	_start_plan(false)


func _start_plan(budgeted: bool) -> void:
	_cancel_plan()
	if not active or current_order == null or influence_map_controller == null:
		return
	influence_map_controller.set_objective_for_team(team, current_order.objective_hex)
	if influence_map_controller.snapshot == null:
		return
	var available: Array[Unit] = _get_effective_squads()
	for unit: Unit in accepted_positions.keys():
		if not available.has(unit):
			accepted_positions.erase(unit)
			executor.cancel(unit)
	_planning_reservations = _create_current_reserved_hexes(available)
	_build_planning_requests(available)
	if budgeted and not _planning_requests.is_empty():
		_submit_planning_query()
		return
	for request: Dictionary in _planning_requests:
		var query: PositionQuery = request["query"]
		_accept_planning_result(request, PositionQueryService.query_positions(query))
	_commit_plan()


func _build_planning_requests(available: Array[Unit]) -> void:
	if current_order.position_mode != PositionProfile.Mode.DEFEND and current_order.position_mode != PositionProfile.Mode.LEGACY_DEFENSE:
		var config: InfluenceProjectionConfig = influence_map_controller._mission_config(team, current_order.objective_hex, current_order, accepted_positions)
		for unit: Unit in available:
			_add_planning_requests(config, [unit], "offense", null)
		return
	if current_order.reserve_policy != MissionOrder.ReservePolicy.NONE and available.size() >= 3:
		var reserve: Unit = _select_reserve_squad(available)
		available.erase(reserve)
		var reserve_config: InfluenceProjectionConfig = influence_map_controller._mission_config(team, current_order.objective_hex, current_order, accepted_positions)
		reserve_config.defense_radius = 2
		reserve_config.profile.firing_weight = 0.0
		reserve_config.defense_responsibility = PositionQuery.Responsibility.GUARD
		_add_planning_requests(reserve_config, [reserve], "reserve", null)
	if current_order.position_mode == PositionProfile.Mode.DEFEND and current_order.defense_responsibility == PositionQuery.Responsibility.AUTO and available.size() >= 2:
		var guard: Unit = available.pop_front()
		var guard_config: InfluenceProjectionConfig = influence_map_controller._mission_config(team, current_order.objective_hex, current_order, accepted_positions)
		guard_config.defense_responsibility = PositionQuery.Responsibility.GUARD
		_add_planning_requests(guard_config, [guard], "guard_objective", null)
	var axes: Array[ThreatAxis] = _get_sorted_threat_axes()
	if axes.is_empty():
		var config: InfluenceProjectionConfig = influence_map_controller._mission_config(team, current_order.objective_hex, current_order, accepted_positions)
		_add_planning_requests(config, available, "defend_objective", null)
	else:
		var assignments: Dictionary = _distribute_squads_over_axes(available, axes)
		for axis: ThreatAxis in axes:
			var config: InfluenceProjectionConfig = influence_map_controller._mission_config(team, current_order.objective_hex, current_order, accepted_positions)
			config.threat_axis = axis
			_add_planning_requests(config, assignments[axis], "defend_axis", axis)


func _add_planning_requests(config: InfluenceProjectionConfig, units: Array[Unit], role: String, axis: ThreatAxis) -> void:
	for unit: Unit in units:
		var query: PositionQuery = DefensePositionAnalyzer.make_query(config, unit, _planning_reservations)
		query.snapshot = influence_map_controller.snapshot
		_planning_requests.append({"query": query, "role": role, "axis": axis})


func _submit_planning_query() -> void:
	_planning_job = influence_map_controller.enqueue_position_query(_planning_requests[_planning_index]["query"])


func _continue_budgeted_plan() -> void:
	if _planning_job.canceled or _planning_job.query.objective_hex != current_order.objective_hex:
		_cancel_plan()
		time_until_reconsider = 0.0
		return
	if not _planning_job.completed:
		return
	var query: PositionQuery = _planning_job.query
	# A route computed from an old occupied hex cannot authorize a new move.
	if not InfluenceUnitQuery.is_valid_living_unit(query.unit) or query.unit.current_hex != query.origin_hex:
		_cancel_plan()
		time_until_reconsider = 0.0
		return
	_accept_planning_result(_planning_requests[_planning_index], _planning_job.result)
	_planning_index += 1
	if _planning_index < _planning_requests.size():
		_submit_planning_query()
	else:
		_commit_plan()


func _accept_planning_result(request: Dictionary, advice: PositionResult) -> void:
	var result: DefensePositionResult = DefensePositionAnalyzer.adapt_result(advice, request["axis"], request["role"])
	_planning_results.append(result)
	if result.is_valid():
		_planning_reservations[result.unit] = result.target_hex


func _commit_plan() -> void:
	for request: Dictionary in _planning_requests:
		var query: PositionQuery = request["query"]
		if not InfluenceUnitQuery.is_valid_living_unit(query.unit) or query.unit.current_hex != query.origin_hex:
			_cancel_plan()
			time_until_reconsider = 0.0
			return
	for index: int in range(_planning_results.size()):
		var result: DefensePositionResult = _planning_results[index]
		var query: PositionQuery = _planning_requests[index]["query"]
		if result.context != query.context_key():
			_cancel_plan()
			time_until_reconsider = 0.0
			return
		if result.is_valid() and query.profile.mode == PositionProfile.Mode.DEFEND:
			query.firepower_by_unit.clear()
			var protection: Dictionary = DefensePositionPolicy.evaluate(query, result.target_hex)
			if protection["responsibility"] == "" or not protection["preserves_screen"]:
				_cancel_plan()
				time_until_reconsider = 0.0
				return
	squad_assignments.clear()
	reserved_hexes_by_squad = _planning_reservations
	for result: DefensePositionResult in _planning_results:
		_apply_position_results([result], result.role, result.axis)
	_issue_orders()
	_planning_job = null
	_planning_requests.clear()
	_planning_results.clear()
	_planning_index = 0


func _cancel_plan() -> void:
	if influence_map_controller != null and _planning_job != null:
		influence_map_controller.cancel_position_query(_planning_job)
	_planning_job = null
	_planning_requests.clear()
	_planning_results.clear()
	_planning_reservations = {}
	_planning_index = 0


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
	if not active:
		return
	for squad: Unit in squad_assignments:
		var result: PositionResult = squad_assignments[squad]["result"]
		squad.position_advice = result
		squad.influence_map = result.score_map
		if result.is_valid() and executor.execute(result, current_order.execution_intent):
			var accepted_at: float = influence_map_controller.snapshot.captured_at
			var previous: Dictionary = accepted_positions.get(squad, {})
			if previous.get("hex") == result.target_hex and previous.get("context") == result.context:
				accepted_at = previous.get("at", accepted_at)
			accepted_positions[squad] = {"hex": result.target_hex, "context": result.context, "at": accepted_at}
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
	if not active or current_order == null:
		return
	var mouse: InputEventMouseButton = event as InputEventMouseButton
	if mouse == null or mouse.button_index != MOUSE_BUTTON_LEFT or not mouse.pressed:
		return
	if (mouse.ctrl_pressed and team == Globals.Team.AXIS) or (mouse.shift_pressed and team == Globals.Team.ALLIES):
		current_order.objective_hex = LOSHelper.ground_layer.local_to_map(get_parent().get_global_mouse_position())
		_start_plan(is_inside_tree())
