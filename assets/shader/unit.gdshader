shader_type canvas_item;

uniform float dissolve_amount : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D noise_texture;
uniform bool indirect_contact = false;

void fragment() {
    vec4 tex_color = texture(TEXTURE, UV);
    float noise = texture(noise_texture, UV).r;

    if (noise < dissolve_amount) {
        discard;
    }

    if (indirect_contact) {
        float grey = dot(tex_color.rgb, vec3(0.299, 0.587, 0.114));
        tex_color.rgb = vec3(grey) * 0.45;
        tex_color.a *= 0.6;
    }
    COLOR = tex_color;
}
