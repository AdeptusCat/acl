extends Node2D

const MAX_STRIKES: int = 16
const STRIKE_SECONDS: float = 0.5
const LOSS_SECONDS: float = 1.25
const RESULT_SECONDS: float = 2.4
const FRIENDLY_COLOR: Color = Color(0.48, 0.85, 0.60)
const ENEMY_COLOR: Color = Color(0.96, 0.40, 0.30)

var hex: Vector2i = Vector2i.ZERO
var outline: PackedVector2Array = PackedVector2Array([
	Vector2(0, -58), Vector2(50, -29), Vector2(50, 29),
	Vector2(0, 58), Vector2(-50, 29), Vector2(-50, -29),
])
var counts: Dictionary[Globals.Team, int] = {Globals.Team.AXIS: 0, Globals.Team.ALLIES: 0}
var roles: Dictionary[Globals.Team, String] = {Globals.Team.AXIS: "ENGAGED", Globals.Team.ALLIES: "ENGAGED"}
var recent_losses: Dictionary[Globals.Team, int] = {Globals.Team.AXIS: 0, Globals.Team.ALLIES: 0}
var loss_remaining: Dictionary[Globals.Team, float] = {Globals.Team.AXIS: 0.0, Globals.Team.ALLIES: 0.0}
var strikes: Array[Dictionary] = []
var resolved: bool = false
var opening_contact: bool = false
var result_text: String = "COMBAT ENDED"
var elapsed: float = 0.0
var result_elapsed: float = 0.0
var visibility_test: Callable
var _ground_id: int = 0
var _random: RandomNumberGenerator = RandomNumberGenerator.new()
var _strike_remaining: Dictionary[Globals.Team, float] = {Globals.Team.AXIS: 0.0, Globals.Team.ALLIES: 0.0}


func _ready() -> void:
	top_level = true
	z_index = 16
	_random.randomize()
	if is_instance_valid(LOSHelper.ground_layer):
		_ground_id = LOSHelper.ground_layer.get_instance_id()
	advance(0.0)


func can_display() -> bool:
	if visibility_test.is_valid():
		return bool(visibility_test.call())
	if not is_instance_valid(LOSHelper.ground_layer) or LOSHelper.ground_layer.get_instance_id() != _ground_id:
		return false
	return Debug.hide_fog_of_war or LOSHelper.visible_hexes.get(Globals.team_player, []).has(hex)


func set_force(team: Globals.Team, living: int, role: String) -> void:
	counts[team] = living
	roles[team] = role
	queue_redraw()


func set_opening_contact(value: bool) -> void:
	opening_contact = value
	queue_redraw()


func record_exchange(actor: Globals.Team, victim: Globals.Team, casualty: bool) -> void:
	if resolved or not can_display():
		return
	var confirmed_loss: bool = casualty and counts[victim] >= 0
	if confirmed_loss:
		recent_losses[victim] += 1
		loss_remaining[victim] = LOSS_SECONDS
	if not confirmed_loss and _strike_remaining[actor] > 0.0:
		return
	_strike_remaining[actor] = 0.08
	if strikes.size() >= MAX_STRIKES:
		strikes.pop_front()
	strikes.append({"age": 0.0, "point": Vector2(_random.randf_range(-24.0, 24.0), _random.randf_range(-18.0, 24.0)), "actor": actor, "casualty": confirmed_loss})
	queue_redraw()


func finish() -> void:
	if resolved:
		return
	resolved = true
	result_elapsed = 0.0
	if counts[Globals.Team.ALLIES] > 0 and counts[Globals.Team.AXIS] == 0:
		result_text = "US HOLDS HEX"
	elif counts[Globals.Team.AXIS] > 0 and counts[Globals.Team.ALLIES] == 0:
		result_text = "GER HOLDS HEX"
	if not can_display():
		queue_free()
	queue_redraw()


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	var step: float = maxf(0.0, delta)
	elapsed += step
	if not visibility_test.is_valid() and (not is_instance_valid(LOSHelper.ground_layer) or LOSHelper.ground_layer.get_instance_id() != _ground_id):
		queue_free()
		return
	visible = can_display()
	for team: Globals.Team in loss_remaining:
		loss_remaining[team] = maxf(0.0, loss_remaining[team] - step)
		_strike_remaining[team] = maxf(0.0, _strike_remaining[team] - step)
		if loss_remaining[team] <= 0.0 or not visible:
			recent_losses[team] = 0
	for index: int in range(strikes.size() - 1, -1, -1):
		strikes[index]["age"] += step
		if strikes[index]["age"] >= STRIKE_SECONDS or not visible:
			strikes.remove_at(index)
	if resolved:
		result_elapsed += step
		modulate.a = clampf((RESULT_SECONDS - result_elapsed) / 0.6, 0.0, 1.0)
		if result_elapsed >= RESULT_SECONDS or not visible:
			queue_free()
	queue_redraw()


