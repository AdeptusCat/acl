extends Node


var thread: Thread
var result_ready := false
var current_threat_maps: Dictionary[int, Dictionary] 

var pending_visible_hexes: Dictionary[int, Array]
var pending_lookup: Dictionary = {}

var update_interval := 0.25  # seconds
var update_timer := 0.0


signal draw_threat(current_threat_maps: Dictionary[int, Dictionary])


func _on_move_requested(selected_unit, to_hex):
	if not selected_unit.current_hex == to_hex:
		var path: Array[Vector3i] = _compute_path(selected_unit.current_hex, to_hex, selected_unit.team)
		selected_unit.give_move_to_hex_order(to_hex, path, false)
		#selected_unit.movement.follow_cube_path(path)
	else:
		selected_unit.movement.move_to_hex(to_hex)

var threat_weights = {}


func _compute_path(from_h: Vector2i, to_h: Vector2i, team: int) -> Array[Vector3i]:
	var from_id: int = LOSHelper.ground_layer.pathfinding_get_point_id(from_h)
	var to_id: int = LOSHelper.ground_layer.pathfinding_get_point_id(to_h)

	# Update point weight scales based on enemy LOS threat
	for point_id in Globals.astars[team].get_point_ids():
		var world_pos = Globals.astars[team].get_point_position(point_id)
		var hex_map = LOSHelper.ground_layer.local_to_map(world_pos)
		var weight = current_threat_maps[team].get(hex_map, 1.0)
		Globals.astars[team].set_point_weight_scale(point_id, weight)
		#LOSHelper.ground_layer.astar.set_point_weight_scale(point_id, weight)
	# Run A*
	#var id_path: PackedInt64Array = LOSHelper.ground_layer.astar.get_id_path(from_id, to_id)
	var id_path: PackedInt64Array = Globals.astars[team].get_id_path(from_id, to_id)

	# Convert path to cube coordinates
	var cube_path: Array[Vector3i] = []
	for pid in id_path:
		var pos = Globals.astars[team].get_point_position(pid)
		cube_path.append(LOSHelper.ground_layer.local_to_cube(pos))

	return cube_path


func _calculate_threat_weight(hex: Vector2i, pending_los_lookup: Dictionary, pending_visible_hexes: Dictionary[int, Array], team: int) -> float:
	var weight = 1.0  # Start with neutral weight scale

	var enemy_team = Globals.Team.AXIS if team == Globals.Team.ALLIES else Globals.Team.ALLIES
	
	var observed_hexes_by_enemy = pending_visible_hexes.get(enemy_team, [])
	
	if observed_hexes_by_enemy.has(hex):
		for unit in Globals.units:
			if not unit.team == enemy_team:
				continue
			var o_hex = unit.current_hex
			if pending_los_lookup.has(o_hex) and pending_los_lookup[o_hex].has(hex):
				var cover = pending_los_lookup[o_hex][hex].target_cover
				weight += max((6.0 - float(cover)), 1.0) * 0.3  # Adjust scaling if needed
	##for o_hex in observed_hexes_by_enemy:
	#for o_hex in units:
		#var observed_hex = 
		#if pending_los_lookup.has(o_hex) and pending_los_lookup[o_hex].has(hex):
			#var cover = pending_los_lookup[o_hex][hex].target_cover
			##cover = clamp(cover, 0, 5)
			#weight += max((6.0 - float(cover)), 1.0) * 0.1  # Adjust scaling if needed

	return weight



func request_threat_update(visible_hexes: Array, lookup_data: Dictionary):
	if thread and thread.is_alive():
		return
	pending_visible_hexes.clear()
	for k in LOSHelper.visible_hexes.keys():
		pending_visible_hexes[k] = LOSHelper.visible_hexes[k].duplicate()
	pending_lookup.clear()
	for k in LOSHelper.los_lookup.keys():
		pending_lookup[k] = LOSHelper.los_lookup[k].duplicate()
	thread = Thread.new()
	thread.start(_threaded_update_threat_map.bind(pending_lookup, pending_visible_hexes))


func _exit_tree():
	if thread:
		thread.wait_to_finish()


func _set_threat_map_result(result: Dictionary[int, Dictionary]):
	#current_threat_map = result
	current_threat_maps = result
	draw_threat.emit(current_threat_maps)
	# get_parent().draw_threat(current_threat_maps)
	result_ready = true


func _threaded_update_threat_map(pending_lookup: Dictionary, pending_visible_hexes: Dictionary[int, Array]):
	var temp_threat_maps: Dictionary[int, Dictionary]
	temp_threat_maps[Globals.Team.AXIS] = {}
	temp_threat_maps[Globals.Team.ALLIES] = {}
	#temp_threat_map[Vector2i(12, 12)] =  _calculate_threat_weight(Vector2i(12, 12), pending_lookup, pending_visible_hexes)
	#temp_threat_map[Vector2i(15, 9)] =  _calculate_threat_weight(Vector2i(15, 9), pending_lookup, pending_visible_hexes)
	for team in Globals.Team.values():
		for point_id in Globals.astars[team].get_point_ids():
			var world_pos = Globals.astars[team].get_point_position(point_id)
			var hex_map = LOSHelper.ground_layer.local_to_map(world_pos)
			var weight = _calculate_threat_weight(hex_map, pending_lookup, pending_visible_hexes, team)
			temp_threat_maps[team][hex_map] = weight

	call_deferred("_set_threat_map_result", temp_threat_maps)
	call_deferred("thread_done")


