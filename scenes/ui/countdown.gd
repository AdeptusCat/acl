extends PanelContainer


@onready var timer_label = $HBoxContainer/TimerLabel
@onready var timer = $Timer

var opacity_tween: Tween = null
var scale_tween: Tween = null

var started: bool = false
var alert_threshold_s: int = 30


func set_countdown(_started: bool):
	started = _started
	if started:
		timer.stop()
		if opacity_tween:
			opacity_tween.kill()
		timer_label.modulate.a = 1.0


func update_timer_label(time_left_seconds: float):
	var minutes: int = int(time_left_seconds) / 60
	var seconds: int = int(time_left_seconds) % 60
	timer_label.text = "%02d:%02d" % [minutes, seconds]
	if time_left_seconds < alert_threshold_s:
		timer_label.modulate = Color(0.947, 0.0, 0.0, 1.0)
		if timer.is_stopped():
			timer.start(1.0)
	if time_left_seconds == 0.0:
		timer.stop()


func _on_timer_timeout() -> void:
	if not started:
		if timer_label.modulate.a < 1.0:
			tween_opacity(1.0)
			timer.start(0.5)
		else:
			tween_opacity(0.1)
			timer.start(1.0)
	if started:
		timer.start(1.0)
		tween_scale()
	#await tween_opacity(0.0).finished


func tween_scale():
	if scale_tween: 
		scale_tween.kill()
	scale_tween = get_tree().create_tween()
	scale_tween.tween_property(timer_label, 'scale', Vector2(1.5, 1.5), 0.2)
	scale_tween.tween_property(timer_label, 'scale', Vector2(1.0, 1.0), 0.2)
	return scale_tween



func tween_opacity(to: float):
	if opacity_tween: 
		opacity_tween.kill()
	opacity_tween = get_tree().create_tween()
	opacity_tween.tween_property(timer_label, 'modulate:a', to, 0.3)
	return opacity_tween
