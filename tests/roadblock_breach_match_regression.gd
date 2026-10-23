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
		var sliced: ExitBreachPlanner.Search = ExitBreachPlanner.Search.new()
		sliced.start(planner, scenario.ai_escape_policies[0].exit_condition.state.exit_hexes, scenario.ai_escape_policies[0])
		var slices: int = 0
		while not sliced.completed and slices < 10000:
			sliced.advance(Time.get_ticks_usec() + 250)
			slices += 1
		_check(sliced.completed and sliced.result != null and sliced.result.hex == weak.current_hex, "Sliced weighted search selects the same weakest breach defender")
		_check(sliced.bypass_units == exit_task.bypass_units, "Sliced sealed-front search preserves bypass duties")
		planner._planning_snapshot = controller.influence_map_controller.snapshot
		planner.goal_assignments = {rifles[0]: exit_task, rifles[1]: exit_task}
		planner._planning_requests.clear()
		planner._add_goal_request(rifles[0], exit_task)
		var query: PositionQuery = planner._planning_requests[0]["query"]
		_check(query.objective_hex == weak.current_hex and query.profile.mode == PositionProfile.Mode.SUPPORT_BY_FIRE, "Exit attackers engage the blocker with covering fire: objective %s; mode %s" % [query.objective_hex, query.profile.mode])
		_check(not query.goal_destination_required, "A breach plan does not demand movement to the defended exit")
		var approach: PositionResult = PositionQueryService.query_positions(query)
		_check(approach.is_valid() and approach.should_move and LOSHelper.get_hex_distance(approach.target_hex, weak.current_hex) < LOSHelper.get_hex_distance(rifles[0].current_hex, weak.current_hex), "A shadowed breach advances into firing range instead of waiting without a shot")
		_test_escape_headquarters(planner, attackers, snapshot, exit_task)
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
		_set_hex(unit, Vector2i(15, 7))
		Globals.unit_visible_enemies[unit] = defenders.duplicate()
	controller.reset_for_match()
	controller.create_maps(0.0)
	while controller.rebuild_pending:
		controller._process_los_rebuild()
		controller._process_budgeted_rebuild()
	var director: ScenarioGoalDirector = planner.goal_director
	var snapshot: InfluenceSnapshot = controller.snapshot
	snapshot.los = snapshot.los.duplicate(true)
	var overwatch: InfluenceContact
	var rifle: Unit
	for unit: Unit in attackers:
		if unit.squad_type == Globals.SquadType.Rifle:
			rifle = unit
	for contact: InfluenceContact in snapshot.get_defensive_contacts(planner.team):
		if contact.unit.squad_type == Globals.SquadType.MG:
			overwatch = contact
	overwatch.weapon_range = 40
	overwatch.firepower = 4.0
	snapshot.los[overwatch.hex] = {}
	for cell: Vector2i in snapshot.point_ids[planner.team]:
		snapshot.los[overwatch.hex][cell] = {"hindrance": 0.0, "target_cover": 0.0}
	director._build_tasks(planner, scenario.duration_s)
	_check(not director.tasks[0].breach_required, "Distant observation and effective fire across open ground do not turn escape into pursuit")
	planner._planning_snapshot = snapshot
	planner._planning_requests.clear()
	planner._add_goal_request(rifle, director.tasks[0])
	var open_query: PositionQuery = planner._planning_requests[0]["query"]
	var open_route: PositionResult = PositionQueryService.query_positions(open_query)
	_check(open_route.is_valid() and open_route.features.get("escape", false), "A fully observed open map still supplies a route to an exit")
	# Seal the terrain front except for one watched passage, away from enemy adjacency.
	var graph: AStar2D = snapshot.routes[planner.team]
	var disabled: Dictionary[int, bool] = {}
	var passage: Vector2i = Vector2i(9, 0)
	var passage_id: int = snapshot.point_ids[planner.team][passage]
	for cell: Vector2i in snapshot.point_ids[planner.team]:
		var id: int = snapshot.point_ids[planner.team][cell]
		if (cell.x == passage.x and cell != passage) or (graph.are_points_connected(id, passage_id) and cell.y != passage.y):
			disabled[id] = graph.is_point_disabled(id)
			graph.set_point_disabled(id, true)
	_check(not EscapeCorridorPolicy.blockers(snapshot, planner.team, passage, director.tasks[0].escape_policy).is_empty(), "Effective observed fire seals a narrow terrain passage")
	var effectiveness: float = overwatch.effectiveness
	overwatch.effectiveness = 0.001
	_check(EscapeCorridorPolicy.blockers(snapshot, planner.team, passage, director.tasks[0].escape_policy).is_empty(), "Observation without effective covering fire does not seal a terrain passage")
	overwatch.effectiveness = effectiveness
	var watched_origin: Vector2i = overwatch.hex + Vector2i(0, -2)
	_check(not EscapeCorridorPolicy.blockers(snapshot, planner.team, watched_origin, director.tasks[0].escape_policy).is_empty(), "Effective fire also guards a close gap on otherwise open terrain")
	_check(EscapeCorridorPolicy.step_is_safe(snapshot, planner.team, watched_origin, passage, director.tasks[0].escape_policy), "A unit already inside a defended area can disengage away from an enemy instead of assaulting it")
	_check(not EscapeCorridorPolicy.step_is_safe(snapshot, planner.team, rifle.current_hex, passage, director.tasks[0].escape_policy), "Observation of open ground does not license entry into a separate guarded bottleneck")
	director._build_tasks(planner, scenario.duration_s)
	_check(director.tasks.size() == 1 and director.tasks[0].escape_policy != null, "The column retains its escape mission while preparing to fight")
	var task: ScenarioGoalTask = director.tasks[0]
	_check(task.breach_required, "A narrow passage covered by effective machine-gun fire requires a deliberate fight")
	planner._planning_snapshot = snapshot
	planner._planning_reservations.clear()
	planner._planning_requests.clear()
	planner._add_goal_request(rifle, task)
	_check(planner._planning_requests[0]["query"].profile.mode == PositionProfile.Mode.SUPPORT_BY_FIRE, "Combat squads establish covering fire instead of squeezing through an observed opening")
	_test_split_escape(planner, attackers, snapshot, scenario)
	_test_pinned_escape(planner, attackers, snapshot, scenario)
	var headquarters_probe: Unit = attackers[0]
	for contact: InfluenceContact in snapshot.get_defensive_contacts(planner.team):
		snapshot.los.get(contact.hex, {}).erase(Vector2i(0, 6))
	_set_hex(headquarters_probe, Vector2i(0, 6))
	director._build_tasks(planner, scenario.duration_s)
	_check(director.tasks[0].breach_required, "A forward headquarters at an unseen exit cannot release a column still covered by fire")
	_set_hex(headquarters_probe, Vector2i(15, 7))
	var probe: ScenarioGoalTask = ScenarioGoalTask.new()
	probe.kind = ScenarioGoalTask.Kind.EXIT
	probe.condition = task.condition
	probe.hex = task.hex
	probe.required_units = task.required_units
	probe.withdrawal = true
	probe.escape_policy = task.escape_policy.duplicate() as EscapeMissionPolicy
	probe.escape_policy.maximum_bypass_visibility = 1.0
	probe.escape_policy.maximum_bypass_risk = 1.0
	planner._planning_requests.clear()
	planner._add_escape_request(rifle, probe)
	var exposed: PositionResult = PositionQueryService.query_positions(planner._planning_requests[0]["query"])
	_check(exposed.is_valid(), "The observed gap has a physical route that avoids adjacent defenders")
	_check(not PositionQueryService.escape_path_is_safe(snapshot, planner.team, rifle.current_hex, exposed.path, task.escape_policy), "Live route validation also refuses the observed gap")
	# Leave one barely visible corridor while preserving enemy positions and the surrounding overwatch.
	for contact: InfluenceContact in snapshot.get_defensive_contacts(planner.team):
		for cell: Vector2i in exposed.path:
			snapshot.los.get(contact.hex, {})[cell] = {"hindrance": 1000.0, "target_cover": 0.0}
	director._build_tasks(planner, scenario.duration_s)
	task = director.tasks[0]
	_check(not task.breach_required, "A concealed corridor permits bypass without an unnecessary fight")
	_check(task.required_units == attackers.size() and task.includes_headquarters(), "The column sends its headquarters and combat squads toward the exits")
	planner._planning_snapshot = controller.snapshot
	planner._planning_reservations.clear()
	for unit: Unit in attackers:
		if unit.squad_type != Globals.SquadType.Rifle and not HqSupportPositionPolicy.is_headquarters(unit):
			continue
		planner._planning_requests.clear()
		planner._add_goal_request(unit, task)
		var query: PositionQuery = planner._planning_requests[0]["query"]
		var result: PositionResult = PositionQueryService.query_positions(query)
		_check(result.is_valid() and result.should_move and query.escape_hexes.has(result.target_hex), "Rifles and headquarters receive a complete route to a reachable western exit")
		_check(PositionQueryService.escape_path_is_safe(controller.snapshot, planner.team, unit.current_hex, result.path, task.escape_policy), "The chosen corridor avoids occupied hexes and neighboring unsuppressed defenders")
		_check(result.features.get("escape", false) and result.profile_mode == PositionProfile.Mode.ADVANCE, "Escape advice preserves movement instead of seeking firing positions")
		if unit.squad_type == Globals.SquadType.Rifle:
			rifle = unit
			unit.stress_system.state = STATES.MoraleState.PINNED
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
	for id: int in disabled:
		graph.set_point_disabled(id, disabled[id])
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
	alternate_query.escape_policy = probe.escape_policy
	var alternate: PositionResult = PositionQueryService.query_positions(alternate_query)
	_check(alternate.is_valid() and alternate.target_hex != Vector2i(0, 6) and alternate_query.escape_hexes.has(alternate.target_hex), "A defended exit redirects movement to another exit instead of rejecting the escape")
	_check(PositionQueryService.escape_path_is_safe(controller.snapshot, planner.team, rifle.current_hex, alternate.path), "The alternate corridor preserves separation from the exit defender")
	controller.snapshot.routes[planner.team].set_point_disabled(controller.snapshot.point_ids[planner.team][Vector2i(0, 6)], true)
	director._build_tasks(planner, scenario.duration_s)
	director._allocate(planner)
	_check(director.assignments.size() == attackers.size(), "Company allocation considers every exit when the nearest marker has no terrain route")


