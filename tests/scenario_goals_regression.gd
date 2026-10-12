extends Node

var checks: int = 0
var failures: int = 0
var controller: Node2D
var planner: PlatoonAI
var rifles: Array[Unit] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(6049)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map: Map = world.maps.get_node("DefaultMap")
	var scenario: Scenario = map.get_scenario(0)
	# Keep this denial fixture independent of authored scenario victory edits.
	var occupation: OccupyObjectiveCondition = OccupyObjectiveCondition.new()
	occupation.team = Globals.Team.ALLIES
	var exit: ExitUnitsCondition = ExitUnitsCondition.new()
	exit.team = Globals.Team.ALLIES
	exit.outcome_level = VictoryCondition.OutcomeLevel.MINOR
	var destroy: DestroyUnitsCondition = DestroyUnitsCondition.new()
	destroy.team = Globals.Team.ALLIES
	destroy.outcome_level = VictoryCondition.OutcomeLevel.MINOR
	scenario.victory_conditions = [exit, destroy, occupation]
	scenario.player_team = Globals.Team.ALLIES
	scenario.axis_ai_status = Scenario.AIStatus.ON
	scenario.allies_ai_status = Scenario.AIStatus.OFF
	scenario.axis_ai_mode = Scenario.AIMode.ATTACK
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	controller = world.game_controller
	planner = controller.platoon_ai
	var player_objective: Vector2i = Vector2i.ZERO
	for condition: VictoryCondition in scenario.victory_conditions:
		if condition is OccupyObjectiveCondition:
			player_objective = (condition as OccupyObjectiveCondition).state.hexes[0]
	_check(planner.current_order.objective_hex == player_objective, "OutpostProbe AI protects the player's actual occupation objective")
	_check(planner.goal_director != null and planner.goal_director.primary.kind == ScenarioGoalTask.Kind.DENY_OCCUPATION, "A side without victory conditions gets a denial mission")
	for frame: int in range(900):
		await get_tree().process_frame
		if not planner.squad_assignments.is_empty():
			break
	_check(not planner.squad_assignments.is_empty(), "The real budgeted planner publishes goal-aware orders")
	_freeze(main)
	for unit: Unit in planner.squads:
		unit.give_hold_order()
		_set_hex(unit, unit.current_hex)
		if unit.squad_type == Globals.SquadType.Rifle:
			rifles.append(unit)
	_check(rifles.size() >= 3, "Fixture has rifles for separate objective duties")
	controller.influence_map_controller.create_maps(0.0)
	_set_hex(rifles[1], _adjacent_empty(controller.influence_map_controller.snapshot, rifles[0]))
	_set_hex(rifles[2], _adjacent_empty(controller.influence_map_controller.snapshot, rifles[1]))
	controller.influence_map_controller.create_maps(0.0)
	_test_outcomes()
	_test_occupation()
	_test_exit_progress()
	_test_multiple_goals()
	_test_exact_destinations()
	_test_bound_stability()
	_test_recovered_defender()
	_test_enemy_knowledge()
	_test_denial_switch()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Scenario goal checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _occupy(hexes: Array[Vector2i], count: int = 1) -> OccupyObjectiveCondition:
	var condition: OccupyObjectiveCondition = OccupyObjectiveCondition.new()
	condition.team = planner.team
	condition.required_unit_count = count
	condition.state = OccupyObjectiveState.new()
	condition.state.hexes = hexes.duplicate()
	for hex: Vector2i in hexes:
		condition.state.required_times_reached_s[hex] = 0.0
		condition.state.victory_conditions_met[hex] = false
		condition.state.units_in_objectives[hex] = UnitsCollection.new()
	return condition


