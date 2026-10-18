class_name SightLineGraphic
extends RefCounted

const INK: Color = Color("#382B27")
const CLEAR: Color = Color("#E8DABD")
const BLOCKED: Color = Color("#C94D3F")
const HINDRANCE_COLORS: Array[Color] = [
	Color("#E4BF67"), Color("#CB9838"), Color("#9C6B27"), Color("#674822")
]


static func draw(canvas: CanvasItem, origin: Vector2, target: Vector2, blocked: bool, obstruction: Vector2, decorated: bool = true, opacity: float = 1.0, hindrance_points: PackedVector2Array = PackedVector2Array()) -> void:
	var length: float = origin.distance_to(target)
	if length < 0.01 or not origin.is_finite() or not target.is_finite():
		return
	# Keep the graphic legible without growing thick when zooming in.
	var zoom: float = maxf(absf(canvas.get_global_transform_with_canvas().get_scale().x), 0.05)
	var pixel: float = 1.0 / zoom
	var direction: Vector2 = (target - origin) / length
	var normal: Vector2 = Vector2(-direction.y, direction.x)
	var inset_start: float = 0.0
	var inset_end: float = 0.0
	if decorated:
		inset_start = minf(7.0 * pixel, length * 0.2)
		inset_end = minf(13.0 * pixel, length * 0.2)
	var start: Vector2 = origin + direction * inset_start
	var finish: Vector2 = target - direction * inset_end
	var clear_color: Color = CLEAR
	clear_color.a = opacity
	var blocked_color: Color = BLOCKED
	blocked_color.a = opacity * 0.85
	var target_color: Color = clear_color
	if blocked:
		var stop: Vector2 = origin
		if obstruction.is_finite():
			stop = Geometry2D.get_closest_point_to_segment(obstruction, origin, target)
		var stop_distance: float = origin.distance_to(stop)
		var clear_end: Vector2 = origin + direction * clampf(stop_distance - 3.0 * pixel, inset_start, length - inset_end)
		var blocked_start: Vector2 = origin + direction * clampf(stop_distance + 5.0 * pixel, inset_start, length - inset_end)
		_hindered_line(canvas, origin, start, clear_end, direction, normal, hindrance_points, pixel, opacity, decorated)
		_dashes(canvas, blocked_start, finish, blocked_color, pixel)
		if decorated:
			_stop_marker(canvas, stop, direction, normal, blocked_color, pixel)
		target_color = blocked_color
	else:
		target_color = _hindered_line(canvas, origin, start, finish, direction, normal, hindrance_points, pixel, opacity, decorated)
	if decorated:
		_reticle(canvas, target, target_color, pixel, not blocked and hindrance_points.size() >= 3)
		_arc(canvas, origin, 3.5 * pixel, 0.0, TAU, clear_color, 1.2 * pixel)


static func _hindrance_color(count: int, opacity: float) -> Color:
	var color: Color = CLEAR
	if count > 0:
		color = HINDRANCE_COLORS[mini(count - 1, HINDRANCE_COLORS.size() - 1)]
		if count > HINDRANCE_COLORS.size():
			color = color.darkened(1.0 - pow(0.88, float(count - HINDRANCE_COLORS.size())))
	color.a = opacity
	return color


static func _hindered_line(canvas: CanvasItem, origin: Vector2, start: Vector2, finish: Vector2, direction: Vector2, normal: Vector2, crossings: PackedVector2Array, pixel: float, opacity: float, decorated: bool) -> Color:
	var span_start: Vector2 = start
	var count: int = 0
	var start_distance: float = (start - origin).dot(direction)
	var end_distance: float = (finish - origin).dot(direction)
	for point: Vector2 in crossings:
		if not point.is_finite():
			continue
		var distance: float = (point - origin).dot(direction)
		var span_end: Vector2 = origin + direction * clampf(distance, start_distance, end_distance)
		_hindrance_span(canvas, span_start, span_end, direction, normal, count, pixel, opacity, decorated)
		span_start = span_end
		count += 1
	_hindrance_span(canvas, span_start, finish, direction, normal, count, pixel, opacity, decorated)
	if decorated:
		for point: Vector2 in crossings:
			var distance: float = (point - origin).dot(direction)
			if point.is_finite() and distance >= start_distance and distance <= end_distance:
				_hindrance_marker(canvas, point, direction, normal, pixel, opacity)
	return _hindrance_color(count, opacity)


static func _hindrance_span(canvas: CanvasItem, start: Vector2, finish: Vector2, direction: Vector2, normal: Vector2, count: int, pixel: float, opacity: float, decorated: bool) -> void:
	var color: Color = _hindrance_color(count, opacity)
	_stroke(canvas, start, finish, color, 1.8 * pixel, count >= 3)
	if decorated:
		_ticks(canvas, start, finish, direction, normal, color, pixel, count >= 3)


