@tool
extends EditorPlugin

var _toolbar: HBoxContainer
var _enabled_button: Button
var _layer: WallTileMapLayer
var _enabled: bool = false
var _kind: int = 0
var _dragging: bool = false
var _stroke_button: MouseButton = MOUSE_BUTTON_NONE
var _erasing: bool = false
var _hover: Vector3i = Vector3i.ZERO
var _has_hover: bool = false
var _previous_point: Vector2 = Vector2.ZERO
var _stroke_transform: Transform2D = Transform2D.IDENTITY
var _before: Dictionary[Vector2i, Vector4i] = {}
var _after: Dictionary[Vector2i, Vector4i] = {}
var _visited: Dictionary[Vector3i, bool] = {}


func _enter_tree() -> void:
	_toolbar = HBoxContainer.new()
	_enabled_button = Button.new()
	_enabled_button.text = "Paint hex edges"
	_enabled_button.toggle_mode = true
	_enabled_button.toggled.connect(_toggle_tool)
	_toolbar.add_child(_enabled_button)
	var group: ButtonGroup = ButtonGroup.new()
	var labels: Array[String] = ["Stone wall", "Hedge", "Erase edge"]
	for index: int in range(labels.size()):
		var button: Button = Button.new()
		button.text = labels[index]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = index == 0
		var kind: int = index
		if index == 2:
			kind = -1
		button.pressed.connect(_select_kind.bind(kind))
		_toolbar.add_child(button)
	_toolbar.hide()
	add_control_to_container(CONTAINER_CANVAS_EDITOR_MENU, _toolbar)


func _exit_tree() -> void:
	_finish_stroke()
	remove_control_from_container(CONTAINER_CANVAS_EDITOR_MENU, _toolbar)
	_toolbar.queue_free()


func _handles(object: Object) -> bool:
	return object is WallTileMapLayer


func _edit(object: Object) -> void:
	_finish_stroke()
	_layer = object as WallTileMapLayer
	_has_hover = false
	update_overlays()


func _make_visible(visible: bool) -> void:
	_toolbar.visible = visible
	if not visible:
		_finish_stroke()
		_has_hover = false
	update_overlays()


func _toggle_tool(enabled: bool) -> void:
	_finish_stroke()
	_enabled = enabled
	update_overlays()


