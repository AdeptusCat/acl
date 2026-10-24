extends Node

const UI_SCENE: PackedScene = preload("res://scenes/game/units/presentation/unit_battlefield_view.tscn")
const UNIT_SCENE: PackedScene = preload("res://scenes/game/units/unit.tscn")

class PreviewHudProbe extends Node:
	var hide_calls: int = 0

	func hide_target_hex_cover_distance() -> void:
		hide_calls += 1


class PreviewWorldProbe extends Node2D:
	var ui: PreviewHudProbe


class ControllerProbe extends Node2D:
	var ground_layer: HexagonTileMapLayer
	var selected_unit: Unit
	var previous_selected_hex: Vector2i = Vector2i(-999, -999)
	var selected_hex_index: int = 0
	var end_game_handled: bool = false
	signal hex_selected(cell: Vector2i, point: Vector2)
	signal show_unit_details_in_ui(unit: Unit)
	signal hide_unit_details_in_ui
	signal mouse_event_position_changed(point: Vector2)

	func _select_unit(unit: Unit) -> void:
		if is_instance_valid(selected_unit):
			selected_unit.deselect()
		selected_unit = unit
		unit.select()

	func _deselect_unit(unit: Unit) -> void:
		if selected_unit == unit:
			unit.deselect()
			selected_unit = null

	func click(point: Vector2) -> void:
		MatchInteractionHandler.on_mouse_button_left_pressed(self, point)


var checks: int = 0
var failures: int = 0
var map_clicks: int = 0
var zooms: int = 0
var right_clicks: int = 0
var hud_clicks: int = 0
var controller: ControllerProbe
var units: Array[Unit] = []


func _ready() -> void:
	if OS.get_cmdline_user_args().has("--render"):
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	_run.call_deferred()


func _run() -> void:
	get_tree().root.size = Vector2i(1152, 648)
	var world: Node = Node.new()
	world.name = "World"
	add_child(world)
	var audio: AudioPool = AudioPool.new()
	audio.name = "AudioPool"
	world.add_child(audio)
	var input: Node = (load("res://scenes/game/input/input_manager.tscn") as PackedScene).instantiate()
	add_child(input)
	input.set_battle_input_enabled(true)
	input.mouse_button_left_pressed.connect(func(_point: Vector2) -> void: map_clicks += 1)
	input.zoom_in.connect(func() -> void: zooms += 1)
	input.right_button_pressed.connect(func() -> void: right_clicks += 1)
	_test_unavailable_map()
	await _test_passive_controls()
	_test_stack_selection()
	await _test_pointer_stack_input(input)
	for unit: Unit in units:
		unit.squad_fire.calc.free()
		unit.free()
	units.clear()
	controller.free()
	print("Battlefield selection checks: ", checks, "; failures: ", failures)
	get_tree().quit(failures)


