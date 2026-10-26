## Visual for one Combatant in battle: sprite, HP bar, status tags, hit feedback.
## Pure presentation: reads the Combatant, never changes it.
##
## Two sprite kinds:
##   * pixel strip (battle_texture): 320x180-grid art, integer scale 2, frame cycling
##   * HD SpriteFrames (battle_frames): 1280x720 art shown 1:1 (scale 0.25 on the 320x180
##     grid, rendered at full resolution because the battle runs in canvas_items stretch).
##     Animations: idle (rest), attack (lunge), hurt (hit), death (KO), defend (while
##     Guarding), advance/victory/skill when present.
class_name BattleActorView
extends Node2D

const FLASH_SHADER := preload("res://shaders/hit_flash.gdshader")
const INK := Color("1a1423")
const RED := Color("c8434b")
const GOLD := Color("f5d26b")
const GREEN := Color("9fd16b")
const WHITE := Color("f4f0e6")

var combatant: Combatant
var selected := false:
	set(v):
		selected = v
		queue_redraw()
var _sprite: Sprite2D
var _hd: AnimatedSprite2D            # HD sprite (null for pixel-strip combatants)
var _hd_height := 0.0                # visible height of the HD idle frame, in grid px
var _busy := false                   # a one-shot animation (attack/hurt) is playing
var _flash_mat: ShaderMaterial
var _anim_t := 0.0
var _home := Vector2.ZERO
var _status_label: Label

func setup(c: Combatant, face_left: bool) -> void:
	combatant = c
	_flash_mat = ShaderMaterial.new()
	_flash_mat.shader = FLASH_SHADER
	if c.stats.battle_frames != null:
		_setup_hd(c, face_left)
	else:
		_setup_strip(c, face_left)
	_status_label = Label.new()
	_status_label.position = Vector2(-20, 6)
	_status_label.size = Vector2(40, 8)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status_label)
	_home = position
	c.hp_changed.connect(func(_c, _o, _n) -> void: queue_redraw())
	c.status_added.connect(func(_c, _s) -> void: refresh())
	c.status_removed.connect(func(_c, _s) -> void: refresh())
	refresh()

func _setup_hd(c: Combatant, face_left: bool) -> void:
	_hd = AnimatedSprite2D.new()
	_hd.sprite_frames = c.stats.battle_frames
	_hd.centered = false
	_hd.offset = -c.stats.battle_frames_origin          # feet on the node origin
	_hd.scale = Vector2.ONE * c.stats.battle_frames_scale
	if face_left:
		_hd.scale.x = -_hd.scale.x                       # mirror around the feet
	_hd.material = _flash_mat
	add_child(_hd)
	var idle_tex: Texture2D = _hd.sprite_frames.get_frame_texture(&"idle", 0)
	var used := idle_tex.get_image().get_used_rect()
	_hd_height = (c.stats.battle_frames_origin.y - used.position.y) * c.stats.battle_frames_scale
	_hd.play(&"idle")

func _setup_strip(c: Combatant, face_left: bool) -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = c.stats.battle_texture
	_sprite.hframes = c.stats.battle_hframes
	_sprite.centered = false
	var fw := _sprite.texture.get_width() / _sprite.hframes
	_sprite.scale = Vector2.ONE * 2          # integer scale only: stays pixel-perfect
	_sprite.offset = Vector2(-fw / 2, -_sprite.texture.get_height())
	_sprite.flip_h = face_left
	_sprite.material = _flash_mat
	add_child(_sprite)

func _process(delta: float) -> void:
	_anim_t += delta
	if _sprite and combatant and combatant.is_alive() and _sprite.hframes > 1:
		_sprite.frame = int(_anim_t * 3.0) % _sprite.hframes
	if _hd and selected:
		queue_redraw()   # bouncing target arrow

## Height of the visible sprite above the feet, in 320x180-grid pixels.
func sprite_height() -> float:
	return _hd_height if _hd else float(_sprite.texture.get_height() * 2)

