extends Button
class_name RoutButton

@export var pulse_color: Color = Color(1.0, 0.28, 0.12, 1.0)
@export var normal_bg_color: Color = Color(0.18, 0.05, 0.03, 1.0)
@export var hover_bg_color: Color = Color(0.28, 0.08, 0.04, 1.0)
@export var font_alert_color: Color = Color(1.0, 0.9, 0.75, 1.0)

@export var pulse_scale: Vector2 = Vector2(1.08, 1.08)
@export var pulse_time_s: float = 0.35

var _pulse_tween: Tween
var _base_scale: Vector2 = Vector2.ONE
var _base_modulate: Color = Color.WHITE
var _is_attention_active: bool = false


func _ready() -> void:
	_base_scale = scale
	_base_modulate = modulate

	pivot_offset = size * 0.5
	resized.connect(_on_resized)


func _on_resized() -> void:
	pivot_offset = size * 0.5


func set_rout_available(is_available: bool) -> void:
	if is_available:
		disabled = false
		visible = true
		text = "Rout"
		_start_attention()
	else:
		disabled = true
		_stop_attention()
		visible = false


func _start_attention() -> void:
	if _is_attention_active:
		return

	_is_attention_active = true

	_apply_alert_style()
	_start_pulse()


func _stop_attention() -> void:
	_is_attention_active = false

	if _pulse_tween != null:
		if _pulse_tween.is_valid():
			_pulse_tween.kill()

	_pulse_tween = null

	scale = _base_scale
	modulate = _base_modulate

	_remove_alert_style()


func _start_pulse() -> void:
	if _pulse_tween != null:
		if _pulse_tween.is_valid():
			_pulse_tween.kill()

	scale = _base_scale
	modulate = _base_modulate

	_pulse_tween = create_tween()
	_pulse_tween.set_loops()

	_pulse_tween.tween_property(
		self,
		"scale",
		_base_scale * pulse_scale,
		pulse_time_s
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	_pulse_tween.parallel().tween_property(
		self,
		"modulate",
		pulse_color,
		pulse_time_s
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	_pulse_tween.tween_property(
		self,
		"scale",
		_base_scale,
		pulse_time_s
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

	_pulse_tween.parallel().tween_property(
		self,
		"modulate",
		_base_modulate,
		pulse_time_s
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _apply_alert_style() -> void:
	var normal_style: StyleBoxFlat = StyleBoxFlat.new()
	normal_style.bg_color = normal_bg_color
	normal_style.border_color = pulse_color
	normal_style.set_border_width_all(2)
	normal_style.set_corner_radius_all(5)
	normal_style.content_margin_left = 10.0
	normal_style.content_margin_right = 10.0
	normal_style.content_margin_top = 6.0
	normal_style.content_margin_bottom = 6.0

	var hover_style: StyleBoxFlat = StyleBoxFlat.new()
	hover_style.bg_color = hover_bg_color
	hover_style.border_color = Color(1.0, 0.65, 0.25, 1.0)
	hover_style.set_border_width_all(3)
	hover_style.set_corner_radius_all(5)
	hover_style.content_margin_left = 10.0
	hover_style.content_margin_right = 10.0
	hover_style.content_margin_top = 6.0
	hover_style.content_margin_bottom = 6.0

	var pressed_style: StyleBoxFlat = StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.12, 0.02, 0.01, 1.0)
	pressed_style.border_color = Color(1.0, 0.85, 0.35, 1.0)
	pressed_style.set_border_width_all(2)
	pressed_style.set_corner_radius_all(5)
	pressed_style.content_margin_left = 10.0
	pressed_style.content_margin_right = 10.0
	pressed_style.content_margin_top = 6.0
	pressed_style.content_margin_bottom = 6.0

	add_theme_stylebox_override("normal", normal_style)
	add_theme_stylebox_override("hover", hover_style)
	add_theme_stylebox_override("pressed", pressed_style)

	add_theme_color_override("font_color", font_alert_color)
	add_theme_color_override("font_hover_color", Color.WHITE)
	add_theme_color_override("font_pressed_color", Color.WHITE)


func _remove_alert_style() -> void:
	remove_theme_stylebox_override("normal")
	remove_theme_stylebox_override("hover")
	remove_theme_stylebox_override("pressed")

	remove_theme_color_override("font_color")
	remove_theme_color_override("font_hover_color")
	remove_theme_color_override("font_pressed_color")