func _test_unavailable_map() -> void:
	var world: PreviewWorldProbe = PreviewWorldProbe.new()
	world.ui = PreviewHudProbe.new()
	world.add_child(world.ui)
	var pending: ControllerProbe = ControllerProbe.new()
	world.add_child(pending)
	add_child(world)
	var motions: Array[Vector2] = []
	var clicks: Array[Vector2i] = []
	pending.mouse_event_position_changed.connect(func(point: Vector2) -> void: motions.append(point))
	pending.hex_selected.connect(func(cell: Vector2i, _point: Vector2) -> void: clicks.append(cell))
	LOSHelper.los_lines.append({})
	MatchInteractionHandler.handle_mouse_event_position_changed(pending, Vector2(10.0, 20.0))
	pending.click(Vector2(10.0, 20.0))
	_check(world.ui.hide_calls == 1 and LOSHelper.los_lines.is_empty(), "Mouse movement before map assignment clears targeting feedback without accessing a map")
	_check(clicks.is_empty() and motions == [Vector2(10.0, 20.0)], "Before setup, clicks are ignored while mouse-position notifications continue")
	var ground: HexagonTileMapLayer = HexagonTileMapLayer.new()
	ground.tile_set = TileSet.new()
	ground.tile_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	ground.tile_set.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL
	ground.tile_set.tile_size = Vector2i(128, 128)
	ground.pathfinding_enabled = false
	pending.add_child(ground)
	pending.ground_layer = ground
	ground.free()
	# A selected squad can remain referenced while a map is being removed.
	var selected: Unit = Unit.new()
	pending.selected_unit = selected
	LOSHelper.los_lines.append({})
	MatchInteractionHandler.handle_mouse_event_position_changed(pending, Vector2(30.0, 40.0))
	pending.click(Vector2(30.0, 40.0))
	_check(world.ui.hide_calls == 2 and LOSHelper.los_lines.is_empty(), "Mouse movement after map deletion clears stale targeting feedback")
	MatchInteractionHandler.refresh_target_preview(pending, Vector2.ZERO, Vector2.ZERO)
	_check(world.ui.hide_calls == 3, "Direct targeting-preview refresh also handles a freed map")
	_check(clicks.is_empty() and motions.size() == 2 and pending.selected_unit == selected, "Map cleanup cannot interpret clicks or change selection through an invalid layer")
	selected.free()
	world.free()


func _test_passive_controls() -> void:
	var ui: UnitUi = UI_SCENE.instantiate() as UnitUi
	ui.position = Vector2(350.0, 200.0)
	ui.scale = Vector2(2.0, 2.0)
	add_child(ui)
	ui.set_cover(3)
	await get_tree().process_frame
	await get_tree().process_frame
	var cover: Control = ui.cover_container.get_child(0) as Control
	var cover_point: Vector2 = cover.get_global_transform_with_canvas() * (cover.size * 0.5)
	_check_pointer_passes(cover_point, "Cover icons")
	ui.die()
	await get_tree().process_frame
	await get_tree().process_frame
	_check_pointer_passes(ui.dead.get_global_transform_with_canvas() * (ui.dead.size * 0.5), "Corpse images")
	ui.show_casualty(1)
	_check_pointer_passes(ui.get_global_transform_with_canvas() * Vector2(32.0, -12.0), "Casualty badges")
	_check_pointer_passes(ui.get_global_transform_with_canvas() * Vector2(32.0, 73.0), "State ribbons")
	ui.free()
	var button: Button = Button.new()
	button.position = Vector2(40.0, 40.0)
	button.size = Vector2(120.0, 36.0)
	button.text = "HUD control"
	button.pressed.connect(func() -> void: hud_clicks += 1)
	add_child(button)
	await get_tree().process_frame
	var before: int = map_clicks
	_mouse(button.position + button.size * 0.5, MouseButton.MOUSE_BUTTON_LEFT, true)
	_mouse(button.position + button.size * 0.5, MouseButton.MOUSE_BUTTON_LEFT, false)
	_check(hud_clicks == 1 and map_clicks == before, "Interactive HUD controls still consume clicks")
	button.free()


func _check_pointer_passes(point: Vector2, label: String) -> void:
	var clicks_before: int = map_clicks
	var zooms_before: int = zooms
	var right_before: int = right_clicks
	_mouse(point, MouseButton.MOUSE_BUTTON_LEFT, true)
	_mouse(point, MouseButton.MOUSE_BUTTON_LEFT, false)
	_mouse(point, MouseButton.MOUSE_BUTTON_RIGHT, true)
	_mouse(point, MouseButton.MOUSE_BUTTON_RIGHT, false)
	_mouse(point, MouseButton.MOUSE_BUTTON_WHEEL_UP, true)
	_mouse(point, MouseButton.MOUSE_BUTTON_WHEEL_UP, false)
	_check(map_clicks == clicks_before + 1, label + " pass left clicks to the battlefield")
	_check(right_clicks == right_before + 1, label + " pass right clicks to the battlefield")
	_check(zooms == zooms_before + 1, label + " do not block map zoom")
	_check(get_viewport().gui_get_hovered_control() == null, label + " do not masquerade as HUD controls and block commands or targeting previews")


