shader_type canvas_item;
render_mode unshaded;

uniform sampler2D visibility_mask : filter_nearest, repeat_disable;
uniform sampler2D cloud_noise : filter_linear, repeat_enable;
uniform vec2 grid_size;
uniform vec2 tile_size = vec2(128.0);
uniform vec2 cell_origin = vec2(64.0);
uniform vec2 wind_velocity = vec2(5.0, 2.0);
uniform float feather_width = 16.0;
uniform float opacity = 0.76;
uniform vec4 shadow_color;
uniform vec4 body_color;
uniform vec4 light_color;
uniform bool hdr_2d = true;
// A fixed time permits deterministic GPU checks and previews.
uniform float time_override = -1.0;

varying vec2 map_position;
varying vec2 world_position;
varying vec4 vertex_tint;

void vertex() {
	map_position = VERTEX;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	vertex_tint = COLOR;
}

vec2 nearest_axial(vec2 point) {
	vec2 relative = point - cell_origin;
	float q = relative.x / (tile_size.x * 0.75);
	float r = relative.y / tile_size.y - q * 0.5;
	vec3 cube = vec3(q, -q - r, r);
	vec3 snapped = round(cube);
	vec3 error = abs(snapped - cube);
	if (error.x > error.y && error.x > error.z) {
		snapped.x = -snapped.y - snapped.z;
	} else if (error.y > error.z) {
		snapped.y = -snapped.x - snapped.z;
	} else {
		snapped.z = -snapped.x - snapped.y;
	}
	return snapped.xz;
}

vec2 offset_cell(vec2 axial) {
	return vec2(axial.x, axial.y + (axial.x - mod(axial.x, 2.0)) * 0.5);
}

vec2 state_at(vec2 cell) {
	if (any(lessThan(cell, vec2(0.0))) || any(greaterThanEqual(cell, grid_size))) {
		return vec2(0.0);
	}
	// Red: map coverage. Green: currently outside the player's LOS.
	return texture(visibility_mask, (cell + vec2(0.5)) / grid_size).rg;
}

float hex_distance(vec2 point, vec2 cell) {
	vec2 center = cell_origin + vec2(cell.x * tile_size.x * 0.75,
		(cell.y + mod(cell.x, 2.0) * 0.5) * tile_size.y);
	vec2 local = abs(point - center);
	float slope = tile_size.x / (2.0 * tile_size.y);
	float side = (local.x + slope * local.y - tile_size.x * 0.5) / sqrt(1.0 + slope * slope);
	return max(local.y - tile_size.y * 0.5, side);
}

vec3 to_linear(vec3 color) {
	vec3 low = color / 12.92;
	vec3 high = pow((color + 0.055) / 1.055, vec3(2.4));
	return mix(high, low, step(color, vec3(0.04045)));
}

void fragment() {
	vec2 axial = nearest_axial(map_position);
	vec2 state = state_at(offset_cell(axial));
	float coverage = 0.0;
	float clock = TIME;
	if (time_override >= 0.0) {
		clock = time_override;
	}
	vec2 drift = wind_velocity * clock;
	vec2 warp = vec2(
		texture(cloud_noise, world_position / 1100.0 + drift / 1600.0).r,
		texture(cloud_noise, world_position / 1100.0 + drift / 1600.0 + vec2(0.37, 0.61)).r
	) - vec2(0.5);
	float billows = texture(cloud_noise, (world_position + warp * 150.0 - drift) / 720.0).r;
	float wisps = texture(cloud_noise, world_position / vec2(300.0, 190.0) + drift / 1050.0 + vec2(0.17, 0.43)).r;
	float density = smoothstep(0.18, 0.82, billows * 0.76 + wisps * 0.24);
	if (state.r > 0.5 && state.g > 0.5) {
		vec2 neighbors[6] = vec2[6](
			vec2(1.0, 0.0), vec2(1.0, -1.0), vec2(0.0, -1.0),
			vec2(-1.0, 0.0), vec2(-1.0, 1.0), vec2(0.0, 1.0)
		);
		float visible_distance = tile_size.x + tile_size.y;
		float outside_distance = visible_distance;
		for (int index = 0; index < 6; index++) {
			vec2 cell = offset_cell(axial + neighbors[index]);
			vec2 neighbor = state_at(cell);
			float distance = hex_distance(map_position, cell);
			if (neighbor.r < 0.5) {
				outside_distance = min(outside_distance, distance);
			} else if (neighbor.g < 0.5) {
				visible_distance = min(visible_distance, distance);
			}
		}
		// Only region boundaries feather; shared obscured hex edges stay seamless.
		float fringe = feather_width * mix(0.8, 1.2, wisps);
		coverage = smoothstep(0.0, fringe, visible_distance);
		coverage *= smoothstep(0.0, feather_width, outside_distance);
	}
	vec3 color = mix(shadow_color.rgb, body_color.rgb, smoothstep(0.0, 0.65, density));
	color = mix(color, light_color.rgb, smoothstep(0.45, 1.0, density) * 0.7);
	if (hdr_2d) {
		color = to_linear(color);
	}
	COLOR = vec4(color, coverage * opacity * mix(0.72, 1.0, density)) * vertex_tint;
}
