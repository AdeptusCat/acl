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
	_pointer_event(settings.settings_button.get_global_rect().get_center(), MouseButton.MOUSE_BUTTON_LEFT)
	await _settle()
	_check(settings.menu.visible and settings.settings_button.button_pressed and not settings.controls_panel.visible, "The Settings button opens the audio menu")
	_check(map_clicks == 0, "Opening the menu does not select a battlefield hex")
	var master_before: float = SessionAudio.master_linear
	var music_before: float = SessionAudio.music_linear
	var links_before: bool = SessionSettings.showCmdConnectivity
	settings.s1.value = 0.35
	settings.s2.value = 0.42
	_check(is_equal_approx(SessionAudio.master_linear, 0.35) and is_equal_approx(SessionAudio.music_linear, 0.42), "Menu sliders update both session audio levels")
	_check(is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master")), SessionAudio.linear_to_db(0.35)) and is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")), SessionAudio.linear_to_db(0.42)), "Audio changes reach the actual master and music buses")
	_check(settings.master_label.text.ends_with("35%") and settings.music_label.text.ends_with("42%"), "Readable labels display the current volume percentages")
	var slider: HSlider = settings.s1
	_pointer_event(slider.get_global_rect().position + Vector2(slider.size.x * 0.75, slider.size.y * 0.5), MouseButton.MOUSE_BUTTON_LEFT)
	_check(SessionAudio.master_linear > 0.65 and SessionAudio.master_linear < 0.85 and is_equal_approx(SessionAudio.music_linear, 0.42), "An actual slider click changes only master volume")
	settings.command_links.button_pressed = not links_before
	_check(SessionSettings.showCmdConnectivity != links_before, "Command links remain configurable from the menu")
	settings.command_links.button_pressed = links_before
	var zoom_before: int = zoom_events
	_pointer_event(settings.menu.get_global_rect().get_center(), MouseButton.MOUSE_BUTTON_WHEEL_DOWN)
	_check(zoom_events == zoom_before, "Menu input does not zoom the battlefield")
	_pointer_event(settings.controls_button.get_global_rect().get_center(), MouseButton.MOUSE_BUTTON_LEFT)
	await _settle()
	_check(settings.controls_panel.visible and not settings.menu.visible and not settings.settings_button.button_pressed, "Controls opens separately and closes Settings")
	_check(settings.control_rows.get_child_count() == 7, "The controls panel describes selection, roster, orders, camera, zoom and closing")
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
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("battle-compact")
	SessionAudio.set_master_linear(master_before)
	SessionAudio.set_music_linear(music_before)
	main.queue_free()
	await _settle()
	print("HUD clutter checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


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