func _select_kind(kind: int) -> void:
	_finish_stroke()
	_kind = kind
	update_overlays()


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if not _enabled or not is_instance_valid(_layer):
		return false
	if event is InputEventPanGesture or event is InputEventMagnifyGesture or Input.is_key_pressed(KEY_SPACE):
		_finish_navigation()
		return false
	if event is InputEventKey:
		var key: InputEventKey = event as InputEventKey
		if key.keycode == KEY_SPACE and key.pressed:
			_finish_navigation()
		return false
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if (motion.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0:
			_finish_navigation()
			return false
		var transform: Transform2D = _editor_transform()
		if _dragging:
			var button_mask: int = 1 << (_stroke_button - 1)
			if not transform.is_equal_approx(_stroke_transform) or (motion.button_mask & button_mask) == 0:
				_finish_stroke()
		var point: Vector2 = transform.affine_inverse() * motion.position
		_hover = _closest_edge(point)
		_has_hover = true
		if _dragging:
			var steps: int = maxi(1, ceili(_previous_point.distance_to(point) / 8.0))
			for step: int in range(1, steps + 1):
				_paint_edge(_closest_edge(_previous_point.lerp(point, float(step) / float(steps))))
		_previous_point = point
		update_overlays()
		return _dragging
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if mouse.button_index != MOUSE_BUTTON_LEFT and mouse.button_index != MOUSE_BUTTON_RIGHT:
			if mouse.pressed:
				_finish_navigation()
			return false
		if not mouse.pressed and mouse.button_index != _stroke_button:
			return false
		if mouse.pressed:
			_finish_stroke()
			_dragging = true
			_stroke_button = mouse.button_index
			_erasing = mouse.button_index == MOUSE_BUTTON_RIGHT or _kind == -1
			_stroke_transform = _editor_transform()
			_previous_point = _stroke_transform.affine_inverse() * mouse.position
			_hover = _closest_edge(_previous_point)
			_has_hover = true
			_paint_edge(_hover)
		else:
			_finish_stroke()
		update_overlays()
		return true
	return false


func _editor_transform() -> Transform2D:
	# The 2D editor stores zoom and pan in the viewport's global canvas transform.
	var viewport: SubViewport = EditorInterface.get_editor_viewport_2d()
	return viewport.get_global_canvas_transform() * _layer.get_global_transform_with_canvas()


func _finish_navigation() -> void:
	_finish_stroke()
	_has_hover = false
	update_overlays()


func _closest_edge(point: Vector2) -> Vector3i:
	var cell: Vector2i = _layer.local_to_map(point)
	var center: Vector2 = _layer.map_to_local(cell)
	var selected: int = 0
	var closest: float = INF
	for side: int in range(6):
		var start: Vector2 = center + ConnectedWalls.VERTICES[side]
		var end: Vector2 = center + ConnectedWalls.VERTICES[(side + 1) % 6]
		var distance: float = point.distance_squared_to(Geometry2D.get_closest_point_to_segment(point, start, end))
		if distance < closest:
			closest = distance
			selected = side
	var neighbor: Vector2i = _layer.get_neighbor_cell(cell, ConnectedWalls.SIDES[selected])
	# A shared side has one owner, even if the mouse strays across its border.
	if neighbor.x < cell.x or (neighbor.x == cell.x and neighbor.y < cell.y):
		cell = neighbor
		selected = (selected + 3) % 6
	return Vector3i(cell.x, cell.y, selected)


func _paint_edge(edge: Vector3i) -> void:
	if _visited.has(edge):
		return
	_visited[edge] = true
	var cell: Vector2i = Vector2i(edge.x, edge.y)
	var neighbor: Vector2i = _layer.get_neighbor_cell(cell, ConnectedWalls.SIDES[edge.z])
	var opposite: int = (edge.z + 3) % 6
	_remember(cell)
	_layer.edit_edge(cell, edge.z, maxi(0, _kind), _erasing)
	_after[cell] = _cell_value(cell)
	# Also remove the same side if an older tile owns it from the other hex.
	if _layer.get_edge_mask(neighbor) & (1 << opposite):
		_remember(neighbor)
		_layer.edit_edge(neighbor, opposite, 0, true)
		_after[neighbor] = _cell_value(neighbor)


func _remember(cell: Vector2i) -> void:
	if not _before.has(cell):
		_before[cell] = _cell_value(cell)


func _cell_value(cell: Vector2i) -> Vector4i:
	var atlas: Vector2i = _layer.get_cell_atlas_coords(cell)
	return Vector4i(_layer.get_cell_source_id(cell), atlas.x, atlas.y, _layer.get_cell_alternative_tile(cell))


func _finish_stroke() -> void:
	_dragging = false
	_stroke_button = MOUSE_BUTTON_NONE
	var changed: bool = false
	for cell: Vector2i in _before:
		if _before[cell] != _after[cell]:
			changed = true
	if is_instance_valid(_layer) and changed:
		var history: EditorUndoRedoManager = get_undo_redo()
		history.create_action("Paint wall or hedge edges", UndoRedo.MERGE_DISABLE, _layer)
		for cell: Vector2i in _before:
			var before: Vector4i = _before[cell]
			var after: Vector4i = _after[cell]
			if before == after:
				continue
			history.add_undo_method(_layer, "set_cell", cell, before.x, Vector2i(before.y, before.z), before.w)
			history.add_do_method(_layer, "set_cell", cell, after.x, Vector2i(after.y, after.z), after.w)
		history.commit_action(false)
	_before.clear()
	_after.clear()
	_visited.clear()


func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if not _enabled or not _has_hover or not is_instance_valid(_layer):
		return
	var center: Vector2 = _layer.map_to_local(Vector2i(_hover.x, _hover.y))
	var transform: Transform2D = _editor_transform()
	var start: Vector2 = transform * (center + ConnectedWalls.VERTICES[_hover.z])
	var end: Vector2 = transform * (center + ConnectedWalls.VERTICES[(_hover.z + 1) % 6])
	var color: Color = Color("f5df85")
	if _kind == 1:
		color = Color("8cca62")
	elif _kind == -1:
		color = Color("e38870")
	overlay.draw_line(start, end, color, 4.0, true)
