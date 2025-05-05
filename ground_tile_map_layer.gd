@tool
extends HexagonTileMapLayer

# ─── store the two map coords the user clicks ──────────────────────────
var _selected_map_hexes: Array[Vector2i] = []
var _selected_cube_hexes: Array[Vector3i] = []

# Customize pathfinding weights (optional)
func _pathfinding_get_tile_weight(coords: Vector2i) -> float:
		# Return custom weight value (default is 1.0)
		return 1.0

# Customize pathfinding connections (optional)
func _pathfinding_does_tile_connect(tile: Vector2i, neighbor: Vector2i) -> bool:
		# Return whether tiles should be connected (default is true)
		return true

func _ready():
	#pathfinding_enabled = true
	#if Engine.is_editor_hint():
		## allow this CanvasItem to receive gui_input in the editor
		#input_pickable = true
	super._ready()
	
	var cube_clicks : Array = []
	cube_clicks.append(map_to_cube(Vector2i(1,1)))
	cube_clicks.append(map_to_cube(Vector2i(0,1)))
	var na = cube_direction_name(cube_clicks[0], cube_clicks[1])
	#print(na)
	# Enable pathfinding
	

	# Enable debug visualization (optional)
	#debug_mode = DebugModeFlags.TILES_COORDS | DebugModeFlags.CONNECTIONS
	#pathfinding_get_point_id(Vector2i.ZERO)
	
	


func cube_direction_name(cur: Vector3i, nxt: Vector3i) -> String:
	var d = nxt - cur
	if d == Vector3i( 0,  1, -1): return "south"
	if d == Vector3i( 1,  0, -1): return "southeast"
	if d == Vector3i( 1, -1,  0): return "northeast"
	if d == Vector3i( 0, -1,  1): return "north"
	if d == Vector3i(-1,  0,  1): return "northwest"
	if d == Vector3i(-1,  1,  0): return "southwest"
	return "other"


# ─── catch clicks in the editor ────────────────────────────────────────
func forward_canvas_gui_input(event: InputEvent) -> void:
	print("lul")
	if not Engine.is_editor_hint():
		return
	
	#if Input.is_action_just_pressed("LEFT"): # and event.button_index == MouseButton.LEFT
		## convert the click into local coords, then into map coords
		#var local_pos : Vector2  = to_local(event.position)
		#var map_coord : Vector2i = local_to_map(local_pos)
		#var cube_coord : Vector3i = local_to_cube(local_pos)
#
		## push onto our 2-slot buffer
		#_selected_map_hexes.append(map_coord)
		#if _selected_map_hexes.size() > 2:
			#_selected_map_hexes = [ _selected_map_hexes.back() ]  # drop the older
		#_selected_cube_hexes.append(map_coord)
		#if _selected_cube_hexes.size() > 2:
			#_selected_cube_hexes = [ _selected_cube_hexes.back() ]  # drop the older
#
		#queue_redraw()  # trigger _draw()
#
		## once we have exactly two points, do the check
		#if _selected_map_hexes.size() == 2:
			#_check_hexside(_selected_map_hexes[0], _selected_map_hexes[1])
		#if _selected_cube_hexes.size() == 2:
			#var na = cube_direction_name(_selected_cube_hexes[0], _selected_cube_hexes[1])
			#print(na)

# ─── draw a red line between the two selected centers ──────────────────
func _draw() -> void:
	if Engine.is_editor_hint() and _selected_map_hexes.size() == 2:
		var a = _selected_map_hexes[0]
		var b = _selected_map_hexes[1]
		# map → cube → local to get exact pixel centers
		var p1 = cube_to_local(map_to_cube(a))
		var p2 = cube_to_local(map_to_cube(b))
		draw_line(p1, p2, Color(1,0,0), 2)

# ─── test if one of Δx,Δy,Δz == 0 in cube coords ────────────────────
func _check_hexside(a: Vector2i, b: Vector2i) -> void:
	var ca : Vector3i = map_to_cube(a)
	var cb : Vector3i = map_to_cube(b)
	var dx = cb.x - ca.x
	var dy = cb.y - ca.y
	var dz = cb.z - ca.z

	if dx == 0 or dy == 0 or dz == 0:
		print("✅ Line follows a hex-side direction.")
	else:
		print("❌ Line does _not_ follow a hex-side.")
