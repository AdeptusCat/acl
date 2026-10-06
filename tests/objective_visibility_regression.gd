extends Node

# Run with: godot --headless --path . tests/objective_visibility_regression.tscn
# Additional cases: -- --allies, -- --defend, or -- --allies --defend.
var failures: int = 0
var match_started: bool = false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var player_team: Globals.Team = Globals.Team.AXIS
	var game_mode: Globals.GameMode = Globals.GameMode.ATTACK
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.has("--allies"):
		player_team = Globals.Team.ALLIES
	if arguments.has("--defend"):
		game_mode = Globals.GameMode.DEFEND
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map: Map = world.maps.get_child(1)
	var scenario: Scenario = map.get_scenario(0)
	scenario.player_team = player_team
	# This scenario normally gives Axis only a start marker, removed during setup.
	# Add Objective A from its existing Axis tileset to exercise a visible marker.
	scenario.axis_objectives_tile_map_layer.set_cell(Vector2i(10, 12), 3, Vector2i.ZERO)
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	var controller: Node = world.game_controller
	controller.start_match.connect(_on_match_started)
	world.start_screen.hide()
	# Exercise the same signal connection used by the scenario-selection screen.
	world.start_screen.game_started.emit(map, scenario, scenario.player_team, game_mode)
	for frame: int in range(10):
		if match_started:
			break
		await get_tree().process_frame
	_freeze_simulation(main)
	_check(match_started, "Scenario selection starts the match")
	_check(Globals.team_player == player_team, "Startup retains the selected faction")
	_check(Globals.game_mode == game_mode, "Startup retains the selected game mode")
	var axis_layer: TileMapLayer = controller.axis_objective_tilemap
	var allies_layer: TileMapLayer = controller.allies_objective_tilemap
	_check(not axis_layer.get_used_cells().is_empty() and not allies_layer.get_used_cells().is_empty(), "Fixture includes objectives for both factions")
	_check_view(controller, player_team, "Scenario startup")
	_check_objective_data(controller)
	var objective_definitions: Dictionary[Globals.Team, ObjectivesCollection] = Globals.objectives.duplicate()
	var axis_cells: Array[Vector2i] = axis_layer.get_used_cells()
	var allies_cells: Array[Vector2i] = allies_layer.get_used_cells()
	# Repeated setup must recover from either layer already being hidden.
	for team: Globals.Team in [Globals.Team.AXIS, Globals.Team.ALLIES, player_team, player_team]:
		controller.set_objective_cells(team)
		_check_view(controller, team, "Repeated objective setup")
		_check_objective_data(controller)
	_check(axis_layer.get_used_cells() == axis_cells and allies_layer.get_used_cells() == allies_cells, "Visibility changes preserve authored objective tiles")
	_check(Globals.objectives == objective_definitions, "Visibility changes preserve victory-condition objective definitions")
	axis_layer.clear()
	allies_layer.clear()
	for team: Globals.Team in [Globals.Team.AXIS, Globals.Team.ALLIES]:
		controller.set_objective_cells(team)
		_check_view(controller, team, "Empty objective layers")
		_check(Globals.objective_hexes.is_empty(), "Empty layers clear previous objective hexes")
	var soldiers: Array[Soldier] = []
	for unit: Unit in Globals.get_units():
		soldiers.append_array(unit.squad_fire.soldiers)
	# Free the fixture's existing unparented soldier tasks separately.
	for soldier: Soldier in soldiers:
		var tasks: Array[SoldierTask] = [
			soldier.setup_weapon_task, soldier.aquire_target_task, soldier.reload_task,
			soldier.fire_weapon_task, soldier.assist_task, soldier.close_combat_task,
		]
		for task: SoldierTask in tasks:
			if is_instance_valid(task):
				task.free()
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Objective visibility regression failures: ", failures)
	get_tree().quit(failures)


func _check_view(controller: Node, player_team: Globals.Team, label: String) -> void:
	var axis_layer: TileMapLayer = controller.axis_objective_tilemap
	var allies_layer: TileMapLayer = controller.allies_objective_tilemap
	_check(axis_layer.visible == (player_team == Globals.Team.AXIS), label + ": Axis visibility matches the player faction")
	_check(allies_layer.visible == (player_team == Globals.Team.ALLIES), label + ": Allied visibility matches the player faction")
	if player_team == Globals.Team.AXIS:
		_check(axis_layer.is_visible_in_tree(), label + ": Axis objectives are visible after reparenting")
	else:
		_check(allies_layer.is_visible_in_tree(), label + ": Allied objectives are visible after reparenting")


func _check_objective_data(controller: Node) -> void:
	for team: Globals.Team in [Globals.Team.AXIS, Globals.Team.ALLIES]:
		var layer: TileMapLayer = controller.allies_objective_tilemap
		if team == Globals.Team.AXIS:
			layer = controller.axis_objective_tilemap
		_check(Globals.objective_hexes.get(team, []) == layer.get_used_cells(), "Both factions retain their objective hexes")


func _freeze_simulation(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	if node is Timer:
		var timer: Timer = node as Timer
		timer.stop()
	for child: Node in node.get_children():
		_freeze_simulation(child)


func _on_match_started() -> void:
	match_started = true


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)
