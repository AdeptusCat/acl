extends "res://tests/order_queue_regression.gd"


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
	controller = world.game_controller
	ground = world.ground_layer
	first = Globals.get_units_for_team(Globals.team_player)[1]
	second = Globals.get_units_for_team(Globals.team_player)[2]
	origin = first.current_hex
	destination = _neighbor(origin, origin)
	onward = _neighbor(destination, origin)
	_reset(first, origin)
	_reset(second, destination)
	controller.camera.position_smoothing_enabled = false
	controller.camera.position = first.position
	controller.camera.reset_smoothing()
	controller.camera.force_update_scroll()
	await _settle_selection()
	var a: Vector2 = BattlefieldStacks.counter_rect(first).get_center()
	var b: Vector2 = BattlefieldStacks.counter_rect(second).get_center()
	_click(a)
	_check(controller.get_selected_units() == [first], "A plain battlefield click selects one squad")
	_shift(true)
	_click(b)
	_check(first.selected and second.selected and controller.get_selected_units().size() == 2, "Shift-click adds a second battlefield squad")
	_click(a)
	_check(not first.selected and second.selected and controller.selected_unit == second, "Shift-click toggles a selected battlefield squad off")
	_shift(false)
	_click(a)
	_check(first.selected and not second.selected, "A plain click replaces multiple selection")
	_shift(true)
	var camera_before: Vector2 = controller.camera.position
	var roster: SquadRosterPanel = world.ui.squad_roster
	roster._on_row_pressed(roster.rows[second])
	_check(first.selected and second.selected and controller.camera.position == camera_before, "Roster Shift-click adds a squad without moving the camera")
	roster._on_row_pressed(roster.rows[first])
	_check(not first.selected and second.selected and roster.rows[second].button_pressed and not roster.rows[first].button_pressed, "Roster Shift-click removes a squad and synchronizes highlights")
	_shift(false)
	var rect: Rect2 = BattlefieldStacks.counter_rect(first).merge(BattlefieldStacks.counter_rect(second)).grow(4.0)
	_drag(rect.end, rect.position)
	_check(first.selected and second.selected and not controller._selection_dragging, "A reversed rectangle selects both counters and ends on release")
	var enemy: Unit = Globals.get_units_for_team(Globals.team_enemy)[0]
	_check(not enemy.selected, "Rectangle selection excludes enemy squads")
	var members: Array[Unit] = [first]
	controller.set_selected_units(members)
	_shift(true)
	var small: Rect2 = BattlefieldStacks.counter_rect(second).grow(2.0)
	_drag(small.position, small.end)
	_check(first.selected and second.selected, "Shift-drag preserves the original selection and adds enclosed squads")
	_shift(false)
	var pair: Array[Unit] = [first, second]
	controller.set_selected_units(pair)
	first.clear_orders()
	second.clear_orders()
	_check(controller.order_via_option_wheel(onward, WheelOption.Option.MOVE_NORMAL), "A move can be issued to multiple selected squads")
	_check(first.action_controller.objective_hex == onward and second.action_controller.objective_hex == onward, "A shared move command reaches both squads")
	_shift(true)
	controller.order_via_option_wheel(origin, WheelOption.Option.MOVE_NORMAL)
	_check(first.action_controller.order_queue.pending.size() == 1 and second.action_controller.order_queue.pending.size() == 1, "Shift Move appends independently to every selected squad")
	_shift(false)
	controller.order_via_option_wheel(origin, WheelOption.Option.STOP)
	_check(first.action_controller.order_queue.entries().is_empty() and second.action_controller.order_queue.entries().is_empty(), "Stop clears every selected squad's queue")
	var pinned_primary: Array[Unit] = [second, first]
	controller.set_selected_units(pinned_primary)
	first.stress_system.state = STATES.MoraleState.PINNED
	_check(controller.order_via_option_wheel(onward, WheelOption.Option.MOVE_NORMAL) and second.movement.target_hex == onward, "A pinned primary member does not block another selected squad's move")
	first.stress_system.state = STATES.MoraleState.NORMAL
	var before: Array[Unit] = controller.get_selected_units()
	var screen_start: Vector2 = rect.position
	_mouse(screen_start, true)
	_motion(rect.end)
	var hud_point: Vector2 = world.ui.get_node("Control/Settings").get_global_rect().get_center()
	_mouse(hud_point, false)
	_check(not controller._selection_pressed and not controller._selection_dragging, "A rectangle drag releases even over HUD controls")
	controller.set_selected_units(before)
	_mouse(rect.position, true)
	_motion(rect.end)
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	Input.flush_buffered_events()
	_check(not controller._selection_pressed and controller.get_selected_units() == before, "Escape cancels rectangle selection and restores the preceding selection")
	world._command_unit = controller.selected_unit
	world._command_selection_revision = controller.selection_revision
	var primary: Unit = controller.selected_unit
	var other: Unit = first
	if other == primary:
		other = second
	controller.toggle_unit_selection(other)
	_check(controller.selected_unit == primary and not world._wheel_restriction(WheelOption.Option.MOVE_NORMAL).is_empty(), "Changing selection invalidates the command wheel even when the primary squad is unchanged")
	controller.set_selected_units(before)
	second.exited = true
	controller._on_unit_exited(second)
	_check(first.selected and not second.selected and controller.selected_unit == first, "An exiting squad leaves selection without clearing surviving members")
	second.exited = false
	var empty: Array[Unit] = []
	controller.set_selected_units(empty)
	_check(controller.selected_unit == null and not first.selected, "Clearing selection clears all counter highlights")
	main.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("Multiple selection checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _shift(pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_SHIFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _mouse(point: Vector2, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _motion(point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _click(point: Vector2) -> void:
	_mouse(point, true)
	_mouse(point, false)


func _drag(start: Vector2, finish: Vector2) -> void:
	_mouse(start, true)
	_motion(finish)
	_mouse(finish, false)


func _settle_selection() -> void:
	for frame: int in range(6):
		await get_tree().process_frame
