extends Node

var checks: int = 0
var failures: int = 0
var controller: Node2D
var commander: PlatoonAI
var command: CompanyAI
var main: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(6049)
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map: Map = world.maps.get_node("DefaultMap")
	var scenario: Scenario = map.get_scenario(3)
	scenario.victory_conditions = []
	scenario.ai_fallback_policies = []
	scenario.axis_ai_status = Scenario.AIStatus.ON
	scenario.axis_ai_mode = Scenario.AIMode.ATTACK
	var defend: bool = OS.get_cmdline_user_args().has("--defend")
	if defend:
		scenario.axis_ai_mode = Scenario.AIMode.DEFEND
	scenario.allies_ai_status = Scenario.AIStatus.OFF
	_add_authored_platoon(map, scenario)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, Globals.Team.ALLIES, Globals.GameMode.ATTACK)
	controller = world.game_controller
	commander = controller.platoon_ai
	command = commander.company_command
	for unit: Unit in Globals.get_units():
		unit.squad_fire.set_process(false)
		unit.squad_fire.set_physics_process(false)
		unit.stress_system.set_process(false)
		unit.stress_system.set_physics_process(false)
		unit.combat_stats_timer.stop()
	for frame: int in range(2400):
		await get_tree().process_frame
		if not commander.squad_assignments.is_empty():
			break
	_check(command != null and command.uses_hierarchy(), "Authored company starts the hierarchy automatically")
	_check(command.platoons.size() == 3, "Three platoons retain separate identities")
	_check(not commander.squad_assignments.is_empty(), "The real budgeted company publishes platoon position orders")
	for key: Vector2i in command.platoons:
		var formation: CompanyPlatoon = command.platoons[key]
		_check(formation.planner != null and formation.planner != commander, "Each platoon has its own squad planner")
		for unit: Unit in formation.planner.squads:
			_check(unit.company == formation.company and unit.platoon == formation.number, "Platoon planners never borrow another platoon's squads")
		_check(not formation.planner.squad_assignments.is_empty(), "Every platoon completes its initial tactical batch")
	_check(controller.influence_map_controller.objectives_by_team[commander.team] == commander.current_order.objective_hex, "Subordinate objectives cannot overwrite the team objective")
	_test_claims()
	if defend:
		_test_defense_positions()
		main.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		print("Company defense checks: ", checks, "; failures: ", failures)
		get_tree().quit(failures)
		return
	_check(_role_count(CompanyPlatoon.Role.SUPPORT) == 1 and _role_count(CompanyPlatoon.Role.MANEUVER) == 1 and _role_count(CompanyPlatoon.Role.RESERVE) == 1, "Company attack assigns support, maneuver, and a whole reserve platoon")
	_freeze(main)
	for formation: CompanyPlatoon in command.platoons.values():
		formation.planner._cancel_plan()
		formation.planner.executor.cancel_all(true)
	for unit: Unit in commander.squads:
		unit.give_hold_order()
		unit.movement._process_movement(100.0)
		unit.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
	controller.influence_map_controller.create_maps(0.0)
	_test_support_gate()
	_test_destination_conflict()
	_test_objective_cohesion()
	_test_scenario_goal_dispatch()
	_test_withdrawal()
	_test_reserve()
	_test_controls()
	_test_runtime_roster()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Company AI checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _add_authored_platoon(map: Map, scenario: Scenario) -> void:
	var ground: HexagonTileMapLayer = map.get_ground_layer()
	var occupied: Dictionary[Vector2i, bool] = {}
	var base: Unit
	for child: Node in scenario.get_units():
		var unit: Unit = child as Unit
		if unit == null:
			continue
		occupied[ground.local_to_map(ground.to_local(unit.global_position))] = true
		if unit.team == Globals.Team.AXIS and unit.squad_type == Globals.SquadType.Rifle:
			base = unit
	if base == null:
		_check(false, "Authored company includes a rifle squad")
		return
	var origin: Vector2i = ground.local_to_map(ground.to_local(base.global_position))
	var placed: int = 0
	for cell: Vector2i in ground.get_used_cells():
		if occupied.has(cell) or LOSHelper.ground_layer != null and ground.get_cell_source_id(cell) < 0:
			continue
		if ground.cube_distance(ground.map_to_cube(origin), ground.map_to_cube(cell)) > 3:
			continue
		var unit: Unit = load("res://scenes/game/units/unit.tscn").instantiate()
		unit.team = Globals.Team.AXIS
		unit.company = Unit.Company.A
		unit.platoon = 3
		unit.squad = placed + 1
		unit.squad_loadout = load("res://resources/squads/germany/rifle_squad.tres") as SquadLoadoutSpec
		scenario.units.add_child(unit)
		unit.global_position = ground.to_global(ground.map_to_local(cell))
		occupied[cell] = true
		placed += 1
		if placed == 2:
			break
	_check(placed == 2, "Fixture adds a third complete maneuver-capable platoon")


