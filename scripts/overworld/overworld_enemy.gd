## A visible overworld enemy: patrols, looks, gets suspicious, chases, and
## turns contact into a battle with the right opening advantage.
##
## SPEC (ForgeSkills gameplay-systems)
##   PURPOSE  : make the player choose between sneaking (advantage) and rushing
##   INPUTS   : player position/facing/sneak, line of sight, patrol route
##   STATE    : State enum, awareness 0..1, last_seen position, facing angle
##   RULES    : PATROL ->(awareness>=SUSPICIOUS_AT) SUSPICIOUS ->(awareness>=1) ALERT
##              ALERT (telegraph pause) -> CHASE ->(no sight for lose_time) SUSPICIOUS
##              SUSPICIOUS ->(awareness==0) PATROL
##   FEEDBACK : vision cone colour, "?" / "!" icon, chase speed, hop on alert
##
## Detection is a meter, not a boolean: seeing the player fills it (faster when
## close), losing them drains it. Sneaking halves the fill rate and disables
## "hearing" (a small 360 degree radius).
class_name OverworldEnemy
extends CharacterBody2D

signal state_changed(enemy: OverworldEnemy, old_state: State, new_state: State)
signal battle_requested(enemy: OverworldEnemy, advantage: EncounterRules.Advantage)

enum State { PATROL, SUSPICIOUS, ALERT, CHASE }

const ICON_Q := preload("res://assets/sprites/icon_question.png")
const ICON_ALERT := preload("res://assets/sprites/icon_alert.png")
const WORLD_MASK := 1
const SUSPICIOUS_AT := 0.3

@export var enemy_id: StringName = &"slime_01"
## The battle party this overworld enemy represents.
@export var encounter: Array[CombatantStats] = []
## Patrol waypoints, relative to the spawn position (ping-pong order).
@export var patrol_points: PackedVector2Array = PackedVector2Array([Vector2(-32, 0), Vector2(32, 0)])
@export var overworld_texture: Texture2D
@export var overworld_hframes := 2
## Tests turn this off to check the advantage without leaving the scene.
@export var start_battle_on_trigger := true

@export_group("Movement")
@export var patrol_speed := 26.0
@export var chase_speed := 58.0
@export var wait_at_point := 0.9
@export var turn_speed := 5.0          # rad/s for the vision cone

@export_group("Perception")
@export var view_distance := 84.0
@export_range(5.0, 90.0) var view_half_angle_deg := 38.0
@export var hear_radius := 22.0
@export var see_rate := 1.6            # awareness/s at point-blank
@export var decay_rate := 0.35
@export var alert_pause := 0.45        # ForgeSkills: telegraph before acting (0.4-1.2s)
@export var lose_time := 2.2

var state: State = State.PATROL
var awareness := 0.0
var facing_angle := 0.0                 # radians; 0 = right
var last_seen := Vector2.ZERO
var _home := Vector2.ZERO
var _wp := 0
var _wp_dir := 1
var _wait := 0.0
var _state_t := 0.0
var _unseen_t := 0.0
var _dazed_t := 0.0
var _anim_t := 0.0
var _player: OverworldPlayer
var _sees_player := false
var _triggered := false

@onready var sprite: Sprite2D = $Sprite
@onready var icon: Sprite2D = $Icon
@onready var sight_ray: RayCast2D = $SightRay
@onready var contact_area: Area2D = $ContactArea

func _ready() -> void:
	add_to_group("overworld_enemies")
	if GameState.is_defeated(enemy_id):
		queue_free()
		return
	_home = global_position
	if overworld_texture:
		sprite.texture = overworld_texture
		sprite.hframes = overworld_hframes
	sprite.offset = Vector2(-sprite.texture.get_width() / sprite.hframes / 2, -sprite.texture.get_height())
	if patrol_points.size() > 0:
		facing_angle = (patrol_points[0]).angle()
	contact_area.body_entered.connect(_on_contact)
	if GameState.fled_from == enemy_id:
		_dazed_t = 2.5          # the one you ran from needs a moment
		GameState.fled_from = &""

