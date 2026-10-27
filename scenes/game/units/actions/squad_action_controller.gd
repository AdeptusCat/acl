extends Node
class_name SquadActionController

enum SquadActionState {
	NO_ORDER,
	MOVING_TO_POSITION,
	ESTABLISHING_POSITION,
	HOLDING_POSITION,
	ADVANCING,
	CROSSING_EXPOSED,
	LOCAL_FALLBACK,
	ROUTING,
	REGROUPING,
}

enum MoraleState {
	NORMAL,
	CAUTIOUS,
	PINNED,
	PANIC,
	COMBAT_INEFFECTIVE,
}

var objective_hex: Vector2i

var unit: Unit
var movement: UnitMovement
var squad_fire: SquadFireController
var stress: StressController
var ui: UnitUi

var action_state: int = SquadActionState.NO_ORDER
var action_order_id: int = 0
var order_queue: SquadOrderQueue

var withdraw_hex: Vector2i = Vector2i.ZERO
var attack_hex: Vector2i = Vector2i.ZERO

var has_take_and_hold_flag: bool = false
var has_attack_flag: bool = false
var has_withdraw_flag: bool = false

var establishing_timer: Timer
var regroup_timer: Timer


signal action_state_changed(prev: int, next: int)
signal rout_failed



func init(p_unit: Unit, p_movement: UnitMovement, p_squad_fire: SquadFireController, p_stress: StressController, p_ui: UnitUi) -> void:
	unit = p_unit
	movement = p_movement
	if not movement:
		pass
	squad_fire = p_squad_fire
	stress = p_stress
	ui = p_ui
	order_queue = SquadOrderQueue.new()
	order_queue.unit = unit
	order_queue.set_process(false)
	add_child(order_queue)
	
	establishing_timer = Timer.new()
	establishing_timer.one_shot = true
	establishing_timer.wait_time = 3.0
	add_child(establishing_timer)
	establishing_timer.timeout.connect(_on_establishing_timer_timeout)
	
	regroup_timer = Timer.new()
	regroup_timer.one_shot = true
	regroup_timer.wait_time = 5.0
	add_child(regroup_timer)
	regroup_timer.timeout.connect(_on_regroup_timer_timeout)


func _set_action_state(next: int) -> void:
	var prev: int = action_state
	if prev == next:
		return
	
	_exit_action_state(prev)
	action_state = next
	_enter_action_state(prev, next)
	action_state_changed.emit(prev, next)


func _exit_action_state(state: int) -> void:
	match state:
		SquadActionState.ESTABLISHING_POSITION:
			if establishing_timer.is_stopped() == false:
				establishing_timer.stop()
		SquadActionState.REGROUPING:
			if regroup_timer.is_stopped() == false:
				regroup_timer.stop()
		_:
			pass


func _enter_action_state(_prev: int, state: int) -> void:
	match state:
		SquadActionState.NO_ORDER:
			_clear_order_context()
			movement.is_moving = false
			squad_fire.clear_target()
		
		SquadActionState.MOVING_TO_POSITION:
			pass
		
		SquadActionState.ESTABLISHING_POSITION:
			_start_establishing_timer()
		
		SquadActionState.HOLDING_POSITION:
			if has_attack_flag:
				squad_fire.set_target_hex(attack_hex)
			else:
				#squad_fire.set_target_hex(Globals.objective_hexes[unit.team][0])
				squad_fire.clear_target()
				
		
		SquadActionState.ADVANCING:
			pass
		
		SquadActionState.CROSSING_EXPOSED:
			pass
		
		SquadActionState.LOCAL_FALLBACK:
			pass
		
		SquadActionState.ROUTING:
			squad_fire.clear_target()
		
		SquadActionState.REGROUPING:
			movement.is_moving = false
			_start_regroup_timer()
		
		_:
			pass

# ----------------------------------------------------------------------
# ORDER API
# ----------------------------------------------------------------------

func give_defend_area_order(target_hex: Vector2i, path: Array[Vector3i]) -> void:
	if not unit.is_active() or unit.in_close_combat:
		return
	if order_queue != null:
		order_queue.cancel()
	action_order_id += 1
	
	objective_hex = target_hex
	withdraw_hex = Vector2i.ZERO
	attack_hex = Vector2i.ZERO
	
	has_take_and_hold_flag = true
	has_attack_flag = false
	has_withdraw_flag = false
	
	_start_move_on_path(path)
	_set_action_state(SquadActionState.MOVING_TO_POSITION)