func _test_split_escape(planner: PlatoonAI, attackers: Array[Unit], snapshot: InfluenceSnapshot, scenario: Scenario) -> void:
	var positions: Dictionary[Unit, Vector2i] = snapshot.positions.duplicate()
	var sightlines: Dictionary = snapshot.los
	var assignments: Dictionary[Unit, ScenarioGoalTask] = planner.goal_assignments.duplicate()
	var director: ScenarioGoalDirector = planner.goal_director
	var previous: Dictionary[Unit, ScenarioGoalTask] = director.assignments.duplicate()
	var formations: Array[CompanyPlatoon] = []
	formations.assign(planner.company_command.platoons.values())
	var escaping: CompanyPlatoon = formations[0]
	var cutoff: CompanyPlatoon = formations[1]
	snapshot.los = sightlines.duplicate(true)
	for contact: InfluenceContact in snapshot.get_defensive_contacts(planner.team):
		for cell: Vector2i in snapshot.point_ids[planner.team]:
			if cell.x <= 3:
				snapshot.los.get(contact.hex, {})[cell] = {"hindrance": 1000.0, "target_cover": 0.0}
	for unit: Unit in escaping.squads:
		_set_hex(unit, Vector2i(2, 6))
	for unit: Unit in attackers:
		if HqSupportPositionPolicy.is_headquarters(unit) and not escaping.squads.has(unit):
			# A safe HQ cannot abandon squads that remain on the covered side.
			_set_hex(unit, Vector2i(2, 8))
		snapshot.positions[unit] = unit.current_hex
	director._build_tasks(planner, scenario.duration_s)
	var task: ScenarioGoalTask = director.tasks[0]
	_check(task.breach_required, "The cut-off platoon still needs to fight through the watched roadblock")
	for unit: Unit in escaping.squads:
		_check(not task.requires_breach(unit), "A squad or HQ with a usable corridor does not inherit another platoon's fight")
	for unit: Unit in cutoff.squads:
		_check(task.requires_breach(unit), "The cut-off platoon and its HQ retain their coordinated breach duty")
	director._allocate(planner)
	planner.set_scenario_goal_assignments(director.assignments)
	planner.company_command._assign_roles()
	_check(escaping.role == CompanyPlatoon.Role.WITHDRAW and escaping.objective == task.hex, "A platoon with a bypass withdraws instead of supporting an unnecessary attack")
	_check(cutoff.role == CompanyPlatoon.Role.MANEUVER and cutoff.objective == task.breach_hex, "Only the platoon without a bypass receives the breach objective")
	escaping.objective = cutoff.objective
	escaping.role = CompanyPlatoon.Role.MANEUVER
	cutoff.role = CompanyPlatoon.Role.SUPPORT
	_check(planner.company_command._choose_maneuver(formations) == cutoff and planner.company_command._choose_support(formations, cutoff) == null, "A shared exit anchor and a previous assault role cannot recruit an escaping platoon back into combat")
	escaping.objective = task.hex
	escaping.role = CompanyPlatoon.Role.WITHDRAW
	cutoff.role = CompanyPlatoon.Role.MANEUVER
	planner.company_command._dispatch(escaping)
	var child: PlatoonAI = escaping.planner
	child._cancel_plan()
	child._planning_snapshot = snapshot
	child._planning_reservations.clear()
	child.company_requires_support = true
	child.company_support_squads.clear()
	for unit: Unit in escaping.squads:
		child._planning_requests.clear()
		child._add_goal_request(unit, task)
		var query: PositionQuery = child._planning_requests[0]["query"]
		var result: PositionResult = PositionQueryService.query_positions(query)
		_check(result.is_valid() and result.features.get("escape", false) and query.escape_hexes.has(result.target_hex), "Rifles and their HQ take the available bypass while another platoon fights")
		child.squad_assignments[unit] = {"result": result}
		child._issue_order(unit)
		_check(unit.movement.is_moving and query.escape_hexes.has(unit.movement.target_hex), "A usable bypass executes without waiting for covering fire elsewhere")
	var split_rifle: Unit = escaping.combat_units()[1]
	_set_hex(split_rifle, Vector2i(15, 7))
	snapshot.positions[split_rifle] = split_rifle.current_hex
	director._build_tasks(planner, scenario.duration_s)
	var split: ScenarioGoalTask = director.tasks[0]
	var free_rifle: Unit = escaping.combat_units()[0]
	_check(not split.requires_breach(free_rifle) and split.requires_breach(split_rifle), "A usable bypass also takes precedence when only part of one platoon is cut off")
	var split_assignments: Dictionary[Unit, ScenarioGoalTask] = {}
	for unit: Unit in escaping.squads:
		split_assignments[unit] = split
		if HqSupportPositionPolicy.is_headquarters(unit):
			_check(split.requires_breach(unit), "A platoon HQ stays with its cut-off squad instead of leaving alone")
	child.set_scenario_goal_assignments(split_assignments)
	_check(child._goal_maneuver(split.breach_hex) == split_rifle, "A squad with an escape route cannot be selected to maneuver against the blocker")
	_set_hex(split_rifle, Vector2i(2, 6))
	snapshot.positions[split_rifle] = split_rifle.current_hex
	# Open a bypass while a cut-off squad is moving into a firing position.
	planner.company_command._dispatch(cutoff)
	child = cutoff.planner
	child._cancel_plan()
	var rifle: Unit = cutoff.combat_units()[0]
	var bound: PositionResult = PositionResult.new()
	bound.unit = rifle
	bound.status = PositionResult.Status.ACCEPTED
	bound.target_hex = Vector2i(14, 7)
	bound.target_index = snapshot.maps[planner.team].cell_to_index(bound.target_hex)
	bound.objective_hex = task.breach_hex
	bound.path = snapshot.get_path(planner.team, rifle.current_hex, bound.target_hex)
	bound.profile_mode = PositionProfile.Mode.SUPPORT_BY_FIRE
	bound.position_profile = PositionProfile.for_mode(bound.profile_mode)
	bound.features = {"scenario_goal": task.key}
	bound.should_move = true
	child.squad_assignments[rifle] = {"result": bound}
	child._issue_order(rifle)
	_check(rifle.movement.is_moving and child.executor.pending.has(rifle), "The reproduction starts with an owned fighting bound in progress")
	snapshot.los = {}
	director._build_tasks(planner, scenario.duration_s)
	var opened: ScenarioGoalTask = director.tasks[0]
	_check(not opened.requires_breach(rifle), "An opened corridor releases the previously cut-off squad")
	child.set_scenario_goal_assignments({rifle: opened})
	_check(not rifle.movement.is_moving and not child.accepted_positions.has(rifle), "The opened bypass immediately cancels the obsolete fighting bound under the same mission key")
	child._planning_snapshot = snapshot
	child._planning_requests.clear()
	child._add_goal_request(rifle, opened)
	var query: PositionQuery = child._planning_requests[0]["query"]
	var result: PositionResult = PositionQueryService.query_positions(query)
	child.squad_assignments[rifle] = {"result": result}
	child._issue_order(rifle)
	_check(result.is_valid() and rifle.movement.is_moving and query.escape_hexes.has(rifle.movement.target_hex), "The former attacker immediately starts the bypass instead of completing its fight")
	for formation: CompanyPlatoon in formations:
		formation.planner._cancel_plan()
		formation.planner.executor.cancel_all(true)
		formation.planner.position_stability.clear()
		formation.planner.accepted_positions.clear()
		formation.planner.squad_assignments.clear()
	planner.company_command.reservations.clear()
	snapshot.positions = positions
	snapshot.los = sightlines
	planner.goal_assignments = assignments
	director.assignments = previous
	for unit: Unit in attackers:
		_set_hex(unit, positions[unit])
	planner._planning_snapshot = snapshot
	planner._planning_requests.clear()
	director._build_tasks(planner, scenario.duration_s)