func facing() -> Vector2:
	return Vector2.from_angle(facing_angle)

func is_aware() -> bool:
	return state == State.ALERT or state == State.CHASE

# ------------------------------------------------------------------ main loop

func _physics_process(delta: float) -> void:
	if _triggered:
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	_state_t += delta
	_anim_t += delta
	_dazed_t = maxf(0.0, _dazed_t - delta)
	_perceive(delta)
	match state:
		State.PATROL: _do_patrol(delta)
		State.SUSPICIOUS: _do_suspicious(delta)
		State.ALERT: _do_alert(delta)
		State.CHASE: _do_chase(delta)
	move_and_slide()
	sprite.frame = int(_anim_t * (8.0 if state == State.CHASE else 4.0)) % maxi(1, sprite.hframes)
	sprite.flip_h = facing().x < -0.1
	queue_redraw()

func _perceive(delta: float) -> void:
	_sees_player = false
	if _player == null or _dazed_t > 0.0 or GameState.in_grace():
		awareness = maxf(0.0, awareness - decay_rate * delta)
		return
	var to_p := _player.global_position - global_position
	var dist := to_p.length()
	var in_cone := dist <= view_distance \
		and absf(angle_difference(facing_angle, to_p.angle())) <= deg_to_rad(view_half_angle_deg)
	if in_cone and _has_line_of_sight():
		_sees_player = true
		last_seen = _player.global_position
		var closeness := 1.0 - clampf(dist / view_distance, 0.0, 1.0)
		var rate := see_rate * (0.35 + 0.65 * closeness) * (0.5 if _player.is_sneaking else 1.0)
		awareness = minf(1.0, awareness + rate * delta)
	elif dist <= hear_radius and not _player.is_sneaking:
		last_seen = _player.global_position          # heard footsteps
		awareness = minf(1.0, awareness + 0.9 * delta)
	else:
		awareness = maxf(0.0, awareness - decay_rate * delta)

	if awareness >= 1.0 and not is_aware():
		_set_state(State.ALERT)
	elif awareness >= SUSPICIOUS_AT and state == State.PATROL:
		_set_state(State.SUSPICIOUS)

func _has_line_of_sight() -> bool:
	sight_ray.target_position = sight_ray.to_local(_player.global_position + Vector2(0, -6))
	sight_ray.force_raycast_update()
	return not sight_ray.is_colliding()

# ------------------------------------------------------------------ states

func _do_patrol(delta: float) -> void:
	if patrol_points.is_empty():
		velocity = Vector2.ZERO
		return
	if _wait > 0.0:
		_wait -= delta
		velocity = Vector2.ZERO
		# look around while waiting: sweep the cone left and right
		facing_angle += sin(_state_t * 2.5) * delta * 1.2
		return
	var target := _home + patrol_points[_wp]
	var to_t := target - global_position
	if to_t.length() < 2.0:
		_wait = wait_at_point
		if patrol_points.size() > 1:
			if _wp + _wp_dir >= patrol_points.size() or _wp + _wp_dir < 0:
				_wp_dir = -_wp_dir
			_wp += _wp_dir
		return
	velocity = to_t.normalized() * patrol_speed
	_turn_towards(velocity.angle(), delta)

func _do_suspicious(delta: float) -> void:
	velocity = Vector2.ZERO
	_turn_towards((last_seen - global_position).angle(), delta)
	# creep a little towards the noise
	if global_position.distance_to(last_seen) > 18.0 and _state_t > 0.6:
		velocity = (last_seen - global_position).normalized() * patrol_speed * 0.6
	if awareness <= 0.0:
		_set_state(State.PATROL)

func _do_alert(delta: float) -> void:
	# Telegraph: stop dead, face the player, hop. The player gets alert_pause
	# seconds to react before the chase starts.
	velocity = Vector2.ZERO
	_turn_towards((last_seen - global_position).angle(), delta * 3.0)
	sprite.position.y = -absf(sin(_state_t * PI / alert_pause)) * 4.0
	if _state_t >= alert_pause:
		sprite.position.y = 0
		_set_state(State.CHASE)