func give_move_to_hex_order(target_hex: Vector2i, path: Array[Vector3i], take_and_hold: bool) -> void:
	if not unit.is_active() or unit.in_close_combat:
		return
	if order_queue != null:
		order_queue.cancel()
	action_order_id += 1
	
	objective_hex = target_hex
	withdraw_hex = Vector2i.ZERO
	attack_hex = Vector2i.ZERO
	
	has_take_and_hold_flag = take_and_hold
	has_attack_flag = false
	has_withdraw_flag = false
	
	_start_move_on_path(path)
	_set_action_state(SquadActionState.MOVING_TO_POSITION)


func give_attack_hex_order(target_hex: Vector2i, covered_path: Array[Vector3i], exposed_segment: Array[Vector3i]) -> void:
	if not unit.is_active() or unit.in_close_combat:
		return
	if order_queue != null:
		order_queue.cancel()
	action_order_id += 1
	
	objective_hex = target_hex
	attack_hex = target_hex
	withdraw_hex = Vector2i.ZERO
	
	has_attack_flag = true
	has_withdraw_flag = false
	has_take_and_hold_flag = true
	
	_start_attack_covered_phase(covered_path, exposed_segment)
	_set_action_state(SquadActionState.MOVING_TO_POSITION)


func give_withdraw_to_hex_order(target_hex: Vector2i, path: Array[Vector3i]) -> void:
	if not unit.is_active() or unit.in_close_combat:
		return
	if order_queue != null:
		order_queue.cancel()
	action_order_id += 1
	
	withdraw_hex = target_hex
	objective_hex = target_hex
	attack_hex = Vector2i.ZERO
	
	has_withdraw_flag = true
	has_attack_flag = false
	has_take_and_hold_flag = true
	
	_set_action_state(SquadActionState.LOCAL_FALLBACK)
	_start_move_on_path(path)


func give_hold_order() -> void:
	if not unit.is_active():
		return
	if order_queue != null:
		order_queue.cancel()
	action_order_id += 1
	
	objective_hex = unit.current_hex
	withdraw_hex = Vector2i.ZERO
	attack_hex = Vector2i.ZERO
	
	has_take_and_hold_flag = true
	has_attack_flag = false
	has_withdraw_flag = false
	
	movement.stop()
	_set_action_state(SquadActionState.HOLDING_POSITION)


func clear_orders() -> void:
	if order_queue != null:
		order_queue.cancel()
	action_order_id += 1
	_set_action_state(SquadActionState.NO_ORDER)
	movement.stop()

# ----------------------------------------------------------------------
# MOVEMENT HELPERS
# ----------------------------------------------------------------------

func _start_move_on_path(path: Array[Vector3i]) -> void:
	if path.is_empty():
		movement.stop()
		_set_action_state(SquadActionState.NO_ORDER)
		return
	
	#movement.set_path(path)
	movement.follow_cube_path(path)
	#movement.start()


func _start_attack_covered_phase(covered_path: Array[Vector3i], exposed_segment: Array[Vector3i]) -> void:
	movement.set_attack_paths(covered_path, exposed_segment)
	movement.start_covered_phase()


func _start_establishing_timer() -> void:
	if establishing_timer.is_stopped() == false:
		establishing_timer.stop()
	establishing_timer.start()


func _start_regroup_timer() -> void:
	if regroup_timer.is_stopped() == false:
		regroup_timer.stop()
	regroup_timer.start()


func _clear_order_context() -> void:
	objective_hex = Vector2i.ZERO
	withdraw_hex = Vector2i.ZERO
	attack_hex = Vector2i.ZERO
	
	has_take_and_hold_flag = false
	has_attack_flag = false
	has_withdraw_flag = false


func _order_still_valid() -> bool:
	var valid: bool = true
	return valid

# ----------------------------------------------------------------------
# EVENTS FROM UNIT / MOVEMENT
# ----------------------------------------------------------------------

func on_started_moving() -> void:
	# Returning to the occupied hex center does not create a new order.
	if action_state == SquadActionState.NO_ORDER and movement.path_hexes.is_empty() and unit.goal_hex == unit.current_hex:
		return
	if action_state == SquadActionState.NO_ORDER or action_state == SquadActionState.HOLDING_POSITION:
		_set_action_state(SquadActionState.MOVING_TO_POSITION)