func _role_count(role: CompanyPlatoon.Role) -> int:
	var count: int = 0
	for formation: CompanyPlatoon in command.platoons.values():
		if formation.role == role:
			count += 1
	return count


func _formation_for_role(role: CompanyPlatoon.Role) -> CompanyPlatoon:
	for formation: CompanyPlatoon in command.platoons.values():
		if formation.role == role:
			return formation
	return null


func _test_claims() -> void:
	var occupied: Dictionary[Vector2i, Unit] = {}
	for unit: Unit in commander.squad_assignments:
		var result: PositionResult = commander.squad_assignments[unit]["result"]
		if not result.is_valid() or not commander.accepted_positions.has(unit) or HqSupportPositionPolicy.is_headquarters(unit):
			continue
		_check(not occupied.has(result.target_hex), "Platoons share reservations without competing for a combat position")
		occupied[result.target_hex] = unit
		_check(result.features.has("company_mission"), "Tactical advice carries its company mission")


func _test_defense_positions() -> void:
	_check(_role_count(CompanyPlatoon.Role.SUPPORT) == 0 and _role_count(CompanyPlatoon.Role.MANEUVER) == 0, "Company defense assigns defensive and reserve roles")
	var sectors: Dictionary[Vector2i, bool] = {}
	for formation: CompanyPlatoon in command.platoons.values():
		var valid: int = 0
		for unit: Unit in formation.planner.squad_assignments:
			var result: PositionResult = formation.planner.squad_assignments[unit]["result"]
			if not result.is_valid() or HqSupportPositionPolicy.is_headquarters(unit):
				continue
			valid += 1
			if not formation.sector_cells.is_empty():
				_check(formation.sector_cells.has(result.target_hex), "Defensive squad advice stays inside its platoon sector")
		_check(valid > 0, "Each defensive platoon finds a usable combat position")
		for cell: Vector2i in formation.sector_cells:
			_check(not sectors.has(cell), "Live defensive platoons receive distinct terrain sectors")
			sectors[cell] = true
	_check(not sectors.is_empty(), "Real company defense allocates sectors on the village terrain")


func _test_support_gate() -> void:
	var maneuver: CompanyPlatoon = _formation_for_role(CompanyPlatoon.Role.MANEUVER)
	var support: CompanyPlatoon = _formation_for_role(CompanyPlatoon.Role.SUPPORT)
	_check(maneuver != null and support != null and maneuver.support == support, "The maneuver platoon depends on a separate support platoon")
	if maneuver == null or support == null:
		return
	var planner: PlatoonAI = maneuver.planner
	var snapshot: InfluenceSnapshot = controller.influence_map_controller.snapshot
	snapshot.contacts[commander.team] = []
	snapshot.defensive_contacts[commander.team] = []
	for unit: Unit in commander.squads:
		Globals.unit_visible_enemies[unit] = []
	for unit: Unit in support.combat_units():
		unit.position_advice = null
	_check(not planner._has_company_support(), "Promised support positions do not release the attack")
	var supporter: Unit = support.combat_units()[0]
	var advice: PositionResult = PositionResult.new()
	advice.unit = supporter
	advice.status = PositionResult.Status.RETAINED
	advice.target_index = 0
	advice.target_hex = supporter.current_hex
	advice.objective_hex = planner.current_order.objective_hex
	advice.profile_mode = PositionProfile.Mode.SUPPORT_BY_FIRE
	advice.features = {"cover": 0.5, "firing": 1.0}
	supporter.position_advice = advice
	supporter.action_controller.action_state = SquadActionController.SquadActionState.ESTABLISHING_POSITION
	_check(not planner._has_company_support(), "Support must finish setting up before maneuver begins")
	supporter.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
	_check(planner._has_company_support(), "Established company overwatch releases the maneuver platoon")
	var attacker: Unit = maneuver.combat_units()[0]
	var move: PositionResult = _move_result(attacker)
	_check(move != null, "Fixture has a real route for a company maneuver")
	if move != null:
		_check(planner.executor.execute(move, TacticalPositionExecutor.Intent.ADVANCE), "Maneuver uses the real movement executor")
		var order_id: int = supporter.action_controller.action_order_id
		var relocation: PositionResult = _move_result(supporter)
		if relocation != null:
			relocation.profile_mode = PositionProfile.Mode.SUPPORT_BY_FIRE
			support.planner.squad_assignments[supporter] = {"result": relocation}
			support.planner._issue_order(supporter)
			_check(supporter.action_controller.action_order_id == order_id, "The last covering squad holds its firing lane during another platoon's bound")
		supporter.position_advice = null
		planner._check_company_cover()
		_check(attacker.movement.path_hexes.is_empty() and attacker.movement.target_hex == attacker.current_hex and not planner.executor.pending.has(attacker), "Losing covering fire cancels the remaining owned bound")
		attacker.movement._process_movement(1.0)
		attacker.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
	supporter.position_advice = advice


