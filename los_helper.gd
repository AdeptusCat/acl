extends Node2D

# --- EXPORTED PROPERTIES ---
@export var ground_layer: HexagonTileMapLayer
@export var building_layer: HexagonTileMapLayer
@export var wall_layer: HexagonTileMapLayer
@export var terrain_layer: HexagonTileMapLayer
@export var debug_draw_enabled: bool = true

# --- CONSTANTS ---
const FLOOR_HEIGHT_METERS = 3.0
const UNIT_HEIGHT_METERS = 1.5
const STEP_SIZE_PIXELS = 1.0

enum COMPASS_DIRECTION {NORTH, NORTHEAST, SOUTHEAST, SOUTH, SOUTHWEST, NORTHWEST}

const WALL_COVER = 1
const BUILDING_COVER = 2
# --- INTERNAL ---
var origin_hex: Vector2i = Vector2i(-1, -1)
var los_lines: Array = []
const GRID_SIZE_X = 24
const GRID_SIZE_Y = 10

# --- PUBLIC FUNCTION ---
var los_lookup: Dictionary = {}

enum BetweenAxis {
	NONE,
	X_Y_POS, X_Y_NEG,
	Y_Z_POS, Y_Z_NEG,
	Z_X_POS, Z_X_NEG
}
func _ready():
	z_index = 100  # Higher than other nodes

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





func refine_entry(a: Vector2, b: Vector2) -> Vector2:
	var dir = (b - a).normalized()
	var dist = a.distance_to(b)
	var steps = int(dist / STEP_SIZE_PIXELS)
	for j in range(steps + 1):
		var p = a + dir * (j * STEP_SIZE_PIXELS)
		if is_sample_point_in_building(p):
			return p
	# fallback
	return Vector2.ZERO


func is_uneven(n: int) -> bool:
	return n % 2 != 0

# 1) Cube → Axial (pointy-topped convention:  q = x, r = z)
func cube_to_axial_frac(c: Vector3) -> Vector2:
	return Vector2(c.x, c.z)


# flat-topped:
#   radius = tile_size.x/2
#   x = radius * 1.5 * q
#   y = radius * sqrt(3) * (r + q*0.5)
func axial_to_pixel_flat(p: Vector2, tile_size: Vector2) -> Vector2:
	var radius = tile_size.x * 0.5
	var x = radius * 1.5 * p.x
	var y = radius * sqrt(3) * (p.y + p.x * 0.5)
	return Vector2(x, y)


# 3) All together:
func fractional_cube_to_local(c: Vector3, tile_size: Vector2) -> Vector2:
	var axial = cube_to_axial_frac(c)
	return axial_to_pixel_flat(axial, tile_size)

