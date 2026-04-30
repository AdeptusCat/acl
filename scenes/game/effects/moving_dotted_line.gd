extends Node2D
class_name MovingDottedDrawLine

const DOTTED_LINE_SHADER: String = """
shader_type canvas_item;
render_mode unshaded, blend_mix;

uniform vec4 line_color : source_color = vec4(1.0, 0.9, 0.15, 0.5);

uniform vec2 line_start = vec2(0.0, 0.0);
uniform vec2 line_end = vec2(100.0, 0.0);

uniform float line_width_px = 40.0;

uniform float dash_px = 14.0;
uniform float gap_px = 10.0;
uniform float speed_px = 70.0;

uniform float dash_softness_px = 4.0;
uniform float side_softness_px = 20.0;

varying vec2 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	vec2 line_vec = line_end - line_start;
	float line_len = max(length(line_vec), 0.001);
	vec2 line_dir = line_vec / line_len;

	vec2 from_start = local_pos - line_start;

	float distance_along = dot(from_start, line_dir);
	float distance_side = abs(from_start.x * line_dir.y - from_start.y * line_dir.x);

	float half_width = line_width_px * 0.5;

	float side_softness = clamp(side_softness_px, 0.001, half_width);
	float side_alpha = 1.0 - smoothstep(
		half_width - side_softness,
		half_width,
		distance_side
	);

	float period = max(dash_px + gap_px, 0.001);
	float moving_distance = distance_along + TIME * speed_px;
	float dash_pos = mod(moving_distance, period);

	float dash_alpha = 0.0;

	if (dash_pos <= dash_px) {
		float dash_softness = clamp(dash_softness_px, 0.001, dash_px * 0.49);

		float start_alpha = smoothstep(
			0.0,
			dash_softness,
			dash_pos
		);

		float end_alpha = 1.0 - smoothstep(
			dash_px - dash_softness,
			dash_px,
			dash_pos
		);

		dash_alpha = start_alpha * end_alpha;
	}

	float line_alpha = 1.0;

	if (distance_along < 0.0 || distance_along > line_len) {
		line_alpha = 0.0;
	}

	COLOR = line_color;
	COLOR.a *= dash_alpha * side_alpha * line_alpha;
}
"""

@export var line_width: float = 60.0
@export var line_color: Color = Color(1.0, 0.9, 0.15, 0.5)
@export var dash_px: float = 14.0
@export var gap_px: float = 10.0
@export var speed_px: float = 70.0
@export var edge_softness_px: float = 5.0

var line_start: Vector2 = Vector2.ZERO
var line_end: Vector2 = Vector2(100.0, 0.0)

var _shader_material: ShaderMaterial

var unit: Unit

func set_unit(_unit):
	unit = _unit


func _ready() -> void:
	var shader: Shader = Shader.new()
	shader.code = DOTTED_LINE_SHADER

	_shader_material = ShaderMaterial.new()
	_shader_material.shader = shader
	material = _shader_material

	_apply_shader_params()
	queue_redraw()
	set_line(Vector2(300,300), Vector2(100,100))

func set_line(from_pos: Vector2, to_pos: Vector2) -> void:
	line_start = from_pos
	line_end = to_pos

	_apply_shader_params()
	queue_redraw()


func _draw() -> void:
	draw_line(line_start, line_end, Color.WHITE, line_width, true)


func _apply_shader_params() -> void:
	if _shader_material == null:
		return

	_shader_material.set_shader_parameter("line_color", line_color)
	_shader_material.set_shader_parameter("line_start", line_start)
	_shader_material.set_shader_parameter("line_end", line_end)
	_shader_material.set_shader_parameter("dash_px", dash_px)
	_shader_material.set_shader_parameter("gap_px", gap_px)
	_shader_material.set_shader_parameter("speed_px", speed_px)
	_shader_material.set_shader_parameter("edge_softness_px", edge_softness_px)