func _test_pinned_escape(planner: PlatoonAI, attackers: Array[Unit], snapshot: InfluenceSnapshot, scenario: Scenario) -> void:
	var positions: Dictionary[Unit, Vector2i] = snapshot.positions.duplicate()
	var sightlines: Dictionary = snapshot.los
	var assignments: Dictionary[Unit, ScenarioGoalTask] = planner.goal_assignments.duplicate()
	var director: ScenarioGoalDirector = planner.goal_director
	var previous: Dictionary[Unit, ScenarioGoalTask] = director.assignments.duplicate()
	snapshot.los = sightlines.duplicate(true)
	for contact: InfluenceContact in snapshot.get_defensive_contacts(planner.team):
		for cell: Vector2i in snapshot.point_ids[planner.team]:
			if cell.x <= 3:
				snapshot.los.get(contact.hex, {})[cell] = {"hindrance": 1000.0, "target_cover": 0.0}
	for unit: Unit in attackers:
		_set_hex(unit, Vector2i(2, 6))
		snapshot.positions[unit] = unit.current_hex
	var formation: CompanyPlatoon = planner.company_command.platoons.values()[0]
	var pinned: Unit = formation.combat_units()[0]
	director._build_tasks(planner, scenario.duration_s)
	director._allocate(planner)
	planner.set_scenario_goal_assignments(director.assignments)
	planner.company_command.reconsider(false)
	_check(pinned.movement.is_moving, "The pinning reproduction begins with an escaping squad in motion")
	var moving_orders: Dictionary[Unit, int] = {}
	for unit: Unit in attackers:
		if unit != pinned and not HqSupportPositionPolicy.is_headquarters(unit):
			moving_orders[unit] = unit.action_controller.action_order_id
	pinned.stress_system._set_state(STATES.MoraleState.PINNED)
	_check(not pinned.movement.is_moving, "The real morale callback stops the pinned squad")
	for tick: int in range(3):
		director._build_tasks(planner, scenario.duration_s)
		director._allocate(planner)
		planner.set_scenario_goal_assignments(director.assignments)
		planner.company_command.reconsider(false)
		_check(director.assignments.has(pinned) and director.assignments[pinned].kind == ScenarioGoalTask.Kind.EXIT, "Pinning retains the squad's escape assignment across reassessments")
		for unit: Unit in moving_orders:
			_check(unit.movement.is_moving and unit.action_controller.action_order_id == moving_orders[unit] and unit.position_advice.features.get("escape", false), "Other squads continue their owned escape orders when one squad is pinned")
	# A pinned straggler in a watched area must not become a company rescue assault.
	_set_hex(pinned, Vector2i(15, 7))
	snapshot.positions[pinned] = pinned.current_hex
	pinned.stress_system._set_state(STATES.MoraleState.PINNED)
	director._build_tasks(planner, scenario.duration_s)
	director._allocate(planner)
	planner.set_scenario_goal_assignments(director.assignments)
	planner.company_command.reconsider(false)
	_check(not director.tasks[0].breach_required, "An immobile pinned straggler cannot create a breach duty for the mobile column")
	for platoon: CompanyPlatoon in planner.company_command.platoons.values():
		_check(platoon.role == CompanyPlatoon.Role.WITHDRAW and not platoon.planner.company_requires_support, "Pinning does not assign an assault or covering-fire role to the escaping platoons")
	for unit: Unit in moving_orders:
		_check(unit.movement.is_moving and unit.position_advice.features.get("escape", false), "The mobile column bypasses while a pinned straggler recovers")
	for unit: Unit in formation.squads:
		if HqSupportPositionPolicy.is_headquarters(unit):
			var profile: int = -1
			var reason: String = "No advice"
			if unit.position_advice != null:
				profile = unit.position_advice.profile_mode
				reason = unit.position_advice.reason
			_check(profile == PositionProfile.Mode.HQ_SUPPORT, "The pinned squad's HQ keeps a recovery support duty instead of assaulting: %s, duty %s, mode %s, assigned %s, %s" % [unit.name, director.tasks[0].escape_duty(unit), profile, director.assignments.has(unit), reason])
	_check(_complete_pinned_budgeted_plan(planner), "The real queued planner publishes every squad's orders while one squad is pinned")
	_check(formation.planner.squad_assignments.has(pinned) and not formation.planner.squad_assignments[pinned]["result"].is_valid(), "The pinned squad waits without blocking publication of the platoon's orders")
	for unit: Unit in attackers:
		unit.stress_system._set_state(STATES.MoraleState.PINNED)
	director._build_tasks(planner, scenario.duration_s)
	director._allocate(planner)
	planner.set_scenario_goal_assignments(director.assignments)
	planner.company_command.reconsider(false)
	_check(not director.tasks[0].breach_required and director.assignments.size() == attackers.size(), "Pinning the entire combat force retains escape and recovery duties without inventing an HQ assault")
	for platoon: CompanyPlatoon in planner.company_command.platoons.values():
		_check(platoon.role == CompanyPlatoon.Role.WITHDRAW, "An entirely pinned platoon keeps its withdrawal mission")
	# Recovery restores movement without needing a new strategic objective.
	for unit: Unit in attackers:
		_set_hex(unit, Vector2i(2, 6))
		snapshot.positions[unit] = unit.current_hex
		unit.stress_system.state = STATES.MoraleState.PINNED
		unit.stress_system._set_state(STATES.MoraleState.CAUTIOUS)
	director._build_tasks(planner, scenario.duration_s)
	director._allocate(planner)
	planner.set_scenario_goal_assignments(director.assignments)
	planner.company_command.reconsider(false)
	_check(pinned.movement.is_moving and pinned.position_advice.features.get("escape", false), "The recovered squad resumes escape instead of falling back to combat orders")
	for platoon: CompanyPlatoon in planner.company_command.platoons.values():
		platoon.planner._cancel_plan()
		platoon.planner.executor.cancel_all(true)
		platoon.planner.position_stability.clear()
		platoon.planner.accepted_positions.clear()
		platoon.planner.squad_assignments.clear()
	planner.company_command.reservations.clear()
	snapshot.positions = positions
	snapshot.los = sightlines
	planner.goal_assignments = assignments
	director.assignments = previous
	for unit: Unit in attackers:
		unit.stress_system._set_state(STATES.MoraleState.NORMAL)
		_set_hex(unit, positions[unit])
	planner._planning_snapshot = snapshot
	planner._planning_requests.clear()
	director._build_tasks(planner, scenario.duration_s)


