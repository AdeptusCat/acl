shader_type canvas_item;

uniform vec4 fog_color : source_color = vec4(0.8, 0.75, 0.7, 1.0);
uniform float fog_strength = 0.3;

void fragment() {
	float vignette = smoothstep(1.0, 0.3, length(UV - vec2(0.5)));
	COLOR = fog_color * vignette * fog_strength;
}