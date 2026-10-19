extends Node

var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map: Map = world.maps.get_node("Alderbrook3") as Map
	var scenario: Scenario = map.get_scenario(0)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.DEFEND)
	_freeze(main)
	var controller: Node2D = world.game_controller
	var planner: PlatoonAI = controller._ai_director_for_team(Globals.Team.AXIS).platoon_ai
	var defenders: Array[Unit] = Globals.get_units_for_team(Globals.Team.ALLIES)
	var attackers: Array[Unit] = Globals.get_units_for_team(Globals.Team.AXIS)
	_test_escape_corridors(planner, defenders, attackers, controller.influence_map_controller, scenario)
	var rows: Array[int] = [0, 3, 6, 9, 12, 13]
	for index: int in range(defenders.size()):
		var defender: Unit = defenders[index]
		_set_hex(defender, Vector2i(9, rows[index]))
		defender.combat_stats.combat_effectiveness = 1.0
	var weak: Unit = defenders[2]
	weak.combat_stats.combat_effectiveness = 0.02
	var rifles: Array[Unit] = []
	for attacker: Unit in attackers:
		_set_hex(attacker, Vector2i(15, 7))
		Globals.unit_visible_enemies[attacker] = defenders.duplicate()
		if attacker.squad_type == Globals.SquadType.Rifle:
			rifles.append(attacker)
	controller.influence_map_controller.reset_for_match()
	controller.influence_map_controller.set_objective_for_team(planner.team, Vector2i(0, 8))
	controller.influence_map_controller.create_maps(0.0)
	while controller.influence_map_controller.rebuild_pending:
		controller.influence_map_controller._process_los_rebuild()
		controller.influence_map_controller._process_budgeted_rebuild()
	# Isolate front-line control from long-range overwatch in this strategic fixture.
	var snapshot: InfluenceSnapshot = controller.influence_map_controller.snapshot
	snapshot.los = {}
	for influence: InfluenceMap in snapshot.maps.values():
		influence.clear_layer(InfluenceMap.Layer.THREAT)
	var director: ScenarioGoalDirector = planner.goal_director
	director._build_tasks(planner, scenario.duration_s)
	var exit_task: ScenarioGoalTask
	for task: ScenarioGoalTask in director.tasks:
		if task.kind == ScenarioGoalTask.Kind.EXIT:
			exit_task = task
	_check(exit_task != null and exit_task.breach_required, "A sealed RoadBlock front creates a breach duty")
	if exit_task != null:
		_check(exit_task.breach_hex == weak.current_hex, "RoadBlock concentrates on the weakest defended point: selected %s; weak %s" % [exit_task.breach_hex, weak.current_hex])
		planner._planning_snapshot = controller.influence_map_controller.snapshot
		planner.goal_assignments = {rifles[0]: exit_task, rifles[1]: exit_task}
		planner._planning_requests.clear()
		planner._add_goal_request(rifles[0], exit_task)
		var query: PositionQuery = planner._planning_requests[0]["query"]
		_check(query.objective_hex == weak.current_hex and query.profile.mode == PositionProfile.Mode.SUPPORT_BY_FIRE, "Exit attackers engage the blocker with covering fire: objective %s; mode %s" % [query.objective_hex, query.profile.mode])
		_check(not query.goal_destination_required, "A breach plan does not demand movement to the defended exit")
		var approach: PositionResult = PositionQueryService.query_positions(query)
		_check(approach.is_valid() and approach.should_move and LOSHelper.get_hex_distance(approach.target_hex, weak.current_hex) < LOSHelper.get_hex_distance(rifles[0].current_hex, weak.current_hex), "A shadowed breach advances into firing range instead of waiting without a shot")
		director._allocate(planner)
		planner.company_command._assign_roles()
		var maneuver: CompanyPlatoon
		var support: CompanyPlatoon
		for formation: CompanyPlatoon in planner.company_command.platoons.values():
			if formation.task != null and formation.task.breach_required:
				_check(formation.objective == weak.current_hex, "Company platoons share the breach objective")
				planner.company_command._dispatch(formation)
			if formation.role == CompanyPlatoon.Role.MANEUVER:
				maneuver = formation
			elif formation.role == CompanyPlatoon.Role.SUPPORT:
				support = formation
		_check(maneuver != null and support != null, "A blocked column pairs maneuver with a supporting platoon: " + str(planner.company_command.diagnostics))
		if maneuver != null and support != null:
			var supporter: Unit = support.combat_units()[0]
			_set_hex(supporter, Vector2i(12, 6))
			var advice: PositionResult = PositionResult.new()
			advice.unit = supporter
			advice.status = PositionResult.Status.RETAINED
			advice.target_index = 0
			advice.target_hex = supporter.current_hex
			advice.objective_hex = weak.current_hex
			advice.profile_mode = PositionProfile.Mode.SUPPORT_BY_FIRE
			advice.features = {"cover": 0.5, "firing": 1.0}
			supporter.position_advice = advice
			supporter.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
			LOSHelper.los_lookup[supporter.current_hex] = {}
			for defender: Unit in defenders:
				LOSHelper.los_lookup[supporter.current_hex][defender.current_hex] = {"target_cover": 0, "hindrance": 0}
			supporter.setAttackState(Unit.AttackState.MANUAL_TRACK)
			supporter.order(Globals.UnitCmd.FIRE_AT_UNIT, weak)
			_check(TacticalPositionExecutor.select_support_target(supporter, weak.current_hex) == weak, "Covering fire prioritizes the selected breach defender")
			_check(maneuver.planner._has_company_support(), "Established fire on the breach releases the company support gate")
	weak.stress_system.state = STATES.MoraleState.PINNED
	director._build_tasks(planner, scenario.duration_s)
	for task: ScenarioGoalTask in director.tasks:
		if task.kind == ScenarioGoalTask.Kind.EXIT:
			_check(not task.breach_required, "Suppressing the blocker releases the breach as soon as a passage opens")
	director._allocate(planner)
	planner.company_command._assign_roles()
	for formation: CompanyPlatoon in planner.company_command.platoons.values():
		if formation.task != null and formation.task.escape_policy != null:
			_check(formation.role == CompanyPlatoon.Role.WITHDRAW, "An opened passage releases company assault and covering-fire roles")
	weak.stress_system.state = STATES.MoraleState.NORMAL
	_test_clear_exit(planner, rifles, snapshot, exit_task)
	for row: int in [6, 7, 8, 9]:
		_check(controller._is_exit_hex(Globals.Team.AXIS, Vector2i(0, row)), "The road and neighboring western bypass hexes are exits")
	_check(not controller._is_exit_hex(Globals.Team.AXIS, Vector2i(1, 8)), "Leaving the map requires reaching the western boundary")
	Globals.game_started = true
	var count: int = Globals.get_units().size()
	_set_hex(rifles[0], Vector2i(0, 8))
	controller._on_unit_entered_hex(rifles[0], rifles[0].current_hex)
	_check(rifles[0].exited and Globals.get_units().size() == count - 1, "A squad next to the road exits immediately at the western edge")
	var recorded: bool = false
	for condition: VictoryCondition in scenario.victory_conditions:
		if condition is ExitUnitsCondition and condition.team == Globals.Team.AXIS:
			recorded = (condition as ExitUnitsCondition).state.units_exited.has(rifles[0])
	_check(recorded, "The western bypass exit counts toward the Axis result")
	Globals.game_started = false
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("RoadBlock breach match regression failures: ", failures)
	get_tree().quit(failures)