func check_los(origin_pos: Vector2, target_pos: Vector2, origin_elevation: int, target_elevation: int, origin_story: int, target_story: int) -> Dictionary:
	var result = {
		"blocked": false,
		"hindrance_count": 0,
		"crossed_wall": false,
		"block_point": null,
		"shooter_cover": 0,
		"target_cover": 0,
		"hexes": [],
		"hindrance": 0,
	}
	

	# 1) shooter building cover
	result.shooter_cover = is_sample_point_in_building(origin_pos)
		#result.shooter_cover = BUILDING_COVER
	# 2) target building cover
	result.target_cover = is_sample_point_in_building(target_pos)
	#if is_sample_point_in_building(target_pos):
		#result.target_cover = BUILDING_COVER
	
	var shooter_height = calculate_absolute_height(origin_elevation, origin_story)
	var target_height = calculate_absolute_height(target_elevation, target_story)

	var delta = target_pos - origin_pos
	var distance = delta.length()
	var direction = delta.normalized()

	var origin_hex_map : Vector2i = ground_layer.local_to_map(origin_pos)
	var target_hex_map : Vector2i = ground_layer.local_to_map(target_pos)
	
	var origin_hex_cube : Vector3i = ground_layer.local_to_cube(origin_pos)
	var target_hex_cube : Vector3i = ground_layer.local_to_cube(target_pos)
	
	var n = ground_layer.cube_distance(origin_hex_cube, target_hex_cube)
	
	var is_between_hexes : bool = check_between_axes(origin_hex_map, target_hex_map)
	
	var direction_between_axes = check_dir_between_axes(origin_hex_map, target_hex_map)
	match direction_between_axes:
		BetweenAxis.X_Y_POS:
			var s_cube_vector : Vector3i = Vector3i(0, 1, -1)
			var se_cube_vector : Vector3i = Vector3i(1, 0, -1)
			var res : Dictionary = _walk_between_axes_and_check_walls(
							origin_hex_cube,
							target_hex_cube,
							origin_hex_map,
							target_hex_map,
							s_cube_vector,
							se_cube_vector
						)
			if res.blocked == true:
				result.merge(res, true)
				return result
		BetweenAxis.X_Y_NEG:
			var n_cube_vector : Vector3i = Vector3i(0, -1, 1)
			var nw_cube_vector : Vector3i = Vector3i(-1, 0, 1)
			var res : Dictionary = _walk_between_axes_and_check_walls(
							origin_hex_cube,
							target_hex_cube,
							origin_hex_map,
							target_hex_map,
							n_cube_vector,
							nw_cube_vector
						)
			if res.blocked == true:
				result.merge(res, true)
				return result
		BetweenAxis.Y_Z_POS:
			var nw_cube_vector : Vector3i = Vector3i(-1, 0, 1)
			var sw_cube_vector : Vector3i = Vector3i(-1, 1, 0)
			var res : Dictionary = _walk_between_axes_and_check_walls(
							origin_hex_cube,
							target_hex_cube,
							origin_hex_map,
							target_hex_map,
							nw_cube_vector,
							sw_cube_vector
						)
			if res.blocked == true:
				result.merge(res, true)
				return result
		BetweenAxis.Y_Z_NEG:
			var ne_cube_vector : Vector3i = Vector3i(1, -1, 0)
			var se_cube_vector : Vector3i = Vector3i(1, 0, -1)
			var res : Dictionary = _walk_between_axes_and_check_walls(
							origin_hex_cube,
							target_hex_cube,
							origin_hex_map,
							target_hex_map,
							ne_cube_vector,
							se_cube_vector
						)
			if res.blocked == true:
				result.merge(res, true)
				return result
		BetweenAxis.Z_X_POS:
			var n_cube_vector : Vector3i = Vector3i(0, -1, 1)
			var ne_cube_vector : Vector3i = Vector3i(1, -1, 0)
			var res : Dictionary = _walk_between_axes_and_check_walls(
							origin_hex_cube,
							target_hex_cube,
							origin_hex_map,
							target_hex_map,
							n_cube_vector,
							ne_cube_vector
						)
			if res.blocked == true:
				result.merge(res, true)
				return result
		BetweenAxis.Z_X_NEG:
			var s_cube_vector : Vector3i = Vector3i(0, 1, -1)
			var se_cube_vector : Vector3i = Vector3i(-1, 1, 0)
			var res : Dictionary = _walk_between_axes_and_check_walls(
							origin_hex_cube,
							target_hex_cube,
							origin_hex_map,
							target_hex_map,
							s_cube_vector,
							se_cube_vector
						)
			if res.blocked == true:
				result.merge(res, true)
				return result
	
	var hexes : Array[Vector3i] = cube_line(origin_hex_cube, target_hex_cube, n)
	result.hexes = hexes
	var steps = hexes.size()
	
	if steps < 2:
		return result
	
	var prev_hex_cube : Vector3i = origin_hex_cube
	var prev_hex_map : Vector2i = origin_hex_map
	
	for i in range(steps):
		var t := float(i) / float(steps - 1)
		var sample_point: Vector2 = origin_pos.lerp(target_pos, t)
		var los_height_at_sample = lerp(shooter_height, target_height, t)
		var sample_hex_map: Vector2i = ground_layer.cube_to_map(hexes[i])
		var sample_hex_cube: Vector3i = hexes[i]
		
		if sample_hex_map == target_hex_map:
			var wall_result
			wall_result = is_wall_blocking(prev_hex_cube, sample_hex_cube, prev_hex_map, sample_point)
			if wall_result.size() > 0:
				if wall_result.cover > result.target_cover:
					result.target_cover = wall_result.cover

			wall_result = is_wall_blocking(sample_hex_cube, prev_hex_cube, sample_hex_map, sample_point)
			if wall_result.size() > 0:
				if wall_result.cover > result.target_cover:
					result.target_cover = wall_result.cover
		
		# skip the target-hex center check
		if sample_hex_map == target_hex_map:
			continue
		
		if prev_hex_map == origin_hex_map:
			var wall_result
			wall_result = is_wall_blocking(prev_hex_cube, sample_hex_cube, prev_hex_map, sample_point)
			if wall_result.size() > 0:
				if wall_result.cover > result.shooter_cover:
					result.shooter_cover = wall_result.cover

			wall_result = is_wall_blocking(sample_hex_cube, prev_hex_cube, sample_hex_map, sample_point)
			if wall_result.size() > 0:
				if wall_result.cover > result.shooter_cover:
					result.shooter_cover = wall_result.cover
		
		# skip the origin-hex center check
		if sample_hex_map == origin_hex_map:
			continue

		if building_layer.get_cell_source_id(sample_hex_map) != -1:
			result = _check_building_block(sample_hex_map, i, steps, origin_pos, target_pos, result)
			if result.blocked:
				return result
		
		if terrain_layer.get_cell_source_id(sample_hex_map) != -1:
			result = _check_hindrance(sample_hex_map, result)
		
		if terrain_layer.get_cell_source_id(sample_hex_map) != -1:
			result = _check_blocking_terrain(sample_hex_map, result)
			if result.blocked:
				return result
		
		
		var wall_result
		if not prev_hex_map == origin_hex_map:
			wall_result = is_wall_blocking(prev_hex_cube, sample_hex_cube, prev_hex_map, sample_point)
			if wall_result.size() > 0:
				result.merge(wall_result, true)
				return result

		if not prev_hex_map == origin_hex_map:
			wall_result = is_wall_blocking(sample_hex_cube, prev_hex_cube, sample_hex_map, sample_point)
			if wall_result.size() > 0:
				result.merge(wall_result, true)
				return result


		prev_hex_cube = sample_hex_cube
		prev_hex_map = sample_hex_map