func on_stopped_moving() -> void:
	if not unit.is_active():
		return
	match action_state:
		SquadActionState.MOVING_TO_POSITION, SquadActionState.CROSSING_EXPOSED:
			if unit.current_hex == objective_hex:
				_set_action_state(SquadActionState.ESTABLISHING_POSITION)
			else:
				_set_action_state(SquadActionState.HOLDING_POSITION)
		SquadActionState.ROUTING:
			pass
		SquadActionState.LOCAL_FALLBACK:
			if unit.current_hex == withdraw_hex:
				_set_action_state(SquadActionState.ESTABLISHING_POSITION)
			else:
				_set_action_state(SquadActionState.HOLDING_POSITION)
		_:
			pass


func on_reached_hex(hex: Vector2i) -> void:
	if not unit.is_active() or unit.surrendered or unit.in_close_combat or movement.is_moving:
		return
	if hex != unit.current_hex:
		return
	# This event completes the whole path; stopped_moving also fires at waypoints.
	on_stopped_moving()


func on_retreat_complete(_retreat_hex: Vector2i) -> void:
	if not unit.is_active():
		return
	if action_state == SquadActionState.ROUTING:
		_set_action_state(SquadActionState.REGROUPING)

# ----------------------------------------------------------------------
# TIMERS
# ----------------------------------------------------------------------

func _on_establishing_timer_timeout() -> void:
	if action_state == SquadActionState.ESTABLISHING_POSITION:
		_set_action_state(SquadActionState.HOLDING_POSITION)


func _on_regroup_timer_timeout() -> void:
	if action_state != SquadActionState.REGROUPING:
		return
	
	if _order_still_valid():
		_set_action_state(SquadActionState.HOLDING_POSITION)
	else:
		_set_action_state(SquadActionState.NO_ORDER)

# ----------------------------------------------------------------------
# MORALE INTEGRATION
# ----------------------------------------------------------------------

func on_morale_state_changed(_prev: int, next: int) -> void:
	ui.state_changed(next)
	
	var rof_mult: float = 1.0
	if next == MoraleState.NORMAL:
		rof_mult = 1.0
	elif next == MoraleState.CAUTIOUS:
		rof_mult = 0.75
	elif next == MoraleState.PINNED:
		rof_mult = 0.5
	elif next == MoraleState.PANIC:
		rof_mult = 0.0
	elif next == MoraleState.COMBAT_INEFFECTIVE:
		rof_mult = 0.0
	
	if rof_mult < 0.05:
		rof_mult = 0.05
	
	squad_fire.seconds_per_volley = squad_fire.base_seconds_per_volley / rof_mult
	
	if next == MoraleState.PANIC:
		if order_queue != null:
			order_queue.cancel()
		if action_state != SquadActionState.ROUTING:
			if not unit.surrendered:
				_start_rout()
				_set_action_state(SquadActionState.ROUTING)
		return
	
	if next == MoraleState.PINNED:
		if action_state == SquadActionState.MOVING_TO_POSITION or action_state == SquadActionState.CROSSING_EXPOSED or action_state == SquadActionState.ADVANCING:
			movement.stop()
			_set_action_state(SquadActionState.HOLDING_POSITION)


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
	var ground_layer: HexagonTileMapLayer = LOSHelper.ground_layer
	
	for direction_index: int in directions:
		var direction_cube: Vector3i = ground_layer.cube_direction(direction_index)
		var neighbor_cube: Vector3i = next_cube_to_check + direction_cube
		var closer_to_enemy: bool = false
		for enemy: Unit in known_enemies:
			var enemy_pos_cube: Vector3i = ground_layer.map_to_cube(enemy.current_hex)
			var distance_to_unit_from_origin: int = ground_layer.cube_distance(origin_cube, enemy_pos_cube)
			var distance_to_unit_from_target: int = ground_layer.cube_distance(neighbor_cube, enemy_pos_cube)
			if distance_to_unit_from_target < distance_to_unit_from_origin:
				closer_to_enemy = true
		if closer_to_enemy == false:
			neighbor_hexes.append(ground_layer.cube_to_map(neighbor_cube))
	
	return neighbor_hexes

var allowed_hexes: Array[Vector2i] = []
var _retreat_known_enemies: Array[Unit] = []