func _test_escape_corridors(planner: PlatoonAI, defenders: Array[Unit], attackers: Array[Unit], controller: InfluenceMapController, scenario: Scenario) -> void:
	for unit: Unit in attackers:
		Globals.unit_visible_enemies[unit] = defenders.duplicate()
	controller.reset_for_match()
	controller.create_maps(0.0)
	while controller.rebuild_pending:
		controller._process_los_rebuild()
		controller._process_budgeted_rebuild()
	var director: ScenarioGoalDirector = planner.goal_director
	director._build_tasks(planner, scenario.duration_s)
	_check(director.tasks.size() == 1 and director.tasks[0].escape_policy != null, "The authored Roadblock escape suppresses competing occupation-denial duties")
	var task: ScenarioGoalTask = director.tasks[0]
	_check(not task.breach_required, "Authored woodland bypasses remain usable despite overlapping enemy fire")
	_check(task.required_units == attackers.size() and task.includes_headquarters(), "The column sends its headquarters and combat squads toward the exits")
	planner._planning_snapshot = controller.snapshot
	planner._planning_reservations.clear()
	var crossed_fire: bool = false
	var rifle: Unit
	for unit: Unit in attackers:
		if unit.squad_type != Globals.SquadType.Rifle and not HqSupportPositionPolicy.is_headquarters(unit):
			continue
		planner._planning_requests.clear()
		planner._add_goal_request(unit, task)
		var query: PositionQuery = planner._planning_requests[0]["query"]
		var result: PositionResult = PositionQueryService.query_positions(query)
		_check(result.is_valid() and result.should_move and query.escape_hexes.has(result.target_hex), "Rifles and headquarters receive a complete route to a reachable western exit")
		_check(PositionQueryService.escape_path_is_safe(controller.snapshot, planner.team, unit.current_hex, result.path), "The chosen corridor avoids occupied hexes and neighboring unsuppressed defenders")
		_check(result.features.get("escape", false) and result.profile_mode == PositionProfile.Mode.ADVANCE, "Escape advice preserves movement instead of seeking firing positions")
		crossed_fire = crossed_fire or result.features.get("peak_exposure", 0.0) > 0.8
		if unit.squad_type == Globals.SquadType.Rifle:
			rifle = unit
			unit.stress_system.state = STATES.MoraleState.PINNED
	_check(crossed_fire, "The bypass fixture includes the high fire exposure that previously forced an assault")
	director._build_tasks(planner, scenario.duration_s)
	_check(director.tasks.size() == 1 and director._preferred_primary().kind == ScenarioGoalTask.Kind.EXIT, "Pinning every rifle cannot replace the escape mission with an attack on A")
	director._allocate(planner)
	var headquarters: int = 0
	for unit: Unit in director.assignments:
		if HqSupportPositionPolicy.is_headquarters(unit):
			headquarters += 1
	_check(headquarters == 3, "The three headquarters remain eligible to satisfy the exit victory condition")
	for unit: Unit in attackers:
		unit.stress_system.state = STATES.MoraleState.NORMAL
	director._build_tasks(planner, scenario.duration_s)
	director._allocate(planner)
	_check(director.assignments.size() == attackers.size(), "Recovered rifles rejoin the committed column escape")
	_set_hex(defenders[0], Vector2i(0, 6))
	controller.reset_for_match()
	controller.create_maps(0.0)
	while controller.rebuild_pending:
		controller._process_los_rebuild()
		controller._process_budgeted_rebuild()
	planner._planning_snapshot = controller.snapshot
	planner._planning_requests.clear()
	planner._add_goal_request(rifle, task)
	var alternate_query: PositionQuery = planner._planning_requests[0]["query"]
	var alternate: PositionResult = PositionQueryService.query_positions(alternate_query)
	_check(alternate.is_valid() and alternate.target_hex != Vector2i(0, 6) and alternate_query.escape_hexes.has(alternate.target_hex), "A defended exit redirects movement to another exit instead of rejecting the escape")
	_check(PositionQueryService.escape_path_is_safe(controller.snapshot, planner.team, rifle.current_hex, alternate.path), "The alternate corridor preserves separation from the exit defender")
	controller.snapshot.routes[planner.team].set_point_disabled(controller.snapshot.point_ids[planner.team][Vector2i(0, 6)], true)
	director._build_tasks(planner, scenario.duration_s)
	director._allocate(planner)
	_check(director.assignments.size() == attackers.size(), "Company allocation considers every exit when the nearest marker has no terrain route")


