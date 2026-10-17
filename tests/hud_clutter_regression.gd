extends Node

var checks: int = 0
var failures: int = 0
var zoom_events: int = 0
var map_clicks: int = 0


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var settings: Control = world.ui.get_node("Control/Settings") as Control
	var debug: PanelContainer = world.ui.get_node("Control/Debug") as PanelContainer
	var muted_before: bool = SessionAudio.master_muted
	_check(not settings.menu.visible and not settings.controls_panel.visible, "Settings and controls start closed")
	_check(debug.section.folded, "Development controls start collapsed")
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
	await _settle()
	_check(settings.size.y <= 32.0 and debug.size.y <= 48.0, "Persistent settings and debug occupy only small button and title bars")
	world.input_manager.zoom_in.connect(_on_zoom)
	world.input_manager.zoom_out.connect(_on_zoom)
	world.input_manager.mouse_button_left_pressed.connect(_on_map_click)
	_pointer_event(Vector2(1000, 100), MouseButton.MOUSE_BUTTON_WHEEL_UP)
	_check(zoom_events == 1, "Closed settings do not block zoom over their former HUD area")
	_check_top_layout(world, settings)
	var master_before: float = SessionAudio.master_linear
	var music_before: float = SessionAudio.music_linear
	SessionAudio.set_master_muted(false)
	var speaker_icon: Texture2D = settings.mute_button.icon
	_check(settings.mute_button.get_global_rect().end.x < settings.settings_button.get_global_rect().position.x and settings.mute_button.size.x <= 36.0, "The compact speaker button sits immediately left of Settings")
	_pointer_event(settings.mute_button.get_global_rect().get_center(), MouseButton.MOUSE_BUTTON_LEFT)
	_check(SessionAudio.master_muted and AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")) and settings.mute_button.button_pressed and settings.mute_button.icon != speaker_icon, "Clicking the speaker mutes all sound and displays the crossed-out icon")
	_check(is_equal_approx(SessionAudio.master_linear, master_before) and is_equal_approx(SessionAudio.music_linear, music_before) and map_clicks == 0 and not settings.menu.visible, "Muting preserves volume levels and consumes the click without opening a menu")
	_pointer_event(settings.settings_button.get_global_rect().get_center(), MouseButton.MOUSE_BUTTON_LEFT)
	await _settle()
	_check(settings.menu.visible and settings.settings_button.button_pressed and not settings.controls_panel.visible, "The Settings button opens the audio menu")
	_check(map_clicks == 0, "Opening the menu does not select a battlefield hex")
	var links_before: bool = SessionSettings.showCmdConnectivity
	settings.s1.value = 0.35
	settings.s2.value = 0.42
	_check(is_equal_approx(SessionAudio.master_linear, 0.35) and is_equal_approx(SessionAudio.music_linear, 0.42), "Menu sliders update both session audio levels")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")), SessionAudio.linear_to_db(0.35)) and is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), SessionAudio.linear_to_db(0.42)), "Audio changes reach the actual master and music buses")
	_check(settings.master_label.text.ends_with("35%") and settings.music_label.text.ends_with("42%"), "Readable labels display the current volume percentages")
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "Changing volume while muted keeps the master bus muted")
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("muted-settings")
	_pointer_event(settings.mute_button.get_global_rect().get_center(), MouseButton.MOUSE_BUTTON_LEFT)
	_check(not SessionAudio.master_muted and not AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")) and not settings.mute_button.button_pressed and settings.mute_button.icon == speaker_icon, "Clicking the crossed-out speaker restores sound and the normal icon")
	_check(settings.menu.visible and is_equal_approx(SessionAudio.master_linear, 0.35) and is_equal_approx(SessionAudio.music_linear, 0.42), "Unmuting restores the chosen volume levels and leaves Settings open")
	SessionAudio.set_master_muted(true)
	var recreated: Control = load("res://scenes/ui/panels/battle_settings_panel.tscn").instantiate()
	world.ui.get_node("Control").add_child(recreated)
	await _settle()
	_check(recreated.mute_button.button_pressed and recreated.mute_button.icon == settings.mute_button.icon and AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "A recreated toolbar retains the session mute state")
	recreated.queue_free()
	await _settle()
	SessionAudio.set_master_muted(false)
	_check(not settings.mute_button.button_pressed and settings.mute_button.tooltip_text == "Mute sound", "Session mute changes keep the existing toolbar synchronized")
	var slider: HSlider = settings.s1
	_pointer_event(slider.get_global_rect().position + Vector2(slider.size.x * 0.75, slider.size.y * 0.5), MouseButton.MOUSE_BUTTON_LEFT)
	_check(SessionAudio.master_linear > 0.65 and SessionAudio.master_linear < 0.85 and is_equal_approx(SessionAudio.music_linear, 0.42), "An actual slider click changes only master volume")
	settings.command_links.button_pressed = not links_before
	_check(SessionSettings.showCmdConnectivity != links_before, "Command links remain configurable from the menu")
	_check(settings.command_view_button.button_pressed == SessionSettings.showCmdConnectivity, "The toolbar reflects the command view setting")
	settings.command_links.button_pressed = links_before
	var zoom_before: int = zoom_events
	_pointer_event(settings.menu.get_global_rect().get_center(), MouseButton.MOUSE_BUTTON_WHEEL_DOWN)
	_check(zoom_events == zoom_before, "Menu input does not zoom the battlefield")
	_pointer_event(settings.controls_button.get_global_rect().get_center(), MouseButton.MOUSE_BUTTON_LEFT)
	await _settle()
	_check(settings.controls_panel.visible and not settings.menu.visible and not settings.settings_button.button_pressed, "Controls opens separately and closes Settings")
	_check(settings.control_rows.get_child_count() == 8, "The controls panel describes selection, roster, orders, cancellation, camera, zoom and closing")
	var readable: bool = true
	for row: HBoxContainer in settings.control_rows.get_children():
		for label: Label in row.get_children():
			readable = readable and label.get_theme_font_size("font_size") >= 13 and _text_fits(label)
	_check(readable, "Controls use readable type with fully visible key and action text")
	_check(_inside_hud(settings.controls_panel, world), "The controls panel stays inside the large viewport")
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("controls-wide")
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape, true)
	_check(not settings.controls_panel.visible and not settings.controls_button.button_pressed, "Escape closes the open controls panel")
	_pointer_event(settings.settings_button.get_global_rect().get_center(), MouseButton.MOUSE_BUTTON_LEFT)
	await _settle()
	_check(is_equal_approx(settings.s2.value, 0.42), "Closing and reopening the menu preserves volume settings")
	var outside: Vector2 = settings.menu.get_global_rect().position + Vector2(-20.0, 10.0)
	_pointer_event(outside, MouseButton.MOUSE_BUTTON_LEFT)
	_check(not settings.menu.visible, "Clicking outside the active menu closes it even inside the hidden controls panel's bounds")
	_pointer_event(settings.settings_button.get_global_rect().get_center(), MouseButton.MOUSE_BUTTON_LEFT)
	await _settle()
	_pointer_event(settings.get_node("Menu/Content/Heading/Close").get_global_rect().get_center(), MouseButton.MOUSE_BUTTON_LEFT)
	_check(not settings.menu.visible, "The explicit Close button closes Settings")
	debug.section.expand()
	await _settle()
	_check(debug.axis_ai_status.is_visible_in_tree() and not debug.axis_ai_status.disabled, "Expanding debug reveals the existing functional AI controls")
	_check(not debug.get_rect().intersects(world.ui.squad_roster.get_rect()), "Expanded debug does not cover the squad roster")
	_check(not debug.get_rect().intersects(world.ui.mission_objectives.get_rect()) and not debug.get_rect().intersects(world.ui.tile_details.get_rect()), "Expanded debug avoids mission objectives and tile details")
	await _test_debug_overlays(world, debug)
	debug.section.fold()
	await _settle()
	_check(not debug.axis_ai_status.is_visible_in_tree() and debug.size.y <= 48.0, "Folding debug restores the compact title bar")
	var squad: Unit = Globals.get_units_for_team(Globals.team_player)[1]
	var summary: PanelContainer = world.ui.unit_details
	summary.show_unit_detail(squad, false)
	squad.stress_system._set_state(STATES.MoraleState.PINNED)
	summary._process(0.0)
	await _settle()
	_check(summary.rout_button.visible and summary.rout_button.text == "Rout squad" and summary.unit_status_label.text.contains("Pinned"), "Pinned squads have a clear state and a steady rout action")
	_check(summary.rout_explanation.visible and summary.rout_explanation.text.contains("surrender") and summary.rout_button.tooltip_text.contains("uncontrolled"), "Rout explains normal movement limits, loss of control and surrender risk")
	for sample: int in range(3):
		await get_tree().create_timer(0.24).timeout
		_check(summary.rout_button.scale == Vector2.ONE and summary.rout_button.modulate == Color.WHITE, "The rout button remains stationary without a repeating pulse")
	squad.in_close_combat = true
	summary._process(0.0)
	_check(not summary.rout_button.visible and summary.rout_explanation.text.contains("unavailable"), "Close combat explains why rout is unavailable")
	squad.in_close_combat = false
	summary._process(0.0)
	var countdown: PanelContainer = world.ui.countdown_panel_container
	countdown.set_countdown(false)
	countdown.update_timer_label(20.0)
	_check(countdown.timer_label.modulate == Color.WHITE and countdown._alert_tween == null, "The pre-battle timer stays steady")
	countdown.set_countdown(true)
	var cue: Tween = countdown._alert_tween
	_check(cue != null and countdown.timer_label.modulate.r > countdown.timer_label.modulate.g, "Entering low time emits one warning cue and a clear warning color")
	countdown.update_timer_label(19.0)
	_check(countdown._alert_tween == cue, "Normal countdown ticks do not restart the warning animation")
	await get_tree().create_timer(0.4).timeout
	countdown.update_timer_label(18.0)
	_check(not cue.is_running() and countdown.timer_label.scale == Vector2.ONE, "The timer settles after its one brief warning")
	countdown.update_timer_label(0.0)
	_check(countdown.timer_label.text == "00:00" and countdown._alert_tween == null, "Time expiry keeps a readable fixed timer")
	countdown.update_timer_label(180.0)
	_check(countdown.timer_label.modulate == Color.WHITE, "A reset restores the normal timer appearance")
	get_tree().root.size = Vector2i(800, 600)
	await _settle()
	_check_top_layout(world, settings)
	_pointer_event(settings.controls_button.get_global_rect().get_center(), MouseButton.MOUSE_BUTTON_LEFT)
	await _settle()
	_check(_inside_hud(settings.controls_panel, world), "The controls panel stays inside the small viewport")
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("controls-compact")
	_pointer_event(settings.settings_button.get_global_rect().get_center(), MouseButton.MOUSE_BUTTON_LEFT)
	await _settle()
	_check(_inside_hud(settings.menu, world) and not settings.controls_panel.visible, "The audio menu remains contained on a small window")
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("settings-compact")
	settings.close_panels()
	await _settle()
	await _check_unit_readability(world, squad, summary)
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("battle-compact")
	get_tree().root.size = Vector2i(708, 639)
	await _settle()
	_check_top_layout(world, settings)
	await _check_unit_readability(world, squad, summary)
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("battle-narrow")
	SessionAudio.set_master_linear(master_before)
	SessionAudio.set_music_linear(music_before)
	SessionAudio.set_master_muted(muted_before)
	main.queue_free()
	await _settle()
	print("HUD clutter checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _check_unit_readability(world: Node, squad: Unit, summary: PanelContainer) -> void:
	_check(_inside_hud(summary, world) and not summary.get_rect().intersects(world.ui.mission_objectives.get_rect()), "Selected squad information stays below objectives and inside the viewport")
	_check(not summary.cohesion_bar.is_visible_in_tree() and not summary.effectiveness_bar.is_visible_in_tree(), "Detailed combat statistics stay collapsed during normal selection")
	for label: Label in [summary.strength_label, summary.unit_status_label, summary.command_label, summary.order_label]:
		_check(_text_fits(label), "Primary squad text remains fully readable: " + label.text)
	var ui: UnitUi = squad.ui
	_check(not ui.stress_arrows.get_rect().intersects(ui.morale_bar.get_rect()) and not ui.recovery_arrows.get_rect().intersects(ui.morale_bar.get_rect()), "Stress and recovery text have their own row above the morale bar")
	for row: SquadRosterRow in world.ui.squad_roster.rows.values():
		_check(row.get_node("Content").get_rect().end.y <= row.size.y, "Roster row height includes every visible text line")
	world.ui.show_order_feedback(true, "Move", "Squad moving to its destination")
	await _settle()
	var feedback: Control = world.ui.get_node("Control/OrderFeedback")
	_check(not feedback.get_rect().intersects(world.ui.mission_objectives.get_rect()) and not feedback.get_rect().intersects(summary.get_rect()), "Order feedback leaves objectives and squad text unobstructed")
	world.ui.hide_order_feedback()
	await _settle()


func _test_debug_overlays(world: Node, panel: PanelContainer) -> void:
	var draw: InfluenceMapDebugDraw = world.game_controller.influence_map_debug_draw
	var influence: InfluenceMapController = world.game_controller.influence_map_controller
	var squad: Unit = Globals.get_units_for_team(Globals.team_player)[1]
	var stress_arrow: Label = squad.ui.get_node("StressLevel")
	var leadership_arrow: Label = squad.ui.get_node("LeadershipBonus")
	var stress_text_before: String = stress_arrow.text
	var leadership_text_before: String = leadership_arrow.text
	var morale_value_before: float = squad.ui.morale_bar.value
	_check(not Debug.show_ai_placement and not draw.visible and not draw.debug_enabled and not draw.is_processing() and not panel.placement_options.visible, "AI placement overlays start hidden and inactive")
	_check(not Debug.show_debug_text and not draw.draw_cell_values and not draw.draw_layer_access_text and not squad.ui.get_node("AmmunitionLeft").visible, "Numeric counters, map values and diagnostic text start hidden")
	squad.stress_system.stress_changed.emit(60.0)
	squad.stress_system.stress_balance_changed.emit(3.0, 1.0, 1.0, 2.0)
	squad.stress_system.leadership_changed.emit(RankGrades.GRADE_PARAMS[RankGrades.Grade.PLATOON_LEADER].lead)
	_check_morale_markers(squad, "Normal play with all debug toggles off")
	world.game_controller._select_unit(squad)
	draw._on_influence_maps_updated()
	draw._process(1.0)
	_check(draw.selected_unit == squad and draw.position_advice == null and influence.inspection_jobs.is_empty() and influence.inspection_results.is_empty() and draw._layer_access_text.is_empty(), "Selecting a squad with debugging off performs no placement inspection")
	var shortcut: InputEventKey = InputEventKey.new()
	shortcut.keycode = KEY_F1
	shortcut.pressed = true
	get_viewport().push_input(shortcut, true)
	_check(not draw.visible and draw.debug_view == InfluenceMapDebugDraw.DebugView.NONE, "A debug keyboard shortcut cannot enable overlays while the menu toggle is off")
	for frame: int in range(1000):
		influence._process_los_rebuild()
		influence._process_budgeted_rebuild()
		if influence.snapshot != null:
			break
	var order_id: int = squad.action_controller.action_order_id
	var assigned: PositionResult = squad.position_advice
	_pointer_event(panel.ai_placement.get_global_rect().get_center(), MouseButton.MOUSE_BUTTON_LEFT)
	await _settle()
	_finish_placement_inspection(influence, draw)
	_check(Debug.show_ai_placement and draw.visible and draw.debug_enabled and draw.debug_view == InfluenceMapDebugDraw.DebugView.POSITION_SCORE and draw.position_advice != null and panel.placement_options.visible, "The debug-menu checkbox enables placement inspection for the already selected squad")
	_check(not draw.draw_cell_values and not draw.draw_layer_access_text and not squad.ui.get_node("AmmunitionLeft").visible, "Enabling AI placement alone leaves numeric and text diagnostics hidden")
	_check_morale_markers(squad, "AI placement enabled")
	_check(squad.action_controller.action_order_id == order_id and squad.position_advice == assigned, "Inspecting placement preserves the squad's orders and tactical assignment")
	var layer_index: int = panel.placement_layer.get_item_index(InfluenceMapDebugDraw.DebugView.THREAT)
	panel.placement_layer.select(layer_index)
	panel.placement_layer.item_selected.emit(layer_index)
	var team_index: int = panel.placement_team.get_item_index(Globals.team_enemy)
	panel.placement_team.select(team_index)
	panel.placement_team.item_selected.emit(team_index)
	_check(draw.debug_view == InfluenceMapDebugDraw.DebugView.THREAT and draw.team == Globals.team_enemy and not panel.placement_team.disabled, "Debug-menu selectors change the influence layer and team")
	world.game_controller._deselect_unit(squad)
	world.game_controller._select_unit(squad)
	_check(draw.team == squad.team and panel.placement_team.disabled and panel.placement_layer.get_selected_id() == InfluenceMapDebugDraw.DebugView.POSITION_SCORE, "Selecting a squad updates placement diagnostics and synchronizes the menu")
	_finish_placement_inspection(influence, draw)
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("placement-debug")
	_pointer_event(panel.ai_placement.get_global_rect().get_center(), MouseButton.MOUSE_BUTTON_LEFT)
	await _settle()
	_check(not draw.visible and not draw.debug_enabled and not draw.is_processing() and draw.position_advice == null and influence.inspection_jobs.is_empty() and influence.inspection_results.is_empty(), "Disabling the checkbox hides every AI overlay and cancels inspection work immediately")
	draw.set_debug_view(InfluenceMapDebugDraw.DebugView.THREAT)
	world.game_controller._select_unit(squad)
	_check(not draw.visible and draw.position_advice == null, "Layer changes and later selections cannot bypass the disabled debug toggle")
	_pointer_event(panel.debug_text.get_global_rect().get_center(), MouseButton.MOUSE_BUTTON_LEFT)
	_check(Debug.show_debug_text and draw.draw_cell_values and draw.draw_layer_access_text and squad.ui.get_node("AmmunitionLeft").visible and not draw.visible, "Debug text has a separate explicit toggle and does not enable influence overlays")
	_check_morale_markers(squad, "Debug text enabled")
	_pointer_event(panel.debug_text.get_global_rect().get_center(), MouseButton.MOUSE_BUTTON_LEFT)
	_check(not Debug.show_debug_text and not squad.ui.get_node("AmmunitionLeft").visible, "Turning debug text off hides numeric counters")
	_check_morale_markers(squad, "Both debug toggles disabled again")
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("morale-markers")
	var exited: UnitUi = load("res://scenes/game/units/presentation/unit_battlefield_view.tscn").instantiate()
	world.ui.get_node("Control").add_child(exited)
	exited.mark_exited()
	Debug.show_debug_text = true
	_check(not exited.get_node("AmmunitionLeft").visible and not exited.get_node("StressLevel").visible, "Debug text cannot restore annotations for an exited squad")
	Debug.show_debug_text = false
	exited.queue_free()
	draw.set_debug_view(InfluenceMapDebugDraw.DebugView.NONE)
	world.game_controller._deselect_unit(squad)
	stress_arrow.text = stress_text_before
	leadership_arrow.text = leadership_text_before
	squad.ui.morale_bar.value = morale_value_before
	await _settle()


func _finish_placement_inspection(influence: InfluenceMapController, draw: InfluenceMapDebugDraw) -> void:
	for frame: int in range(1000):
		influence._process_position_queries()
		draw._refresh_position_advice()
		if draw.position_advice != null:
			return
	_check(false, "Placement inspection completes")


func _check_morale_markers(squad: Unit, context: String) -> void:
	var stress: Label = squad.ui.get_node("StressLevel")
	var leadership: Label = squad.ui.get_node("LeadershipBonus")
	_check(stress.visible and stress.text == "<<<" and leadership.visible and leadership.text == ">>", "%s preserves working stress and recovery arrows" % context)
	_check(squad.ui.morale_bar.visible and is_equal_approx(squad.ui.morale_bar.value, 0.4) and squad.ui.rank_texture_rect.visible and squad.ui.unit_status_control.visible, "%s preserves morale bars and squad status icons" % context)


func _check_top_layout(world: Node, settings: Control) -> void:
	var retry: Control = world.ui.get_node("Control/TryAgain")
	var countdown: Control = world.ui.countdown_panel_container
	var retry_rect: Rect2 = retry.get_rect()
	var timer_rect: Rect2 = countdown.get_rect()
	var header_rect: Rect2 = retry_rect.merge(timer_rect)
	var hud_width: float = world.ui.get_node("Control").size.x
	_check(is_equal_approx(header_rect.get_center().x, hud_width * 0.5) and is_equal_approx(retry_rect.position.y, timer_rect.position.y) and is_equal_approx(timer_rect.position.x - retry_rect.end.x, 8.0), "Try Again and Time Left form a centered adjacent row at width %d" % int(hud_width))
	_check(_inside_hud(retry, world) and _inside_hud(countdown, world) and not header_rect.intersects(settings.get_rect()), "The centered header stays onscreen without overlapping the speaker and settings buttons")
	_check(not header_rect.intersects(world.ui.mission_objectives.get_rect()) and not header_rect.intersects(world.ui.squad_roster.get_rect()), "The header leaves objectives and the squad roster clear")


func _inside_hud(panel: Control, world: Node) -> bool:
	var hud_size: Vector2 = world.ui.get_node("Control").size
	return Rect2(Vector2.ZERO, hud_size).encloses(panel.get_global_rect())


func _text_fits(label: Label) -> bool:
	return label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, label.get_theme_font_size("font_size")).x <= label.size.x


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


func _on_zoom() -> void:
	zoom_events += 1


func _on_map_click(_position: Vector2) -> void:
	map_clicks += 1


func _capture(label: String) -> void:
	await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/acl-hud-%s.png" % label)


func _settle() -> void:
	for frame: int in range(6):
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
