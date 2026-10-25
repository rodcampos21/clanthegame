## Builds a Godot FontFile from the claude-pxl 3x5 font atlas (assets/sprites/font_atlas.png).
##
## The atlas holds ASCII 32..95 in a 16x4 grid of 4x6 cells. Lowercase letters
## are mapped onto the uppercase glyphs (pxl's font is caps-only). Glyph widths
## are measured from the pixels so "I", "!" and "." get tight spacing.
class_name PixelFont
extends RefCounted

const ATLAS := preload("res://assets/sprites/font_atlas.png")
const CELL := Vector2i(4, 6)
const COLS := 16
const FIRST := 32
const COUNT := 64
const SIZE := 6          # nominal font size; use 6 (1x) or 12 (2x) in the UI

static var _font: FontFile
static var _theme: Theme

static func font() -> FontFile:
	if _font != null:
		return _font
	var img: Image = ATLAS.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	var f := FontFile.new()
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.generate_mipmaps = false
	f.allow_system_fallback = false
	f.fixed_size = SIZE
	f.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY
	var key := Vector2i(SIZE, 0)
	f.set_texture_image(0, key, 0, img)
	f.set_cache_ascent(0, SIZE, 5)
	f.set_cache_descent(0, SIZE, 1)
	for i in COUNT:
		var code := FIRST + i
		var origin := Vector2i((i % COLS) * CELL.x, (i / COLS) * CELL.y)
		var w := _ink_width(img, origin)
		var adv := 4 if code == 32 else w + 1
		_add_glyph(f, key, code, origin, w, adv)
		if code >= 65 and code <= 90:   # a-z -> A-Z
			_add_glyph(f, key, code + 32, origin, w, adv)
	_font = f
	return f

static func _add_glyph(f: FontFile, key: Vector2i, code: int, origin: Vector2i, w: int, adv: int) -> void:
	f.set_glyph_advance(0, SIZE, code, Vector2(adv, 0))
	f.set_glyph_offset(0, key, code, Vector2(0, -5))
	f.set_glyph_size(0, key, code, Vector2(maxi(w, 1), 5))
	f.set_glyph_uv_rect(0, key, code, Rect2(origin.x, origin.y, maxi(w, 1), 5))
	f.set_glyph_texture_idx(0, key, code, 0)

static func _ink_width(img: Image, origin: Vector2i) -> int:
	var w := 0
	for x in 3:
		for y in 5:
			if img.get_pixel(origin.x + x, origin.y + y).a > 0.5:
				w = x + 1
	return w

static func theme() -> Theme:
	## Project-wide theme: pixel font + flat palette panels/buttons.
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = SIZE
	var ink := Color("1a1423")
	var night := Color("3b2d4f")
	var violet := Color("6b4f8a")
	var gold := Color("f5d26b")
	var white := Color("f4f0e6")
	t.set_stylebox("panel", "PanelContainer", _box(ink, night, 1, 3))
	t.set_stylebox("panel", "Panel", _box(ink, night, 1, 3))
	t.set_stylebox("normal", "Button", _box(night, violet, 1, 2))
	t.set_stylebox("hover", "Button", _box(violet, gold, 1, 2))
	t.set_stylebox("focus", "Button", _box(violet, gold, 1, 2))
	t.set_stylebox("pressed", "Button", _box(ink, gold, 1, 2))
	t.set_stylebox("disabled", "Button", _box(ink, night, 1, 2))
	t.set_color("font_color", "Button", white)
	t.set_color("font_hover_color", "Button", gold)
	t.set_color("font_focus_color", "Button", gold)
	t.set_color("font_pressed_color", "Button", gold)
	t.set_color("font_disabled_color", "Button", violet)
	t.set_color("font_color", "Label", white)
	t.set_constant("separation", "VBoxContainer", 1)
	t.set_constant("separation", "HBoxContainer", 2)
	t.set_constant("line_spacing", "Label", 1)
	_theme = t
	return t

static func _box(bg: Color, border: Color, bw: int, pad: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_content_margin_all(pad)
	s.anti_aliasing = false
	return s
