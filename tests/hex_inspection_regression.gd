extends Node

var checks: int = 0
var failures: int = 0
var map_clicks: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var map: Map = world.maps.get_node("DefaultMap")
	var scenario: Scenario = map.get_scenario(0)
	scenario.axis_ai_status = Scenario.AIStatus.OFF
	scenario.allies_ai_status = Scenario.AIStatus.OFF
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	_freeze(main)
	world.ui.hide_target_hex_cover_distance()
	get_tree().root.size = Vector2i(1440, 900)
	var card: PanelContainer = world.ui.tile_details
	var overlay: HexInspectionOverlay = world.hex_inspection
	var ground: HexagonTileMapLayer = world.ground_layer
	var controller: Node2D = world.game_controller
	var squad: Unit = Globals.get_units_for_team(Globals.team_player)[1]
	await _settle()
	_check(not card.visible and not overlay.visible, "Terrain inspection starts hidden")
	var hex: Vector2i = squad.current_hex
	var hex_point: Vector2 = controller.get_global_transform_with_canvas() * ground.map_to_local(hex)
	_pointer_event(hex_point, MouseButton.MOUSE_BUTTON_LEFT)
	overlay.set_process(false)
	await _settle()
	_check(card.visible and world.has_inspected_hex and card.inspected_hex == hex, "Selecting a hex opens its own terrain data rather than the mouse's previous hex")
	var summary_height: float = _screen_rect(card).size.y
	_check(is_equal_approx(card.size.x, 240.0) and summary_height >= 70.0 and summary_height <= 110.0, "The terrain summary fits a compact fixed-width card with readable type: %s" % _screen_rect(card).size)
	_check(card.details.folded and not card.has_node("FoldableContainer/VBoxContainer/Tile"), "Detailed information starts collapsed and the duplicate tile preview is removed")
	var style: StyleBoxFlat = card.get_theme_stylebox("panel") as StyleBoxFlat
	_check(is_equal_approx(style.bg_color.a, 1.0), "The card has an opaque readable background")
	var sample: Dictionary = {"hex": hex, "tile_name": "Stone building", "cover_in_hex": 3, "blocking": true, "hindrance": true, "cover_n": 1, "cover_ne": 2, "cover_se": 0, "cover_s": 2, "cover_sw": 0, "cover_nw": 1}
	card.show_tile_data(sample)
	overlay.inspect(ground, sample)
	overlay.set_process(false)
	await _settle()
	_check(card.terrain_name.text == "Stone building" and card.cover_label.text == "Hex cover: 3" and card.sight_label.text.contains("blocks"), "The summary labels terrain, interior protection and sight obstruction")
	_check(overlay.segments.size() == 4, "Only protected hex edges receive map markings")
	var center: Vector2 = ground.map_to_local(hex)
	for segment: Dictionary in overlay.segments:
		var midpoint: Vector2 = (segment["start"] + segment["end"]) * 0.5
		var direction: int = int(segment["direction"])
		var neighbor: Vector2 = ground.cube_to_local(ground.map_to_cube(hex) + ground.cube_direction(HexInspectionOverlay.DIRECTIONS[direction]))
		_check((midpoint - center).normalized().dot((neighbor - center).normalized()) > 0.95, "The cover marking faces the correct neighboring hex")
	card.details.expand()
	await _settle()
	_check(card.features.text.contains("Blocks sight: Yes") and card.features.text.contains("Obscures sight: Yes"), "Expanded details retain both blocking and obscuring effects")
	_check(card.edge_values[0].text == "Cover 1" and card.edge_values[1].text == "Cover 2" and card.edge_values[2].text == "None", "The full breakdown labels protected and unprotected sides")
	_check(_screen_rect(card).size.y <= 350.0 and _inside(card, world), "The expanded breakdown remains bounded inside the viewport: %s" % _screen_rect(card).size)
	var first: Dictionary = overlay.segments[0]
	var midpoint: Vector2 = (first["start"] + first["end"]) * 0.5
	var screen_point: Vector2 = overlay.get_global_transform_with_canvas() * midpoint
	overlay.update_hover(midpoint, screen_point)
	await _settle()
	_check(world.ui.hex_edge_hint.visible and world.ui.hex_edge_hint.heading.text == "North edge · Cover 1", "Hovering a marked edge explains its direction and protection value")
	_check(world.ui.hex_edge_hint.detail.text.contains("this side") and _inside(world.ui.hex_edge_hint, world), "The edge explanation is readable and remains onscreen")
	overlay.update_hover(first["label"], screen_point)
	_check(world.ui.hex_edge_hint.visible, "The cover value badge also displays its edge explanation")
	overlay.update_hover(center, overlay.get_global_transform_with_canvas() * center)
	_check(not world.ui.hex_edge_hint.visible, "Moving off a protected edge removes its explanation")
	sample["cover_in_hex"] = 0
	sample["blocking"] = false
	sample["tile_name"] = "Woods"
	card.show_tile_data(sample)
	_check(card.cover_label.text == "Hex cover: none" and card.sight_label.text.contains("obscures"), "Obscuring terrain is distinct from building protection")
	var other: Vector2i = ground.cube_to_map(ground.cube_neighbors(squad.current_cube)[0])
	sample["hex"] = other
	sample["tile_name"] = ""
	sample["hindrance"] = false
	card.show_tile_data(sample)
	await _settle()
	_check(card.terrain_name.text == "Open ground" and card.sight_label.text.contains("clear") and not card.details.folded, "Changing hex preserves expanded details and clears old terrain properties")
	world._on_hex_selected(other, Vector2.ZERO)
	await _settle()
	_check(card.visible and card.inspected_hex == other and not card.details.folded, "Selecting another hex through the world preserves expanded terrain details")
	world._on_hex_selected(hex, Vector2.ZERO)
	await _settle()
	_check(card.visible and card.inspected_hex == hex and not card.details.folded, "Selecting the previous hex keeps terrain details expanded")
	world.input_manager.mouse_button_left_pressed.connect(_on_map_click)
	_pointer_event(_screen_rect(card.get_node("Content/Heading/Close")).get_center(), MouseButton.MOUSE_BUTTON_LEFT)
	_check(not card.visible and not overlay.visible and not world.has_inspected_hex and map_clicks == 0, "The Close button clears the card, map markings and inspection without clicking the map")
	world._on_hex_selected(hex, Vector2.ZERO)
	_check(not card.details.folded, "Reopening terrain inspection preserves expanded details")
	world._on_hex_selected(hex, Vector2.ZERO)
	_check(world.has_inspected_hex and world.selected_hex == hex and card.visible and card.inspected_hex == hex and not card.details.folded,
		"Clicking an inspected hex again preserves selection and expanded terrain details")
	_check(world.selected_tile_map_layer.get_cell_source_id(hex) != -1, "Clicking the selected hex again preserves its map highlight")
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape, true)
	_check(not world.has_inspected_hex and not overlay.visible, "Escape dismisses terrain inspection")
	world._on_hex_selected(hex, Vector2.ZERO)
	var settings: Control = world.ui.get_node("Control/Settings") as Control
	settings._on_controls_toggled(true)
	get_viewport().push_input(escape, true)
	_check(not settings.controls_panel.visible and world.has_inspected_hex, "Escape closes an open menu before clearing terrain inspection")
	get_viewport().push_input(escape, true)
	_check(not world.has_inspected_hex, "A subsequent Escape closes inspection")
	world._on_hex_selected(hex, Vector2.ZERO)
	world.ui.squad_roster._on_row_pressed(world.ui.squad_roster.rows[squad])
	_check(not card.visible and controller.selected_unit == squad, "Roster selection ends terrain inspection while retaining squad selection")
	world._on_hex_selected(Vector2i(-9999, -9999), Vector2.ZERO)
	_check(not card.visible and not overlay.visible, "Clicking outside the map does not leave terrain details open")
	# Preview tests use the same adapter as mouse and camera movement, with fixed coordinates.
	_pointer_event(Vector2(600, 300), MouseButton.MOUSE_BUTTON_WHEEL_UP)
	var visible_targets: Dictionary = LOSHelper.los_lookup.get(squad.current_hex, {})
	var clear_target: Vector2i
	for candidate: Vector2i in visible_targets:
		if ground.get_cell_source_id(candidate) != -1 and candidate != squad.current_hex and ground.cube_distance(squad.current_cube, ground.map_to_cube(candidate)) <= InfluenceUnitQuery.get_unit_range(squad):
			clear_target = candidate
			break
	MatchInteractionHandler.refresh_target_preview(controller, ground.map_to_local(clear_target), Vector2(800, 300))
	await _settle()
	var aim: Control = world.ui.target_cover_distance
	_check(aim.visible and aim.heading.text == "Line of sight clear", "A clear aiming line has explicit sight feedback")
	_check(not LOSHelper.los_lines.is_empty(), "Aiming displays its line of sight on the battlefield")
	LOSHelper.clear_los()
	MatchInteractionHandler.refresh_target_preview(controller, ground.map_to_local(clear_target), Vector2(800, 300))
	_check(not LOSHelper.los_lines.is_empty(), "Returning to the same target after closing inspection restores its sight line")
	_check(aim.detail.text.contains("Cover: %d" % int(visible_targets[clear_target]["target_cover"])), "Aiming uses cover from the actual firing direction")
	_check(aim.detail.text.contains("Distance:") and aim.extra.text.contains("Effective firepower:"), "Distance and effective firepower remain readable in the target hint")
	_pointer_event(_screen_rect(settings.settings_button).get_center(), MouseButton.MOUSE_BUTTON_WHEEL_UP)
	MatchInteractionHandler.refresh_target_preview(controller, ground.map_to_local(clear_target), Vector2(800, 300))
	_check(not aim.visible and LOSHelper.los_lines.is_empty(), "Hovering HUD controls clears aiming feedback and its battlefield line")
	_pointer_event(Vector2(600, 300), MouseButton.MOUSE_BUTTON_WHEEL_UP)
	var blocked_target: Vector2i
	for candidate: Vector2i in ground.get_used_cells():
		if not visible_targets.has(candidate) and candidate != squad.current_hex:
			blocked_target = candidate
			break
	MatchInteractionHandler.refresh_target_preview(controller, ground.map_to_local(blocked_target), Vector2(1138, 705))
	await _settle()
	_check(aim.visible and (aim.heading.text == "Line of sight blocked" or aim.heading.text == "Out of range") and aim.detail.text.contains("unknown (blocked sight)") and controller.firepower == 0.0, "Blocked targets explain missing sight without claiming zero cover")
	_check(_inside(aim, world), "The target hint flips inward at viewport edges")
	MatchInteractionHandler.refresh_target_preview(controller, ground.map_to_local(squad.current_hex), Vector2(800, 300))
	_check(not aim.visible, "Aiming at the selected squad's own hex hides the target hint")
	controller._deselect_unit(squad)
	MatchInteractionHandler.refresh_target_preview(controller, ground.map_to_local(clear_target), Vector2(800, 300))
	_check(not aim.visible, "Deselecting the squad removes aiming feedback")
	# Capture actual terrain with a wall, rather than the synthetic values above.
	var wall_hex: Vector2i = _find_wall_hex(world)
	world._on_hex_selected(wall_hex, Vector2.ZERO)
	overlay.set_process(false)
	controller.move_camera(wall_hex)
	controller.camera.reset_smoothing()
	controller.camera.force_update_scroll()
	await _settle()
	_check(overlay.segments.size() > 0, "Real map wall data produces visible directional cover")
	_check(not card.get_rect().intersects(world.ui.squad_roster.get_rect()), "The terrain card leaves room for the squad roster")
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("compact-wide")
		var edge: Dictionary = overlay.segments[0]
		var edge_point: Vector2 = (edge["start"] + edge["end"]) * 0.5
		overlay.update_hover(edge_point, overlay.get_global_transform_with_canvas() * edge_point)
		await _capture("edge-wide")
		overlay.update_hover(ground.map_to_local(wall_hex), Vector2.ZERO)
	card.details.expand()
	await _settle()
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("details-wide")
	get_tree().root.size = Vector2i(800, 600)
	card.details.fold()
	await _settle()
	world.ui.show_target_hex_cover_distance(Vector2(1140, 850), 2, 4, 3.0)
	await _settle()
	_check(_inside(card, world) and _inside(world.ui.target_cover_distance, world), "The terrain card and target hint fit a small viewport")
	_check(not world.ui.target_cover_distance.get_global_rect().intersects(world.ui.unit_details.get_global_rect()), "The target hint avoids the selected squad summary")
	_check(not card.get_rect().intersects(world.ui.get_node("Control/Debug").get_rect()), "The terrain card avoids collapsed development controls")
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("compact-small")
	world.clear_hex_inspection()
	_check(world.selected_tile_map_layer.get_used_cells().is_empty() and overlay.segments.is_empty(), "Ending inspection removes every stale map marker")
	main.queue_free()
	await _settle()
	print("Hex inspection checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _find_wall_hex(world: Node) -> Vector2i:
	for hex: Vector2i in world.wall_layer.get_used_cells():
		if world.ground_layer.get_cell_source_id(hex) == -1:
			continue
		var data: Dictionary = world.get_hex_inspection_data(hex)
		for key: String in HexInspectionOverlay.EDGE_KEYS:
			if int(data[key]) > 0:
				return hex
	return Vector2i.ZERO


func _inside(panel: Control, world: Node) -> bool:
	return Rect2(Vector2.ZERO, world.ui.get_node("Control").size).encloses(panel.get_global_rect())


func _pointer_event(point: Vector2, button: MouseButton) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.position = point
	press.global_position = point
	press.button_index = button
	press.pressed = true
	get_viewport().push_input(press, true)
	var release: InputEventMouseButton = press.duplicate() as InputEventMouseButton
	release.pressed = false
	get_viewport().push_input(release, true)


func _on_map_click(_point: Vector2) -> void:
	map_clicks += 1


func _settle() -> void:
	for frame: int in range(6):
		await get_tree().process_frame


func _capture(label: String) -> void:
	await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/acl-hex-%s.png" % label)


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


func _screen_rect(control: Control) -> Rect2:
	return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)
