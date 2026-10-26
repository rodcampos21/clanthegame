## Builds res://assets/sprites/knight/knight_frames.tres (SpriteFrames) from the knight sheets.
##
## Sheets come from tools/sprite_pipeline (AI strips -> real pixel art, locked palette).
## Every cell has the SAME origin: the point between the feet on the ground, at ORIGIN
## (pixels from the cell's top-left). Cells are 192 px tall; the attack is wider (256) because
## the slash reaches forward, but its origin is the same, so swapping animations never jumps.
##
## Run:  godot --headless --path . --script res://tools/build_knight_frames.gd
extends SceneTree

const DIR := "res://assets/sprites/knight/"
const OUT := DIR + "knight_frames.tres"
const ORIGIN := Vector2(96, 190)
const BASE_FPS := 10.0     # frame duration below is in ms; SpriteFrames stores it relative to this

## name: [sheet, cell width, frame count, ms per frame, loop]
const ANIMS := {
	&"idle": ["idle.png", 192, 2, [600, 600], true],
	&"attack": ["attack.png", 256, 5, [160, 80, 80, 140, 240], false],
	&"hurt": ["hurt.png", 192, 3, [180, 200, 200], false],
	&"advance": ["advance.png", 192, 4, [110, 110, 110, 110], true],
	&"death": ["death.png", 192, 5, [120, 160, 180, 200, 1000], false],
	&"defend": ["defend.png", 192, 2, [120, 400], false],
}


func _init() -> void:
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	for anim: StringName in ANIMS:
		var spec: Array = ANIMS[anim]
		var tex: Texture2D = load(DIR + spec[0])
		var cell_w: int = spec[1]
		var count: int = spec[2]
		var ms: Array = spec[3]
		assert(tex.get_width() == cell_w * count, "%s: sheet is %d px wide, expected %d" % [spec[0], tex.get_width(), cell_w * count])
		frames.add_animation(anim)
		frames.set_animation_speed(anim, BASE_FPS)
		frames.set_animation_loop(anim, spec[4])
		for i: int in count:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(i * cell_w, 0, cell_w, tex.get_height())
			frames.add_frame(anim, at, float(ms[i]) / (1000.0 / BASE_FPS))
	var err := ResourceSaver.save(frames, OUT)
	print("knight frames -> %s (%s) err=%d" % [OUT, ", ".join(frames.get_animation_names()), err])
	quit(err)
