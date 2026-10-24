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
	# Native camera smoothing continues even after the fixture freezes scripts.
	controller.camera.position_smoothing_enabled = false
	controller.camera.reset_smoothing()
	controller.camera.force_update_scroll()
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
	_check(wheel.options.size() == 5 and wheel.options[0].option == WheelOption.Option.MOVE_NORMAL and wheel.options[1].option == WheelOption.Option.FIRE_AT and wheel.options[2].option == WheelOption.Option.STOP and wheel.options[3].option == WheelOption.Option.NONE and wheel.options[4].option == WheelOption.Option.ROUT, "Rout joins the wheel while Move stays in the center")
	_check(wheel.get_option_point(0) == Vector2.ZERO and is_zero_approx(wheel.get_option_point(1).x) and wheel.get_option_point(1).y < 0.0 and wheel.get_option_point(2).x < 0.0 and is_zero_approx(wheel.get_option_point(2).y) and is_zero_approx(wheel.get_option_point(3).x) and wheel.get_option_point(3).y > 0.0 and wheel.get_option_point(4).x > 0.0, "Move is centered, with Fire above, Stop left, Cancel below and Rout right")
	for index: int in range(1, wheel.options.size()):
		_motion(wheel.get_global_transform_with_canvas() * wheel.get_option_point(index))
		_check(wheel.selected_label.text.begins_with(WheelOption.COMMAND_NAMES[wheel.options[index].option]), "Pointing at each outer command selects its displayed label")
	_check(wheel.selected_label.text == "Rout · attempt escape" and wheel.restriction_label.text == "Available while pinned.", "Rout remains visible with its restriction for a fresh squad")
	_motion(wheel.get_global_transform_with_canvas() * wheel.get_option_point(0))
	_check(wheel.selected_label.text == "Move", "Pointing at Move displays the command prominently")
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	get_viewport().push_input(escape, true)
	_right_release(wheel.get_global_transform_with_canvas().origin)
	_check(not wheel.is_open() and unit.action_controller.action_order_id == order_before and feedback.is_empty(), "Escape cancels the wheel and releasing right click cannot issue a stale command")
	_right_open(target_point)
	await _settle()
	_motion(wheel.get_global_transform_with_canvas() * wheel.get_option_point(0))
	_mouse(wheel.get_global_transform_with_canvas().origin, MouseButton.MOUSE_BUTTON_LEFT, true)
	_mouse(wheel.get_global_transform_with_canvas().origin, MouseButton.MOUSE_BUTTON_LEFT, false)
	_right_release(wheel.get_global_transform_with_canvas().origin)
	_check(not wheel.is_open() and unit.action_controller.action_order_id == order_before and map_clicks == 0, "Left click cancels without selecting a battlefield hex")
	_right_open(target_point)
	await _settle()
	_right_release(wheel.get_global_transform_with_canvas() * wheel.get_option_point(3))
	_check(unit.action_controller.action_order_id == order_before and feedback.is_empty(), "Releasing in the Cancel sector preserves existing orders")
	_right_open(target_point)
	await _settle()
	_right_release(wheel.get_global_transform_with_canvas() * Vector2(220.0, 0.0))
	_check(unit.action_controller.action_order_id == order_before, "Releasing outside the wheel cancels instead of choosing a sector")
	_right_open(target_point)
	await _settle()
	var move_point: Vector2 = wheel.get_global_transform_with_canvas() * wheel.get_option_point(0)
	_motion(move_point)
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("move")
	_right_release(move_point)
	_check(unit.action_controller.action_order_id > order_before and unit.action_controller.objective_hex == destination, "Releasing Move submits the original target hex through the actual input path (expected %s; selected %s; ordered %s)" % [destination, world.selected_map_hex, unit.action_controller.objective_hex])
	_check(bool(feedback.back()["accepted"]) and _feedback_title(world).contains("Order accepted · Move"), "Accepted movement gets explicit positive feedback")
	_right_open(target_point)
	await _settle()
	_right_release(wheel.get_global_transform_with_canvas() * wheel.get_option_point(2))
	_check(unit.action_controller.action_state == SquadActionController.SquadActionState.NO_ORDER and not unit.movement.is_moving, "Stop clears the pending movement order")
	_check(_feedback_title(world).contains("Order accepted · Stop"), "Stop reports acceptance")
	unit.movement._process_movement(0.1)
	# Exercise a real in-flight return through the command acceptance path.
	controller.order_via_option_wheel(destination, WheelOption.Option.MOVE_NORMAL)
	unit.movement._process_movement(0.1)
	var occupied_hex: Vector2i = unit.current_hex
	_check(controller.order_via_option_wheel(occupied_hex, WheelOption.Option.MOVE_NORMAL), "Move accepts the occupied hex while departing")
	unit.movement._process_movement(100.0)
	_check(unit.position == ground.map_to_local(occupied_hex) and not unit.movement.is_moving, "Moving back to the occupied hex reaches its center")
	controller.order_via_option_wheel(destination, WheelOption.Option.MOVE_NORMAL)
	unit.movement._process_movement(0.1)
	occupied_hex = unit.current_hex
	controller.order_via_option_wheel(destination, WheelOption.Option.STOP)
	_check(unit.movement.is_moving, "Stop preserves movement toward the occupied hex center")
	unit.movement._process_movement(100.0)
	_check(unit.position == ground.map_to_local(occupied_hex) and not unit.movement.is_moving, "Stop finishes at the occupied hex center")
	unit.stress_system._set_state(STATES.MoraleState.PINNED)
	order_before = unit.action_controller.action_order_id
	_right_open(target_point)
	await _settle()
	move_point = wheel.get_global_transform_with_canvas() * wheel.get_option_point(0)
	_motion(move_point)
	_check(wheel.restriction_label.text == "Pinned: use Rout to attempt escape.", "Pinned movement points the player to Rout")
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("pinned")
	var children_before: int = controller.get_child_count()
	_right_release(move_point)
	_check(unit.action_controller.action_order_id == order_before and not bool(feedback.back()["accepted"]), "Pinned movement is rejected without changing orders")
	_check(_feedback_title(world).contains("Order rejected · Move") and controller.get_child_count() <= children_before, "Rejection gets an explicit message and no success glow")
	_right_open(target_point)
	await _settle()
	_motion(wheel.get_global_transform_with_canvas() * wheel.get_option_point(4))
	var rout_position: Vector2 = wheel.get_option_point(4)
	_check(wheel.restriction_label.text.contains("surrender") and wheel.selected_label.get_theme_color("font_color").is_equal_approx(wheel.ROUT_COLOR), "Eligible Rout is amber and explains the failed-escape outcome")
	unit.stress_system._set_state(STATES.MoraleState.CAUTIOUS)
	_check(wheel.restriction_label.text == "Available while pinned." and wheel.get_option_point(4) == rout_position, "Recovery disables Rout immediately without moving it or adding a notification")
	unit.stress_system._set_state(STATES.MoraleState.PINNED)
	_check(wheel.restriction_label.text.contains("surrender"), "Becoming pinned updates the open Rout command immediately")
	if OS.get_cmdline_user_args().has("--capture"):
		await _capture("rout")
	unit.stress_system._set_state(STATES.MoraleState.CAUTIOUS)
	order_before = unit.action_controller.action_order_id
	_right_release(wheel.get_global_transform_with_canvas() * rout_position)
	_check(not bool(feedback.back()["accepted"]) and feedback.back()["explanation"] == "Available while pinned." and unit.action_controller.action_order_id == order_before and unit.stress_system.state == STATES.MoraleState.CAUTIOUS, "Releasing Rout after recovery rejects the attempt without changing the squad")
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
	var mortar_cover: int = LOSHelper.is_sample_point_in_building(ground.map_to_local(destination))
	var mortar_power: float = InfluenceUnitQuery.get_firepower_at_range(unit, controller.distance) * InfluenceUnitQuery.get_unit_effectiveness(unit)
	mortar_power *= 2.0
	var mortar_multiplier: float = SquadFireMath.cover_multiplier_exp(float(mortar_cover))
	if mortar_cover == 1:
		mortar_multiplier = 2.0
	_check(controller.targetCover == mortar_cover and is_equal_approx(controller.firepower, mortar_power * mortar_multiplier) and not hint.detail.text.contains("unknown"), "Blocked indirect-fire previews use the same target terrain cover as mortar impacts")
	LOSHelper.los_lookup[unit.current_hex][destination] = {"target_cover": 5}
	MatchInteractionHandler.refresh_target_preview(controller, ground.map_to_local(destination), target_point)
	_check(controller.targetCover == mortar_cover and is_equal_approx(controller.firepower, mortar_power * mortar_multiplier), "Mortar previews ignore directional wall cover even with clear line of sight")
	unit.squad_type = original_type
	LOSHelper.los_lookup[unit.current_hex][destination] = {"target_cover": 2}
	_test_cover_firepower(world, unit, destination, target_point)
	_test_point_blank_firepower(world, unit, target_point)
	var far_target: Vector2i = _far_hex(unit, ground)
	LOSHelper.los_lookup[unit.current_hex][far_target] = {"target_cover": 1}
	MatchInteractionHandler.refresh_target_preview(controller, ground.map_to_local(far_target), target_point)
	_check(hint.visible and hint.heading.text == "Out of range" and controller.firepower == 0.0, "Out-of-range targets keep a visible preview with zero effective firepower")
	_check(not controller.order_via_option_wheel(far_target, WheelOption.Option.FIRE_AT) and str(feedback.back()["explanation"]).contains("Out of range"), "Fire orders beyond the live weapon ranges are rejected explicitly")
	MatchInteractionHandler.refresh_target_preview(controller, ground.map_to_local(destination), target_point)
	var expected: float = InfluenceUnitQuery.get_firepower_at_range(unit, controller.distance) * InfluenceUnitQuery.get_unit_effectiveness(unit) * 0.4 * 2.0
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
	_right_release(wheel.get_global_transform_with_canvas() * wheel.get_option_point(0))
	_check(not bool(feedback.back()["accepted"]) and str(feedback.back()["explanation"]).contains("selection changed"), "Changing squads while the wheel is open cannot redirect its order to another squad: %s" % feedback.back())
	controller.select_and_center_unit(unit)
	unit.in_close_combat = true
	_check(not controller.order_via_option_wheel(destination, WheelOption.Option.STOP) and str(feedback.back()["explanation"]).contains("close combat"), "Close combat restrictions also produce clear rejection feedback")
	unit.in_close_combat = false
	var settings: Control = world.ui.get_node("Control/Settings")
	_right_open(_screen_rect(settings.settings_button).get_center())
	_check(not wheel.is_open(), "Right clicking a HUD control does not open a battlefield command wheel")
	_right_release(_screen_rect(settings.settings_button).get_center())
	for point: Vector2 in [Vector2(1.0, 1.0), Vector2(1151.0, 1.0), Vector2(1.0, 647.0), Vector2(1151.0, 647.0), Vector2(576.0, 1.0), Vector2(576.0, 647.0), Vector2(1.0, 324.0), Vector2(1151.0, 324.0)]:
		wheel.open(point)
		_check(wheel.get_global_transform_with_canvas().origin.is_equal_approx(point), "The wheel opens centered on the original pointer near %s" % point)
		await _settle()
		_check(wheel.get_global_transform_with_canvas().origin.is_equal_approx(point), "Deferred status layout preserves the pointer anchor near %s" % point)
		_check(Rect2(Vector2.ZERO, world.ui.get_node("Control").size).encloses(wheel.status_panel.get_global_rect()), "The command status stays onscreen near %s" % point)
		wheel.select_at(point)
		_check(wheel.close() == WheelOption.Option.MOVE_NORMAL, "Releasing at the original pointer selects Move near %s" % point)
	LOSHelper.los_lookup[unit.current_hex] = original_los
	await _check_keep_playing(world, unit)
	await _check_rout(world, unit, other)
	main.queue_free()
	await _settle()
	print("Command interaction checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _check_keep_playing(world: Node, unit: Unit) -> void:
	var controller: Node2D = world.game_controller
	var ground: HexagonTileMapLayer = world.ground_layer
	var scenario: Scenario = Globals.scenario_chosen
	var original_conditions: Array[VictoryCondition] = scenario.victory_conditions.duplicate()
	var original_collections: Dictionary[Globals.Team, VictoryConditionCollection] = Globals.victory_conditions
	var wheel: Control = world.ui.selection_wheel_alt
	_check(not controller.continue_after_end(), "Keep Playing cannot change an unfinished mission")
	for early_defeat: bool in [false, true]:
		controller.end_game_handled = false
		controller.continuing_after_end = false
		controller.timer_running = true
		controller.time_left_seconds = 0.0
		if early_defeat:
			controller.time_left_seconds = 120.0
		var major: ExitUnitsCondition = ExitUnitsCondition.new()
		major.team = Globals.team_player
		major.required_unit_count = 999
		major.state = ExitUnitsState.new()
		major.state.exit_hexes.assign([unit.current_hex])
		var minor: ExitUnitsCondition = major.duplicate() as ExitUnitsCondition
		minor.outcome_level = VictoryCondition.OutcomeLevel.MINOR
		minor.state = ExitUnitsState.new()
		minor.state.exit_hexes.assign([unit.current_hex])
		scenario.victory_conditions.assign([major, minor])
		Globals.victory_conditions = {Globals.Team.AXIS: VictoryConditionCollection.new(), Globals.Team.ALLIES: VictoryConditionCollection.new()}
		Globals.victory_conditions[Globals.team_player].victory_conditions.assign([major, minor])
		controller._on_win_condition_timer_timeout()
		await _settle()
		_check(controller.end_game_handled and world.result_screen.visible and not world.input_manager._battle_input_enabled, "Timeout and impossible objectives display results and suspend battlefield input")
		if early_defeat:
			_check(world.result_screen.result_label.text == "Defeat" and controller.time_left_seconds == 120.0, "Impossible objectives end the actual map before its deadline")
		_check(not controller.order_via_option_wheel(unit.current_hex, WheelOption.Option.STOP), "Orders stay blocked until Keep Playing is chosen")
		var save_path: String = "user://matches/%s.tres" % scenario.get_save_id()
		var recorded_result: String = FileAccess.get_file_as_string(save_path)
		var recorded_time: float = controller.time_left_seconds
		world.result_screen.get_node("Control/CenterContainer/PanelContainer/Content/Actions/KeepPlaying").pressed.emit()
		await _settle()
		_check(not world.result_screen.visible and controller.continuing_after_end and world.input_manager._battle_input_enabled, "The actual Keep Playing button restores battlefield input after either result")
		controller._deselect_unit(controller.selected_unit)
		controller.camera.position = unit.position
		controller.camera.force_update_scroll()
		await _settle()
		var counter_point: Vector2 = BattlefieldStacks.counter_rect(unit).get_center()
		var clicks_before: int = map_clicks
		_motion(counter_point)
		_mouse(counter_point, MouseButton.MOUSE_BUTTON_LEFT, true)
		_mouse(counter_point, MouseButton.MOUSE_BUTTON_LEFT, false)
		_check(map_clicks == clicks_before + 1 and controller.selected_unit == unit, "Battlefield clicks select a surviving squad again after Keep Playing")
		var destination: Vector2i = _reachable_neighbor(unit, ground)
		major.state.exit_hexes.assign([destination])
		minor.state.exit_hexes.assign([destination])
		var target_point: Vector2 = controller.get_global_transform_with_canvas() * ground.map_to_local(destination)
		_motion(target_point)
		await _settle()
		MatchInteractionHandler.refresh_target_preview(controller, ground.map_to_local(destination), target_point)
		_check(world.ui.target_cover_distance.visible, "Target previews resume after Keep Playing")
		var order_before: int = unit.action_controller.action_order_id
		_right_open(target_point)
		await _settle()
		_check(wheel.is_open(), "The actual command wheel reopens in a completed map")
		_right_release(wheel.get_global_transform_with_canvas() * wheel.get_option_point(0))
		_check(unit.action_controller.action_order_id > order_before and unit.action_controller.objective_hex == destination, "Move orders reach the surviving squad after Keep Playing")
		unit.movement._process_movement(100.0)
		_check(unit.current_hex == destination and unit.position == ground.map_to_local(destination), "The squad completes its movement after the map has ended")
		var fire_target: Vector2i = _reachable_neighbor(unit, ground)
		LOSHelper.los_lookup[unit.current_hex][fire_target] = {"target_cover": 0}
		_check(controller.order_via_option_wheel(fire_target, WheelOption.Option.FIRE_AT) and unit.squad_fire.has_target_hex, "Fire orders remain available after Keep Playing")
		_check(controller.order_via_option_wheel(destination, WheelOption.Option.STOP) and not unit.squad_fire.has_target_hex, "Stop still clears orders after Keep Playing")
		controller._process(1.0)
		controller._on_win_condition_timer_timeout()
		_check(controller.end_game_handled and not controller.timer_running and controller.time_left_seconds == recorded_time and not world.result_screen.visible, "Continuing cannot restart the clock or display another result")
		_check(major.state.units_exited.is_empty() and minor.state.units_exited.is_empty() and unit.is_active(), "Moving onto an exit after the result does not alter scored objectives or retire the squad")
		_check(FileAccess.get_file_as_string(save_path) == recorded_result, "Continuing leaves the saved battle result unchanged")
	scenario.victory_conditions = original_conditions
	Globals.victory_conditions = original_collections


func _test_cover_firepower(world: Node, unit: Unit, destination: Vector2i, target_point: Vector2) -> void:
	var controller: Node2D = world.game_controller
	var ground: HexagonTileMapLayer = world.ground_layer
	var distance: int = ground.cube_distance(unit.current_cube, ground.map_to_cube(destination))
	var raw_power: float = InfluenceUnitQuery.get_firepower_at_range(unit, distance) * InfluenceUnitQuery.get_unit_effectiveness(unit) * 2.0
	_check(raw_power > 0.0, "The cover preview fixture has usable firepower")
	var multipliers: Array[float] = [1.5, 0.5, 0.4, 0.3, 0.1, 0.05, 0.001]
	var previous_power: float = INF
	for cover: int in range(multipliers.size()):
		LOSHelper.los_lookup[unit.current_hex][destination] = {"target_cover": cover}
		MatchInteractionHandler.refresh_target_preview(controller, ground.map_to_local(destination), target_point)
		var power: float = raw_power * multipliers[cover]
		_check(is_equal_approx(controller.firepower, power) and controller.firepower < previous_power and world.ui.target_cover_distance.extra.text == "Effective firepower: %s" % String.num(power, 2), "Cover %d reduces displayed firepower using the combat multiplier" % cover)
		previous_power = controller.firepower
	LOSHelper.los_lookup[unit.current_hex][destination] = {"target_cover": 2}
	_check(SquadFireMath.hit_cover_multiplier(1.0, true) == 2.0 and SquadFireMath.hit_cover_multiplier(2.0, true) == 0.4, "Mortar terrain exceptions share the hit resolver's cover calculation")


func _test_point_blank_firepower(world: Node, unit: Unit, target_point: Vector2) -> void:
	var controller: Node2D = world.game_controller
	var ground: HexagonTileMapLayer = world.ground_layer
	for distance: int in [1, 2]:
		var found: bool = false
		for hex: Vector2i in ground.get_used_cells():
			if ground.cube_distance(unit.current_cube, ground.map_to_cube(hex)) != distance:
				continue
			LOSHelper.los_lookup[unit.current_hex][hex] = {"target_cover": 2}
			var expected: float = InfluenceUnitQuery.get_firepower_at_range(unit, distance) * InfluenceUnitQuery.get_unit_effectiveness(unit) * 0.4
			if distance == 1:
				expected *= 2.0
			MatchInteractionHandler.refresh_target_preview(controller, ground.map_to_local(hex), target_point)
			_check(controller.distance == distance and is_equal_approx(controller.firepower, expected) and world.ui.target_cover_distance.extra.text == "Effective firepower: %s" % String.num(expected, 2), "The displayed firepower applies the point-blank bonus only at one hex: distance %d" % distance)
			found = true
			break
		_check(found, "The range-preview fixture includes distance %d" % distance)
	_check(SquadFireMath.point_blank_hit_multiplier(0) == 1.0 and SquadFireMath.point_blank_hit_multiplier(1) == 2.0 and SquadFireMath.point_blank_hit_multiplier(2) == 1.0, "The shared combat multiplier doubles exactly one-hex fire, without extending the bonus to the same hex or longer ranges")


func _check_rout(world: Node, unit: Unit, other: Unit) -> void:
	var controller: Node2D = world.game_controller
	var wheel: Control = world.ui.selection_wheel_alt
	controller.select_and_center_unit(unit)
	unit.stress_system._set_state(STATES.MoraleState.PINNED)
	unit.in_close_combat = true
	_check(not unit.can_rout() and not controller.order_via_option_wheel(unit.current_hex, WheelOption.Option.ROUT) and str(feedback.back()["explanation"]).contains("close combat"), "Pinned squads in close combat cannot use Rout")
	unit.in_close_combat = false
	_check(unit.can_rout() and MatchInteractionHandler.command_restriction(controller, Vector2i(-999, -999), WheelOption.Option.ROUT).is_empty(), "Rout does not require a target hex or high stress")
	var point: Vector2 = controller.get_global_transform_with_canvas() * world.ground_layer.map_to_local(unit.current_hex)
	_right_open(point)
	await _settle()
	_check(wheel.is_open(), "The pinned squad can open its command wheel")
	_right_release(wheel.get_global_transform_with_canvas() * wheel.get_option_point(4))
	_check(bool(feedback.back()["accepted"]) and _feedback_title(world).contains("Order accepted · Rout") and unit.stress_system.state == STATES.MoraleState.PANIC and unit.movement.retreating, "The wheel starts the existing uncontrolled retreat and reports acceptance")
	_check(not unit.can_rout() and not unit.request_rout(), "A squad already routing cannot start another rout")
	controller.select_and_center_unit(other)
	other.stress_system._set_state(STATES.MoraleState.PINNED)
	# Isolate the squad's hex so the existing retreat search has no legal exit.
	var ground: HexagonTileMapLayer = world.ground_layer
	var blocked_cells: Dictionary[Vector2i, Vector4i] = {}
	for cube: Vector3i in ground.cube_neighbors(other.current_cube):
		var hex: Vector2i = ground.cube_to_map(cube)
		var atlas: Vector2i = ground.get_cell_atlas_coords(hex)
		blocked_cells[hex] = Vector4i(ground.get_cell_source_id(hex), atlas.x, atlas.y, ground.get_cell_alternative_tile(hex))
		ground.erase_cell(hex)
	world.ui.unit_details._on_rout_pressed()
	_check(other.surrendered and not other.can_rout(), "The detail button shares the same rout action and a trapped squad still surrenders")
	_check(not controller.order_via_option_wheel(other.current_hex, WheelOption.Option.ROUT) and str(feedback.back()["explanation"]).contains("surrendered"), "Surrendered squads reject further Rout orders")
	for hex: Vector2i in blocked_cells:
		var cell: Vector4i = blocked_cells[hex]
		ground.set_cell(hex, cell.x, Vector2i(cell.y, cell.z), cell.w)


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


func _screen_rect(control: Control) -> Rect2:
	return control.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, control.size)
