@tool
extends SceneTree

const SCENE: String = "res://tests/editor/hex_edge_brush_fixture.tscn"

var checks: int = 0
var failures: int = 0
var plugin: EditorPlugin
var layer: WallTileMapLayer
var viewport: SubViewport
var history: UndoRedo


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	while EditorInterface.get_resource_filesystem().is_scanning():
		await process_frame
	EditorInterface.open_scene_from_path(SCENE)
	var scene: Node
	for frame: int in range(300):
		await process_frame
		scene = EditorInterface.get_edited_scene_root()
		if scene != null and scene.scene_file_path == SCENE:
			layer = scene.get_node("OffsetParent/WallTileMapLayer") as WallTileMapLayer
			break
	if layer == null:
		push_error("Editor did not open the edge-brush fixture")
		quit(1)
		return
	var script: Script = load("res://addons/hex_edge_barriers/plugin.gd") as Script
	plugin = script.new() as EditorPlugin
	root.add_child(plugin)
	plugin._edit(layer)
	plugin._make_visible(true)
	plugin._toggle_tool(true)
	viewport = EditorInterface.get_editor_viewport_2d()
	var original_view: Transform2D = viewport.global_canvas_transform
	var parent: Node2D = layer.get_parent() as Node2D
	var transforms: Array[Transform2D] = [Transform2D.IDENTITY, Transform2D(0.37, Vector2(1.3, 0.8), 0.08, Vector2(240, -150))]
	var zooms: Array[float] = [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 4.0]
	var pans: Array[Vector2] = [Vector2.ZERO, Vector2(320, -240), Vector2(-2300, -1700)]
	var anchors: Array[Vector2i] = [Vector2i(4, 4), Vector2i(25, 16), Vector2i(-3, -4)]
	for transform: Transform2D in transforms:
		parent.transform = transform
		for zoom: float in zooms:
			for pan: Vector2 in pans:
				viewport.global_canvas_transform = Transform2D(0.0, Vector2(zoom, zoom), 0.0, pan)
				# Use the native editor view independently of the brush conversion.
				var screen: Transform2D = viewport.global_canvas_transform * layer.get_canvas_transform() * layer.get_global_transform()
				for anchor: Vector2i in anchors:
					for side: int in range(6):
						_test_click(anchor, side, screen)
				_test_drag(screen)
	_test_navigation()
	viewport.global_canvas_transform = original_view
	layer.clear()
	plugin.free()
	print("Editor hex-edge brush checks: ", checks, "; failures: ", failures)
	quit(failures)


func _test_click(anchor: Vector2i, side: int, screen: Transform2D) -> void:
	layer.clear()
	var midpoint: Vector2 = layer.map_to_local(anchor) + (ConnectedWalls.VERTICES[side] + ConnectedWalls.VERTICES[(side + 1) % 6]) * 0.5
	var edge: Vector3i = plugin._closest_edge(midpoint)
	var owner: Vector2i = Vector2i(edge.x, edge.y)
	var point: Vector2 = screen * midpoint
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point
	plugin._forward_canvas_gui_input(motion)
	_check(plugin._hover == edge, "Hover selects the visible hex edge after zoom/pan")
	var actual: Transform2D = plugin._editor_transform()
	_check((actual * midpoint).is_equal_approx(point), "Overlay and input use the same visible edge, including ancestor transforms")
	_click(point, MOUSE_BUTTON_LEFT)
	_check(layer.get_edge_mask(owner) == (1 << edge.z) and layer.get_used_cells().size() == 1, "A click paints only the edge beneath the pointer")
	var manager: EditorUndoRedoManager = plugin.get_undo_redo()
	history = manager.get_history_undo_redo(manager.get_object_history_id(layer))
	_check(history.undo() and layer.get_used_cells().is_empty(), "Editor undo removes the zoomed/panned stroke")
	_check(history.redo() and layer.get_edge_mask(owner) == (1 << edge.z), "Editor redo restores the same map edge")
	_click(point, MOUSE_BUTTON_RIGHT)
	_check(layer.get_used_cells().is_empty(), "Right-click erases the edge beneath the pointer")
	layer.clear()