func _test_outcomes() -> void:
	var first: DestroyUnitsCondition = DestroyUnitsCondition.new()
	first.team = planner.team
	first.required_unit_count = 0
	var second: DestroyUnitsCondition = DestroyUnitsCondition.new()
	second.team = planner.team
	second.required_unit_count = 100
	var conditions: Array[VictoryCondition] = [first, second]
	_check(not VictoryConditionProgress.outcome_complete(conditions, planner.team, VictoryCondition.OutcomeLevel.MAJOR, false), "All conditions of a victory level must be met")
	second.required_unit_count = 0
	second.test_at_scenario_end = true
	_check(not VictoryConditionProgress.outcome_complete(conditions, planner.team, VictoryCondition.OutcomeLevel.MAJOR, false), "End-only conditions cannot award early victory")
	_check(VictoryConditionProgress.outcome_complete(conditions, planner.team, VictoryCondition.OutcomeLevel.MAJOR, true), "End-only conditions are eligible at the deadline")
	_check(not VictoryConditionProgress.outcome_complete([], planner.team, VictoryCondition.OutcomeLevel.MAJOR, true), "A side with no conditions cannot win automatically")
	_check(not _occupy([]).is_condition_met(), "Missing occupation markers cannot award victory")


func _test_occupation() -> void:
	var friendly: Unit = rifles[0]
	var enemy: Unit = Globals.get_units_for_team(Globals.get_enemy_team(planner.team))[0]
	var enemy_hex: Vector2i = enemy.current_hex
	var condition: OccupyObjectiveCondition = _occupy([friendly.current_hex])
	friendly.stress_system.state = UnitStates.MoraleState.PINNED
	condition.advance_time(3.0)
	_check(condition.is_condition_met(), "A pinned squad already on an objective still counts under the occupation rules")
	_set_hex(enemy, friendly.current_hex)
	condition.advance_time(0.1)
	_check(not condition.is_condition_met(), "A good-order enemy in the same hex resets occupation")
	condition.contested_by_enemy_presence = false
	condition.advance_time(3.0)
	_check(condition.is_condition_met(), "The authored contest setting is respected")
	_set_hex(enemy, enemy_hex)
	friendly.stress_system.state = UnitStates.MoraleState.NORMAL


func _test_exit_progress() -> void:
	var condition: ExitUnitsCondition = ExitUnitsCondition.new()
	condition.team = planner.team
	condition.required_unit_count = 2
	condition.state = ExitUnitsState.new()
	condition.state.exit_hexes = [rifles[0].current_hex]
	VictoryConditionProgress.read(condition)
	_check(condition.state.units_exited.is_empty(), "Reading exit progress never registers units or changes the match")
	condition.advance_time(0.1)
	condition.advance_time(0.1)
	_check(condition.state.units_exited.size() == 1 and not condition.is_condition_met(), "Repeated visits by one squad count once")
	var original: Vector2i = rifles[1].current_hex
	_set_hex(rifles[1], condition.state.exit_hexes[0])
	condition.advance_time(0.1)
	_check(condition.is_condition_met(), "Two distinct squads satisfy the exit threshold")
	_set_hex(rifles[1], original)
	_check(condition.is_condition_met(), "Recorded exits remain complete after the squads leave the marker")


