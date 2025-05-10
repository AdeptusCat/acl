extends Node2D

# --- SETUP ---

@onready var ground_layer = $"../GroundTileMapLayer"
@onready var building_layer = $"../BuildingTileMapLayer"
@onready var wall_layer = $"../WallTileMapLayer"

# Constants
const FLOOR_HEIGHT_METERS = 3.0
const UNIT_HEIGHT_METERS = 1.5
const STEP_SIZE_PIXELS = 2.0

const FULL_BLOCKERS = ["building", "cliff", "rubble"]
const HINDRANCES = ["grain", "orchard", "brush", "smoke"]


var origin_hex: Vector2 = Vector2(-1, -1)  # Initialize invalid
var los_lines = []  # Stores { "target_pos": Vector2, "blocked": bool }
const GRID_SIZE = 7  # 6x6 hexes

# --- FUNCTIONS ---

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
			# Means this point hits the building_tilemap's collision shape
			return true
	return false

func is_sample_point_crossing_wall(sample_point: Vector2) -> bool:
	var space_state = get_world_2d().direct_space_state
	var params = PhysicsPointQueryParameters2D.new()
	params.position = sample_point
	params.collide_with_areas = false
	params.collide_with_bodies = true
	params.collision_mask = 2  # Assuming walls are on layer 1
	var result = space_state.intersect_point(params, 1)

	for item in result:
		if item.collider == wall_layer:
			# Means this point hits the building_tilemap's collision shape
			return true
	return false

func check_los(
	origin_pos: Vector2, target_pos: Vector2,
	origin_elevation: int, target_elevation: int,
	origin_story: int, target_story: int
) -> Dictionary:

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
			# Inside target hex → Ignore walls, ignore buildings blocking
			continue

		# Check if sample hits a real building
		if is_sample_point_in_building(sample_point):
			result["blocked"] = true
			result["block_point"] = sample_point
			return result

		# Check if sample crosses a real wall
		if is_sample_point_crossing_wall(sample_point):
			var forward_step = sample_point + direction * 20.0
			var forward_hex = ground_layer.local_to_map(forward_step)

			# Check if wall is between current hex and target hex
			var sample_neighbors = get_neighboring_hexes(sample_hex)
			if target_hex_map in sample_neighbors and (forward_hex == target_hex_map or sample_hex == target_hex_map):
				# Wall is along hexside into target → ignore
				continue
			else:
				result["crossed_wall"] = true
				result["blocked"] = true
				result["block_point"] = sample_point
				return result

	return result

func get_neighboring_hexes(hex: Vector2i) -> Array:
	# Assuming pointy-topped hex layout (flat sides left/right)
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


func _ready():
	self.z_index = 100
	#await get_tree().process_frame
	
	#check_all_los()

func check_all_los():
	for ox in range(7):
		for oy in range(7):
			var origin_hex = Vector2(ox, oy)
			var origin_pos = ground_layer.map_to_local(origin_hex)

			for tx in range(7):
				for ty in range(7):
					var target_hex = Vector2(tx, ty)

					# Skip if origin and target are the same
					if origin_hex == target_hex:
						continue

					var target_pos = ground_layer.map_to_local(target_hex)

					# Call LOS checker
					var los_result = check_los(
						origin_pos,
						target_pos,
						1,  # origin_elevation
						0,  # target_elevation
						1,  # origin_story
						0   # target_story
					)

					# Print result
					var message = "LOS from (%d,%d) to (%d,%d): " % [ox, oy, tx, ty]
					if los_result["blocked"]:
						print(message, "BLOCKED")
					#elif los_result["hindrance_count"] > 0:
						#print(message, "Degraded by ", los_result["hindrance_count"], " hindrances")
					#else:
						#print(message, "CLEAR")






func _input(event):
	if event is InputEventMouseButton and event.pressed: #  and event.button_index == MouseButton.LEFT
		var mouse_pos = event.position
		var hex = ground_layer.local_to_map(mouse_pos)
		origin_hex = hex
		generate_los_lines()

func generate_los_lines():
	los_lines.clear()

	var origin_pos = ground_layer.map_to_local(origin_hex)

	for tx in range(GRID_SIZE):
		for ty in range(GRID_SIZE):
			var target_hex = Vector2(tx, ty)

			if origin_hex == target_hex:
				continue

			var target_pos = ground_layer.map_to_local(target_hex)

			var los_result = check_los(
				origin_pos,
				target_pos,
				1,  # origin elevation
				0,  # target elevation
				1,  # origin story
				0   # target story
			)

			los_lines.append({
				"target_pos": target_pos,
				"blocked": los_result["blocked"],
				"block_point": los_result["block_point"]  # <-- NEW
			})

	queue_redraw()
	
	
func _draw():
	if origin_hex == Vector2(-1, -1):
		return

	var origin_pos = ground_layer.map_to_local(origin_hex)

	# First: draw all RED (blocked) parts
	for line_data in los_lines:
		if line_data["blocked"]:
			var block_point = line_data["block_point"]
			if block_point == null:
				block_point = origin_pos  # Failsafe

			draw_line(block_point, line_data["target_pos"], Color(1, 0, 0), 2.0)

	# Then: draw all GREEN (clear) parts on top
	for line_data in los_lines:
		var block_point = line_data.get("block_point", null)
		if not line_data["blocked"]:
			draw_line(origin_pos, line_data["target_pos"], Color(0, 1, 0), 2.0)
		else:
			if block_point == null:
				block_point = origin_pos
			draw_line(origin_pos, block_point, Color(0, 1, 0), 2.0)