func _test_clear_exit(planner: PlatoonAI, rifles: Array[Unit], snapshot: InfluenceSnapshot, blocked_task: ScenarioGoalTask) -> void:
	if blocked_task == null:
		return
	var task: ScenarioGoalTask = ScenarioGoalTask.new()
	task.kind = ScenarioGoalTask.Kind.EXIT
	task.hex = Vector2i(0, 8)
	task.condition = blocked_task.condition
	task.required_units = 3
	task.key = "clear_exit"
	var front: Unit = rifles[0]
	_set_hex(front, Vector2i(2, 8))
	snapshot.positions[front] = front.current_hex
	snapshot.contacts[planner.team] = []
	snapshot.defensive_contacts[planner.team] = []
	for unit: Unit in planner.squads:
		Globals.unit_visible_enemies[unit] = []
	planner.goal_assignments = {front: task}
	planner.company_requires_support = true
	planner.company_support_squads.clear()
	planner._planning_snapshot = snapshot
	planner._planning_requests.clear()
	planner._planning_reservations.clear()
	planner._add_goal_request(front, task)
	var query: PositionQuery = planner._planning_requests[0]["query"]
	_check(query.profile.mode == PositionProfile.Mode.ADVANCE and query.goal_destination_required, "A clear exit advances without waiting for rear units to provide covering fire")
	var result: PositionResult = PositionQueryService.query_positions(query)
	_check(result.is_valid() and result.should_move and result.target_hex == task.hex, "A squad near the western edge exits instead of returning to the rear formation")
	planner.squad_assignments[front] = {"result": result}
	planner._issue_order(front)
	_check(front.movement.is_moving and front.movement.target_hex == task.hex, "Execution preserves the clear exit order without company covering fire")
	_set_hex(front, Vector2i(2, 8))
	for formation: CompanyPlatoon in planner.company_command.platoons.values():
		formation.task = task
		_check(not planner.company_command._needs_attack(formation), "A clear exit does not request a company assault or support role")


func _set_hex(unit: Unit, cell: Vector2i) -> void:
	unit.movement.is_moving = false
	unit.clear_orders()
	unit.current_hex = cell
	unit.current_cube = LOSHelper.ground_layer.map_to_cube(cell)
	unit.position = LOSHelper.ground_layer.map_to_local(cell)
	unit.stress_system.state = STATES.MoraleState.NORMAL


func _freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	if node is Timer:
		(node as Timer).stop()
	for child: Node in node.get_children():
		_freeze(child)


func _check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
