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
	_check(occupy.get_description() == "Capture Objective A" and destroy.get_description() == "Destroy 2 enemy squads", "Capture and destruction descriptions use short action labels")
	_check(exit.get_description() == "Exit with 3 squads" and prevent.get_description() == "Allow no more than 1 enemy exit at Objective A", "Exit objectives have short descriptions with the target and limit")
	_check(occupy.get_details().contains("continuous seconds") and prevent.get_details().contains("Required at mission end"), "Short labels retain capture mechanics and scoring timing in their details")
	scenario.victory_conditions = [occupy, exit, destroy, prevent, enemy_objective, minor]
	Globals.map_chosen = map
	Globals.scenario_chosen = scenario
	world.start_screen.hide()
	await world._on_game_started(map, scenario, scenario.player_team, Globals.GameMode.ATTACK)
	_freeze(main)
	_check_initial_objective_control(world, occupy)
	_check(panel.is_visible_in_tree(), "Starting a battle displays its mission panel")
	_check(panel.conditions.size() == 5 and not panel.conditions.has(enemy_objective) and panel.conditions.has(minor), "Both victory levels are displayed without enemy conditions")
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
	panel.status_labels[0].gui_input.emit(click)
	_check(world.game_controller.camera.position == world.ground_layer.map_to_local(objective_hex), "Clicking a capture row centers the camera on its hex")
	panel.status_labels[1].gui_input.emit(click)
	_check(world.game_controller.camera.position == world.ground_layer.map_to_local(exit.state.exit_hexes[0]), "Clicking an exit row focuses its exit hex")
	var previous_position: Vector2 = world.game_controller.camera.position
	panel.status_labels[2].gui_input.emit(click)
	_check(world.game_controller.camera.position == previous_position, "Objectives without a hex leave the camera unchanged")
	_check_hex_cycling(world, panel, occupy, exit, prevent)
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
	_check_capture_visual(world, objective_hex, 1.25 / 3.0, ObjectiveAreaOverlay.FRIENDLY_COLOR)
	_check(_row(panel, 0) == "Objective A: securing · 1/3 s", "Capture rows distinguish occupation from completed capture")
	for iteration: int in range(5):
		panel.refresh()
	_check(is_equal_approx(occupy.state.required_times_reached_s[objective_hex], 1.25), "Reading the HUD never advances mission progress")
	occupy.advance_time(1.75)
	panel.refresh()
	_check(occupy.is_condition_met() and _row(panel, 0) == "Objective A: player controlled", "Meeting capture requirements preserves the control-only label")
	_check_capture_visual(world, objective_hex, 0.0, ObjectiveAreaOverlay.FRIENDLY_COLOR)
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
	_check_capture_visual(world, objective_hex, 1.0 / 3.0, ObjectiveAreaOverlay.ENEMY_COLOR)
	_check(occupy.is_condition_met(), "An incomplete enemy capture preserves ownership")
	friends[0].current_hex = objective_hex
	occupy.advance_time(4.0)
	_check_capture_visual(world, objective_hex, 0.0, ObjectiveAreaOverlay.FRIENDLY_COLOR)
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
	_check(not panel.requirement_labels[1].visible and not panel.requirement_labels[3].visible, "Exit and prevention rows use the same compact layout as mission 2")
	_check(_row(panel, 1) == "Exit squads: 2/3" and panel.status_labels[1].tooltip_text.contains("In progress"), "Recorded exits display their live count")
	Globals.units_destroyed.units_collection[Globals.Team.ALLIES].units.append(enemies[0])
	panel.refresh()
	_check(_row(panel, 2).contains("Enemy squads destroyed: 1/2"), "Enemy losses display their live count")
	_check(_row(panel, 3) == "Enemy exits: 0/1 allowed at Objective A" and panel.status_labels[3].tooltip_text.contains("On track at mission end"), "Preventing exits is provisional while time remains")
	await _check_layout(hud, panel, Vector2i(1440, 900))
	await _check_layout(hud, panel, Vector2i(800, 600))
	for index: int in range(2, 3):
		exit.record_unit_entry(friends[index], exit.state.exit_hexes[0])
	panel.refresh()
	_check(_row(panel, 1) == "Exit squads: 3/3" and panel.status_labels[1].get_theme_color("font_color") == MissionObjectivesPanel.COMPLETE_COLOR, "The exit target is marked complete when enough squads exit")
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
	await _check_exit_shader(world)
	await _check_mission_two(world, panel)
	var replacement_conditions: Array[VictoryCondition] = [minor, enemy_objective]
	hud.show_mission_objectives(replacement_conditions, Globals.Team.ALLIES, 60.0)
	_check(panel.conditions.size() == 1 and panel.status_labels.size() == 1 and panel.conditions[0] == minor, "A mission with only minor objectives displays its own minor group")
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
	var label: Label = panel.status_labels[index]
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
		var occupy: OccupyObjectiveCondition = world.ui.mission_objectives.conditions[0] as OccupyObjectiveCondition
		occupy.state.controlling_teams[hex] = Globals.Team.AXIS
		occupy.state.required_times_reached_s[hex] = occupy.required_time_s * 0.5
		overlay._update_colors()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/acl-capture-progress.png")
		occupy.state.controlling_teams[hex] = Globals.Team.ALLIES
		occupy.state.enemy_hold_times_s[hex] = occupy.required_time_s * 0.75
		overlay._update_colors()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/acl-enemy-capture-progress.png")
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


