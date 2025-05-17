extends Node

signal unit_clicked(unit, hex)
signal move_requested(from_hex, to_hex)
signal end_turn

@onready var ground = $"../GroundLayer"
@onready var container = $"../UnitContainer"

func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
		var map_hex = ground.local_to_map(event.position)
		# find unit under cursor
		for u in container.get_children():
			if ground.local_to_map(u.position)==map_hex:
				emit_signal("unit_clicked", u, map_hex)
				return
		emit_signal("move_requested", null, map_hex)
	if event is InputEventKey and event.pressed and event.scancode==KEY_SPACE:
		pass