func _test_drag(screen: Transform2D) -> void:
	layer.clear()
	var start: Vector2 = layer.map_to_local(Vector2i(8, 8)) + Vector2(0, -64)
	var end: Vector2 = layer.map_to_local(Vector2i(10, 8)) + Vector2(0, -64)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = screen * start
	event.pressed = true
	plugin._forward_canvas_gui_input(event)
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = screen * end
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	plugin._forward_canvas_gui_input(motion)
	event.position = motion.position
	event.pressed = false
	plugin._forward_canvas_gui_input(event)
	for point: Vector2 in [start, end]:
		var edge: Vector3i = plugin._closest_edge(point)
		_check((layer.get_edge_mask(Vector2i(edge.x, edge.y)) & (1 << edge.z)) != 0, "Dragging reaches the intended edges at every zoom and pan")
	_check(layer.get_used_cells().size() > 1, "Drag interpolation paints the intervening borders")
	layer.clear()


func _test_navigation() -> void:
	var screen: Transform2D = viewport.global_canvas_transform * layer.get_canvas_transform() * layer.get_global_transform()
	var point: Vector2 = screen * (layer.map_to_local(Vector2i(4, 4)) + Vector2(0, -64))
	for button: MouseButton in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		layer.clear()
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.position = point
		event.button_index = button
		event.pressed = true
		_check(not plugin._forward_canvas_gui_input(event), "Viewport navigation buttons reach the editor")
		event.pressed = false
		_check(not plugin._forward_canvas_gui_input(event), "Viewport navigation releases reach the editor")
		_check(layer.get_used_cells().is_empty(), "Navigation buttons do not paint")
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = point + Vector2(120, 60)
	motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	_check(not plugin._forward_canvas_gui_input(motion) and layer.get_used_cells().is_empty(), "Middle-button drag pans without painting")
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.position = point
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.pressed = true
	_check(not plugin._forward_canvas_gui_input(mouse), "Space-left drag is reserved for viewport panning")
	var release: InputEventKey = InputEventKey.new()
	release.keycode = KEY_SPACE
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	mouse.pressed = false
	_check(not plugin._forward_canvas_gui_input(mouse) and layer.get_used_cells().is_empty(), "Releasing a pan gesture does not paint or consume the release")
	for gesture: InputEventGesture in [InputEventPanGesture.new(), InputEventMagnifyGesture.new()]:
		mouse.pressed = true
		plugin._forward_canvas_gui_input(mouse)
		var before: PackedByteArray = layer.tile_map_data
		_check(not plugin._forward_canvas_gui_input(gesture), "Trackpad gestures reach the viewport")
		_check(not plugin._dragging, "Navigation ends the current paint stroke")
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		plugin._forward_canvas_gui_input(motion)
		_check(layer.tile_map_data == before, "Panning after a stroke does not connect unrelated map positions")
		layer.clear()
	var original: Transform2D = viewport.global_canvas_transform
	for view: Transform2D in [Transform2D(0.0, Vector2(0.5, 0.5), 0.0, Vector2(400, 300)), Transform2D(0.0, Vector2(3, 3), 0.0, Vector2(-1200, -900))]:
		mouse.pressed = true
		plugin._forward_canvas_gui_input(mouse)
		var before: PackedByteArray = layer.tile_map_data
		viewport.global_canvas_transform = view
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		plugin._forward_canvas_gui_input(motion)
		_check(not plugin._dragging and layer.tile_map_data == before, "Changing the view during a stroke cannot paint a long accidental connection")
		viewport.global_canvas_transform = original
		layer.clear()
	mouse.pressed = true
	plugin._forward_canvas_gui_input(mouse)
	var missed_release_before: PackedByteArray = layer.tile_map_data
	motion.button_mask = 0
	plugin._forward_canvas_gui_input(motion)
	_check(not plugin._dragging and layer.tile_map_data == missed_release_before, "Releasing the button outside the viewport stops painting on reentry")
	layer.clear()


func _click(point: Vector2, button: MouseButton) -> void:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.position = point
	event.button_index = button
	event.pressed = true
	plugin._forward_canvas_gui_input(event)
	event.pressed = false
	plugin._forward_canvas_gui_input(event)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		if failures <= 10:
			push_error(message)
