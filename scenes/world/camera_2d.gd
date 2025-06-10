extends Camera2D

# Lower cap for the `_zoom_level`.
@export var min_zoom := 0.5
# Upper cap for the `_zoom_level`.
@export var max_zoom := 2.0
# Controls how much we increase or decrease the `_zoom_level` on every turn of the scroll wheel.
@export var zoom_factor := 0.1
# Duration of the zoom's tween animation.
@export var zoom_duration := 0.2

# The camera's target zoom level.
var _zoom_level: float = 1.0 


@export var speed: float = 400.0


func _physics_process(delta):
	var direction: Vector2 = Vector2.ZERO
	if Input.is_action_pressed("up"):
		direction.y -= 1
	if Input.is_action_pressed("down"):
		direction.y += 1
	if Input.is_action_pressed("right"):
		direction.x += 1
	if Input.is_action_pressed("left"):
		direction.x -= 1
	
	if direction != Vector2.ZERO:
		direction = direction.normalized() 
		position += direction * speed * delta



func zoom_in():
	_set_zoom_level(_zoom_level - zoom_factor)


func zoom_out():
	_set_zoom_level(_zoom_level + zoom_factor)


func _set_zoom_level(value: float) -> void:
	# We limit the value between `min_zoom` and `max_zoom`
	_zoom_level = clamp(value, min_zoom, max_zoom)
	# Then, we ask the tween node to animate the camera's `zoom` property from its current value
	# to the target zoom level.
	var tween: Tween = create_tween()
	#en.tween_property(sprite_node.material, "shader_parameter/dissolve_amount", 1.0, 0.6)
	tween.tween_property(
		self,
		"zoom",
		Vector2(_zoom_level, _zoom_level),
		zoom_duration
	)
