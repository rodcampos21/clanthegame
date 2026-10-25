// Overworld -> Battle transition (claude-pxl style: integer pixel blocks,
// ordered dither, everything quantised to the clan16 palette strip).
//
// Drive `progress` 0 -> 1 to cover the screen, swap scenes, then 1 -> 0.
// Three stacked passes, all on the 320x180 virtual grid:
//   1. PIXELATE  block size grows 1 -> max_block px (always whole pixels)
//   2. PALETTE   colour snapped to the nearest palette entry, then darkened
//                one ramp step at a time (a palette shift, not a blend)
//   3. SHATTER   16px cells drop out in a randomised radial order; the edge
//                of each cell is an ordered-dither (Bayer 4x4) fade, never alpha
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest, repeat_disable;
uniform sampler2D palette_tex : filter_nearest, repeat_disable;
uniform int palette_size = 16;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float max_block = 20.0;
uniform vec2 virtual_size = vec2(320.0, 180.0);
uniform float shard_size = 16.0;
uniform vec4 fill_color : source_color = vec4(0.102, 0.078, 0.137, 1.0);
// 0 = shatter + pixelate (encounter), 1 = dither iris (return to overworld)
uniform int mode = 0;
// Flash colour for the hit frame (alpha = strength).
uniform vec4 flash : source_color = vec4(1.0, 1.0, 1.0, 0.0);

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
                                  3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

float bayer4(vec2 p) {
	ivec2 i = ivec2(mod(p, 4.0));
	return (BAYER[i.x + i.y * 4] + 0.5) / 16.0;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

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
	float p = clamp(progress, 0.0, 1.0);
	vec2 vpix = floor(SCREEN_UV * virtual_size);          // virtual pixel coords

	// 1. pixelate (whole-pixel blocks, centred sample)
	float block = floor(mix(1.0, max_block, p * p));
	vec2 sample_px = (floor(vpix / block) * block) + block * 0.5;
	vec3 col = texture(screen_tex, sample_px / virtual_size).rgb;

	// 2. palette snap + stepped darkening
	col = nearest_palette(col);
	float steps = floor(p * 4.0) / 4.0;
	col = nearest_palette(col * (1.0 - 0.6 * steps));

	// 3. cover pattern
	vec2 aspect = vec2(virtual_size.x / virtual_size.y, 1.0);
	float dist = length((SCREEN_UV - 0.5) * aspect);    // 0 centre .. ~1 corner
	float key;
	if (mode == 0) {
		vec2 shard = floor(vpix / shard_size);
		key = hash(shard) * 0.55 + dist * 0.5;            // shards, roughly outward
	} else {
		key = 1.05 - dist;                                 // iris closing on centre
	}
	float edge = (p * 1.25 - key) * 5.0;                  // >1 covered, <0 clear
	float covered = step(bayer4(vpix), edge);

	vec3 out_col = mix(col, fill_color.rgb, covered);
	out_col = mix(out_col, flash.rgb, flash.a);
	COLOR = vec4(out_col, 1.0);
}