#
		### --- Crest line blocking (NEW)
		##if is_sample_point_blocked_by_crest(sample_point, los_height_at_sample):
			##result["blocked"] = true
			##result["block_point"] = sample_point
			##return result
	
	return result

# --- INTERNAL HELPERS ---

func _walk_between_axes_and_check_walls(
		origin_hex_cube: Vector3i,
		target_hex_cube: Vector3i,
		origin_hex_map: Vector2i,
		target_hex_map: Vector2i,
		direction_1: Vector3i,
		direction_2: Vector3i
	) -> Dictionary:

	var result := {
		"blocked": false,
		"block_point": Vector2.ZERO,
		"hindrance" : 0
	}
	var start_hex_cube : Vector3i = origin_hex_cube
	var start_hex_map : Vector2i = origin_hex_map
	while true:
		var s_hex_cube : Vector3i = start_hex_cube + direction_1
		var s_hex_map : Vector2i = ground_layer.cube_to_map(s_hex_cube)
		var se_hex_cube : Vector3i = start_hex_cube + direction_2
		var se_hex_map : Vector2i = ground_layer.cube_to_map(se_hex_cube)
		var next_middle_hex_cube : Vector3i = s_hex_cube + direction_2
		var next_middle_hex_map : Vector2i = ground_layer.cube_to_map(next_middle_hex_cube)
		
		
		if not start_hex_cube == origin_hex_cube:
			if terrain_layer.get_cell_source_id(start_hex_map) != -1:
				result = _check_hindrance(start_hex_map, result)
				result = _check_blocking_terrain(start_hex_map, result)
				if result.blocked:
					return result
		
		var hindrance_result : Dictionary = {"hindrance" : 0}
		if terrain_layer.get_cell_source_id(s_hex_map) != -1:
			hindrance_result = _check_hindrance(s_hex_map, hindrance_result)
			result = _check_blocking_terrain(s_hex_map, result)
			if result.blocked:
				return result
		
		if terrain_layer.get_cell_source_id(se_hex_map) != -1:
			hindrance_result = _check_hindrance(se_hex_map, hindrance_result)
			result = _check_blocking_terrain(se_hex_map, result)
			if result.blocked:
				return result
		# only count one hindrance if the hexspine is edging on two hindrance hexes
		if hindrance_result.hindrance > 0:
			result.hindrance += 1
		
		
		## check blocked by building from start to target hex, so test line is along hexspine
		#if not start_hex_cube == origin_hex_cube:
			#result["block_point"] = _refine_entry(ground_layer.cube_to_local(start_hex_cube), ground_layer.cube_to_local(next_middle_hex_cube))
			#if result["block_point"] == Vector2.ZERO:
				#result["blocked"] = true
			#if result.blocked:
				#return result
		result["block_point"] = _refine_entry_alt(ground_layer.cube_to_local(start_hex_cube), ground_layer.cube_to_local(next_middle_hex_cube), se_hex_map)
		if not result["block_point"] == Vector2.ZERO:
			result["blocked"] = true
		if result.blocked:
			return result
		
		result["block_point"] = _refine_entry_alt(ground_layer.cube_to_local(start_hex_cube), ground_layer.cube_to_local(next_middle_hex_cube), s_hex_map)
		if not result["block_point"] == Vector2.ZERO:
			result["blocked"] = true
		if result.blocked:
			return result


		# from start to South
		if wall_layer.get_cell_source_id(start_hex_map) != -1 and not start_hex_map == origin_hex_map:
			var wall_result = is_wall_blocking(start_hex_cube, s_hex_cube, start_hex_map, ground_layer.map_to_local(s_hex_map))
			if wall_result.size() > 0:
				result.merge(wall_result, true)
				return result

		if wall_layer.get_cell_source_id(s_hex_map) != -1 and not start_hex_map == origin_hex_map: 
			var wall_result = is_wall_blocking(s_hex_cube, start_hex_cube, s_hex_map, ground_layer.map_to_local(start_hex_map))
			if wall_result.size() > 0:
				result.merge(wall_result, true)
				return result
			
		
		# from South to next middle hex
		if wall_layer.get_cell_source_id(s_hex_map) != -1 and not next_middle_hex_map == target_hex_map:
			var wall_result = is_wall_blocking(s_hex_cube, next_middle_hex_cube, s_hex_map, ground_layer.map_to_local(next_middle_hex_map))
			if wall_result.size() > 0:
				result.merge(wall_result, true)
				return result

		if wall_layer.get_cell_source_id(next_middle_hex_map) != -1 and not next_middle_hex_map == target_hex_map: 
			var wall_result = is_wall_blocking(next_middle_hex_cube, s_hex_cube, next_middle_hex_map, ground_layer.map_to_local(s_hex_map))
			if wall_result.size() > 0:
				result.merge(wall_result, true)
				return result
		
		# from start to South-East
		if wall_layer.get_cell_source_id(start_hex_map) != -1 and not start_hex_map == origin_hex_map:
			var wall_result = is_wall_blocking(start_hex_cube, se_hex_cube, start_hex_map, ground_layer.map_to_local(se_hex_map))
			if wall_result.size() > 0:
				result.merge(wall_result, true)
				return result
		
		if wall_layer.get_cell_source_id(se_hex_map) and not start_hex_map == origin_hex_map:
			var wall_result = is_wall_blocking(se_hex_cube, start_hex_cube, se_hex_map, ground_layer.map_to_local(start_hex_map))
			if wall_result.size() > 0:
				result.merge(wall_result, true)
				return result
		
		# from South-East to next middle hex
		if wall_layer.get_cell_source_id(se_hex_map) != -1 and not next_middle_hex_map == target_hex_map:
			var wall_result = is_wall_blocking(se_hex_cube, next_middle_hex_cube, se_hex_map, ground_layer.map_to_local(next_middle_hex_map))
			if wall_result.size() > 0:
				result.merge(wall_result, true)
				return result

		if wall_layer.get_cell_source_id(next_middle_hex_map) and not next_middle_hex_map == target_hex_map:
			var wall_result = is_wall_blocking(next_middle_hex_cube, se_hex_cube, next_middle_hex_map, ground_layer.map_to_local(se_hex_map))
			if wall_result.size() > 0:
				result.merge(wall_result, true)
				return result
		
		start_hex_cube = next_middle_hex_cube
		start_hex_map = next_middle_hex_map
		if next_middle_hex_cube == target_hex_cube:
			break;
	return result