func _do_chase(delta: float) -> void:
	var target := last_seen
	if _sees_player:
		_unseen_t = 0.0
		target = _player.global_position
	else:
		_unseen_t += delta
		if _unseen_t >= lose_time or global_position.distance_to(last_seen) < 4.0 and _unseen_t > 0.5:
			awareness = 0.6
			_set_state(State.SUSPICIOUS)
			return
	velocity = (target - global_position).normalized() * chase_speed
	_turn_towards(velocity.angle(), delta * 2.0)

func _turn_towards(angle: float, delta: float) -> void:
	facing_angle = rotate_toward(facing_angle, angle, turn_speed * delta)

func _set_state(s: State) -> void:
	if s == state:
		return
	var old := state
	state = s
	_state_t = 0.0
	_unseen_t = 0.0
	match s:
		State.SUSPICIOUS:
			icon.texture = ICON_Q
			icon.visible = true
		State.ALERT, State.CHASE:
			icon.texture = ICON_ALERT
			icon.visible = true
		_:
			icon.visible = false
	state_changed.emit(self, old, s)

# ------------------------------------------------------------------ encounters

func on_player_strike(player: OverworldPlayer) -> void:
	## Called by the player's strike hitbox.
	if _triggered or BattleTransition.busy or GameState.in_grace():
		return
	var adv := EncounterRules.resolve_player_strike(is_aware(), facing(),
		global_position, player.global_position)
	_trigger_battle(player, adv)

func _on_contact(body: Node) -> void:
	if not body is OverworldPlayer or _triggered or BattleTransition.busy \
			or GameState.in_grace() or _dazed_t > 0.0:
		return
	var player := body as OverworldPlayer
	var adv := EncounterRules.resolve_enemy_contact(state == State.CHASE, player.facing,
		player.global_position, global_position)
	_trigger_battle(player, adv)

func _trigger_battle(player: OverworldPlayer, adv: EncounterRules.Advantage) -> void:
	_triggered = true
	velocity = Vector2.ZERO
	player.input_enabled = false
	battle_requested.emit(self, adv)
	print("[encounter] %s advantage=%s | %s" % [enemy_id, EncounterRules.Advantage.keys()[adv], debug_state()])
	if start_battle_on_trigger:
		BattleTransition.start_battle(enemy_id, encounter, adv, player.global_position, player.facing)

# ------------------------------------------------------------------ feedback

func _draw() -> void:
	if not GameState.debug_overlay and state == State.PATROL and awareness <= 0.0:
		_draw_cone(Color(0.96, 0.94, 0.9, 0.10))
		return
	var col: Color
	match state:
		State.PATROL: col = Color(0.96, 0.94, 0.9, 0.12)
		State.SUSPICIOUS: col = Color(0.96, 0.82, 0.42, 0.20)
		_: col = Color(0.78, 0.26, 0.29, 0.25)
	_draw_cone(col)
	var w := int(round(awareness * 12.0))
	if w > 0 and awareness < 1.0:
		# 12px awareness meter above the "?" icon, whole pixels only
		draw_rect(Rect2(-6, -28, 12, 2), Color("1a1423"))
		draw_rect(Rect2(-6, -28, w, 2), Color("f5d26b"))

func _draw_cone(col: Color) -> void:
	var pts := PackedVector2Array([Vector2(0, -5)])
	var half := deg_to_rad(view_half_angle_deg)
	var steps := 10
	for i in steps + 1:
		var a := facing_angle - half + (2.0 * half) * float(i) / steps
		pts.append((Vector2(0, -5) + Vector2.from_angle(a) * view_distance).round())
	draw_colored_polygon(pts, col)

func debug_state() -> String:
	return "%s state=%s aware=%.2f facing=%s sees=%s" % [
		enemy_id, State.keys()[state], awareness, facing().snapped(Vector2(0.01, 0.01)), _sees_player]
