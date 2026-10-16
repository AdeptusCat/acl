class_name BattlefieldTracer
extends Node2D

enum Kind { BULLET, ROCKET, GRENADE, MORTAR }
enum Surface { GROUND, WOOD, STONE, WATER, FOLIAGE, ROAD }

const MUZZLE_SECONDS: float = 0.045
const ARRIVAL_FADE_SECONDS: float = 0.045

@export var speed: float = 1200.0

signal arrived
signal finished

var visibility_test: Callable
var screen_test: Callable
var active: bool = false
var flight_time: float = 0.0
var elapsed: float = 0.0
var has_arrived: bool = false
var kind: Kind = Kind.BULLET
var surface: Surface = Surface.GROUND
var show_streak: bool = true
var origin: Vector2 = Vector2.ZERO
var destination: Vector2 = Vector2.ZERO
var head: Vector2 = Vector2.ZERO

var _direction: Vector2 = Vector2.RIGHT
var _distance: float = 0.0
var _frame_seconds: float = 1.0 / 60.0
var _weapon: WeaponSpec
var _audio_pool: AudioPool
var _random: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_random.randomize()
	set_process(false)
	hide()


func launch(from: Vector2, to: Vector2, weapon: WeaponSpec, shot_kind: Kind, impact_surface: Surface, tracer_visible: bool) -> void:
	origin = from
	destination = to
	head = from
	_direction = (to - from).normalized()
	_distance = from.distance_to(to)
	_weapon = weapon
	kind = shot_kind
	surface = impact_surface
	show_streak = tracer_visible
	speed = float(weapon.projectile_speed)
	if kind == Kind.GRENADE:
		speed = float(weapon.riflegrenade_projectile_speed)
	speed = maxf(speed, 1.0)
	flight_time = _distance / speed
	elapsed = 0.0
	_frame_seconds = 1.0 / 60.0
	has_arrived = false
	active = true
	_audio_pool = get_node_or_null("/root/Main/World/AudioPool") as AudioPool
	show()
	set_process(true)
	queue_redraw()


func deactivate() -> void:
	active = false
	_weapon = null
	_audio_pool = null
	hide()
	set_process(false)


func _process(delta: float) -> void:
	advance(delta)


func advance(delta: float) -> void:
	if not active:
		return
	elapsed += maxf(delta, 0.0)
	_frame_seconds = clampf(delta, 1.0 / 120.0, 1.0 / 15.0)
	if elapsed >= flight_time:
		head = destination
	else:
		head = origin + _direction * minf(elapsed * speed, _distance)
	if not has_arrived and elapsed >= flight_time:
		head = destination
		has_arrived = true
		_play_impact_sound()
		arrived.emit()
		if not active:
			return
	if elapsed >= flight_time + impact_duration():
		deactivate()
		finished.emit()
	queue_redraw()


func impact_duration() -> float:
	if kind == Kind.BULLET:
		return 0.28
	return 0.65


func _can_draw_at(point: Vector2) -> bool:
	if visibility_test.is_valid() and not bool(visibility_test.call(point)):
		return false
	if screen_test.is_valid() and not bool(screen_test.call(point)):
		return false
	return true


func _draw() -> void:
	if not active:
		return
	var zoom: float = maxf(get_global_transform_with_canvas().get_scale().x, 0.05)
	var size_scale: float = clampf(1.0 / zoom, 0.75, 1.8)
	if elapsed < MUZZLE_SECONDS and kind != Kind.MORTAR and _can_draw_at(origin):
		_draw_muzzle(size_scale)
	if show_streak and elapsed < flight_time + ARRIVAL_FADE_SECONDS:
		_draw_flight(zoom)
	if has_arrived and _can_draw_at(destination):
		_draw_impact(size_scale)


func _draw_muzzle(size_scale: float) -> void:
	var fade: float = 1.0 - elapsed / MUZZLE_SECONDS
	var radius: float = 5.0 * size_scale * fade
	if kind == Kind.ROCKET:
		radius *= 1.5
	draw_circle(origin, radius * 1.7, Color(1.0, 0.45, 0.10, fade * 0.12))
	draw_circle(origin, radius * 0.55, Color(2.2, 1.7, 0.75, fade))
	draw_line(origin - _direction * radius * 0.4, origin + _direction * radius * 2.0, Color(2.2, 1.9, 1.2, fade), maxf(radius * 0.4, 0.7), true)


func trail_start() -> Vector2:
	var length: float = maxf(18.0, speed * _frame_seconds)
	if kind == Kind.ROCKET:
		length = 24.0
	elif kind == Kind.GRENADE or kind == Kind.MORTAR:
		length = 6.0
	length = minf(length, 72.0)
	return head - _direction * minf(length, origin.distance_to(head))