func _test_stack_selection() -> void:
	var ground: HexagonTileMapLayer = HexagonTileMapLayer.new()
	ground.tile_set = TileSet.new()
	ground.tile_set.tile_shape = TileSet.TILE_SHAPE_HEXAGON
	ground.tile_set.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_VERTICAL
	ground.tile_set.tile_size = Vector2i(128, 128)
	ground.pathfinding_enabled = false
	controller = ControllerProbe.new()
	add_child(controller)
	controller.add_child(ground)
	controller.ground_layer = ground
	Globals.team_player = Globals.Team.ALLIES
	Debug.enemy_selectable = false
	var cell: Vector2i = Vector2i(3, 2)
	var enemy: Unit = _unit(Globals.Team.AXIS, cell)
	var first: Unit = _unit(Globals.Team.ALLIES, cell)
	var second: Unit = _unit(Globals.Team.ALLIES, cell)
	var point: Vector2 = ground.get_global_transform_with_canvas() * ground.map_to_local(cell)
	controller.click(point)
	_check(controller.selected_unit == first or controller.selected_unit == second, "A mixed stack selects a friendly squad on the first click")
	var previous: Unit = controller.selected_unit
	controller.click(point)
	_check(controller.selected_unit != null and controller.selected_unit != previous, "Cycling a mixed stack skips non-selectable enemies")
	previous = controller.selected_unit
	controller.click(point)
	_check(controller.selected_unit != null and controller.selected_unit != previous, "Every stack click advances to a selectable squad")
	enemy.hide()
	Debug.enemy_selectable = true
	for click: int in range(4):
		controller.click(point)
		_check(controller.selected_unit != null and controller.selected_unit != enemy, "Hidden enemies are excluded even when debug selection is enabled")
	Debug.enemy_selectable = false
	enemy.show()
	first.current_hex = Vector2i(5, 2)
	first.position = ground.map_to_local(first.current_hex)
	second.current_hex = first.current_hex
	second.position = first.position + Vector2(0.0, -60.0)
	second.z_index = 2
	var edge_point: Vector2 = second.ui.sprite_node.get_global_transform_with_canvas() * Vector2(32.0, 8.0)
	_check(ground.local_to_map(ground.get_global_transform_with_canvas().affine_inverse() * edge_point) != second.current_hex, "The fixture has a drawn counter outside its occupied hex")
	controller.previous_selected_hex = Vector2i(-999, -999)
	controller.selected_unit = null
	controller.click(edge_point)
	_check(controller.selected_unit == first or controller.selected_unit == second, "Clicking an offset counter selects its actual stack")
	ground.position = Vector2(179.0, 143.0)
	first.current_hex = Vector2i(2, 1)
	second.hide()
	first.hide()
	enemy.hide()
	# Ground clicks use the layer's transform even when no sprite is under the pointer.
	var clicked: Array[Vector2i] = []
	controller.hex_selected.connect(func(hex: Vector2i, _point: Vector2) -> void: clicked.append(hex))
	point = ground.get_global_transform_with_canvas() * ground.map_to_local(Vector2i(2, 2))
	controller.click(point)
	_check(clicked.back() == Vector2i(2, 2), "Hex picking uses the ground layer's transform")


func _unit(team: Globals.Team, cell: Vector2i) -> Unit:
	var unit: Unit = UNIT_SCENE.instantiate() as Unit
	controller.add_child(unit)
	unit.team = team
	unit.current_hex = cell
	unit.position = controller.ground_layer.map_to_local(cell)
	unit.set_process(false)
	for child: Node in unit.get_children():
		child.set_process(false)
		child.set_physics_process(false)
		if child is Timer:
			(child as Timer).stop()
	unit.add_to_group("units")
	units.append(unit)
	return unit


