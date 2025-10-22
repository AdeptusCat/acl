shader_type canvas_item;
render_mode unshaded;

uniform float emission_energy : hint_range(0.0, 64.0) = 4.0;
uniform bool  preserve_alpha = true;

void fragment() {
    vec4 c = texture(TEXTURE, UV) * COLOR;

    // Push brightness above 1.0 in HDR
    vec3 rgb = c.rgb * emission_energy;

    // Write HDR color; alpha from texture unless overridden
    if (preserve_alpha) {
        COLOR = vec4(rgb, c.a);
    } else {
        COLOR = vec4(rgb, 1.0);
    }
}
