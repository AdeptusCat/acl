extends Node

var checks: int = 0
var failures: int = 0
var main: Node
var planner: PlatoonAI
var controller: InfluenceMapController
var player_positions: Dictionary[Unit, Vector2i] = {}
var village: bool = true


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(6049)
	Engine.max_fps = 0
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map_name: String = "Alderbrook5"
	var scenario_index: int = 0
	var seconds: int = 180
	if OS.get_cmdline_user_args().has("--outpost") or OS.get_cmdline_user_args().has("--single"):
		map_name = "DefaultMap"
		seconds = 120
		village = false
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
	for unit: Unit in Globals.get_units_for_team(scenario.player_team):
		player_positions[unit] = unit.current_hex
	# Keep normal movement speeds, combat, morale, perception and scenario duties.
	for frame: int in range(seconds * 60 + 1):
		if frame >= 90 * 60 and frame % (30 * 60) == 0:
			_sample(floori(float(frame) / 60.0))
		await get_tree().process_frame
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Idle defense checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _sample(seconds: int) -> void:
	if planner.goal_director.active_fallback != null:
		_check(not village, "The stationary-player village match retains its defense")
		_check(not planner.goal_director.fallback_reason.is_empty(), "An authored withdrawal retains its activation reason")
		for task: ScenarioGoalTask in planner.goal_director.tasks:
			_check(task.kind == ScenarioGoalTask.Kind.EXIT and task.withdrawal, "An authorized withdrawal releases the abandoned defensive duties")
		print("Idle defense withdrawal: ", seconds, "; ", planner.goal_director.fallback_reason)
		return
	var fronts: Array[PlatoonAI] = [planner]
	if planner.company_command.uses_hierarchy():
		fronts.clear()
		for formation: CompanyPlatoon in planner.company_command.platoons.values():
			if formation.role == CompanyPlatoon.Role.DEFEND and formation.support_firepower() > 0.0:
				fronts.append(formation.planner)
	var actual_screens: int = 0
	var reserves: int = 0
	var needs_screen: bool = false
	for front: PlatoonAI in fronts:
		var screens: int = 0
		var capable: int = 0
		for unit: Unit in front.squads:
			if DefenseSectorAllocator.combat_reserve_capable(unit):
				capable += 1
				if not front.goal_assignments.has(unit) and unit != front.reserve_squad:
					needs_screen = true
		for unit: Unit in front.squad_assignments:
			if not DefenseSectorAllocator.combat_reserve_capable(unit) or unit.movement.is_moving:
				continue
			var advice: Dictionary = front.squad_assignments[unit]
			var result: PositionResult = advice["result"]
			if not result.is_valid() or advice["role"] != "defend_sector" or front.defense_area == null:
				continue
			var query: PositionQuery = PositionQuery.new()
			query.unit = unit
			query.team = planner.team
			query.snapshot = controller.snapshot
			query.objective_hex = front.current_order.objective_hex
			query.defense_area = front.defense_area
			query.assigned_sector = result.features.get("assigned_sector", -1)
			query.assigned_branch = result.features.get("assigned_branch", "")
			DefensePositionPolicy.prepare(query)
			var progress: int = DefensePositionPolicy.forward_progress(query, unit.current_hex)
			var branch: Dictionary = front.defense_area.branch_for_key(query.assigned_branch)
			var coverage: float = 0.0
			if not branch.is_empty():
				coverage = front.defense_area.coverage(query, unit, unit.current_hex, branch)["coverage"]
			var established: bool = unit.current_hex != query.objective_hex and coverage >= DefensePositionPolicy.MIN_APPROACH_COVERAGE
			if village:
				established = established and progress >= 2
			if established:
				var formation: Dictionary = DefensePositionPolicy.deployment_features(query, unit.current_hex)
				if capable >= 2:
					_check(formation["mutual_support"] > 0.0, "The actual forward screen has established friendly support")
				screens += 1
			print("Idle defender: ", seconds, "; ", unit.name, "; actual: ", unit.current_hex, "; progress: ", progress, "; coverage: ", coverage, "; role: ", advice["role"])
		actual_screens += screens
		if village:
			_check(screens > 0, "Each village district retains an actual forward screen after the opening")
		if DefenseSectorAllocator.combat_reserve_capable(front.reserve_squad) and not front.reserve_deployed:
			reserves += 1
			_check(not front.reserve_squad.movement.is_moving, "A quiet reserve reaches its protected response position")
			_check(front.reserve_squad.current_hex != front.current_order.objective_hex, "A reserve does not duplicate the objective garrison")
			print("Idle reserve: ", seconds, "; ", front.reserve_squad.name, "; actual: ", front.reserve_squad.current_hex, "; reason: ", front.reserve_reason)
	_check(not needs_screen or actual_screens > 0, "Capable squads remaining after scenario duties establish actual approach coverage")
	if village:
		_check(reserves == 1, "A nine-squad company retains one mobile reserve across its three objectives")
	else:
		_check(reserves == 0, "The smaller outpost force keeps its needed squads in the defense")
	for task: ScenarioGoalTask in planner.goal_director.tasks:
		if task.kind != ScenarioGoalTask.Kind.OCCUPY:
			continue
		var stationed: int = 0
		for unit: Unit in planner.squads:
			if not HqSupportPositionPolicy.is_headquarters(unit) and unit.is_good_order() and not unit.movement.is_moving and unit.current_hex == task.hex:
				stationed += 1
		_check(stationed == task.required_units, "Each required objective has its minimum actual garrison")
	for unit: Unit in player_positions:
		if TacticalPositionExecutor.is_active_defender(unit) and unit.is_good_order():
			_check(unit.current_hex == player_positions[unit], "The player remains stationary throughout the idle reproduction")
	print("Idle defense sample: ", seconds, "; screens: ", actual_screens, "; reserves: ", reserves)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