func _check_capture_visual(world: Node, hex: Vector2i, progress: float, color: Color) -> void:
	var overlay: ObjectiveAreaOverlay = world.game_controller.allies_objective_tilemap.get_node("ObjectiveArea") as ObjectiveAreaOverlay
	overlay._update_colors()
	for marker: Dictionary in overlay.markers:
		if marker["hex"] != hex:
			continue
		var shader_material: ShaderMaterial = marker["material"]
		var actual: float = shader_material.get_shader_parameter("capture_progress")
		_check(is_equal_approx(actual, progress), "Capture bands reflect live hold progress and clear after capture or interruption")
		var activity_label: Label = marker["activity_label"]
		_check(activity_label.visible == (progress > 0.0), "Hex capture activity labels appear during capture and clear after interruption or completion")
		if progress > 0.0:
			var action: String = "CAPTURING"
			if color == ObjectiveAreaOverlay.ENEMY_COLOR:
				action = "LOSING"
			_check(activity_label.text.begins_with(action) and activity_label.text.contains("%"), "Hex labels identify the capturing side and show progress")
			world.ui.mission_objectives.refresh()
			var button: ObjectiveCaptureButton = world.ui.mission_objectives.capture_buttons[0]
			_check(button.text.to_upper().begins_with(action), "Objective buttons announce friendly capture and enemy recapture")
		if progress > 0.0:
			_check(shader_material.get_shader_parameter("capture_color") == color, "Capture bands use the capturing side's color")
		return
	_check(false, "Capture progress has a matching objective marker")


