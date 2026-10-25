extends Node2D

enum State { NONE, PINNED, SURRENDERED, ELIMINATED, FLANKED, SURROUNDED }

const TRANSITION_SECONDS: float = 1.1
const FADE_SECONDS: float = 0.6
const LIFETIME_SECONDS: float = TRANSITION_SECONDS + FADE_SECONDS
const SKULL: Texture2D = preload("res://assets/effects/skull.png")
const FRAME_RECT: Rect2 = Rect2(-2.0, -3.0, 68.0, 66.0)
const RIBBON_RECT: Rect2 = Rect2(-10.0, 65.0, 84.0, 17.0)

var state: State = State.NONE
var elapsed: float = LIFETIME_SECONDS
var ribbon_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	z_index = 15
	hide()
	set_process(false)


func set_state(next: State, emphasize: bool = true) -> void:
	# Morale and action controllers can publish the same state in one frame.
	if next == state:
		return
	state = next
	elapsed = LIFETIME_SECONDS
	modulate = Color.WHITE
	if next == State.NONE:
		hide()
		set_process(false)
	else:
		show()
		if emphasize and is_visible_in_tree():
			elapsed = 0.0
		advance(0.0)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree() and state != State.NONE:
		if not is_visible_in_tree():
			# Revealing an enemy must not replay a notification from behind the fog.
			elapsed = LIFETIME_SECONDS
			if _is_temporary():
				modulate.a = 0.0
				hide()
			set_process(false)
			queue_redraw()


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if state == State.NONE:
		return
	elapsed = minf(elapsed + maxf(delta, 0.0), LIFETIME_SECONDS)
	if not is_visible_in_tree():
		elapsed = LIFETIME_SECONDS
	if _is_temporary():
		modulate.a = 1.0 - clampf((elapsed - TRANSITION_SECONDS) / FADE_SECONDS, 0.0, 1.0)
		if elapsed >= LIFETIME_SECONDS:
			hide()
		set_process(elapsed < LIFETIME_SECONDS)
	else:
		set_process(elapsed < TRANSITION_SECONDS)
	queue_redraw()


func _is_temporary() -> bool:
	return state != State.NONE and state != State.ELIMINATED


func contains_screen_point(screen_point: Vector2) -> bool:
	if state == State.NONE or not is_visible_in_tree() or modulate.a <= 0.0:
		return false
	var local_point: Vector2 = get_global_transform_with_canvas().affine_inverse() * screen_point
	return FRAME_RECT.has_point(local_point) or Rect2(RIBBON_RECT.position + ribbon_offset, RIBBON_RECT.size).has_point(local_point)


