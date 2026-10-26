## Automated loop tests (ForgeSkills gamedev-game-testing / gameplay-systems step 7).
##
## Run headless:
##   godot --headless --path . res://tests/test_runner.tscn
## Exit code 0 = all passed. Every failure prints "FAIL <test>: <reason>".
extends Node

const HERO := preload("res://data/combatants/hero.tres")
const SLIME := preload("res://data/combatants/slime.tres")
const FIRE := preload("res://data/skills/fire.tres")
const POWER_SLASH := preload("res://data/skills/power_slash.tres")
const POISONED := preload("res://data/statuses/poisoned.tres")
const BATTLE := preload("res://scenes/battle/battle.tscn")
const OVERWORLD := preload("res://scenes/overworld/overworld.tscn")
const GUARD := preload("res://data/skills/guard.tres")
const A := EncounterRules.Advantage
const HD_ANIMS: Array[StringName] = [&"idle", &"attack", &"hurt", &"death", &"defend", &"advance", &"skill", &"victory"]
const ATTACK := preload("res://data/skills/attack.tres")

var failures := 0
var passes := 0
var _current := ""

func _ready() -> void:
	await get_tree().process_frame
	for t in ["skill_pipeline", "cooldowns", "status_modifiers", "advantage_rules",
			"opening_player_advantage", "opening_enemy_ambush", "persistence", "guard_lasts",
			"hd_knight_frames", "hd_battle_view", "battle_background", "knight_kit",
			"battle_loop_victory", "overworld_perception", "overworld_back_strike",
			"overworld_ambush_contact"]:
		_current = t
		GameState.reset()
		await call("test_" + t)
	print("\n%d checks passed, %d failed" % [passes, failures])
	get_tree().quit(1 if failures > 0 else 0)

func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
	else:
		failures += 1
		print("FAIL %s: %s" % [_current, msg])

func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = 1234
	return r

func _pair() -> Array[Combatant]:
	return [Combatant.new(HERO, Combatant.Team.PARTY), Combatant.new(SLIME, Combatant.Team.ENEMY)]

# ---------------------------------------------------------------- skills

func test_skill_pipeline() -> void:
	var p := _pair()
	var hero := p[0]
	var slime := p[1]
	var mp0 := hero.mp
	var ev := SkillExecutor.execute(hero, FIRE, [slime], _rng())
	check(hero.mp == mp0 - FIRE.mp_cost, "fire costs mp (%d -> %d)" % [mp0, hero.mp])
	check(slime.hp < slime.stats.max_hp, "fire deals damage")
	check(ev.any(func(e): return e.type == "damage"), "damage event emitted")
	hero.mp = 0
	ev = SkillExecutor.execute(hero, FIRE, [slime], _rng())
	check(ev.size() == 1 and ev[0].type == "fail" and ev[0].reason == "NO MP", "no-mp is rejected")

func test_cooldowns() -> void:
	var p := _pair()
	var hero := p[0]
	SkillExecutor.execute(hero, POWER_SLASH, [p[1]], _rng())
	hero.end_of_turn()                                   # same turn ends
	check(hero.can_use(POWER_SLASH).begins_with("CD"), "blocked on next turn")
	hero.end_of_turn()
	check(hero.can_use(POWER_SLASH).begins_with("CD"), "blocked on 2nd turn")
	hero.end_of_turn()
	check(hero.can_use(POWER_SLASH) == "", "usable again after 2 turns")

func test_status_modifiers() -> void:
	var hero := Combatant.new(HERO)
	var def0 := hero.get_def()
	hero.add_status(EncounterRules.STATUS_OFF_GUARD)
	check(hero.get_def() == roundi(def0 * 0.5), "off-guard halves defense")
	hero.add_status(EncounterRules.STATUS_STUNNED, 1)
	check(hero.must_skip_turn(), "stun skips turn")
	hero.end_of_turn()
	check(not hero.must_skip_turn(), "stun expires after one turn")

# ---------------------------------------------------------------- advantage