func _check_initial_objective_control(world: Node, occupy: OccupyObjectiveCondition) -> void:
	_check(occupy.initial_control == OccupyObjectiveCondition.InitialControl.ENEMY, "Existing capture objectives default to enemy control")
	var hex: Vector2i = occupy.state.hexes[0]
	_check(occupy.state.controlling_teams[hex] == Globals.Team.AXIS and not occupy.is_condition_met(), "Match startup assigns objectives to the player's enemy")
	_check(_row(world.ui.mission_objectives, 0) == "Objective A: enemy controlled", "The HUD immediately shows starting enemy ownership")
	var overlay: ObjectiveAreaOverlay = world.game_controller.allies_objective_tilemap.get_node("ObjectiveArea") as ObjectiveAreaOverlay
	for marker: Dictionary in overlay.markers:
		if marker["hex"] == hex:
			var shader_material: ShaderMaterial = marker["material"]
			_check(shader_material.get_shader_parameter("area_color") == ObjectiveAreaOverlay.ENEMY_COLOR, "Starting ownership reaches the shader before the first refresh")
	var opposing_capture: OccupyObjectiveCondition = OccupyObjectiveCondition.new()
	opposing_capture.team = Globals.Team.AXIS
	Globals.victory_conditions[Globals.Team.AXIS].victory_conditions.append(opposing_capture)
	for selected_team: Globals.Team in [Globals.Team.AXIS, Globals.Team.ALLIES]:
		Globals.team_player = selected_team
		for control: OccupyObjectiveCondition.InitialControl in [OccupyObjectiveCondition.InitialControl.NEUTRAL, OccupyObjectiveCondition.InitialControl.FRIENDLY, OccupyObjectiveCondition.InitialControl.ENEMY]:
			occupy.initial_control = control
			opposing_capture.initial_control = control
			world.game_controller.set_victory_conditions()
			var expected_owner: int = -1
			if control == OccupyObjectiveCondition.InitialControl.FRIENDLY:
				expected_owner = selected_team
			elif control == OccupyObjectiveCondition.InitialControl.ENEMY:
				expected_owner = Globals.get_enemy_team(selected_team)
			for capture: OccupyObjectiveCondition in [occupy, opposing_capture]:
				_check(not capture.state.hexes.is_empty(), "Both factions have capture markers for initial ownership checks")
				for cell: Vector2i in capture.state.hexes:
					_check(capture.state.controlling_teams[cell] == expected_owner, "Initial ownership is relative to the selected player for both factions")
					_check(capture.state.victory_conditions_met[cell] == (expected_owner == capture.team), "Initial ownership and capture scoring agree")
					var expected_seconds: float = 0.0
					if expected_owner == capture.team:
						expected_seconds = capture.required_time_s
					_check(is_equal_approx(capture.state.required_times_reached_s[cell], expected_seconds) and capture.state.enemy_hold_times_s[cell] == 0.0, "Repeated setup resets capture timers and fully credits the initial owner")
				capture.refresh_control()
				_check(capture.state.controlling_teams[capture.state.hexes[0]] == expected_owner, "Presence refresh preserves authored starting ownership")
	Globals.team_player = Globals.Team.ALLIES
	var mixed_captures: Array[OccupyObjectiveCondition] = [occupy]
	var added_markers: Array[ObjectiveDefinition] = []
	for id: OccupyObjectiveCondition.ObjectiveId in [OccupyObjectiveCondition.ObjectiveId.B, OccupyObjectiveCondition.ObjectiveId.C]:
		var capture: OccupyObjectiveCondition = OccupyObjectiveCondition.new()
		capture.team = Globals.Team.ALLIES
		capture.objective_id = id
		capture.initial_control = OccupyObjectiveCondition.InitialControl.NEUTRAL
		if id == OccupyObjectiveCondition.ObjectiveId.C:
			capture.initial_control = OccupyObjectiveCondition.InitialControl.FRIENDLY
		var marker: ObjectiveDefinition = ObjectiveDefinition.new()
		marker.team = capture.team
		marker.objective_id = id
		marker.hex = hex + Vector2i(int(id), 0)
		Globals.objectives[capture.team].objectives.append(marker)
		Globals.victory_conditions[capture.team].victory_conditions.append(capture)
		mixed_captures.append(capture)
		added_markers.append(marker)
	occupy.initial_control = OccupyObjectiveCondition.InitialControl.ENEMY
	world.game_controller.set_victory_conditions()
	var expected_owners: Array[int] = [Globals.Team.AXIS, -1, Globals.Team.ALLIES]
	for index: int in range(mixed_captures.size()):
		var capture: OccupyObjectiveCondition = mixed_captures[index]
		for cell: Vector2i in capture.state.hexes:
			_check(capture.state.controlling_teams[cell] == expected_owners[index], "Objectives A, B and C can start enemy, neutral and friendly in the same scenario")
			_check(capture.state.victory_conditions_met[cell] == (expected_owners[index] == capture.team), "Mixed starting ownership initializes each objective's capture credit independently")
	var saved_capture: OccupyObjectiveCondition = mixed_captures[2]
	_check(ResourceSaver.save(saved_capture, "user://objective_control_test.tres") == OK, "Per-objective ownership saves with the capture resource")
	var loaded_capture: OccupyObjectiveCondition = ResourceLoader.load("user://objective_control_test.tres", "", ResourceLoader.CACHE_MODE_IGNORE) as OccupyObjectiveCondition
	_check(loaded_capture != null and loaded_capture.initial_control == OccupyObjectiveCondition.InitialControl.FRIENDLY, "Per-objective ownership survives resource reload")
	DirAccess.remove_absolute("user://objective_control_test.tres")
	for marker: ObjectiveDefinition in added_markers:
		Globals.objectives[Globals.Team.ALLIES].objectives.erase(marker)
	for index: int in range(1, mixed_captures.size()):
		Globals.victory_conditions[Globals.Team.ALLIES].victory_conditions.erase(mixed_captures[index])
	Globals.victory_conditions[Globals.Team.AXIS].victory_conditions.erase(opposing_capture)
	Globals.team_player = Globals.Team.ALLIES
	occupy.initial_control = OccupyObjectiveCondition.InitialControl.NEUTRAL
	world.game_controller.set_victory_conditions()
	overlay._update_colors()
	world.ui.mission_objectives.refresh()


