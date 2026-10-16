extends Node

var checks: int = 0
var failures: int = 0
var planner: PlatoonAI
var controller: InfluenceMapController
var main: Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(6049)
	Engine.max_fps = 60
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map_name: String = "Alderbrook5"
	var scenario_index: int = 0
	if OS.get_cmdline_user_args().has("--outpost") or OS.get_cmdline_user_args().has("--single"):
		map_name = "DefaultMap"
	if OS.get_cmdline_user_args().has("--single"):
		scenario_index = 2
	var map: Map = world.maps.get_node(map_name) as Map
	var scenario: Scenario = map.get_scenario(scenario_index)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.time = scenario.duration_s / 60.0
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	planner = world.game_controller.platoon_ai
	controller = world.game_controller.influence_map_controller
	_check(not scenario.victory_conditions.is_empty(), "The authored victory conditions remain active")
	for unit: Unit in Globals.get_units():
		unit.squad_fire.process_mode = Node.PROCESS_MODE_DISABLED
		unit.squad_ai_controller.process_mode = Node.PROCESS_MODE_DISABLED
		unit.stress_system.process_mode = Node.PROCESS_MODE_DISABLED
		unit.combat_stats_timer.stop()
		if unit.team == planner.team:
			unit.movement.base_speed = 90.0
			unit.movement.move_speed = 90.0
	var frames: int = 0
	while frames < 1800:
		await get_tree().process_frame
		frames += 1
		if frames >= 1200 and _complete():
			break
	_check(_complete(), "Every surviving squad receives an opening decision")
	_test_goal_duties()
	var fronts: Array[PlatoonAI] = []
	if planner.company_command.uses_hierarchy():
		var sectors: Dictionary[Vector2i, int] = {}
		for formation: CompanyPlatoon in planner.company_command.platoons.values():
			if formation.task != null and formation.task.kind == ScenarioGoalTask.Kind.OCCUPY and not _contested(formation.objective):
				_check(formation.role == CompanyPlatoon.Role.DEFEND and formation.planner.current_order.position_mode == PositionProfile.Mode.DEFEND, "An uncontested occupation does not turn its platoon into an assault formation")
			if formation.role != CompanyPlatoon.Role.DEFEND or formation.support_firepower() <= 0.0:
				continue
			fronts.append(formation.planner)
			_check(not formation.sector_cells.is_empty(), "Defending platoons receive sectors across distinct objectives")
			for cell: Vector2i in formation.sector_cells:
				_check(not sectors.has(cell), "Defensive sectors have one platoon owner")
				sectors[cell] = formation.number
	else:
		fronts.append(planner)
		_check(OS.get_cmdline_user_args().has("--single"), "A single platoon uses the same defensive planner without company command")
	var approach_positions: int = 0
	var forward_positions: int = 0
	for front: PlatoonAI in fronts:
		var counts: Dictionary = _test_front(front)
		approach_positions += counts["approach"]
		forward_positions += counts["forward"]
	_check(approach_positions > 0, "The defense assigns useful approach coverage beyond mandatory garrisons")
	if map_name == "Alderbrook5":
		_check(forward_positions >= 2, "Village defense establishes multiple positions beyond the objective's adjacent hexes")
	_test_intents()
	print("Deployment summary: ", scenario.scenario_name, "; approach positions: ", approach_positions, "; forward positions: ", forward_positions, "; frames: ", frames)
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Defensive deployment checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _complete() -> bool:
	for unit: Unit in planner.squads:
		if TacticalPositionExecutor.is_active_defender(unit) and PositionQueryService.can_follow_intent(unit) and not planner.squad_assignments.has(unit):
			return false
	return not planner.squad_assignments.is_empty()


func _contested(hex: Vector2i) -> bool:
	for contact: InfluenceContact in controller.snapshot.get_contacts(planner.team):
		if contact.observed and contact.hex == hex and TacticalPositionExecutor.is_active_defender(contact.unit):
			return true
	return false


