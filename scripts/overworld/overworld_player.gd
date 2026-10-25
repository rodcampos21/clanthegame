## Overworld hero: 4-way movement, sneaking, and the field strike that starts
## battles (the "hit it first" mechanic from Chrono Trigger / Persona 5).
class_name OverworldPlayer
extends CharacterBody2D

const TEX_DOWN := preload("res://assets/sprites/hero_down.png")
const TEX_UP := preload("res://assets/sprites/hero_up.png")
const TEX_SIDE := preload("res://assets/sprites/hero_side.png")

@export var walk_speed := 72.0
@export var sneak_speed := 34.0
@export var strike_reach := 12.0
@export var strike_cooldown := 0.35

var facing := Vector2.DOWN
var is_sneaking := false
var input_enabled := true
var _anim_t := 0.0
var _strike_cd := 0.0
var _slash_t := 0.0            # >0 while the slash arc is visible

@onready var sprite: Sprite2D = $Sprite
@onready var strike_area: Area2D = $StrikeArea
@onready var camera: Camera2D = $Camera

func _ready() -> void:
	add_to_group("player")
	_update_sprite(false)

func setup_camera(limits: Vector2i) -> void:
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = limits.x
	camera.limit_bottom = limits.y

func _physics_process(delta: float) -> void:
	_strike_cd = maxf(0.0, _strike_cd - delta)
	_slash_t = maxf(0.0, _slash_t - delta)
	var dir := Vector2.ZERO
	if input_enabled:
		dir = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		is_sneaking = Input.is_action_pressed("sneak")
		if Input.is_action_just_pressed("strike") and _strike_cd <= 0.0:
			_strike()
	# 4-way facing from the dominant axis
	if dir != Vector2.ZERO:
		facing = Vector2(signf(dir.x), 0) if absf(dir.x) > absf(dir.y) else Vector2(0, signf(dir.y))
	velocity = dir.normalized() * (sneak_speed if is_sneaking else walk_speed)
	move_and_slide()
	_anim_t += delta * (velocity.length() / 12.0)
	_update_sprite(velocity != Vector2.ZERO)
	queue_redraw()

func _update_sprite(moving: bool) -> void:
	if facing.y > 0:
		sprite.texture = TEX_DOWN
	elif facing.y < 0:
		sprite.texture = TEX_UP
	else:
		sprite.texture = TEX_SIDE
	sprite.flip_h = facing.x < 0
	# Feet at the body origin, whole-pixel offset (no half-pixel blur when centred).
	var fw := sprite.texture.get_width() / sprite.hframes
	sprite.offset = Vector2(-fw / 2, -sprite.texture.get_height())
	sprite.frame = (int(_anim_t) % 2) if moving else 0
	sprite.modulate.a = 0.65 if is_sneaking else 1.0

func _strike() -> void:
	## Short-lived hitbox in front of the hero. Any enemy body inside it gets
	## on_player_strike(); the enemy decides the advantage (it knows its state).
	_strike_cd = strike_cooldown
	_slash_t = 0.12
	strike_area.position = facing * strike_reach + Vector2(0, -6)
	await get_tree().physics_frame
	await get_tree().physics_frame      # overlaps are valid after a physics step
	if not is_inside_tree():
		return
	for body in strike_area.get_overlapping_bodies():
		if body.has_method("on_player_strike"):
			body.on_player_strike(self)
			return

func _draw() -> void:
	if _slash_t <= 0.0:
		return
	# A 3-pixel arc in front: crisp, palette-only feedback for the swing.
	var c := strike_area.position
	var perp := Vector2(-facing.y, facing.x)
	for i in range(-4, 5):
		var p := (c + perp * i + facing * (2 - absi(i) / 2)).floor()
		draw_rect(Rect2(p, Vector2.ONE), Color("f4f0e6"))

func restore(snapshot: Dictionary) -> void:
	if snapshot.has("position"):
		global_position = snapshot.position
	if snapshot.has("facing"):
		facing = snapshot.facing
	_update_sprite(false)

func debug_state() -> String:
	return "player pos=%s facing=%s sneak=%s" % [global_position.round(), facing, is_sneaking]
