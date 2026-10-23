extends Node2D

# --- EXPORTED PROPERTIES ---
@export var ground_layer: HexagonTileMapLayer
@export var building_layer: HexagonTileMapLayer
@export var wall_layer: HexagonTileMapLayer
@export var terrain_layer: HexagonTileMapLayer
@export var road_layer: HexagonTileMapLayer
@export var debug_draw_enabled: bool = true

var grid_size: Vector2i

# --- CONSTANTS ---
const FLOOR_HEIGHT_METERS: float = 3.0
const UNIT_HEIGHT_METERS: float = 1.5
const STEP_SIZE_PIXELS: float = 1.0

enum COMPASS_DIRECTION {NORTH, NORTHEAST, SOUTHEAST, SOUTH, SOUTHWEST, NORTHWEST}

const WALL_COVER: int = 1
const BUILDING_COVER: int = 2
# --- INTERNAL ---
var origin_hex: Vector2i = Vector2i(-1, -1)
var los_lines: Array = []


var visible_hexes: Dictionary[int, Array] = {Globals.Team.AXIS: [], Globals.Team.ALLIES: []}
#var visible_hexes: Array[Vector2i]

var initialized: bool = false

# --- PUBLIC FUNCTION ---
var los_lookup: Dictionary = {}
var _texture_images: Dictionary[Texture2D, Image] = {}
var _active_los_resource: LosLookupData
var _bake_cache: LosBakeCache
var _last_bake_layout_signature: String = ""

enum BetweenAxis {
	NONE,
	X_Y_POS, X_Y_NEG,
	Y_Z_POS, Y_Z_NEG,
	Z_X_POS, Z_X_NEG
}
func _ready() -> void:
	z_index = 100  # Higher than other nodes
	

func load_prebaked_los(map: Map) -> void:
	end_los_bake()
	_last_bake_layout_signature = ""
	clear_los()
	_texture_images.clear()
	var file_path: String = "res://resources/los/" + map.map_name.to_lower().replace(" ", "_") + ".tres"
	if not map.los_resource_path.is_empty():
		file_path = map.los_resource_path
	var los_resource: LosLookupData
	if ResourceLoader.exists(file_path):
		los_resource = load(file_path) as LosLookupData
	_active_los_resource = los_resource
	ground_layer = map.get_ground_layer()
	building_layer = map.get_building_layer()
	wall_layer = map.get_wall_layer()
	terrain_layer = map.get_terrain_layer()
	road_layer = map.get_road_layer()
	grid_size = map.grid_size
	var signature: String = building_layout_signature()
	var wall_signature: String = wall_layout_signature()
	if los_resource == null:
		if not signature.is_empty() or not wall_signature.is_empty():
			_active_los_resource = _load_or_rebuild_los(map, signature, wall_signature)
			los_lookup = _active_los_resource.los_lookup
			return
		los_lookup = {}
		push_error("Missing baked line of sight for " + map.map_name)
		return
	var changed: bool = los_resource.building_layout_signature != signature or los_resource.wall_layout_signature != wall_signature
	# Legacy tables have no terrain fingerprint and cannot certify the current layout.
	# Always validate the full layout, including vegetation, artwork and grid changes.
	begin_los_bake()
	changed = changed or los_resource.bake_layout_signature != bake_layout_signature()
	if changed:
		var rebuilt: LosLookupData = _load_or_rebuild_los(map, signature, wall_signature)
		# Retain the refreshed active lookup in memory; authoring tools save it.
		los_resource.los_lookup = rebuilt.los_lookup
		los_resource.building_layout_signature = signature
		los_resource.wall_layout_signature = wall_signature
		los_resource.bake_layout_signature = rebuilt.bake_layout_signature
	end_los_bake()
	los_lookup = los_resource.los_lookup
	print("LOS data loaded!")


func _load_or_rebuild_los(map: Map, signature: String, wall_signature: String) -> LosLookupData:
	if _bake_cache == null:
		begin_los_bake()
	var layout: String = bake_layout_signature()
	var identity: String = map.los_resource_path
	if identity.is_empty():
		identity = map.scene_file_path
	if identity.is_empty():
		identity = map.map_name
	var directory: String = "user://los_cache/"
	var path: String = directory + identity.sha256_text() + ".res"
	var rebuilt: LosLookupData
	if ResourceLoader.exists(path):
		rebuilt = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as LosLookupData
		if rebuilt != null and rebuilt.bake_layout_signature == layout:
			end_los_bake()
			print("Reused rebuilt LOS cache: ", map.map_name)
			return rebuilt
	print("Rebuilding LOS for changed map layout: ", map.map_name)
	_bake_prepared_los()
	rebuilt = LosLookupData.new()
	rebuilt.los_lookup = los_lookup
	rebuilt.building_layout_signature = signature
	rebuilt.wall_layout_signature = wall_signature
	rebuilt.bake_layout_signature = layout
	end_los_bake()
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK:
		var error: Error = ResourceSaver.save(rebuilt, path, ResourceSaver.FLAG_COMPRESS)
		if error != OK:
			push_warning("Could not retain rebuilt LOS cache: " + error_string(error))
	return rebuilt


func building_layout_signature() -> String:
	if building_layer is BuildingTileMapLayer:
		return (building_layer as BuildingTileMapLayer).los_layout_signature()
	return ""


func wall_layout_signature() -> String:
	if wall_layer is WallTileMapLayer:
		return (wall_layer as WallTileMapLayer).los_layout_signature()
	return ""


func bake_layout_signature() -> String:
	return _last_bake_layout_signature


func unload_map() -> void:
	end_los_bake()
	_last_bake_layout_signature = ""
	clear_los()
	_texture_images.clear()
	ground_layer = null
	building_layer = null
	wall_layer = null
	terrain_layer = null
	road_layer = null
	grid_size = Vector2i.ZERO
	los_lookup = {}
	_active_los_resource = null
	visible_hexes = {Globals.Team.AXIS: [], Globals.Team.ALLIES: []}
	initialized = false


