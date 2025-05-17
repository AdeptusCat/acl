extends Node

signal mouse_button_left_pressed(event_pos)
signal key_space_pressed(event_pos)


func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
		mouse_button_left_pressed.emit(event.position)
	if event is InputEventKey and event.pressed and event.scancode==KEY_SPACE:
		key_space_pressed.emit(event.position)