func _check_mission_two(world: Node, panel: MissionObjectivesPanel) -> void:
	var mission_map: Map = load("res://scenes/campaigns/alderbrook/02_orchard_outpost.tscn").instantiate() as Map
	get_tree().root.add_child(mission_map)
	var scenario: Scenario = mission_map.get_scenario(0)
	var previous_scenario: Scenario = Globals.scenario_chosen
	var previous_objectives: Dictionary[Globals.Team, ObjectivesCollection] = Globals.objectives
	var previous_conditions: Dictionary[Globals.Team, VictoryConditionCollection] = Globals.victory_conditions
	Globals.scenario_chosen = scenario
	Globals.objectives = scenario.get_objectives()
	Globals.victory_conditions = scenario.get_victory_conditions()
	world.game_controller.set_victory_conditions()
	panel.setup(scenario.victory_conditions, Globals.Team.ALLIES, 600.0)
	_check(panel.conditions.size() == 3, "Mission 2 displays both major requirements and its minor objective")
	_check(panel.group_headings[VictoryCondition.OutcomeLevel.MAJOR].text == "Major victory" and panel.group_headings[VictoryCondition.OutcomeLevel.MINOR].text == "Minor victory", "Major and minor requirements have separate labeled groups")
	_check(panel.requirement_labels[0].text.contains("Capture all A hexes") and panel.requirement_labels[0].text.contains("30 s continuous"), "Mission 2 explains the major capture requirement and hold duration")
	_check(panel.requirement_labels[1].text.contains("Destroy at least 2"), "Mission 2 also explains the destruction requirement for major victory")
	_check(panel.requirement_labels[2].text.contains("Capture all B hexes") and panel.requirement_labels[2].text.contains("Required at mission end"), "Mission 2 shows objective B and its mission-end requirement for minor victory")
	_check(panel.capture_buttons[0].text == "Capture Objective A" and panel.capture_buttons[2].text == "Capture Objective B", "Mission 2 uses concise capture button labels")
	_check(not panel.requirement_labels[0].visible and not panel.status_labels[0].visible and not panel.requirement_labels[1].visible, "Mission 2 hides verbose requirement and duplicate status lines")
	_check(panel.status_labels[1].text == "Enemy squads destroyed: 1/2", "Mission 2 displays only the live destruction count")
	_check_button_capture_style(panel.capture_buttons[0], ObjectiveAreaOverlay.ENEMY_COLOR, 0.0)
	var major: OccupyObjectiveCondition = panel.conditions[0] as OccupyObjectiveCondition
	var major_hex: Vector2i = major.state.hexes[0]
	major.state.required_times_reached_s[major_hex] = major.required_time_s * 0.5
	panel.refresh()
	_check_button_capture_style(panel.capture_buttons[0], ObjectiveAreaOverlay.ENEMY_COLOR, 0.5)
	_check(panel.capture_buttons[0].text.begins_with("Capturing A"), "Active friendly capture is explicit in the objective button")
	var minor: OccupyObjectiveCondition = panel.conditions[2] as OccupyObjectiveCondition
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	panel.capture_buttons[2].pressed.emit()
	_check(world.game_controller.camera.position == world.ground_layer.map_to_local(minor.state.hexes[0]), "Clicking the minor victory requirement focuses objective B")
	for hex: Vector2i in minor.state.hexes:
		minor.state.victory_conditions_met[hex] = true
		minor.state.controlling_teams[hex] = minor.team
		minor.state.required_times_reached_s[hex] = minor.required_time_s
	panel.refresh()
	_check(_row(panel, 2).contains("player controlled"), "Minor objective progress refreshes alongside major objectives")
	_check_button_capture_style(panel.capture_buttons[2], ObjectiveAreaOverlay.FRIENDLY_COLOR, 0.0)
	await _check_layout(world.ui, panel, Vector2i(1440, 900))
	await _check_layout(world.ui, panel, Vector2i(800, 600))
	Globals.scenario_chosen = previous_scenario
	Globals.objectives = previous_objectives
	Globals.victory_conditions = previous_conditions
	mission_map.queue_free()


