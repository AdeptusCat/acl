extends Node

const UNIT_SCENE: PackedScene = preload("res://scenes/game/units/unit.tscn")
const STACK_SCRIPT: Script = preload("res://scenes/world/overlays/battlefield_stacks.gd")
const COMMAND_SCRIPT: Script = preload("res://scenes/world/overlays/command_connectivity_renderer.gd")

class ControllerProbe extends Node2D:
	var ground_layer: HexagonTileMapLayer
	var selected_unit: Unit
	var previous_selected_hex: Vector2i = Vector2i(-999, -999)
	var selected_hex_index: int = 0
	var end_game_handled: bool = false
	var continuing_after_end: bool = false
	var stacks: BattlefieldStacks
	var map_clicks: int = 0
	signal hex_selected(cell: Vector2i, point: Vector2)
	signal show_unit_details_in_ui(unit: Unit)
	signal hide_unit_details_in_ui

	func _select_unit(unit: Unit) -> void:
		if is_instance_valid(selected_unit):
			selected_unit.deselect()
		selected_unit = unit
		unit.select()

	func _deselect_unit(unit: Unit) -> void:
		if selected_unit == unit:
			unit.deselect()
			selected_unit = null

	func get_selected_units() -> Array[Unit]:
		var members: Array[Unit] = []
		if is_instance_valid(selected_unit):
			members.append(selected_unit)
		return members

	func set_selected_units(members: Array[Unit]) -> void:
		if is_instance_valid(selected_unit):
			_deselect_unit(selected_unit)
		if not members.is_empty():
			_select_unit(members.back())

	func cycle_stack_selection(cell: Vector2i, picked: Unit) -> bool:
		return stacks.cycle_selection(cell, picked)

	func click(point: Vector2) -> void:
		map_clicks += 1
		MatchInteractionHandler.on_mouse_button_left_pressed(self, point)


var checks: int = 0
var failures: int = 0
var zooms: int = 0
var units: Array[Unit] = []
var controller: ControllerProbe
var stacks: BattlefieldStacks
var commands: CommandConnectivityRenderer
var hud: Control
var first: Unit
var second: Unit
var third: Unit
var headquarters: Unit
var single: Unit
var stack_cell: Vector2i = Vector2i(3, 2)
var snapshots: Dictionary[int, Dictionary] = {}


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--render"):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	_run.call_deferred()


