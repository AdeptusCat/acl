extends Node

var failures: int = 0
var checks: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(6049)
	Engine.max_fps = 0
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map: Map = world.maps.get_node("Alderbrook3") as Map
	var scenario: Scenario = map.get_scenario(0)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.time = scenario.duration_s / 60.0
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.DEFEND)
	var planner: PlatoonAI = world.game_controller._ai_director_for_team(Globals.Team.AXIS).platoon_ai
	var exit: ExitUnitsCondition = scenario.ai_escape_policies[0].exit_condition
	var saw_pinned: bool = false
	var started: bool = false
	var headquarters_origins: Dictionary[Unit, Vector2i] = {}
	var headquarters_moved: Dictionary[Unit, bool] = {}
	for unit: Unit in planner.squads:
		if HqSupportPositionPolicy.is_headquarters(unit):
			headquarters_origins[unit] = unit.current_hex
	# Keep authored forces, visibility, movement, damage, morale, victory rules and player orders.
	for frame: int in range(90 * 60):
		started = started or Globals.game_started
		for unit: Unit in headquarters_origins:
			if is_instance_valid(unit) and unit.current_hex != headquarters_origins[unit]:
				headquarters_moved[unit] = true
		if frame % (5 * 60) == 0:
			for task: ScenarioGoalTask in planner.goal_director.tasks:
				_check(task.kind == ScenarioGoalTask.Kind.EXIT and task.escape_policy != null, "The column retains escape instead of contesting A")
			for unit: Unit in planner.squads:
				saw_pinned = saw_pinned or unit.stress_system.state == STATES.MoraleState.PINNED
		if exit.is_condition_met():
			print("Roadblock column reached its exit quota after ", float(frame) / 60.0, " seconds")
			break
		if started and not Globals.game_started:
			break
		await get_tree().process_frame
	_check(exit.is_condition_met(), "The normal column bypasses the roadblock and satisfies the authored escape quota under live fire")
	_check(saw_pinned, "The live reproduction includes temporary pinning without abandoning escape")
	_check(headquarters_origins.size() == 3 and headquarters_moved.size() == headquarters_origins.size(), "All three headquarters move with the column instead of waiting at their starting positions")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Roadblock escape match checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
