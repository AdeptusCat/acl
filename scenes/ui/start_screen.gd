extends CanvasLayer

signal game_started(team : int)

@onready var objective_label = $CenterContainer/VBoxContainer/ObjectiveLabel
@onready var start_as_axis_button = $CenterContainer/VBoxContainer/StartAsAxisButton
@onready var start_as_allies_button = $CenterContainer/VBoxContainer/StartAsAlliesButton
@onready var animation_player = $AnimationPlayer

func _ready():
	visible = true
	start_as_axis_button.pressed.connect(_on_start_as_axis_pressed)
	start_as_allies_button.pressed.connect(_on_start_as_allies_pressed)
	animation_player.play("fade_in")  # Play when screen appears


func _on_set_objective_text(hex: String):
	objective_label.text = "Hold hex at %s (red circle) with an unbroken unit!" % hex


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