func _test_goal_duties() -> void:
	for task: ScenarioGoalTask in planner.goal_director.tasks:
		if task.kind != ScenarioGoalTask.Kind.OCCUPY:
			continue
		for other: ScenarioGoalTask in planner.goal_director.tasks:
			_check(other.hex != task.hex or other.kind != ScenarioGoalTask.Kind.DENY_OCCUPATION, "Own occupation and enemy denial share one garrison duty")
		var assigned: int = 0
		for unit: Unit in planner.goal_assignments:
			if planner.goal_assignments[unit].key == task.key:
				assigned += 1
		_check(assigned == task.required_units, "Occupation receives exactly its required garrison capacity")


func _test_front(front: PlatoonAI) -> Dictionary:
	var approach: int = 0
	var forward: int = 0
	for unit: Unit in front.squad_assignments:
		var assignment: Dictionary = front.squad_assignments[unit]
		var result: PositionResult = assignment["result"]
		if front._has_objective_goal_duty():
			_check(assignment["role"] != "guard_objective", "A scenario objective duty is not duplicated by an automatic guard")
		if not result.is_valid() or HqSupportPositionPolicy.is_headquarters(unit):
			continue
		if assignment["role"] == "defend_sector":
			_check(result.features.get("assigned_coverage", 0.0) >= DefensePositionPolicy.MIN_APPROACH_COVERAGE, "A sector squad actually covers its assigned approach")
			_check(result.features.get("preserves_screen", false), "An accepted forward move preserves existing covering fire")
			_check(result.features.get("exposure_seconds", 0.0) <= 6.0 and result.features.get("open_exposure_seconds", 0.0) <= 2.0, "Deployment routes retain exposure limits")
			approach += 1
			if LOSHelper.get_hex_distance(result.target_hex, front.current_order.objective_hex) > 1:
				forward += 1
		print("Deployment position: ", unit.name, "; role: ", assignment["role"], "; at: ", unit.current_hex, "; target: ", result.target_hex, "; coverage: ", result.features.get("assigned_coverage", 0.0))
	if front.squads.size() <= 3:
		_check(front.reserve_squad == null, "A small outpost does not withhold a needed combat squad as a reserve")
	return {"approach": approach, "forward": forward}


func _test_intents() -> void:
	if not planner.company_command.uses_hierarchy():
		return
	var command: CompanyAI = planner.company_command
	var formation: CompanyPlatoon
	for candidate: CompanyPlatoon in command.platoons.values():
		if candidate.can_maneuver():
			formation = candidate
			break
	_check(formation != null, "Intent validation has a maneuver-capable platoon")
	if formation == null:
		return
	var saved: ScenarioGoalTask = formation.task
	var saved_objective: Vector2i = formation.objective
	var saved_contacts: Array[InfluenceContact] = controller.snapshot.get_contacts(planner.team)
	var occupation: ScenarioGoalTask = ScenarioGoalTask.new()
	occupation.kind = ScenarioGoalTask.Kind.OCCUPY
	occupation.hex = formation.anchor()
	formation.task = occupation
	formation.objective = occupation.hex
	controller.snapshot.contacts[planner.team] = []
	_check(not command._needs_attack(formation), "An empty or friendly objective retains defensive intent")
	var contact: InfluenceContact = InfluenceContact.new()
	for enemy: Unit in Globals.get_units_for_team(Globals.get_enemy_team(planner.team)):
		if TacticalPositionExecutor.is_active_defender(enemy) and enemy.is_good_order():
			contact.unit = enemy
			break
	contact.hex = occupation.hex
	contact.observed = true
	controller.snapshot.contacts[planner.team] = [contact]
	_check(command._needs_attack(formation), "A confirmed enemy on the objective permits a counterattack")
	controller.snapshot.contacts[planner.team] = saved_contacts
	formation.task = saved
	formation.objective = saved_objective


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