func _has_map_layers() -> bool:
	return is_instance_valid(ground_layer) and is_instance_valid(building_layer) and is_instance_valid(wall_layer) and is_instance_valid(terrain_layer)


func bake_and_save_los_data(map: Map) -> void:
	clear_los()
	ground_layer = map.get_ground_layer()
	building_layer = map.get_building_layer()
	wall_layer = map.get_wall_layer()
	terrain_layer = map.get_terrain_layer()
	road_layer = map.get_road_layer()
	grid_size = map.grid_size
	prebake_los()

	var los_resource: LosLookupData = LosLookupData.new()
	los_resource.los_lookup = los_lookup
	los_resource.building_layout_signature = building_layout_signature()
	los_resource.wall_layout_signature = wall_layout_signature()
	los_resource.bake_layout_signature = bake_layout_signature()
	var file_path: String = "res://resources/los/" + map.map_name.to_lower().replace(" ", "_") + ".tres"
	
	ResourceSaver.save(los_resource, file_path)
	print("LOS data saved to: ", file_path)

func begin_los_bake() -> void:
	end_los_bake()
	building_layout_signature()
	wall_layout_signature()
	_texture_images.clear()
	var cache: LosBakeCache = LosBakeCache.new()
	cache.setup(ground_layer, building_layer, wall_layer, terrain_layer)
	for x: int in range(grid_size.x):
		for y: int in range(grid_size.y):
			var cell: Vector2i = Vector2i(x, y)
			var point: Vector2 = ground_layer.map_to_local(cell)
			cache.positions[cell] = point
			cache.endpoint_cover[point] = is_sample_point_in_building(point)
			cache.endpoint_concealment[point] = get_target_concealment(point)
	_bake_cache = cache
	_last_bake_layout_signature = cache.fingerprint(grid_size, STEP_SIZE_PIXELS)


func end_los_bake() -> void:
	_bake_cache = null


func bake_los_origin(origin: Vector2i) -> Dictionary:
	assert(_bake_cache != null, "Begin the LOS rebuild before baking an origin")
	var row: Dictionary = {}
	var origin_pos: Vector2 = _bake_cache.positions[origin]
	for target: Vector2i in _bake_cache.positions:
		if origin == target:
			continue
		var result: Dictionary = check_los(origin_pos, _bake_cache.positions[target], 1, 0, 1, 0)
		if not result["blocked"]:
			row[target] = {
				"shooter_cover": result["shooter_cover"],
				"target_cover": result["target_cover"],
				"wall_cover": result["wall_cover"],
				"hindrance": result["hindrance"],
				"target_concealment": result["target_concealment"],
			}
	return row


func prebake_los() -> void:
	begin_los_bake()
	_bake_prepared_los()
	end_los_bake()
	print("LOS prebake with cover done!")


func _bake_prepared_los() -> void:
	los_lookup = {}
	for origin: Vector2i in _bake_cache.positions:
		los_lookup[origin] = bake_los_origin(origin)


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
	#var target_hex: Vector2i = ground_layer.local_to_map(target_pos)
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
	var dir: Vector2 = (b - a).normalized()
	var dist: float = a.distance_to(b)
	var steps: int = int(dist / STEP_SIZE_PIXELS)
	for j: int in range(steps + 1):
		var p: Vector2 = a + dir * (j * STEP_SIZE_PIXELS)
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
	var radius: float = tile_size.x * 0.5
	var x: float = radius * 1.5 * p.x
	var y: float = radius * sqrt(3) * (p.y + p.x * 0.5)
	return Vector2(x, y)


# 3) All together:
func fractional_cube_to_local(c: Vector3, tile_size: Vector2) -> Vector2:
	var axial: Vector2 = cube_to_axial_frac(c)
	return axial_to_pixel_flat(axial, tile_size)