func _test_multiple_goals() -> void:
	var first: Vector2i = rifles[0].current_hex
	var second: Vector2i = rifles[1].current_hex
	var condition: OccupyObjectiveCondition = _occupy([first, second])
	var goals: ScenarioGoalDirector = ScenarioGoalDirector.new()
	goals.configure(planner.team, [condition], PositionProfile.Mode.ASSAULT)
	planner.receive_mission_order(goals.initial_order(planner, MissionOrder.new(), 300.0))
	goals.update(planner, 300.0, 10.0)
	_check(goals.assignments.size() == 2, "Multi-hex occupation assigns a garrison to each required marker")
	_check(goals.assignments.has(rifles[0]) and goals.assignments.has(rifles[1]) and goals.assignments[rifles[0]].hex == first and goals.assignments[rifles[1]].hex == second, "Existing eligible occupants retain their own objective duties")
	var order_id: int = rifles[0].action_controller.action_order_id
	for tick: int in range(12):
		goals.update(planner, 300.0, 11.0 + float(tick))
	_check(rifles[0].action_controller.action_order_id == order_id and goals.assignments[rifles[0]].hex == first, "Periodic strategic updates preserve accepted unit orders and assignments")
	var allied: PlatoonAI = controller.get_node("PlatoonAi2")
	goals.update(allied, 300.0, 30.0)
	_check(not allied.active and allied.current_order == null, "An inactive side receives no strategic orders")
	# A simultaneous exit condition is completed before its squad is reassigned to a garrison.
	var exit: ExitUnitsCondition = ExitUnitsCondition.new()
	exit.team = planner.team
	exit.state = ExitUnitsState.new()
	exit.state.exit_hexes = [rifles[2].current_hex]
	goals.configure(planner.team, [condition, exit], PositionProfile.Mode.ASSAULT)
	planner.receive_mission_order(goals.initial_order(planner, MissionOrder.new(), 300.0))
	goals.update(planner, 300.0, 40.0)
	_check(goals.assignments.size() == 3 and goals.assignments[rifles[2]].kind == ScenarioGoalTask.Kind.EXIT, "Distinct squads receive exit and occupation duties in one winning package")
	exit.advance_time(0.1)
	goals.update(planner, 300.0, 41.0)
	_check(goals.assignments.size() == 2 and not goals.assignments.has(rifles[2]), "Completed exit duties release squads without extra trips")
	var overlap: OccupyObjectiveCondition = _occupy([first], 2)
	goals.configure(planner.team, [condition, overlap], PositionProfile.Mode.ASSAULT)
	planner.receive_mission_order(goals.initial_order(planner, MissionOrder.new(), 300.0))
	goals.update(planner, 300.0, 50.0)
	_check(goals.tasks.size() == 2 and goals.assignments.size() == 3, "Overlapping occupation conditions share the maximum required garrison instead of duplicating duties")


func _test_exact_destinations() -> void:
	var snapshot: InfluenceSnapshot = controller.influence_map_controller.snapshot
	snapshot.contacts[planner.team] = []
	snapshot.defensive_contacts[planner.team] = []
	var map: InfluenceMap = snapshot.maps[planner.team]
	map.clear_layer(InfluenceMap.Layer.THREAT)
	map.clear_layer(InfluenceMap.Layer.FORECAST_THREAT)
	snapshot._forecasts.clear()
	var unit: Unit = rifles[2]
	var target: Vector2i = _adjacent_empty(snapshot, unit)
	_check(target != Vector2i(-999, -999), "A reachable empty destination exists for the exact-entry check")
	if target == Vector2i(-999, -999):
		return
	var query: PositionQuery = PositionQuery.new()
	query.unit = unit
	query.team = unit.team
	query.snapshot = snapshot
	query.objective_hex = target
	query.profile = PositionProfile.for_mode(PositionProfile.Mode.ADVANCE)
	query.goal_destination_required = true
	query.goal_key = "occupation_fixture"
	query.goal_reason = "Occupy the required marker"
	var result: PositionResult = PositionQueryService.query_positions(query)
	_check(result.is_valid() and result.target_hex == target and result.features.has("scenario_goal"), "Occupation and exit advice enters the marker rather than settling nearby")
	_check(result.reason.contains(query.goal_reason), "Position advice explains the strategic duty")
	var other: Unit = rifles[1]
	var original: Vector2i = other.current_hex
	_set_hex(other, target)
	snapshot.positions[other] = target
	query.goal_capacity = 2
	result = PositionQueryService.query_positions(query)
	_check(result.is_valid() and result.target_hex == target, "A two-squad occupation requirement permits the necessary shared objective")
	query.goal_capacity = 1
	result = PositionQueryService.query_positions(query)
	_check(not result.is_valid() or result.target_hex != target, "Ordinary destinations keep the existing combat-squad capacity limit")
	_set_hex(other, original)
	snapshot.positions[other] = original
	var exit: ExitUnitsCondition = ExitUnitsCondition.new()
	exit.required_unit_count = 2
	var task: ScenarioGoalTask = ScenarioGoalTask.new()
	task.kind = ScenarioGoalTask.Kind.EXIT
	task.condition = exit
	task.hex = target
	task.key = "exit_capacity_fixture"
	planner._planning_snapshot = snapshot
	planner._planning_reservations = {}
	planner._planning_requests.clear()
	planner._add_goal_request(unit, task)
	_check(planner._planning_requests[0]["query"].goal_capacity == 2, "Exit movement retains capacity for the original threshold after earlier squads register")
	planner._cancel_plan()


