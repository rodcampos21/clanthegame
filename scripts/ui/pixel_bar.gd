## HP/MP bar drawn from HudBarStyle art.
##
## PURPOSE  show a value as whole art pixels of the fill, and how much was just lost.
## INPUTS   set_value(cur, max) from the owner (battle view / HUD).
## STATE    ratio (fill, snaps), trail_ratio (old value, follows after TRAIL_DELAY).
## RULES    loss: fill drops at once, the trail holds TRAIL_DELAY then slides down in
##          TRAIL_TIME (game time: tweens freeze during hitstop). Gain: both snap.
##          Fill width = round(channel_w * ratio) art px, but never 0 while value > 0.
## FEEDBACK frame, then trail, then fill; art_scale grid px per art px (0.5 = 2 screen px
##          at 1280x720, the battle's canvas_items stretch renders it at full resolution).
class_name PixelBar
extends Control

const TRAIL_DELAY := 0.35
const TRAIL_TIME := 0.4

@export var style: HudBarStyle:
	set(v):
		style = v
		_resize()
@export var art_scale := 0.5:
	set(v):
		art_scale = v
		_resize()

var ratio := 1.0
var trail_ratio := 1.0
var _tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_resize()

func _resize() -> void:
	if style and style.frame:
		custom_minimum_size = style.frame.get_size() * art_scale
		size = custom_minimum_size
	queue_redraw()

func set_value(cur: int, max_value: int, animate := true) -> void:
	var r := clampf(float(cur) / maxf(max_value, 1), 0.0, 1.0)
	if _tween:
		_tween.kill()
	if r < ratio and animate and is_inside_tree():
		trail_ratio = maxf(trail_ratio, ratio)
		ratio = r
		_tween = create_tween()
		_tween.tween_interval(TRAIL_DELAY)
		_tween.tween_property(self, "trail_ratio", r, TRAIL_TIME)
		_tween.tween_callback(queue_redraw)
		_tween.set_trans(Tween.TRANS_QUAD)
	else:
		ratio = r
		trail_ratio = r
	queue_redraw()

## Fill width in art pixels for a ratio.
func pixels(r: float) -> int:
	if style == null or r <= 0.0:
		return 0
	return clampi(roundi(style.channel_w * r), 1, style.channel_w)

func _process(_delta: float) -> void:
	if _tween and _tween.is_running():
		queue_redraw()

func _draw() -> void:
	if style == null or style.frame == null:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * art_scale)
	draw_texture(style.frame, Vector2.ZERO)
	var h := style.frame.get_height()
	for layer: Array in [[style.trail, trail_ratio], [style.fill, ratio]]:
		var tex: Texture2D = layer[0]
		var n := pixels(layer[1])
		if tex and n > 0:
			var r := Rect2(0, 0, style.channel_x + n, h)
			draw_texture_rect_region(tex, r, r)

func debug_state() -> String:
	return "bar %d/%d px (trail %d)" % [pixels(ratio), style.channel_w if style else 0, pixels(trail_ratio)]