func compute_retreat_hex(origin_hex: Vector2i, known_enemies: Array[Unit], max_steps: int) -> Vector2i:
	allowed_hexes.clear()
	allowed_hexes.append(origin_hex)
	_retreat_known_enemies.assign(known_enemies)

	var ground_layer: TileMapLayer = LOSHelper.ground_layer
	var origin_cube: Vector3i = ground_layer.map_to_cube(origin_hex)
	var retreat_hex: Vector2i = origin_hex
	var best_priority: int = 5
	var best_depth: int = 0

	var visited: Dictionary = {}
	var queue: Array[Vector2i] = []
	var depth_queue: Array[int] = []

	queue.append(origin_hex)
	depth_queue.append(0)
	visited[origin_hex] = true

	var queue_index: int = 0

	while queue_index < queue.size():
		var current: Vector2i = queue[queue_index]
		var current_depth: int = depth_queue[queue_index]
		queue_index += 1

		if current_depth >= max_steps:
			continue

		var current_cube: Vector3i = ground_layer.map_to_cube(current)

		var next_neighbors: Array[Vector2i] = get_neighbor_hexes_not_closer_to_enemy(
			origin_cube,
			current_cube,
			known_enemies
		)

		for neighbor: Vector2i in next_neighbors:
			if visited.has(neighbor):
				continue

			if not _is_valid_retreat_candidate(neighbor):
				continue

			if not _can_retreat_step(current, neighbor, known_enemies):
				continue

			visited[neighbor] = true
			allowed_hexes.append(neighbor)
			var priority: int = _retreat_priority(neighbor, known_enemies)
			var depth: int = current_depth + 1
			# Search the entire reachable area so nearby lower-priority terrain
			# cannot hide a better refuge farther away. Prefer nearby cover;
			# on open ground, continue moving away instead of stopping early.
			if priority < best_priority or (priority == best_priority and priority >= 3 and depth > best_depth):
				best_priority = priority
				best_depth = depth
				retreat_hex = neighbor

			queue.append(neighbor)
			depth_queue.append(depth)

	return retreat_hex


func _retreat_priority(hex: Vector2i, known_enemies: Array[Unit]) -> int:
	var woods: bool = false
	for layer: HexagonTileMapLayer in [LOSHelper.building_layer, LOSHelper.terrain_layer]:
		if not is_instance_valid(layer):
			continue
		var data: TileData = layer.get_cell_tile_data(hex)
		if data == null:
			continue
		if data.has_custom_data("art_family") and str(data.get_custom_data("art_family")) == "woods":
			woods = true
		if data.has_custom_data("name") and str(data.get_custom_data("name")).to_lower() == "woods":
			woods = true
	var building: bool = not woods and LOSHelper.building_layer.get_cell_source_id(hex) != -1
	var seen: bool = _is_hex_visible_by_any_enemy(hex, known_enemies)
	if not seen:
		if building:
			return 0
		if woods:
			return 1
	if building or woods:
		return 2
	if not seen:
		return 3
	return 4


func _can_retreat_step(from_hex: Vector2i, to_hex: Vector2i, known_enemies: Array[Unit]) -> bool:
	var ground: HexagonTileMapLayer = LOSHelper.ground_layer
	var graph: AStar2D = Globals.astars[unit.team]
	var from_id: int = ground.pathfinding_get_point_id(from_hex)
	var to_id: int = ground.pathfinding_get_point_id(to_hex)
	if not graph.has_point(from_id) or not graph.has_point(to_id):
		return false
	if graph.is_point_disabled(to_id) or not graph.are_points_connected(from_id, to_id, false):
		return false
	for enemy: Unit in known_enemies:
		var distance: int = ground.cube_distance(ground.map_to_cube(to_hex), ground.map_to_cube(enemy.current_hex))
		if distance <= 1:
			return false
		var previous_distance: int = ground.cube_distance(ground.map_to_cube(from_hex), ground.map_to_cube(enemy.current_hex))
		if distance <= previous_distance:
			return false
	return true


func _is_valid_retreat_candidate(hex: Vector2i) -> bool:
	var ground_layer: HexagonTileMapLayer = LOSHelper.ground_layer

	if ground_layer.get_cell_source_id(hex) == -1:
		return false

	#if not ground_layer.has_point(hex):
		#return false
