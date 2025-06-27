class_name UnitMovement
extends Node

var unit: Node2D
var ground_map: HexagonTileMapLayer

# Movement state
var path_hexes: Array[Vector2i] = []
var path_index: int = 0
var target_position: Vector2
var moving: bool = false
var move_speed: float = 50.0

# Retreat state
var retreating: bool = false
var retreat_distance := 3
var retreat_target_hex: Vector2i = Vector2i()

signal started_moving
signal stopped_moving
signal rout_failed

func _init(_unit: Node2D):
	unit = _unit


func process(delta: float):
	if moving:
		_process_movement(delta)


func move_to_hex(new_hex: Vector2i):
	unit.current_hex = new_hex
	target_position = ground_map.map_to_local(new_hex)
	moving = true
	started_moving.emit()
	unit.moved_to_hex.emit(unit, new_hex)

func follow_cube_path(cube_path: Array[Vector3i]):
	path_hexes.clear()
	for c in cube_path:
		path_hexes.append(ground_map.cube_to_map(c))
	if path_hexes.size() > 1:
		path_index = 1
		move_to_hex(path_hexes[path_index])


func begin_retreat(target_hex: Vector2i):
	retreat_target_hex = target_hex
	retreating = true
	var from_id = ground_map.pathfinding_get_point_id(unit.current_hex)
	var to_id = ground_map.pathfinding_get_point_id(target_hex)
	var id_path = ground_map.astar.get_id_path(from_id, to_id)

	var cube_path: Array[Vector3i] = []
	for pid in id_path:
		var pos = ground_map.astar.get_point_position(pid)
		cube_path.append(ground_map.local_to_cube(pos))
	follow_cube_path(cube_path)


func _process_movement(delta: float):
	var dir = (target_position - unit.position).normalized()
	var dist = unit.position.distance_to(target_position)
	var step = move_speed * delta

	if dist <= step:
		unit.position = target_position
		moving = false
		stopped_moving.emit()

		if path_index < path_hexes.size() - 1:
			path_index += 1
			move_to_hex(path_hexes[path_index])
		else:
			if retreating:
				retreating = false
				unit.emit_signal("retreat_complete", unit.current_hex)
			unit.unit_arrived_at_hex.emit(unit.current_hex)
			path_hexes.clear()
			path_index = 0
	else:
		unit.position += dir * step


func rout(current_hex : Vector2i, known_enemies, retreat_distance):
	# careful, known_enemies are now all enemies, visible or not
	var retreat_hex = compute_retreat_hex(current_hex, known_enemies, retreat_distance)
	if retreat_hex == Vector2i.ZERO:
		rout_failed.emit()
		return
	
	retreating = true
	retreat_target_hex = retreat_hex

	var restricted_astar = create_restricted_astar(allowed_hexes)
	var from_id =  restricted_astar.get_closest_point(ground_map.map_to_local(current_hex))
	#var from_id = ground_map.pathfinding_get_point_id(current_hex)
	var to_id =  restricted_astar.get_closest_point(ground_map.map_to_local(retreat_hex))
	#var to_id = ground_map.pathfinding_get_point_id(retreat_hex)
	var id_path = restricted_astar.get_id_path(from_id, to_id)

	#var from_id = ground_map.pathfinding_get_point_id(current_hex)
	#var to_id = ground_map.pathfinding_get_point_id(retreat_map)
	#var id_path = ground_map.astar.get_id_path(from_id, to_id)

	var cube_path: Array[Vector3i] = []
	for pid in id_path:
		var pos = restricted_astar.get_point_position(pid)
		cube_path.append(ground_map.local_to_cube(pos))

	follow_cube_path(cube_path)


