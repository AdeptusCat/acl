extends Node2D

# --- EXPORTED PROPERTIES ---
@export var ground_layer: HexagonTileMapLayer
@export var building_layer: HexagonTileMapLayer
@export var wall_layer: HexagonTileMapLayer
@export var debug_draw_enabled: bool = true

# --- CONSTANTS ---
const FLOOR_HEIGHT_METERS = 3.0
const UNIT_HEIGHT_METERS = 1.5
const STEP_SIZE_PIXELS = 3.0

enum COMPASS_DIRECTION {NORTH, NORTHEAST, SOUTHEAST, SOUTH, SOUTHWEST, NORTHWEST}

const WALL_COVER = 1
const BUILDING_COVER = 2
# --- INTERNAL ---
var origin_hex: Vector2i = Vector2i(-1, -1)
var los_lines: Array = []
const GRID_SIZE_X = 6#24
const GRID_SIZE_Y = 6#10

# --- PUBLIC FUNCTION ---
var los_lookup: Dictionary = {}

func load_prebaked_los(file_path: String):
	var los_resource = load(file_path) as LosLookupData
	los_lookup = los_resource.los_lookup
	print("LOS data loaded!")

func bake_and_save_los_data(file_path: String):
	prebake_los()

	var los_resource = LosLookupData.new()
	los_resource.los_lookup = los_lookup

	ResourceSaver.save(los_resource, file_path)
	print("LOS data saved to: ", file_path)

func prebake_los():
	for ox in range(GRID_SIZE_X):
		for oy in range(GRID_SIZE_Y):
			var o_hex = Vector2i(ox, oy)
			var o_pos = ground_layer.map_to_local(o_hex)

			# make this a Dictionary, not an Array
			los_lookup[o_hex] = {}

			for tx in range(GRID_SIZE_X):
				for ty in range(GRID_SIZE_Y):
					var t_hex = Vector2i(tx, ty)
					if o_hex == t_hex:
						continue

					var t_pos = ground_layer.map_to_local(t_hex)
					var los = check_los(o_pos, t_pos, 1, 0, 1, 0)
					if not los["blocked"]:
						# store both cover values under t_hex
						los_lookup[o_hex][t_hex] = {
							"shooter_cover": los["shooter_cover"],
							"target_cover":  los["target_cover"]
						}
				# end tx,ty
			# end ox,oy
	print("LOS prebake with cover done!")


#func check_los(
		#origin_pos: Vector2, target_pos: Vector2,
		#origin_elevation: int, target_elevation: int,
		#origin_story: int, target_story: int
#) -> Dictionary:
	#var result = {
		#"blocked": false,
		#"hindrance_count": 0,
		#"crossed_wall": false,
		#"block_point": null,
		#"shooter_cover": 0.0,
		#"target_cover": 0.0,
	#}
	#
	## 1) shooter/target building cover
	#if is_sample_point_in_building(origin_pos):
		#result.shooter_cover = BUILDING_COVER
	#if is_sample_point_in_building(target_pos):
		#result.target_cover = BUILDING_COVER
#
	## 2) heights for crest‐blocking
	#var shooter_h = calculate_absolute_height(origin_elevation, origin_story)
	#var target_h  = calculate_absolute_height(target_elevation, target_story)
#
	## 3) origin/target hex in map coords
	#var origin_hex = ground_layer.local_to_map(origin_pos)
	#var target_hex = ground_layer.local_to_map(target_pos)
#
	## 4) cube coords & hex‐distance
	#var co = ground_layer.map_to_cube(origin_hex)
	#var ct = ground_layer.map_to_cube(target_hex)
	#var hex_path = ground_layer.cube_linedraw(co, ct)
	## we’ll skip hex_path[0]==origin_hex, hex_path[-1]==target_hex if you like
#
	## 5) walk each hex‐center along that line
	#for i in hex_path.size():
		## sample at the center of this hex
		#var hex_cube : Vector3i = hex_path[i]
		## convert cube → map coords
		#var hex_map : Vector2i = ground_layer.cube_to_map(hex_cube)
		## get world position of the hex‐center
		#var sample_pt : Vector2 = ground_layer.cube_to_local(hex_cube)
