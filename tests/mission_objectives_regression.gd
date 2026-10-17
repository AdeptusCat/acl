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
	var friends: Array[Unit] = Globals.get_units_for_team(Globals.Team.ALLIES)
	var enemies: Array[Unit] = Globals.get_units_for_team(Globals.Team.AXIS)
	_check(friends.size() >= 3 and enemies.size() >= 2, "Fixture supplies squads for capture, exits, and losses")
	for unit: Unit in Globals.get_units():
		unit.current_hex = Vector2i(-100, -100)
	var objective_hex: Vector2i = occupy.state.hexes[0]
	enemies[0].current_hex = objective_hex
	occupy.advance_time(0.5)
	panel.refresh()
	_check(_row(panel, 0).contains("enemy controlled"), "Enemy occupation is shown explicitly")
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
	_check(_row(panel, 0) == "Objective A: unoccupied" and not occupy.is_condition_met(), "Losing control updates the label while resetting capture progress")
	hud._on_update_timer_label(0.0)
	_check(_row(panel, 0) == "Objective A: unoccupied", "An unfinished capture still displays control at the deadline")
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
	var header_bottom: float = maxf(toolbar.get_rect().end.y, timer_rect.end.y)
	_check(is_equal_approx(panel_rect.end.x, canvas_size.x - 12.0) and is_equal_approx(panel_rect.position.y, header_bottom + 12.0), "Objectives stay on the right below the top HUD controls")
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