func _check_button_capture_style(button: ObjectiveCaptureButton, color: Color, progress: float) -> void:
	var shader_material: ShaderMaterial = (button.backgrounds.get_child(0) as ColorRect).material as ShaderMaterial
	_check(shader_material.get_shader_parameter("area_color") == color, "Capture buttons match the map's current ownership color")
	_check(is_equal_approx(float(shader_material.get_shader_parameter("capture_progress")), progress), "Capture button bands match live hex capture progress")


func _check_hex_cycling(world: Node, panel: MissionObjectivesPanel, occupy: OccupyObjectiveCondition, exit: ExitUnitsCondition, prevention: PreventEnemyExitCondition) -> void:
	var original_capture: Array[Vector2i] = occupy.state.hexes.duplicate()
	var original_exits: Array[Vector2i] = exit.state.exit_hexes.duplicate()
	var original_enemy_exits: Array[Vector2i] = prevention.state.exit_hexes.duplicate()
	occupy.state.hexes = [Vector2i(4, 4), Vector2i(5, 4)]
	exit.state.exit_hexes = [Vector2i(6, 4), Vector2i(7, 4), Vector2i(8, 4)]
	prevention.state.exit_hexes = [Vector2i(4, 8), Vector2i(5, 8), Vector2i(6, 8)]
	panel.refresh()
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	for index: int in range(4):
		panel.capture_buttons[0].pressed.emit()
		_check(world.game_controller.camera.position == world.ground_layer.map_to_local(occupy.state.hexes[index % 2]), "Capture button clicks cycle through every objective hex and wrap")
		panel.status_labels[1].gui_input.emit(click)
		_check(world.game_controller.camera.position == world.ground_layer.map_to_local(exit.state.exit_hexes[index % 3]), "Exit row clicks cycle independently through all exit hexes")
		var enemy_row: PanelContainer = panel.status_labels[3].get_parent() as PanelContainer
		enemy_row.gui_input.emit(click)
		_check(world.game_controller.camera.position == world.ground_layer.map_to_local(prevention.state.exit_hexes[index % 3]), "The full enemy-exit row cycles through enemy exit hexes")
		panel.refresh()
	_check(panel.capture_buttons[0].tooltip_text.contains("cycle through 2") and panel.status_labels[3].tooltip_text.contains("cycle through 3"), "Multihex objective tooltips explain cycling")
	click.button_index = MOUSE_BUTTON_RIGHT
	var previous_position: Vector2 = world.game_controller.camera.position
	panel.status_labels[1].gui_input.emit(click)
	_check(world.game_controller.camera.position == previous_position, "Right-clicking does not focus or advance objective cycling")
	click.button_index = MOUSE_BUTTON_LEFT
	panel.status_labels[1].gui_input.emit(click)
	_check(world.game_controller.camera.position == world.ground_layer.map_to_local(exit.state.exit_hexes[1]), "Ignored clicks leave the next objective hex unchanged")
	prevention.state.exit_hexes.clear()
	panel.status_labels[3].gui_input.emit(click)
	_check(world.game_controller.camera.position == world.ground_layer.map_to_local(exit.state.exit_hexes[1]), "Empty objective hex lists leave the camera unchanged")
	prevention.state.exit_hexes = [Vector2i(9, 8)]
	panel.status_labels[3].gui_input.emit(click)
	_check(world.game_controller.camera.position == world.ground_layer.map_to_local(Vector2i(9, 8)), "A replaced objective list safely focuses its new first hex")
	occupy.state.hexes = original_capture
	exit.state.exit_hexes = original_exits
	prevention.state.exit_hexes = original_enemy_exits
	panel.refresh()


