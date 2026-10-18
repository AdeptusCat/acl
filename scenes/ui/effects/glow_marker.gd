extends ColorRect

@export var duration: float = 0.4

func _ready() -> void:
	position -= size/2
	modulate.a = 1.0
	var shader_mat: ShaderMaterial = material as ShaderMaterial
	shader_mat.set_shader_parameter("glow_alpha", 1.0)
	var tween: Tween = create_tween()
	tween.tween_method(func(val: float) -> void: shader_mat.set_shader_parameter("glow_alpha", val), 1.0, 0.0, 0.4)
	tween.tween_callback(queue_free)
	
