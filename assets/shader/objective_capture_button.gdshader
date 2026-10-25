shader_type canvas_item;
render_mode unshaded;

uniform vec4 area_color : source_color;
uniform vec4 capture_color : source_color;
uniform float capture_progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	// Use screen derivatives so the border stays two rendered pixels wide.
	vec2 edge = min(UV, vec2(1.0) - UV) / max(fwidth(UV), vec2(0.0001));
	float border = 1.0 - step(2.0, min(edge.x, edge.y));
	float band_position = clamp(UV.x, 0.0, 0.9999) * 12.0;
	float amount = floor(clamp(capture_progress, 0.0, 1.0) * 12.0 + 0.0001);
	float filled = 1.0 - step(amount, floor(band_position));
	float diagonal = fract(UV.x * 12.0 + UV.y * 0.7);
	float stripe = step(0.20, diagonal) * (1.0 - step(0.75, diagonal));
	float marking = filled * stripe * (1.0 - border);
	vec3 tint = mix(area_color.rgb, capture_color.rgb, marking);
	float alpha = mix(0.16, 0.48, marking);
	COLOR = vec4(tint, mix(alpha, 0.95, border));
}