func _draw_flight(zoom: float) -> void:
	var tail: Vector2 = trail_start()
	var fade: float = 1.0
	if has_arrived:
		fade = clampf(1.0 - (elapsed - flight_time) / ARRIVAL_FADE_SECONDS, 0.0, 1.0)
	var width: float = clampf(1.2 / zoom, 0.7, 3.0)
	var tail_color: Color = Color(1.25, 0.70, 0.22, fade)
	var head_color: Color = Color(2.1, 1.75, 1.0, fade)
	if kind != Kind.BULLET:
		tail_color = Color(0.48, 0.44, 0.34, fade)
		head_color = tail_color
		width *= 1.5
	# Short segments prevent a visible head from exposing a tail inside hidden hexes.
	var steps: int = maxi(1, ceili(tail.distance_to(head) / 6.0))
	for index: int in range(steps):
		var a: Vector2 = tail.lerp(head, float(index) / float(steps))
		var b: Vector2 = tail.lerp(head, float(index + 1) / float(steps))
		if not _can_draw_at(a) or not _can_draw_at(b) or not _can_draw_at(a.lerp(b, 0.5)):
			continue
		var start_fraction: float = float(index) / float(steps)
		var end_fraction: float = float(index + 1) / float(steps)
		var start_color: Color = tail_color.lerp(head_color, start_fraction)
		var end_color: Color = tail_color.lerp(head_color, end_fraction)
		start_color.a *= start_fraction * start_fraction
		end_color.a *= end_fraction * end_fraction
		if kind == Kind.BULLET or kind == Kind.ROCKET:
			_draw_segment(a, b, width * 3.5, Color(1.0, 0.48, 0.12, start_color.a * 0.10), Color(1.0, 0.48, 0.12, end_color.a * 0.10))
		_draw_segment(a, b, width, start_color, end_color)
	if _can_draw_at(head):
		var tip: Color = Color(2.3, 2.0, 1.35, fade)
		if kind != Kind.BULLET:
			tip = Color(0.25, 0.26, 0.22, fade)
		var tip_radius: float = width * 0.6
		if kind == Kind.GRENADE:
			tip_radius = width * 1.2
		draw_circle(head, tip_radius, tip)
	if kind == Kind.ROCKET:
		_draw_exhaust(tail, width, fade)


func _draw_segment(a: Vector2, b: Vector2, width: float, start_color: Color, end_color: Color) -> void:
	var normal: Vector2 = _direction.orthogonal() * width * 0.5
	draw_polygon(PackedVector2Array([a - normal, b - normal, b + normal, a + normal]), PackedColorArray([start_color, end_color, end_color, start_color]))


func _draw_exhaust(tail: Vector2, width: float, fade: float) -> void:
	var engine: Vector2 = head - _direction * 3.0
	if _can_draw_at(engine):
		draw_circle(engine, width * 0.75, Color(1.9, 0.7, 0.15, fade * 0.8))
	for index: int in range(5):
		var point: Vector2 = tail - _direction * float(index * 5)
		if _can_draw_at(point):
			var age: float = float(index) / 5.0
			draw_circle(point, width * (1.2 + age), Color(0.58, 0.55, 0.50, (1.0 - age) * 0.20 * fade))


func _draw_impact(size_scale: float) -> void:
	var age: float = maxf(0.0, elapsed - flight_time)
	var progress: float = clampf(age / impact_duration(), 0.0, 1.0)
	var fade: float = (1.0 - progress) * (1.0 - progress)
	var color: Color = Color(0.60, 0.49, 0.32, fade * 0.65)
	match surface:
		Surface.WOOD:
			color = Color(0.64, 0.39, 0.18, fade)
		Surface.STONE, Surface.ROAD:
			color = Color(0.72, 0.71, 0.64, fade)
		Surface.WATER:
			color = Color(0.67, 0.85, 0.90, fade * 0.85)
		Surface.FOLIAGE:
			color = Color(0.40, 0.52, 0.19, fade)
	var radius: float = (2.0 + progress * 11.0) * size_scale
	var fragments: int = 6
	if kind != Kind.BULLET:
		radius *= 2.5
		fragments = 12
		if age < 0.12:
			var flash: float = 1.0 - age / 0.12
			draw_circle(destination, (7.0 + age * 70.0) * size_scale, Color(2.6, 1.1, 0.20, flash * 0.85))
	if surface == Surface.WATER:
		draw_arc(destination, radius, 0.0, TAU, 20, color, size_scale, true)
	else:
		draw_circle(destination, radius * 0.7, Color(color.r, color.g, color.b, fade * 0.10))
	for index: int in range(fragments):
		var angle: float = float(index) * 2.399963 + _direction.angle()
		var spread: Vector2 = Vector2.from_angle(angle) * radius * (0.45 + float(index % 3) * 0.2)
		var point: Vector2 = destination + spread
		if not _can_draw_at(point):
			continue
		if surface == Surface.WOOD or surface == Surface.FOLIAGE:
			draw_line(point, point + Vector2.from_angle(angle) * 3.0 * size_scale, color, size_scale, true)
		else:
			draw_circle(point, maxf(0.7, size_scale * (1.0 - progress)), color)


func _play_impact_sound() -> void:
	if not is_instance_valid(_audio_pool) or _weapon == null:
		return
	var sound: AudioStream = null
	var volume: float = 0.0
	if kind == Kind.GRENADE:
		sound = _weapon.riflegrenade_hit
		volume = 6.0
	elif kind == Kind.ROCKET or kind == Kind.MORTAR:
		sound = _weapon.snd_hit
	if sound != null:
		_audio_pool.play_one_shot(sound, destination, volume, _random.randf_range(0.97, 1.03), "SFX_Close")


static func predict_end_position(from: Vector2, to: Vector2, projectile_speed: float, lifetime: float) -> Vector2:
	return from.move_toward(to, maxf(0.0, projectile_speed * lifetime))
