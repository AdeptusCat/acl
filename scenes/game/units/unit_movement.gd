class_name UnitMovement
extends Node

var unit: Unit

# Movement state
var path_hexes: Array[Vector2i] = []
var path_index: int = 0
var target_position: Vector2
var moving: bool = false
var move_speed: float = 30.0
var target_hex: Vector2i
@export var base_speed: float = 30.0

# Attack-move specific
var attack_in_progress: bool = false
var in_exposed_phase: bool = false
var covered_path_cubes: Array[Vector3i] = []
var exposed_path_hexes: Array[Vector2i] = []

signal started_moving
signal stopped_moving
signal rout_failed
signal crossing_exposed_started
signal new_target_hex(hex: Vector2i)

# Retreat state
var retreating: bool = false
var retreat_distance: int = 3
var retreat_target_hex: Vector2i = Vector2i.ZERO

var obey_player_orders: bool = true
var stance: int = 0  # 0 stand, 1 crouch, 2 prone, 3 run, 4 withdraw

# --- map ASL-ish terrain to MF (per hex entered) ---
enum TerrainType { OPEN, ROAD, ORCHARD, GRAIN, BRUSH, WOODS, BUILDING }

@export var mf_by_terrain: Array[float] = [
	1.0,  # OPEN
	1.0,  # ROAD
	1.0,  # ORCHARD
	1.5,  # GRAIN
	2.0,  # BRUSH
	2.0,  # WOODS
	2.0,  # BUILDING
]

@export var mf_wall_hexside: float = 1.0
@export var mf_smoke_enter: float = 1.0
@export var crest_uphill_mult: float = 2.0
@export var mf_to_speed_gamma: float = 1.0
@export var mf_speed_floor: float = 0.25
@export var cover_to_move_mult: Array[float] = [1.00, 0.85, 0.70, 0.60]

var terrain_mult: float = 1.0

func _process(delta: float) -> void:
	if moving:
		_process_movement(delta)


# ----------------------------------------------------------------------
# BASIC MOVE / PATH
# ----------------------------------------------------------------------

func stop():
	if moving:
		path_index = 0
		path_hexes.clear()
		move_to_hex(unit.current_hex)
		target_hex = unit.current_hex
		new_target_hex.emit(target_hex)


func move_to_hex(new_hex: Vector2i) -> void:
	get_terrain_multiplier()
	unit.goal_hex = new_hex
	target_position = LOSHelper.ground_layer.map_to_local(unit.goal_hex)
	moving = true
	started_moving.emit()


func follow_cube_path(cube_path: Array[Vector3i]) -> void:
	path_hexes.clear()
	var i: int = 0
	while i < cube_path.size():
		var cube: Vector3i = cube_path[i]
		path_hexes.append(LOSHelper.ground_layer.cube_to_map(cube))
		i += 1
	
	if path_hexes.size() > 1:
		path_index = 1
		move_to_hex(path_hexes[path_index])
	elif path_hexes.size() == 1:
		path_index = 0
		move_to_hex(path_hexes[0])
	if not path_hexes.is_empty():
		target_hex = path_hexes[-1]
		new_target_hex.emit(target_hex)

# ----------------------------------------------------------------------
# ATTACK-MOVE PATH SUPPORT
# ----------------------------------------------------------------------

# covered_path: cubes from A* (safe route)
# exposed_segment: hexes for the final open-ground leg
func set_attack_paths(covered_path: Array[Vector3i], exposed_segment: Array[Vector3i]) -> void:
	attack_in_progress = true
	in_exposed_phase = false
	
	covered_path_cubes.clear()
	exposed_path_hexes.clear()
	
	var i: int = 0
	while i < covered_path.size():
		covered_path_cubes.append(covered_path[i])
		i += 1
	
	i = 0
	while i < exposed_segment.size():
		exposed_path_hexes.append(exposed_segment[i])
		i += 1
	
	# Seed path_hexes with covered part; movement starts with start_covered_phase()
	path_hexes.clear()
	i = 0
	while i < covered_path_cubes.size():
		path_hexes.append(LOSHelper.ground_layer.cube_to_map(covered_path_cubes[i]))
		i += 1


# Called by the action FSM
func start_covered_phase() -> void:
	if path_hexes.size() <= 1:
		attack_in_progress = false
		in_exposed_phase = false
		return
	
	path_index = 1
	move_to_hex(path_hexes[path_index])