func _test_destination_conflict() -> void:
	var formation: CompanyPlatoon = _formation_for_role(CompanyPlatoon.Role.MANEUVER)
	var other: CompanyPlatoon = _formation_for_role(CompanyPlatoon.Role.SUPPORT)
	if formation == null or other == null:
		return
	var unit: Unit = formation.combat_units()[0]
	var occupant: Unit = other.combat_units()[0]
	var result: PositionResult = _move_result(unit)
	if result == null:
		return
	result.target_hex = occupant.current_hex
	formation.planner.squad_assignments[unit] = {"result": result}
	formation.planner._issue_order(unit)
	_check(not result.is_valid() and result.reason.contains("another platoon"), "A stale query cannot claim another platoon's live destination")


func _move_result(unit: Unit) -> PositionResult:
	var snapshot: InfluenceSnapshot = controller.influence_map_controller.snapshot
	for cell: Vector2i in LOSHelper.ground_layer.get_surrounding_cells(unit.current_hex):
		var path: Array[Vector2i] = snapshot.get_path(unit.team, unit.current_hex, cell)
		if path.size() < 2:
			continue
		var result: PositionResult = PositionResult.new()
		result.unit = unit
		result.status = PositionResult.Status.ACCEPTED
		result.target_index = 0
		result.target_hex = cell
		result.objective_hex = commander.current_order.objective_hex
		result.should_move = true
		result.path = path
		result.profile_mode = PositionProfile.Mode.ADVANCE
		result.position_profile = PositionProfile.for_mode(PositionProfile.Mode.ADVANCE)
		result.context = "company_movement_fixture"
		return result
	return null


func _test_objective_cohesion() -> void:
	var first: ScenarioGoalTask = ScenarioGoalTask.new()
	first.kind = ScenarioGoalTask.Kind.OCCUPY
	first.key = "first_company_objective"
	first.hex = command.platoons[Vector2i(0, 1)].anchor()
	first.reason = "First objective"
	var second: ScenarioGoalTask = ScenarioGoalTask.new()
	second.kind = ScenarioGoalTask.Kind.OCCUPY
	second.key = "second_company_objective"
	second.hex = command.platoons[Vector2i(0, 2)].anchor()
	second.reason = "Second objective"
	var assignments: Dictionary[Unit, ScenarioGoalTask] = command.allocate([first, second], {})
	var duties: Dictionary[Vector2i, String] = {}
	for unit: Unit in assignments:
		var key: Vector2i = Vector2i(int(unit.company), unit.platoon)
		_check(not duties.has(key) or duties[key] == assignments[unit].key, "A platoon receives one company objective")
		duties[key] = assignments[unit].key
	_check(duties.size() == 2 and assignments.size() == 2, "Separate objectives receive separate platoons")
	commander.set_scenario_goal_assignments(assignments)
	for key: Vector2i in duties:
		_check(command.platoons[key].planner.current_order.objective_hex == command.platoons[key].task.hex, "The entire assigned platoon plans around its objective")
	var retained: Dictionary[Unit, ScenarioGoalTask] = command.allocate([first, second], assignments)
	_check(retained == assignments, "Routine strategic reassessment retains platoon objective ownership")
	var assigned: Unit = assignments.keys()[0]
	var assigned_key: Vector2i = Vector2i(int(assigned.company), assigned.platoon)
	var move: PositionResult = _move_result(assigned)
	if move != null:
		command.platoons[assigned_key].planner.executor.execute(move, TacticalPositionExecutor.Intent.ADVANCE)
		var changed: Dictionary[Unit, ScenarioGoalTask] = command.allocate([second], assignments)
		_check(changed.has(assigned) and changed[assigned].key == assignments[assigned].key, "Accepted bounds retain their platoon's previous objective during reassessment")
		command.platoons[assigned_key].planner.executor.cancel(assigned, true)
		assigned.movement._process_movement(1.0)
		assigned.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
	for formation: CompanyPlatoon in command.platoons.values():
		formation.task = null
	commander.set_scenario_goal_assignments({})
	command.reconsider(true)


