shader_type canvas_item;
render_mode unshaded;

// Approved sRGB ramps, with source brightness stops.
uniform vec4 palette[5];
uniform float levels[5];
uniform vec4 timber_palette[5];
uniform float timber_levels[5];
uniform vec4 soil_palette[5];
uniform float soil_levels[5];
uniform vec4 clay_palette[5];
uniform float clay_levels[5];
uniform vec4 slate_palette[5];
uniform float slate_levels[5];
uniform vec4 water_palette[5];
uniform float water_levels[5];
uniform vec4 fruit_palette[5];
uniform vec4 grid_ink;
// 0: single material, 1: ground, 2: woods, 3: orchard, 4: crops,
// 5: stone building, 6: timber building, 7: bridge.
uniform int material_kind = 0;
uniform bool hdr_2d = true;
uniform bool texture_is_linear = true;

varying vec4 vertex_tint;

void vertex() {
	vertex_tint = COLOR;
}

vec3 to_srgb(vec3 color) {
	vec3 low = color * 12.92;
	vec3 high = 1.055 * pow(max(color, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055;
	return mix(high, low, step(color, vec3(0.0031308)));
}

vec3 to_linear(vec3 color) {
	vec3 low = color / 12.92;
	vec3 high = pow((color + 0.055) / 1.055, vec3(2.4));
	return mix(high, low, step(color, vec3(0.04045)));
}

vec3 ramp(float brightness, vec4 colors[5], float stops[5]) {
	vec3 result = colors[0].rgb;
	for (int index = 1; index < 5; index++) {
		float amount = clamp((brightness - stops[index - 1]) / (stops[index] - stops[index - 1]), 0.0, 1.0);
		result = mix(result, colors[index].rgb, amount);
	}
	return result;
}

void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	vec3 original = texel.rgb;
	if (texture_is_linear) {
		original = to_srgb(original);
	}
	float brightness = dot(original, vec3(0.2126, 0.7152, 0.0722));
	vec3 result = ramp(brightness, palette, levels);
	float warm = smoothstep(0.02, 0.09, original.r - original.g);
	if (material_kind == 1) {
		// Keep the existing outline shape while giving it the approved grid ink.
		result = mix(grid_ink.rgb, result, smoothstep(0.17, 0.28, brightness));
	} else if (material_kind == 2) {
		result = mix(result, ramp(brightness, timber_palette, timber_levels), warm);
	} else if (material_kind == 3) {
		float apple = warm * (1.0 - smoothstep(0.45, 0.65, original.g / max(original.r, 0.001)));
		float pear = warm * smoothstep(0.45, 0.65, original.g / max(original.r, 0.001));
		float flower = smoothstep(0.48, 0.72, min(original.r, min(original.g, original.b)));
		vec3 apples = mix(fruit_palette[0].rgb, fruit_palette[1].rgb, clamp((brightness - 0.12) / 0.34, 0.0, 1.0));
		vec3 pears = mix(fruit_palette[2].rgb, fruit_palette[3].rgb, clamp((brightness - 0.25) / 0.45, 0.0, 1.0));
		result = mix(result, apples, apple);
		result = mix(result, pears, pear);
		result = mix(result, fruit_palette[4].rgb, flower);
	} else if (material_kind == 4) {
		result = mix(result, ramp(brightness, soil_palette, soil_levels), warm);
	} else if (material_kind == 5 || material_kind == 6) {
		float cool = smoothstep(0.00, 0.06, original.b - original.r);
		float clay = warm;
		if (material_kind == 6) {
			clay *= smoothstep(0.02, 0.08, original.r - 2.0 * original.g + original.b);
		}
		result = mix(result, ramp(brightness, clay_palette, clay_levels), clay);
		result = mix(result, ramp(brightness, slate_palette, slate_levels), cool);
	} else if (material_kind == 7) {
		float river = smoothstep(0.01, 0.06, original.b - original.r);
		result = mix(result, ramp(brightness, water_palette, water_levels), river);
	}
	if (hdr_2d) {
		result = to_linear(result);
	}
	// Preserve the exact alpha used by terrain fringes and pixel LOS.
	COLOR = vec4(result, texel.a) * vertex_tint;
}