func _test_pointer_stack_input(input: Node) -> void:
	input.mouse_button_left_pressed.connect(controller.click)
	var original_canvas: Transform2D = get_viewport().canvas_transform
	var ground: HexagonTileMapLayer = controller.ground_layer
	controller.position = Vector2(37.0, 19.0)
	ground.position = Vector2(79.0, 53.0)
	var cell: Vector2i = Vector2i(3, 2)
	var center: Vector2 = ground.to_global(ground.map_to_local(cell))
	for index: int in range(units.size()):
		var unit: Unit = units[index]
		unit.current_hex = cell
		unit.global_position = center + Vector2(0.0, -16.0 * float(index))
		unit.z_index = index
		unit.show()
	units[1].ui.set_cover(3)
	for zoom: float in [0.5, 1.0, 2.0]:
		var canvas: Transform2D = Transform2D.IDENTITY.scaled(Vector2(zoom, zoom))
		canvas.origin = Vector2(420.0, 270.0) - center * zoom
		get_viewport().canvas_transform = canvas
		await get_tree().process_frame
		await get_tree().process_frame
		controller.previous_selected_hex = Vector2i(-999, -999)
		if controller.selected_unit != null:
			controller._deselect_unit(controller.selected_unit)
		var point: Vector2 = units[2].ui.sprite_node.get_global_transform_with_canvas() * Vector2(32.0, 20.0)
		_mouse(point, MouseButton.MOUSE_BUTTON_LEFT, true)
		_mouse(point, MouseButton.MOUSE_BUTTON_LEFT, false)
		_check(controller.selected_unit == units[2], "Actual pointer input selects the front counter after zoom and pan: " + str(zoom))
		_mouse(point, MouseButton.MOUSE_BUTTON_LEFT, true)
		_mouse(point, MouseButton.MOUSE_BUTTON_LEFT, false)
		_check(controller.selected_unit == units[1], "A repeated pointer click cycles to the next friendly squad: " + str(zoom))
		_mouse(point, MouseButton.MOUSE_BUTTON_LEFT, true)
		_mouse(point, MouseButton.MOUSE_BUTTON_LEFT, false)
		_check(controller.selected_unit == units[2], "Actual stack cycling has no enemy-induced dead click: " + str(zoom))
	# A corpse drawn over a living unit must neither intercept input nor enter the cycle.
	units[2].alive = false
	units[2].ui.die()
	await get_tree().process_frame
	var corpse_point: Vector2 = units[2].ui.dead.get_global_transform_with_canvas() * (units[2].ui.dead.size * 0.5)
	controller.previous_selected_hex = Vector2i(-999, -999)
	_mouse(corpse_point, MouseButton.MOUSE_BUTTON_LEFT, true)
	_mouse(corpse_point, MouseButton.MOUSE_BUTTON_LEFT, false)
	_check(controller.selected_unit == units[1], "Clicks through an overlapping corpse still select the living squad")
	_check(get_viewport().gui_get_hovered_control() == null, "A corpse over a stack cannot block the command wheel")
	var hidden_details: Array[int] = [0]
	var shown_details: Array[Unit] = []
	controller.hide_unit_details_in_ui.connect(func() -> void: hidden_details[0] += 1)
	controller.show_unit_details_in_ui.connect(func(unit: Unit) -> void: shown_details.append(unit))
	for click: int in range(3):
		_mouse(corpse_point, MouseButton.MOUSE_BUTTON_LEFT, true)
		_mouse(corpse_point, MouseButton.MOUSE_BUTTON_LEFT, false)
		_check(controller.selected_unit == units[1] and units[1].selected, "Repeated pointer clicks preserve the only living squad's selection")
	_check(hidden_details[0] == 0 and shown_details == [units[1], units[1], units[1]], "Repeated selection keeps squad details visible")
	get_viewport().canvas_transform = original_canvas


func _mouse(point: Vector2, button: MouseButton, pressed: bool) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	get_viewport().push_input(motion, true)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	get_viewport().push_input(event, true)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