func _test_scenario_goal_dispatch() -> void:
	var original_director: ScenarioGoalDirector = commander.goal_director
	var original_order: MissionOrder = commander.current_order
	var occupation: OccupyObjectiveCondition = OccupyObjectiveCondition.new()
	occupation.team = commander.team
	occupation.state = OccupyObjectiveState.new()
	occupation.state.hexes = [command.platoons[Vector2i(0, 1)].anchor(), command.platoons[Vector2i(0, 2)].anchor()]
	for hex: Vector2i in occupation.state.hexes:
		occupation.state.required_times_reached_s[hex] = 0.0
		occupation.state.victory_conditions_met[hex] = false
		occupation.state.units_in_objectives[hex] = UnitsCollection.new()
	var goals: ScenarioGoalDirector = ScenarioGoalDirector.new()
	goals.configure(commander.team, [occupation], PositionProfile.Mode.ASSAULT)
	commander.goal_director = goals
	commander.receive_mission_order(goals.initial_order(commander, original_order.copy(), 300.0))
	goals.update(commander, 300.0, 10.0)
	_check(goals.assignments.size() == 2 and commander.goal_assignments == goals.assignments, "The real scenario director dispatches company objective assignments")
	var platoon_ids: Dictionary[Vector2i, bool] = {}
	for unit: Unit in goals.assignments:
		var key: Vector2i = Vector2i(int(unit.company), unit.platoon)
		platoon_ids[key] = true
		_check(command.platoons[key].planner.goal_assignments.has(unit), "Scenario duties reach the responsible subordinate planner")
	_check(platoon_ids.size() == 2, "Scenario occupation objectives retain separate platoon ownership")
	commander.goal_director = original_director
	commander.receive_mission_order(original_order)


func _test_withdrawal() -> void:
	for unit: Unit in commander.squads:
		unit.give_hold_order()
		unit.movement._process_movement(1.0)
		unit.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
	var exit: ExitUnitsCondition = ExitUnitsCondition.new()
	exit.team = commander.team
	exit.state = ExitUnitsState.new()
	exit.state.exit_hexes = [command.platoons[Vector2i(0, 1)].anchor()]
	var task: ScenarioGoalTask = ScenarioGoalTask.new()
	task.kind = ScenarioGoalTask.Kind.EXIT
	task.condition = exit
	task.key = "company_withdrawal"
	task.hex = exit.state.exit_hexes[0]
	task.withdrawal = true
	task.reason = "Withdraw the entire company"
	task.required_units = 0
	for unit: Unit in commander.squads:
		if TacticalPositionExecutor.is_active_defender(unit):
			task.required_units += 1
	exit.required_unit_count = task.required_units
	var assignments: Dictionary[Unit, ScenarioGoalTask] = command.allocate([task], {})
	_check(assignments.size() == task.required_units, "Whole-force withdrawal assigns every living squad and headquarters")
	commander.set_scenario_goal_assignments(assignments)
	for formation: CompanyPlatoon in command.platoons.values():
		_check(formation.role == CompanyPlatoon.Role.WITHDRAW and not formation.planner.company_requires_support, "Withdrawal releases every platoon from its covering-fire dependency")
	var headquarters: Unit
	for unit: Unit in assignments:
		if unit.squad_type == Globals.SquadType.COMPANY_HEADQUARTERS:
			headquarters = unit
	_check(headquarters != null and command._headquarters_planner.goal_assignments.has(headquarters), "Company headquarters receives an explicit exit mission")
	commander.receive_mission_order(commander.current_order)