func _color(team: Globals.Team) -> Color:
	if team == Globals.team_player:
		return FRIENDLY_COLOR
	return ENEMY_COLOR


func _text(text: String, center: Vector2, size: int, color: Color) -> void:
	var font: Font = ThemeDB.fallback_font
	var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x
	draw_string(font, center - Vector2(width * 0.5, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)


func _draw() -> void:
	if not can_display():
		return
	var pulse: float = 0.5 + 0.5 * sin(elapsed * TAU * 1.8)
	var accent: Color = Color(1.0, 0.65, 0.18)
	if resolved:
		pulse = 0.0
		accent = Color(0.75, 0.73, 0.65)
		if counts[Globals.Team.ALLIES] > 0 and counts[Globals.Team.AXIS] == 0:
			accent = _color(Globals.Team.ALLIES)
		elif counts[Globals.Team.AXIS] > 0 and counts[Globals.Team.ALLIES] == 0:
			accent = _color(Globals.Team.AXIS)
	var border: PackedVector2Array = outline.duplicate()
	border.append(outline[0])
	draw_colored_polygon(outline, Color(0.65, 0.16, 0.035, 0.07 + pulse * 0.04))
	draw_polyline(border, Color(0.06, 0.025, 0.01, 0.9), 5.0, true)
	draw_polyline(border, Color(accent.r, accent.g, accent.b, 0.6 + pulse * 0.35), 2.0 + pulse, true)
	for strike: Dictionary in strikes:
		var progress: float = float(strike["age"]) / STRIKE_SECONDS
		var fade: float = 1.0 - progress
		var point: Vector2 = strike["point"]
		var direction: float = -1.0
		if strike["actor"] == Globals.Team.ALLIES:
			direction = 1.0
		var flash: Color = Color(1.8, 1.35, 0.6, fade)
		if strike["casualty"]:
			flash = Color(1.5, 0.22, 0.09, fade)
		draw_circle(point + Vector2.UP * progress * 9.0, 6.0 + progress * 18.0, Color(0.68, 0.56, 0.35, fade * 0.16))
		if progress < 0.45:
			draw_line(point - Vector2(direction * 14.0, 5.0), point + Vector2(direction * 6.0, -2.0), flash, 2.5, true)
			draw_circle(point, 2.0 + fade * 3.0, flash)
		for ray: int in range(4):
			var offset: Vector2 = Vector2.from_angle(float(ray) * TAU / 4.0 + direction) * (4.0 + progress * 15.0)
			draw_line(point + offset, point + offset * 1.35, Color(flash.r, flash.g, flash.b, fade * 0.6), 1.0, true)
	# Keep labels readable when zoomed out without changing the physical hex outline.
	var zoom: float = maxf(get_global_transform_with_canvas().get_scale().x, 0.05)
	var label_scale: float = clampf(1.0 / zoom, 0.8, 1.6)
	draw_set_transform(Vector2(0.0, -58.0), 0.0, Vector2.ONE * label_scale)
	var badge: Rect2 = Rect2(-92.0, -54.0, 184.0, 51.0)
	draw_rect(badge, Color(0.045, 0.035, 0.025, 0.96))
	draw_rect(badge, Color(accent.r, accent.g, accent.b, 0.9), false, 1.0)
	if resolved:
		_text(result_text, Vector2(0.0, -25.0), 14, Color(1.0, 0.88, 0.60))
	else:
		var heading: String = "CLOSE COMBAT"
		if opening_contact:
			heading = "CLOSE CONTACT"
		_text(heading, Vector2(0.0, -38.0), 12, Color(1.0, 0.85, 0.52))
		_text("vs", Vector2(0.0, -20.0), 10, Color(0.8, 0.77, 0.69))
		var teams: Array[Globals.Team] = [Globals.Team.ALLIES, Globals.Team.AXIS]
		var names: Array[String] = ["US", "GER"]
		for index: int in range(teams.size()):
			var team: Globals.Team = teams[index]
			var x: float = -48.0 + float(index) * 96.0
			var count: String = "?"
			if counts[team] >= 0:
				count = str(counts[team])
			_text(names[index] + " " + count, Vector2(x, -21.0), 14, _color(team))
			_text(roles[team], Vector2(x, -9.0), 8, Color(0.83, 0.81, 0.73))
	for team: Globals.Team in recent_losses:
		if recent_losses[team] <= 0:
			continue
		var x: float = -48.0
		var name: String = "US"
		if team == Globals.Team.AXIS:
			x = 48.0
			name = "GER"
		var age: float = 1.0 - loss_remaining[team] / LOSS_SECONDS
		_text(name + " -" + str(recent_losses[team]), Vector2(x, 15.0 - age * 10.0), 14, Color(1.0, 0.35, 0.24, clampf(loss_remaining[team] / 0.3, 0.0, 1.0)))
	draw_set_transform(Vector2.ZERO)
