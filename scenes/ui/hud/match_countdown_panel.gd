extends PanelContainer

@onready var timer_label: Label = $HBoxContainer/TimerLabel

var started: bool = false
var alert_threshold_s: int = 30
var _time_left_seconds: float = 600.0
var _alert_active: bool = false
var _alert_tween: Tween


func set_countdown(is_started: bool) -> void:
	started = is_started
	_update_alert()


func update_timer_label(time_left_seconds: float) -> void:
	$HBoxContainer/Label2.text = "Time left: "
	_time_left_seconds = maxf(0.0, time_left_seconds)
	var minutes: int = int(_time_left_seconds / 60.0)
	var seconds: int = int(_time_left_seconds) % 60
	timer_label.text = "%02d:%02d" % [minutes, seconds]
	_update_alert()


func update_overtime_label(elapsed_seconds: float) -> void:
	_stop_alert_tween()
	var seconds: int = maxi(0, int(elapsed_seconds))
	$HBoxContainer/Label2.text = "Overtime: "
	timer_label.text = "+%02d:%02d" % [seconds / 60, seconds % 60]
	timer_label.modulate = Color(0.96, 0.68, 0.32)


func _update_alert() -> void:
	var time_low: bool = started and _time_left_seconds <= float(alert_threshold_s)
	if time_low:
		timer_label.modulate = Color(0.96, 0.48, 0.32)
	else:
		timer_label.modulate = Color.WHITE
	if time_low and not _alert_active and _time_left_seconds > 0.0:
		# One brief cue when the countdown enters its final thirty seconds.
		_stop_alert_tween()
		timer_label.pivot_offset = timer_label.size * 0.5
		_alert_tween = create_tween()
		_alert_tween.tween_property(timer_label, "scale", Vector2(1.1, 1.1), 0.12)
		_alert_tween.tween_property(timer_label, "scale", Vector2.ONE, 0.18)
	if not time_low or _time_left_seconds <= 0.0:
		_stop_alert_tween()
	_alert_active = time_low


func _stop_alert_tween() -> void:
	if _alert_tween != null and _alert_tween.is_valid():
		_alert_tween.kill()
	_alert_tween = null
	timer_label.scale = Vector2.ONE
