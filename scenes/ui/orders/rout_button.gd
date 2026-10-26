extends Button
class_name RoutButton

const ROUT_EXPLANATION: String = "Pinned or broken: normal movement is blocked.\nRout attempts an uncontrolled retreat.\nNo escape route means surrender."

@export var alert_color: Color = Color(0.85, 0.55, 0.3, 1.0)
@export var normal_bg_color: Color = Color(0.18, 0.12, 0.08, 1.0)
@export var hover_bg_color: Color = Color(0.28, 0.18, 0.1, 1.0)


func _ready() -> void:
	_apply_alert_style()


func set_rout_available(is_available: bool) -> void:
	disabled = not is_available
	visible = is_available
	text = "Rout squad"
	tooltip_text = ROUT_EXPLANATION


func _apply_alert_style() -> void:
	var normal_style: StyleBoxFlat = _style(normal_bg_color)
	var hover_style: StyleBoxFlat = _style(hover_bg_color)
	add_theme_stylebox_override("normal", normal_style)
	add_theme_stylebox_override("hover", hover_style)
	add_theme_stylebox_override("pressed", hover_style)
	add_theme_color_override("font_color", Color(0.95, 0.83, 0.64))
	add_theme_color_override("font_hover_color", Color.WHITE)
	add_theme_color_override("font_pressed_color", Color.WHITE)


func _style(background: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = alert_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	return style