func cube_line(origin_hex_cube: Vector3i, target_hex_cube: Vector3i, n: int) -> Array[Vector3i]:
	var hexes: Array[Vector3i] = []
	for i in range(n + 1):
		var t: float = float(i) / float(n)
		# Linear interpolation in 3D
		var fx = lerp(origin_hex_cube.x, target_hex_cube.x, t)
		var fy = lerp(origin_hex_cube.y, target_hex_cube.y, t)
		var fz = lerp(origin_hex_cube.z, target_hex_cube.z, t)
		# Round to nearest valid cube coord
		var h: Vector3i = HexagonTileMap.cube_round(Vector3(fx, fy, fz))
		hexes.append(h)
	return hexes




func _check_hindrance(sample_hex_map: Vector2i, result: Dictionary) -> Dictionary:
	var tile_data: TileData = terrain_layer.get_cell_tile_data(sample_hex_map)
	if tile_data and tile_data.has_custom_data("hindrance") \
	   and tile_data.get_custom_data("hindrance"):
		result["hindrance"] += 1
	return result

func _check_blocking_terrain(sample_hex_map: Vector2i, result: Dictionary) -> Dictionary:
	var tile_data: TileData = terrain_layer.get_cell_tile_data(sample_hex_map)
	if tile_data and tile_data.has_custom_data("blocking") \
	   and tile_data.get_custom_data("blocking"):
		result["blocked"]      = true
		result["block_point"]  = ground_layer.map_to_local(sample_hex_map)
	return result