func thread_done():
	if thread:
		thread.wait_to_finish()
		thread = null


func _process(delta: float) -> void:
	update_timer += delta
	if update_timer >= update_interval:
		update_timer = 0.0
		
		await _start_threat_map_update()
		
		#var enemy_team = Globals.Team.AXIS if Globals.team_player == Globals.Team.ALLIES else Globals.Team.ALLIES
		#var observers: Array = LOSHelper.visible_hexes.get(enemy_team, [])
		#request_threat_update(observers, LOSHelper.los_lookup)

var updating_threat := false
func _start_threat_map_update():
	if updating_threat:
		return
	updating_threat = true
	#pending_visible_hexes = LOSHelper.visible_hexes.duplicate(true)
	#pending_lookup = LOSHelper.los_lookup.duplicate(true)
	
	pending_visible_hexes = await _deferred_copy_dict_visible_hexes(LOSHelper.visible_hexes)
	#pending_lookup = await _deferred_copy_dict(LOSHelper.los_lookup)
	pending_lookup = LOSHelper.los_lookup
	await _incremental_threat_map_update()
	updating_threat = false

func _deferred_copy_dict_visible_hexes(source: Dictionary[int, Array]) -> Dictionary[int, Array]:
	var copy:Dictionary[int, Array] = {}
	for k in source.keys():
		var v = source[k]
		if typeof(v) == TYPE_DICTIONARY:
			copy[k] = v.duplicate(true)
		elif typeof(v) == TYPE_ARRAY:
			copy[k] = v.duplicate(true)
		else:
			copy[k] = v
		await get_tree().create_timer(0.0).timeout
	return copy

func _deferred_copy_dict(source: Dictionary) -> Dictionary:
	var copy := {}
	for k in source.keys():
		var v = source[k]
		if typeof(v) == TYPE_DICTIONARY:
			copy[k] = v.duplicate(true)
		elif typeof(v) == TYPE_ARRAY:
			copy[k] = v.duplicate(true)
		else:
			copy[k] = v
		await get_tree().create_timer(0.0).timeout
	return copy

func _incremental_threat_map_update() -> void:
	var temp_threat_maps: Dictionary[int, Dictionary]
	temp_threat_maps[Globals.Team.AXIS] = {}
	temp_threat_maps[Globals.Team.ALLIES] = {}

	for team in Globals.Team.values():
		var points := Globals.astars[team].get_point_ids()
		var index := 0
		while index < points.size():
			var batch_size := 30  # Lower this if still lagging
			for j in range(batch_size):
				if index >= points.size():
					break
				var point_id := points[index]
				var world_pos = Globals.astars[team].get_point_position(point_id)
				var hex_map = LOSHelper.ground_layer.local_to_map(world_pos)
				var weight := _calculate_threat_weight(hex_map, pending_lookup, pending_visible_hexes, team)
				temp_threat_maps[team][hex_map] = weight
				index += 1
			await get_tree().create_timer(0.00).timeout  # Yield between small batches
	call_deferred("_set_threat_map_result", temp_threat_maps)

func _on_arrived(hex):
	_restack_units_in_hex(hex)


func _restack_units_in_hex(hex: Vector2i):
	# collect alive units in this hex
	var stack := []
	for u in Globals.units:
		if u.alive and u.current_hex == hex:
			stack.append(u)

	var count = stack.size()
	if count == 0:
		return

	var base_pos = LOSHelper.ground_layer.map_to_local(hex)

	if count == 1:
		# single‐unit stays centered
		stack[0].position = base_pos
		stack[0].z_index   = 0
	else:
		# spacing in pixels between each sprite
		var spacing = 16
		# center_index so that the whole column is centered on base_pos.y
		var center_index = (count - 1) / 2.0
		for i in range(count):
			var u = stack[i]
			# compute Y offset: units above get negative y, below get positive y
			var y_off = (i - center_index) * spacing
			u.position = base_pos + Vector2(0, y_off)
			u.z_index  = i   # draw in order, top to bottom


func _restack_units():
	# 1) Group units by their current_hex
	var groups := {}
	for u in Globals.units:
		if not u.alive:
			continue
		var h = u.current_hex
		if not groups.has(h):
			groups[h] = []
		groups[h].append(u)

	# 2) For each hex, if there’s 1 unit keep it centered;
	#    if >1, spread them in a little circle.
	var center_offset = Vector2.ZERO
	for h in groups.keys():
		var group = groups[h]
		var base_pos = LOSHelper.ground_layer.map_to_local(h)
		var cnt = group.size()

		if cnt == 1:
			group[0].position = base_pos
			group[0].z_index   = 0
		else:
			# radius in pixels you want units spread around
			var radius = 16  
			for i in range(cnt):
				# evenly space them in a circle
				var angle = TAU * i / cnt  # TAU = 2*PI
				var offset = Vector2(cos(angle), sin(angle)) * radius
				var u = group[i]
				u.position = base_pos + offset
				# Optional: layer them so they don’t z-fight
				u.z_index = i
