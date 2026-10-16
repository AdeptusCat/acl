extends Node

var checks: int = 0
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	await _start_mission(main, "Alderbrook5")
	_check_fog(main)
	_draw_preview()
	_check(not LOSHelper.los_lines.is_empty(), "The new company map produces a live LOS preview")
	LOSHelper.clear_los()
	_check(LOSHelper.origin_hex == Vector2i(-1, -1) and LOSHelper.los_lines.is_empty(), "Clearing LOS invalidates its drawing origin")
	LOSHelper.generate_los_lines_for_debug()
	_check(LOSHelper.los_lines.is_empty(), "Debug drawing cannot generate lines from a cleared origin")
	_draw_preview()
	_check(not LOSHelper.los_lines.is_empty(), "The same preview can be regenerated after clearing its coordinate cache")
	var old_world: Node = main.world
	LOSHelper.queue_redraw()
	main._on_try_again()
	await _settle()
	_check(not is_instance_valid(old_world) and is_instance_valid(main.world), "Retry replaces the active world through the real scene lifecycle")
	_check_unloaded()
	LOSHelper.draw_los(Vector2.ZERO, Vector2(64.0, 0.0))
	LOSHelper.generate_los_lines_for_debug()
	_check(LOSHelper.los_lines.is_empty(), "Late preview requests are harmless while the mission menu has no active map")
	await _start_mission(main, "Alderbrook1")
	_check_fog(main)
	_check(LOSHelper.grid_size == Vector2i(16, 10) and not LOSHelper.los_lookup.is_empty(), "The next mission loads its own map and LOS data")
	_draw_preview()
	_check(not LOSHelper.los_lines.is_empty(), "Drawing resumes on the replacement campaign map")
	Globals.game_started = false
	main.queue_free()
	await _settle()
	_check_unloaded()
	_test_freed_layer_draw()
	await _settle()
	print("LOS map lifecycle checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _start_mission(main: Node, map_name: String) -> void:
	var world: Node = main.world
	var map: Map = world.maps.get_node(map_name) as Map
	var scenario: Scenario = map.get_scenario(0)
	scenario.axis_ai_status = Scenario.AIStatus.OFF
	scenario.allies_ai_status = Scenario.AIStatus.OFF
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.time = scenario.duration_s / 60.0
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	_freeze(main)


func _draw_preview() -> void:
	var ground: HexagonTileMapLayer = LOSHelper.ground_layer
	LOSHelper.draw_los(ground.map_to_local(Vector2i(2, 3)), ground.map_to_local(Vector2i(3, 3)))


func _check_fog(main: Node) -> void:
	var fog: FogOfWarOverlay = main.world.fog_of_war
	var image: Image = fog._mask_image
	_check(image.get_size() == LOSHelper.grid_size, "The active fog mask uses the current mission dimensions")
	var matching: bool = true
	for x: int in range(image.get_width()):
		for y: int in range(image.get_height()):
			var cell: Vector2i = Vector2i(x, y)
			var state: Color = image.get_pixelv(cell)
			if state.r > 0.5:
				var visible: bool = LOSHelper.visible_hexes[Globals.team_player].has(cell)
				if visible != (state.g < 0.5):
					matching = false
	_check(matching, "Live fog follows the current player's LOS on startup and after returning to the menu")
	Debug.hide_fog_of_war = true
	main.world._process(0.0)
	_check(not fog.visible, "The existing fog debug toggle hides the animated overlay")
	Debug.hide_fog_of_war = false
	main.world._process(0.0)
	_check(fog.visible, "The existing fog debug toggle restores the animated overlay")


func _check_unloaded() -> void:
	_check(LOSHelper.ground_layer == null and LOSHelper.building_layer == null and LOSHelper.wall_layer == null and LOSHelper.terrain_layer == null and LOSHelper.road_layer == null, "World teardown releases all map layer references")
	_check(LOSHelper.origin_hex == Vector2i(-1, -1) and LOSHelper.los_lines.is_empty(), "World teardown removes the pending debug drawing")
	_check(LOSHelper.grid_size == Vector2i.ZERO and LOSHelper.los_lookup.is_empty() and LOSHelper.visible_hexes[Globals.Team.ALLIES].is_empty() and LOSHelper.visible_hexes[Globals.Team.AXIS].is_empty(), "World teardown clears map-specific visibility and lookup state")


func _test_freed_layer_draw() -> void:
	var ground: HexagonTileMapLayer = HexagonTileMapLayer.new()
	LOSHelper.ground_layer = ground
	LOSHelper.origin_hex = Vector2i(2, 3)
	LOSHelper.los_lines = [{"blocked": false, "block_point": null, "target_pos": Vector2.ZERO}]
	ground.free()
	# Exercise the draw callback with a dangling reference and a pending line.
	LOSHelper._draw()
	LOSHelper.draw_los(Vector2.ZERO, Vector2(64.0, 0.0))
	_check(LOSHelper.los_lines.is_empty() and LOSHelper.origin_hex == Vector2i(-1, -1), "A freed layer cannot be accessed by late drawing or preview requests")
	LOSHelper.origin_hex = Vector2i(2, 3)
	LOSHelper.generate_los_lines_for_debug()
	_check(LOSHelper.origin_hex == Vector2i(-1, -1), "Debug line generation also rejects a freed layer")
	LOSHelper.unload_map()


func _settle() -> void:
	for frame: int in range(8):
		await get_tree().process_frame


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
