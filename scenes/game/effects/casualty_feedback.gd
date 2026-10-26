extends Node2D

# One reusable cue per unit. Repeated losses combine instead of stacking popups.
const DURATION: float = 1.35
const FADE_SECONDS: float = 0.35
const PULSE_SECONDS: float = 0.65

var casualty_count: int = 0
var elapsed: float = 0.0
var active: bool = false
var badge_visible: bool = true


func _ready() -> void:
	z_index = 20
	clear()


func show_losses(count: int, show_badge: bool = true) -> void:
	if count <= 0:
		return
	casualty_count += count
	elapsed = 0.0
	active = true
	# Keep a close-combat cue suppressed until it expires, including on death.
	badge_visible = badge_visible and show_badge
	show()
	set_process(true)
	queue_redraw()


func suppress_badge() -> void:
	if not badge_visible:
		return
	badge_visible = false
	queue_redraw()


func clear() -> void:
	casualty_count = 0
	elapsed = 0.0
	active = false
	badge_visible = true
	hide()
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if not active:
		return
	elapsed += maxf(delta, 0.0)
	# Do not retain a hidden enemy's cue for a later reveal.
	if elapsed >= DURATION or not is_visible_in_tree():
		clear()
		return
	queue_redraw()


func _draw() -> void:
	if not active:
		return
	var fade: float = clampf((DURATION - elapsed) / FADE_SECONDS, 0.0, 1.0)
	var pulse: float = clampf(1.0 - elapsed / PULSE_SECONDS, 0.0, 1.0)
	pulse *= 0.7 + 0.3 * cos(elapsed * TAU / 0.26)
	var frame: Rect2 = Rect2(-2.0, -3.0, 68.0, 66.0)
	draw_rect(frame, Color(0.95, 0.08, 0.03, pulse * 0.18))
	draw_rect(frame, Color(0.12, 0.02, 0.01, pulse), false, 4.0)
	draw_rect(frame, Color(1.0, 0.18, 0.08, pulse), false, 2.0)
	if not badge_visible:
		return

	var rise: float = 12.0 * (1.0 - pow(1.0 - minf(elapsed / 0.7, 1.0), 2.0))
	var badge: Rect2 = Rect2(-6.0, -26.0 - rise, 76.0, 30.0)
	draw_rect(badge.grow(1.0), Color(0.05, 0.02, 0.01, fade))
	draw_rect(badge, Color(0.23, 0.035, 0.02, fade * 0.96))
	draw_rect(badge, Color(1.0, 0.28, 0.16, fade), false, 1.0)
	var font: Font = ThemeDB.fallback_font
	var loss_text: String = "−%d" % casualty_count
	var caption: String = "CASUALTY"
	if casualty_count > 1:
		caption = "CASUALTIES"
	var loss_width: float = font.get_string_size(loss_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18).x
	var caption_width: float = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8).x
	draw_string(font, Vector2(32.0 - loss_width * 0.5, badge.position.y + 17.0), loss_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color(1.0, 0.96, 0.84, fade))
	draw_string(font, Vector2(32.0 - caption_width * 0.5, badge.position.y + 27.0), caption, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, Color(1.0, 0.78, 0.68, fade))