func _test_bound_stability() -> void:
	var unit: Unit = rifles[2]
	var snapshot: InfluenceSnapshot = controller.influence_map_controller.snapshot
	var target: Vector2i = _adjacent_empty(snapshot, unit)
	var occupy: OccupyObjectiveCondition = _occupy([rifles[0].current_hex])
	var exit: ExitUnitsCondition = ExitUnitsCondition.new()
	exit.team = planner.team
	exit.state = ExitUnitsState.new()
	exit.state.exit_hexes = [target]
	exit.state.units_exited = [unit]
	var goals: ScenarioGoalDirector = ScenarioGoalDirector.new()
	goals.configure(planner.team, [occupy, exit], PositionProfile.Mode.ASSAULT)
	planner.receive_mission_order(goals.initial_order(planner, MissionOrder.new(), 300.0))
	var old: ScenarioGoalTask = ScenarioGoalTask.new()
	old.kind = ScenarioGoalTask.Kind.EXIT
	old.condition = exit
	old.hex = target
	old.key = "counted_exit_bound"
	goals.assignments[unit] = old
	planner.goal_assignments[unit] = old
	var query: PositionQuery = PositionQuery.new()
	query.unit = unit
	query.team = unit.team
	query.snapshot = snapshot
	query.objective_hex = target
	query.profile = PositionProfile.for_mode(PositionProfile.Mode.ADVANCE)
	query.goal_destination_required = true
	var result: PositionResult = PositionQueryService.query_positions(query)
	_check(result.is_valid() and planner.executor.execute(result), "A goal squad begins a real accepted bound")
	planner.position_stability.accepted(result, 60.0)
	var order_id: int = unit.action_controller.action_order_id
	goals.update(planner, 300.0, 61.0)
	_check(goals.assignments.has(unit) and goals.assignments[unit] == old and unit.action_controller.action_order_id == order_id and unit.movement.target_hex == target, "A counted exit squad finishes its bound before receiving another duty")
	planner.change_scenario_objective(rifles[1].current_hex)
	planner._sync_position_mission()
	_check(planner.position_stability.orders.has(unit), "Changing the strategic objective preserves accepted physical orders")
	planner.executor.cancel(unit, true)
	unit.give_hold_order()


func _test_enemy_knowledge() -> void:
	var destroy: DestroyUnitsCondition = DestroyUnitsCondition.new()
	destroy.team = planner.team
	var goals: ScenarioGoalDirector = ScenarioGoalDirector.new()
	goals.configure(planner.team, [destroy], PositionProfile.Mode.ASSAULT)
	goals.initial_order(planner, MissionOrder.new(), 300.0)
	_check(goals.primary == null and goals.tasks.is_empty() and not goals.diagnostics.is_empty(), "Destruction goals do not acquire hidden enemy locations")
	var enemy: Unit = Globals.get_units_for_team(Globals.get_enemy_team(planner.team))[0]
	var original: Vector2i = enemy.current_hex
	var contact: InfluenceContact = InfluenceContact.new()
	contact.unit = enemy
	contact.hex = original
	contact.observed = false
	controller.influence_map_controller.snapshot.defensive_contacts[planner.team] = [contact]
	_set_hex(enemy, Vector2i(25, 20))
	goals.initial_order(planner, MissionOrder.new(), 300.0)
	_check(goals.primary != null and goals.primary.hex == original, "Hunting uses a remembered contact hex, never the hidden squad's live hex")
	_set_hex(enemy, original)


