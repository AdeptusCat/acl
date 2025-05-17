extends Node2D

var lines = []  # {from, to, timer, duration}
var los_enemy_lines: Array = []


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
	# 🔥 New: Draw blue lines to visible enemies
	for los_data in los_enemy_lines:
		draw_line(los_data["from"], los_data["to"], Color(0, 0, 1), 2.0)


func _process(delta):
	for line in los_enemy_lines:
		line["timer"] += delta

	# Remove fully expired lines
	los_enemy_lines = los_enemy_lines.filter(func(line):
		return line["timer"] < line["duration"]
	)

	queue_redraw()  # Always request redraw if lines change