func _objective_source(layer: HexagonTileMapLayer, objective_id: int) -> int:
	for index: int in range(layer.tile_set.get_source_count()):
		var source_id: int = layer.tile_set.get_source_id(index)
		var source: TileSetAtlasSource = layer.tile_set.get_source(source_id) as TileSetAtlasSource
		if source != null and source.has_tile(Vector2i.ZERO):
			if int(source.get_tile_data(Vector2i.ZERO, 0).get_custom_data("objective_id")) == objective_id:
				return source_id
	return -1


func _check_exit_shader(world: Node) -> void:
	var player_layer: HexagonTileMapLayer = world.game_controller.allies_objective_tilemap
	var enemy_layer: HexagonTileMapLayer = world.game_controller.axis_objective_tilemap
	var exit_hex: Vector2i = Vector2i(12, 12)
	var neighbor: Vector2i = enemy_layer.get_neighbor_cell(exit_hex, TileSet.CELL_NEIGHBOR_TOP_SIDE)
	var named_exit: Vector2i = Vector2i(14, 12)
	var hidden_capture: Vector2i = Vector2i(15, 12)
	player_layer.clear()
	enemy_layer.clear()
	for hex: Vector2i in [exit_hex, neighbor]:
		player_layer.set_cell(hex, _objective_source(player_layer, 0), Vector2i.ZERO)
		enemy_layer.set_cell(hex, _objective_source(enemy_layer, 0), Vector2i.ZERO)
	enemy_layer.set_cell(named_exit, _objective_source(enemy_layer, 1), Vector2i.ZERO)
	enemy_layer.set_cell(hidden_capture, _objective_source(enemy_layer, 2), Vector2i.ZERO)
	var prevention: PreventEnemyExitCondition = world.ui.mission_objectives.conditions[3] as PreventEnemyExitCondition
	prevention.state.exit_hexes = [named_exit]
	world.game_controller.set_objective_cells(Globals.Team.ALLIES)
	var own_overlay: ObjectiveAreaOverlay = player_layer.get_node("ObjectiveArea") as ObjectiveAreaOverlay
	var enemy_overlay: ObjectiveAreaOverlay = enemy_layer.get_parent().get_node("EnemyExitArea") as ObjectiveAreaOverlay
	_check(own_overlay.markers.size() == 2 and enemy_overlay.markers.size() == 3, "Both player and enemy exit hexes receive shader markers")
	_check(enemy_overlay.is_visible_in_tree() and not enemy_layer.visible, "Enemy exit effects remain visible while enemy capture markers stay hidden")
	var exposed: int = 0
	for marker: Dictionary in enemy_overlay.markers:
		_check(bool(marker["is_exit"]) and marker["hex"] != hidden_capture, "The enemy overlay only reveals exit routes, including named exits")
		var shader_material: ShaderMaterial = marker["material"]
		_check(shader_material.shader == ObjectiveAreaOverlay.AREA_SHADER and shader_material.get_shader_parameter("area_color") == ObjectiveAreaOverlay.COLORS[0], "Exit routes use the objective animation shader with cyan markings")
		if int(marker["id"]) == 0:
			for edge: float in marker["edges"]:
				exposed += int(edge)
	_check(exposed == 10, "Connected exit hexes share one animated perimeter")
	if OS.get_cmdline_user_args().has("--capture"):
		world.ui.hide()
		world.game_controller.camera.position = (enemy_layer.map_to_local(exit_hex) + enemy_layer.map_to_local(named_exit)) * 0.5
		world.game_controller.camera.zoom = Vector2(1.5, 1.5)
		world.game_controller.camera.reset_smoothing()
		world.game_controller.camera.force_update_scroll()
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/acl-exit-area-shader.png")
		world.ui.show()
	player_layer.clear()
	enemy_layer.clear()
	world.game_controller.set_objective_cells(Globals.Team.ALLIES)
	_check(enemy_overlay.markers.is_empty(), "Repeated setup clears exit effects after exit tiles are removed")