#
		## 5a) building? → refine between previous & current
		#if building_layer.get_cell_source_id(hex_map) != -1:
			## we hit the first building‐hex:
			## find the exact entry-point by sub-sampling between centers
			#var prev_pt = ground_layer.cube_to_local(hex_path[i - 1]) if i > 0 else origin_pos
			#result.block_point = _refine_entry(prev_pt, sample_pt)
			#result.blocked     = true
			#if result.blocked:
				#return result
#
		## 5b) wall‐crossing (your existing logic)
		#if is_sample_point_crossing_wall(sample_pt):
			#pass
			## … same as before …
			## set result.crossed_wall, result.block_point, etc.
			## return if fully blocked
		## 5c) crest‐blocking
		#var ratio = i / float(hex_path.size() - 1)
		#var height_here = lerp(shooter_h, target_h, ratio)
		#if is_sample_point_blocked_by_crest(sample_pt, height_here):
			#result.blocked     = true
			#result.block_point = sample_pt
			#return result
#
	## 6) nothing blocked!
	#return result


# Sub‐sampling between two points at 1px increments to find exactly
# where you enter the building tile.
func _refine_entry(a: Vector2, b: Vector2) -> Vector2:
	var dir = (b - a).normalized()
	var dist = a.distance_to(b)
	var steps = int(dist / STEP_SIZE_PIXELS)
	for j in range(steps + 1):
		var p = a + dir * (j * STEP_SIZE_PIXELS)
		if is_sample_point_in_building(p):
			return p
	# fallback
	return Vector2.ZERO


func check_los(origin_pos: Vector2, target_pos: Vector2, origin_elevation: int, target_elevation: int, origin_story: int, target_story: int) -> Dictionary:
	var result = {
		"blocked": false,
		"hindrance_count": 0,
		"crossed_wall": false,
		"block_point": null,
		"shooter_cover": 0,
		"target_cover": 0,
		"hexes": []
	}
	

	# 1) shooter building cover
	if is_sample_point_in_building(origin_pos):
		result.shooter_cover = BUILDING_COVER
	# 2) target building cover
	if is_sample_point_in_building(target_pos):
		result.target_cover = BUILDING_COVER
	
	var shooter_height = calculate_absolute_height(origin_elevation, origin_story)
	var target_height = calculate_absolute_height(target_elevation, target_story)

	var delta = target_pos - origin_pos
	var distance = delta.length()
	var direction = delta.normalized()
	#var steps = int(distance / STEP_SIZE_PIXELS)
	#var steps = distance

	var origin_hex_map : Vector2i = ground_layer.local_to_map(origin_pos)
	var target_hex_map : Vector2i = ground_layer.local_to_map(target_pos)
	
	var origin_hex_cube : Vector3i = ground_layer.local_to_cube(origin_pos)
	var target_hex_cube : Vector3i = ground_layer.local_to_cube(target_pos)
	
	var hexes : Array[Vector3i] = ground_layer.cube_linedraw(origin_hex_cube, target_hex_cube)
	result.hexes = hexes
	
	var is_in_wall = false
	var steps = hexes.size()
	
	if steps < 2:
		return result  # nothing to sample
	
	var prev_hex_cube : Vector3i = origin_hex_cube
	var prev_hex_map : Vector2i = origin_hex_map
	
	for i in range(steps):
		 # t runs from 0.0 at origin to 1.0 at target
		var t := float(i) / float(steps - 1)
		# sample_point equally spaced along the straight line
		var sample_point: Vector2 = origin_pos.lerp(target_pos, t)
		# same t for height interpolation
		var los_height_at_sample = lerp(shooter_height, target_height, t)
		#var sample_point = origin_pos + direction * (i * STEP_SIZE_PIXELS)
		#var sample_distance_ratio = (i * STEP_SIZE_PIXELS) / distance
		var sample_hex_map: Vector2i = ground_layer.local_to_map(sample_point)
		var sample_hex_cube: Vector3i = ground_layer.local_to_cube(sample_point)
		
		
		# skip the target-hex center check if you like:
		if sample_hex_map == target_hex_map:
			continue
		
		if sample_hex_map == origin_hex_map:
			continue
		#var los_height_at_sample = lerp(shooter_height, target_height, sample_distance_ratio)