# Sub‐sampling between two points at 1px increments to find exactly
# where you enter the building tile.
func _refine_entry(a: Vector2, b: Vector2) -> Vector2:
	var dir = (b - a).normalized()
	var dist = a.distance_to(b)
	var steps = int(dist / STEP_SIZE_PIXELS)
	var start_hex_map : Vector2i = ground_layer.local_to_map(a)
	var target_hex_map : Vector2i = ground_layer.local_to_map(b)
	for j in range(steps + 1):
		var p = a + dir * (j * STEP_SIZE_PIXELS)
		var curr_hex_map : Vector2i = ground_layer.local_to_map(p)
		if curr_hex_map == start_hex_map or curr_hex_map == target_hex_map:
			continue
		if is_pixel_in_building(p, building_layer):
			return p
			
		#if is_sample_point_in_building(p):
			#return p
	# fallback
	return Vector2.ZERO

func is_pixel_in_building(world_pos_to_check: Vector2, tilemap: HexagonTileMapLayer) -> bool:
	var hex_map : Vector2i = tilemap.local_to_map(world_pos_to_check)
	var hex_pos = tilemap.map_to_local(hex_map)
	var vector : Vector2 = world_pos_to_check - hex_pos
	var pos_on_hex : Vector2 = Vector2(32,32) + vector
	
	# 1. Convert world coordinates to tile (cell) coordinates
	#var cell_coords = tilemap.local_to_map(world_pos)
	# 2. Get the tile ID at the cell
	var tile_id = tilemap.get_cell_source_id(hex_map)
	if tile_id == -1:
		return false  # No tile here

	# 3. Get the atlas texture or tile texture
	var tileset = tilemap.tile_set
	
	var texture = tileset.get_source(tile_id).texture
	if texture == null:
		return false

	# 5. Convert to pixel coordinates (assuming 1:1 texel-to-pixel ratio)
	var tex_size = texture.get_size()
	var image = texture.get_image()
	if image == null:
		return false

	#var pixel_x = clamp(int(local_pos.x), 0, tex_size.x - 1)
	#var pixel_y = clamp(int(local_pos.y), 0, tex_size.y - 1)

	#print(hex_map)
	if pos_on_hex.x == 64 or pos_on_hex.y == 64:
		return false
	var color = image.get_pixel(pos_on_hex.x, pos_on_hex.y)
	#print(pos_on_hex.x)
	#print(pos_on_hex.y)
	#print(color)

	#print("Alpha at pixel:", color.a)
	if color.a == 0.0:
		return false
	else:
		return true