func _complete_pinned_budgeted_plan(planner: PlatoonAI) -> bool:
	var children: Array[PlatoonAI] = []
	for formation: CompanyPlatoon in planner.company_command.platoons.values():
		children.append(formation.planner)
	if planner.company_command._headquarters_planner != null:
		children.append(planner.company_command._headquarters_planner)
	for child: PlatoonAI in children:
		child.squad_assignments.clear()
		child._start_plan(true)
	for slice: int in range(20000):
		planner.influence_map_controller._process_position_queries()
		var pending: bool = false
		for child: PlatoonAI in children:
			if not child._planning_requests.is_empty() or child._planning_job != null or child._validation_job != null:
				child._process(0.0)
				pending = true
		if not pending:
			for child: PlatoonAI in children:
				if child.squad_assignments.size() != child.squads.size():
					return false
			planner.company_command.collect_assignments()
			return true
	return false


func _test_escape_headquarters(planner: PlatoonAI, attackers: Array[Unit], snapshot: InfluenceSnapshot, task: ScenarioGoalTask) -> void:
	var positions: Dictionary[Unit, Vector2i] = snapshot.positions.duplicate()
	var support_units: Dictionary[Unit, Dictionary] = snapshot.support_units.duplicate(true)
	var assignments: Dictionary[Unit, ScenarioGoalTask] = planner.goal_assignments.duplicate()
	var contacts: Array = snapshot.contacts[planner.team]
	var had_defensive_contacts: bool = snapshot.defensive_contacts.has(planner.team)
	var defensive_contacts: Array = snapshot.defensive_contacts.get(planner.team, [])
	var map: InfluenceMap = snapshot.maps[planner.team]
	var threat: PackedFloat32Array = map.get_layer_data_copy(InfluenceMap.Layer.THREAT)
	var sightlines: Dictionary = snapshot.los
	var weapon_ranges: Dictionary[InfluenceContact, int] = {}
	snapshot.los = {}
	for contact: InfluenceContact in snapshot.get_defensive_contacts(planner.team):
		weapon_ranges[contact] = contact.weapon_range
		contact.weapon_range = 1
		snapshot.los[contact.hex] = {}
		for cell: Vector2i in map.playable_cells:
			snapshot.los[contact.hex][cell] = {"hindrance": 0.0, "target_cover": 0.0}
	# A broad threat projection cannot veto movement where captured contacts have no fire.
	for cell: Vector2i in map.playable_cells:
		map.set_layer_value(InfluenceMap.Layer.THREAT, cell, 100.0)
	var headquarters: Array[Unit] = []
	var squad_types: Dictionary[Unit, Globals.SquadType] = {}
	for unit: Unit in attackers:
		squad_types[unit] = unit.squad_type
		if HqSupportPositionPolicy.is_headquarters(unit):
			_set_hex(unit, Vector2i(19, 7))
			headquarters.append(unit)
		else:
			# Exercise withdrawal without rifles or stress to drive ordinary assault support.
			unit.squad_type = Globals.SquadType.MG
			_set_hex(unit, Vector2i(11, 7))
		snapshot.positions[unit] = unit.current_hex
		snapshot.support_units[unit]["need"] = 0.0
	planner._planning_reservations.clear()
	for unit: Unit in headquarters:
		planner.goal_assignments[unit] = task
		planner._planning_requests.clear()
		planner._add_goal_request(unit, task)
		var query: PositionQuery = planner._planning_requests[0]["query"]
		_check(query.profile.mode == PositionProfile.Mode.HQ_SUPPORT and not query.goal_destination_required, "A blocked exit gives headquarters a protected bound with its squads")
		var result: PositionResult = PositionQueryService.query_positions(query)
		_check(result.is_valid() and result.should_move and LOSHelper.get_hex_distance(result.target_hex, Vector2i(11, 7)) < 8, "Platoon and company headquarters close a leadership gap larger than one planning radius")
		var follows_weapons: bool = false
		for subordinate: Unit in query.support_targets:
			_check(subordinate.company == unit.company and (unit.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS or subordinate.platoon == unit.platoon), "Headquarters follows its own formation")
			if subordinate.squad_type != Globals.SquadType.Rifle:
				follows_weapons = follows_weapons or query.support_targets[subordinate]["need"] >= 0.35
		_check(follows_weapons, "Calm support weapons also draw their headquarters forward during withdrawal")
		_check(PositionQueryService.approach_path_is_safe(query, result.path), "The headquarters bound avoids unsuppressed defenders")
		planner.squad_assignments[unit] = {"result": result}
		planner._issue_order(unit)
		_check(unit.movement.is_moving and unit.movement.target_hex == result.target_hex, "Headquarters starts the follow order while combat squads prepare the breach")
	var observer: InfluenceContact = snapshot.get_defensive_contacts(planner.team)[0]
	var firepower: float = observer.firepower
	observer.firepower = 10000.0
	observer.weapon_range = 40
	var safety_query: PositionQuery = PositionQuery.new()
	safety_query.snapshot = snapshot
	safety_query.team = planner.team
	safety_query.profile = PositionProfile.for_mode(PositionProfile.Mode.HQ_SUPPORT)
	safety_query.profile.support_withdrawing_squads = true
	_check(not HqSupportPositionPolicy.open_position_is_safe(safety_query, Vector2i(19, 7)), "Dangerous overwatch still rejects an open headquarters position")
	planner._planning_requests.clear()
	planner._add_goal_request(headquarters[0], task)
	var unsafe: PositionResult = PositionQueryService.query_positions(planner._planning_requests[0]["query"])
	_check(not unsafe.is_valid(), "Withdrawal does not authorize a headquarters bound under overwhelming fire")
	observer.firepower = firepower
	observer.weapon_range = 1
	# A fresh escape order must replace the accepted support bound once the passage opens.
	map.set_layer_data_copy(InfluenceMap.Layer.THREAT, threat)
	task.breach_required = false
	snapshot.contacts[planner.team] = []
	snapshot.defensive_contacts[planner.team] = []
	for unit: Unit in headquarters:
		planner._planning_requests.clear()
		planner._add_goal_request(unit, task)
		var query: PositionQuery = planner._planning_requests[0]["query"]
		var result: PositionResult = PositionQueryService.query_positions(query)
		_check(result.is_valid() and result.should_move and result.features.get("escape", false) and query.escape_hexes.has(result.target_hex), "An opened route replaces headquarters support with a complete exit order")
		planner.squad_assignments[unit] = {"result": result}
		planner._issue_order(unit)
		_check(unit.movement.is_moving and query.escape_hexes.has(unit.movement.target_hex), "Headquarters executes escape instead of keeping its old support bound")
	# An HQ with no remaining squads still receives its own escape duty.
	task.breach_required = true
	for unit: Unit in attackers:
		if not HqSupportPositionPolicy.is_headquarters(unit):
			snapshot.positions.erase(unit)
	planner._planning_requests.clear()
	planner._add_goal_request(headquarters[0], task)
	_check(planner._planning_requests[0]["query"].escape_policy == task.escape_policy, "Headquarters without subordinates seeks an exit instead of an empty support duty")
	snapshot.positions = positions
	snapshot.support_units = support_units
	snapshot.los = sightlines
	for contact: InfluenceContact in weapon_ranges:
		contact.weapon_range = weapon_ranges[contact]
	snapshot.contacts[planner.team] = contacts
	if had_defensive_contacts:
		snapshot.defensive_contacts[planner.team] = defensive_contacts
	else:
		snapshot.defensive_contacts.erase(planner.team)
	planner.goal_assignments = assignments
	for unit: Unit in attackers:
		unit.squad_type = squad_types[unit]
		_set_hex(unit, positions[unit])
	for unit: Unit in headquarters:
		planner.executor.cancel(unit, true)
		planner.position_stability.forget(unit)
		planner.accepted_positions.erase(unit)
		planner.squad_assignments.erase(unit)
	planner._planning_reservations.clear()
	planner._planning_requests.clear()


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
