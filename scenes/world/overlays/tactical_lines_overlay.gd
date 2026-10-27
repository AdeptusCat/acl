extends Node2D

var lines: Array[Dictionary] = []  # {from, to, timer, duration}
var los_enemy_lines: Array = []
var los_to_target: Array = []
var movement_path: Array = []
var chain_of_command: Array = []
var command_link_strength: Array = []
var leader_presence_strength: Dictionary[Globals.Team, Array] = {
	Globals.Team.AXIS: [],
	Globals.Team.ALLIES: [],
}


func _on_draw_command_link_strength(team: Globals.Team, from_hex: Vector2i, to_hex: Vector2i, strength: float) -> void:
	var from_pos: Vector2 = LOSHelper.ground_layer.map_to_local(from_hex)
	var to_pos: Vector2 = LOSHelper.ground_layer.map_to_local(to_hex)

	command_link_strength.append({
		"from": from_pos,
		"to": to_pos,
		"timer": 0.0,
		"duration": 1.0,  # Line fades out over 2 seconds
		"strength": strength
	})

	queue_redraw()


func _on_draw_leader_presence_strength(team: Globals.Team, from_hex: Vector2i, to_hex: Vector2i, strength: float) -> void:
	var from_pos: Vector2 = LOSHelper.ground_layer.map_to_local(from_hex)
	var to_pos: Vector2 = LOSHelper.ground_layer.map_to_local(to_hex)
	
	leader_presence_strength[team].append({
		"from": from_pos,
		"to": to_pos,
		"timer": 0.0,
		"duration": 1.0,  # Line fades out over 2 seconds
		"strength": strength
	})

	queue_redraw()


func _on_draw_chain_of_command(from_hex: Vector2i, path: Array[Vector2i]) -> void:
	var i: int = 0
	for hex: Vector2i in path:
		if path.size() <= i + 1:
			return
		var from_pos: Vector2 = LOSHelper.ground_layer.map_to_local(path[i])
		var to_pos: Vector2 = LOSHelper.ground_layer.map_to_local(path[i+1])

		chain_of_command.append({
			"from": from_pos,
			"to": to_pos,
			"timer": 0.0,
			"duration": 2.0  # Line fades out over 2 seconds
		})

		queue_redraw()
		
		i += 1


func _on_draw_draw_movement_path(from_hex: Vector2i, path: Array[Vector2i]) -> void:
	var i: int = 0
	for hex: Vector2i in path:
		if path.size() <= i + 1:
			return
		var from_pos: Vector2 = LOSHelper.ground_layer.map_to_local(path[i])
		var to_pos: Vector2 = LOSHelper.ground_layer.map_to_local(path[i+1])

		movement_path.append({
			"from": from_pos,
			"to": to_pos,
			"timer": 0.0,
			"duration": 2.0  # Line fades out over 2 seconds
		})

		queue_redraw()
		
		i += 1


func _on_draw_los_to_target_unit(from_hex: Vector2i, to_hex: Vector2i) -> void:
	var from_pos: Vector2 = LOSHelper.ground_layer.map_to_local(from_hex)
	var to_pos: Vector2 = LOSHelper.ground_layer.map_to_local(to_hex)
	var crossings: PackedVector2Array = PackedVector2Array()
	if Debug.show_los_lines:
		crossings = LOSHelper.get_hindrance_crossings(from_pos, to_pos)

	los_to_target.append({
		"from": from_pos,
		"to": to_pos,
		"hindrance_points": crossings,
		"timer": 0.0,
		"duration": 2.0  # Line fades out over 2 seconds
	})

	queue_redraw()


func _on_draw_los_to_enemy(from_hex: Vector2i, to_hex: Vector2i) -> void:
	var from_pos: Vector2 = LOSHelper.ground_layer.map_to_local(from_hex)
	var to_pos: Vector2 = LOSHelper.ground_layer.map_to_local(to_hex)
	var crossings: PackedVector2Array = PackedVector2Array()
	if Debug.show_los_lines:
		crossings = LOSHelper.get_hindrance_crossings(from_pos, to_pos)

	los_enemy_lines.append({
		"from": from_pos,
		"to": to_pos,
		"hindrance_points": crossings,
		"timer": 0.0,
		"duration": 2.0  # Line fades out over 2 seconds
	})

	queue_redraw()


