class_name UnitMovement
extends Node

var unit: Node2D
var ground_map: HexagonTileMapLayer

# Movement state
var path_hexes: Array[Vector2i] = []
var path_index: int = 0
var target_position: Vector2
var moving: bool = false
var move_speed: float = 100.0

# Retreat state
var retreating: bool = false
var retreat_distance := 3
var retreat_target_hex: Vector2i = Vector2i()

signal started_moving
signal stopped_moving


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
	var retreat_map = compute_retreat_hex(current_hex, known_enemies, retreat_distance)
	retreating = true
	retreat_target_hex = retreat_map

	var from_id = ground_map.pathfinding_get_point_id(current_hex)
	var to_id = ground_map.pathfinding_get_point_id(retreat_map)
	var id_path = ground_map.astar.get_id_path(from_id, to_id)

	var cube_path: Array[Vector3i] = []
	for pid in id_path:
		var pos = ground_map.astar.get_point_position(pid)
		cube_path.append(ground_map.local_to_cube(pos))

	follow_cube_path(cube_path)


func compute_retreat_hex(origin_hex: Vector2i, known_enemies: Array, steps: int) -> Vector2i:
	# shortcuts
	var map    = ground_map                          # HexagonTileMapLayer reference
	var ground = LOSHelper.ground_layer          # for map_to_local()
	var build  = LOSHelper.building_layer        # for get_cell_source_id()

	# 1) enemy centroid in pixel‐space
	var centroid = Vector2.ZERO
	var enemy_hexes : Array
	for enemy in known_enemies:
		if not is_instance_valid(enemy):
			continue
		enemy_hexes.append(enemy.current_hex)
	for e_hex in enemy_hexes:
		centroid += ground.map_to_local(e_hex)
	if enemy_hexes.size() > 0:
		centroid /= enemy_hexes.size()

	# 2) all cubes within 'steps'
	var origin_cube = map.map_to_cube(origin_hex)
	var cube_list   = map.cube_range(origin_cube, steps)

	# 3) inline Callable to test “unseen by all enemies”
	var is_unseen = func(test_map_hex: Vector2i) -> bool:
		var tpos = ground.map_to_local(test_map_hex)
		for e_hex in enemy_hexes:
			var epos = ground.map_to_local(e_hex)
			var los  = LOSHelper.check_los(epos, tpos, 1, 0, 1, 0)
			if not los["blocked"]:
				return false
		return true

	# 4) bucket hexes by priority
	var unseen_bld  : Array[Vector2i] = []
	var any_bld     : Array[Vector2i] = []
	var unseen_only : Array[Vector2i] = []
	for c3 in cube_list:
		var m = map.cube_to_map(c3)
		if map.get_cell_source_id(m) == -1:
			continue  # no tile here
		var has_b = build.get_cell_source_id(m) != -1
		var vis   = is_unseen.call(m)
		if has_b and vis:
			unseen_bld.append(m)
		elif has_b:
			any_bld.append(m)
		elif vis:
			unseen_only.append(m)

	# 5) fallback = origin + every reachable hex
	var fallback : Array[Vector2i] = [ origin_hex ]
	for c3 in cube_list:
		fallback.append(map.cube_to_map(c3))

	# 6) choose the pool in priority order
	var pool : Array[Vector2i]
	if unseen_bld.size() > 0:
		pool = unseen_bld
	elif any_bld.size() > 0:
		pool = any_bld
	elif unseen_only.size() > 0:
		pool = unseen_only
	else:
		pool = fallback

	# — new: filter out any hex that is strictly closer to any enemy —
	var safe_pool: Array[Vector2i] = []
	# gather just the enemy hex coords
	enemy_hexes = []
	for e in known_enemies:
		if is_instance_valid(e):
			enemy_hexes.append(e.current_hex)

	for h in pool:
		var moves_closer := false
		for e_hex in enemy_hexes:
			# if h is closer to this enemy than you already are, it's invalid
			if h.distance_to(e_hex) < origin_hex.distance_to(e_hex):
				moves_closer = true
				break
		if not moves_closer:
			safe_pool.append(h)
	# if nothing left, you have no “away” route → die
	if safe_pool.is_empty() or safe_pool[0] == origin_hex:
		#die()
		return origin_hex

	# replace pool with safe options
	pool = safe_pool

	# — now pick from pool as before (e.g. farthest from centroid) —
	var best_hex  = origin_hex
	var best_dist = -1.0
	for h in pool:
		var d = (ground.map_to_local(h) - centroid).length()
		if d > best_dist:
			best_dist = d
			best_hex  = h

	return best_hex
