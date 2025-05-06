# res://addons/hex_tool/hex_tool.gd
@tool
extends EditorPlugin

var _tilemap: HexagonTileMapLayer = null
var map_clicks: Array[Vector2i] = []
var cube_clicks: Array[Vector3i] = []
var _prev_left := false
var points_to_draw : Array[Vector2]

func _enter_tree():
	set_process(true)                                      # turn on _process()
	set_force_draw_over_forwarding_enabled()           # allow our draw callback

func _handles(obj: Object) -> bool:
	return obj is HexagonTileMapLayer

func _edit(obj: Object) -> void:
	_tilemap = obj as HexagonTileMapLayer
	# pull in all the conversion functions now that we’re in editor
	_tilemap._on_tileset_changed()    # <— this makes map_to_cube()/cube_to_local() valid
	map_clicks.clear()
	cube_clicks.clear()
	update_overlays()

func _forward_canvas_gui_input(event: InputEvent) -> bool:
	#print("got event:", _tilemap)   # does this ever print?
	if not _tilemap:
		return false
	if event is InputEventMouseButton and event.pressed:
		if map_clicks.size() >= 2:
			map_clicks.clear()
		if cube_clicks.size() >= 2:
			cube_clicks.clear()
		 # 1) raw mouse in viewport coords
		var scene_root = get_tree().get_edited_scene_root()
		var mouse_coords = scene_root.get_global_mouse_position()
		#Viewport.get_mouse_pos()
		var viewport = get_editor_interface().get_base_control().get_viewport()
		var mouse_v = viewport.get_mouse_position()
		#mouse_coords = get_global_mouse_position()

		# 4) to map (cell) coords
		var map_pos  = _tilemap.local_to_map(mouse_v)
		var cube_pos  = _tilemap.local_to_cube(mouse_v)

		map_clicks.append(map_pos)
		cube_clicks.append(cube_pos)
		update_overlays()
		if map_clicks.size() == 2:
			_check_between_axes(map_clicks[0], map_clicks[1])
		if cube_clicks.size() == 2:
			var na = cube_direction_name(cube_clicks[0], cube_clicks[1])
			draw_selected_hexes(cube_clicks[0], cube_clicks[1])
			print(na)
	return false  # return true if you want to _consume_ the click

func draw_selected_hexes(origin_hex_cube, target_hex_cube):
	#var origin_hex_map : Vector2i = ground_layer.local_to_map(origin_pos)
	#var target_hex_map : Vector2i = ground_layer.local_to_map(target_pos)
	#
	#var origin_hex_cube : Vector3i = ground_layer.local_to_cube(origin_pos)
	#var target_hex_cube : Vector3i = ground_layer.local_to_cube(target_pos)
	points_to_draw.clear()
	var n = _tilemap.cube_distance(origin_hex_cube, target_hex_cube)
	var hexes : Array[Vector3i] = []
	for i in range(n + 1):
		var t = float(i) / float(n)
		# linear interpolate in 3D
		var fx = lerp(origin_hex_cube.x, target_hex_cube.x, t)
		var fy = lerp(origin_hex_cube.y, target_hex_cube.y, t)
		var fz = lerp(origin_hex_cube.z, target_hex_cube.z, t)
		# round to the nearest valid cube coord
		var h = HexagonTileMap.cube_round(Vector3(fx, fy, fz))
		hexes.append(h)
		points_to_draw.append(_tilemap.cube_to_local(h))

func cube_direction_name(cur: Vector3i, nxt: Vector3i) -> String:
	var d = nxt - cur
	if d == Vector3i( 0,  1, -1): return "north"
	if d == Vector3i( 1,  0, -1): return "northeast"
	if d == Vector3i( 1, -1,  0): return "southeast"
	if d == Vector3i( 0, -1,  1): return "south"
	if d == Vector3i(-1,  0,  1): return "southwest"
	if d == Vector3i(-1,  1,  0): return "northwest"
	return "other"

#func _process(delta: float) -> void:
	#if not _tilemap:
		#return
	#var left = Input.is_action_pressed("lol")  # poll left button :contentReference[oaicite:1]{index=1}
	#if left and not _prev_left:
		## just pressed!
		#var vp = get_editor_interface().get_editor_viewport()
		#var mouse_pos = vp.get_mouse_position()                 # get Mouse position in viewport coords :contentReference[oaicite:2]{index=2}
		#var map_pos = _tilemap.local_to_map(mouse_pos)
#
		#_clicks.append(map_pos)
		#if _clicks.size() > 2:
			#_clicks = [_clicks.back()]
#
		#update_overlays()
		#if _clicks.size() == 2:
			#_check_hexside(_clicks[0], _clicks[1])
#
	#_prev_left = left

#func forward_canvas_draw_over_viewport(overlay: Control) -> void:
	#if _tilemap and _clicks.size() == 2:
		#var a = _tilemap.map_to_cube(_clicks[0])
		#var b = _tilemap.map_to_cube(_clicks[1])
		#var p1 = _tilemap.cube_to_local(a)
		#var p2 = _tilemap.cube_to_local(b)
		#overlay.draw_line(p1, p2, Color.RED, 2)

func _check_hexside(a: Vector2i, b: Vector2i) -> void:
	print("got :", _tilemap)
	print(" what ", _tilemap.map_to_cube(a))
	var ca = _tilemap.map_to_cube(a)
	var cb = _tilemap.map_to_cube(b)
	if ca.x == cb.x or ca.y == cb.y or ca.z == cb.z:
		print("✅ Aligned to a hex-side.")
	else:
		print("❌ Not aligned.")

func _check_between_axes(a: Vector2i, b: Vector2i) -> void:
	# 1) Convert to cube coords
	var ca: Vector3i = _tilemap.map_to_cube(a)
	var cb: Vector3i = _tilemap.map_to_cube(b)

	# 2) Compute the delta vector
	var dx = cb.x - ca.x
	var dy = cb.y - ca.y
	var dz = cb.z - ca.z
	
	print(a)
	print(b)
	
	print(ca)
	print(cb)

	# 3) Check for “between-axes”: two equal components, third == –2× them
	#    This covers all multiples of (1,1,–2), (–2,1,1), etc.
	if   (dx == dy   and dz == -2*dx) \
	 or (dy == dz   and dx == -2*dy) \
	 or (dz == dx   and dy == -2*dz):
		print("✅ Line runs perfectly between two axes.")
	else:
		print("❌ Line does _not_ run between axes.")


func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	# only draw when we have exactly two clicks
	if _tilemap and map_clicks.size() == 2:
		# 1) convert map -> cube -> local (pixel) coords
		var p1 = _tilemap.cube_to_local( _tilemap.map_to_cube(map_clicks[0]) )
		var p2 = _tilemap.cube_to_local( _tilemap.map_to_cube(map_clicks[1]) )
		# 2) draw a line between them
		overlay.draw_line(p1, p2, Color.RED, 2)
		update_overlays()
	if _tilemap:
		
		for i in range(points_to_draw.size()-1):
			overlay.draw_line(points_to_draw[i], points_to_draw[i+1], Color.GREEN, 2)
