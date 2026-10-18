extends Node

const DETAILS_SCRIPT: Script = preload("res://scenes/ui/units/unit_details_panel.gd")

var checks: int = 0
var failures: int = 0
var zoom_events: int = 0


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
	# The normal first controller tick hides this preview when no unit is selected.
	world.ui.hide_target_hex_cover_distance()
	get_tree().root.size = Vector2i(1440, 900)
	var panel: PanelContainer = world.ui.unit_details
	var players: Array[Unit] = Globals.get_units_for_team(Globals.team_player)
	var selected: Unit = players[0]
	panel.show_unit_detail(selected, false)
	await _settle()
	_check(panel.is_visible_in_tree(), "Selecting a squad displays its summary")
	_check(panel.details_section.folded and panel.roster_section.folded, "Extra information starts collapsed")
	_check(panel.unit_type_label.text.contains(selected.ui.unit_designation_label.text) and panel.formation_label.text.contains("Company"), "Identity includes the map designation and formation")
	_check(panel.strength_label.text == "%d/%d soldiers" % [selected.squad_fire.soldiers.size(), selected.original_size], "Strength uses the live roster and its initial size")
	_check(is_equal_approx(panel.size.x, 300.0) and panel.size.y <= 244.0, "The summary including command contact is compact and has a stable width")
	_check(panel.command_label.is_visible_in_tree() and panel.command_label.tooltip_text.contains("HQ:") and panel.command_label.tooltip_text.contains("Leadership support:"), "Selection shows readable contact status and distinguishes HQ contact from leadership support")
	selected.combat_stats.cohesion_current = 0.64
	selected.combat_stats.combat_effectiveness = 0.37
	selected.combat_stats.recent_casualty_shock = 0.25
	panel._process(0.0)
	_check(is_equal_approx(panel.cohesion_bar.value, 0.64) and panel.cohesion.text == "64%", "Cohesion has a labeled live bar and percentage")
	_check(is_equal_approx(panel.effectiveness_bar.value, 0.37) and panel.effectiveness.text == "37%", "Effectiveness has a labeled live bar and percentage")
	_check(not panel.casualty_shock.is_visible_in_tree(), "Casualty shock is kept out of the collapsed summary")
	var destination: Vector2i = _adjacent_hex(selected, world.ground_layer)
	var path: Array[Vector3i] = [selected.current_cube, world.ground_layer.map_to_cube(destination)]
	selected.give_move_to_hex_order(destination, path, false)
	panel._process(0.0)
	_check(panel.order_label.text == "Order: Move to (%d, %d)" % [destination.x, destination.y], "The current movement order is displayed with its destination")
	selected.give_hold_order()
	selected.movement._process_movement(1.0)
	selected.give_hold_order()
	panel._process(0.0)
	_check(panel.order_label.text == "Order: Hold position", "Replacing a move with a hold updates the summary")
	selected.order(Globals.UnitCmd.FIRE_AT_HEX, destination)
	panel._process(0.0)
	_check(panel.order_label.text == "Order: Fire at (%d, %d)" % [destination.x, destination.y], "A manual fire order is displayed with its target")
	selected.stress_system._set_state(STATES.MoraleState.PINNED)
	panel._process(0.0)
	_check(panel.unit_status_label.text.contains("Pinned") and panel.rout_button.visible, "Morale changes update the summary and the available rout action")
	selected.stress_system._set_state(STATES.MoraleState.NORMAL)
	selected.give_hold_order()
	var loadout: SquadLoadoutSpec = SquadLoadoutSpec.new()
	var template: SoldierLoadout = selected.squad_loadout.soldiers[0]
	for index: int in range(20):
		var member: SoldierLoadout = SoldierLoadout.new()
		member.nickname = "Soldier with a deliberately long name %d" % index
		member.rank_grade = template.rank_grade
		member.role = template.role
		member.weapon = template.weapon
		loadout.soldiers.append(member)
	selected._setup_runtime_soldiers(loadout)
	selected.soldiers_changed.emit()
	panel.roster_section.expand()
	await _settle()
	_check(panel.soldier_entries_by_soldier.size() == 20, "The roster supports more than twelve soldiers")
	_check(not panel.roster_section.folded and panel.details_section.folded, "Opening the roster keeps the detailed statistics collapsed")
	_check(is_equal_approx(panel.size.x, 300.0) and panel.size.y <= 380.0, "A long roster cannot widen or excessively grow the panel")
	var scrollbar: VScrollBar = panel.roster_scroll.get_v_scroll_bar()
	_check(scrollbar.max_value > scrollbar.page, "Long rosters have a bounded vertical scroll area")
	_check(_text_fits(panel.strength_label), "Remaining and initial soldier counts are fully readable")
	panel._on_state_changed(STATES.MoraleState.COMBAT_INEFFECTIVE)
	_check(_text_fits(panel.unit_status_label), "Even the longest morale status fits the compact summary")
	panel._process(0.0)
	panel.roster_scroll.scroll_vertical = 40
	_check(panel.roster_scroll.scroll_vertical > 0, "The roster can scroll beyond its first rows")
	world.input_manager.zoom_in.connect(_on_zoom)
	world.input_manager.zoom_out.connect(_on_zoom)
	var scroll_position: Vector2 = _screen_rect(panel.roster_scroll).get_center()
	var scroll_before: int = panel.roster_scroll.scroll_vertical
	_scroll_at(scroll_position, MouseButton.MOUSE_BUTTON_WHEEL_DOWN)
	_check(zoom_events == 0 and panel.roster_scroll.scroll_vertical > scroll_before, "Scrolling the roster moves its rows without zooming the battlefield: %d events, %d -> %d" % [zoom_events, scroll_before, panel.roster_scroll.scroll_vertical])
	_scroll_at(Vector2(600, 100), MouseButton.MOUSE_BUTTON_WHEEL_UP)
	var hovered: Control = get_viewport().gui_get_hovered_control()
	var hovered_path: String = "none"
	if hovered != null:
		hovered_path = str(hovered.get_path())
	_check(zoom_events == 1, "Scrolling over the battlefield still controls zoom: %d events, hovered %s" % [zoom_events, hovered_path])
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("expanded")
	panel.details_section.expand()
	await _settle()
	_check(panel.roster_section.folded and panel.casualty_shock.is_visible_in_tree(), "Opening details exposes casualty shock while folding the roster")
	var casualty: Soldier = selected.squad_fire.soldiers[0]
	selected.apply_specific_casualty(casualty)
	panel._process(0.0)
	_check(panel.strength_label.text == "19/20 soldiers", "A casualty immediately updates remaining soldiers")
	_check(panel.casualty_entries_by_casualty.has(casualty) and not panel.soldier_entries_by_soldier.has(casualty), "The roster moves casualties out of the active soldier list")
	var casualty_task: Label = panel.casualty_entries_by_casualty[casualty][DETAILS_SCRIPT.Entry.TASK]
	_check(casualty_task.text == "Incapacitated", "Casualties remain identifiable in the roster")
	var active: Soldier = selected.squad_fire.soldiers[0]
	panel.set_progress_bar(active, "Idle", 0.0, 0.0)
	var task_progress: ProgressBar = panel.soldier_entries_by_soldier[active][DETAILS_SCRIPT.Entry.PROGRESS_BAR]
	_check(is_finite(task_progress.value) and not task_progress.visible, "Untimed activities do not show invalid task progress")
	var other: Unit = players[1]
	panel.show_unit_detail(other, false)
	await _settle()
	_check(panel.unit == other and not panel.details_section.folded and panel.roster_section.folded, "Switching squads preserves expanded details")
	_check(not selected.soldiers_changed.is_connected(panel._on_soldiers_changed), "Switching squads releases the previous squad's UI subscriptions")
	panel.roster_section.expand()
	panel.show_unit_detail(selected, false)
	await _settle()
	_check(not panel.roster_section.folded and panel.details_section.folded, "Switching squads preserves the expanded roster")
	panel.show_unit_detail(other, false)
	panel.hide_unit_detail()
	panel.show_unit_detail(other, false)
	await get_tree().create_timer(0.2).timeout
	_check(panel.unit == other and panel.visible, "A rapid deselect and reselect cannot hide the new selection")
	get_tree().root.size = Vector2i(800, 600)
	await _settle()
	var hud_size: Vector2 = world.ui.get_node("Control").size
	var panel_rect: Rect2 = panel.get_rect()
	_check(panel_rect.position.x >= 0.0 and panel_rect.position.y >= 0.0 and panel_rect.end.x <= hud_size.x and panel_rect.end.y <= hud_size.y, "The summary stays inside the HUD after resizing")
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("compact")
	var remaining: int = other.squad_fire.soldiers.size()
	panel.hide_unit_detail()
	await get_tree().create_timer(0.2).timeout
	_check(not panel.visible and panel.unit == null and not panel.is_processing(), "Deselecting hides and disconnects the summary")
	_check(other.squad_fire.soldiers.size() == remaining, "Clearing the UI never clears the squad's runtime roster")
	panel.show_unit_detail(other, false)
	other.unit_died.emit(other)
	await get_tree().create_timer(0.2).timeout
	_check(not panel.visible and panel.unit == null, "Removing the selected squad closes the summary")
	main.queue_free()
	await _settle()
	print("Unit summary checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _adjacent_hex(unit: Unit, ground: HexagonTileMapLayer) -> Vector2i:
	for cube: Vector3i in ground.cube_neighbors(unit.current_cube):
		var hex: Vector2i = ground.cube_to_map(cube)
		if ground.get_cell_source_id(hex) != -1:
			return hex
	return unit.current_hex


func _scroll_at(position: Vector2, button: MouseButton) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	get_viewport().push_input(motion, true)
	var wheel: InputEventMouseButton = InputEventMouseButton.new()
	wheel.position = position
	wheel.global_position = position
	wheel.button_index = button
	wheel.pressed = true
	get_viewport().push_input(wheel, true)
	var release: InputEventMouseButton = wheel.duplicate() as InputEventMouseButton
	release.pressed = false
	get_viewport().push_input(release, true)


func _text_fits(label: Label) -> bool:
	var font: Font = label.get_theme_font("font")
	var font_size: int = label.get_theme_font_size("font_size")
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x <= label.size.x


func _on_zoom() -> void:
	zoom_events += 1


func _capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/acl-unit-summary-%s.png" % label)


func _settle() -> void:
	for frame: int in range(4):
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


func _screen_rect(control: Control) -> Rect2:
	return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)