func _refine_entry_alt(a: Vector2, b: Vector2, hex_to_check: Vector2i) -> Vector2:
	var dir = (b - a).normalized()
	var dist = a.distance_to(b)
	var steps = int(dist / STEP_SIZE_PIXELS)
	var start_hex_map : Vector2i = ground_layer.local_to_map(a)
	var target_hex_map : Vector2i = ground_layer.local_to_map(b)
	for j in range(steps + 1):
		var p = a + dir * (j * STEP_SIZE_PIXELS)
		var curr_hex_map : Vector2i = ground_layer.local_to_map(p)
		if curr_hex_map == start_hex_map or curr_hex_map == target_hex_map:
			continue
		if is_pixel_in_building_alt(p, building_layer, hex_to_check):
			return p
			
		#if is_sample_point_in_building(p):
			#return p
	# fallback
	return Vector2.ZERO


func is_pixel_in_building_alt(world_pos_to_check: Vector2, tilemap: HexagonTileMapLayer, hex_map_to_check: Vector2i) -> bool:
	var hex_map : Vector2i = hex_map_to_check
	var hex_pos = tilemap.map_to_local(hex_map)
	var vector : Vector2 = world_pos_to_check - hex_pos
	var pos_on_hex : Vector2 = Vector2(32,32) + vector
	
	# 1. Convert world coordinates to tile (cell) coordinates
	#var cell_coords = tilemap.local_to_map(world_pos)
	# 2. Get the tile ID at the cell
	var tile_id = tilemap.get_cell_source_id(hex_map)
	if tile_id == -1:
		return false  # No tile here

	# 3. Get the atlas texture or tile texture
	var tileset = tilemap.tile_set
	
	var texture = tileset.get_source(tile_id).texture
	if texture == null:
		return false

	# 5. Convert to pixel coordinates (assuming 1:1 texel-to-pixel ratio)
	var tex_size = texture.get_size()
	var image = texture.get_image()
	if image == null:
		return false

	#var pixel_x = clamp(int(local_pos.x), 0, tex_size.x - 1)
	#var pixel_y = clamp(int(local_pos.y), 0, tex_size.y - 1)

	#print(hex_map)
	if pos_on_hex.x == 64  or pos_on_hex.y == 64:
		return false
	var color = image.get_pixel(pos_on_hex.x, pos_on_hex.y)
	#print(pos_on_hex.x)
	#print(pos_on_hex.y)
	#print(color)

	#print("Alpha at pixel:", color.a)
	if color.a == 0.0:
		return false
	else:
		return true


func _check_building_block(sample_hex_map: Vector2i, i: int, steps: int, origin_pos: Vector2, target_pos: Vector2, result: Dictionary) -> Dictionary:
	# Compute sub-sampled points just before and after the hit
	var t1: float = float(i - 1) / float(steps - 1)
	var t2: float = float(i + 1) / float(steps - 1)
	var prev_pt: Vector2 = origin_pos.lerp(target_pos, t1)
	var next_pt: Vector2 = origin_pos.lerp(target_pos, t2)
	
	# Try to find precise entry point
	result["block_point"] = _refine_entry(prev_pt, next_pt)
	if result["block_point"] != Vector2.ZERO:
		result["blocked"] = true
	
	return result


func check_building_block(sample_hex_map: Vector2i, i: int, steps: int, origin_pos: Vector2, target_pos: Vector2, result: Dictionary) -> Dictionary:
	# Compute sub-sampled points just before and after the hit
	var t1: float = float(i - 1) / float(steps - 1)
	var t2: float = float(i + 1) / float(steps - 1)
	var prev_pt: Vector2 = origin_pos.lerp(target_pos, t1)
	var next_pt: Vector2 = origin_pos.lerp(target_pos, t2)

	# Try to find precise entry point
	result["block_point"] = refine_entry(prev_pt, next_pt)
	if result["block_point"] != Vector2.ZERO:
		result["blocked"] = true

	return result

