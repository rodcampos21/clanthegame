// Optional full-screen "retro display" pass (toggle with F2).
// Snaps the frame to the clan16 palette with a 4x4 Bayer dither, then adds
// light scanlines and a vignette. Works on the 320x180 virtual grid so the
// dither pattern is exactly one art pixel.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D palette_tex : filter_nearest, repeat_disable;
uniform int palette_size = 16;
uniform vec2 virtual_size = vec2(320.0, 180.0);
uniform float dither_strength = 0.06;
uniform float scanline = 0.12;
uniform float vignette = 0.35;

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
                                  3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

vec3 nearest_palette(vec3 c) {
	vec3 best = c;
	float best_d = 1e9;
	for (int i = 0; i < palette_size; i++) {
		vec3 p = texelFetch(palette_tex, ivec2(i, 0), 0).rgb;
		vec3 d = c - p;
		float dist = dot(d, d);
		if (dist < best_d) { best_d = dist; best = p; }
	}
	return best;
}

void fragment() {
	vec2 vpix = floor(SCREEN_UV * virtual_size);
	vec3 col = texture(screen_tex, (vpix + 0.5) / virtual_size).rgb;
	ivec2 b = ivec2(mod(vpix, 4.0));
	float threshold = (BAYER[b.x + b.y * 4] + 0.5) / 16.0 - 0.5;
	col = nearest_palette(col + threshold * dither_strength);
	// scanlines on the *window* pixels so they stay thin at any integer scale
	float line = mod(FRAGCOORD.y, 4.0) < 1.0 ? 1.0 - scanline : 1.0;
	vec2 d = SCREEN_UV - 0.5;
	float vig = 1.0 - vignette * dot(d, d) * 2.0;
	COLOR = vec4(col * line * vig, 1.0);
}