# Internal: once covered path finished, switch into exposed segment
func _start_exposed_phase() -> void:
	if exposed_path_hexes.is_empty():
		attack_in_progress = false
		in_exposed_phase = false
		return
	
	in_exposed_phase = true
	path_hexes.clear()
	var i: int = 0
	while i < exposed_path_hexes.size():
		path_hexes.append(exposed_path_hexes[i])
		i += 1
	
	if path_hexes.size() <= 0:
		attack_in_progress = false
		in_exposed_phase = false
		return
	
	path_index = 0
	move_to_hex(path_hexes[path_index])
	crossing_exposed_started.emit()




# ----------------------------------------------------------------------
# MOVEMENT STEP
# ----------------------------------------------------------------------

func _process_movement(delta: float) -> void:
	
	var dir: Vector2 = (target_position - unit.position).normalized()
	var dist: float = unit.position.distance_to(target_position)
	var step: float = move_speed * terrain_mult * delta
	
	if path_index < path_hexes.size():
		var closest_cube: Vector3i = LOSHelper.ground_layer.get_closest_cell_from_local(unit.position)
		var next_cube: Vector3i = LOSHelper.ground_layer.map_to_cube(path_hexes[path_index])
		if closest_cube == next_cube:
			if unit.current_hex != path_hexes[path_index]:
				unit.current_hex = path_hexes[path_index]
				unit.current_cube = LOSHelper.ground_layer.map_to_cube(path_hexes[path_index])
				unit.unit_entered_hex.emit(unit, path_hexes[path_index])
	
	if dist <= step:
		unit.position = target_position
		moving = false
		stopped_moving.emit()
		
		# here somethings off, the target target_position is where the unit is but the path is another 
		# or it already passed points in the path and is already at target hex but the path is still full of hexes in between
		if path_index < path_hexes.size() - 1:
			path_index += 1
			move_to_hex(path_hexes[path_index])
		else:
			# end of this segment
			if retreating:
				retreating = false
				unit.emit_signal("retreat_complete", unit.current_hex)
			
			# If we are in an attack-move and just finished COVERED, go to EXPOSED
			if attack_in_progress and in_exposed_phase == false and not exposed_path_hexes.is_empty():
				_start_exposed_phase()
				return
			
			# Otherwise, end of whole path
			attack_in_progress = false
			in_exposed_phase = false
			path_hexes.clear()
			path_index = 0
			unit.unit_arrived_at_hex.emit(unit.current_hex)
	else:
		unit.position += dir * step
		if unit.stress_system.state != STATES.MoraleState.NORMAL:
			var state: int = unit.stress_system.state
			# hook if needed


# ----------------------------------------------------------------------
# TERRAIN MULTIPLIER
# ----------------------------------------------------------------------

func get_terrain_multiplier() -> void:
	if path_hexes.is_empty():
		terrain_mult = 1.0
		return
	
	var next_terr: int = _get_terrain_type(path_hexes[path_index])
	var mf_total: float = compute_total_mf(unit.current_hex, path_hexes[path_index], next_terr)
	
	var from: Vector2 = LOSHelper.ground_layer.map_to_local(unit.current_hex)
	var to: Vector2 = LOSHelper.ground_layer.map_to_local(path_hexes[path_index])
	var cover_dict: Dictionary = LOSHelper.check_los(from, to, 1, 1, 1, 1)
	if cover_dict.has("wall_cover"):
		if cover_dict.wall_cover > 0:
			mf_total += 1.0
	
	terrain_mult = mf_to_speed_mult(mf_total)


# ----------------------------------------------------------------------
# ROUT / RETREAT (unchanged except for types)
# ----------------------------------------------------------------------

func rout(current_hex: Vector2i, known_enemies: Array[Unit], retreat_distance: int) -> void:
	var retreat_hex: Vector2i = compute_retreat_hex(current_hex, known_enemies, retreat_distance)
	if retreat_hex == Vector2i.ZERO:
		rout_failed.emit()
		return
	
	retreating = true
	retreat_target_hex = retreat_hex
	
	var restricted_astar: AStar2D = create_restricted_astar(allowed_hexes)
	var from_id: int = restricted_astar.get_closest_point(LOSHelper.ground_layer.map_to_local(current_hex))
	var to_id: int = restricted_astar.get_closest_point(LOSHelper.ground_layer.map_to_local(retreat_hex))
	var id_path: PackedInt64Array = restricted_astar.get_id_path(from_id, to_id)
	
	var cube_path: Array[Vector3i] = []
	var i: int = 0
	while i < id_path.size():
		var pid: int = id_path[i]
		var pos: Vector2 = restricted_astar.get_point_position(pid)
		cube_path.append(LOSHelper.ground_layer.local_to_cube(pos))
		i += 1
	
	follow_cube_path(cube_path)


