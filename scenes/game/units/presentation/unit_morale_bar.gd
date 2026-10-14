@tool
extends ProgressBar
class_name UnitMoraleBar

var _fill: StyleBoxFlat = StyleBoxFlat.new()


func _ready() -> void:
	var track: StyleBoxFlat = StyleBoxFlat.new()
	track.bg_color = Color("0c151a")
	track.set_corner_radius_all(2)
	track.set_border_width_all(1)
	track.border_color = Color("56615d")
	_fill.bg_color = Color("81c6a3")
	_fill.set_corner_radius_all(2)
	add_theme_stylebox_override("background", track)
	add_theme_stylebox_override("fill", _fill)
	max_value = 1.0
	step = 0.001
	show_percentage = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_morale(pressure: float, state: int) -> void:
	var remaining: float = 1.0 - clampf(pressure, 0.0, 1.0)
	var tint: Color = UnitHudStyle.morale_color(state)
	if is_equal_approx(value, remaining) and _fill.bg_color == tint:
		return
	value = remaining
	_fill.bg_color = tint
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