#
	#if ground_layer.is_point_solid(hex):
		#return false

	return true


func _is_hex_visible_by_any_enemy(hex: Vector2i, known_enemies: Array[Unit]) -> bool:
	for enemy: Unit in known_enemies:
		if not is_instance_valid(enemy):
			continue

		var visible_hexes: Dictionary = LOSHelper.los_lookup.get(enemy.current_hex, {})
		if visible_hexes.has(hex):
			return true

	return false


func _is_adjacent_to_any_enemy(hex: Vector2i, known_enemies: Array[Unit]) -> bool:
	var ground_layer: TileMapLayer = LOSHelper.ground_layer
	var hex_cube: Vector3i = ground_layer.map_to_cube(hex)

	for enemy: Unit in known_enemies:
		if not is_instance_valid(enemy):
			continue

		var enemy_cube: Vector3i = ground_layer.map_to_cube(enemy.current_hex)
		var distance: int = ground_layer.cube_distance(hex_cube, enemy_cube)

		if distance <= 1:
			return true

	return false


func _start_rout() -> void:
	if unit.in_close_combat:
		# A locked encounter has no legal rout; retain the existing failed-rout outcome.
		rout_failed.emit()
		return
	var known_enemies: Array[Unit] = []
	#var i: int = 0
	#while i < unit.units.size():
		#var u: Unit = unit.units[i]
		#if u.team != unit.team and u.surrendered == false:
			#known_enemies.append(u)
		#i += 1
	var visible_enemies1: Array = Globals.unit_visible_enemies.get(unit, [])
	for u: Unit in visible_enemies1: # unit.units:
		if is_instance_valid(u) and u.is_active() and u.team != unit.team and not u.surrendered:
			known_enemies.append(u)
	
	var retreat_distance: int = 3
	var retreat_hex: Vector2i = compute_retreat_hex(unit.current_hex, known_enemies, retreat_distance)
	if retreat_hex == unit.current_hex:
		rout_failed.emit()
		return
	
	var restricted_astar: AStar2D = create_restricted_astar(allowed_hexes)
	var from_id: int = restricted_astar.get_closest_point(LOSHelper.ground_layer.map_to_local(unit.current_hex))
	var to_id: int = restricted_astar.get_closest_point(LOSHelper.ground_layer.map_to_local(retreat_hex))
	var id_path: PackedInt64Array = restricted_astar.get_id_path(from_id, to_id)
	if id_path.size() < 2:
		rout_failed.emit()
		return
	
	var cube_path: Array[Vector3i] = []
	var i: int = 0
	while i < id_path.size():
		var pid: int = id_path[i]
		var pos: Vector2 = restricted_astar.get_point_position(pid)
		cube_path.append(LOSHelper.ground_layer.local_to_cube(pos))
		i += 1
	
	unit.movement.follow_cube_path(cube_path)
	if not cube_path.is_empty():
		unit.movement.retreating = true



func create_restricted_astar(retreat_hexes: Array[Vector2i]) -> AStar2D:
	var new_astar: AStar2D = AStar2D.new()
	var original: AStar2D = Globals.astars[unit.team]
	
	var allowed_ids: Array[int] = []
	var i: int = 0
	while i < retreat_hexes.size():
		allowed_ids.append(LOSHelper.ground_layer.pathfinding_get_point_id(retreat_hexes[i]))
		i += 1
	
	for id: int in allowed_ids:
		var pos: Vector2 = original.get_point_position(id)
		new_astar.add_point(id, pos)
	
	for id: int in allowed_ids:
		var connected_ids: PackedInt64Array = original.get_point_connections(id)
		var j: int = 0
		while j < connected_ids.size():
			var conn_id: int = connected_ids[j]
			if allowed_ids.has(conn_id):
				var from_hex: Vector2i = LOSHelper.ground_layer.local_to_map(original.get_point_position(id))
				var to_hex: Vector2i = LOSHelper.ground_layer.local_to_map(original.get_point_position(conn_id))
				if _can_retreat_step(from_hex, to_hex, _retreat_known_enemies):
					new_astar.connect_points(id, conn_id, false)
			j += 1
	
	return new_astar


func on_rout_safe_and_morale_recovered() -> void:
	if action_state == SquadActionState.ROUTING:
		movement.stop()
		_set_action_state(SquadActionState.REGROUPING)
