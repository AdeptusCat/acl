extends CanvasLayer

signal game_started(team : int)
signal hover_start_button(team: int)
signal time_changed(_time: float)

@onready var objective_label = $Control/CenterContainer/PanelContainer/VBoxContainer/VBoxContainer/ObjectiveLabel
@onready var start_as_axis_button = $Control/CenterContainer/PanelContainer/VBoxContainer/VBoxContainer/StartAsAxisButton
@onready var start_as_allies_button = $Control/CenterContainer/PanelContainer/VBoxContainer/VBoxContainer/StartAsAlliesButton
@onready var animation_player = $AnimationPlayer
@onready var time_spinbox = $Control/CenterContainer/PanelContainer/VBoxContainer/HBoxContainer/SpinBox


var time: float

func _ready():
	if not SessionSettings.mission_time == 0:
		time_spinbox.value = SessionSettings.mission_time
	visible = true
	start_as_axis_button.pressed.connect(_on_start_as_axis_pressed)
	start_as_allies_button.pressed.connect(_on_start_as_allies_pressed)
	animation_player.play("fade_in")  # Play when screen appears
	time = time_spinbox.value
	time_changed.emit.call_deferred(time)


func _on_set_objective_text(hex: String):
	objective_label.text = "Hold objective (red circle) with an unbroken unit when the time runs out!"


func _on_start_as_axis_pressed():
	animation_player.play("fade_out")
	await animation_player.animation_finished
	visible = false
	game_started.emit(0)


func _on_start_as_allies_pressed():
	animation_player.play("fade_out")
	await animation_player.animation_finished
	visible = false
	game_started.emit(1)


func _on_spin_box_value_changed(value: float) -> void:
	time = value
	SessionSettings.mission_time = value
	time_changed.emit(time)


func _on_start_as_axis_button_mouse_entered() -> void:
	hover_start_button.emit(0)


func _on_start_as_axis_button_mouse_exited() -> void:
	hover_start_button.emit(-1)


func _on_start_as_allies_button_mouse_entered() -> void:
	hover_start_button.emit(1)


func _on_start_as_allies_button_mouse_exited() -> void:
	hover_start_button.emit(-1)
