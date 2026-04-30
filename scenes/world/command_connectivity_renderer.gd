extends Node2D


func setup():
	for unit in Globals.get_units():
		var aim_line: MovingDottedDrawLine = MovingDottedDrawLine.new()
		add_child(aim_line)
		aim_line.set_unit(unit)


func _process(_delta: float) -> void:
	for line in get_children():
		if is_instance_valid(line.unit.command_squad):
			line.set_line(
				line.unit.position,
				line.unit.command_squad.position
			)
			#line.line_width = clamp(line.unit.command_connectivity.leader_presence_strength * 10, 1.0, 10.0) 
			line.line_color = strength_to_color_hsv(line.unit.command_connectivity.leader_presence_strength)
			line._shader_material.set_shader_parameter("line_width_px", clamp(line.unit.command_connectivity.leader_presence_strength * 10, 1.0, 10.0) )
			line.show()
		else:
			line.hide()

func strength_to_color_hsv(strength: float) -> Color:
	var s: float = strength

	if s < 0.0:
		s = 0.0
	else:
		if s > 1.0:
			s = 1.0

	var hue: float = 0.33 * s   # 0.0 → 0.33 (red → green)
	return Color.from_hsv(hue, 1.0, 1.0, 0.3)