#
		#var sample_hex = ground_layer.local_to_map(sample_point)
		#var origin_hex = ground_layer.local_to_map(origin_pos)

		#if sample_hex == origin_hex_map:
			#continue
		
		# 5a) building? → refine between previous & current
		if building_layer.get_cell_source_id(sample_hex_map) != -1:
			# we hit the first building‐hex:
			# find the exact entry-point by sub-sampling between centers
			#var sample_point: Vector2 = origin_pos.lerp(target_pos, t)
			var t1 := float(i-1) / float(steps - 1)
			var t2 := float(i+1) / float(steps - 1)
			var prev_pt : Vector2 = origin_pos.lerp(target_pos, t1)
			var next_pt : Vector2 = origin_pos.lerp(target_pos, t2)
			result.block_point = _refine_entry(prev_pt, next_pt)
			if not result.block_point == Vector2.ZERO:
				result.blocked = true
			if result.blocked:
				return result

		if wall_layer.get_cell_source_id(prev_hex_map) != -1:
			#print(building_layer.cube_to_map(prev_hex_cube))
			#print(building_layer.cube_to_map(sample_hex_cube))
			var compass_direction : int = cube_direction_name(prev_hex_cube, sample_hex_cube)
			
			var wall : bool = false
			var tile_data_prev : TileData = wall_layer.get_cell_tile_data(prev_hex_map)
			if tile_data_prev:
				if tile_data_prev.has_custom_data("n"):
					var dir : bool = tile_data_prev.get_custom_data("n")
					if dir == true and compass_direction == COMPASS_DIRECTION.NORTH:
						wall = true
				if tile_data_prev.has_custom_data("ne"):
					var dir : bool = tile_data_prev.get_custom_data("ne")
					if dir == true and compass_direction == COMPASS_DIRECTION.NORTHEAST:
						wall = true
				if tile_data_prev.has_custom_data("se"):
					var dir : bool = tile_data_prev.get_custom_data("se")
					if dir == true and compass_direction == COMPASS_DIRECTION.SOUTHEAST:
						wall = true
				if tile_data_prev.has_custom_data("s"):
					var dir : bool = tile_data_prev.get_custom_data("s")
					if dir == true and compass_direction == COMPASS_DIRECTION.SOUTH:
						wall = true
				if tile_data_prev.has_custom_data("sw"):
					var dir : bool = tile_data_prev.get_custom_data("sw")
					if dir == true and compass_direction == COMPASS_DIRECTION.SOUTHWEST:
						wall = true
				if tile_data_prev.has_custom_data("nw"):
					var dir : bool = tile_data_prev.get_custom_data("nw")
					if dir == true and compass_direction == COMPASS_DIRECTION.NORTHWEST:
						wall = true
			if wall == true:
				result["crossed_wall"] = true
				result["blocked"] = true
				result["block_point"] = sample_point
				return result
		if wall_layer.get_cell_source_id(sample_hex_map) != -1:
			var compass_direction : int = cube_direction_name(prev_hex_cube, sample_hex_cube)
			
			var wall : bool = false
			var tile_data_sample : TileData = wall_layer.get_cell_tile_data(sample_hex_map)
			if tile_data_sample:
				if tile_data_sample.has_custom_data("n"):
					var dir : bool = tile_data_sample.get_custom_data("n")
					if dir == true and compass_direction == COMPASS_DIRECTION.SOUTH:
						wall = true
				if tile_data_sample.has_custom_data("ne"):
					var dir : bool = tile_data_sample.get_custom_data("ne")
					if dir == true and compass_direction == COMPASS_DIRECTION.SOUTHWEST:
						wall = true
				if tile_data_sample.has_custom_data("se"):
					var dir : bool = tile_data_sample.get_custom_data("se")
					if dir == true and compass_direction == COMPASS_DIRECTION.NORTHWEST:
						wall = true
				if tile_data_sample.has_custom_data("s"):
					var dir : bool = tile_data_sample.get_custom_data("s")
					if dir == true and compass_direction == COMPASS_DIRECTION.NORTH:
						wall = true
				if tile_data_sample.has_custom_data("sw"):
					var dir : bool = tile_data_sample.get_custom_data("sw")
					if dir == true and compass_direction == COMPASS_DIRECTION.NORTHEAST:
						wall = true
				if tile_data_sample.has_custom_data("nw"):
					var dir : bool = tile_data_sample.get_custom_data("nw")
					if dir == true and compass_direction == COMPASS_DIRECTION.SOUTHEAST:
						wall = true
			if wall == true:
				result["crossed_wall"] = true
				result["blocked"] = true
				result["block_point"] = sample_point
				return result
				
			
		prev_hex_cube = sample_hex_cube
		prev_hex_map = sample_hex_map
		
		#if is_sample_point_crossing_wall(sample_point):
			#var forward_step = sample_point + direction * 20.0
			#var forward_hex = ground_layer.local_to_map(forward_step)
