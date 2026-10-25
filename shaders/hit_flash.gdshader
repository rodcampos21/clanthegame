// Per-sprite hit flash: replaces every opaque pixel with flash_color while
// flash > 0 (no blending, so the silhouette stays palette-pure).
shader_type canvas_item;
uniform vec4 flash_color : source_color = vec4(0.957, 0.941, 0.902, 1.0);
uniform float flash : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	COLOR = vec4(mix(c.rgb, flash_color.rgb, step(0.5, flash)), c.a) * vec4(1.0, 1.0, 1.0, COLOR.a);
}
