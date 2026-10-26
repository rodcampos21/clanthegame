## Autoload "BattleTransition": owns every Overworld <-> Battle scene change.
##
## Node tree it builds for itself (CanvasLayers sit above every scene):
##   BattleTransition (Node)
##   |- CrtLayer   (CanvasLayer 90)  > CrtRect (ColorRect, palette_crt.gdshader)   [F2]
##   '- FxLayer    (CanvasLayer 100) > FxRect  (ColorRect, battle_transition.gdshader)
##
## Sequence for start_battle():
##   freeze tree -> 2-frame white flash (hit confirm) -> shatter/pixelate OUT
##   -> change_scene_to_file(battle) -> wait for the new scene -> pixelate IN
## The data hand-off happens BEFORE the swap: GameState.begin_encounter() stores
## the hero snapshot + enemy list + advantage, BattleManager reads it in _ready().
extends Node

signal midpoint            # screen fully covered, scene is being swapped
signal finished            # transition fully done, gameplay resumed

const TRANSITION_SHADER := preload("res://shaders/battle_transition.gdshader")
const CRT_SHADER := preload("res://shaders/palette_crt.gdshader")
const PALETTE := preload("res://assets/sprites/palette.png")

@export var out_time := 0.75
@export var in_time := 0.45

var busy := false
var _fx: ColorRect
var _fx_mat: ShaderMaterial
var _crt: ColorRect

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var crt_layer := CanvasLayer.new()
	crt_layer.name = "CrtLayer"
	crt_layer.layer = 90
	add_child(crt_layer)
	_crt = _make_rect("CrtRect", CRT_SHADER)
	_crt.visible = false
	crt_layer.add_child(_crt)

	var fx_layer := CanvasLayer.new()
	fx_layer.name = "FxLayer"
	fx_layer.layer = 100
	add_child(fx_layer)
	_fx = _make_rect("FxRect", TRANSITION_SHADER)
	_fx.visible = false
	_fx_mat = _fx.material
	fx_layer.add_child(_fx)

func _make_rect(n: String, shader: Shader) -> ColorRect:
	var r := ColorRect.new()
	r.name = n
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("palette_tex", PALETTE)
	m.set_shader_parameter("palette_size", PALETTE.get_width())
	r.material = m
	return r

func set_crt(enabled: bool) -> void:
	_crt.visible = enabled

## HD battles (canvas_items stretch) run the optional CRT pass on the 1280x720 output grid and
## add the HD sprites' palettes to clan16, so the filter does not collapse HD art into 4x4
## blocks of the 16 base colours. Call with no palettes to go back to the 320x180 look.
func set_display_grid(grid: Vector2, extra_palettes: Array[Texture2D] = []) -> void:
	var m: ShaderMaterial = _crt.material
	m.set_shader_parameter("virtual_size", grid)
	var pal := PALETTE as Texture2D
	if not extra_palettes.is_empty():
		var colors: Array[Color] = []
		for t: Texture2D in [PALETTE as Texture2D] + extra_palettes:
			var img := t.get_image()
			if img.is_compressed():
				img.decompress()
			for x: int in img.get_width():
				colors.append(img.get_pixel(x, 0))
		var merged := Image.create(colors.size(), 1, false, Image.FORMAT_RGBA8)
		for i: int in colors.size():
			merged.set_pixel(i, 0, colors[i])
		pal = ImageTexture.create_from_image(merged)
	m.set_shader_parameter("palette_tex", pal)
	m.set_shader_parameter("palette_size", pal.get_width())

# ---------------------------------------------------------------- public API

func start_battle(enemy_id: StringName, enemies: Array[CombatantStats],
		advantage: EncounterRules.Advantage, player_pos: Vector2, player_facing: Vector2) -> void:
	if busy:
		return
	GameState.begin_encounter(enemy_id, enemies, advantage, player_pos, player_facing)
	await _run(GameState.BATTLE_SCENE, 0, _flash_color(advantage))

func return_to_overworld(result: StringName) -> void:
	if busy:
		return
	GameState.finish_encounter(result)
	await _run(GameState.OVERWORLD_SCENE, 1, Color(0, 0, 0, 0))

# ---------------------------------------------------------------- internals

func _flash_color(advantage: EncounterRules.Advantage) -> Color:
	match advantage:
		EncounterRules.Advantage.PLAYER: return Color("f5d26b")   # gold: you got them
		EncounterRules.Advantage.ENEMY: return Color("c8434b")    # red: they got you
	return Color("f4f0e6")

func _run(scene_path: String, mode: int, flash: Color) -> void:
	busy = true
	var tree := get_tree()
	tree.paused = true
	_fx_mat.set_shader_parameter("mode", mode)
	_fx_mat.set_shader_parameter("progress", 0.0)
	_fx.visible = true

	# Hit-stop + flash: two frames of solid colour sell the impact.
	if flash.a > 0.0:
		_fx_mat.set_shader_parameter("flash", Color(flash, 0.85))
		await _wait_frames(3)
		_fx_mat.set_shader_parameter("flash", Color(flash, 0.0))

	await _tween_progress(0.0, 1.0, out_time)
	midpoint.emit()
	tree.change_scene_to_file(scene_path)
	await _wait_frames(2)              # let the new scene run _ready() and draw once
	tree.paused = false
	await _tween_progress(1.0, 0.0, in_time)
	_fx.visible = false
	busy = false
	finished.emit()

func _tween_progress(from: float, to: float, time: float) -> void:
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_method(func(v: float) -> void: _fx_mat.set_shader_parameter("progress", v),
		from, to, time).set_trans(Tween.TRANS_LINEAR)
	await tw.finished

func _wait_frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func debug_state() -> String:
	return "busy=%s crt=%s" % [busy, _crt.visible]
