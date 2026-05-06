class_name UnitMovement
extends Node

var unit: Unit

# Movement state
var path_hexes: Array[Vector2i] = []
var path_index: int = 0
var target_position: Vector2
var is_moving: bool = false
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
signal crossing_exposed_started
signal new_target_hex(hex: Vector2i)
signal draw_movement_path(from_hex: Vector2i,path: Array[Vector2i])

# Retreat state
var retreating: bool = false
var retreat_distance: int = 3

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
	if is_moving:
		_process_movement(delta)


# ----------------------------------------------------------------------
# BASIC MOVE / PATH
# ----------------------------------------------------------------------

func stop():
	if is_moving:
		_get_terrain_multiplier()
		path_index = 0
		path_hexes.clear()
		move_to_hex(unit.current_hex)
		target_hex = unit.current_hex
		new_target_hex.emit(target_hex)


func move_to_hex(new_hex: Vector2i) -> void:
	_get_terrain_multiplier()
	unit.goal_hex = new_hex
	target_position = LOSHelper.ground_layer.map_to_local(unit.goal_hex)
	is_moving = true
	started_moving.emit()
	draw_movement_path.emit(unit.current_hex, path_hexes)


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
	
	# check if unit entered hex
	if path_index < path_hexes.size():
		var closest_cube: Vector3i = LOSHelper.ground_layer.get_closest_cell_from_local(unit.position)
		var next_cube: Vector3i = LOSHelper.ground_layer.map_to_cube(path_hexes[path_index])
		if closest_cube == next_cube:
			if unit.current_hex != path_hexes[path_index]:
				unit.current_hex = path_hexes[path_index]
				unit.current_cube = LOSHelper.ground_layer.map_to_cube(path_hexes[path_index])
				unit.unit_entered_hex.emit(unit, path_hexes[path_index])
	
	# check if arrived at hex
	if dist <= step:
		# arrive at hex
		unit.position = target_position
		is_moving = false
		stopped_moving.emit()
		
		# here somethings off, the target target_position is where the unit is but the path is another 
		# or it already passed points in the path and is already at target hex but the path is still full of hexes in between
		if path_index < path_hexes.size() - 1:
			# move to next hex
			path_index += 1
			move_to_hex(path_hexes[path_index])
		else:
			# end movement here
			if retreating:
				retreating = false
				unit.retreat_complete.emit(unit.current_hex)
			
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
		# keep is_moving
		unit.position += dir * step
		# debug
		if unit.stress_system.state != STATES.MoraleState.NORMAL:
			var _state: int = unit.stress_system.state


# ----------------------------------------------------------------------
# TERRAIN MULTIPLIER
# ----------------------------------------------------------------------

func _get_terrain_multiplier() -> void:
	if path_hexes.is_empty():
		var hex_to_move_to: Vector2i = unit.current_hex
		var next_terr: int = _get_terrain_type(hex_to_move_to)
		var mf_base = _terrain_mf(next_terr)
		terrain_mult = _mf_to_speed_mult(mf_base)
		#terrain_mult = 1.0
		return
	
	var next_terr: int = _get_terrain_type(path_hexes[path_index])
	var mf_total: float = compute_total_mf(unit.current_hex, path_hexes[path_index], next_terr)
	
	var from: Vector2 = LOSHelper.ground_layer.map_to_local(unit.current_hex)
	var to: Vector2 = LOSHelper.ground_layer.map_to_local(path_hexes[path_index])
	var cover_dict: Dictionary = LOSHelper.check_los(from, to, 1, 1, 1, 1)
	if cover_dict.has("wall_cover"):
		if cover_dict.wall_cover > 0:
			mf_total += 1.0
	
	terrain_mult = _mf_to_speed_mult(mf_total)


# ----------------------------------------------------------------------
# STATE CHANGE FROM MORALE
# ----------------------------------------------------------------------

func state_changed(next: int) -> void:
	var move_mult: float = float(STATES.STATE_MOD[next]["move"])
	_apply_speed(base_speed * move_mult)


func _apply_speed(v: float) -> void:
	move_speed = v


# ----------------------------------------------------------------------
# TERRAIN / MF HELPERS
# ----------------------------------------------------------------------

func _get_terrain_type(hex: Vector2i) -> int:
	var terrain_type: int = TerrainType.OPEN
	if LOSHelper.building_layer.get_cell_source_id(hex) != -1:
		terrain_type = TerrainType.BUILDING
	return terrain_type


func _mf_to_speed_mult(mf_total: float) -> float:
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


func _using_road_rate(_cur_hex: Vector2i, _next_hex: Vector2i) -> bool:
	return false


func _crest_uphill_between(_cur_hex: Vector2i, _next_hex: Vector2i) -> bool:
	return false


func _hexside_cost(_cur_hex: Vector2i, _next_hex: Vector2i) -> float:
	var cost: float = 0.0
	var has_wall: bool = false
	if has_wall:
		cost += mf_wall_hexside
	return cost


func _entering_smoke(_next_hex: Vector2i) -> bool:
	return false


func compute_total_mf(_cur_hex: Vector2i, _next_hex: Vector2i, _next_terr: int) -> float:
	var mf_base: float
	if _using_road_rate(_cur_hex, _next_hex):
		mf_base = 1.0
	else:
		mf_base = _terrain_mf(_next_terr)
	
	var mf_add: float = _hexside_cost(_cur_hex, _next_hex)
	if _entering_smoke(_next_hex):
		mf_add += mf_smoke_enter
	
	var mf_total: float = mf_base + mf_add
	if _crest_uphill_between(_cur_hex, _next_hex):
		mf_total *= crest_uphill_mult
	
	return mf_total
