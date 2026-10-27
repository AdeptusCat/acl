class_name UnitMovement
extends Node

var unit: Unit
const REFERENCE_TILE_SIZE: float = 64.0

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
var pending_recenter: bool = false

func _process(delta: float) -> void:
	if pending_recenter:
		resume_centering()
	if is_moving:
		_process_movement(delta)


# ----------------------------------------------------------------------
# BASIC MOVE / PATH
# ----------------------------------------------------------------------

func stop() -> void:
	_clear_path_state()
	if not unit.is_active() or unit.surrendered or unit.in_close_combat or _is_pinned():
		# Combat locks the occupied hex immediately, without recentering or arrival callbacks.
		pending_recenter = unit.is_active() and not unit.surrendered and is_instance_valid(LOSHelper.ground_layer) and unit.position.distance_to(LOSHelper.ground_layer.map_to_local(unit.current_hex)) > 0.1
		var was_moving: bool = is_moving or unit.is_moving
		is_moving = false
		unit.is_moving = false
		unit.goal_hex = unit.current_hex
		target_hex = unit.current_hex
		target_position = unit.position
		if was_moving:
			stopped_moving.emit()
		new_target_hex.emit(target_hex)
		return
	pending_recenter = false
	if unit.position.distance_to(LOSHelper.ground_layer.map_to_local(unit.current_hex)) > 0.1:
		_start_move_to_hex(unit.current_hex)
		target_hex = unit.current_hex
		new_target_hex.emit(target_hex)
	else:
		var was_moving: bool = is_moving or unit.is_moving
		is_moving = false
		unit.is_moving = false
		unit.goal_hex = unit.current_hex
		target_hex = unit.current_hex
		target_position = LOSHelper.ground_layer.map_to_local(unit.current_hex)
		if was_moving:
			stopped_moving.emit()
		new_target_hex.emit(target_hex)


func resume_centering() -> void:
	if not pending_recenter:
		return
	if not unit.is_active() or unit.surrendered:
		pending_recenter = false
		return
	if unit.in_close_combat or _is_pinned() or not is_instance_valid(LOSHelper.ground_layer):
		return
	pending_recenter = false
	target_hex = unit.current_hex
	_start_move_to_hex(unit.current_hex)
	new_target_hex.emit(target_hex)


func remaining_waypoints() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not unit.is_active() or unit.surrendered:
		return result
	if not is_moving and not attack_in_progress:
		return result
	if path_hexes.is_empty():
		result.append(unit.goal_hex)
	else:
		for index: int in range(path_index, path_hexes.size()):
			result.append(path_hexes[index])
	if attack_in_progress and not in_exposed_phase:
		for hex: Vector2i in exposed_path_hexes:
			if result.is_empty() or result[-1] != hex:
				result.append(hex)
	return result


func move_to_hex(new_hex: Vector2i) -> void:
	_clear_path_state()
	_start_move_to_hex(new_hex)


func _start_move_to_hex(new_hex: Vector2i) -> void:
	if not unit.is_active() or unit.surrendered or unit.in_close_combat or _is_pinned():
		stop()
		return
	pending_recenter = false
	_get_terrain_multiplier()
	unit.goal_hex = new_hex
	target_position = LOSHelper.ground_layer.map_to_local(unit.goal_hex)
	is_moving = true
	started_moving.emit()
	draw_movement_path.emit(unit.current_hex, path_hexes)


func follow_cube_path(cube_path: Array[Vector3i]) -> void:
	if _is_pinned():
		stop()
		return
	_clear_path_state()
	var i: int = 0
	while i < cube_path.size():
		var cube: Vector3i = cube_path[i]
		path_hexes.append(LOSHelper.ground_layer.cube_to_map(cube))
		i += 1
	
	if path_hexes.size() > 1:
		path_index = 1
		_start_move_to_hex(path_hexes[path_index])
	elif path_hexes.size() == 1:
		path_index = 0
		_start_move_to_hex(path_hexes[0])
	else:
		stop()
	if not path_hexes.is_empty():
		target_hex = path_hexes[-1]
		new_target_hex.emit(target_hex)


func _clear_path_state() -> void:
	path_hexes.clear()
	path_index = 0
	attack_in_progress = false
	in_exposed_phase = false
	covered_path_cubes.clear()
	exposed_path_hexes.clear()
	retreating = false


func replace_remaining_move_path(path: Array[Vector2i]) -> void:
	path_hexes = path.duplicate()
	path_index = 1
	_start_move_to_hex(path_hexes[path_index])


# ----------------------------------------------------------------------
# ATTACK-MOVE PATH SUPPORT
# ----------------------------------------------------------------------

# covered_path: cubes from A* (safe route)
# exposed_segment: cubes for the final open-ground leg
func set_attack_paths(covered_path: Array[Vector3i], exposed_segment: Array[Vector3i]) -> void:
	if unit.in_close_combat or _is_pinned():
		stop()
		return
	_clear_path_state()
	is_moving = false
	attack_in_progress = true
	
	var i: int = 0
	while i < covered_path.size():
		covered_path_cubes.append(covered_path[i])
		i += 1
	
	i = 0
	while i < exposed_segment.size():
		exposed_path_hexes.append(LOSHelper.ground_layer.cube_to_map(exposed_segment[i]))
		i += 1
	
	# Seed path_hexes with covered part; movement starts with start_covered_phase()
	path_hexes.clear()
	i = 0
	while i < covered_path_cubes.size():
		path_hexes.append(LOSHelper.ground_layer.cube_to_map(covered_path_cubes[i]))
		i += 1


