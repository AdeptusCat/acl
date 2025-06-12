shader_type canvas_item;

uniform vec2 mask_position = vec2(0.0, 0.0); // top-left corner of mask
uniform vec2 mask_size = vec2(64.0, 64.0);   // size of the visible area in pixels

void fragment() {
    vec2 pixel = UV * textureSize(TEXTURE, 0);

    if (pixel.x < mask_position.x || pixel.x > mask_position.x + mask_size.x ||
        pixel.y < mask_position.y || pixel.y > mask_position.y + mask_size.y) {
        discard;
    }

    COLOR = texture(TEXTURE, UV);
}