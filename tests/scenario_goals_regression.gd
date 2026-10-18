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
	# These squad-allocation checks exercise one platoon; company allocation has its own suite.
	var headquarters_found: bool = false
	for child: Node in scenario.get_units():
		var unit: Unit = child as Unit
		if unit == null or unit.team != Globals.Team.AXIS:
			continue
		if HqSupportPositionPolicy.is_headquarters(unit):
			if headquarters_found:
				unit.queue_free()
				continue
			headquarters_found = true
		unit.platoon = 1
		unit.formation_id = 1
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
	var authored_fallback: HoldToExitFallbackPolicy = HoldToExitFallbackPolicy.new()
	authored_fallback.hold_condition = occupation
	authored_fallback.exit_condition = exit
	scenario.ai_fallback_policies = [authored_fallback]
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
	_check(controller._ai_goal_directors[Globals.Team.ALLIES].fallback_policies == [authored_fallback] and planner.goal_director.fallback_policies.is_empty(), "Match setup loads explicit policies for their owning side only")
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
	_test_fallback_authoring()
	_test_hold_to_exit_fallback()
	_test_counter_exit_fallback_gate()
	_test_fallback_minimum_force()
	_test_multi_objective_fallback()
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
	_check(goals.assignments.size() == 3 and goals.assignments[rifles[2]].kind == ScenarioGoalTask.Kind.EXIT, "Distinct squads receive exit and occupation duties in one winning package: " + str(goals.diagnostics))
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
	snapshot._forecast_jobs.clear()
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


func _fallback_exit(hex: Vector2i) -> ExitUnitsCondition:
	var exit: ExitUnitsCondition = ExitUnitsCondition.new()
	exit.team = planner.team
	exit.outcome_level = VictoryCondition.OutcomeLevel.MINOR
	exit.test_at_scenario_end = true
	exit.state = ExitUnitsState.new()
	exit.state.exit_hexes = [hex]
	return exit


