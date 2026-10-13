extends Node

var checks: int = 0
var failures: int = 0
var starts: int = 0
var started_scenario: Scenario


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child(main)
	var world: Node = main.world
	var screen: CanvasLayer = world.start_screen
	world.set_process(false)
	world.game_controller.set_process(false)
	screen.game_started.connect(_on_started)
	get_tree().root.size = Vector2i(1152, 648)
	await _settle()
	_check(screen.start_button.disabled and screen.selected_scenario == null, "A mission requires a selection before Start mission becomes available")
	_check(not screen.force_briefing.visible and screen.player_roster_rows.is_empty() and screen.enemy_assessment.text.is_empty(), "No force or enemy preview is shown before choosing a mission")
	var map: Map = world.maps.get_node("DefaultMap")
	var available: Scenario = map.get_scenario(0)
	var button: Button = screen.scenario_buttons[available]
	await _select(screen, button)
	_check(screen.selected_map == map and screen.selected_scenario == available and button.button_pressed, "Clicking a scenario selects and highlights that mission")
	_check(starts == 0 and not world.is_setup and screen.visible, "Selecting a scenario does not start the battle")
	_check(screen.scenario_description.text == available.scenario_description and not screen.start_button.disabled, "Selection populates a persistent briefing and enables Start mission")
	_check_force_preview(screen, available)
	await _check_enemy_privacy(screen, available, button)
	var objectives: int = screen.major_victory_conditions_v_box_container.get_child_count()
	_motion(Vector2(20.0, 20.0))
	await _settle()
	_check(screen.scenario_description.text == available.scenario_description and button.button_pressed and screen.major_victory_conditions_v_box_container.get_child_count() == objectives, "Leaving a row retains its briefing, objectives and highlight")
	var other: Scenario = map.get_scenario(1)
	var other_button: Button = screen.scenario_buttons[other]
	screen.scenario_scroll.ensure_control_visible(other_button)
	await _settle()
	_motion(other_button.get_global_rect().get_center())
	await _settle()
	_check(screen.selected_scenario == available and button.button_pressed, "Hovering another mission does not replace the selected briefing")
	await _select(screen, other_button)
	_check(screen.selected_scenario == other and other_button.button_pressed and not button.button_pressed, "Selecting another mission transfers the persistent highlight")
	_check_force_preview(screen, other)
	var other_objectives: int = screen.major_victory_conditions_v_box_container.get_child_count()
	var other_roster_children: int = screen.player_roster.get_child_count()
	await _select(screen, other_button)
	_check(screen.major_victory_conditions_v_box_container.get_child_count() == other_objectives, "Reselecting a mission does not duplicate its objectives")
	_check(screen.player_roster.get_child_count() == other_roster_children, "Reselecting a mission replaces rather than duplicates its roster")
	var locked: Scenario = map.get_scenarios().back()
	_check(locked.previous_scenario != null, "The fixture provides a prerequisite-locked mission")
	var previous: Scenario = locked.previous_scenario
	var save_path: String = "user://matches/%s.tres" % previous.scenario_name.to_lower().replace(" ", "_")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://matches"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	await _select(screen, screen.scenario_buttons[locked])
	_check(screen.selected_scenario == locked and screen.start_button.disabled and screen.lock_label.text.contains(previous.scenario_name), "Locked missions remain selectable and explain which mission must be won")
	_check(starts == 0 and screen.scenario_description.text == locked.scenario_description, "A locked mission's briefing can be read without starting it")
	_check_force_preview(screen, locked)
	var saved: MatchSaveData = MatchSaveData.new()
	saved.player_team = Globals.Team.AXIS
	saved.winner_team = Globals.Team.ALLIES
	_check(ResourceSaver.save(saved, save_path) == OK, "The isolated progression fixture can save a previous result")
	await _select(screen, screen.scenario_buttons[locked])
	_check(screen.start_button.disabled, "Losing the prerequisite keeps the mission locked")
	saved.winner_team = saved.player_team
	ResourceSaver.save(saved, save_path)
	await _select(screen, screen.scenario_buttons[locked])
	_check(not screen.start_button.disabled and screen.lock_label.text.is_empty(), "Winning the prerequisite unlocks Start mission on reselection")
	available.scenario_description = "Read this briefing before deployment. ".repeat(150)
	await _select(screen, button)
	await _settle()
	var scrollbar: VScrollBar = screen.briefing_scroll.get_v_scroll_bar()
	_check(scrollbar.max_value > scrollbar.page, "Long briefings scroll within the mission selection panel")
	_check(_inside(screen), "The mission selector remains inside a compact viewport with a long briefing")
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("long")
	available.scenario_description = "Lead a platoon to clear the enemy outpost."
	await _select(screen, button)
	get_tree().root.size = Vector2i(1440, 900)
	await _settle()
	_check(_inside(screen), "The mission selector remains inside the large viewport")
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("selected")
	await _select(screen, screen.scenario_buttons[locked])
	# Restore the lock explanation for the preview, then launch an available mission.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	await _select(screen, screen.scenario_buttons[locked])
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("locked")
	await _select(screen, button)
	available.axis_ai_status = Scenario.AIStatus.OFF
	available.allies_ai_status = Scenario.AIStatus.OFF
	screen.time_spinbox.value = 4.0
	_check(is_equal_approx(screen.time, 4.0), "Mission time remains configurable before deployment")
	_click(screen.start_button.get_global_rect().get_center())
	screen._on_start_mission_pressed()
	await get_tree().create_timer(0.5).timeout
	_check(starts == 1 and started_scenario == available and not screen.visible and world.is_setup, "Start mission launches the selected mission once and closes selection")
	main.queue_free()
	await _settle()
	print("Scenario selection checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _check_force_preview(screen: CanvasLayer, scenario: Scenario) -> void:
	var friendly_count: int = 0
	for node: Node in scenario.get_units():
		if not node is Unit:
			continue
		var unit: Unit = node as Unit
		if unit.team != scenario.player_team:
			_check(not screen.player_roster_rows.has(unit), "The friendly roster does not reveal enemy squads")
			continue
		if not unit.is_active():
			continue
		friendly_count += 1
		var row: HBoxContainer = screen.player_roster_rows.get(unit)
		_check(row != null and row.get_node("Identity").text == unit.get_hud_name(), "The preview uses ordinal squad names and the selected scenario's player side")
		_check(row != null and row.get_node("Strength").text == "%d soldiers" % unit.squad_loadout.soldiers.size(), "Friendly strength comes from the actual deployment loadout")
	_check(screen.force_briefing.visible and screen.player_roster_rows.size() == friendly_count, "The selected mission shows its complete friendly roster")
	var has_number: bool = false
	for index: int in range(screen.enemy_assessment.text.length()):
		var code: int = screen.enemy_assessment.text.unicode_at(index)
		if code >= 48 and code <= 57:
			has_number = true
	_check(not screen.enemy_assessment.text.is_empty() and not has_number and not screen.enemy_assessment.text.contains("MG") and not screen.enemy_assessment.text.contains("Mortar") and not screen.enemy_assessment.text.contains("Antitank"), "Enemy intelligence gives broad capabilities without counts or exact squad types")


func _check_enemy_privacy(screen: CanvasLayer, scenario: Scenario, button: Button) -> void:
	var enemy: Unit
	for node: Node in scenario.get_units():
		if node is Unit and (node as Unit).team != scenario.player_team and (node as Unit).squad_type != Globals.SquadType.PLATOON_HEADQUARTERS:
			enemy = node as Unit
			break
	_check(enemy != null, "The fixture supplies an enemy combat squad")
	if enemy == null:
		return
	var assessment_before: String = screen.enemy_assessment.text
	var units_before: int = Globals.get_units().size()
	var roster_before: int = screen.player_roster_rows.size()
	var additional_enemy: Unit = enemy.duplicate() as Unit
	scenario.units.add_child(additional_enemy)
	await _select(screen, button)
	_check(screen.enemy_assessment.text == assessment_before and screen.player_roster_rows.size() == roster_before, "Increasing enemy numbers does not change the qualitative assessment or the friendly roster")
	_check(Globals.get_units().size() == units_before and starts == 0, "Previewing forces does not register battle units or start a mission")
	scenario.units.remove_child(additional_enemy)
	additional_enemy.queue_free()
	await _select(screen, button)


func _select(screen: CanvasLayer, button: Button) -> void:
	screen.scenario_scroll.ensure_control_visible(button)
	await _settle()
	_click(button.get_global_rect().get_center())
	await _settle()


func _inside(screen: CanvasLayer) -> bool:
	return Rect2(Vector2.ZERO, screen.get_node("Control").size).encloses(screen.panel.get_rect())


func _motion(point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	get_viewport().push_input(event, true)


func _click(point: Vector2) -> void:
	_motion(point)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MouseButton.MOUSE_BUTTON_LEFT
	event.pressed = true
	get_viewport().push_input(event, true)
	event.pressed = false
	get_viewport().push_input(event, true)


func _on_started(_map: Map, scenario: Scenario, _team: int, _mode: Globals.GameMode) -> void:
	starts += 1
	started_scenario = scenario


func _capture(label: String) -> void:
	await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/acl-scenario-%s.png" % label)


func _settle() -> void:
	for frame: int in range(6):
		await get_tree().process_frame


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
