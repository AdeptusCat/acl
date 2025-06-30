extends Node


var unit_visible_enemies: Dictionary
var units: Array[Node2D] = []


func _on_move_requested(selected_unit, to_hex):
	var path: Array[Vector3i] = _compute_path(selected_unit.current_hex, to_hex)
	selected_unit.movement.follow_cube_path(path)


#func _compute_path(from_h, to_h) -> Array[Vector3i]:
	#var from_id: int = LOSHelper.ground_layer.pathfinding_get_point_id(from_h)
	#var to_id: int   = LOSHelper.ground_layer.pathfinding_get_point_id(to_h)
	#var id_path: PackedInt64Array = LOSHelper.ground_layer.astar.get_id_path(from_id, to_id)
	#var cube_path: Array[Vector3i] = []
	#for pid in id_path:
		#var pos = LOSHelper.ground_layer.astar.get_point_position(pid)
		#cube_path.append(LOSHelper.ground_layer.local_to_cube(pos))
	#return cube_path

var threat_weights = {}


#func _compute_path(from_h: Vector2i, to_h: Vector2i) -> Array[Vector3i]:
	#threat_weights.clear()
	#var from_id: int = LOSHelper.ground_layer.pathfinding_get_point_id(from_h)
	#var to_id: int = LOSHelper.ground_layer.pathfinding_get_point_id(to_h)
#
	## Update point weight scales based on enemy LOS threat
	#for point_id in LOSHelper.ground_layer.astar.get_point_ids():
		#var world_pos = LOSHelper.ground_layer.astar.get_point_position(point_id)
		#var hex_map = LOSHelper.ground_layer.local_to_map(world_pos)
		#var weight = _calculate_threat_weight(hex_map)
		#LOSHelper.ground_layer.astar.set_point_weight_scale(point_id, weight)
		#threat_weights[hex_map] = weight
	#get_parent().draw_threat(threat_weights)
	## Run A*
	#var id_path: PackedInt64Array = LOSHelper.ground_layer.astar.get_id_path(from_id, to_id)
#
	## Convert path to cube coordinates
	#var cube_path: Array[Vector3i] = []
	#for pid in id_path:
		#var pos = LOSHelper.ground_layer.astar.get_point_position(pid)
		#cube_path.append(LOSHelper.ground_layer.local_to_cube(pos))
#
	#return cube_path


func _compute_path(from_h: Vector2i, to_h: Vector2i) -> Array[Vector3i]:
	threat_weights.clear()
	var from_id: int = LOSHelper.ground_layer.pathfinding_get_point_id(from_h)
	var to_id: int = LOSHelper.ground_layer.pathfinding_get_point_id(to_h)

	# Update point weight scales based on enemy LOS threat
	for point_id in LOSHelper.ground_layer.astar.get_point_ids():
		var world_pos = LOSHelper.ground_layer.astar.get_point_position(point_id)
		var hex_map = LOSHelper.ground_layer.local_to_map(world_pos)
		var weight = current_threat_map.get(hex_map, 1.0)
		LOSHelper.ground_layer.astar.set_point_weight_scale(point_id, weight)
		threat_weights[hex_map] = weight
	get_parent().draw_threat(threat_weights)
	# Run A*
	var id_path: PackedInt64Array = LOSHelper.ground_layer.astar.get_id_path(from_id, to_id)

	# Convert path to cube coordinates
	var cube_path: Array[Vector3i] = []
	for pid in id_path:
		var pos = LOSHelper.ground_layer.astar.get_point_position(pid)
		cube_path.append(LOSHelper.ground_layer.local_to_cube(pos))

	return cube_path


func _calculate_threat_weight(hex: Vector2i) -> float:
	var weight = 1.0  # Start with neutral weight scale

	var enemy_team = Globals.Team.AXIS if Globals.team_player == Globals.Team.ALLIES else Globals.Team.ALLIES
	var enemy_observers = LOSHelper.visible_hexes.get(enemy_team, [])

	for o_hex in enemy_observers:
		if LOSHelper.los_lookup.has(o_hex) and LOSHelper.los_lookup[o_hex].has(hex):
			var cover = LOSHelper.los_lookup[o_hex][hex].shooter_cover
			cover = clamp(cover, 0, 5)
			weight += (8.0 - float(cover)) * 0.1  # Adjust scaling if needed

	return weight

var thread := Thread.new()
var result_ready := false
var current_threat_map: Dictionary[Vector2i, float] = {}

var pending_visible_hexes: Array = []
var pending_lookup: Dictionary = {}

var update_interval := 0.25  # seconds
var update_timer := 0.0

func request_threat_update(visible_hexes: Array, lookup_data: Dictionary):
	if thread.is_alive():
		return  # avoid overlapping work

	pending_visible_hexes = visible_hexes.duplicate()
	pending_lookup = lookup_data.duplicate()
	thread.start(Callable(self, "_threaded_update_threat_map"), Thread.PRIORITY_NORMAL)

func _set_threat_map_result(result: Dictionary[Vector2i, float]):
	current_threat_map = result
	result_ready = true

func _threaded_update_threat_map():
	var temp_threat_map: Dictionary[Vector2i, float] = {}

	for o_hex in pending_visible_hexes:
		if pending_lookup.has(o_hex):
			for t_hex in pending_lookup[o_hex].keys():
				var cover = clamp(pending_lookup[o_hex][t_hex].shooter_cover, 0, 5)
				var threat = (8.0 - float(cover)) * 0.1
				temp_threat_map[t_hex] = temp_threat_map.get(t_hex, 0.0) + threat

	# Add base weight (1.0) after loop to match logic
	for hex in temp_threat_map.keys():
		temp_threat_map[hex] += 1.0

	call_deferred("_set_threat_map_result", temp_threat_map)

func _process(delta: float) -> void:
	update_timer += delta
	if update_timer >= update_interval:
		update_timer = 0.0
		update_threat_map()
		#var enemy_team = Globals.Team.AXIS if Globals.team_player == Globals.Team.ALLIES else Globals.Team.ALLIES
		#var observers: Array = LOSHelper.visible_hexes.get(enemy_team, [])
		#request_threat_update(observers, LOSHelper.los_lookup)
		

func update_threat_map():
	threat_weights.clear()
	current_threat_map.clear()

	var enemy_team = Globals.Team.AXIS if Globals.team_player == Globals.Team.ALLIES else Globals.Team.AXIS
	var enemy_observers = LOSHelper.visible_hexes.get(enemy_team, [])

	var threat_map: Dictionary[Vector2i, float] = {}

	for o_hex in enemy_observers:
		if not LOSHelper.los_lookup.has(o_hex):
			continue

		for t_hex in LOSHelper.los_lookup[o_hex].keys():
			if not LOSHelper.visible_hexes[enemy_team].has(t_hex):
				continue

			var cover = clamp(LOSHelper.los_lookup[o_hex][t_hex].shooter_cover, 0, 5)
			var threat = (8.0 - float(cover)) * 0.1
			threat_map[t_hex] = threat_map.get(t_hex, 1.0) + threat
			threat_weights[t_hex] = 1.0 + threat
	get_parent().draw_threat(threat_weights)
	current_threat_map = threat_map



func _on_arrived(hex):
	_restack_units_in_hex(hex)


func _restack_units_in_hex(hex: Vector2i):
	# collect alive units in this hex
	var stack := []
	for u in units:
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
	for u in units:
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
