class_name TacticalPositionExecutor
extends RefCounted

enum Intent { FROM_PROFILE, HOLD, SUPPORT_BY_FIRE, ADVANCE, ASSAULT, WITHDRAW }

var pending: Dictionary[Unit, Dictionary] = {}
var completed: Dictionary[Unit, Dictionary] = {}


func execute(result: PositionResult, intent: Intent = Intent.FROM_PROFILE) -> bool:
	if not result.is_valid() or result.unit.action_controller == null or result.unit.action_controller.movement == null:
		return false
	var unit: Unit = result.unit
	if result.profile_mode == PositionProfile.Mode.HQ_SUPPORT:
		# Combat intent belongs to the fighting squads, even during an offensive mission.
		intent = Intent.HOLD
	if intent == Intent.FROM_PROFILE:
		intent = intent_for_profile(result.profile_mode)
		if result.decision == PositionResult.Decision.WITHDRAW:
			intent = Intent.WITHDRAW
	if unit.surrendered or unit.members_alive <= 0 or not PositionQueryService.can_follow_intent(unit):
		return false
	if intent == Intent.ASSAULT and not PositionQueryService.can_assault(unit):
		return false
	if not result.should_move:
		if unit.current_hex == result.target_hex:
			if pending.has(unit):
				cancel(unit, true)
			_finish_intent(unit, result, intent)
		elif unit.movement.is_moving and unit.movement.target_hex == result.target_hex:
			if pending.has(unit) and pending[unit]["order_id"] == unit.action_controller.action_order_id:
				pending[unit]["result"] = result
				pending[unit]["intent"] = intent
			else:
				cancel(unit)
				_track_arrival(unit, result, intent)
		return true
	if not _valid_live_path(unit, result.path, result.target_hex):
		return false
	cancel(unit)
	var cubes: Array[Vector3i] = []
	for cell: Vector2i in result.path:
		cubes.append(LOSHelper.ground_layer.map_to_cube(cell))
	if intent == Intent.ASSAULT:
		var covered: Array[Vector3i] = cubes.duplicate()
		var exposed: Array[Vector3i] = []
		if covered.size() > 1:
			exposed.append(covered.pop_back())
		unit.give_attack_hex_order(result.target_hex, covered, exposed)
	else:
		unit.give_defend_area_order(result.target_hex, cubes)
	_track_arrival(unit, result, intent)
	return true


func _track_arrival(unit: Unit, result: PositionResult, intent: Intent) -> void:
	var callback: Callable = _on_arrived.bind(unit)
	unit.unit_arrived_at_hex.connect(callback, CONNECT_ONE_SHOT)
	pending[unit] = {"result": result, "intent": intent, "order_id": unit.action_controller.action_order_id, "callback": callback}


func _on_arrived(cell: Vector2i, unit: Unit) -> void:
	if not pending.has(unit):
		return
	var intent: Dictionary = pending[unit]
	pending.erase(unit)
	if is_instance_valid(unit) and unit.action_controller.action_order_id == intent["order_id"] and cell == intent["result"].target_hex and unit.current_hex == cell:
		_finish_intent(unit, intent["result"], intent["intent"])


func _finish_intent(unit: Unit, result: PositionResult, intent: Intent) -> void:
	if not unit.alive or unit.surrendered or not PositionQueryService.can_follow_intent(unit):
		return
	var previous: Dictionary = completed.get(unit, {})
	if previous.get("context") == result.context and previous.get("hex") == result.target_hex and previous.get("order_id") == unit.action_controller.action_order_id and previous.get("intent") == intent:
		if intent != Intent.SUPPORT_BY_FIRE or unit.squad_fire == null or unit.attackState != Unit.AttackState.AUTO:
			return
	_release_support_fire(unit)
	if intent == Intent.SUPPORT_BY_FIRE:
		var state: int = unit.action_controller.action_state
		if state != SquadActionController.SquadActionState.ESTABLISHING_POSITION and state != SquadActionController.SquadActionState.HOLDING_POSITION:
			unit.give_hold_order()
		var distance: int = LOSHelper.get_hex_distance(unit.current_hex, result.objective_hex)
		if LOSHelper.los_lookup.get(unit.current_hex, {}).has(result.objective_hex) and InfluenceUnitQuery.get_firepower_at_range(unit, distance) > 0.0:
			unit.order(Globals.UnitCmd.FIRE_AT_HEX, result.objective_hex)
	elif intent == Intent.HOLD or intent == Intent.ADVANCE or intent == Intent.WITHDRAW:
		# A move-and-hold action already handles establishment and its preparation timer.
		var state: int = unit.action_controller.action_state
		if state != SquadActionController.SquadActionState.ESTABLISHING_POSITION and state != SquadActionController.SquadActionState.HOLDING_POSITION:
			unit.give_hold_order()
	var fire_unit: Unit = null
	if unit.squad_fire != null:
		fire_unit = unit.squad_fire.target_unit
	completed[unit] = {"intent": intent, "context": result.context, "hex": result.target_hex, "objective": result.objective_hex, "fire_unit": fire_unit, "order_id": unit.action_controller.action_order_id}