#
			#var sample_neighbors = get_neighboring_hexes(sample_hex_map)
			#
			#
			#if is_in_wall:
				#continue
			#
			#if sample_hex_map == origin_hex:
				#is_in_wall = true
				#if result.shooter_cover < WALL_COVER:
					#result.shooter_cover = WALL_COVER
				#continue
			#
			#if target_hex_map in sample_neighbors and (forward_hex == target_hex_map or sample_hex_map == target_hex_map):
				#if result.target_cover < WALL_COVER:
					#result.target_cover = WALL_COVER
				#continue
			#is_in_wall = true
			#result["crossed_wall"] = true
			#result["blocked"] = true
			#result["block_point"] = sample_point
			#return result
			#
		#else:
			#is_in_wall = false
		## --- Crest line blocking (NEW)
		if is_sample_point_blocked_by_crest(sample_point, los_height_at_sample):
			result["blocked"] = true
			result["block_point"] = sample_point
			return result
	
	return result

# --- INTERNAL HELPERS ---

func calculate_absolute_height(hex_elevation: int, story_level: int) -> float:
	return (hex_elevation * FLOOR_HEIGHT_METERS) + (story_level * FLOOR_HEIGHT_METERS) + UNIT_HEIGHT_METERS

func is_sample_point_in_building(sample_point: Vector2) -> bool:
	var space_state = get_world_2d().direct_space_state
	var params = PhysicsPointQueryParameters2D.new()
	params.position = sample_point
	params.collide_with_areas = false
	params.collide_with_bodies = true
	params.collision_mask = 1  # Assuming buildings are on layer 1
	var result = space_state.intersect_point(params, 1)

	for item in result:
		if item.collider == building_layer:
			return true
	return false

func is_sample_point_crossing_wall(sample_point: Vector2) -> bool:
	var space_state = get_world_2d().direct_space_state
	var params = PhysicsPointQueryParameters2D.new()
	params.position = sample_point
	params.collide_with_areas = false
	params.collide_with_bodies = true
	params.collision_mask = 2  # Assuming walls are on layer 2
	var result = space_state.intersect_point(params, 1)

	for item in result:
		if item.collider == wall_layer:
			return true
	return false

func is_sample_point_blocked_by_crest(sample_point: Vector2, los_height_at_sample: float) -> bool:
	var space_state = get_world_2d().direct_space_state
	var params = PhysicsPointQueryParameters2D.new()
	params.position = sample_point
	params.collide_with_areas = false
	params.collide_with_bodies = true
	params.collision_mask = 4  # Assuming layer 4 is crest lines
	var result = space_state.intersect_point(params, 1)

	if result.size() == 0:
		return false

	for item in result:
		# Optionally check collider properties, etc.
		# Assume crest elevation from custom data or fixed crest height
		var crest_elevation = 6.0  # Or read from tile data

		if los_height_at_sample < crest_elevation:
			return true
	return false

	return false

