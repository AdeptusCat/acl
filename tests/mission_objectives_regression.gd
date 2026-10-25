extends Node

var checks: int = 0
var failures: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var hud: CanvasLayer = world.ui
	var panel: MissionObjectivesPanel = hud.mission_objectives
	_check(not panel.visible, "The mission panel stays hidden during scenario selection")
	var map: Map = world.maps.get_node("DefaultMap")
	var scenario: Scenario = map.get_scenario(0)
	scenario.player_team = Globals.Team.ALLIES
	scenario.axis_ai_status = Scenario.AIStatus.OFF
	scenario.allies_ai_status = Scenario.AIStatus.OFF
	# Keep this single-marker fixture independent of the default map's authored objectives.
	var kept_objective: bool = false
	for hex: Vector2i in scenario.allied_objectives_tile_map_layer.get_used_cells():
		var tile: TileData = scenario.allied_objectives_tile_map_layer.get_cell_tile_data(hex)
		if tile != null and tile.get_custom_data("objective_id") == OccupyObjectiveCondition.ObjectiveId.A:
			if kept_objective:
				scenario.allied_objectives_tile_map_layer.erase_cell(hex)
			kept_objective = true
	scenario.axis_objectives_tile_map_layer.set_cell(Vector2i(10, 12), 3, Vector2i.ZERO)
	var occupy: OccupyObjectiveCondition = OccupyObjectiveCondition.new()
	occupy.team = Globals.Team.ALLIES
	var exit: ExitUnitsCondition = ExitUnitsCondition.new()
	exit.team = Globals.Team.ALLIES
	exit.required_unit_count = 3
	var destroy: DestroyUnitsCondition = DestroyUnitsCondition.new()
	destroy.team = Globals.Team.ALLIES
	destroy.required_unit_count = 2
	var prevent: PreventEnemyExitCondition = PreventEnemyExitCondition.new()
	prevent.team = Globals.Team.ALLIES
	prevent.objective_id = PreventEnemyExitCondition.ObjectiveId.A
	prevent.max_allowed_enemy_exits = 1
	var enemy_objective: DestroyUnitsCondition = DestroyUnitsCondition.new()
	enemy_objective.team = Globals.Team.AXIS
	var minor: DestroyUnitsCondition = DestroyUnitsCondition.new()
	minor.team = Globals.Team.ALLIES
	minor.outcome_level = VictoryCondition.OutcomeLevel.MINOR
	scenario.victory_conditions = [occupy, exit, destroy, prevent, enemy_objective, minor]
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	_freeze(main)
	_check(panel.is_visible_in_tree(), "Starting a battle displays its mission panel")
	_check(panel.conditions.size() == 4 and not panel.conditions.has(enemy_objective) and not panel.conditions.has(minor), "Only the player's primary objectives are displayed")
	for frame: int in range(6):
		await get_tree().process_frame
	var expanded_height: float = panel.size.y
	panel.section.fold()
	for frame: int in range(6):
		await get_tree().process_frame
	_check(panel.section.folded and not panel.rows.is_visible_in_tree() and panel.size.y < expanded_height, "Objectives fold into a compact title bar")
	var friends: Array[Unit] = Globals.get_units_for_team(Globals.Team.ALLIES)
	var enemies: Array[Unit] = Globals.get_units_for_team(Globals.Team.AXIS)
	_check(friends.size() >= 3 and enemies.size() >= 2, "Fixture supplies squads for capture, exits, and losses")
	for unit: Unit in Globals.get_units():
		unit.current_hex = Vector2i(-100, -100)
	var objective_hex: Vector2i = occupy.state.hexes[0]
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	world.game_controller.camera.position = Vector2(-1000.0, -1000.0)
	panel.rows.get_child(0).gui_input.emit(click)
	_check(world.game_controller.camera.position == world.ground_layer.map_to_local(objective_hex), "Clicking a capture row centers the camera on its hex")
	panel.rows.get_child(1).gui_input.emit(click)
	_check(world.game_controller.camera.position == world.ground_layer.map_to_local(exit.state.exit_hexes[0]), "Clicking an exit row focuses its exit hex")
	var previous_position: Vector2 = world.game_controller.camera.position
	panel.rows.get_child(2).gui_input.emit(click)
	_check(world.game_controller.camera.position == previous_position, "Objectives without a hex leave the camera unchanged")
	enemies[0].current_hex = objective_hex
	occupy.advance_time(0.5)
	panel.refresh()
	_check(_row(panel, 0).contains("enemy controlled"), "Enemy occupation is shown explicitly")
	_check(panel.section.folded, "Objective updates preserve the player's collapsed panel")
	panel.section.expand()
	for frame: int in range(6):
		await get_tree().process_frame
	_check(panel.rows.is_visible_in_tree() and _row(panel, 0).contains("enemy controlled"), "Expanding objectives reveals progress updated while folded")
	friends[0].current_hex = objective_hex
	occupy.advance_time(0.5)
	panel.refresh()
	_check(_row(panel, 0).contains("contested"), "Contested occupation is distinguished from friendly control")
	enemies[0].current_hex = Vector2i(-100, -100)
	occupy.advance_time(1.25)
	panel._process(0.2)
	_check(_row(panel, 0) == "Objective A: securing · 1/3 s", "Capture rows distinguish occupation from completed capture")
	for iteration: int in range(5):
		panel.refresh()
	_check(is_equal_approx(occupy.state.required_times_reached_s[objective_hex], 1.25), "Reading the HUD never advances mission progress")
	occupy.advance_time(1.75)
	panel.refresh()
	_check(occupy.is_condition_met() and _row(panel, 0) == "Objective A: player controlled", "Meeting capture requirements preserves the control-only label")
	occupy.test_at_scenario_end = true
	panel.refresh()
	_check(_row(panel, 0) == "Objective A: player controlled", "End-only capture displays control without provisional status")
	hud._on_update_timer_label(0.0)
	_check(_row(panel, 0) == "Objective A: player controlled", "The deadline preserves the capture control label")
	hud._on_update_timer_label(60.0)
	friends[0].current_hex = Vector2i(-100, -100)
	occupy.advance_time(0.25)
	panel.refresh()
	_check(_row(panel, 0) == "Objective A: player controlled" and occupy.is_condition_met(), "Captured objectives remain controlled after the garrison leaves")
	occupy.refresh_control()
	_check(occupy.is_condition_met(), "Final scoring preserves an empty captured objective")
	enemies[0].current_hex = objective_hex
	occupy.advance_time(1.0)
	_check(occupy.is_condition_met(), "An incomplete enemy capture preserves ownership")
	friends[0].current_hex = objective_hex
	occupy.advance_time(4.0)
	_check(occupy.is_condition_met() and occupy.state.enemy_hold_times_s[objective_hex] == 0.0, "Contesting interrupts the enemy capture without losing ownership")
	friends[0].current_hex = Vector2i(-100, -100)
	enemies[0].broken = true
	occupy.advance_time(4.0)
	_check(occupy.is_condition_met(), "Broken enemies cannot recapture an objective")
	enemies[0].broken = false
	occupy.required_unit_count = 2
	occupy.advance_time(4.0)
	_check(occupy.is_condition_met(), "Enemy recapture requires the configured squad count")
	occupy.required_unit_count = 1
	occupy.advance_time(3.0)
	_check(not occupy.is_condition_met(), "A full uncontested enemy hold transfers ownership")
	enemies[0].current_hex = Vector2i(-100, -100)
	occupy.advance_time(1.0)
	panel.refresh()
	_check(_row(panel, 0) == "Objective A: enemy controlled", "Enemy ownership also persists without a garrison")
	friends[0].current_hex = objective_hex
	occupy.advance_time(1.0)
	friends[0].current_hex = Vector2i(-100, -100)
	occupy.advance_time(1.0)
	_check(occupy.state.required_times_reached_s[objective_hex] == 0.0, "Leaving an unfinished recapture resets its timer")
	friends[0].current_hex = objective_hex
	occupy.advance_time(3.0)
	friends[0].current_hex = Vector2i(-100, -100)
	panel.refresh()
	hud._on_update_timer_label(0.0)
	_check(_row(panel, 0) == "Objective A: player controlled", "The deadline retains captured ownership without a garrison")
	hud._on_update_timer_label(60.0)
	for index: int in range(2):
		exit.record_unit_entry(friends[index], exit.state.exit_hexes[0])
	panel.refresh()
	_check(_row(panel, 1).contains("Exit squads: 2/3") and _row(panel, 1).contains("In progress"), "Recorded exits display their live count")
	Globals.units_destroyed.units_collection[Globals.Team.ALLIES].units.append(enemies[0])
	panel.refresh()
	_check(_row(panel, 2).contains("Enemy squads destroyed: 1/2"), "Enemy losses display their live count")
	_check(_row(panel, 3).contains("On track") and not _row(panel, 3).contains("Complete"), "Preventing exits is provisional while time remains")
	await _check_layout(hud, panel, Vector2i(1440, 900))
	await _check_layout(hud, panel, Vector2i(800, 600))
	for index: int in range(2, 3):
		exit.record_unit_entry(friends[index], exit.state.exit_hexes[0])
	panel.refresh()
	_check(_row(panel, 1).contains("3/3") and _row(panel, 1).contains("Complete"), "The exit target is marked complete when enough squads exit")
	prevent.record_unit_entry(enemies[0], prevent.state.exit_hexes[0])
	prevent.record_unit_entry(enemies[1], prevent.state.exit_hexes[0])
	panel.refresh()
	_check(_row(panel, 3).contains("2/1 allowed") and _row(panel, 3).contains("Failed"), "Exceeding the allowed exits is marked failed")
	# An occupation condition with several markers must complete every marker.
	occupy.state.hexes.append(Vector2i(-99, -99))
	occupy.state.required_times_reached_s[Vector2i(-99, -99)] = 0.0
	occupy.state.victory_conditions_met[Vector2i(-99, -99)] = false
	occupy.state.units_in_objectives[Vector2i(-99, -99)] = UnitsCollection.new()
	friends[0].current_hex = objective_hex
	occupy.advance_time(3.0)
	panel.refresh()
	_check(_row(panel, 0) == "Objective A: partially player controlled" and not occupy.is_condition_met(), "Multiple objective markers display partial control without capture counters")
	friends[0].current_hex = Vector2i(-99, -99)
	occupy.advance_time(3.0)
	panel.refresh()
	_check(occupy.is_condition_met() and _row(panel, 0) == "Objective A: player controlled", "A single squad can secure multiple hexes sequentially")
	enemies[0].current_hex = objective_hex
	occupy.advance_time(3.0)
	_check(not occupy.is_condition_met() and occupy.state.victory_conditions_met[Vector2i(-99, -99)], "Enemy recapture only transfers the hex it occupies")
	await _check_area_overlay(world, objective_hex)
	var replacement_conditions: Array[VictoryCondition] = [minor, enemy_objective]
	hud.show_mission_objectives(replacement_conditions, Globals.Team.ALLIES, 60.0)
	_check(panel.conditions.size() == 1 and panel.rows.get_child_count() == 1 and panel.conditions[0] == minor, "A mission without primary objectives falls back to its own minor objectives")
	replacement_conditions = [enemy_objective]
	hud.show_mission_objectives(replacement_conditions, Globals.Team.AXIS, 60.0)
	_check(panel.conditions.size() == 1 and panel.conditions[0].team == Globals.Team.AXIS, "Reconfiguration uses the selected faction without stale rows")
	replacement_conditions = []
	hud.show_mission_objectives(replacement_conditions, Globals.Team.ALLIES, 60.0)
	_check(not panel.visible and not panel.is_processing() and panel.rows.get_child_count() == 0, "An empty mission hides and clears the panel")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Mission objective checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _check_layout(hud: CanvasLayer, panel: MissionObjectivesPanel, window_size: Vector2i) -> void:
	get_tree().root.size = window_size
	for frame: int in range(6):
		await get_tree().process_frame
	var timer_rect: Rect2 = hud.countdown_panel_container.get_rect()
	var panel_rect: Rect2 = panel.get_rect()
	var canvas_size: Vector2 = hud.get_node("Control").size
	_check(panel_rect.position.x >= 0.0 and panel_rect.end.x <= canvas_size.x and panel_rect.end.y <= canvas_size.y, "Mission panel stays inside the window after resizing")
	_check(not panel_rect.intersects(timer_rect), "Mission panel never overlaps the timer")
	var retry_panel: Control = hud.get_node("Control/TryAgain")
	_check(not panel_rect.intersects(retry_panel.get_rect()), "Mission panel never overlaps the restart control")
	var toolbar: Control = hud.get_node("Control/Settings")
	_check(is_equal_approx(panel_rect.end.x, canvas_size.x - 12.0) and is_equal_approx(panel_rect.position.y, toolbar.get_rect().end.y + 6.0), "Objectives sit directly below the top-right toolbar")
	_check(not panel_rect.intersects(hud.squad_roster.get_rect()), "Objectives leave the roster column clear")
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/acl-mission-panel-%d.png" % window_size.x)


