shader_type canvas_item;

uniform vec4 glow_color : source_color = vec4(0.7, 0.6, 0.4, 1.0); // dusty amber
uniform float glow_thickness = 0.08;
uniform float glow_softness = 0.03;
uniform float border_thickness = 0.025;
uniform float glow_alpha : hint_range(0.0, 1.0) = 1.0;

float rand(vec2 co) {
    return fract(sin(dot(co.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

float hex(vec2 p) {
    p = abs(p);
    return max(dot(p, normalize(vec2(sqrt(3.0), 1.0))), p.y);
}

void fragment() {
    vec2 uv = (UV - vec2(0.5)) * 2.0;
    uv = vec2(uv.y, -uv.x); // rotate to flat-top
    uv.x *= 1.0 / cos(radians(30.0));

    float h = hex(uv);
    float edge = 1.0 - glow_thickness;

    float border = smoothstep(edge, edge + border_thickness, h);
    float glow = smoothstep(1.0 + glow_softness, 1.0, h);

    vec4 final_color = vec4(glow_color.rgb, (1.0 - border) * glow * glow_alpha); // ← use alpha

	float noise = rand(UV + TIME * 0.2);
	float vignette = smoothstep(1.0, 0.7, h);

	final_color.a *= mix(0.7, 1.0, noise);
	final_color.rgb *= vignette;
	final_color.a *= vignette;
    COLOR = final_color;
}
