extends Node

var checks: int = 0
var failures: int = 0
var feedback: Array[Dictionary] = []
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
	get_tree().root.size = Vector2i(1152, 648)
	var controller: Node2D = world.game_controller
	var ground: HexagonTileMapLayer = world.ground_layer
	var unit: Unit = Globals.get_units_for_team(Globals.team_player)[1]
	controller.select_and_center_unit(unit)
	controller.order_feedback.connect(_on_feedback)
	world.input_manager.mouse_button_left_pressed.connect(_on_map_click)
	world.ui.hide_target_hex_cover_distance()
	await _settle()
	var wheel: Control = world.ui.selection_wheel_alt
	var destination: Vector2i = _reachable_neighbor(unit, ground)
	var target_point: Vector2 = controller.get_global_transform_with_canvas() * ground.map_to_local(destination)
	var order_before: int = unit.action_controller.action_order_id
	_right_open(target_point)
	await _settle()
	_check(wheel.is_open() and wheel.selected_label.text == "Move", "Right click opens the wheel with Move in the center")
	_check(wheel.options.size() == 4 and wheel.options[0].option == WheelOption.Option.MOVE_NORMAL and wheel.options[1].option == WheelOption.Option.FIRE_AT and wheel.options[2].option == WheelOption.Option.STOP and wheel.options[3].option == WheelOption.Option.NONE, "The wheel restores the original Move, Fire, Stop and Cancel order")
	_check(wheel.get_option_point(0) == Vector2.ZERO and is_zero_approx(wheel.get_option_point(1).x) and wheel.get_option_point(1).y < 0.0 and wheel.get_option_point(2).x < 0.0 and wheel.get_option_point(2).y > 0.0 and wheel.get_option_point(3).x > 0.0 and wheel.get_option_point(3).y > 0.0, "The original layout has Move centered, Fire above, Stop lower left and Cancel lower right")
	for index: int in range(1, wheel.options.size()):
		_motion(wheel.position + wheel.get_option_point(index))
		_check(wheel.selected_label.text == WheelOption.COMMAND_NAMES[wheel.options[index].option], "Pointing at each outer command selects its displayed label")
	_motion(wheel.position + wheel.get_option_point(0))
	_check(wheel.selected_label.text == "Move", "Pointing at Move displays the command prominently")
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape, true)
	_right_release(wheel.position)
	_check(not wheel.is_open() and unit.action_controller.action_order_id == order_before and feedback.is_empty(), "Escape cancels the wheel and releasing right click cannot issue a stale command")
	_right_open(target_point)
	await _settle()
	_motion(wheel.position + wheel.get_option_point(0))
	_mouse(wheel.position, MouseButton.MOUSE_BUTTON_LEFT, true)
	_mouse(wheel.position, MouseButton.MOUSE_BUTTON_LEFT, false)
	_right_release(wheel.position)
	_check(not wheel.is_open() and unit.action_controller.action_order_id == order_before and map_clicks == 0, "Left click cancels without selecting a battlefield hex")
	_right_open(target_point)
	await _settle()
	_right_release(wheel.position + wheel.get_option_point(3))
	_check(unit.action_controller.action_order_id == order_before and feedback.is_empty(), "Releasing in the Cancel sector preserves existing orders")
	_right_open(target_point)
	await _settle()
	_right_release(wheel.position + Vector2(220.0, 0.0))
	_check(unit.action_controller.action_order_id == order_before, "Releasing outside the wheel cancels instead of choosing a sector")
	_right_open(target_point)
	await _settle()
	var move_point: Vector2 = wheel.position + wheel.get_option_point(0)
	_motion(move_point)
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("move")
	_right_release(move_point)
	_check(unit.action_controller.action_order_id > order_before and unit.action_controller.objective_hex == destination, "Releasing Move submits the original target hex through the actual input path")
	_check(bool(feedback.back()["accepted"]) and _feedback_title(world).contains("Order accepted · Move"), "Accepted movement gets explicit positive feedback")
	_right_open(target_point)
	await _settle()
	_right_release(wheel.position + wheel.get_option_point(2))
	_check(unit.action_controller.action_state == SquadActionController.SquadActionState.NO_ORDER and not unit.movement.is_moving, "Stop clears the pending movement order")
	_check(_feedback_title(world).contains("Order accepted · Stop"), "Stop reports acceptance")
	unit.stress_system._set_state(STATES.MoraleState.PINNED)
	order_before = unit.action_controller.action_order_id
	_right_open(target_point)
	await _settle()
	move_point = wheel.position + wheel.get_option_point(0)
	_motion(move_point)
	_check(wheel.restriction_label.text == "Cannot move while pinned.", "An unavailable Move command explains the pinned restriction")
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("pinned")
	var children_before: int = controller.get_child_count()
	_right_release(move_point)
	_check(unit.action_controller.action_order_id == order_before and not bool(feedback.back()["accepted"]), "Pinned movement is rejected without changing orders")
	_check(_feedback_title(world).contains("Order rejected · Move") and controller.get_child_count() <= children_before, "Rejection gets an explicit message and no success glow")
	unit.stress_system._set_state(STATES.MoraleState.NORMAL)
	var original_los: Dictionary = LOSHelper.los_lookup[unit.current_hex].duplicate(true)
	LOSHelper.los_lookup[unit.current_hex].erase(destination)
	_motion(target_point)
	MatchInteractionHandler.refresh_target_preview(controller, ground.map_to_local(destination), target_point)
	var hint: Control = world.ui.target_cover_distance
	_check(hint.visible and hint.heading.text == "Line of sight blocked" and hint.detail.text.contains("Cover: unknown") and hint.extra.text.contains("Effective firepower: 0"), "Blocked direct-fire targets keep a visible, correctly labeled preview")
	_check(not controller.order_via_option_wheel(destination, WheelOption.Option.FIRE_AT) and str(feedback.back()["explanation"]).contains("Line of sight blocked"), "Blocked direct fire is rejected with its reason")
	var original_type: Globals.SquadType = unit.squad_type
	unit.squad_type = Globals.SquadType.MORTAR
	_check(MatchInteractionHandler.command_restriction(controller, destination, WheelOption.Option.FIRE_AT).is_empty(), "Indirect fire remains available without direct line of sight")
	MatchInteractionHandler.refresh_target_preview(controller, ground.map_to_local(destination), target_point)
	_check(hint.visible and hint.heading.text == "Indirect fire", "The preview distinguishes indirect fire from blocked direct fire")
	unit.squad_type = original_type
	LOSHelper.los_lookup[unit.current_hex][destination] = {"target_cover": 2}
	var far_target: Vector2i = _far_hex(unit, ground)
	LOSHelper.los_lookup[unit.current_hex][far_target] = {"target_cover": 1}
	MatchInteractionHandler.refresh_target_preview(controller, ground.map_to_local(far_target), target_point)
	_check(hint.visible and hint.heading.text == "Out of range" and controller.firepower == 0.0, "Out-of-range targets keep a visible preview with zero effective firepower")
	_check(not controller.order_via_option_wheel(far_target, WheelOption.Option.FIRE_AT) and str(feedback.back()["explanation"]).contains("Out of range"), "Fire orders beyond the live weapon ranges are rejected explicitly")
	MatchInteractionHandler.refresh_target_preview(controller, ground.map_to_local(destination), target_point)
	var expected: float = InfluenceUnitQuery.get_firepower_at_range(unit, controller.distance) * InfluenceUnitQuery.get_unit_effectiveness(unit)
	_check(hint.detail.text.contains("Distance:") and hint.detail.text.contains("Cover: 2") and hint.extra.text.contains("Effective firepower:") and is_equal_approx(controller.firepower, expected), "The preview labels distance and directional cover and uses live effective firepower")
	_check(controller.order_via_option_wheel(destination, WheelOption.Option.FIRE_AT) and unit.squad_fire.has_target_hex and unit.squad_fire.target_hex == destination, "Valid fire is accepted and actually assigns the intended target")
	_check(_feedback_title(world).contains("Order accepted · Fire"), "Accepted fire is distinguished from rejection")
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("accepted-fire")
	controller.order_via_option_wheel(destination, WheelOption.Option.STOP)
	_check(not unit.squad_fire.has_target_hex and not unit.squad_fire.has_mortar_target_hex, "Stop clears manual fire even when no movement order is active")
	_right_open(target_point)
	await _settle()
	var other: Unit = Globals.get_units_for_team(Globals.team_player)[0]
	_check(wheel.is_open(), "The command wheel opens before changing squads")
	controller.select_and_center_unit(other)
	_check(controller.selected_unit == other and other != unit, "The fixture changes to a different active squad")
	_right_release(wheel.position + wheel.get_option_point(0))
	_check(not bool(feedback.back()["accepted"]) and str(feedback.back()["explanation"]).contains("selection changed"), "Changing squads while the wheel is open cannot redirect its order to another squad: %s" % feedback.back())
	controller.select_and_center_unit(unit)
	unit.in_close_combat = true
	_check(not controller.order_via_option_wheel(destination, WheelOption.Option.STOP) and str(feedback.back()["explanation"]).contains("close combat"), "Close combat restrictions also produce clear rejection feedback")
	unit.in_close_combat = false
	var settings: Control = world.ui.get_node("Control/Settings")
	_right_open(settings.settings_button.get_global_rect().get_center())
	_check(not wheel.is_open(), "Right clicking a HUD control does not open a battlefield command wheel")
	_right_release(settings.settings_button.get_global_rect().get_center())
	for point: Vector2 in [Vector2(1.0, 1.0), Vector2(1151.0, 1.0), Vector2(1.0, 647.0), Vector2(1151.0, 647.0)]:
		wheel.open(point)
		wheel.select_at(wheel.position + wheel.get_option_point(0))
		await _settle()
		_check(Rect2(Vector2.ZERO, world.ui.get_node("Control").size).encloses(wheel.get_wheel_rect()), "The complete wheel and command status stay onscreen near %s" % point)
		wheel.cancel()
	LOSHelper.los_lookup[unit.current_hex] = original_los
	main.queue_free()
	await _settle()
	print("Command interaction checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _reachable_neighbor(unit: Unit, ground: HexagonTileMapLayer) -> Vector2i:
	for cube: Vector3i in ground.cube_neighbors(unit.current_cube):
		var hex: Vector2i = ground.cube_to_map(cube)
		if MatchInteractionHandler.command_restriction(unit.get_parent().get_parent(), hex, WheelOption.Option.MOVE_NORMAL).is_empty():
			return hex
	_check(false, "The fixture supplies a reachable adjacent target")
	return unit.current_hex


func _far_hex(unit: Unit, ground: HexagonTileMapLayer) -> Vector2i:
	for hex: Vector2i in ground.get_used_cells():
		if ground.cube_distance(unit.current_cube, ground.map_to_cube(hex)) > InfluenceUnitQuery.get_unit_range(unit):
			return hex
	_check(false, "The fixture supplies an out-of-range target")
	return unit.current_hex


func _feedback_title(world: Node) -> String:
	return world.ui.get_node("Control/OrderFeedback/Content/Title").text


func _right_open(point: Vector2) -> void:
	_motion(point)
	_mouse(point, MouseButton.MOUSE_BUTTON_RIGHT, true)


func _right_release(point: Vector2) -> void:
	_motion(point)
	_mouse(point, MouseButton.MOUSE_BUTTON_RIGHT, false)


func _motion(point: Vector2) -> void:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	get_viewport().push_input(event, true)


func _mouse(point: Vector2, button: MouseButton, pressed: bool) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	get_viewport().push_input(event, true)


func _on_feedback(accepted: bool, command: String, explanation: String) -> void:
	feedback.append({"accepted": accepted, "command": command, "explanation": explanation})


func _on_map_click(_point: Vector2) -> void:
	map_clicks += 1


func _capture(label: String) -> void:
	await get_tree().create_timer(0.2).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/acl-command-%s.png" % label)


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