static func _hindrance_marker(canvas: CanvasItem, point: Vector2, direction: Vector2, normal: Vector2, pixel: float, opacity: float) -> void:
	var outline: PackedVector2Array = PackedVector2Array([
		point - direction * 4.5 * pixel, point + normal * 4.5 * pixel,
		point + direction * 4.5 * pixel, point - normal * 4.5 * pixel
	])
	var ink: Color = INK
	ink.a = opacity * 0.9
	canvas.draw_colored_polygon(outline, ink)
	var diamond: PackedVector2Array = PackedVector2Array([
		point - direction * 3.0 * pixel, point + normal * 3.0 * pixel,
		point + direction * 3.0 * pixel, point - normal * 3.0 * pixel
	])
	var amber: Color = HINDRANCE_COLORS[1]
	amber.a = opacity
	canvas.draw_colored_polygon(diamond, amber)


static func _stroke(canvas: CanvasItem, start: Vector2, finish: Vector2, color: Color, width: float, pale_keyline: bool = false) -> void:
	if start.distance_squared_to(finish) < 0.001:
		return
	var ink: Color = INK
	ink.a = color.a * 0.85
	canvas.draw_line(start, finish, ink, width * 2.5, true)
	if pale_keyline:
		var edge: Color = CLEAR
		edge.a = color.a * 0.75
		canvas.draw_line(start, finish, edge, width * 1.7, true)
	canvas.draw_line(start, finish, color, width, true)


static func _dashes(canvas: CanvasItem, start: Vector2, finish: Vector2, color: Color, pixel: float) -> void:
	var length: float = start.distance_to(finish)
	if length < 0.01:
		return
	var direction: Vector2 = (finish - start) / length
	var distance: float = 0.0
	while distance < length:
		var end: float = minf(distance + 8.0 * pixel, length)
		_stroke(canvas, start + direction * distance, start + direction * end, color, 1.4 * pixel)
		distance += 14.0 * pixel


static func _ticks(canvas: CanvasItem, start: Vector2, finish: Vector2, direction: Vector2, normal: Vector2, color: Color, pixel: float, pale_keyline: bool = false) -> void:
	var length: float = start.distance_to(finish)
	var distance: float = 48.0 * pixel
	var tick_color: Color = color
	tick_color.a *= 0.65
	while distance < length - 18.0 * pixel:
		var point: Vector2 = start + direction * distance
		_stroke(canvas, point - normal * 2.5 * pixel, point + normal * 2.5 * pixel, tick_color, pixel, pale_keyline)
		distance += 48.0 * pixel


static func _stop_marker(canvas: CanvasItem, point: Vector2, direction: Vector2, normal: Vector2, color: Color, pixel: float) -> void:
	_stroke(canvas, point - normal * 6.0 * pixel, point + normal * 6.0 * pixel, color, 2.0 * pixel)
	_stroke(canvas, point - normal * 6.0 * pixel, point - normal * 6.0 * pixel - direction * 3.0 * pixel, color, 1.3 * pixel)
	_stroke(canvas, point + normal * 6.0 * pixel, point + normal * 6.0 * pixel - direction * 3.0 * pixel, color, 1.3 * pixel)


static func _reticle(canvas: CanvasItem, point: Vector2, color: Color, pixel: float, pale_keyline: bool = false) -> void:
	for index: int in range(4):
		var angle: float = index * PI * 0.5
		_arc(canvas, point, 10.0 * pixel, angle - PI / 6.0, angle + PI / 6.0, color, 1.5 * pixel, pale_keyline)
	var ink: Color = INK
	ink.a = color.a * 0.85
	canvas.draw_circle(point, 2.3 * pixel, ink, true, -1.0, true)
	if pale_keyline:
		var edge: Color = CLEAR
		edge.a = color.a * 0.75
		canvas.draw_circle(point, 1.7 * pixel, edge, true, -1.0, true)
	canvas.draw_circle(point, pixel, color, true, -1.0, true)


static func _arc(canvas: CanvasItem, point: Vector2, radius: float, start_angle: float, end_angle: float, color: Color, width: float, pale_keyline: bool = false) -> void:
	var ink: Color = INK
	ink.a = color.a * 0.85
	canvas.draw_arc(point, radius, start_angle, end_angle, 24, ink, width * 2.5, true)
	if pale_keyline:
		var edge: Color = CLEAR
		edge.a = color.a * 0.75
		canvas.draw_arc(point, radius, start_angle, end_angle, 24, edge, width * 1.7, true)
	canvas.draw_arc(point, radius, start_angle, end_angle, 24, color, width, true)
