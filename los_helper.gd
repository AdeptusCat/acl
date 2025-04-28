extends Node2D

# --- EXPORTED PROPERTIES ---
@export var ground_layer: TileMapLayer
@export var building_layer: TileMapLayer
@export var wall_layer: TileMapLayer
@export var debug_draw_enabled: bool = false

# --- CONSTANTS ---
const FLOOR_HEIGHT_METERS = 3.0
const UNIT_HEIGHT_METERS = 1.5
const STEP_SIZE_PIXELS = 2.0

# --- INTERNAL ---
var origin_hex: Vector2 = Vector2(-1, -1)
var los_lines: Array = []
const GRID_SIZE = 7

# --- PUBLIC FUNCTION ---

func check_los(origin_pos: Vector2, target_pos: Vector2, origin_elevation: int, target_elevation: int, origin_story: int, target_story: int) -> Dictionary:
	var result = {
		"blocked": false,
		"hindrance_count": 0,
		"crossed_wall": false,
		"block_point": null
	}

	var shooter_height = calculate_absolute_height(origin_elevation, origin_story)
	var target_height = calculate_absolute_height(target_elevation, target_story)

	var delta = target_pos - origin_pos
	var distance = delta.length()
	var direction = delta.normalized()
	var steps = int(distance / STEP_SIZE_PIXELS)

	var target_hex_map = ground_layer.local_to_map(target_pos)

	for i in range(steps + 1):
		var sample_point = origin_pos + direction * (i * STEP_SIZE_PIXELS)
		var sample_distance_ratio = (i * STEP_SIZE_PIXELS) / distance
		var los_height_at_sample = lerp(shooter_height, target_height, sample_distance_ratio)

		var sample_hex = ground_layer.local_to_map(sample_point)

		if sample_hex == target_hex_map:
			continue

		if is_sample_point_in_building(sample_point):
			result["blocked"] = true
			result["block_point"] = sample_point
			return result

		if is_sample_point_crossing_wall(sample_point):
			var forward_step = sample_point + direction * 20.0
			var forward_hex = ground_layer.local_to_map(forward_step)

			var sample_neighbors = get_neighboring_hexes(sample_hex)
			if target_hex_map in sample_neighbors and (forward_hex == target_hex_map or sample_hex == target_hex_map):
				continue
			else:
				result["crossed_wall"] = true
				result["blocked"] = true
				result["block_point"] = sample_point
				return result
		
		# --- Crest line blocking (NEW)
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
	if event is InputEventMouseButton and event.pressed: #  and event.button_index == MouseButton.LEFT
		var mouse_pos = event.position
		var hex = ground_layer.local_to_map(mouse_pos)
		origin_hex = hex
		generate_los_lines_for_debug()

func _draw():
	if not debug_draw_enabled:
		return

	if origin_hex == Vector2(-1, -1):
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

func generate_los_lines_for_debug():
	if not debug_draw_enabled:
		return

	los_lines.clear()
	var origin_pos = ground_layer.map_to_local(origin_hex)

	for tx in range(GRID_SIZE):
		for ty in range(GRID_SIZE):
			var target_hex = Vector2(tx, ty)
			if origin_hex == target_hex:
				continue

			var target_pos = ground_layer.map_to_local(target_hex)

			var los_result = check_los(origin_pos, target_pos, 1, 0, 1, 0)

			los_lines.append({
				"target_pos": target_pos,
				"blocked": los_result["blocked"],
				"block_point": los_result["block_point"]
			})

	queue_redraw()