func _test_fallback_authoring() -> void:
	var hold: OccupyObjectiveCondition = _occupy([rifles[0].current_hex])
	var exit: ExitUnitsCondition = _fallback_exit(rifles[1].current_hex)
	var policy: HoldToExitFallbackPolicy = HoldToExitFallbackPolicy.new()
	policy.hold_condition = hold
	policy.exit_condition = exit
	policy.minimum_combat_squads = 2
	var source: Scenario = load("res://scenes/scenarios/scenario.tscn").instantiate()
	source.victory_conditions = [hold, exit]
	source.ai_fallback_policies = [policy]
	var packed: PackedScene = PackedScene.new()
	_check(packed.pack(source) == OK and ResourceSaver.save(packed, "user://hold_to_exit_fixture.tscn") == OK, "A Scenario can save an explicit hold-to-exit link")
	var reloaded: PackedScene = ResourceLoader.load("user://hold_to_exit_fixture.tscn", "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var restored: Scenario = reloaded.instantiate()
	var copy: HoldToExitFallbackPolicy = restored.ai_fallback_policies[0]
	_check(copy.hold_condition == restored.victory_conditions[0] and copy.exit_condition == restored.victory_conditions[1], "Scene reload preserves links to the actual victory conditions, not independent copies")
	_check(copy.configuration_error(restored.victory_conditions) == "" and copy.withdraw_entire_force and copy.minimum_combat_squads == 2, "Restored policy preserves its operational force threshold and whole-force withdrawal")
	restored.free()
	source.free()
	var goals: ScenarioGoalDirector = ScenarioGoalDirector.new()
	goals.configure(planner.team, [hold], PositionProfile.Mode.DEFEND, [policy])
	goals.initial_order(planner, MissionOrder.new(), 10000.0)
	_check(goals.fallback_policies.is_empty() and not goals.diagnostics.is_empty(), "A link to an exit outside the Scenario's conditions is rejected with a diagnostic")
	exit.team = Globals.get_enemy_team(planner.team)
	goals.configure(planner.team, [hold, exit], PositionProfile.Mode.DEFEND, [policy])
	_check(goals.fallback_policies.is_empty(), "A fallback cannot use the opponent's exit victory condition")
	exit.team = planner.team
	exit.outcome_level = VictoryCondition.OutcomeLevel.MAJOR
	goals.configure(planner.team, [hold, exit], PositionProfile.Mode.DEFEND, [policy])
	_check(goals.fallback_policies.is_empty(), "Hold and exit cannot be alternatives inside the same AND victory package")
	exit.outcome_level = VictoryCondition.OutcomeLevel.MINOR
	policy.enabled = false
	goals.configure(planner.team, [hold, exit], PositionProfile.Mode.DEFEND, [policy])
	_check(goals.fallback_policies.is_empty(), "An explicitly disabled policy leaves ordinary goal selection intact")


func _test_hold_to_exit_fallback() -> void:
	var snapshot: InfluenceSnapshot = controller.influence_map_controller.snapshot
	snapshot.contacts[planner.team] = []
	snapshot.defensive_contacts[planner.team] = []
	planner.executor.cancel_all(true)
	planner.position_stability.clear()
	for unit: Unit in planner.squads:
		unit.give_hold_order()
		_set_hex(unit, unit.current_hex)
		unit.stress_system.state = UnitStates.MoraleState.NORMAL
		unit.broken = false
		unit.in_close_combat = false
	var target: Vector2i = _adjacent_empty(snapshot, rifles[2])
	var hold: OccupyObjectiveCondition = _occupy([rifles[0].current_hex])
	var exit: ExitUnitsCondition = _fallback_exit(target)
	var policy: HoldToExitFallbackPolicy = HoldToExitFallbackPolicy.new()
	policy.hold_condition = hold
	policy.exit_condition = exit
	var conditions: Array[VictoryCondition] = [hold, exit]
	var goals: ScenarioGoalDirector = ScenarioGoalDirector.new()
	goals.configure(planner.team, conditions, PositionProfile.Mode.DEFEND, [policy])
	planner.receive_mission_order(goals.initial_order(planner, MissionOrder.new(), 10000.0))
	goals.update(planner, 10000.0, 100.0)
	_check(goals.active_fallback == null and goals.primary.kind == ScenarioGoalTask.Kind.OCCUPY, "A feasible hold stays primary even though a secondary exit is available")
	hold.required_unit_count = 99
	goals.update(planner, 10000.0, 101.0)
	goals.update(planner, 10000.0, 105.0)
	_check(goals.active_fallback == null and goals.primary.kind == ScenarioGoalTask.Kind.OCCUPY, "Temporary hold infeasibility does not immediately release an exit mission")
	hold.required_unit_count = 1
	goals.update(planner, 10000.0, 106.0)
	hold.required_unit_count = 99
	goals.update(planner, 10000.0, 107.0)
	goals.update(planner, 10000.0, 110.0)
	_check(goals.active_fallback == null, "Recovery resets the continuous fallback confirmation timer")
	var bound_unit: Unit = rifles[0]
	var bound_hex: Vector2i = _adjacent_empty(snapshot, bound_unit)
	var bound_query: PositionQuery = PositionQuery.new()
	bound_query.unit = bound_unit
	bound_query.team = planner.team
	bound_query.snapshot = snapshot
	bound_query.profile = PositionProfile.for_mode(PositionProfile.Mode.ADVANCE)
	bound_query.objective_hex = bound_hex
	bound_query.goal_destination_required = true
	var bound: PositionResult = PositionQueryService.query_positions(bound_query)
	_check(bound.is_valid() and planner.executor.execute(bound), "A hold squad starts a real accepted bound before fallback confirmation")
	planner.position_stability.accepted(bound, 110.0)
	var previous_task: ScenarioGoalTask = goals.assignments[bound_unit]
	var previous_order: int = bound_unit.action_controller.action_order_id
	goals.update(planner, 10000.0, 112.0)
	_check(goals.active_fallback == policy and goals.primary.kind == ScenarioGoalTask.Kind.EXIT and planner.current_order.objective_hex == target, "Confirmed inability to hold commits the platoon to the linked exit")
	_check(goals.assignments[bound_unit] == previous_task and planner.executor.pending.has(bound_unit) and bound_unit.action_controller.action_order_id == previous_order and bound_unit.movement.target_hex == bound_hex, "Withdrawal leaves a squad's accepted safe bound intact")
	# Establish the bound's endpoint without advancing the frozen combat fixture.
	planner.executor.cancel(bound_unit, true)
	bound_unit.give_hold_order()
	_set_hex(bound_unit, bound_hex)
	snapshot.positions[bound_unit] = bound_hex
	goals.update(planner, 10000.0, 112.5)
	_check(goals.assignments.has(bound_unit) and goals.assignments[bound_unit].kind == ScenarioGoalTask.Kind.EXIT, "An established squad replaces its obsolete hold duty with withdrawal")
	var all_withdrawing: bool = goals.assignments.size() == planner.squads.size()
	for unit: Unit in planner.squads:
		all_withdrawing = all_withdrawing and goals.assignments.has(unit) and goals.assignments[unit].withdrawal
	_check(all_withdrawing and goals.primary.exit_capacity() >= planner.squads.size(), "Whole-force withdrawal assigns rifles, MG, and HQ sufficient exit capacity")
	planner._planning_snapshot = snapshot
	planner._planning_reservations = {}
	planner._planning_requests.clear()
	planner._build_planning_requests(planner.squads)
	var hq_exits: int = 0
	for request: Dictionary in planner._planning_requests:
		var query: PositionQuery = request["query"]
		if HqSupportPositionPolicy.is_headquarters(query.unit):
			if query.goal_key == goals.primary.key and query.goal_destination_required and query.profile.mode == PositionProfile.Mode.ADVANCE:
				hq_exits += 1
				var advice: PositionResult = PositionQueryService.query_positions(query)
				_check(advice.is_valid() and advice.target_hex == target and advice.profile_mode == PositionProfile.Mode.ADVANCE, "HQ's exact exit duty survives the actual position-query job")
				_check(advice.is_valid() and planner.executor.execute(advice), "HQ can begin a real withdrawal move to the exit")
				planner.executor.cancel(query.unit, true)
				query.unit.give_hold_order()
				_set_hex(query.unit, query.unit.current_hex)
	_check(hq_exits == 1 and planner._planning_requests.size() == planner.squads.size(), "The real planner gives HQ one exact exit request instead of a competing support request: exits %d; requests %d; squads %d" % [hq_exits, planner._planning_requests.size(), planner.squads.size()])
	planner._cancel_plan()
	_check(goals.primary.reason.contains("Too few combat squads"), "Withdrawal advice explains why the linked hold was abandoned")
	hold.required_unit_count = 1
	hold.state.victory_conditions_met[hold.state.hexes[0]] = true
	goals.update(planner, 10000.0, 113.0)
	_check(goals.active_fallback == policy and goals.primary.kind == ScenarioGoalTask.Kind.EXIT, "A recovered objective cannot reverse an accepted withdrawal")
	var pinned: Unit = rifles[1]
	pinned.stress_system.state = UnitStates.MoraleState.PINNED
	goals.update(planner, 10000.0, 114.0)
	_check(not goals.assignments.has(pinned), "A pinned withdrawing squad receives no impossible movement assignment")
	pinned.stress_system.state = UnitStates.MoraleState.NORMAL
	goals.update(planner, 10000.0, 115.0)
	_check(goals.assignments.has(pinned) and goals.assignments[pinned].kind == ScenarioGoalTask.Kind.EXIT, "A recovered squad joins the already committed withdrawal")
	exit.state.units_exited.assign(planner.squads)
	goals.update(planner, 10000.0, 116.0)
	_check(goals.assignments.size() == planner.squads.size() and goals.primary.kind == ScenarioGoalTask.Kind.EXIT, "Counted exit squads retain withdrawal duties until the scenario ends")
	var original_director: ScenarioGoalDirector = controller._ai_goal_directors[planner.team]
	controller._ai_goal_directors[planner.team] = goals
	planner.goal_director = goals
	controller.set_team_ai_mode(planner.team, PositionProfile.Mode.ASSAULT)
	_check(goals.active_fallback == policy and planner.current_order.objective_hex == target, "Changing ATTACK/DEFEND does not clear the accepted strategic fallback")
	controller.set_team_ai_enabled(planner.team, false)
	controller.set_team_ai_enabled(planner.team, true)
	_check(goals.active_fallback == policy and planner.current_order.objective_hex == target, "Turning AI OFF and ON preserves the withdrawal commitment")
	controller._ai_goal_directors[planner.team] = original_director
	planner.goal_director = original_director
	planner.executor.cancel_all(true)
	planner.position_stability.clear()
	exit.state.units_exited.clear()
	hold.state.victory_conditions_met[hold.state.hexes[0]] = false
	goals.configure(planner.team, conditions, PositionProfile.Mode.DEFEND, [policy])
	planner.receive_mission_order(goals.initial_order(planner, MissionOrder.new(), 10.0))
	_check(goals.active_fallback == policy and goals.primary.kind == ScenarioGoalTask.Kind.EXIT, "An unsecured hold releases withdrawal immediately when only the reserved exit window remains")
	hold.state.victory_conditions_met[hold.state.hexes[0]] = true
	goals.configure(planner.team, conditions, PositionProfile.Mode.DEFEND, [policy])
	planner.receive_mission_order(goals.initial_order(planner, MissionOrder.new(), 10.0))
	_check(goals.active_fallback == null and goals.primary.kind == ScenarioGoalTask.Kind.OCCUPY, "A secured hold is not abandoned simply because the deadline approaches")
	hold.state.victory_conditions_met[hold.state.hexes[0]] = false
	goals.update(planner, 10000.0, 200.0)
	goals.update(planner, 10000.0, 205.0)
	_check(goals.active_fallback == policy and goals.fallback_reason.contains("lost"), "Sustained loss of a previously secured objective activates the explicit fallback")
	policy.withdraw_entire_force = false
	exit.state.units_exited.clear()
	goals.update(planner, 10000.0, 206.0)
	_check(goals.assignments.size() == exit.required_unit_count and not goals.primary.withdrawal, "Quota-only fallback assigns only the remaining distinct exit requirement")
	hold.state = null
	goals.configure(planner.team, conditions, PositionProfile.Mode.DEFEND, [policy])
	goals.initial_order(planner, MissionOrder.new(), 10000.0)
	_check(goals.active_fallback == null and not goals.diagnostics.is_empty(), "Missing hold markers disable explicit fallback activation and report the configuration problem")


func _has_goal_task(goals: ScenarioGoalDirector, kind: ScenarioGoalTask.Kind, condition: VictoryCondition) -> bool:
	for task: ScenarioGoalTask in goals.tasks:
		if task.kind == kind and task.condition == condition:
			return true
	return false


func _test_counter_exit_fallback_gate() -> void:
	var snapshot: InfluenceSnapshot = controller.influence_map_controller.snapshot
	planner.executor.cancel_all(true)
	planner.position_stability.clear()
	for unit: Unit in planner.squads:
		unit.give_hold_order()
		_set_hex(unit, unit.current_hex)
	var hold: OccupyObjectiveCondition = _occupy([rifles[0].current_hex])
	var exit: ExitUnitsCondition = _fallback_exit(_adjacent_empty(snapshot, rifles[2]))
	var prevention: PreventEnemyExitCondition = PreventEnemyExitCondition.new()
	prevention.team = Globals.get_enemy_team(planner.team)
	prevention.outcome_level = VictoryCondition.OutcomeLevel.MINOR
	prevention.state = ExitUnitsState.new()
	prevention.state.exit_hexes = exit.state.exit_hexes.duplicate()
	var conditions: Array[VictoryCondition] = [hold, exit, prevention]
	var policy: HoldToExitFallbackPolicy = HoldToExitFallbackPolicy.new()
	policy.hold_condition = hold
	policy.exit_condition = exit
	var goals: ScenarioGoalDirector = ScenarioGoalDirector.new()
	goals.configure(planner.team, conditions, PositionProfile.Mode.DEFEND)
	planner.receive_mission_order(goals.initial_order(planner, MissionOrder.new(), 10000.0))
	goals.update(planner, 10000.0, 300.0)
	var early_exit: bool = false
	for task: ScenarioGoalTask in goals.assignments.values():
		early_exit = early_exit or (task.kind == ScenarioGoalTask.Kind.EXIT and task.condition == prevention)
	_check(early_exit, "Without a fallback policy, a spare squad still receives the ordinary counter-exit duty")
	goals.configure(planner.team, conditions, PositionProfile.Mode.DEFEND, [policy])
	planner.receive_mission_order(goals.initial_order(planner, MissionOrder.new(), 10000.0))
	goals.update(planner, 10000.0, 301.0)
	_check(goals.active_fallback == null and not _has_goal_task(goals, ScenarioGoalTask.Kind.EXIT, prevention), "A valid hold-to-exit policy suppresses early counter-exit tasks while holding")
	var premature_assignment: bool = false
	for task: ScenarioGoalTask in goals.assignments.values():
		premature_assignment = premature_assignment or task.kind == ScenarioGoalTask.Kind.EXIT
	_check(not premature_assignment and not goals.diagnostics.is_empty(), "Spare squads receive no exit assignment while the fallback is deferred")
	hold.required_unit_count = 99
	goals.update(planner, 10000.0, 302.0)
	goals.update(planner, 10000.0, 306.0)
	_check(goals.active_fallback == null and not _has_goal_task(goals, ScenarioGoalTask.Kind.EXIT, prevention), "Counter-exit duties cannot bypass the fallback confirmation period")
	goals.update(planner, 10000.0, 307.0)
	_check(goals.active_fallback == policy and _has_goal_task(goals, ScenarioGoalTask.Kind.EXIT, exit) and not _has_goal_task(goals, ScenarioGoalTask.Kind.EXIT, prevention), "Confirmed fallback releases the linked exit without a duplicate counter-exit mission")
	exit.record_unit_entry(rifles[0], exit.state.exit_hexes[0])
	prevention.record_unit_entry(rifles[0], exit.state.exit_hexes[0])
	_check(exit.is_condition_met() and not prevention.is_condition_met(), "The authorized escape satisfies the owning side's exit and denies enemy prevention together")
	hold.required_unit_count = 1
	exit.state.units_exited.clear()
	prevention.state.units_exited.clear()
	policy.enabled = false
	goals.configure(planner.team, conditions, PositionProfile.Mode.DEFEND, [policy])
	goals.initial_order(planner, MissionOrder.new(), 10000.0)
	_check(_has_goal_task(goals, ScenarioGoalTask.Kind.EXIT, prevention), "A disabled policy does not suppress ordinary counter-exit behavior")
	policy.enabled = true
	goals.configure(planner.team, [hold, prevention], PositionProfile.Mode.DEFEND, [policy])
	goals.initial_order(planner, MissionOrder.new(), 10000.0)
	_check(_has_goal_task(goals, ScenarioGoalTask.Kind.EXIT, prevention), "An invalid policy link cannot silently forbid an otherwise valid exit duty")
	var other_prevention: PreventEnemyExitCondition = PreventEnemyExitCondition.new()
	other_prevention.team = prevention.team
	other_prevention.outcome_level = VictoryCondition.OutcomeLevel.MINOR
	other_prevention.objective_id = PreventEnemyExitCondition.ObjectiveId.A
	other_prevention.state = ExitUnitsState.new()
	other_prevention.state.exit_hexes = hold.state.hexes.duplicate()
	goals.configure(planner.team, [hold, exit, other_prevention], PositionProfile.Mode.DEFEND, [policy])
	goals.initial_order(planner, MissionOrder.new(), 10000.0)
	_check(_has_goal_task(goals, ScenarioGoalTask.Kind.EXIT, other_prevention), "The fallback gate applies to its linked marker group rather than unrelated objectives")
	var enemy_exit: ExitUnitsCondition = _fallback_exit(rifles[1].current_hex)
	enemy_exit.team = prevention.team
	goals.configure(planner.team, [hold, exit, prevention, enemy_exit], PositionProfile.Mode.DEFEND, [policy])
	goals.initial_order(planner, MissionOrder.new(), 10000.0)
	_check(_has_goal_task(goals, ScenarioGoalTask.Kind.BLOCK_EXIT, enemy_exit) and not _has_goal_task(goals, ScenarioGoalTask.Kind.EXIT, prevention), "Deferred counter-exit leaves another necessary enemy condition available for denial")


func _test_fallback_minimum_force() -> void:
	var snapshot: InfluenceSnapshot = controller.influence_map_controller.snapshot
	var alive_before: Dictionary[Unit, bool] = {}
	var headquarters: Unit
	planner.executor.cancel_all(true)
	planner.position_stability.clear()
	for unit: Unit in planner.squads:
		alive_before[unit] = unit.alive
		unit.give_hold_order()
		_set_hex(unit, unit.current_hex)
		if HqSupportPositionPolicy.is_headquarters(unit):
			headquarters = unit
	var hold: OccupyObjectiveCondition = _occupy([rifles[0].current_hex])
	hold.state.victory_conditions_met[hold.state.hexes[0]] = true
	var exit: ExitUnitsCondition = _fallback_exit(_adjacent_empty(snapshot, rifles[2]))
	var policy: HoldToExitFallbackPolicy = HoldToExitFallbackPolicy.new()
	policy.hold_condition = hold
	policy.exit_condition = exit
	policy.minimum_combat_squads = 2
	var goals: ScenarioGoalDirector = ScenarioGoalDirector.new()
	goals.configure(planner.team, [hold, exit], PositionProfile.Mode.DEFEND, [policy])
	planner.receive_mission_order(goals.initial_order(planner, MissionOrder.new(), 10000.0))
	for unit: Unit in planner.squads:
		if not HqSupportPositionPolicy.is_headquarters(unit) and unit != rifles[0] and unit != rifles[1]:
			unit.alive = false
	goals.update(planner, 10000.0, 400.0)
	goals.update(planner, 10000.0, 406.0)
	_check(goals.active_fallback == null, "Exactly the configured minimum of combat squads continues holding")
	rifles[1].alive = false
	goals.update(planner, 10000.0, 407.0)
	goals.update(planner, 10000.0, 411.0)
	_check(goals.active_fallback == null, "A force-strength deficit obeys the continuous confirmation period")
	goals.update(planner, 10000.0, 412.0)
	_check(goals.active_fallback == policy and goals.fallback_reason.contains("remaining: 1"), "One combat squad plus HQ activates the minimum-force fallback even while the objective is secured")
	_check(hold.is_condition_met() and hold.required_unit_count == 1, "Operational withdrawal does not alter the one-unit occupation victory requirement")
	_check(goals.assignments.has(rifles[0]) and goals.assignments.has(headquarters) and goals.assignments[rifles[0]].kind == ScenarioGoalTask.Kind.EXIT and goals.assignments[headquarters].kind == ScenarioGoalTask.Kind.EXIT, "The surviving rifle and HQ both receive withdrawal duties")
	rifles[0].stress_system.state = UnitStates.MoraleState.PINNED
	goals.update(planner, 10000.0, 413.0)
	_check(not goals.assignments.has(rifles[0]), "A depletion-triggered withdrawal still cannot move a pinned survivor")
	rifles[0].stress_system.state = UnitStates.MoraleState.NORMAL
	goals.update(planner, 10000.0, 414.0)
	_check(goals.assignments.has(rifles[0]) and goals.assignments[rifles[0]].kind == ScenarioGoalTask.Kind.EXIT, "The recovered survivor joins the committed withdrawal")
	rifles[0].alive = false
	var hq_hex: Vector2i = headquarters.current_hex
	_set_hex(headquarters, hold.state.hexes[0])
	snapshot.positions[headquarters] = headquarters.current_hex
	hold.advance_time(hold.required_time_s)
	_check(hold.is_condition_met(), "HQ alone can still meet the authored occupation rule in the fixture")
	goals.configure(planner.team, [hold, exit], PositionProfile.Mode.DEFEND, [policy])
	planner.receive_mission_order(goals.initial_order(planner, MissionOrder.new(), 10000.0))
	goals.update(planner, 10000.0, 420.0)
	goals.update(planner, 10000.0, 425.0)
	_check(goals.active_fallback == policy and goals.fallback_reason.contains("remaining: 0") and goals.assignments.size() == 1 and goals.assignments.has(headquarters), "HQ is excluded from the combat threshold and withdraws when it is the only survivor: " + str(goals.assignments.size()) + "; " + goals.fallback_reason)
	planner._planning_snapshot = snapshot
	planner._planning_reservations = {}
	planner._planning_requests.clear()
	planner._add_goal_request(headquarters, goals.assignments[headquarters])
	var query: PositionQuery = planner._planning_requests[0]["query"]
	var advice: PositionResult = PositionQueryService.query_positions(query)
	_check(advice.is_valid() and advice.target_hex == exit.state.exit_hexes[0] and planner.executor.execute(advice), "The lone HQ can execute a real exit move after the force-strength fallback")
	planner.executor.cancel(headquarters, true)
	headquarters.give_hold_order()
	_set_hex(headquarters, hq_hex)
	snapshot.positions[headquarters] = hq_hex
	planner._cancel_plan()
	rifles[0].alive = true
	policy.minimum_combat_squads = 0
	goals.configure(planner.team, [hold, exit], PositionProfile.Mode.DEFEND, [policy])
	planner.receive_mission_order(goals.initial_order(planner, MissionOrder.new(), 10000.0))
	goals.update(planner, 10000.0, 430.0)
	goals.update(planner, 10000.0, 436.0)
	_check(goals.active_fallback == null, "Zero disables the optional strength trigger and retains existing hold behavior")
	policy.minimum_combat_squads = -1
	_check(policy.configuration_error([hold, exit]) != "", "A negative minimum-force threshold is rejected")
	for unit: Unit in alive_before:
		unit.alive = alive_before[unit]


func _test_multi_objective_fallback() -> void:
	var snapshot: InfluenceSnapshot = controller.influence_map_controller.snapshot
	var contacts_before: Array[InfluenceContact] = snapshot.get_defensive_contacts(planner.team)
	var alive_before: Dictionary[Unit, bool] = {}
	var personnel_before: Dictionary[Unit, int] = {}
	for unit: Unit in planner.squads:
		alive_before[unit] = unit.alive
		personnel_before[unit] = unit.members_alive
		unit.give_hold_order()
		_set_hex(unit, unit.current_hex)
		unit.stress_system.state = UnitStates.MoraleState.NORMAL
	planner.executor.cancel_all(true)
	planner.position_stability.clear()
	var second_hex: Vector2i = rifles[1].current_hex
	var first: OccupyObjectiveCondition = _occupy([rifles[0].current_hex])
	var second: OccupyObjectiveCondition = _occupy([second_hex])
	var third: OccupyObjectiveCondition = _occupy([_adjacent_empty(snapshot, rifles[2])])
	var duplicate: OccupyObjectiveCondition = _occupy(first.state.hexes)
	var exit: ExitUnitsCondition = _fallback_exit(third.state.hexes[0])
	var policy: HoldToExitFallbackPolicy = HoldToExitFallbackPolicy.new()
	policy.hold_condition = third
	policy.exit_condition = exit
	policy.minimum_combat_squads = 2
	var conditions: Array[VictoryCondition] = [first, second, third, duplicate, exit]
	var goals: ScenarioGoalDirector = ScenarioGoalDirector.new()
	snapshot.defensive_contacts[planner.team] = []
	goals.configure(planner.team, conditions, PositionProfile.Mode.DEFEND, [policy])
	planner.receive_mission_order(goals.initial_order(planner, MissionOrder.new(), 0.0))
	goals.update(planner, 0.0, 500.0)
	goals.update(planner, 0.0, 506.0)
	_check(goals.active_fallback == null, "Initially unsecured objectives and a missed hold deadline are not captured objectives")
	var enemies: Array[Unit] = Globals.get_units_for_team(Globals.get_enemy_team(planner.team))
	var capture: InfluenceContact = InfluenceContact.new()
	capture.unit = enemies[0]
	capture.hex = third.state.hexes[0]
	capture.observed = true
	third.state.victory_conditions_met[capture.hex] = true
	goals.update(planner, 10000.0, 507.0)
	third.state.victory_conditions_met[capture.hex] = false
	snapshot.defensive_contacts[planner.team] = [capture]
	goals.update(planner, 10000.0, 508.0)
	goals.update(planner, 10000.0, 514.0)
	_check(goals.active_fallback == null, "Losing a previously secured linked objective does not abandon a multi-objective defense")
	_check(goals.assignments.has(rifles[0]) and goals.assignments[rifles[0]].hex == first.state.hexes[0] and goals.assignments.has(rifles[1]) and goals.assignments[rifles[1]].hex == second_hex, "Intact objective garrisons are allocated before the local recapture duty")
	_check(goals.assignments.has(rifles[2]) and goals.assignments[rifles[2]].hex == capture.hex, "A nearby free rifle receives the counterattack duty while other objectives remain garrisoned")
	for unit: Unit in planner.squads:
		if unit != rifles[0] and not HqSupportPositionPolicy.is_headquarters(unit):
			unit.alive = false
	goals.update(planner, 0.0, 515.0)
	goals.update(planner, 0.0, 521.0)
	_check(goals.active_fallback == null, "Low strength and an expired exit window cannot bypass the two-objective loss requirement")
	for unit: Unit in alive_before:
		unit.alive = alive_before[unit]
	_set_hex(rifles[1], rifles[2].current_hex)
	var second_capture: InfluenceContact = InfluenceContact.new()
	second_capture.unit = enemies[1]
	second_capture.hex = second_hex
	second_capture.observed = true
	snapshot.defensive_contacts[planner.team] = [capture, second_capture]
	goals.update(planner, 0.0, 522.0)
	goals.update(planner, 0.0, 528.0)
	_check(goals.active_fallback == null, "Two captured objectives do not cause a healthy force to flee, even at the deadline")
	for unit: Unit in planner.squads:
		if unit != rifles[0] and not HqSupportPositionPolicy.is_headquarters(unit):
			unit.alive = false
	goals.update(planner, 10000.0, 529.0)
	goals.update(planner, 10000.0, 533.0)
	_check(goals.active_fallback == null, "Combined objective losses and low strength still require continuous confirmation")
	rifles[1].alive = true
	_set_hex(rifles[1], second_hex)
	snapshot.defensive_contacts[planner.team] = [capture]
	goals.update(planner, 10000.0, 534.0)
	_check(goals.active_fallback == null and goals._fallback_pending_since.is_empty(), "Recapturing an objective resets withdrawal confirmation before its victory hold timer completes")
	rifles[1].alive = false
	snapshot.defensive_contacts[planner.team] = [capture, second_capture]
	goals.update(planner, 10000.0, 535.0)
	# Loss of sight does not erase a confirmed enemy capture.
	snapshot.defensive_contacts[planner.team] = []
	goals.update(planner, 10000.0, 539.0)
	_check(goals.active_fallback == null, "A fresh pair of losses starts a fresh confirmation period")
	goals.update(planner, 10000.0, 540.0)
	_check(goals.active_fallback == policy and goals.fallback_reason.contains("2/3 objectives lost"), "Two distinct captured objectives plus sustained low strength release whole-force withdrawal")
	_check(goals.assignments.has(rifles[0]) and goals.assignments[rifles[0]].withdrawal, "The surviving garrison receives an authorized exit duty after the defense breaks")
	for unit: Unit in alive_before:
		unit.alive = alive_before[unit]
	policy.minimum_combat_squads = 0
	goals.configure(planner.team, conditions, PositionProfile.Mode.DEFEND, [policy])
	snapshot.defensive_contacts[planner.team] = []
	planner.receive_mission_order(goals.initial_order(planner, MissionOrder.new(), 10000.0))
	_set_hex(rifles[1], rifles[2].current_hex)
	snapshot.defensive_contacts[planner.team] = [capture, second_capture]
	for unit: Unit in planner.squads:
		if not HqSupportPositionPolicy.is_headquarters(unit):
			unit.members_alive = 1
	goals.update(planner, 10000.0, 550.0)
	goals.update(planner, 10000.0, 555.0)
	_check(goals.active_fallback == policy, "Relative personnel losses can break the defense even when the number of surviving squads is unchanged")
	for unit: Unit in personnel_before:
		unit.members_alive = personnel_before[unit]
	_set_hex(rifles[1], second_hex)
	snapshot.defensive_contacts[planner.team] = contacts_before
	policy.minimum_lost_objectives = 1
	_check(policy.configuration_error(conditions) != "", "Multi-objective withdrawal cannot be configured to flee after a single capture")
	policy.minimum_lost_objectives = 2
	policy.withdrawal_strength_ratio = NAN
	_check(policy.configuration_error(conditions) != "", "Invalid relative strength thresholds are rejected")


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