func _test_recovered_defender() -> void:
	var unit: Unit = rifles[2]
	var snapshot: InfluenceSnapshot = controller.influence_map_controller.snapshot
	var enemy: Unit = Globals.get_units_for_team(Globals.get_enemy_team(planner.team))[0]
	var original: Vector2i = enemy.current_hex
	var target: Vector2i = _adjacent_empty(snapshot, unit)
	_set_hex(enemy, target)
	var contact: InfluenceContact = InfluenceContact.new()
	contact.unit = enemy
	contact.hex = target
	contact.observed = true
	snapshot.contacts[planner.team] = [contact]
	snapshot.defensive_contacts[planner.team] = [contact]
	var result: DefensePositionResult = DefensePositionResult.new()
	result.unit = unit
	result.status = PositionResult.Status.ACCEPTED
	result.profile_mode = PositionProfile.Mode.ASSAULT
	result.position_profile = PositionProfile.for_mode(PositionProfile.Mode.ASSAULT)
	result.position_profile.enter_suppressed_enemy_hex = true
	result.position_profile.avoid_unsuppressed_defenders = true
	result.objective_hex = target
	result.target_hex = target
	result.should_move = true
	result.path = [unit.current_hex, target]
	result.features = {"scenario_goal": "stale_assault", "press_attack": true}
	planner.squad_assignments[unit] = {"result": result}
	var order_id: int = unit.action_controller.action_order_id
	planner._issue_order(unit)
	_check(unit.action_controller.action_order_id == order_id and not planner.executor.pending.has(unit), "A recovered defender invalidates stale goal-assault advice before execution")
	_set_hex(enemy, original)
	snapshot.contacts[planner.team] = []
	snapshot.defensive_contacts[planner.team] = []


func _test_denial_switch() -> void:
	var owner: Globals.Team = Globals.get_enemy_team(planner.team)
	var destroy: DestroyUnitsCondition = DestroyUnitsCondition.new()
	destroy.team = owner
	destroy.outcome_level = VictoryCondition.OutcomeLevel.MINOR
	destroy.required_unit_count = 100
	var exit: ExitUnitsCondition = ExitUnitsCondition.new()
	exit.team = owner
	exit.outcome_level = VictoryCondition.OutcomeLevel.MINOR
	exit.state = ExitUnitsState.new()
	exit.state.exit_hexes = [Vector2i(11, 13)]
	var goals: ScenarioGoalDirector = ScenarioGoalDirector.new()
	goals.configure(planner.team, [destroy, exit], PositionProfile.Mode.DEFEND)
	goals.initial_order(planner, MissionOrder.new(), 300.0)
	_check(goals.tasks.size() == 1 and goals.tasks[0].kind == ScenarioGoalTask.Kind.PRESERVE, "Denial chooses one remaining bottleneck rather than defending every condition")
	destroy.required_unit_count = 0
	goals.initial_order(planner, MissionOrder.new(), 300.0)
	_check(goals.primary != null and goals.primary.kind == ScenarioGoalTask.Kind.BLOCK_EXIT, "Once destruction is complete, denial switches to the still-unfinished exit condition")


func _adjacent_empty(snapshot: InfluenceSnapshot, unit: Unit) -> Vector2i:
	var graph: AStar2D = snapshot.routes[unit.team]
	var origin: int = snapshot.point_ids[unit.team][unit.current_hex]
	for id: int in graph.get_point_connections(origin):
		var hex: Vector2i = LOSHelper.ground_layer.local_to_map(graph.get_point_position(id))
		if not graph.is_point_disabled(id) and LOSHelper.find_units_at(hex).is_empty():
			return hex
	return Vector2i(-999, -999)


func _set_hex(unit: Unit, hex: Vector2i) -> void:
	unit.current_hex = hex
	unit.current_cube = LOSHelper.ground_layer.map_to_cube(hex)
	unit.position = LOSHelper.ground_layer.map_to_local(hex)
	unit.movement.is_moving = false
	unit.is_moving = false
	unit.movement.target_hex = hex
	unit.movement.target_position = unit.position


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	if node is Timer:
		(node as Timer).stop()
	for child: Node in node.get_children():
		_freeze(child)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
