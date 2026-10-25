## Visual for one Combatant in battle: sprite, HP bar, status tags, hit feedback.
## Pure presentation: reads the Combatant, never changes it.
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
var _flash_mat: ShaderMaterial
var _anim_t := 0.0
var _home := Vector2.ZERO
var _status_label: Label

func setup(c: Combatant, face_left: bool) -> void:
	combatant = c
	_sprite = Sprite2D.new()
	_sprite.texture = c.stats.battle_texture
	_sprite.hframes = c.stats.battle_hframes
	_sprite.centered = false
	var fw := _sprite.texture.get_width() / _sprite.hframes
	_sprite.scale = Vector2.ONE * 2          # integer scale only: stays pixel-perfect
	_sprite.offset = Vector2(-fw / 2, -_sprite.texture.get_height())
	_sprite.flip_h = face_left
	_flash_mat = ShaderMaterial.new()
	_flash_mat.shader = FLASH_SHADER
	_sprite.material = _flash_mat
	add_child(_sprite)
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

func _process(delta: float) -> void:
	_anim_t += delta
	if combatant and combatant.is_alive() and _sprite.hframes > 1:
		_sprite.frame = int(_anim_t * 3.0) % _sprite.hframes

func refresh() -> void:
	var tags := []
	var col := WHITE
	for s in combatant.statuses:
		tags.append(s.data.display_name.to_upper())
		col = s.data.color
	_status_label.text = " ".join(tags)
	_status_label.add_theme_color_override("font_color", col)
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
		var y := -_sprite.texture.get_height() * 2 - 8 - int(_anim_t * 6.0) % 2
		draw_colored_polygon(PackedVector2Array([Vector2(-3, y), Vector2(4, y), Vector2(0, y + 4)]), GOLD)

func lunge(direction: float) -> void:
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
	await tw.finished
	queue_redraw()

func die() -> void:
	# blink out (no alpha blending: pure on/off like old consoles)
	for i in 6:
		_sprite.visible = i % 2 == 1
		await get_tree().create_timer(0.06).timeout
	_sprite.visible = false
	_status_label.visible = false
	queue_redraw()

func top() -> Vector2:
	return position + Vector2(0, -_sprite.texture.get_height() * 2 - 4)