func test_advantage_rules() -> void:
	# enemy at origin looking RIGHT
	check(EncounterRules.is_behind(Vector2.RIGHT, Vector2.ZERO, Vector2(-20, 0)), "left is behind")
	check(not EncounterRules.is_behind(Vector2.RIGHT, Vector2.ZERO, Vector2(20, 0)), "right is in front")
	check(not EncounterRules.is_behind(Vector2.RIGHT, Vector2.ZERO, Vector2(0, 20)), "side is not behind")
	check(EncounterRules.resolve_player_strike(false, Vector2.RIGHT, Vector2.ZERO, Vector2(-16, 2)) == A.PLAYER,
		"unaware + behind -> PLAYER")
	check(EncounterRules.resolve_player_strike(true, Vector2.RIGHT, Vector2.ZERO, Vector2(-16, 2)) == A.NEUTRAL,
		"aware enemy -> NEUTRAL")
	check(EncounterRules.resolve_player_strike(false, Vector2.RIGHT, Vector2.ZERO, Vector2(16, 0)) == A.NEUTRAL,
		"frontal strike -> NEUTRAL")
	# player at origin looking DOWN, enemy coming from above (behind)
	check(EncounterRules.resolve_enemy_contact(true, Vector2.DOWN, Vector2.ZERO, Vector2(0, -10)) == A.ENEMY,
		"chasing + behind -> ENEMY")
	check(EncounterRules.resolve_enemy_contact(false, Vector2.DOWN, Vector2.ZERO, Vector2(0, -10)) == A.NEUTRAL,
		"patrolling bump -> NEUTRAL")
	check(EncounterRules.resolve_enemy_contact(true, Vector2.DOWN, Vector2.ZERO, Vector2(0, 10)) == A.NEUTRAL,
		"face to face -> NEUTRAL")

func _opening(adv: EncounterRules.Advantage) -> Array[Combatant]:
	var hero := Combatant.new(HERO, Combatant.Team.PARTY)
	var e1 := Combatant.new(SLIME, Combatant.Team.ENEMY, 0)
	var e2 := Combatant.new(SLIME, Combatant.Team.ENEMY, 1)
	var party: Array[Combatant] = [hero]
	var enemies: Array[Combatant] = [e1, e2]
	var q := TurnQueue.new()
	q.setup(party + enemies, _rng())
	EncounterRules.apply_opening(adv, party, enemies)
	var order := q.preview(3)
	return [hero, e1, e2, order[0]]

func test_opening_player_advantage() -> void:
	var r := _opening(A.PLAYER)
	check(r[3] == r[0], "hero acts first")
	check(r[0].has_status(&"surprise_boost"), "hero gets Surprise Boost")
	check(r[1].must_skip_turn() and r[2].must_skip_turn(), "enemies are stunned")

func test_opening_enemy_ambush() -> void:
	var r := _opening(A.ENEMY)
	check(r[3] != r[0], "an enemy acts first (got %s)" % r[3].display_name)
	check(r[0].has_status(&"off_guard"), "hero is Off-Guard")

func test_persistence() -> void:
	var hero := GameState.hero
	hero.add_status(POISONED)
	hero.add_status(EncounterRules.STATUS_SURPRISE)
	hero.hp -= 10
	GameState.pending_encounter = { "enemy_id": &"x" }
	GameState.finish_encounter(&"victory")
	check(hero.has_status(&"poisoned"), "poison survives the battle")
	check(not hero.has_status(&"surprise_boost"), "battle-only status cleared")
	check(hero.hp == hero.stats.max_hp - 10, "hp carried over")
	check(GameState.is_defeated(&"x"), "enemy marked defeated")

func test_guard_lasts() -> void:
	## "Guard: double defense until your next turn" — it must still be up while enemies act.
	var r := _pair()
	var hero := r[0]
	hero.start_of_turn()
	SkillExecutor.execute(hero, GUARD, [hero], _rng())
	hero.end_of_turn()
	check(hero.has_status(&"guarding"), "Guard survives the end of the turn it was used")
	hero.start_of_turn()
	hero.end_of_turn()
	check(not hero.has_status(&"guarding"), "Guard is gone after the hero's next turn")
	var slime := r[1]
	slime.start_of_turn()
	slime.add_status(POISONED)       # applied by someone else's action: ticks normally
	slime.end_of_turn()
	hero.add_status(POISONED)        # outside the hero's own turn
	var before: int = hero.statuses.filter(func(s): return s.data.id == &"poisoned")[0].turns
	hero.start_of_turn()
	hero.end_of_turn()
	var after: int = hero.statuses.filter(func(s): return s.data.id == &"poisoned")[0].turns
	check(after == before - 1, "statuses from others still tick every turn (%d -> %d)" % [before, after])

# ---------------------------------------------------------------- HD battle sprites

## Background art on the 320x180 grid, and every color of it is in the palette merged into
## the CRT filter (otherwise F2 remaps the scenery to the overworld colors).
func test_knight_kit() -> void:
	var hero: CombatantStats = load("res://data/combatants/hero.tres")
	var ids: Array = hero.skills.map(func(sk: SkillData) -> StringName: return sk.id)
	check(ids == [&"attack", &"power_slash", &"fire", &"guard"], "knight kit is attack/power slash/fire/guard (%s)" % [ids])
	check(not hero.skills.any(func(sk: SkillData) -> bool: return sk.kind == SkillData.Kind.HEAL), "knight has no heal skill")