#func _ready():
	#await get_tree().process_frame
	#prebake_los()

func get_neighboring_hexes(hex: Vector2i) -> Array:
	var neighbors = []
	var even = hex.y % 2 == 0

	neighbors.append(hex + Vector2i(1, 0))   # East
	neighbors.append(hex + Vector2i(-1, 0))  # West
	neighbors.append(hex + Vector2i(0, -1))  # North-East or North-West
	neighbors.append(hex + Vector2i(0, 1))   # South-East or South-West

	if even:
		neighbors.append(hex + Vector2i(-1, -1)) # NW
		neighbors.append(hex + Vector2i(-1, 1))  # SW
	else:
		neighbors.append(hex + Vector2i(1, -1)) # NE
		neighbors.append(hex + Vector2i(1, 1))  # SE

	return neighbors

# --- DEBUG DRAW (Optional) ---

func _input(event):
	if Input.is_action_just_pressed("MIDDLE"): 
		
		var mouse_pos = event.position
		var hex = ground_layer.local_to_map(mouse_pos)
		if not origin_hex == hex or los_lines.is_empty():
			origin_hex = hex
			generate_los_lines_for_debug()
		else:
			los_lines.clear()
			queue_redraw()
			
		

func _draw():
	if not debug_draw_enabled:
		return

	if origin_hex == Vector2i(-1, -1):
		return

	var origin_pos = ground_layer.map_to_local(origin_hex)

	for line_data in los_lines:
		if line_data["blocked"]:
			var block_point = line_data["block_point"]
			if block_point == null:
				block_point = origin_pos  # Failsafe
			draw_line(block_point, line_data["target_pos"], Color(1, 0, 0), 2.0)

	for line_data in los_lines:
		var block_point = line_data["block_point"]
		if block_point == null:
			block_point = origin_pos  # Failsafe
		if not line_data["blocked"]:
			draw_line(origin_pos, line_data["target_pos"], Color(0, 1, 0), 2.0)
		else:
			draw_line(origin_pos, block_point, Color(0, 1, 0), 2.0)
		#var orig = origin_pos
		#for hex in line_data["hexes"]:
			#var pos = ground_layer.cube_to_local(hex)
			#draw_line(orig, pos, Color(0, 1, 0), 2.0)
			#orig = pos
			

func generate_los_lines_for_debug():
	if not debug_draw_enabled:
		return

	los_lines.clear()
	var origin_pos = ground_layer.map_to_local(origin_hex)

	for tx in range(GRID_SIZE_X):
		for ty in range(GRID_SIZE_Y):
			var target_hex = Vector2i(tx, ty)
			if origin_hex == target_hex:
				continue

			var target_pos = ground_layer.map_to_local(target_hex)

			var los_result = check_los(origin_pos, target_pos, 1, 0, 1, 0)

			los_lines.append({
				"target_pos": target_pos,
				"blocked": los_result["blocked"],
				"block_point": los_result["block_point"],
				"hexes": los_result["hexes"]
			})
			
			

	queue_redraw()

func cube_direction_name(cur: Vector3i, nxt: Vector3i) -> int:
	var d = nxt - cur
	if d == Vector3i( 0,  1, -1): return COMPASS_DIRECTION.SOUTH
	if d == Vector3i( 1,  0, -1): return COMPASS_DIRECTION.SOUTHEAST
	if d == Vector3i( 1, -1,  0): return COMPASS_DIRECTION.NORTHEAST
	if d == Vector3i( 0, -1,  1): return COMPASS_DIRECTION.NORTH
	if d == Vector3i(-1,  0,  1): return COMPASS_DIRECTION.NORTHWEST
	if d == Vector3i(-1,  1,  0): return COMPASS_DIRECTION.SOUTHWEST
	return 66

func check_between_axes(a: Vector2i, b: Vector2i) -> bool:
	# 1) Convert to cube coords
	var ca: Vector3i = ground_layer.map_to_cube(a)
	var cb: Vector3i = ground_layer.map_to_cube(b)

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
		return true
	else:
		print("❌ Line does _not_ run between axes.")
		return false
