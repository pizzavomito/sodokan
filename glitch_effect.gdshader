shader_type canvas_item;

uniform float glitch_intensity : hint_range(0.0, 1.0) = 0.0;
uniform int glitch_type : hint_range(1, 3) = 1;
uniform float time_offset = 0.0;

// Hash simple pour pseudo-random
float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec4 color = texture(TEXTURE, uv);
	float t = time_offset;

	if (glitch_intensity <= 0.0) {
		COLOR = color;
	} else if (glitch_type == 1) {
		// === TYPE 1 : Chromatic Aberration ===
		float offset = glitch_intensity * 0.02;
		// Décalage qui varie dans le temps
		float shift = sin(t * 15.0) * offset;
		float r = texture(TEXTURE, uv + vec2(shift, 0.0)).r;
		float g = texture(TEXTURE, uv).g;
		float b = texture(TEXTURE, uv - vec2(shift, 0.0)).b;
		color = vec4(r, g, b, color.a);

	} else if (glitch_type == 2) {
		// === TYPE 2 : Scanlines + décalage horizontal ===
		// Scanlines
		float scanline = sin(uv.y * 800.0) * 0.04 * glitch_intensity;
		color.rgb -= scanline;

		// Décalage horizontal par bandes
		float band = floor(uv.y * 20.0);
		float band_hash = hash(band + floor(t * 8.0));
		if (band_hash > 0.7) {
			float shift_amount = (band_hash - 0.7) * 0.1 * glitch_intensity;
			color = texture(TEXTURE, uv + vec2(shift_amount, 0.0));
		}

	} else if (glitch_type == 3) {
		// === TYPE 3 : Blocs pixelisés déplacés ===
		float block_size = mix(0.1, 0.03, glitch_intensity);
		vec2 block = floor(uv / block_size);
		float block_hash = hash2(block + vec2(floor(t * 6.0)));

		if (block_hash > 0.85) {
			// Déplace ce bloc
			vec2 block_offset = vec2(
				hash(block_hash * 13.0) - 0.5,
				hash(block_hash * 17.0) - 0.5
			) * 0.05 * glitch_intensity;
			color = texture(TEXTURE, uv + block_offset);
			// Teinte légèrement le bloc
			color.rgb = mix(color.rgb, vec3(hash(block_hash), 0.2, 0.8), 0.15 * glitch_intensity);
		}
	}

	COLOR = color;
}