func has_anim(anim: StringName) -> bool:
	return _hd != null and _hd.sprite_frames.has_animation(anim)

## Animation to rest on between actions: Guard pose while Guarding, else idle.
func rest_anim() -> StringName:
	if combatant and combatant.has_status(&"guarding") and has_anim(&"defend"):
		return &"defend"
	return &"idle"

func _play_rest() -> void:
	if _hd and combatant.is_alive() and not _busy and _hd.animation != rest_anim():
		_hd.play(rest_anim())

## Plays a one-shot HD animation to its end (respecting game time / hitstop), then rests.
func play_once(anim: StringName) -> void:
	if not has_anim(anim):
		return
	_busy = true
	_hd.play(anim)
	await _hd.animation_finished
	_busy = false
	_play_rest()

func refresh() -> void:
	var tags := []
	var col := WHITE
	for s in combatant.statuses:
		tags.append(s.data.display_name.to_upper())
		col = s.data.color
	_status_label.text = " ".join(tags)
	_status_label.add_theme_color_override("font_color", col)
	_play_rest()
	queue_redraw()

func _draw() -> void:
	if combatant == null or not combatant.is_alive():
		return
	# HP bar: 24px, whole pixels, palette colours only.
	var w := 24
	var fill := int(round(float(combatant.hp) / combatant.stats.max_hp * w))
	draw_rect(Rect2(-w / 2 - 1, 2, w + 2, 4), INK)
	draw_rect(Rect2(-w / 2, 3, fill, 2), GREEN if combatant.side == Combatant.Team.PARTY else RED)
	if selected:
		# bouncing target arrow
		var y := -int(sprite_height()) - 8 - int(_anim_t * 6.0) % 2
		draw_colored_polygon(PackedVector2Array([Vector2(-3, y), Vector2(4, y), Vector2(0, y + 4)]), GOLD)

func lunge(direction: float) -> void:
	if has_anim(&"attack"):
		# HD: the swing itself carries the motion; step in a little during the wind-up
		var step := create_tween()
		step.tween_property(self, "position:x", _home.x + 6 * direction, 0.16)
		await play_once(&"attack")
		var back := create_tween()
		back.tween_property(self, "position:x", _home.x, 0.10)
		await back.finished
		return
	var tw := create_tween()
	tw.tween_property(self, "position:x", _home.x + 10 * direction, 0.08)
	tw.tween_property(self, "position:x", _home.x, 0.12)
	await tw.finished

func hit(strong: bool) -> void:
	## ForgeSkills vfx-impact: confirm every hit — flash + shake (+ hitstop in manager).
	_flash_mat.set_shader_parameter("flash", 1.0)
	var tw := create_tween()
	for i in (4 if strong else 2):
		tw.tween_property(self, "position:x", _home.x + (2 if i % 2 == 0 else -2), 0.03)
	tw.tween_property(self, "position:x", _home.x, 0.03)
	tw.parallel().tween_callback(func() -> void: _flash_mat.set_shader_parameter("flash", 0.0)).set_delay(0.08)
	if has_anim(&"hurt") and combatant.is_alive():
		play_once(&"hurt")          # runs alongside the shake; returns to rest by itself
	await tw.finished
	queue_redraw()

func die() -> void:
	if has_anim(&"death"):
		# HD: fall and stay down (last frame holds)
		_busy = true
		_status_label.visible = false
		_hd.play(&"death")
		await _hd.animation_finished
		queue_redraw()
		return
	# blink out (no alpha blending: pure on/off like old consoles)
	for i in 6:
		_sprite.visible = i % 2 == 1
		await get_tree().create_timer(0.06).timeout
	_sprite.visible = false
	_status_label.visible = false
	queue_redraw()

func top() -> Vector2:
	return position + Vector2(0, -sprite_height() - 4)

func debug_state() -> String:
	if _hd:
		return "%s HD anim=%s frame=%d busy=%s scale=%s" % [combatant.display_name, _hd.animation, _hd.frame, _busy, _hd.scale]
	return "%s strip frame=%d" % [combatant.display_name, _sprite.frame]
