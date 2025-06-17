shader_type canvas_item;
render_mode blend_mix;

uniform float grain_strength = 0.35;

float rand(vec2 co) {
	return fract(sin(dot(co.xy, vec2(12.9898,78.233))) * 43758.5453);
}

void fragment() {
	float vignette = smoothstep(1.0, 0.6, length(UV - vec2(0.5)));
	float noise = rand(UV + TIME * 0.1);
	vec3 grain = vec3(noise * 1.5 - 0.25); // increases contrast
	COLOR = vec4(grain, noise * grain_strength * vignette);
}