func _run() -> void:
	name = "Main"
	get_tree().root.size = Vector2i(1152, 648)
	Globals.team_player = Globals.Team.AXIS
	Debug.enemy_selectable = false
	SessionSettings.showCmdConnectivity = false
	var world: Node2D = Node2D.new()
	world.name = "World"
	add_child(world)
	var audio: AudioPool = AudioPool.new()
	audio.name = "AudioPool"
	world.add_child(audio)
	controller = ControllerProbe.new()
	controller.position = Vector2(37.0, 19.0)
	world.add_child(controller)
	var template: HexagonTileMapLayer = (load("res://scenes/world/maps/layers/ground_tile_map_layer.tscn") as PackedScene).instantiate() as HexagonTileMapLayer
	var ground: HexagonTileMapLayer = HexagonTileMapLayer.new()
	ground.pathfinding_enabled = false
	ground.tile_set = template.tile_set
	template.free()
	ground.position = Vector2(79.0, 53.0)
	ground.z_index = -10
	controller.add_child(ground)
	controller.ground_layer = ground
	var previous_ground: HexagonTileMapLayer = LOSHelper.ground_layer
	LOSHelper.ground_layer = ground
	for x: int in range(10):
		for y: int in range(7):
			ground.set_cell(Vector2i(x, y), 1, Vector2i.ZERO)
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	hud = Control.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var input: Node = (load("res://scenes/game/input/input_manager.tscn") as PackedScene).instantiate()
	add_child(input)
	input.set_battle_input_enabled(true)
	input.mouse_button_left_pressed.connect(controller.click)
	input.zoom_in.connect(func() -> void: zooms += 1)
	first = _unit(stack_cell, 1, Globals.SquadType.Rifle, Vector2(0.0, -16.0))
	second = _unit(stack_cell, 2, Globals.SquadType.MG)
	third = _unit(stack_cell, 3, Globals.SquadType.Rifle, Vector2(0.0, 16.0))
	headquarters = _unit(Vector2i(6, 2), 0, Globals.SquadType.PLATOON_HEADQUARTERS)
	single = _unit(Vector2i(2, 2), 4, Globals.SquadType.Rifle)
	for unit: Unit in [first, second, third, single]:
		unit.command_squad = headquarters
		unit.command_connectivity.runner_chain_to_leader = true
	for unit: Unit in units:
		snapshots[unit.get_instance_id()] = {"transform": unit.global_transform, "hex": unit.current_hex, "cube": unit.current_cube, "ui_transform": unit.ui.get_global_transform()}
	stacks = STACK_SCRIPT.new() as BattlefieldStacks
	controller.add_child(stacks)
	controller.stacks = stacks
	stacks.setup(controller)
	commands = COMMAND_SCRIPT.new() as CommandConnectivityRenderer
	controller.add_child(commands)
	commands.setup()
	commands.set_process(false)
	await _settle()
	_test_preserved_stack()
	_test_arrivals()
	_test_enemy_visibility()
	await _test_pointer_and_selection()
	await _test_outside_hud_click()
	_test_model_positions()
	_test_large_stacks()
	_test_removal_and_cleanup()
	for unit: Unit in units:
		unit.squad_fire.calc.free()
	LOSHelper.ground_layer = previous_ground
	world.free()
	layer.free()
	print("Stacked squad checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _unit(cell: Vector2i, number: int, type: Globals.SquadType, offset: Vector2 = Vector2.ZERO) -> Unit:
	var unit: Unit = UNIT_SCENE.instantiate() as Unit
	unit.squad = number
	unit.platoon = 1
	unit.squad_type = type
	controller.add_child(unit)
	unit.current_hex = cell
	unit.current_cube = controller.ground_layer.map_to_cube(cell)
	unit.global_position = controller.ground_layer.to_global(controller.ground_layer.map_to_local(cell)) + offset
	unit.movement.unit = unit
	unit.action_controller.init(unit, unit.movement, unit.squad_fire, unit.stress_system, unit.ui)
	unit._setup_runtime_soldiers(unit.squad_loadout)
	unit.stress_system.state_changed.connect(unit._on_state_changed)
	unit.ui.update_team_sprite(unit.team, type)
	_freeze(unit)
	unit.add_to_group("units")
	units.append(unit)
	return unit


func _move_to(unit: Unit, cell: Vector2i) -> void:
	unit.goal_hex = cell
	unit.movement.target_position = controller.to_local(controller.ground_layer.to_global(controller.ground_layer.map_to_local(cell)))
	unit.movement.is_moving = true
	unit.movement._process_movement(100.0)


func _test_preserved_stack() -> void:
	_check(hud.get_child_count() == 0 and not stacks.is_processing(), "Stack selection creates no floating panel or continuously refreshed UI")
	_check(Globals.get_units().size() == units.size(), "Stack selection does not create gameplay units")
	for unit: Unit in [first, second, third, single]:
		_check(unit.ui.modulate.a == 1.0 and unit.ui.is_visible_in_tree(), "Every squad counter remains visible")


func _test_arrivals() -> void:
	controller._select_unit(second)
	_move_to(single, stack_cell)
	_check(hud.get_child_count() == 0 and controller.selected_unit == second, "Entering an occupied hex opens no panel and preserves the selected squad")
	_check(single.current_hex == stack_cell and single.current_cube == controller.ground_layer.map_to_cube(stack_cell), "Removing the arrival popup preserves normal movement")
	_move_to(single, Vector2i(2, 2))
	_check(hud.get_child_count() == 0, "Leaving an occupied hex adds no panel")


func _test_enemy_visibility() -> void:
	var enemy: Unit = _unit(stack_cell, 8, Globals.SquadType.Rifle)
	enemy.team = Globals.get_enemy_team(Globals.team_player)
	var hidden: Unit = _unit(stack_cell, 9, Globals.SquadType.Rifle)
	hidden.hide()
	var exited: Unit = _unit(stack_cell, 10, Globals.SquadType.Rifle)
	exited.exited = true
	controller._select_unit(third)
	for expected: Unit in [first, second, third]:
		_check(stacks.cycle_selection(stack_cell) and controller.selected_unit == expected, "Cycling skips enemy, hidden and exited squads")
	_check(not hidden.is_visible_in_tree() and hud.get_child_count() == 0, "Stack selection cannot reveal hidden units or create a panel")
	for unit: Unit in [enemy, hidden, exited]:
		units.erase(unit)
		unit.squad_fire.calc.free()
		unit.free()


func _test_pointer_and_selection() -> void:
	var center: Vector2 = controller.ground_layer.to_global(controller.ground_layer.map_to_local(stack_cell))
	for zoom: float in [0.5, 1.0, 2.0]:
		var canvas: Transform2D = Transform2D.IDENTITY.scaled(Vector2(zoom, zoom))
		canvas.origin = Vector2(350.0, 270.0) - center * zoom
		get_viewport().canvas_transform = canvas
		await _settle()
		if is_instance_valid(controller.selected_unit):
			controller._deselect_unit(controller.selected_unit)
		var point: Vector2 = BattlefieldStacks.counter_rect(second).get_center()
		_click(point)
		await _settle()
		_check(controller.selected_unit == third, "The first stack click selects the front counter at zoom %.1f" % zoom)
		for expected: Unit in [first, second, third]:
			_click(point)
			await _settle()
			commands.refresh(0.0)
			_check(controller.selected_unit == expected, "Repeated clicks reach every squad and wrap at zoom %.1f" % zoom)
			_check(commands.displayed_links == [expected] and commands.highlighted_units.has(headquarters.get_instance_id()), "Each cycle step updates the selected squad's HQ connection")
		_check(hud.get_child_count() == 0, "Clicking a stack never opens a squad panel at zoom %.1f" % zoom)
		_check(commands.counter_rect(third).is_equal_approx(BattlefieldStacks.counter_rect(third)), "Command links retain the counter's original position")
		var single_rect: Rect2 = BattlefieldStacks.counter_rect(single)
		_click(single_rect.position + Vector2(single_rect.size.x * 0.5, 1.0))
		await _settle()
		_check(controller.selected_unit == single, "An outside click selects a different squad immediately")
		if OS.get_cmdline_user_args().has("--render"):
			await _capture("zoom-" + str(zoom))
	get_viewport().canvas_transform = Transform2D.IDENTITY


func _test_outside_hud_click() -> void:
	var button: Button = Button.new()
	button.position = Vector2(12.0, 12.0)
	button.size = Vector2(140.0, 32.0)
	button.text = "HUD control"
	var presses: Array[int] = [0]
	button.pressed.connect(func() -> void: presses[0] += 1)
	hud.add_child(button)
	var before: int = controller.map_clicks
	_click(button.get_global_rect().get_center())
	await _settle()
	_check(presses[0] == 1 and controller.map_clicks == before, "HUD controls retain normal input handling")
	button.free()
	var zoom_before: int = zooms
	_mouse(BattlefieldStacks.counter_rect(second).get_center(), MouseButton.MOUSE_BUTTON_WHEEL_UP, true)
	_mouse(BattlefieldStacks.counter_rect(second).get_center(), MouseButton.MOUSE_BUTTON_WHEEL_UP, false)
	_check(zooms == zoom_before + 1 and hud.get_child_count() == 0, "Wheel input zooms the battlefield without opening a stack panel")


func _test_large_stacks() -> void:
	for index: int in range(8):
		_unit(stack_cell, 5 + index, Globals.SquadType.Rifle)
	controller._deselect_unit(controller.selected_unit)
	var expected: Array[Unit] = [first, second, third]
	for index: int in range(5, units.size()):
		expected.append(units[index])
	for unit: Unit in expected:
		_check(stacks.cycle_selection(stack_cell, first) and controller.selected_unit == unit, "Large stacks retain every squad in formation order")
	_check(stacks.cycle_selection(stack_cell) and controller.selected_unit == first, "Cycling past the last squad wraps to the first")
	_check(hud.get_child_count() == 0, "Large stacks add no floating panel")
	first.ui.show_casualty(1)
	_check(first.ui._casualty_feedback.active and first.ui.modulate.a == 1.0, "Stacked squads retain their own casualty feedback")


func _test_removal_and_cleanup() -> void:
	third.current_hex = Vector2i(7, 4)
	first.alive = false
	first.ui.die()
	controller._select_unit(first)
	_check(stacks.cycle_selection(stack_cell, second) and controller.selected_unit == second, "Cycling skips dead squads and squads that left the hex")
	var doomed: Unit = units.back()
	controller._select_unit(doomed)
	units.erase(doomed)
	doomed.squad_fire.calc.free()
	doomed.free()
	_check(stacks.cycle_selection(stack_cell, second) and controller.selected_unit == second, "Cycling recovers from a freed selected squad without stale references")
	for unit: Unit in units:
		if unit != second:
			unit.current_hex = Vector2i(15 + unit.squad, 15)
	_check(not stacks.cycle_selection(stack_cell) and controller.selected_unit == second, "Single squads retain normal selection behavior")
	controller.end_game_handled = true
	third.current_hex = stack_cell
	_check(not stacks.cycle_selection(stack_cell), "Stack selection stops when the match ends")
	controller.continuing_after_end = true
	_check(stacks.cycle_selection(stack_cell) and controller.selected_unit == third, "Keep Playing restores cycling through surviving stacked squads")
	_check(hud.get_child_count() == 0, "Movement, selection and removal never recreate the squad panel")


func _test_model_positions() -> void:
	for unit: Unit in [first, second, third, headquarters, single]:
		var original: Dictionary = snapshots[unit.get_instance_id()]
		_check(unit.global_transform == original["transform"] and unit.current_hex == original["hex"] and unit.current_cube == original["cube"] and unit.ui.get_global_transform() == original["ui_transform"], "Stack presentation preserves unit transforms, occupied hexes and counter origins")
		_check(not unit.is_moving and not unit.movement.is_moving, "Selecting a stack does not issue movement orders")


func _capture(label: String) -> void:
	await get_tree().process_frame
	# Minimized test windows do not reliably emit frame_post_draw on every driver.
	RenderingServer.force_draw(false)
	var capture: Image = get_viewport().get_texture().get_image()
	_check(capture.save_png("/tmp/acl-stacks-" + label + ".png") == OK, "Capture stack selection %s" % label)


func _settle() -> void:
	for frame: int in range(3):
		await get_tree().process_frame


func _click(point: Vector2) -> void:
	_mouse(point, MouseButton.MOUSE_BUTTON_LEFT, true)
	_mouse(point, MouseButton.MOUSE_BUTTON_LEFT, false)


func _mouse(point: Vector2, button: MouseButton, pressed: bool) -> void:
	_motion(point)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	get_viewport().push_input(event, true)


func _motion(point: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)


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
