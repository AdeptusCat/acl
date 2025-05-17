extends Node


var unit_visible_enemies: Dictionary
var units: Array[Node2D] = []


func _on_move_requested(selected_unit, to_hex):
	var path = _compute_path(selected_unit.current_hex, to_hex)
	selected_unit.movement.follow_cube_path(path)


func _compute_path(from_h, to_h):
	#var id1 = LOSHelper.ground_layer.pathfinding_get_point_id(from_h)
	#var id2 = LOSHelper.ground_layer.pathfinding_get_point_id(to_h)
	#var raw = LOSHelper.ground_layer.astar.get_id_path(id1, id2)
	#return raw.map(func(pid): LOSHelper.ground_layer.local_to_cube( LOSHelper.ground_layer.astar.get_point_position(pid) ))
	var from_id = LOSHelper.ground_layer.pathfinding_get_point_id(from_h)
	var to_id   = LOSHelper.ground_layer.pathfinding_get_point_id(to_h)
	var id_path = LOSHelper.ground_layer.astar.get_id_path(from_id, to_id)
	return id_path


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