func _row(panel: MissionObjectivesPanel, index: int) -> String:
	var label: Label = panel.rows.get_child(index) as Label
	return label.text


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


func _check_area_overlay(world: Node, hex: Vector2i) -> void:
	var layer: HexagonTileMapLayer = world.game_controller.allies_objective_tilemap
	var neighbor: Vector2i = layer.get_neighbor_cell(hex, TileSet.CELL_NEIGHBOR_TOP_SIDE)
	var source: int = layer.get_cell_source_id(hex)
	var atlas: Vector2i = layer.get_cell_atlas_coords(hex)
	var alternative: int = layer.get_cell_alternative_tile(hex)
	layer.clear()
	layer.set_cell(hex, source, atlas, alternative)
	layer.set_cell(neighbor, source, atlas, alternative)
	ObjectiveAreaOverlay.install(layer, Globals.Team.ALLIES)
	var overlay: ObjectiveAreaOverlay = layer.get_node("ObjectiveArea") as ObjectiveAreaOverlay
	_check(overlay.markers.size() == 2, "Every objective hex receives a shader polygon")
	var exposed: int = 0
	for marker: Dictionary in overlay.markers:
		for edge: float in marker["edges"]:
			exposed += int(edge)
	_check(exposed == 10, "Connected hexes of the same objective omit both shared edges")
	if OS.get_cmdline_user_args().has("--capture"):
		world.ui.hide()
		world.game_controller.camera.position = (layer.map_to_local(hex) + layer.map_to_local(neighbor)) * 0.5
		world.game_controller.camera.zoom = Vector2(2.0, 2.0)
		world.game_controller.camera.reset_smoothing()
		world.game_controller.camera.force_update_scroll()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/acl-connected-objectives.png")
		world.ui.show()
	var different_source: int = -1
	for index: int in range(layer.tile_set.get_source_count()):
		var candidate_id: int = layer.tile_set.get_source_id(index)
		var candidate: TileSetAtlasSource = layer.tile_set.get_source(candidate_id) as TileSetAtlasSource
		if candidate != null and candidate.has_tile(Vector2i.ZERO):
			if int(candidate.get_tile_data(Vector2i.ZERO, 0).get_custom_data("objective_id")) == 2:
				different_source = candidate_id
	_check(different_source >= 0, "Fixture supplies another objective identity")
	if different_source >= 0:
		layer.set_cell(neighbor, different_source, Vector2i.ZERO)
		ObjectiveAreaOverlay.install(layer, Globals.Team.ALLIES)
		exposed = 0
		for marker: Dictionary in overlay.markers:
			for edge: float in marker["edges"]:
				exposed += int(edge)
		_check(exposed == 12, "Adjacent different objectives retain their separate borders")
	layer.clear()
	ObjectiveAreaOverlay.install(layer, Globals.Team.ALLIES)
	_check(overlay.markers.is_empty() and overlay.get_child_count() == 0, "Reinitializing an empty layer removes old objective artwork")