func test_battle_background() -> void:
	var scene: Node = load("res://scenes/battle/battle.tscn").instantiate()
	var bg: Image = (scene.get_node("Background") as Sprite2D).texture.get_image()
	var pal_tex: Texture2D = scene.background_palette
	check(bg.get_size() == Vector2i(320, 180), "background is 320x180 (%s)" % bg.get_size())
	check(pal_tex != null, "battle has a background palette")
	if pal_tex:
		var pal := {}
		var pimg := pal_tex.get_image()
		for x: int in pimg.get_width():
			pal[pimg.get_pixel(x, 0).to_html(false)] = true
		var missing := 0
		for y: int in bg.get_height():
			for x: int in bg.get_width():
				if not pal.has(bg.get_pixel(x, y).to_html(false)):
					missing += 1
		check(missing == 0, "all background colors in its palette (%d px missing)" % missing)
	scene.free()

func test_hd_knight_frames() -> void:
	var f: SpriteFrames = HERO.battle_frames
	check(f != null, "hero has HD battle frames")
	if f == null:
		return
	for anim in HD_ANIMS:
		check(f.has_animation(anim), "HD anim '%s' exists" % anim)
		if not f.has_animation(anim):
			continue
		for i in f.get_frame_count(anim):
			var tex := f.get_frame_texture(anim, i)
			check(tex.get_height() == 224, "%s[%d] cell is 224 px tall" % [anim, i])
			# feet sit on the shared origin row (190): last opaque row of every frame
			var used := tex.get_image().get_used_rect()
			check(used.end.y == int(HERO.battle_frames_origin.y) + 1 or anim == &"death",
				"%s[%d] feet on the origin row (bottom=%d)" % [anim, i, used.end.y])
	check(f.get_animation_loop(&"idle") and not f.get_animation_loop(&"attack") and not f.get_animation_loop(&"death"),
		"idle loops; attack/death play once")

func test_hd_battle_view() -> void:
	var before := get_window().content_scale_mode
	var enemies: Array[CombatantStats] = [SLIME]
	GameState.begin_encounter(&"hd", enemies, A.NEUTRAL, Vector2.ZERO, Vector2.RIGHT)
	var b: BattleManager = BATTLE.instantiate()
	b.return_on_finish = false
	b.rng_seed = 3
	add_child(b)
	await get_tree().process_frame
	check(get_window().content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,
		"battle renders in canvas_items stretch (HD sprites at full resolution)")
	var hero: Combatant = b.party[0]
	var v: BattleActorView = b.views[hero]
	var spr: AnimatedSprite2D = v._hd
	check(spr != null, "hero view uses the HD AnimatedSprite2D")
	if spr:
		# 320x180 grid x4 = 1280x720 output: scale 0.25 -> 1 art pixel = 1 screen pixel
		check(is_equal_approx(spr.scale.x * 4.0, 1.0), "HD sprite is 1:1 on a 1280x720 output (scale %s)" % spr.scale)
		check(spr.animation == &"idle" and spr.is_playing(), "rests on idle")
		check(v.sprite_height() > 40 and v.sprite_height() < 48, "HD height ~43 grid px (%.1f)" % v.sprite_height())
		hero.add_status(GUARD.applies_status)
		check(spr.animation == &"defend", "Guarding shows the defend pose (%s)" % spr.animation)
		hero.remove_status(&"guarding")
		check(spr.animation == &"idle", "back to idle when Guard ends")
		# Attack: run up to the target (advance), swing, stay; run back after the hit
		var foe: BattleActorView = b.views[b.enemies[0]]
		var seen := {}
		spr.animation_changed.connect(func() -> void: seen[spr.animation] = true)
		await v.perform(ATTACK, foe, 1.0)
		check(seen.has(&"advance") and seen.has(&"attack"), "attack runs in (advance) then swings (%s)" % [seen.keys()])
		var gap := foe.position.x - v.position.x
		check(v.is_away() and absf(gap - BattleActorView.MELEE_GAP) < 1.0,
			"knight stands in front of the enemy (gap %.1f)" % gap)
		await v.return_home()
		check(not v.is_away() and spr.animation == &"idle" and spr.scale.x > 0,
			"runs back home, facing the enemies again")
		await v.celebrate()
		check(spr.animation == &"victory" and spr.frame == spr.sprite_frames.get_frame_count(&"victory") - 1,
			"victory plays and holds the cheer")
		hero.hp = 0
		await v.die()
		check(spr.animation == &"death" and spr.frame == spr.sprite_frames.get_frame_count(&"death") - 1,
			"death holds its last frame")
	b.queue_free()
	await get_tree().process_frame
	check(get_window().content_scale_mode == before, "stretch mode restored after battle")