#var point_array: Array[Vector2]
var allowed_hexes: Array[Vector2i]
func compute_retreat_hex(origin_hex: Vector2i, known_enemies: Array, steps: int) -> Vector2i:
	var retreat_hex: Vector2i = Vector2i.ZERO
	allowed_hexes.clear()
	allowed_hexes.append(origin_hex)
	var ground_layer = LOSHelper.ground_layer
	var building_layer = LOSHelper.building_layer
	var origin_cube = ground_layer.map_to_cube(origin_hex)
	
	# First check immediate neighbors
	var immediate_neighbors: Array[Vector2i] = get_neighbor_hexes_not_closer_to_enemy(origin_cube, origin_cube, known_enemies)
	for neighbor_hex in immediate_neighbors:
		if building_layer.get_cell_source_id(neighbor_hex) != -1:
			var visible_by_enemy := false
			for enemy in known_enemies:
				var visible_hexes = LOSHelper.los_lookup.get(enemy.current_hex, [])
				if visible_hexes.has(neighbor_hex):
					visible_by_enemy = true
					break
			if not visible_by_enemy:
				return neighbor_hex  # Early return for fast escape
	
	# BFS for further rings
	var visited := {}
	var queue := [origin_hex]
	visited[origin_hex] = true
	var ring := 0
	
	while queue.size() > 0 and retreat_hex == Vector2i.ZERO:
		var level_size = queue.size()
		var added_any := false  # track if we added any new hex this ring
		
		for i in range(level_size):
			var current = queue.pop_front()
			var current_cube = ground_layer.map_to_cube(current)
			
			var next_neighbors = get_neighbor_hexes_not_closer_to_enemy(origin_cube, current_cube, known_enemies)
			for neighbor in next_neighbors:
				if visited.has(neighbor):
					continue
				visited[neighbor] = true
				added_any = true  # we added at least one new neighbor
				
				# Reject if this hex is adjacent to any enemy
				# Get all neighbors of the candidate hex
				var neighbor_cube = ground_layer.map_to_cube(neighbor)
				var adjacent_hexes := []
				for direction_index in [
					TileSet.CELL_NEIGHBOR_TOP_SIDE,
					TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE,
					TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE,
					TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
					TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE,
					TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE,
				]:
					var offset = ground_layer.cube_direction(direction_index)
					var adjacent_cube = neighbor_cube + offset
					adjacent_hexes.append(ground_layer.cube_to_map(adjacent_cube))
				# Check if any enemy is on an adjacent hex
				var is_adjacent_to_enemy := false
				for enemy in known_enemies:
					if adjacent_hexes.has(enemy.current_hex):
						is_adjacent_to_enemy = true
						break
				if is_adjacent_to_enemy:
					continue  # Skip this hex, too close to an enemy
				
				#point_array.append(ground_map.map_to_local(neighbor))
				allowed_hexes.append(neighbor)
				
				if building_layer.get_cell_source_id(neighbor) != -1:
					var visible_by_enemy := false
					for enemy in known_enemies:
						var visible_hexes = LOSHelper.los_lookup.get(enemy.current_hex, [])
						if visible_hexes.has(neighbor):
							visible_by_enemy = true
							break
					if not visible_by_enemy:
						retreat_hex = neighbor
						break
				queue.append(neighbor)
			
			if retreat_hex != Vector2i.ZERO:
				break
		
		if not added_any:
			break  # no new hexes found => no valid retreat path
		ring += 1
	
	# Optional debug draw
	#unit.get_parent().get_parent().draw_points(point_array)
	
	return retreat_hex


func get_neighbor_hexes_not_closer_to_enemy(origin_cube: Vector3i, next_cube_to_check: Vector3i, known_enemies: Array[Node2D]) -> Array[Vector2i]:
	var neighbor_hexes: Array[Vector2i]
	var directions: Array[int] = [
	TileSet.CELL_NEIGHBOR_TOP_SIDE,
	TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE,
	TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE,
	TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
	TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE,
	TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE,
	]
	var ground_layer = LOSHelper.ground_layer
	
	for direction_index in directions:
		var direction_cube = ground_layer.cube_direction(direction_index)
		var neighbor_cube = next_cube_to_check + direction_cube
		var closer_to_enemy: bool = false
		for enemy in known_enemies:
			var enemy_pos_cube = ground_layer.map_to_cube(enemy.current_hex)
			var distance_to_unit_from_origin = ground_layer.cube_distance(origin_cube, enemy_pos_cube)
			var distance_to_unit_from_target = ground_layer.cube_distance(neighbor_cube, enemy_pos_cube)
			if (distance_to_unit_from_target < distance_to_unit_from_origin):
				closer_to_enemy = true
		if not closer_to_enemy:
			neighbor_hexes.append(ground_layer.cube_to_map(neighbor_cube))
	return neighbor_hexes
	
func create_restricted_astar(allowed_hexes: Array[Vector2i]) -> AStar2D:
	var new_astar = AStar2D.new()
	var original = ground_map.astar
	
	var allowed_ids = allowed_hexes.map(func(h): return ground_map.pathfinding_get_point_id(h))
	
	# Copy only allowed points
	for id in allowed_ids:
		var pos = original.get_point_position(id)
		new_astar.add_point(id, pos)
	
	# Copy only connections between allowed points
	for id in allowed_ids:
		var connected_ids = original.get_point_connections(id)
		for conn_id in connected_ids:
			if allowed_ids.has(conn_id) and not new_astar.are_points_connected(id, conn_id):
				new_astar.connect_points(id, conn_id, false)
	
	return new_astar