# helper to map compass constants to your custom-data keys
func compass_direction_to_label(dir: int) -> String:
	match dir:
		COMPASS_DIRECTION.NORTH:     return "n"
		COMPASS_DIRECTION.NORTHEAST: return "ne"
		COMPASS_DIRECTION.SOUTHEAST: return "se"
		COMPASS_DIRECTION.SOUTH:     return "s"
		COMPASS_DIRECTION.SOUTHWEST: return "sw"
		COMPASS_DIRECTION.NORTHWEST: return "nw"
		_:                          return ""


func is_wall_blocking(
		from_cube: Vector3i,
		to_cube:   Vector3i,
		from_map:  Vector2i,
		sample_pt: Vector2
	) -> Dictionary:
	var result := {}
	# early out if there's no tile here or it's the origin tile
	if wall_layer.get_cell_source_id(from_map) == -1:
		return result

	var dir = cube_direction_name(from_cube, to_cube)
	var label = compass_direction_to_label(dir)
	if label == "":
		return result   # some weird direction?

	var tile_data: TileData = wall_layer.get_cell_tile_data(from_map)
	if tile_data and tile_data.has_custom_data(label) \
	   and tile_data.get_custom_data(label):
		result["crossed_wall"] = true
		result["blocked"]      = true
		result["block_point"]  = sample_pt
		result["cover"] = tile_data.get_custom_data("cover")
	return result


func calculate_absolute_height(hex_elevation: int, story_level: int) -> float:
	return (hex_elevation * FLOOR_HEIGHT_METERS) + (story_level * FLOOR_HEIGHT_METERS) + UNIT_HEIGHT_METERS

#func is_sample_point_in_building(sample_point: Vector2) -> bool:
	#var tile_data: TileData = wall_layer.get_cell_tile_data(from_map)
	#if tile_data and tile_data.has_custom_data(label) \
	   #and tile_data.get_custom_data(label):
		#result["crossed_wall"] = true
		#result["blocked"]      = true
		#result["block_point"]  = sample_pt
	#return false

func is_sample_point_in_building(sample_point: Vector2) -> int:
	var hex_map = building_layer.local_to_map(sample_point)
	if building_layer.get_cell_source_id(hex_map) == -1:
		return 0
	else:
		var tile_data: TileData = building_layer.get_cell_tile_data(hex_map)
		if tile_data and tile_data.has_custom_data("cover"):
			return tile_data.get_custom_data("cover")
		return true

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

			var los_result = check_los(origin_pos, target_pos, 1, 1, 1, 1)
			
			if los_result["blocked"] == true:
				pass
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

	# 3) Check for “between-axes”: two equal components, third == –2× them
	#    This covers all multiples of (1,1,–2), (–2,1,1), etc.
	if   (dx == dy   and dz == -2*dx) \
	 or (dy == dz   and dx == -2*dy) \
	 or (dz == dx   and dy == -2*dz):
		#print("✅ Line runs perfectly between two axes.")
		return true
	else:
		#print("❌ Line does _not_ run between axes.")
		return false


func check_dir_between_axes(a: Vector2i, b: Vector2i) -> BetweenAxis:
	var ca: Vector3i = ground_layer.map_to_cube(a)
	var cb: Vector3i = ground_layer.map_to_cube(b)

	var dx = cb.x - ca.x
	var dy = cb.y - ca.y
	var dz = cb.z - ca.z

	var gcd_val = gcd(abs(dx), gcd(abs(dy), abs(dz)))
	if gcd_val == 0:
		return BetweenAxis.NONE

	var ndx = dx / gcd_val
	var ndy = dy / gcd_val
	var ndz = dz / gcd_val

	if ndx == ndy and ndz == -2 * ndx:
		return BetweenAxis.X_Y_POS if ndx > 0 else BetweenAxis.X_Y_NEG
	elif ndy == ndz and ndx == -2 * ndy:
		return BetweenAxis.Y_Z_POS if ndy > 0 else BetweenAxis.Y_Z_NEG
	elif ndz == ndx and ndy == -2 * ndz:
		return BetweenAxis.Z_X_POS if ndz > 0 else BetweenAxis.Z_X_NEG
	else:
		return BetweenAxis.NONE

# Helper: greatest common divisor
func gcd(a: int, b: int) -> int:
	while b != 0:
		var temp = b
		b = a % b
		a = temp
	return a
