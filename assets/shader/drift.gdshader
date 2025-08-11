shader_type canvas_item;

uniform vec2 scroll_speed = vec2(0.02, 0.01); // pixels per second
uniform vec2 texture_scale = vec2(1.0, 1.0); // set to Vector2(texture_size.x, texture_size.y) in shader params
uniform float opacity = 0.2; // your desired alpha value

void fragment() {
	// Calculate scroll offset
	vec2 offset = TIME * scroll_speed / texture_scale;

	// Wrap the texture UVs with scrolling
	vec2 uv = fract(UV + offset);

	vec4 tex_color = texture(TEXTURE, uv);
	tex_color.a *= opacity; // control alpha manually

	COLOR = tex_color;
}