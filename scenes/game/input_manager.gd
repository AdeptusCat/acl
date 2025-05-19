extends Node

signal mouse_button_left_pressed(event_pos)
signal key_space_pressed(event_pos)
signal mouse_event_position_changed(event_pos)

func set_input(enabled: bool):
	set_process_input(enabled)


func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
		mouse_button_left_pressed.emit(event.position)
	if event is InputEventMouseMotion:
		mouse_event_position_changed.emit(event.position)
	#if event is InputEventKey and event.pressed and event.scancode==KEY_SPACE:
		#key_space_pressed.emit(event.position)
	
