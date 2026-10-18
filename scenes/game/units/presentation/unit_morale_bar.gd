@tool
extends ProgressBar
class_name UnitMoraleBar

var _track: StyleBoxFlat = StyleBoxFlat.new()
var _fill: StyleBoxFlat = StyleBoxFlat.new()


func _ready() -> void:
	_track.bg_color = Color("0c151a")
	_track.set_corner_radius_all(2)
	_track.set_border_width_all(1)
	_track.border_color = UnitHudStyle.SUPPORT_COLOR
	_fill.bg_color = UnitHudStyle.SUPPORT_COLOR
	_fill.set_corner_radius_all(2)
	add_theme_stylebox_override("background", _track)
	add_theme_stylebox_override("fill", _fill)
	max_value = 1.0
	step = 0.001
	show_percentage = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_morale(pressure: float, platoon_color: Color) -> void:
	var remaining: float = 1.0 - clampf(pressure, 0.0, 1.0)
	if is_equal_approx(value, remaining) and _fill.bg_color == platoon_color:
		return
	value = remaining
	if _fill.bg_color != platoon_color:
		_fill.bg_color = platoon_color
		_track.border_color = platoon_color
	queue_redraw()


func _draw() -> void:
	for segment: int in range(1, 5):
		var fraction: float = float(segment) / 5.0
		if fill_mode == ProgressBar.FILL_BOTTOM_TO_TOP or fill_mode == ProgressBar.FILL_TOP_TO_BOTTOM:
			var y: float = size.y * fraction
			draw_line(Vector2(1.0, y), Vector2(size.x - 1.0, y), Color("0c151a"), 1.0)
		else:
			var x: float = size.x * fraction
			draw_line(Vector2(x, 1.0), Vector2(x, size.y - 1.0), Color("0c151a"), 1.0)
