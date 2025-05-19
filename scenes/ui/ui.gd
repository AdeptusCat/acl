extends CanvasLayer


@onready var timer_label = $HBoxContainer/TimerLabel


func _on_update_timer_label(time_left_seconds : float):
	var minutes = int(time_left_seconds) / 60
	var seconds = int(time_left_seconds) % 60
	timer_label.text = "Time left: %02d:%02d" % [minutes, seconds]


func mouse_event_position_changed(event_pos: Vector2):
	pass