func _test_reserve() -> void:
	for unit: Unit in commander.squads:
		unit.give_hold_order()
		unit.movement._process_movement(1.0)
		unit.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
	var reserve: CompanyPlatoon = _formation_for_role(CompanyPlatoon.Role.RESERVE)
	var maneuver: CompanyPlatoon = _formation_for_role(CompanyPlatoon.Role.MANEUVER)
	_check(reserve != null and maneuver != null, "A full platoon remains available as company reserve")
	if reserve == null or maneuver == null:
		return
	var old_states: Dictionary[Unit, UnitStates.MoraleState] = {}
	for unit: Unit in maneuver.combat_units():
		old_states[unit] = unit.stress_system.state
		unit.stress_system.state = UnitStates.MoraleState.PINNED
	command.reconsider(true)
	_check(reserve.reserve_deployed and reserve.role == CompanyPlatoon.Role.REINFORCE, "A disabled maneuver platoon commits the company reserve")
	for unit: Unit in old_states:
		unit.stress_system.state = old_states[unit]
	command.reconsider(true)
	_check(reserve.reserve_deployed, "Reserve recovery does not oscillate on the next assessment")
	command._clock += CompanyAI.RESERVE_RECOVERY_SECONDS + 1.0
	command.reconsider(true)
	_check(not reserve.reserve_deployed and reserve.role == CompanyPlatoon.Role.RESERVE, "A quiet reserve returns after the recovery interval")


func _test_controls() -> void:
	var order: MissionOrder = commander.current_order
	var maneuver: CompanyPlatoon = _formation_for_role(CompanyPlatoon.Role.MANEUVER)
	var unit: Unit = maneuver.combat_units()[0]
	var move: PositionResult = _move_result(unit)
	var manual_id: int = -1
	if move != null:
		maneuver.planner.executor.execute(move, TacticalPositionExecutor.Intent.ADVANCE)
		var cubes: Array[Vector3i] = []
		for cell: Vector2i in move.path:
			cubes.append(LOSHelper.ground_layer.map_to_cube(cell))
		unit.give_move_to_hex_order(move.target_hex, cubes, false)
		manual_id = unit.action_controller.action_order_id
	controller.set_team_ai_enabled(commander.team, false)
	for formation: CompanyPlatoon in command.platoons.values():
		_check(not formation.planner.active and formation.planner.executor.pending.is_empty(), "OFF cancels every subordinate planner")
	_check(commander.current_order == null and commander.squad_assignments.is_empty(), "OFF releases company mission ownership")
	if manual_id >= 0:
		_check(unit.action_controller.action_order_id == manual_id and not unit.movement.path_hexes.is_empty(), "Company OFF preserves a player order that replaced a subordinate AI order")
		unit.give_hold_order()
		unit.movement._process_movement(1.0)
		unit.action_controller.action_state = SquadActionController.SquadActionState.HOLDING_POSITION
	controller.set_team_ai_enabled(commander.team, true)
	_check(commander.current_order == order, "ON restores the company mission")
	controller.set_team_ai_mode(commander.team, PositionProfile.Mode.DEFEND)
	for formation: CompanyPlatoon in command.platoons.values():
		_check(formation.planner.current_order.position_mode == PositionProfile.Mode.DEFEND, "Posture changes propagate to every platoon")
	var sectors: Dictionary[Vector2i, bool] = {}
	for formation: CompanyPlatoon in command.platoons.values():
		for cell: Vector2i in formation.sector_cells:
			_check(not sectors.has(cell), "Company defense gives platoons separate sectors")
			sectors[cell] = true
	_check(not sectors.is_empty(), "Company defense assigns actual terrain sectors")


func _test_runtime_roster() -> void:
	var unit: Unit = command.platoons[Vector2i(0, 3)].combat_units()[0]
	unit.surrendered = true
	command.sync_roster()
	_check(not command.platoons[Vector2i(0, 3)].planner.squads.has(unit) and not command.reservations.has(unit), "Surrendered squads leave platoon control and shared reservations")
	var count: int = commander.squads.size()
	var hex: Vector2i = command.platoons[Vector2i(0, 1)].anchor()
	controller.spawn_unit_from_save(commander.team, hex, load("res://resources/squads/germany/rifle_squad.tres") as SquadLoadoutSpec, 0)
	_check(commander.squads.size() == count + 1, "Runtime reinforcements register with the company automatically")
	var added: Unit = commander.squads.back()
	_check(command.platoons.has(Vector2i(int(added.company), added.platoon)) and command.platoons[Vector2i(int(added.company), added.platoon)].planner.squads.has(added), "Runtime reinforcements join their actual platoon planner")
	for squad: Unit in commander.squads:
		if squad.platoon != 1:
			squad.surrendered = true
	command.sync_roster()
	_check(not command.uses_hierarchy() and command.platoons.size() == 1, "A depleted company falls back to its remaining platoon")
	for squad: Unit in command.platoons[Vector2i(0, 1)].squads:
		_check(squad.squad_ai_controller.defensive_mission_controlled, "Single-platoon handoff preserves defensive mission ownership")


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
