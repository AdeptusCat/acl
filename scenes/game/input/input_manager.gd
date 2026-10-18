extends Node

signal mouse_button_left_pressed(event_pos: Vector2)
signal mouse_button_right_pressed(event_pos: Vector2)
signal right_button_pressed()
signal right_button_released()

signal key_space_pressed(event_pos: Vector2)
signal mouse_event_position_changed(event_pos: Vector2)
signal zoom_in
signal zoom_out

var pointer_position: Vector2
var _battle_input_enabled: bool = false
var _right_button_held: bool = false

func _ready() -> void:
	set_process(false)


func set_battle_input_enabled(enabled: bool) -> void:
	_battle_input_enabled = enabled
	if not enabled:
		_right_button_held = false


func _unhandled_input(event: InputEvent) -> void:
	if not _battle_input_enabled:
		return
	if event.is_action_pressed("RIGHT"):
		_right_button_held = true
		right_button_pressed.emit()
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.pressed and event.button_index == MouseButton.MOUSE_BUTTON_LEFT:
		mouse_button_left_pressed.emit(event.position)
	# HUD controls consume wheel events before they can zoom the map.
	if event.is_action_pressed("zoom_in"):
		zoom_in.emit()
	if event.is_action_pressed("zoom_out"):
		zoom_out.emit()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		pointer_position = event.position
	if _battle_input_enabled and _right_button_held and event.is_action_released("RIGHT"):
		_right_button_held = false
		right_button_released.emit()
		get_viewport().set_input_as_handled()
	#if event is InputEventMouseButton and event.pressed and event.button_index == MouseButton.MOUSE_BUTTON_RIGHT:
		#print("released")
		#mouse_button_right_pressed.emit(event.position)
	if event is InputEventMouseMotion:
		mouse_event_position_changed.emit(event.position)
	#if event is InputEventKey and event.pressed and event.scancode==KEY_SPACE:
		#key_space_pressed.emit(event.position)
