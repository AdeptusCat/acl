extends Node

signal mouse_button_left_pressed(event_pos)
signal mouse_button_right_pressed(event_pos)
signal right_button_pressed()
signal right_button_released()

signal key_space_pressed(event_pos)
signal mouse_event_position_changed(event_pos)
signal zoom_in
signal zoom_out

func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	if Input.is_action_just_pressed("RIGHT"):
		right_button_pressed.emit()
	elif Input.is_action_just_released("RIGHT"):
		right_button_released.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
		mouse_button_left_pressed.emit(event.position)
func _input(event):
	#if event is InputEventMouseButton and event.pressed and event.button_index == MouseButton.MOUSE_BUTTON_RIGHT:
		#print("released")
		#mouse_button_right_pressed.emit(event.position)
	if event is InputEventMouseMotion:
		mouse_event_position_changed.emit(event.position)
	#if event is InputEventKey and event.pressed and event.scancode==KEY_SPACE:
		#key_space_pressed.emit(event.position)

#func _unhandled_input(event):
	if event.is_action_pressed("zoom_in"):
		zoom_in.emit()
	if event.is_action_pressed("zoom_out"):
		zoom_out.emit()