func _draw() -> void:
	_draw_selected_watch_sectors()
	_draw_selected_target()
	_draw_player_routes()
	if Debug.show_los_lines:
		for los_data: Dictionary in los_enemy_lines:
			_draw_sight_line(los_data, 0.55)
		for los_data: Dictionary in los_to_target:
			_draw_sight_line(los_data, 0.9)
	if Debug.show_movement_lines:
		for los_data: Dictionary in movement_path:
			draw_line(los_data["from"], los_data["to"], Color(0.044, 0.0, 0.953, 1.0), 2.0)
	for los_data: Dictionary in chain_of_command:
		draw_line(los_data["from"], los_data["to"], Color(0.0, 0.391, 0.122, 1.0), 2.0)
	#if SessionSettings.showCmdConnectivity:
		#if Debug.showEnemyCmdConnectivity:
			#for connection in leader_presence_strength[Globals.team_enemy]:
				#draw_line(connection["from"], connection["to"], strength_to_color_hsv(connection["strength"]), clamp(connection["strength"] * 10, 1.0, 10.0))
		#for connection in leader_presence_strength[Globals.team_player]:
			#draw_line(connection["from"], connection["to"], strength_to_color_hsv(connection["strength"]), clamp(connection["strength"] * 10, 1.0, 10.0))
	#if SessionSettings.showCmdConnectivity:
		#if Debug.showEnemyCmdConnectivity:
			#for connection in leader_presence_strength[Globals.team_enemy]:
				#var aim_line: MovingDottedDrawLine = MovingDottedDrawLine.new()
				#add_child(aim_line)
				#aim_line.set_line(
					#connection["from"],
					#connection["to"]
				#)
				##draw_line(connection["from"], connection["to"], strength_to_color_hsv(connection["strength"]), clamp(connection["strength"] * 10, 1.0, 10.0))
		#for connection in leader_presence_strength[Globals.team_player]:
			#var aim_line: MovingDottedDrawLine = MovingDottedDrawLine.new()
			#add_child(aim_line)
			#aim_line.set_line(
				#connection["from"],
				#connection["to"]
				#)
				##draw_line(connection["from"], connection["to"], strength_to_color_hsv(connection["strength"]), clamp(connection["strength"] * 10, 1.0, 10.0))

func _draw_sight_line(data: Dictionary, opacity: float) -> void:
	if not is_instance_valid(LOSHelper.ground_layer):
		return
	var origin: Vector2 = to_local(LOSHelper.ground_layer.to_global(data["from"]))
	var target: Vector2 = to_local(LOSHelper.ground_layer.to_global(data["to"]))
	var crossings: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in data["hindrance_points"]:
		crossings.append(to_local(LOSHelper.ground_layer.to_global(point)))
	SightLineGraphic.draw(self, origin, target, false, origin, false, opacity, crossings)


func _target_for_link(unit: Unit) -> Unit:
	if not is_instance_valid(unit) or not unit.selected or not unit.is_active() or unit.surrendered or unit.broken or unit.in_close_combat or not unit.is_visible_in_tree():
		return null
	# Enemy inspection must not expose an enemy's targeting decisions.
	if unit.team != Globals.team_player and not Debug.enemy_selectable:
		return null
	if unit.attackState == Unit.AttackState.MANUAL_GROUND or not is_instance_valid(unit.squad_fire):
		return null
	var target: Unit = unit.squad_fire.target_unit
	if not is_instance_valid(target) or target.team == unit.team or not target.is_visible_in_tree():
		return null
	if not unit.squad_fire._can_track_target(target):
		return null
	return target


