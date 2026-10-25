shader_type canvas_item;
render_mode unshaded;

uniform vec4 area_color : source_color = vec4(0.95, 0.74, 0.32, 1.0);
uniform vec2 corners[6];
uniform float exposed_edges[6];
uniform vec2 center;
uniform float objective_phase = 0.0;
uniform float capture_progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 capture_color : source_color = vec4(0.48, 0.85, 0.60, 1.0);
uniform vec2 capture_span = vec2(-64.0, 64.0);

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
	// Twelve discrete bands switch on at fixed capture thresholds; colors never fade.
	float height = clamp((dot(p, vec2(0.45, -1.0)) - capture_span.x) / (capture_span.y - capture_span.x), 0.0, 0.9999);
	float band_position = height * 12.0;
	float filled_bands = floor(clamp(capture_progress, 0.0, 1.0) * 12.0 + 0.0001);
	float filled = 1.0 - step(filled_bands, floor(band_position));
	float stripe = step(0.20, fract(band_position)) * (1.0 - step(0.75, fract(band_position)));
	float capture_mask = filled * stripe;
	// Keep the connected objective perimeter legible over the capture bands.
	capture_mask *= step(7.0, boundary);
	tint = mix(tint, capture_color.rgb, capture_mask);
	alpha = mix(alpha, 0.80 * capture_color.a, capture_mask);
	// A moving inner capture ring announces activity before the first band fills.
	float active = step(0.00001, capture_progress) * (1.0 - step(1.0, capture_progress));
	float capture_ring = 1.0 - smoothstep(1.1, 1.1 + aa, abs(boundary - 10.0));
	float moving_marks = step(0.0, sin((area_position.x + area_position.y) * 0.15 - TIME * 4.0));
	float activity = active * capture_ring * (0.45 + 0.55 * moving_marks);
	tint = mix(tint, capture_color.rgb, activity);
	alpha = max(alpha, activity * 0.95);
	COLOR = vec4(tint, min(alpha, 0.95) * area_color.a);
}