var allowed_hexes: Array[Vector2i] = []

func compute_retreat_hex(origin_hex: Vector2i, known_enemies: Array[Unit], steps: int) -> Vector2i:
	var retreat_hex: Vector2i = Vector2i.ZERO
	allowed_hexes.clear()
	allowed_hexes.append(origin_hex)
	var ground_layer = LOSHelper.ground_layer
	var building_layer = LOSHelper.building_layer
	var origin_cube: Vector3i = ground_layer.map_to_cube(origin_hex)
	
	var immediate_neighbors: Array[Vector2i] = get_neighbor_hexes_not_closer_to_enemy(origin_cube, origin_cube, known_enemies)
	for neighbor_hex in immediate_neighbors:
		if building_layer.get_cell_source_id(neighbor_hex) != -1:
			var visible_by_enemy: bool = false
			for enemy in known_enemies:
				var visible_hexes = LOSHelper.los_lookup.get(enemy.current_hex, [])
				if visible_hexes.has(neighbor_hex):
					visible_by_enemy = true
					break
			if visible_by_enemy == false:
				allowed_hexes.append(neighbor_hex)
				return neighbor_hex
	
	var visited := {}
	var queue: Array[Vector2i] = [origin_hex]
	visited[origin_hex] = true
	var ring: int = 0
	
	while queue.size() > 0 and retreat_hex == Vector2i.ZERO:
		var level_size: int = queue.size()
		var added_any: bool = false
		
		var li: int = 0
		while li < level_size:
			var current: Vector2i = queue.pop_front()
			var current_cube: Vector3i = ground_layer.map_to_cube(current)
			
			var next_neighbors: Array[Vector2i] = get_neighbor_hexes_not_closer_to_enemy(origin_cube, current_cube, known_enemies)
			for neighbor in next_neighbors:
				if visited.has(neighbor):
					continue
				visited[neighbor] = true
				added_any = true
				
				var neighbor_cube: Vector3i = ground_layer.map_to_cube(neighbor)
				var adjacent_hexes: Array[Vector2i] = []
				for direction_index in [
					TileSet.CELL_NEIGHBOR_TOP_SIDE,
					TileSet.CELL_NEIGHBOR_TOP_RIGHT_SIDE,
					TileSet.CELL_NEIGHBOR_BOTTOM_RIGHT_SIDE,
					TileSet.CELL_NEIGHBOR_BOTTOM_SIDE,
					TileSet.CELL_NEIGHBOR_BOTTOM_LEFT_SIDE,
					TileSet.CELL_NEIGHBOR_TOP_LEFT_SIDE,
				]:
					var offset: Vector3i = ground_layer.cube_direction(direction_index)
					var adjacent_cube: Vector3i = neighbor_cube + offset
					adjacent_hexes.append(ground_layer.cube_to_map(adjacent_cube))
				
				var is_adjacent_to_enemy: bool = false
				for enemy in known_enemies:
					if adjacent_hexes.has(enemy.current_hex):
						is_adjacent_to_enemy = true
						break
				if is_adjacent_to_enemy:
					continue
				
				allowed_hexes.append(neighbor)
				
				if building_layer.get_cell_source_id(neighbor) != -1:
					var visible_by_enemy: bool = false
					for enemy in known_enemies:
						var visible_hexes = LOSHelper.los_lookup.get(enemy.current_hex, [])
						if visible_hexes.has(neighbor):
							visible_by_enemy = true
							break
					if visible_by_enemy == false:
						retreat_hex = neighbor
						break
				queue.append(neighbor)
			
			if retreat_hex != Vector2i.ZERO:
				break
			
			li += 1
		
		if added_any == false:
			break
		ring += 1
	
	return retreat_hex