func cancel(unit: Unit, stop_execution: bool = false) -> void:
	_release_support_fire(unit)
	completed.erase(unit)
	if not pending.has(unit):
		return
	var owned: Dictionary = pending[unit]
	if stop_execution and is_instance_valid(unit) and unit.alive and not unit.surrendered and unit.action_controller.action_order_id == owned["order_id"]:
		var state: int = unit.action_controller.action_state
		if state == SquadActionController.SquadActionState.MOVING_TO_POSITION or state == SquadActionController.SquadActionState.ADVANCING or state == SquadActionController.SquadActionState.CROSSING_EXPOSED:
			unit.give_hold_order()
	var callback: Callable = owned["callback"]
	if is_instance_valid(unit) and unit.unit_arrived_at_hex.is_connected(callback):
		unit.unit_arrived_at_hex.disconnect(callback)
	pending.erase(unit)


func cancel_all(stop_execution: bool = false) -> void:
	var units: Array[Unit] = []
	units.assign(pending.keys())
	for unit: Unit in completed:
		if not units.has(unit):
			units.append(unit)
	for unit: Unit in units:
		cancel(unit, stop_execution)


static func _valid_live_path(unit: Unit, path: Array[Vector2i], target: Vector2i) -> bool:
	if path.is_empty() or path[0] != unit.current_hex or path[-1] != target or not Globals.astars.has(unit.team):
		return false
	var graph: AStar2D = Globals.astars[unit.team]
	var ids: Dictionary = {}
	for id: int in graph.get_point_ids():
		ids[LOSHelper.ground_layer.local_to_map(graph.get_point_position(id))] = id
	var previous: int = -1
	for cell: Vector2i in path:
		if not ids.has(cell) or graph.is_point_disabled(ids[cell]):
			return false
		var id: int = ids[cell]
		if previous >= 0 and previous != id and not graph.are_points_connected(previous, id):
			return false
		previous = id
	return true


static func intent_for_profile(mode: PositionProfile.Mode) -> Intent:
	if mode == PositionProfile.Mode.SUPPORT_BY_FIRE:
		return Intent.SUPPORT_BY_FIRE
	if mode == PositionProfile.Mode.ADVANCE:
		return Intent.ADVANCE
	if mode == PositionProfile.Mode.ASSAULT:
		return Intent.ASSAULT
	return Intent.HOLD


func _release_support_fire(unit: Unit) -> void:
	if not completed.has(unit) or not is_instance_valid(unit) or unit.squad_fire == null or unit.action_controller == null:
		return
	var owned: Dictionary = completed[unit]
	if owned["intent"] != Intent.SUPPORT_BY_FIRE or unit.action_controller.action_order_id != owned["order_id"]:
		return
	var matches_ground: bool = unit.attackState == Unit.AttackState.MANUAL_GROUND and unit.squad_fire.target_hex == owned["objective"]
	var matches_track: bool = unit.attackState == Unit.AttackState.MANUAL_TRACK and unit.squad_fire.target_unit == owned["fire_unit"]
	if matches_ground or matches_track:
		unit.squad_fire.clear_target()
		unit.setAttackState(Unit.AttackState.AUTO)
