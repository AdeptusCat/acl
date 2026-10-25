shader_type canvas_item;
render_mode unshaded;

uniform vec4 area_color : source_color = vec4(0.95, 0.74, 0.32, 1.0);
uniform vec2 corners[6];
uniform float exposed_edges[6];
uniform vec2 center;
uniform float objective_phase = 0.0;

varying vec2 area_position;

void vertex() {
	area_position = VERTEX;
}

float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 edge = b - a;
	return length(p - a - edge * clamp(dot(p - a, edge) / dot(edge, edge), 0.0, 1.0));
}

void fragment() {
	vec2 p = area_position - center;
	float boundary = 10000.0;
	for (int i = 0; i < 6; i++) {
		if (exposed_edges[i] > 0.5) {
			boundary = min(boundary, segment_distance(p, corners[i], corners[(i + 1) % 6]));
		}
	}
	float aa = max(fwidth(boundary), 0.65);
	float rim = 1.0 - smoothstep(1.4, 1.4 + aa, boundary);
	float inner_rail = 1.0 - smoothstep(0.65, 0.65 + aa, abs(boundary - 5.0));
	float motion = area_position.x * 0.7 + area_position.y * 0.45 - TIME * 15.0 + objective_phase;
	float dashes = smoothstep(0.35, 0.5, sin(motion * 0.18));
	float sweep = pow(0.5 + 0.5 * sin((area_position.x + area_position.y) * 0.025 - TIME * 1.2 + objective_phase), 8.0);
	float glow = exp(-boundary * 0.17);
	float hatch = smoothstep(0.93, 1.0, sin((area_position.x - area_position.y - TIME * 5.0) * 0.22));
	float alpha = 0.045 + hatch * 0.025 + sweep * 0.055 + glow * 0.15;
	alpha += rim * 0.72 + inner_rail * dashes * 0.42;
	vec3 tint = area_color.rgb + vec3(rim * 0.16 + sweep * 0.08);
	COLOR = vec4(tint, min(alpha, 0.95) * area_color.a);
}