func _counter_center(unit: Unit) -> Vector2:
	var sprite: TextureRect = unit.ui.sprite_node
	return sprite.get_global_transform() * (sprite.size * 0.5)


func _counter_edge(unit: Unit, toward: Vector2) -> Vector2:
	var sprite: TextureRect = unit.ui.sprite_node
	var transform: Transform2D = sprite.get_global_transform()
	var half_size: Vector2 = sprite.size * 0.5
	var direction: Vector2 = (transform.affine_inverse() * toward - half_size).normalized()
	var reach: float = minf(half_size.x / maxf(absf(direction.x), 0.001), half_size.y / maxf(absf(direction.y), 0.001))
	return transform * (half_size + direction * reach)


func _watch_sector_points(unit: Unit) -> PackedVector2Array:
	if not is_instance_valid(unit) or not unit.selected or not unit.is_active() or unit.surrendered or not unit.has_watch_order() or not unit.is_visible_in_tree():
		return PackedVector2Array()
	if unit.team != Globals.team_player and not Debug.enemy_selectable:
		return PackedVector2Array()
	if not is_instance_valid(unit.ui) or not unit.ui.is_node_ready():
		return PackedVector2Array()
	var radius: float = 160.0
	if is_instance_valid(LOSHelper.ground_layer) and LOSHelper.ground_layer.tile_set != null:
		radius = float(LOSHelper.ground_layer.tile_set.tile_size.x) * 2.5
	var origin: Vector2 = _counter_center(unit)
	var points: PackedVector2Array = PackedVector2Array([to_local(origin)])
	var half_width: float = unit.watch_arc_radians() * 0.5
	for step: int in range(33):
		var angle: float = lerpf(-half_width, half_width, float(step) / 32.0)
		points.append(to_local(origin + unit.watch_direction.rotated(angle) * radius))
	points.append(to_local(origin))
	return points


func _draw_selected_watch_sectors() -> void:
	var pixel: float = 1.0 / maxf(get_global_transform_with_canvas().get_scale().x, 0.01)
	for unit: Unit in Globals.get_units():
		var points: PackedVector2Array = _watch_sector_points(unit)
		if points.is_empty():
			continue
		var tint: Color = Color(0.9, 0.74, 0.39)
		if unit.tactical_state != null and unit.tactical_state.watch_diverted:
			tint = Color(0.66, 0.67, 0.62)
		draw_colored_polygon(points.slice(0, points.size() - 1), Color(tint, 0.07))
		draw_polyline(points, Color(tint, 0.7), 1.5 * pixel, true)


func _draw_selected_target() -> void:
	for unit: Unit in Globals.get_units():
		var target: Unit = _target_for_link(unit)
		if target == null:
			continue
		var origin: Vector2 = to_local(_counter_center(unit))
		var destination: Vector2 = to_local(_counter_center(target))
		var direction: Vector2 = (destination - origin).normalized()
		var start: Vector2 = to_local(_counter_edge(unit, _counter_center(target)))
		var finish: Vector2 = to_local(_counter_edge(target, _counter_center(unit)))
		if (finish - start).dot(direction) <= 0.0:
			continue
		var zoom: float = maxf(absf(get_global_transform_with_canvas().get_scale().x), 0.05)
		var pixel: float = 1.0 / zoom
		var effect: Dictionary = unit.squad_fire.get_fire_effect()
		var pulse: float = float(effect.get("pulse", 0.0))
		var strength: float = float(effect.get("strength", 0.0))
		var tint: Color = Color(1.0, 0.24, 0.18)
		if not effect.is_empty():
			tint = effect["color"]
		# Layered transparent strokes give a soft glow without requiring HDR bloom.
		draw_line(start, finish, Color(tint, 0.04 + pulse * 0.12), (10.0 + pulse * 4.0) * pixel, true)
		draw_line(start, finish, Color(tint, 0.09 + pulse * 0.20), 5.0 * pixel, true)
		draw_line(start, finish, Color(tint, 0.20 + strength * 0.25 + pulse * 0.45), (1.0 + strength + pulse) * pixel, true)
		if pulse > 0.0:
			draw_arc(finish, (5.0 + (1.0 - pulse) * 8.0) * pixel, 0.0, TAU, 24, Color(tint, pulse * 0.7), 1.5 * pixel, true)
		var normal: Vector2 = Vector2(-direction.y, direction.x)
		var arrow: Vector2 = finish - direction * 7.0 * pixel
		draw_polyline(PackedVector2Array([arrow + normal * 3.0 * pixel, finish, arrow - normal * 3.0 * pixel]), Color(tint, 0.32 + pulse * 0.55), 1.5 * pixel, true)


