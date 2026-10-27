extends Node


func _compute_path(from_h: Vector2i, to_h: Vector2i, team: int, moving_unit: Unit = null) -> Array[Vector3i]:
	var movement: UnitMovement
	var origin_position: Vector2 = Vector2.INF
	if is_instance_valid(moving_unit):
		if moving_unit.team != team or moving_unit.current_hex != from_h:
			return []
		movement = moving_unit.movement
		origin_position = moving_unit.position
	var temporary_movement: bool = movement == null
	if temporary_movement:
		movement = UnitMovement.new()
	var contacts: Array[InfluenceContact] = ThreatMap.capture_contacts(team)
	var route: MoveRoutePlanner = MoveRoutePlanner.new()
	route.build(from_h, to_h, team, movement, contacts, origin_position)
	if is_instance_valid(moving_unit) and is_instance_valid(Debug.engagement_recorder):
		Debug.engagement_recorder.record_move_route(moving_unit, to_h, route, contacts)
	if temporary_movement:
		movement.free()
	return route.path


func _on_arrived(hex: Vector2i) -> void:
	_restack_units_in_hex(hex)


func _restack_units_in_hex(hex: Vector2i) -> void:
	# collect alive units in this hex
	var stack: Array[Unit] = []
	for u: Unit in Globals.get_units():
		if u.alive and u.current_hex == hex:
			stack.append(u)

	var count: int = stack.size()
	if count == 0:
		return

	var base_pos: Vector2 = LOSHelper.ground_layer.map_to_local(hex)

	if count == 1:
		# single‐unit stays centered
		stack[0].position = base_pos
		stack[0].z_index   = 0
	else:
		# spacing in pixels between each sprite
		var spacing: int = 16
		# center_index so that the whole column is centered on base_pos.y
		var center_index: float = (count - 1) / 2.0
		for i: int in range(count):
			var u: Unit = stack[i]
			# compute Y offset: units above get negative y, below get positive y
			var y_off: float = (i - center_index) * spacing
			u.position = base_pos + Vector2(0, y_off)
			u.z_index  = i   # draw in order, top to bottom


func _restack_units() -> void:
	# 1) Group units by their current_hex
	var groups: Dictionary[Vector2i, Array] = {}
	for u: Unit in Globals.get_units():
		if not u.alive:
			continue
		var h: Vector2i = u.current_hex
		if not groups.has(h):
			var occupants: Array[Unit] = []
			groups[h] = occupants
		groups[h].append(u)

	# 2) For each hex, if there’s 1 unit keep it centered;
	#    if >1, spread them in a little circle.
	var _center_offset: Vector2 = Vector2.ZERO
	for h: Vector2i in groups.keys():
		var group: Array[Unit] = groups[h]
		var base_pos: Vector2 = LOSHelper.ground_layer.map_to_local(h)
		var cnt: int = group.size()

		if cnt == 1:
			group[0].position = base_pos
			group[0].z_index   = 0
		else:
			# radius in pixels you want units spread around
			var radius: int = 16
			for i: int in range(cnt):
				# evenly space them in a circle
				var angle: float = TAU * i / cnt  # TAU = 2*PI
				var offset: Vector2 = Vector2(cos(angle), sin(angle)) * radius
				var u: Unit = group[i]
				u.position = base_pos + offset
				# Optional: layer them so they don’t z-fight
				u.z_index = i