func check_los(origin_pos: Vector2, target_pos: Vector2, origin_elevation: int, target_elevation: int, origin_story: int, target_story: int) -> Dictionary:
	var result: Dictionary = {
		"blocked": false,
		"hindrance_count": 0,
		"crossed_wall": false,
		"block_point": null,
		"hex_cover": 0,
		"wall_cover" : 0,
		"shooter_cover": 0,
		"target_cover": 0,
		"hexes": [],
		"hindrance": 0,
		"target_concealment": 0,
	}
	

	# 1) shooter building cover
	result.shooter_cover = is_sample_point_in_building(origin_pos)
	result.hex_cover = result.shooter_cover
		#result.shooter_cover = BUILDING_COVER
	# 2) target building cover
	result.target_cover = is_sample_point_in_building(target_pos)
	result.target_concealment = get_target_concealment(target_pos)
	#if is_sample_point_in_building(target_pos):
		#result.target_cover = BUILDING_COVER
	
	var shooter_cover_origin_hex: int = result.shooter_cover
	var hex_cover: int = result.hex_cover
	var target_cover_target_hex: int = result.target_cover
	
	var shooter_height: float = calculate_absolute_height(origin_elevation, origin_story)
	var target_height: float = calculate_absolute_height(target_elevation, target_story)

	var delta: Vector2 = target_pos - origin_pos
	var _distance: float = delta.length()
	var _direction: Vector2 = delta.normalized()

	var origin_hex_map : Vector2i = ground_layer.local_to_map(origin_pos)
	var target_hex_map : Vector2i = ground_layer.local_to_map(target_pos)
	
	#if (target_hex_map == Vector2i(22,8)):
	#print(origin_hex_map, target_hex_map, origin_pos, target_pos, result.target_cover)
	
	var origin_hex_cube : Vector3i = ground_layer.local_to_cube(origin_pos)
	var target_hex_cube : Vector3i = ground_layer.local_to_cube(target_pos)
	
	var n: int = ground_layer.cube_distance(origin_hex_cube, target_hex_cube)
	if n == 0:
		return result
	
	var _is_between_hexes : bool = check_between_axes(origin_hex_map, target_hex_map)
	
	var direction_between_axes: BetweenAxis = check_dir_between_axes(origin_hex_map, target_hex_map)
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
							se_cube_vector,
							result
						)
			result.merge(res, true)
			result.shooter_cover += shooter_cover_origin_hex
			result.hex_cover = hex_cover
			result.target_cover += target_cover_target_hex
			if res.blocked == true:
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
							nw_cube_vector,
							result
						)
			result.merge(res, true)
			result.shooter_cover += shooter_cover_origin_hex
			result.hex_cover = hex_cover
			result.target_cover += target_cover_target_hex
			if res.blocked == true:
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
							sw_cube_vector,
							result
						)
			result.merge(res, true)
			result.shooter_cover += shooter_cover_origin_hex
			result.hex_cover = hex_cover
			result.target_cover += target_cover_target_hex
			if res.blocked == true:
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
							se_cube_vector,
							result
						)
			result.merge(res, true)
			result.shooter_cover += shooter_cover_origin_hex
			result.hex_cover = hex_cover
			result.target_cover += target_cover_target_hex
			if res.blocked == true:
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
							ne_cube_vector,
							result
						)
			result.merge(res, true)
			result.shooter_cover += shooter_cover_origin_hex
			result.hex_cover = hex_cover
			result.target_cover += target_cover_target_hex
			if res.blocked == true:
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
							se_cube_vector,
							result
						)
			result.merge(res, true)
			result.shooter_cover += shooter_cover_origin_hex
			result.hex_cover = hex_cover
			result.target_cover += target_cover_target_hex
			if res.blocked == true:
				return result
	
	var hexes : Array[Vector3i] = cube_line(origin_hex_cube, target_hex_cube, n)
	result.hexes = hexes
	result = _check_texture_obstacles(origin_pos, target_pos, hexes, result)
	if result.blocked:
		return result
	var steps: int = hexes.size()
	
	if steps < 2:
		return result
	
	var prev_hex_cube : Vector3i = origin_hex_cube
	var prev_hex_map : Vector2i = origin_hex_map
	
	for i: int in range(steps):
		var t: float = float(i) / float(steps - 1)
		var sample_point: Vector2 = origin_pos.lerp(target_pos, t)
		var _los_height_at_sample: float = lerp(shooter_height, target_height, t)
		var sample_hex_map: Vector2i = ground_layer.cube_to_map(hexes[i])
		var sample_hex_cube: Vector3i = hexes[i]
		
		var _wall_result: Dictionary
		_wall_result.clear()
		if sample_hex_map == target_hex_map:
			_wall_result = is_wall_cover(prev_hex_cube, sample_hex_cube, prev_hex_map, sample_point)
			if _wall_result.size() > 0:
				if _wall_result.cover > result.target_cover:
					result.target_cover = _wall_result.cover

			_wall_result = is_wall_cover(sample_hex_cube, prev_hex_cube, sample_hex_map, sample_point)
			if _wall_result.size() > 0:
				if _wall_result.cover > result.target_cover:
					result.target_cover = _wall_result.cover
		
		_wall_result.clear()
		if prev_hex_map == origin_hex_map:
			_wall_result = is_wall_cover(prev_hex_cube, sample_hex_cube, prev_hex_map, sample_point)
			if _wall_result.size() > 0:
				result.wall_cover = _wall_result.cover
				if _wall_result.cover > result.shooter_cover:
					result.shooter_cover = _wall_result.cover

			_wall_result = is_wall_cover(sample_hex_cube, prev_hex_cube, sample_hex_map, sample_point)
			if _wall_result.size() > 0:
				result.wall_cover = _wall_result.cover
				if _wall_result.cover > result.shooter_cover:
					result.shooter_cover = _wall_result.cover
		
		# skip the target-hex center check
		if sample_hex_map == target_hex_map:
			continue
		
		# skip the origin-hex center check
		if sample_hex_map == origin_hex_map:
			continue

		var wall_result: Dictionary
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
		direction_2: Vector3i,
		_result : Dictionary
	) -> Dictionary:

	var result: Dictionary = {
		"blocked": false,
		"block_point": Vector2.ZERO,
		"hindrance" : 0,
		"target_cover" : 0,
		"shooter_cover" : 0,
		"hex_cover": 0,
		"wall_cover" : 0,
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
		
		
		# check wall cover for shooter
		if start_hex_map == origin_hex_map:
			var wall_result : Dictionary
			wall_result = is_wall_cover(start_hex_cube, s_hex_cube, start_hex_map, ground_layer.map_to_local(s_hex_map))
			if wall_result.size() > 0:
				result.wall_cover = wall_result.cover
				if wall_result.cover > _result.shooter_cover:
					result.shooter_cover = wall_result.cover
					

			wall_result = is_wall_cover(s_hex_cube, start_hex_cube, s_hex_map, ground_layer.map_to_local(start_hex_map))
			if wall_result.size() > 0:
				result.wall_cover = wall_result.cover
				if wall_result.cover > _result.shooter_cover:
					result.shooter_cover = wall_result.cover
		
			wall_result = is_wall_cover(start_hex_cube, se_hex_cube, start_hex_map, ground_layer.map_to_local(se_hex_map))
			if wall_result.size() > 0:
				result.wall_cover = wall_result.cover
				if wall_result.cover > _result.shooter_cover:
					result.shooter_cover = wall_result.cover

			wall_result = is_wall_cover(se_hex_cube, start_hex_cube, se_hex_map, ground_layer.map_to_local(start_hex_map))
			if wall_result.size() > 0:
				result.wall_cover = wall_result.cover
				if wall_result.cover > _result.shooter_cover:
					result.shooter_cover = wall_result.cover
		
		# check wall cover for target
		if next_middle_hex_map == target_hex_map:
			var wall_result : Dictionary
			wall_result = is_wall_cover(next_middle_hex_cube, s_hex_cube, next_middle_hex_map, ground_layer.map_to_local(s_hex_map))
			if wall_result.size() > 0:
				if wall_result.cover > _result.target_cover:
					result.target_cover = wall_result.cover

			wall_result = is_wall_cover(s_hex_cube, next_middle_hex_cube, s_hex_map, ground_layer.map_to_local(next_middle_hex_map))
			if wall_result.size() > 0:
				if wall_result.cover > _result.target_cover:
					result.target_cover = wall_result.cover
		
			wall_result = is_wall_cover(next_middle_hex_cube, se_hex_cube, next_middle_hex_map, ground_layer.map_to_local(se_hex_map))
			if wall_result.size() > 0:
				if wall_result.cover > _result.target_cover:
					result.target_cover = wall_result.cover

			wall_result = is_wall_cover(se_hex_cube, next_middle_hex_cube, se_hex_map, ground_layer.map_to_local(next_middle_hex_map))
			if wall_result.size() > 0:
				if wall_result.cover > _result.target_cover:
					result.target_cover = wall_result.cover
		
		
		# from start to South
		if wall_layer.get_cell_source_id(start_hex_map) != -1 and not start_hex_map == origin_hex_map:
			var wall_result: Dictionary = is_wall_blocking(start_hex_cube, s_hex_cube, start_hex_map, ground_layer.map_to_local(s_hex_map))
			if wall_result.size() > 0:
				result.merge(wall_result, true)
				return result

		if wall_layer.get_cell_source_id(s_hex_map) != -1 and not start_hex_map == origin_hex_map: 
			var wall_result: Dictionary = is_wall_blocking(s_hex_cube, start_hex_cube, s_hex_map, ground_layer.map_to_local(start_hex_map))
			if wall_result.size() > 0:
				result.merge(wall_result, true)
				return result
			
		
		# from South to next middle hex
		if wall_layer.get_cell_source_id(s_hex_map) != -1 and not next_middle_hex_map == target_hex_map:
			var wall_result: Dictionary = is_wall_blocking(s_hex_cube, next_middle_hex_cube, s_hex_map, ground_layer.map_to_local(next_middle_hex_map))
			if wall_result.size() > 0:
				result.merge(wall_result, true)
				return result

		if wall_layer.get_cell_source_id(next_middle_hex_map) != -1 and not next_middle_hex_map == target_hex_map: 
			var wall_result: Dictionary = is_wall_blocking(next_middle_hex_cube, s_hex_cube, next_middle_hex_map, ground_layer.map_to_local(s_hex_map))
			if wall_result.size() > 0:
				result.merge(wall_result, true)
				return result
		
		# from start to South-East
		if wall_layer.get_cell_source_id(start_hex_map) != -1 and not start_hex_map == origin_hex_map:
			var wall_result: Dictionary = is_wall_blocking(start_hex_cube, se_hex_cube, start_hex_map, ground_layer.map_to_local(se_hex_map))
			if wall_result.size() > 0:
				result.merge(wall_result, true)
				return result
		
		if wall_layer.get_cell_source_id(se_hex_map) and not start_hex_map == origin_hex_map:
			var wall_result: Dictionary = is_wall_blocking(se_hex_cube, start_hex_cube, se_hex_map, ground_layer.map_to_local(start_hex_map))
			if wall_result.size() > 0:
				result.merge(wall_result, true)
				return result
		
		# from South-East to next middle hex
		if wall_layer.get_cell_source_id(se_hex_map) != -1 and not next_middle_hex_map == target_hex_map:
			var wall_result: Dictionary = is_wall_blocking(se_hex_cube, next_middle_hex_cube, se_hex_map, ground_layer.map_to_local(next_middle_hex_map))
			if wall_result.size() > 0:
				result.merge(wall_result, true)
				return result

		if wall_layer.get_cell_source_id(next_middle_hex_map) and not next_middle_hex_map == target_hex_map:
			var wall_result: Dictionary = is_wall_blocking(next_middle_hex_cube, se_hex_cube, next_middle_hex_map, ground_layer.map_to_local(se_hex_map))
			if wall_result.size() > 0:
				result.merge(wall_result, true)
				return result
		
		start_hex_cube = next_middle_hex_cube
		start_hex_map = next_middle_hex_map
		if next_middle_hex_cube == target_hex_cube:
			break
	return result


func cube_line(origin_hex_cube: Vector3i, target_hex_cube: Vector3i, n: int) -> Array[Vector3i]:
	var hexes: Array[Vector3i] = []
	for i: int in range(n + 1):
		var t: float = float(i) / float(n)
		# Linear interpolation in 3D
		var fx: float = lerp(origin_hex_cube.x, target_hex_cube.x, t)
		var fy: float = lerp(origin_hex_cube.y, target_hex_cube.y, t)
		var fz: float = lerp(origin_hex_cube.z, target_hex_cube.z, t)
		# Round to nearest valid cube coord
		var h: Vector3i = HexagonTileMap.cube_round(Vector3(fx, fy, fz))
		hexes.append(h)
	return hexes


func _check_hindrance(sample_hex_map: Vector2i, result: Dictionary) -> Dictionary:
	var tile_data: TileData = terrain_layer.get_cell_tile_data(sample_hex_map)
	if tile_data and tile_data.has_custom_data("hindrance") \
	   and tile_data.get_custom_data("hindrance"):
		result["hindrance"] += 1
		if result.has("shooter_cover"):
			result.shooter_cover += 1
			result.target_cover += 1
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
	var dir: Vector2 = (b - a).normalized()
	var dist: float = a.distance_to(b)
	var steps: int = int(dist / STEP_SIZE_PIXELS)
	var start_hex_map : Vector2i = ground_layer.local_to_map(a)
	var target_hex_map : Vector2i = ground_layer.local_to_map(b)
	for j: int in range(steps + 1):
		var p: Vector2 = a + dir * (j * STEP_SIZE_PIXELS)
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
	return _tile_pixel_is_solid(world_pos_to_check, tilemap, tilemap.local_to_map(world_pos_to_check))


func _refine_entry_alt(a: Vector2, b: Vector2, hex_to_check: Vector2i) -> Vector2:
	var dir: Vector2 = (b - a).normalized()
	var dist: float = a.distance_to(b)
	var steps: int = int(dist / STEP_SIZE_PIXELS)
	var start_hex_map : Vector2i = ground_layer.local_to_map(a)
	var target_hex_map : Vector2i = ground_layer.local_to_map(b)
	for j: int in range(steps + 1):
		var p: Vector2 = a + dir * (j * STEP_SIZE_PIXELS)
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
	return _tile_pixel_is_solid(world_pos_to_check, tilemap, hex_map_to_check)


func _check_building_block(_sample_hex_map: Vector2i, i: int, steps: int, origin_pos: Vector2, target_pos: Vector2, result: Dictionary) -> Dictionary:
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


func check_building_block(_sample_hex_map: Vector2i, i: int, steps: int, origin_pos: Vector2, target_pos: Vector2, result: Dictionary) -> Dictionary:
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

func is_wall_cover(
		from_cube: Vector3i,
		to_cube:   Vector3i,
		from_map:  Vector2i,
		_sample_pt: Vector2
	) -> Dictionary:
	var result: Dictionary = {}
	if _bake_cache != null:
		var edge: Vector2i = _bake_cache.walls.get(from_map, Vector2i.ZERO)
		var direction: int = cube_direction_name(from_cube, to_cube)
		if direction < 6 and (edge.x & (1 << direction)) != 0:
			result["cover"] = edge.y
		return result
	# early out if there's no tile here or it's the origin tile
	if wall_layer.get_cell_source_id(from_map) == -1:
		return result

	var dir: int = cube_direction_name(from_cube, to_cube)
	var label: String = compass_direction_to_label(dir)
	if label == "":
		return result   # some weird direction?

	var tile_data: TileData = wall_layer.get_cell_tile_data(from_map)
	if tile_data and tile_data.has_custom_data(label) \
	   and tile_data.get_custom_data(label):
		result["cover"] = tile_data.get_custom_data("cover")
	return result


func is_wall_blocking(
		from_cube: Vector3i,
		to_cube:   Vector3i,
		from_map:  Vector2i,
		sample_pt: Vector2
	) -> Dictionary:
	var result: Dictionary = {}
	if _bake_cache != null:
		var edge: Vector2i = _bake_cache.walls.get(from_map, Vector2i.ZERO)
		var direction: int = cube_direction_name(from_cube, to_cube)
		if direction < 6 and (edge.x & (1 << direction)) != 0:
			result["blocked"] = true
			result["block_point"] = sample_pt
		return result
	# early out if there's no tile here or it's the origin tile
	if wall_layer.get_cell_source_id(from_map) == -1:
		return result

	var dir: int = cube_direction_name(from_cube, to_cube)
	var label: String = compass_direction_to_label(dir)
	if label == "":
		return result   # some weird direction?

	var tile_data: TileData = wall_layer.get_cell_tile_data(from_map)
	if tile_data and tile_data.has_custom_data(label) \
	   and tile_data.get_custom_data(label):
		result["blocked"]      = true
		result["block_point"]  = sample_pt
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


func is_hex_hindrance(hex_map: Vector2i) -> bool:
	if terrain_layer.get_cell_source_id(hex_map) == -1:
		return false
	else:
		var tile_data: TileData = terrain_layer.get_cell_tile_data(hex_map)
		if tile_data and tile_data.has_custom_data("hindrance"):
			return tile_data.get_custom_data("hindrance")
		return false


func get_target_concealment(sample_point: Vector2) -> int:
	if _bake_cache != null and _bake_cache.endpoint_concealment.has(sample_point):
		return _bake_cache.endpoint_concealment[sample_point]
	var hex_map: Vector2i = building_layer.local_to_map(sample_point)
	if building_layer.get_cell_source_id(hex_map) != -1:
		var tile_data: TileData = building_layer.get_cell_tile_data(hex_map)
		if tile_data and tile_data.has_custom_data("cover") and is_pixel_in_building(sample_point, building_layer):
			return 2
	if terrain_layer.get_cell_source_id(hex_map) != -1:
		var tile_data: TileData = terrain_layer.get_cell_tile_data(hex_map)
		if tile_data and tile_data.has_custom_data("hindrance") and bool(tile_data.get_custom_data("hindrance")) and is_pixel_in_building(sample_point, terrain_layer):
			return 1
	return 0
	


func is_sample_point_in_building(sample_point: Vector2) -> int:
	if _bake_cache != null and _bake_cache.endpoint_cover.has(sample_point):
		return _bake_cache.endpoint_cover[sample_point]
	var hex_map: Vector2i = building_layer.local_to_map(sample_point)
	if building_layer.get_cell_source_id(hex_map) == -1:
		return 0
	else:
		var tile_data: TileData = building_layer.get_cell_tile_data(hex_map)
		if tile_data and tile_data.has_custom_data("cover"):
			return tile_data.get_custom_data("cover")
		return 0


func get_tile_name(sample_point: Vector2) -> String:
	var tile_name: String = ""
	var hex_map: Vector2i = building_layer.local_to_map(sample_point)
	if is_instance_valid(road_layer) and road_layer.get_cell_source_id(hex_map) >= 0:
		var road: TileData = road_layer.get_cell_tile_data(hex_map)
		if road != null and road.has_custom_data("name"):
			tile_name = str(road.get_custom_data("name"))
	if not building_layer.get_cell_source_id(hex_map) == -1:
		var tile_data: TileData = building_layer.get_cell_tile_data(hex_map)
		if tile_data and tile_data.has_custom_data("name"):
			tile_name =  tile_data.get_custom_data("name")
	if not terrain_layer.get_cell_source_id(hex_map) == -1:
		var tile_data: TileData = terrain_layer.get_cell_tile_data(hex_map)
		if tile_data and tile_data.has_custom_data("name"):
			tile_name =  tile_data.get_custom_data("name")
	return tile_name

func is_sample_point_crossing_wall(sample_point: Vector2) -> bool:
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var params: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	params.position = sample_point
	params.collide_with_areas = false
	params.collide_with_bodies = true
	params.collision_mask = 2  # Assuming walls are on layer 2
	var result: Array[Dictionary] = space_state.intersect_point(params, 1)

	for item: Dictionary in result:
		if item.collider == wall_layer:
			return true
	return false

func is_sample_point_blocked_by_crest(sample_point: Vector2, los_height_at_sample: float) -> bool:
	var space_state: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state
	var params: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	params.position = sample_point
	params.collide_with_areas = false
	params.collide_with_bodies = true
	params.collision_mask = 4  # Assuming layer 4 is crest lines
	var result: Array[Dictionary] = space_state.intersect_point(params, 1)

	if result.size() == 0:
		return false

	for item: Dictionary in result:
		# Optionally check collider properties, etc.
		# Assume crest elevation from custom data or fixed crest height
		var crest_elevation: float = 6.0  # Or read from tile data

		if los_height_at_sample < crest_elevation:
			return true
	return false

#func _ready():
	#await get_tree().process_frame
	#prebake_los()

func get_neighboring_hexes(hex: Vector2i) -> Array:
	var neighbors: Array = []
	var even: bool = hex.y % 2 == 0

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


#func _input(event):
	#if Input.is_action_just_pressed("MIDDLE"): 		
		#var mouse_pos = event.position
		#var hex = ground_layer.local_to_map(mouse_pos)
		#if not origin_hex == hex or los_lines.is_empty():
			#origin_hex = hex
			#generate_los_lines_for_debug()
		#else:
			#los_lines.clear()
			#queue_redraw()


func _draw() -> void:
	if not debug_draw_enabled or not is_instance_valid(ground_layer) or los_lines.is_empty():
		return
	if origin_hex == Vector2i(-1, -1):
		return
	var origin_pos: Vector2 = to_local(ground_layer.to_global(ground_layer.map_to_local(origin_hex)))
	var decorated: bool = los_lines.size() == 1
	for line_data: Dictionary in los_lines:
		var target_pos: Vector2 = to_local(ground_layer.to_global(line_data["target_pos"]))
		var block_point: Vector2 = origin_pos
		var hit: Variant = line_data["block_point"]
		if hit is Vector2:
			var hit_point: Vector2 = hit
			if hit_point.is_finite():
				block_point = to_local(ground_layer.to_global(hit_point))
		var crossings: PackedVector2Array = PackedVector2Array()
		for point: Vector2 in line_data["hindrance_points"]:
			crossings.append(to_local(ground_layer.to_global(point)))
		SightLineGraphic.draw(self, origin_pos, target_pos, bool(line_data["blocked"]), block_point, decorated, 1.0, crossings)


func generate_los_lines_for_debug() -> void:
	if not debug_draw_enabled:
		return
	if not _has_map_layers() or origin_hex == Vector2i(-1, -1):
		clear_los()
		return

	los_lines.clear()
	var origin_pos: Vector2 = ground_layer.map_to_local(origin_hex)

	for tx: int in range(grid_size.x):
		for ty: int in range(grid_size.y):
			var target_hex: Vector2i = Vector2i(tx, ty)
			if origin_hex == target_hex:
				continue

			var target_pos: Vector2 = ground_layer.map_to_local(target_hex)

			var los_result: Dictionary = check_los(origin_pos, target_pos, 1, 1, 1, 1)
			
			if los_result["blocked"] == true:
				pass
			los_lines.append({
				"target_pos": target_pos,
				"blocked": los_result["blocked"],
				"block_point": los_result["block_point"],
				"hexes": los_result["hexes"],
				"hindrance_points": _preview_hindrance_crossings(origin_pos, target_pos, los_result)
			})
			
			
	
	queue_redraw()


# Nullable tile coordinates: Vector2i when present, null when cleared.
var _target_hex: Variant
var _origin_hex: Variant
func draw_los(origin_pos: Vector2, target_pos: Vector2) -> void:
	if not _has_map_layers():
		clear_los()
		return
	var target_hex: Vector2i = ground_layer.local_to_map(target_pos)
	origin_hex = ground_layer.local_to_map(origin_pos)
	if origin_hex == target_hex:
		clear_los()
		return
	if target_hex == _target_hex and origin_hex == _origin_hex:
		return
	los_lines.clear()
	_target_hex = target_hex
	_origin_hex = origin_hex
	
	origin_pos = ground_layer.map_to_local(origin_hex)
	target_pos = ground_layer.map_to_local(target_hex)
	var los_result: Dictionary = check_los(origin_pos, target_pos, 1, 1, 1, 1)
	
	if los_result["blocked"] == true:
		pass
	los_lines.append({
		"target_pos": target_pos,
		"blocked": los_result["blocked"],
		"block_point": los_result["block_point"],
		"hexes": los_result["hexes"],
		"hindrance_points": _preview_hindrance_crossings(origin_pos, target_pos, los_result)
	})
	queue_redraw()


func clear_los() -> void:
	los_lines.clear()
	origin_hex = Vector2i(-1, -1)
	_target_hex = null
	_origin_hex = null
	queue_redraw()


func cube_direction_name(cur: Vector3i, nxt: Vector3i) -> int:
	var d: Vector3i = nxt - cur
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
	var dx: int = cb.x - ca.x
	var dy: int = cb.y - ca.y
	var dz: int = cb.z - ca.z

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

	var dx: float = cb.x - ca.x
	var dy: float = cb.y - ca.y
	var dz: float = cb.z - ca.z

	var gcd_val: float = gcd(abs(dx), gcd(abs(dy), abs(dz)))
	if gcd_val == 0:
		return BetweenAxis.NONE

	var ndx: int = int(dx / gcd_val)
	var ndy: int = int(dy / gcd_val)
	var ndz: int = int(dz / gcd_val)

	if ndx == ndy and ndz == -2 * ndx:
		if ndx > 0:
			return BetweenAxis.X_Y_POS
		return BetweenAxis.X_Y_NEG
	elif ndy == ndz and ndx == -2 * ndy:
		if ndy > 0:
			return BetweenAxis.Y_Z_POS
		return BetweenAxis.Y_Z_NEG
	elif ndz == ndx and ndy == -2 * ndz:
		if ndz > 0:
			return BetweenAxis.Z_X_POS
		return BetweenAxis.Z_X_NEG
	else:
		return BetweenAxis.NONE

# Helper: greatest common divisor
func gcd(a: int, b: int) -> int:
	while b != 0:
		var temp: int = b
		b = a % b
		a = temp
	return a


func find_units_at(hex: Vector2i) -> Array[Unit]:
	var units: Array[Unit]
	for u: Unit in Globals.get_units():
		if not u.alive:
			continue
		if u.current_hex == hex:
			units.append(u)
	return units


func get_hex_distance(a: Vector2i, b: Vector2i) -> int:
	var a_cube: Vector3i = ground_layer.map_to_cube(a)
	var b_cube: Vector3i = ground_layer.map_to_cube(b)

	var distance: int = ground_layer.cube_distance(a_cube, b_cube)
	return distance


func get_hex_neighbors(a: Vector2i) -> Array[Vector2i]:
	var cube: Vector3i = ground_layer.map_to_cube(a)
	var cube_neighbors: Array[Vector3i] = ground_layer.cube_neighbors(cube)
	var hex_neighbors: Array[Vector2i]
	for cube_neighbor: Vector3i in cube_neighbors:
		var hex: Vector2i = ground_layer.cube_to_map(cube_neighbor)
		hex_neighbors.append(hex)
	return hex_neighbors


func get_hex_ring(hex_center: Vector2i, radius: int, first_side: TileSet.CellNeighbor = -1) -> Array[Vector2i]:
	var cube_center: Vector3i = ground_layer.map_to_cube(hex_center)
	var cube_ring: Array[Vector3i] = ground_layer.cube_ring(cube_center, radius, first_side)
	var hex_ring: Array[Vector2i]
	for cube: Vector3i in cube_ring:
		hex_ring.append(LOSHelper.ground_layer.cube_to_map(cube))
	return hex_ring


# Atlas coordinates and alternative transforms match the image drawn by TileMapLayer.
func _tile_pixel_is_solid(point: Vector2, layer: TileMapLayer, cell: Vector2i) -> bool:
	if not is_instance_valid(layer) or layer.get_cell_source_id(cell) == -1:
		return false
	var source: TileSetAtlasSource = layer.tile_set.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
	if source == null or source.texture == null:
		return false
	var data: TileData = layer.get_cell_tile_data(cell)
	if (_is_multihex_building(data) or ConnectedWalls.is_barrier(data)) and layer.local_to_map(point) != cell:
		return false
	var region: Rect2i = source.get_tile_texture_region(layer.get_cell_atlas_coords(cell))
	var offset: Vector2 = point - layer.map_to_local(cell) + Vector2(data.texture_origin)
	if data.transpose:
		offset = Vector2(offset.y, offset.x)
	if data.flip_h:
		offset.x = -offset.x
	if data.flip_v:
		offset.y = -offset.y
	var pixel: Vector2i = Vector2i((offset + Vector2(region.size) * 0.5).floor())
	if pixel.x < 0 or pixel.y < 0 or pixel.x >= region.size.x or pixel.y >= region.size.y:
		return false
	if not _texture_images.has(source.texture):
		_texture_images[source.texture] = source.texture.get_image()
	var image: Image = _texture_images[source.texture]
	if image == null:
		return false
	pixel += region.position
	if pixel.x >= image.get_width() or pixel.y >= image.get_height():
		return false
	return image.get_pixelv(pixel).a > 0.1


# Clip the ray to the sprite bounds before visiting its pixels.
func _sprite_entry(origin: Vector2, target: Vector2, layer: TileMapLayer, cell: Vector2i) -> Vector2:
	var source: TileSetAtlasSource = layer.tile_set.get_source(layer.get_cell_source_id(cell)) as TileSetAtlasSource
	var data: TileData = layer.get_cell_tile_data(cell)
	var clip_to_cell: bool = _is_multihex_building(data) or ConnectedWalls.is_barrier(data)
	var region: Rect2i = source.get_tile_texture_region(layer.get_cell_atlas_coords(cell))
	var size: Vector2 = Vector2(region.size)
	if data.transpose:
		size = Vector2(size.y, size.x)
	var center: Vector2 = layer.map_to_local(cell) - Vector2(data.texture_origin)
	var bounds: Rect2 = Rect2(center - size * 0.5, size)
	var delta: Vector2 = target - origin
	var near: float = 0.0
	var far: float = 1.0
	for axis: int in range(2):
		if absf(delta[axis]) < 0.000001:
			if origin[axis] < bounds.position[axis] or origin[axis] >= bounds.end[axis]:
				return Vector2.INF
			continue
		var first: float = (bounds.position[axis] - origin[axis]) / delta[axis]
		var last: float = (bounds.end[axis] - origin[axis]) / delta[axis]
		near = maxf(near, minf(first, last))
		far = minf(far, maxf(first, last))
		if near > far:
			return Vector2.INF
	var steps: int = maxi(1, ceili(delta.length() * (far - near) / STEP_SIZE_PIXELS))
	if not _texture_images.has(source.texture):
		_texture_images[source.texture] = source.texture.get_image()
	var image: Image = _texture_images[source.texture]
	if image == null:
		return Vector2.INF
	for index: int in range(steps + 1):
		var point: Vector2 = origin.lerp(target, lerpf(near, far, float(index) / float(steps)))
		if clip_to_cell and layer.local_to_map(point) != cell:
			continue
		var offset: Vector2 = point - center
		if data.transpose:
			offset = Vector2(offset.y, offset.x)
		if data.flip_h:
			offset.x = -offset.x
		if data.flip_v:
			offset.y = -offset.y
		var pixel: Vector2i = Vector2i((offset + Vector2(region.size) * 0.5).floor())
		if pixel.x < 0 or pixel.y < 0 or pixel.x >= region.size.x or pixel.y >= region.size.y:
			continue
		pixel += region.position
		if pixel.x < image.get_width() and pixel.y < image.get_height() and image.get_pixelv(pixel).a > 0.1:
			return point
	return Vector2.INF


func _is_multihex_building(data: TileData) -> bool:
	# The visible anchor draws the full roof, but each hex owns its LOS slice.
	return data.has_custom_data("building_hexes") and int(data.get_custom_data("building_hexes")) >= 2


func _texture_obstacle_candidates(hexes: Array[Vector3i]) -> Dictionary[Vector2i, bool]:
	if _bake_cache != null:
		return _bake_cache.candidates(hexes)
	var candidates: Dictionary[Vector2i, bool] = {}
	for cube: Vector3i in hexes:
		candidates[ground_layer.cube_to_map(cube)] = true
		# Also sample both sides of a hex spine, using the same ray.
		for neighbor: Vector3i in ground_layer.cube_neighbors(cube):
			candidates[ground_layer.cube_to_map(neighbor)] = true
	return candidates


# Preview-only metadata: one entry per crossed hindering hex, ordered along the ray.
# Reuse the combat pixel test so transparent sprite margins never add a marker.
func get_hindrance_crossings(origin: Vector2, target: Vector2, obstruction: Vector2 = Vector2.INF) -> PackedVector2Array:
	var crossings: PackedVector2Array = PackedVector2Array()
	if not _has_map_layers() or not origin.is_finite() or not target.is_finite():
		return crossings
	var origin_cell: Vector2i = ground_layer.local_to_map(origin)
	var target_cell: Vector2i = ground_layer.local_to_map(target)
	if origin_cell == target_cell:
		return crossings
	var origin_cube: Vector3i = ground_layer.map_to_cube(origin_cell)
	var target_cube: Vector3i = ground_layer.map_to_cube(target_cell)
	var distance: int = ground_layer.cube_distance(origin_cube, target_cube)
	var hexes: Array[Vector3i] = cube_line(origin_cube, target_cube, distance)
	var direction: Vector2 = (target - origin).normalized()
	var limit: float = origin.distance_to(target)
	if obstruction.is_finite():
		limit = clampf((obstruction - origin).dot(direction), 0.0, limit)
	var entries: Array[float] = []
	for cell: Vector2i in _texture_obstacle_candidates(hexes):
		if cell == origin_cell or cell == target_cell or terrain_layer.get_cell_source_id(cell) == -1:
			continue
		var data: TileData = terrain_layer.get_cell_tile_data(cell)
		if not data.has_custom_data("hindrance") or not bool(data.get_custom_data("hindrance")):
			continue
		if data.has_custom_data("blocking") and bool(data.get_custom_data("blocking")):
			continue
		var entry: Vector2 = _sprite_entry(origin, target, terrain_layer, cell)
		if not entry.is_finite():
			continue
		var along_ray: float = (entry - origin).dot(direction)
		if along_ray >= 0.0 and along_ray < limit:
			entries.append(along_ray)
	entries.sort()
	for along_ray: float in entries:
		crossings.append(origin + direction * along_ray)
	return crossings


func _preview_hindrance_crossings(origin: Vector2, target: Vector2, result: Dictionary) -> PackedVector2Array:
	var obstruction: Vector2 = Vector2.INF
	if bool(result["blocked"]):
		obstruction = origin
		if result["block_point"] is Vector2:
			var hit: Vector2 = result["block_point"]
			if hit.is_finite():
				obstruction = hit
	return get_hindrance_crossings(origin, target, obstruction)


func _check_texture_obstacles(origin: Vector2, target: Vector2, hexes: Array[Vector3i], result: Dictionary) -> Dictionary:
	if _bake_cache != null:
		return _bake_cache.check_obstacles(origin, target, hexes, result, STEP_SIZE_PIXELS)
	var candidates: Dictionary[Vector2i, bool] = _texture_obstacle_candidates(hexes)
	var origin_cell: Vector2i = ground_layer.local_to_map(origin)
	var target_cell: Vector2i = ground_layer.local_to_map(target)
	var nearest: float = INF
	for cell: Vector2i in candidates:
		if cell == origin_cell or cell == target_cell:
			continue
		if building_layer.get_cell_source_id(cell) != -1:
			var hit: Vector2 = _sprite_entry(origin, target, building_layer, cell)
			if hit != Vector2.INF and origin.distance_squared_to(hit) < nearest:
				nearest = origin.distance_squared_to(hit)
				result.blocked = true
				result.block_point = hit
				return result
		if terrain_layer.get_cell_source_id(cell) == -1:
			continue
		var data: TileData = terrain_layer.get_cell_tile_data(cell)
		var blocks: bool = data.has_custom_data("blocking") and bool(data.get_custom_data("blocking"))
		var hinders: bool = data.has_custom_data("hindrance") and bool(data.get_custom_data("hindrance"))
		if not blocks and not hinders:
			continue
		var hit: Vector2 = _sprite_entry(origin, target, terrain_layer, cell)
		if hit == Vector2.INF:
			continue
		if hinders:
			result.hindrance += 1
			result.shooter_cover += 1
			result.target_cover += 1
		if blocks and origin.distance_squared_to(hit) < nearest:
			nearest = origin.distance_squared_to(hit)
			result.blocked = true
			result.block_point = hit
			return result
	return result
