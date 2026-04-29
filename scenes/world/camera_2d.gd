extends Camera2D

@export var min_zoom: float = 0.5
@export var max_zoom: float = 2.0
@export var zoom_factor: float = 0.1
@export var zoom_duration: float = 0.2

@export var speed: float = 400.0
@export var edge_margin: float = 80.0

var _zoom_level: float = 1.0
var _zoom_tween: Tween

var map_rect: Rect2 = Rect2(Vector2.ZERO, Vector2.ZERO)
var last_pos: Vector2 = Vector2.INF

signal camera_moved


func set_camera_limit(_map_size: Vector2) -> void:
	map_rect = Rect2(Vector2.ZERO, _map_size)

	# Optional backup limits for Camera2D itself.
	#limit_left = int(map_rect.position.x - edge_margin)
	#limit_top = int(map_rect.position.y - edge_margin)
	#limit_right = int(map_rect.position.x + map_rect.size.x + edge_margin)
	#limit_bottom = int(map_rect.position.y + map_rect.size.y + edge_margin)

	position = _clamp_camera_position(position)
	last_pos = position


func _physics_process(delta: float) -> void:
	var direction: Vector2 = Vector2.ZERO

	if Input.is_action_pressed("up"):
		direction.y -= 1.0
	if Input.is_action_pressed("down"):
		direction.y += 1.0
	if Input.is_action_pressed("right"):
		direction.x += 1.0
	if Input.is_action_pressed("left"):
		direction.x -= 1.0

	if direction != Vector2.ZERO:
		direction = direction.normalized()

		var new_position: Vector2 = position + direction * speed * delta
		#position = new_position
		position = _clamp_camera_position(new_position)

	if position.distance_to(last_pos) > 0.5:
		last_pos = position
		camera_moved.emit()


func _clamp_camera_position(target_position: Vector2) -> Vector2:
	var bounds: Rect2 = map_rect.grow(edge_margin)

	var viewport_size: Vector2 = get_viewport_rect().size
	var visible_half_size: Vector2 = viewport_size * 0.5 / zoom

	var min_pos: Vector2 = Vector2.ZERO # bounds.position# + visible_half_size
	var max_pos: Vector2 = bounds.size# bounds.position# + bounds.size - visible_half_size

	var clamped_position: Vector2 = target_position

	if min_pos.x > max_pos.x:
		clamped_position.x = bounds.get_center().x
	else:
		clamped_position.x = clamp(target_position.x, min_pos.x, max_pos.x)

	if min_pos.y > max_pos.y:
		clamped_position.y = bounds.get_center().y
	else:
		clamped_position.y = clamp(target_position.y, min_pos.y, max_pos.y)
	
	return clamped_position


func zoom_in() -> void:
	_set_zoom_level(_zoom_level + zoom_factor)


func zoom_out() -> void:
	_set_zoom_level(_zoom_level - zoom_factor)


func _set_zoom_level(value: float) -> void:
	_zoom_level = clamp(value, min_zoom, max_zoom)

	if _zoom_tween != null:
		if _zoom_tween.is_valid():
			_zoom_tween.kill()

	_zoom_tween = create_tween()
	_zoom_tween.tween_property(
		self,
		"zoom",
		Vector2(_zoom_level, _zoom_level),
		zoom_duration
	)

	_zoom_tween.tween_callback(_on_zoom_finished)


func _on_zoom_finished() -> void:
	position = _clamp_camera_position(position)
