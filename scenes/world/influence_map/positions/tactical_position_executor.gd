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
	var support_target: Unit = null
	if intent == Intent.SUPPORT_BY_FIRE:
		if unit.squad_fire != null:
			unit.squad_fire.mission_support_fire = true
		support_target = select_support_target(unit, result.objective_hex)
	if previous.get("context") == result.context and previous.get("hex") == result.target_hex and previous.get("order_id") == unit.action_controller.action_order_id and previous.get("intent") == intent:
		if intent != Intent.SUPPORT_BY_FIRE or unit.squad_fire == null:
			return
		if unit.attackState != Unit.AttackState.AUTO and (unit.squad_fire.has_target_hex or unit.squad_fire.target_unit != null):
			if support_target != null and unit.squad_fire.target_unit == support_target:
				return
	_release_support_fire(unit)
	if intent == Intent.SUPPORT_BY_FIRE:
		if unit.squad_fire != null:
			unit.squad_fire.mission_support_fire = true
		var state: int = unit.action_controller.action_state
		if state != SquadActionController.SquadActionState.ESTABLISHING_POSITION and state != SquadActionController.SquadActionState.HOLDING_POSITION:
			unit.give_hold_order()
		if support_target != null:
			unit.setAttackState(Unit.AttackState.MANUAL_TRACK)
			unit.order(Globals.UnitCmd.FIRE_AT_UNIT, support_target)
		else:
			if unit.squad_fire != null:
				unit.squad_fire.clear_target()
			unit.setAttackState(Unit.AttackState.AUTO)
	elif intent == Intent.HOLD or intent == Intent.ADVANCE or intent == Intent.WITHDRAW:
		# A move-and-hold action already handles establishment and its preparation timer.
		var state: int = unit.action_controller.action_state
		if state != SquadActionController.SquadActionState.ESTABLISHING_POSITION and state != SquadActionController.SquadActionState.HOLDING_POSITION:
			unit.give_hold_order()
	var fire_unit: Unit = null
	if unit.squad_fire != null:
		fire_unit = unit.squad_fire.target_unit
	var fire_hex: Vector2i = result.objective_hex
	if unit.squad_fire != null and unit.squad_fire.has_target_hex:
		fire_hex = unit.squad_fire.target_hex
	completed[unit] = {"intent": intent, "context": result.context, "hex": result.target_hex, "objective": fire_hex, "fire_unit": fire_unit, "order_id": unit.action_controller.action_order_id}


static func is_sufficiently_suppressed(enemy: Unit) -> bool:
	if not is_active_defender(enemy) or enemy.stress_system == null:
		return false
	return enemy.stress_system.state in [Unit.MoraleState.PINNED, Unit.MoraleState.PANIC, Unit.MoraleState.COMBAT_INEFFECTIVE] or enemy.stress_system.S_eff >= enemy.stress_system.pin_threshold


static func is_overwhelmed(enemy: Unit) -> bool:
	return is_active_defender(enemy) and enemy.stress_system != null and enemy.stress_system.S_CAP > 0.0 and enemy.stress_system.S_eff / enemy.stress_system.S_CAP > 0.8


static func is_active_defender(enemy: Unit) -> bool:
	return InfluenceUnitQuery.is_valid_living_unit(enemy) and not enemy.surrendered and enemy.members_alive > 0


static func support_hex_is_clear(unit: Unit, cell: Vector2i) -> bool:
	for friendly: Unit in Globals.get_units_for_team(unit.team):
		if InfluenceUnitQuery.is_valid_living_unit(friendly) and friendly.members_alive > 0 and friendly.current_hex == cell:
			return false
	return true


static func select_support_target(unit: Unit, objective: Vector2i) -> Unit:
	var selected: Unit = null
	var lowest_stress: float = INF
	var selected_suppressed: bool = true
	for enemy: Unit in Globals.unit_visible_enemies.get(unit, []):
		if not is_active_defender(enemy) or enemy.team == unit.team or enemy.stress_system == null or not support_hex_is_clear(unit, enemy.current_hex):
			continue
		if LOSHelper.get_hex_distance(enemy.current_hex, objective) > 4:
			continue
		var distance: int = LOSHelper.get_hex_distance(unit.current_hex, enemy.current_hex)
		if not LOSHelper.los_lookup.get(unit.current_hex, {}).has(enemy.current_hex) or InfluenceUnitQuery.get_firepower_at_range(unit, distance) <= 0.0:
			continue
		var suppressed: bool = is_sufficiently_suppressed(enemy)
		var stress: float = enemy.stress_system.S_eff
		if selected == null or (selected_suppressed and not suppressed) or (selected_suppressed == suppressed and stress < lowest_stress):
			selected = enemy
			lowest_stress = stress
			selected_suppressed = suppressed
	return selected


static func select_support_target_for_objective(unit: Unit, objective: Vector2i) -> Unit:
	var target: Unit = select_support_target(unit, objective)
	if target != null and (target.current_hex == objective or not is_sufficiently_suppressed(target)):
		return target
	return null


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
	if is_instance_valid(unit) and unit.squad_fire != null:
		unit.squad_fire.mission_support_fire = false
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
