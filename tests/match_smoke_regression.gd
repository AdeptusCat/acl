extends Node

# Active scene integration, with --default-map for the other authored map.
# Use --fixed-fps 60 for deterministic frame progression and isolated user data.
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	seed(6049)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map_index: int = 1
	if OS.get_cmdline_user_args().has("--default-map"):
		map_index = 0
	var map: Map = world.maps.get_child(map_index)
	var scenario: Scenario = map.get_scenario(0)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	var controller: Node = world.game_controller
	var players: Array[Unit] = Globals.get_units_for_team(Globals.team_player)
	_check(not players.is_empty(), "Scenario initializes player units")
	var selected: Unit = players[0]
	controller._select_unit(selected)
	controller.show_unit_details_in_ui.emit(selected)
	SessionSettings.showCmdConnectivity = true
	Debug.showEnemyCmdConnectivity = true
	Debug.draw_thread_map = true
	controller.influence_map_debug_draw.set_team(Globals.team_player)
	controller.influence_map_debug_draw.set_debug_view(InfluenceMapDebugDraw.DebugView.FIRE_POWER)
	controller.influence_map_debug_draw.show()
	for frame: int in range(600):
		await get_tree().process_frame
	var state: Array[Dictionary] = []
	for unit: Unit in Globals.get_units():
		_check(unit.squad_fire.soldiers.size() == unit.members_alive, "Active match retains consistent runtime strength")
		state.append({"name": str(unit.name), "team": unit.team, "hex": [unit.current_hex.x, unit.current_hex.y],
			"members": unit.members_alive, "casualties": unit.casualties_taken, "alive": unit.alive})
	print("Active match snapshot: ", JSON.stringify({"map": str(map.name), "units": state, "rng_tail": randf()}))
	if controller.selected_unit != null:
		controller._deselect_unit(controller.selected_unit)
	controller.time_left_seconds = 0.0
	controller._on_win_condition_timer_timeout()
	_check(world.result_screen.visible, "Match result reaches the existing screen")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Match smoke regression failures: ", failures)
	get_tree().quit(failures)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