# Called by the action FSM
func start_covered_phase() -> void:
	if not attack_in_progress:
		return
	if path_hexes.size() <= 1:
		_start_exposed_phase()
		return
	
	path_index = 1
	_start_move_to_hex(path_hexes[path_index])


# Internal: once covered path finished, switch into exposed segment
func _start_exposed_phase() -> void:
	if unit.in_close_combat or _is_pinned():
		stop()
		return
	if not attack_in_progress:
		return
	if exposed_path_hexes.is_empty():
		_clear_path_state()
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
	_start_move_to_hex(path_hexes[path_index])
	crossing_exposed_started.emit()




# ----------------------------------------------------------------------
# MOVEMENT STEP
# ----------------------------------------------------------------------

func _process_movement(delta: float) -> void:
	if not is_moving:
		return
	if not unit.is_active() or unit.surrendered or unit.in_close_combat or _is_pinned():
		stop()
		return
	var dir: Vector2 = (target_position - unit.position).normalized()
	var dist: float = unit.position.distance_to(target_position)
	var step: float = move_speed * _movement_scale() * terrain_mult * delta
	
	# check if arrived at hex
	if dist <= step:
		# arrive at hex
		unit.position = target_position
		_update_current_hex(unit.goal_hex)
		if not unit.is_active():
			return
		# Hex-entry signals can synchronously admit this unit to close combat.
		if unit.in_close_combat:
			stop()
			return
		if MovementSystem.replan_at_boundary(unit):
			return
		is_moving = false
		stopped_moving.emit()
		
		# here somethings off, the target target_position is where the unit is but the path is another 
		# or it already passed points in the path and is already at target hex but the path is still full of hexes in between
		if path_index < path_hexes.size() - 1:
			# move to next hex
			path_index += 1
			_start_move_to_hex(path_hexes[path_index])
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
			_clear_path_state()
			unit.unit_arrived_at_hex.emit(unit.current_hex)
	else:
		# keep is_moving
		unit.position += dir * step
		_update_current_hex(LOSHelper.ground_layer.local_to_map(unit.position))
		# debug
		if unit.stress_system.state != STATES.MoraleState.NORMAL:
			var _state: int = unit.stress_system.state


func _update_current_hex(hex: Vector2i) -> void:
	if unit.current_hex == hex:
		return
	unit.current_hex = hex
	unit.current_cube = LOSHelper.ground_layer.map_to_cube(hex)
	unit.unit_entered_hex.emit(unit, hex)


# ----------------------------------------------------------------------
# TERRAIN MULTIPLIER
# ----------------------------------------------------------------------

func _get_terrain_multiplier() -> void:
	if path_hexes.is_empty():
		var hex_to_move_to: Vector2i = unit.current_hex
		var next_terr: int = _get_terrain_type(hex_to_move_to)
		var mf_base: float = _terrain_mf(next_terr)
		terrain_mult = _mf_to_speed_mult(mf_base)
		#terrain_mult = 1.0
		return
	
	terrain_mult = _mf_to_speed_mult(crossing_movement_factor(unit.current_hex, path_hexes[path_index]))


func crossing_movement_factor(from_hex: Vector2i, to_hex: Vector2i) -> float:
	var factor: float = compute_total_mf(from_hex, to_hex, _get_terrain_type(to_hex))
	var record: Dictionary = LOSHelper.los_lookup.get(from_hex, {}).get(to_hex, {})
	if not record.has("wall_cover") and is_instance_valid(LOSHelper.wall_layer) and is_instance_valid(LOSHelper.building_layer):
		record = LOSHelper.check_los(LOSHelper.ground_layer.map_to_local(from_hex), LOSHelper.ground_layer.map_to_local(to_hex), 1, 1, 1, 1)
	if float(record.get("wall_cover", 0.0)) > 0.0:
		factor += mf_wall_hexside
	return factor


func estimate_crossing_seconds(from_hex: Vector2i, to_hex: Vector2i, from_position: Vector2 = Vector2.INF) -> float:
	if not from_position.is_finite():
		from_position = LOSHelper.ground_layer.map_to_local(from_hex)
	return estimate_travel_seconds(from_position, LOSHelper.ground_layer.map_to_local(to_hex), crossing_movement_factor(from_hex, to_hex))


# ----------------------------------------------------------------------
# STATE CHANGE FROM MORALE
# ----------------------------------------------------------------------

func state_changed(next: int) -> void:
	var move_mult: float = float(STATES.STATE_MOD[next]["move"])
	_apply_speed(base_speed * move_mult)
	if next == STATES.MoraleState.PINNED:
		stop()
	else:
		resume_centering()


func _is_pinned() -> bool:
	return unit.stress_system != null and unit.stress_system.state == STATES.MoraleState.PINNED


func _apply_speed(v: float) -> void:
	move_speed = v


# ----------------------------------------------------------------------
# TERRAIN / MF HELPERS
# ----------------------------------------------------------------------

func _get_terrain_type(hex: Vector2i) -> int:
	var terrain_type: int = TerrainType.OPEN
	if is_instance_valid(LOSHelper.building_layer) and LOSHelper.building_layer.get_cell_source_id(hex) != -1:
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


func estimate_travel_seconds(from: Vector2, to: Vector2, movement_factor: float) -> float:
	var speed: float = move_speed * _movement_scale() * _mf_to_speed_mult(movement_factor)
	if speed <= 0.0:
		return INF
	return from.distance_to(to) / speed


func _movement_scale() -> float:
	if not is_instance_valid(LOSHelper.ground_layer) or LOSHelper.ground_layer.tile_set == null:
		return 1.0
	# Art resolution changes world distances, while a hex crossing keeps its duration.
	return float(LOSHelper.ground_layer.tile_set.tile_size.x) / REFERENCE_TILE_SIZE


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