func _draw() -> void:
	if state == State.NONE:
		return
	var accent: Color = Color(1.0, 0.70, 0.12)
	var caption: String = "PINNED"
	match state:
		State.FLANKED:
			accent = Color(1.0, 0.54, 0.14)
			caption = "FLANKED"
		State.SURROUNDED:
			accent = Color(1.0, 0.28, 0.18)
			caption = "SURROUNDED"
		State.SURRENDERED:
			accent = Color(0.96, 0.96, 0.88)
			caption = "SURRENDERED"
		State.ELIMINATED:
			accent = Color(1.0, 0.22, 0.12)
			caption = "ELIMINATED"
	var pulse: float = clampf(1.0 - elapsed / TRANSITION_SECONDS, 0.0, 1.0)
	var pulse_alpha: float = pulse * (0.65 + 0.35 * cos(elapsed * TAU / 0.32))
	var frame: Rect2 = FRAME_RECT
	if pulse > 0.0:
		draw_rect(frame, Color(accent.r, accent.g, accent.b, pulse_alpha * 0.20))
		draw_arc(Vector2(32.0, 29.0), 37.0 + elapsed * 18.0, 0.0, TAU, 48, Color(accent.r, accent.g, accent.b, pulse * 0.7), 2.0, true)

	match state:
		State.ELIMINATED:
			draw_circle(Vector2(32.0, 28.0), 28.0, Color(0.10, 0.025, 0.02, 0.94))
			draw_line(Vector2(8.0, 4.0), Vector2(56.0, 52.0), Color(0.03, 0.02, 0.01), 5.0, true)
			draw_line(Vector2(8.0, 52.0), Vector2(56.0, 4.0), Color(0.03, 0.02, 0.01), 5.0, true)
			draw_line(Vector2(8.0, 4.0), Vector2(56.0, 52.0), accent, 2.5, true)
			draw_line(Vector2(8.0, 52.0), Vector2(56.0, 4.0), accent, 2.5, true)
			draw_texture_rect(SKULL, Rect2(17.0, 10.0, 30.0, 34.0), false, Color(1.0, 0.94, 0.80))

	# The state ribbon sits below the counter; casualty counts float above it.
	draw_set_transform(ribbon_offset)
	var badge: Rect2 = RIBBON_RECT
	draw_rect(badge.grow(1.0), Color(0.03, 0.02, 0.01))
	draw_rect(badge, Color(accent.r * 0.16, accent.g * 0.12, accent.b * 0.09, 0.96))
	match state:
		State.PINNED:
			_draw_pin(Vector2(-4.0, 69.0), 0.65, accent)
		State.SURRENDERED:
			_draw_flag(Vector2(-4.0, 68.0), 0.7, accent)
		State.ELIMINATED:
			draw_texture_rect(SKULL, Rect2(-5.0, 68.0, 9.0, 11.0), false, Color(1.0, 0.94, 0.80))
		State.FLANKED:
			_draw_tactical_arrows(Vector2(0.0, 73.0), 2, accent)
		State.SURROUNDED:
			_draw_tactical_arrows(Vector2(0.0, 73.0), 4, accent)
	var font: Font = ThemeDB.fallback_font
	var text_width: float = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9).x
	draw_string(font, Vector2(39.0 - text_width * 0.5, 76.5), caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 9, Color(1.0, 0.97, 0.88))


func _draw_tactical_arrows(center: Vector2, count: int, color: Color) -> void:
	for index: int in range(count):
		var direction: Vector2 = Vector2.from_angle(float(index) * TAU / float(count))
		var tip: Vector2 = center + direction
		var side: Vector2 = direction.orthogonal() * 1.5
		var head: PackedVector2Array = PackedVector2Array([tip + direction * 2.0 + side, tip, tip + direction * 2.0 - side])
		draw_line(center + direction * 6.0, tip, Color(0.04, 0.02, 0.01), 3.0, true)
		draw_polyline(head, Color(0.04, 0.02, 0.01), 3.0, true)
		draw_line(center + direction * 6.0, tip, color, 1.0, true)
		draw_polyline(head, color, 1.0, true)


func _draw_pin(point: Vector2, icon_scale: float, color: Color) -> void:
	for row: int in range(2):
		var top: Vector2 = point + Vector2(0.0, float(row) * 4.0 * icon_scale)
		var chevron: PackedVector2Array = PackedVector2Array([top, top + Vector2(5.0, 4.0) * icon_scale, top + Vector2(10.0, 0.0) * icon_scale])
		draw_polyline(chevron, Color(0.04, 0.03, 0.01), 4.0 * icon_scale, true)
		draw_polyline(chevron, color, 2.0 * icon_scale, true)


func _draw_flag(point: Vector2, icon_scale: float, color: Color) -> void:
	var bottom: Vector2 = point + Vector2(0.0, 15.0) * icon_scale
	draw_line(point, bottom, Color(0.04, 0.03, 0.02), 3.5 * icon_scale, true)
	draw_line(point, bottom, color, 1.5 * icon_scale, true)
	var cloth: Rect2 = Rect2(point + Vector2(1.0, 0.0) * icon_scale, Vector2(10.0, 7.0) * icon_scale)
	draw_rect(cloth.grow(icon_scale), Color(0.04, 0.03, 0.02))
	draw_rect(cloth, color)
