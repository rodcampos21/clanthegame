## Visual for one Combatant in battle: sprite, HP bar (enemies; the party's HP is on the
## HeroPanel), status icons + tags, hit feedback.
## Pure presentation: reads the Combatant, never changes it.
##
## Two sprite kinds:
##   * pixel strip (battle_texture): 320x180-grid art, integer scale 2, frame cycling
##   * HD SpriteFrames (battle_frames): 1280x720 art shown 1:1 (scale 0.25 on the 320x180
##     grid, rendered at full resolution because the battle runs in canvas_items stretch).
##     Animations: idle (rest), defend (while Guarding), advance (run to a melee target and
##     back), attack/skill (SkillData.user_anim), hurt (hit), death (KO), victory.
class_name BattleActorView
extends Node2D

const FLASH_SHADER := preload("res://shaders/hit_flash.gdshader")
const BAR_STYLE := preload("res://data/ui/bar_short.tres")
const ICON_SCALE := 0.5          # grid px per icon art px (same density as the bars)
const GOLD := Color("f5d26b")
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
var _status_row: HBoxContainer      # status icons + tag label, centered under the feet
var _icons: HBoxContainer
var hp_bar: PixelBar                # null for party members

func setup(c: Combatant, face_left: bool) -> void:
	combatant = c
	_flash_mat = ShaderMaterial.new()
	_flash_mat.shader = FLASH_SHADER
	if c.stats.battle_frames != null:
		_setup_hd(c, face_left)
	else:
		_setup_strip(c, face_left)
	var row_y := 6.0
	if c.side != Combatant.Team.PARTY:
		hp_bar = PixelBar.new()
		hp_bar.style = BAR_STYLE
		hp_bar.position = Vector2(-16, 2)
		hp_bar.set_value(c.hp, c.stats.max_hp, false)
		add_child(hp_bar)
		row_y = 12.0
	_status_row = HBoxContainer.new()
	_status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_status_row.add_theme_constant_override("separation", 1)
	_status_row.position = Vector2(-40, row_y)
	_status_row.size = Vector2(80, 10)
	_status_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_status_row)
	_icons = HBoxContainer.new()
	_icons.add_theme_constant_override("separation", 1)
	_status_row.add_child(_icons)
	_status_label = Label.new()
	_status_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_status_row.add_child(_status_label)
	_home = position
	c.hp_changed.connect(func(_c, _o, n: int) -> void:
		if hp_bar:
			hp_bar.set_value(n, combatant.stats.max_hp)
		queue_redraw())
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
	for child in _icons.get_children():
		child.free()
	for s in combatant.statuses:
		tags.append(s.data.display_name.to_upper())
		col = s.data.color
		if s.data.icon:
			var icon_rect := TextureRect.new()
			icon_rect.texture = s.data.icon
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.custom_minimum_size = s.data.icon.get_size() * ICON_SCALE
			icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			_icons.add_child(icon_rect)
	_status_label.text = " ".join(tags)
	_status_label.add_theme_color_override("font_color", col)
	_play_rest()
	queue_redraw()

func _draw() -> void:
	if combatant == null or not combatant.is_alive():
		return
	if selected:
		# bouncing target arrow
		var y := -int(sprite_height()) - 8 - int(_anim_t * 6.0) % 2
		draw_colored_polygon(PackedVector2Array([Vector2(-3, y), Vector2(4, y), Vector2(0, y + 4)]), GOLD)

## Grid px between the user's feet and the target's when striking in melee: the HD slash
## reaches ~37 px forward, so the blade tip lands on the middle of a 32 px slime.
const MELEE_GAP := 36.0
const RUN_SPEED := 260.0     # grid px / s while running in or back

## HD skill presentation: optional run-up to the target (advance), then the skill's
## animation. Stays at the target; BattleManager calls return_home() after the hit lands.
func perform(skill: SkillData, target: BattleActorView, direction: float) -> void:
	var anim := skill.user_anim
	if anim == &"" and skill.is_offensive():
		anim = &"attack"
	if skill.approach and target != null and target != self and has_anim(&"advance"):
		var dest := target.position + Vector2(-MELEE_GAP * direction, 0)
		await run_to(dest)
	if anim != &"" and has_anim(anim):
		await play_once(anim)     # ends back on the rest pose, still standing at the target

func run_to(dest: Vector2, backwards := false) -> void:
	var dist := position.distance_to(dest)
	if dist < 1.0:
		return
	_busy = true
	if backwards:
		_hd.scale.x = -_hd.scale.x            # turn around to run home
	_hd.play(&"advance")
	var tw := create_tween()
	tw.tween_property(self, "position", dest, clampf(dist / RUN_SPEED, 0.2, 0.6))
	await tw.finished
	if backwards:
		_hd.scale.x = -_hd.scale.x
	_busy = false
	_play_rest()

func is_away() -> bool:
	return position.distance_to(_home) > 1.0

func return_home() -> void:
	if is_away() and combatant.is_alive():
		await run_to(_home, true)
	position = _home

func lunge(direction: float) -> void:
	var tw := create_tween()
	tw.tween_property(self, "position:x", _home.x + 10 * direction, 0.08)
	tw.tween_property(self, "position:x", _home.x, 0.12)
	await tw.finished

func hit(strong: bool) -> void:
	## ForgeSkills vfx-impact: confirm every hit — flash + shake (+ hitstop in manager).
	_flash_mat.set_shader_parameter("flash", 1.0)
	var base_x := position.x
	var tw := create_tween()
	for i in (4 if strong else 2):
		tw.tween_property(self, "position:x", base_x + (2 if i % 2 == 0 else -2), 0.03)
	tw.tween_property(self, "position:x", base_x, 0.03)
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
	_hide_hud()
	queue_redraw()

func _hide_hud() -> void:
	_status_row.visible = false
	if hp_bar:
		hp_bar.visible = false

func top() -> Vector2:
	return position + Vector2(0, -sprite_height() - 4)

func celebrate() -> void:
	if has_anim(&"victory") and combatant.is_alive():
		_busy = true
		_hd.play(&"victory")
		await _hd.animation_finished

func debug_state() -> String:
	var bar := (" " + hp_bar.debug_state()) if hp_bar else ""
	if _hd:
		return "%s HD anim=%s frame=%d busy=%s scale=%s%s" % [combatant.display_name, _hd.animation, _hd.frame, _busy, _hd.scale, bar]
	return "%s strip frame=%d%s" % [combatant.display_name, _sprite.frame, bar]
