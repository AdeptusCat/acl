extends Node2D

var lines = []  # {from, to, timer, duration}
var los_enemy_lines: Array = []
var los_to_target: Array = []
var movement_path: Array = []
var chain_of_command: Array = []
var command_link_strength: Array = []
var leader_presence_strength: Array = []


func _on_draw_command_link_strength(from_hex: Vector2i, to_hex: Vector2i, strength: float) -> void:
	var from_pos = LOSHelper.ground_layer.map_to_local(from_hex)
	var to_pos = LOSHelper.ground_layer.map_to_local(to_hex)

	command_link_strength.append({
		"from": from_pos,
		"to": to_pos,
		"timer": 0.0,
		"duration": 1.0,  # Line fades out over 2 seconds
		"strength": strength
	})

	queue_redraw()


func _on_draw_leader_presence_strength(from_hex: Vector2i, to_hex: Vector2i, strength: float) -> void:
	var from_pos = LOSHelper.ground_layer.map_to_local(from_hex)
	var to_pos = LOSHelper.ground_layer.map_to_local(to_hex)

	leader_presence_strength.append({
		"from": from_pos,
		"to": to_pos,
		"timer": 0.0,
		"duration": 1.0,  # Line fades out over 2 seconds
		"strength": strength
	})
	queue_redraw()


func _on_draw_chain_of_command(from_hex: Vector2i, path: Array[Vector2i]):
	var i: int = 0
	for hex in path:
		if path.size() <= i + 1:
			return
		var from_pos = LOSHelper.ground_layer.map_to_local(path[i])
		var to_pos = LOSHelper.ground_layer.map_to_local(path[i+1])

		chain_of_command.append({
			"from": from_pos,
			"to": to_pos,
			"timer": 0.0,
			"duration": 2.0  # Line fades out over 2 seconds
		})

		queue_redraw()
		
		i += 1


func _on_draw_draw_movement_path(from_hex: Vector2i, path: Array[Vector2i]):
	var i: int = 0
	for hex in path:
		if path.size() <= i + 1:
			return
		var from_pos = LOSHelper.ground_layer.map_to_local(path[i])
		var to_pos = LOSHelper.ground_layer.map_to_local(path[i+1])

		movement_path.append({
			"from": from_pos,
			"to": to_pos,
			"timer": 0.0,
			"duration": 2.0  # Line fades out over 2 seconds
		})

		queue_redraw()
		
		i += 1


func _on_draw_los_to_target_unit(from_hex: Vector2i, to_hex: Vector2i):
	var from_pos = LOSHelper.ground_layer.map_to_local(from_hex)
	var to_pos = LOSHelper.ground_layer.map_to_local(to_hex)

	los_to_target.append({
		"from": from_pos,
		"to": to_pos,
		"timer": 0.0,
		"duration": 2.0  # Line fades out over 2 seconds
	})

	queue_redraw()


func _on_draw_los_to_enemy(from_hex: Vector2i, to_hex: Vector2i):
	var from_pos = LOSHelper.ground_layer.map_to_local(from_hex)
	var to_pos = LOSHelper.ground_layer.map_to_local(to_hex)

	los_enemy_lines.append({
		"from": from_pos,
		"to": to_pos,
		"timer": 0.0,
		"duration": 2.0  # Line fades out over 2 seconds
	})

	queue_redraw()


func _draw():
	#return
	# 🔥 New: Draw blue lines to visible enemies
	for los_data in los_enemy_lines:
		draw_line(los_data["from"], los_data["to"], Color(0.36, 0.074, 0.005, 1.0), 2.0)
	for los_data in los_to_target:
		draw_line(los_data["from"], los_data["to"], Color(0.895, 0.0, 0.316, 1.0), 2.0)
	for los_data in movement_path:
		draw_line(los_data["from"], los_data["to"], Color(0.044, 0.0, 0.953, 1.0), 2.0)
	for los_data in chain_of_command:
		draw_line(los_data["from"], los_data["to"], Color(0.0, 0.391, 0.122, 1.0), 2.0)
	for connection in leader_presence_strength:
		draw_line(connection["from"], connection["to"], strength_to_color_hsv(connection["strength"]), 1.0)


func strength_to_color_hsv(strength: float) -> Color:
	var s: float = strength

	if s < 0.0:
		s = 0.0
	else:
		if s > 1.0:
			s = 1.0

	var hue: float = 0.33 * s   # 0.0 → 0.33 (red → green)
	return Color.from_hsv(hue, 1.0, 1.0, 1.0)

func _process(delta):
	for line in los_enemy_lines:
		line["timer"] += delta
	# Remove fully expired lines
	los_enemy_lines = los_enemy_lines.filter(func(line):
		return line["timer"] < line["duration"]
	)
	
	
	
	for line in los_to_target:
		line["timer"] += delta
	# Remove fully expired lines
	los_to_target = los_to_target.filter(func(line):
		return line["timer"] < line["duration"]
	)
	
	
	for line in movement_path:
		line["timer"] += delta
	# Remove fully expired lines
	movement_path = movement_path.filter(func(line):
		return line["timer"] < line["duration"]
	)
	
	
	for line in movement_path:
		line["timer"] += delta
	# Remove fully expired lines
	movement_path = movement_path.filter(func(line):
		return line["timer"] < line["duration"]
	)
	
	
	for line in leader_presence_strength:
		line["timer"] += delta
	# Remove fully expired lines
	leader_presence_strength = leader_presence_strength.filter(func(line):
		return line["timer"] < line["duration"]
	)
	
	

	queue_redraw()  # Always request redraw if lines change