# ---------------------------------------------------------------- loop tests

func test_battle_loop_victory() -> void:
	var enemies: Array[CombatantStats] = [SLIME, SLIME]
	GameState.begin_encounter(&"loop_slimes", enemies, A.PLAYER, Vector2(10, 10), Vector2.RIGHT)
	var b: BattleManager = BATTLE.instantiate()
	b.fast = true
	b.auto_play = true
	b.return_on_finish = false
	b.rng_seed = 7
	add_child(b)
	var frames := 0
	while b.result == &"" and frames < 3000:
		await get_tree().process_frame
		frames += 1
	check(b.result == &"victory", "auto battle ends in victory (got '%s' after %d frames)" % [b.result, frames])
	check(b.enemies.all(func(e): return not e.is_alive()), "all enemies down")
	check(GameState.hero.is_alive(), "hero survives 2 slimes")
	print("  battle: %d turns, %s" % [b.turn_count, GameState.hero.debug_state()])
	b.queue_free()
	await get_tree().process_frame

func _spawn_overworld() -> Node2D:
	var ow: Node2D = OVERWORLD.instantiate()
	add_child(ow)
	for e in get_tree().get_nodes_in_group("overworld_enemies"):
		e.start_battle_on_trigger = false
	return ow

func _physics(n: int) -> void:
	for i in n:
		await get_tree().physics_frame

func test_overworld_perception() -> void:
	var ow := _spawn_overworld()
	var player: OverworldPlayer = ow.get_node("Actors/Player")
	var enemy: OverworldEnemy = ow.get_node("Actors/SlimePath")
	enemy.patrol_points = PackedVector2Array()          # stand still
	enemy.facing_angle = 0.0                             # look right
	await _physics(2)
	player.global_position = enemy.global_position + Vector2(40, 0)
	var states := []
	enemy.state_changed.connect(func(_e, _o, s): states.append(s))
	await _physics(150)
	check(OverworldEnemy.State.SUSPICIOUS in states, "went SUSPICIOUS first (%s)" % [states])
	check(OverworldEnemy.State.ALERT in states, "then ALERT (telegraph)")
	check(enemy.state == OverworldEnemy.State.CHASE, "ends in CHASE: %s" % enemy.debug_state())
	ow.queue_free()
	await get_tree().process_frame

func test_overworld_back_strike() -> void:
	var ow := _spawn_overworld()
	var player: OverworldPlayer = ow.get_node("Actors/Player")
	var enemy: OverworldEnemy = ow.get_node("Actors/SlimePath")
	enemy.patrol_points = PackedVector2Array()
	enemy.facing_angle = 0.0                              # looking right...
	player.global_position = enemy.global_position + Vector2(-14, 0)   # ...player behind it
	player.facing = Vector2.RIGHT
	var got := []
	enemy.battle_requested.connect(func(_e, adv): got.append(adv))
	await _physics(3)
	player._strike()
	await _physics(4)
	check(got.size() == 1, "strike hit the enemy (%d hits)" % got.size())
	check(got.size() == 1 and got[0] == A.PLAYER, "back strike gives PLAYER advantage (%s)" % [got])
	ow.queue_free()
	await get_tree().process_frame

func test_overworld_ambush_contact() -> void:
	var ow := _spawn_overworld()
	var player: OverworldPlayer = ow.get_node("Actors/Player")
	var enemy: OverworldEnemy = ow.get_node("Actors/SlimePath")
	enemy.patrol_points = PackedVector2Array()
	player.input_enabled = false
	player.facing = Vector2.LEFT                        # looking away from the slime
	player.global_position = enemy.global_position + Vector2(-40, 0)
	enemy.facing_angle = PI                             # slime looks at the player's back
	var got := []
	enemy.battle_requested.connect(func(_e, adv): got.append(adv))
	await _physics(200)                                  # it notices, telegraphs, chases, touches
	check(got.size() == 1, "chasing enemy reached the player (%s)" % enemy.debug_state())
	check(got.size() == 1 and got[0] == A.ENEMY, "contact from behind = ENEMY ambush (%s)" % [got])
	ow.queue_free()
	await get_tree().process_frame
