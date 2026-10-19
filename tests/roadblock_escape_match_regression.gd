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
	var saw_bypass: bool = false
	var saw_pinned: bool = false
	var started: bool = false
	# Keep authored forces, visibility, movement, damage, morale, victory rules and player orders.
	for frame: int in range(180 * 60):
		started = started or Globals.game_started
		if frame % (5 * 60) == 0:
			for task: ScenarioGoalTask in planner.goal_director.tasks:
				_check(task.kind == ScenarioGoalTask.Kind.EXIT and task.escape_policy != null, "The column retains escape instead of contesting A")
			for unit: Unit in planner.squads:
				saw_pinned = saw_pinned or unit.stress_system.state == STATES.MoraleState.PINNED
				var advice: PositionResult = unit.position_advice
				if advice != null and advice.is_valid() and advice.features.get("escape", false) and unit.movement.is_moving:
					saw_bypass = true
		if exit.is_condition_met():
			print("Roadblock column reached its exit quota after ", float(frame) / 60.0, " seconds")
			break
		if started and not Globals.game_started:
			break
		await get_tree().process_frame
	_check(saw_bypass, "The normal match executes bypass movement")
	_check(saw_pinned, "The live reproduction includes temporary pinning")
	_check(exit.is_condition_met(), "The column actually exits three units with normal combat and no player orders")
	var headquarters_exited: bool = false
	for unit: Unit in exit.state.units_exited:
		headquarters_exited = headquarters_exited or HqSupportPositionPolicy.is_headquarters(unit)
	_check(headquarters_exited, "Headquarters physically escape and count toward the result")
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