func _draw_player_routes() -> void:
	if not is_instance_valid(LOSHelper.ground_layer):
		return
	for unit: Unit in Globals.get_units_for_team(Globals.team_player):
		if not unit.is_active() or unit.movement == null:
			continue
		var waypoints: Array[Vector2i] = unit.movement.remaining_waypoints()
		if waypoints.is_empty():
			continue
		var color: Color = Color(0.45, 0.85, 1.0, 0.8)
		var width: float = 2.5
		if unit.selected:
			color = Color(1.0, 0.87, 0.24, 1.0)
			width = 4.0
		var previous: Vector2 = to_local(unit.global_position)
		for index: int in range(waypoints.size()):
			var point: Vector2 = to_local(LOSHelper.ground_layer.to_global(LOSHelper.ground_layer.map_to_local(waypoints[index])))
			draw_line(previous, point, Color(0.05, 0.08, 0.05, 0.85), width + 3.0, true)
			draw_line(previous, point, color, width, true)
			draw_circle(point, 4.0, color)
			if index == waypoints.size() - 1:
				draw_arc(point, 10.0, 0.0, TAU, 32, Color(0.05, 0.08, 0.05, 0.9), width + 3.0, true)
				draw_arc(point, 10.0, 0.0, TAU, 32, color, width, true)
			previous = point

func strength_to_color_hsv(strength: float) -> Color:
	var s: float = strength

	if s < 0.0:
		s = 0.0
	else:
		if s > 1.0:
			s = 1.0

	var hue: float = 0.33 * s   # 0.0 → 0.33 (red → green)
	return Color.from_hsv(hue, 1.0, 1.0, 1.0)

func _process(delta: float) -> void:
	for line: Dictionary in command_link_strength:
		line["timer"] += delta
	command_link_strength = command_link_strength.filter(func(line: Dictionary) -> bool:
		return line["timer"] < line["duration"]
	)

	for line: Dictionary in los_enemy_lines:
		line["timer"] += delta
	# Remove fully expired lines
	los_enemy_lines = los_enemy_lines.filter(func(line: Dictionary) -> bool:
		return line["timer"] < line["duration"]
	)
	
	
	
	for line: Dictionary in los_to_target:
		line["timer"] += delta
	# Remove fully expired lines
	los_to_target = los_to_target.filter(func(line: Dictionary) -> bool:
		return line["timer"] < line["duration"]
	)
	
	
	for line: Dictionary in movement_path:
		line["timer"] += delta
	# Remove fully expired lines
	movement_path = movement_path.filter(func(line: Dictionary) -> bool:
		return line["timer"] < line["duration"]
	)
	
	
	for line: Dictionary in movement_path:
		line["timer"] += delta
	# Remove fully expired lines
	movement_path = movement_path.filter(func(line: Dictionary) -> bool:
		return line["timer"] < line["duration"]
	)
	
	
	for team: Array in leader_presence_strength.values():
		for line: Dictionary in team:
			line["timer"] += delta
	# Remove fully expired lines
	for team: Globals.Team in leader_presence_strength:
		leader_presence_strength[team] = leader_presence_strength[team].filter(func(line: Dictionary) -> bool:
			return line["timer"] < line["duration"]
		)
	
	

	queue_redraw()  # Always request redraw if lines change