func get_neighbor_hexes_not_closer_to_enemy(origin_cube: Vector3i, next_cube_to_check: Vector3i, known_enemies: Array[Unit]) -> Array[Vector2i]:
	var neighbor_hexes: Array[Vector2i] = []
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
		var direction_cube: Vector3i = ground_layer.cube_direction(direction_index)
		var neighbor_cube: Vector3i = next_cube_to_check + direction_cube
		var closer_to_enemy: bool = false
		for enemy in known_enemies:
			var enemy_pos_cube: Vector3i = ground_layer.map_to_cube(enemy.current_hex)
			var distance_to_unit_from_origin: int = ground_layer.cube_distance(origin_cube, enemy_pos_cube)
			var distance_to_unit_from_target: int = ground_layer.cube_distance(neighbor_cube, enemy_pos_cube)
			if distance_to_unit_from_target < distance_to_unit_from_origin:
				closer_to_enemy = true
		if closer_to_enemy == false:
			neighbor_hexes.append(ground_layer.cube_to_map(neighbor_cube))
	
	return neighbor_hexes


func create_restricted_astar(allowed_hexes: Array[Vector2i]) -> AStar2D:
	var new_astar: AStar2D = AStar2D.new()
	var original: AStar2D = Globals.astars[unit.team]
	
	var allowed_ids: Array[int] = []
	var i: int = 0
	while i < allowed_hexes.size():
		allowed_ids.append(LOSHelper.ground_layer.pathfinding_get_point_id(allowed_hexes[i]))
		i += 1
	
	for id in allowed_ids:
		var pos: Vector2 = original.get_point_position(id)
		new_astar.add_point(id, pos)
	
	for id in allowed_ids:
		var connected_ids: PackedInt64Array = original.get_point_connections(id)
		var j: int = 0
		while j < connected_ids.size():
			var conn_id: int = connected_ids[j]
			if allowed_ids.has(conn_id) and new_astar.are_points_connected(id, conn_id) == false:
				new_astar.connect_points(id, conn_id, false)
			j += 1
	
	return new_astar


# ----------------------------------------------------------------------
# STATE CHANGE FROM MORALE
# ----------------------------------------------------------------------

func state_changed(next: int) -> void:
	var move_mult: float = float(STATES.STATE_MOD[next]["move"])
	_apply_speed(base_speed * move_mult)


func _apply_speed(v: float) -> void:
	move_speed = v


func _set_stance(s: int) -> void:
	stance = s


# ----------------------------------------------------------------------
# TERRAIN / MF HELPERS
# ----------------------------------------------------------------------

func _get_terrain_type(hex: Vector2i) -> int:
	var terrain_type: int = TerrainType.OPEN
	if LOSHelper.building_layer.get_cell_source_id(hex) != -1:
		terrain_type = TerrainType.BUILDING
	return terrain_type


func mf_to_speed_mult(mf_total: float) -> float:
	var safe_mf: float = mf_total
	if safe_mf < 0.001:
		safe_mf = 0.001
	var mult: float = pow(1.0 / safe_mf, mf_to_speed_gamma)
	if mult < mf_speed_floor:
		mult = mf_speed_floor
	if mult > 1.0:
		mult = 1.0
	return mult


func _terrain_mf(t: int) -> float:
	var idx: int = t
	if idx < 0:
		idx = 0
	if idx > mf_by_terrain.size() - 1:
		idx = mf_by_terrain.size() - 1
	return float(mf_by_terrain[idx])


func _blend_mult(cur_mult: float, next_mult: float, alpha: float) -> float:
	if alpha < 0.0:
		alpha = 0.0
	if alpha > 1.0:
		alpha = 1.0
	return cur_mult * (1.0 - alpha) + next_mult * alpha


func _using_road_rate(cur_hex: Vector2i, next_hex: Vector2i) -> bool:
	return false


func _crest_uphill_between(cur_hex: Vector2i, next_hex: Vector2i) -> bool:
	return false


func _hexside_cost(cur_hex: Vector2i, next_hex: Vector2i) -> float:
	var cost: float = 0.0
	var has_wall: bool = false
	if has_wall:
		cost += mf_wall_hexside
	return cost


func _entering_smoke(next_hex: Vector2i) -> bool:
	return false


func compute_total_mf(cur_hex: Vector2i, next_hex: Vector2i, next_terr: int) -> float:
	var mf_base: float
	if _using_road_rate(cur_hex, next_hex):
		mf_base = 1.0
	else:
		mf_base = _terrain_mf(next_terr)
	
	var mf_add: float = _hexside_cost(cur_hex, next_hex)
	if _entering_smoke(next_hex):
		mf_add += mf_smoke_enter
	
	var mf_total: float = mf_base + mf_add
	if _crest_uphill_between(cur_hex, next_hex):
		mf_total *= crest_uphill_mult
	
	return mf_total
