## Turn-based battle driver.
##
##   _ready()          read GameState.pending_encounter, build Combatants + views
##   TurnQueue.setup   charge-time clocks from SPD
##   EncounterRules    bend the clocks + apply opening statuses (advantage)
##   _battle_loop()    next actor -> start-of-turn ticks -> skip? -> choose -> execute -> end-of-turn
##
## Every action (player or AI) goes through SkillExecutor.execute(), which
## returns events; _present() animates them. Rules never wait on animation
## code except through those events, so `fast = true` runs a whole battle in
## a few frames for the automated loop test.
class_name BattleManager
extends Node2D

signal battle_finished(result: StringName)
signal command_chosen(cmd: Dictionary)

const FALLBACK_ENEMY := preload("res://data/combatants/slime.tres")
const RUN_CHANCE := 0.6

## Skip all animation waits (tests).
@export var fast := false
## Let the hero pick actions by itself (tests / demo).
@export var auto_play := false
## Go back to the overworld through BattleTransition when the battle ends.
@export var return_on_finish := true
@export var rng_seed := 0

var rng := RandomNumberGenerator.new()
var queue := TurnQueue.new()
var party: Array[Combatant] = []
var enemies: Array[Combatant] = []
var advantage: EncounterRules.Advantage = EncounterRules.Advantage.NEUTRAL
var views: Dictionary = {}          # Combatant -> BattleActorView
var turn_count := 0
var result: StringName = &""
var _ended := false

@onready var party_slots: Node2D = $PartySlots
@onready var enemy_slots: Node2D = $EnemySlots
@onready var actors: Node2D = $Actors
@onready var fx: Node2D = $FX
@onready var banner: Label = $UI/Banner
@onready var turn_label: Label = $UI/TurnOrder
@onready var log_label: Label = $UI/Log
@onready var hero_name: Label = $UI/HeroPanel/VBox/Name
@onready var hero_hp: Label = $UI/HeroPanel/VBox/HP
@onready var hero_mp: Label = $UI/HeroPanel/VBox/MP
@onready var command_panel: PanelContainer = $UI/Commands
@onready var command_list: VBoxContainer = $UI/Commands/VBox/List
@onready var command_info: Label = $UI/Commands/VBox/Info

## The battle renders in canvas_items stretch: layout and pixel art stay on the 320x180 grid
## (same 4x look), but the HD battle sprites (battle_frames) are drawn at full output
## resolution. The overworld keeps the original pixel-perfect viewport stretch.
const BATTLE_STRETCH := Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
var _prev_stretch := Window.CONTENT_SCALE_MODE_VIEWPORT

func _enter_tree() -> void:
	_prev_stretch = get_window().content_scale_mode
	get_window().content_scale_mode = BATTLE_STRETCH

func _exit_tree() -> void:
	get_window().content_scale_mode = _prev_stretch
	BattleTransition.set_display_grid(Vector2(320, 180))

## CRT filter on the output grid with the HD palettes (see BattleTransition.set_display_grid).
func _setup_display() -> void:
	var pals: Array[Texture2D] = []
	for c: Combatant in party + enemies:
		if c.stats.battle_frames_palette and not pals.has(c.stats.battle_frames_palette):
			pals.append(c.stats.battle_frames_palette)
	if pals.is_empty():
		return   # only pixel-strip combatants: keep the 320x180 CRT look
	BattleTransition.set_display_grid(Vector2(get_window().size), pals)

func _ready() -> void:
	if rng_seed != 0:
		rng.seed = rng_seed
	else:
		rng.randomize()
	_build_from_encounter(GameState.pending_encounter)
	_setup_display()
	command_panel.visible = false
	_battle_loop()

# ------------------------------------------------------------------ setup

func _build_from_encounter(enc: Dictionary) -> void:
	var enemy_stats: Array = enc.get("enemies", [])
	if enemy_stats.is_empty():
		enemy_stats = [FALLBACK_ENEMY]       # running battle.tscn directly (F6)
	advantage = enc.get("advantage", EncounterRules.Advantage.NEUTRAL)

	party = [GameState.hero]
	var letters := "ABC"
	var counts := {}
	for s in enemy_stats:
		counts[s.id] = int(counts.get(s.id, 0)) + 1
	var seen := {}
	for i in enemy_stats.size():
		var st: CombatantStats = enemy_stats[i]
		var e := Combatant.new(st, Combatant.Team.ENEMY, i)
		if counts[st.id] > 1:
			seen[st.id] = int(seen.get(st.id, 0)) + 1
			e.display_name = "%s %s" % [st.display_name, letters[seen[st.id] - 1]]
		enemies.append(e)

	var all: Array[Combatant] = []
	all.append_array(party)
	all.append_array(enemies)
	for c in all:
		for sk in c.stats.skills:          # passive skills = permanent statuses
			if sk.kind == SkillData.Kind.PASSIVE and sk.passive_status:
				c.add_status(sk.passive_status, 999)
	queue.setup(all, rng)
	EncounterRules.apply_opening(advantage, party, enemies)

	_spawn_view(party[0], party_slots.get_child(0).position, false)
	for i in enemies.size():
		var slot: Node2D = enemy_slots.get_child(mini(i, enemy_slots.get_child_count() - 1))
		_spawn_view(enemies[i], slot.position, true)

func _spawn_view(c: Combatant, pos: Vector2, face_left: bool) -> void:
	var v := BattleActorView.new()
	v.position = pos
	actors.add_child(v)
	v.setup(c, face_left)
	views[c] = v

# ------------------------------------------------------------------ loop

func _battle_loop() -> void:
	banner.text = EncounterRules.label(advantage)
	match advantage:
		EncounterRules.Advantage.PLAYER: banner.add_theme_color_override("font_color", Color("f5d26b"))
		EncounterRules.Advantage.ENEMY: banner.add_theme_color_override("font_color", Color("c8434b"))
	_refresh_ui()
	await _wait(1.0)
	banner.text = ""
	while not _ended:
		var end := _check_end()
		if end != &"":
			await _finish(end)
			return
		var actor := queue.next_actor()
		if actor == null:
			await _finish(&"defeat")
			return
		turn_count += 1
		_refresh_ui(actor)
		await _take_turn(actor)
		if _ended:
			return
		queue.advance(actor)
		if turn_count > 400:   # safety net for the headless loop test
			push_error("battle did not terminate")
			await _finish(&"defeat")
			return

func _take_turn(actor: Combatant) -> void:
	# 1. start-of-turn ticks (poison, burn)
	var dot := actor.start_of_turn()
	if not dot.is_empty():
		await _present(dot)
	if not actor.is_alive():
		return
	# 2. lost turn?
	if actor.must_skip_turn():
		_log("%s CAN'T MOVE!" % actor.display_name)
		await _wait(0.6)
		actor.end_of_turn()
		return
	# 3. choose
	var cmd: Dictionary
	if actor.side == Combatant.Team.PARTY and not auto_play:
		cmd = await _player_command(actor)
	elif actor.side == Combatant.Team.PARTY:
		cmd = _auto_command(actor)
	else:
		cmd = _ai_command(actor)
	# 4. run away?
	if cmd.get("run", false):
		if advantage == EncounterRules.Advantage.ENEMY and turn_count <= 2:
			_log("CAN'T ESCAPE AN AMBUSH YET!")
			await _wait(0.7)
		elif rng.randf() < RUN_CHANCE + (0.3 if advantage == EncounterRules.Advantage.PLAYER else 0.0):
			_log("GOT AWAY!")
			await _finish(&"fled")
			return
		else:
			_log("COULDN'T ESCAPE!")
			await _wait(0.7)
		actor.end_of_turn()
		return
	# 5. execute through the shared pipeline
	var skill: SkillData = cmd.skill
	var allies := party if actor.side == Combatant.Team.PARTY else enemies
	var foes := enemies if actor.side == Combatant.Team.PARTY else party
	var targets := SkillExecutor.resolve_targets(actor, skill, cmd.get("target"), allies, foes)
	var events := SkillExecutor.execute(actor, skill, targets, rng)
	await _present(events)
	actor.end_of_turn()
	_refresh_ui()

func _check_end() -> StringName:
	if party.all(func(c: Combatant) -> bool: return not c.is_alive()):
		return &"defeat"
	if enemies.all(func(c: Combatant) -> bool: return not c.is_alive()):
		return &"victory"
	return &""

func _finish(r: StringName) -> void:
	if _ended:
		return
	_ended = true
	result = r
	command_panel.visible = false
	match r:
		&"victory":
			banner.text = "VICTORY!"
			banner.add_theme_color_override("font_color", Color("f5d26b"))
		&"defeat":
			banner.text = "DEFEATED..."
			banner.add_theme_color_override("font_color", Color("c8434b"))
		&"fled":
			banner.text = "ESCAPED"
			banner.add_theme_color_override("font_color", Color("f4f0e6"))
	print("[battle] finished: %s after %d turns | %s" % [r, turn_count, GameState.hero.debug_state()])
	if r == &"victory" and not fast:
		for c in party:
			if c.is_alive() and views[c].has_anim(&"victory"):
				views[c].celebrate()
	await _wait(1.2)
	battle_finished.emit(r)
	if return_on_finish:
		BattleTransition.return_to_overworld(r)

# ------------------------------------------------------------------ choosing

func _ai_command(actor: Combatant) -> Dictionary:
	## Tiny weighted AI: prefer skills with status effects when the target
	## doesn't have them yet, otherwise basic attacks.
	var usable := actor.usable_skills()
	var target := party[0]
	var best: SkillData = usable[0]
	var best_w := -1.0
	for s in usable:
		var w := 1.0 + rng.randf()
		if s.applies_status and not target.has_status(s.applies_status.id):
			w += 1.0
		if s.mp_cost > 0:
			w += 0.3
		if w > best_w:
			best_w = w
			best = s
	return { "skill": best, "target": target }

func _auto_command(actor: Combatant) -> Dictionary:
	## Demo/test hero: heal when low, else strongest usable offensive skill.
	var usable := actor.usable_skills()
	var target := _first_alive(enemies)
	if actor.hp < actor.stats.max_hp * 0.35:
		for s in usable:
			if s.kind == SkillData.Kind.HEAL:
				return { "skill": s, "target": actor }
	var best: SkillData = null
	for s in usable:
		if s.is_offensive() and (best == null or s.power > best.power):
			best = s
	return { "skill": best if best else usable[0], "target": target }

func _player_command(actor: Combatant) -> Dictionary:
	while true:
		_show_skill_menu(actor)
		var cmd: Dictionary = await command_chosen
		if cmd.get("run", false):
			return cmd
		var skill: SkillData = cmd.skill
		var alive := enemies.filter(func(e: Combatant) -> bool: return e.is_alive())
		if skill.target == SkillData.Target.SINGLE_ENEMY and alive.size() > 1:
			_show_target_menu(alive)
			var pick: Dictionary = await command_chosen
			_clear_selection()
			if pick.get("back", false):
				continue
			cmd.target = pick.target
		command_panel.visible = false
		return cmd
	return {}

func _show_skill_menu(actor: Combatant) -> void:
	## UI derived from data (ForgeSkills: never hard-code slots). One button per
	## known skill; disabled ones show the reason (NO MP / CD n).
	_clear_buttons()
	command_panel.visible = true
	var first: Button = null
	for s in actor.stats.skills:
		if s.kind == SkillData.Kind.PASSIVE:
			continue
		var reason := actor.can_use(s)
		var b := _make_button(_skill_text(s, reason))
		b.disabled = reason != ""
		b.pressed.connect(func() -> void: command_chosen.emit({ "skill": s }))
		b.focus_entered.connect(func() -> void: command_info.text = s.description.to_upper())
		if first == null and not b.disabled:
			first = b
	var run := _make_button("RUN")
	run.pressed.connect(func() -> void: command_chosen.emit({ "run": true }))
	run.focus_entered.connect(func() -> void: command_info.text = "TRY TO ESCAPE.")
	if first:
		first.grab_focus()

func _show_target_menu(alive: Array) -> void:
	_clear_buttons()
	command_info.text = "CHOOSE A TARGET"
	var first: Button = null
	for e in alive:
		var b := _make_button("%s %d/%d" % [e.display_name.to_upper(), e.hp, e.stats.max_hp])
		b.pressed.connect(func() -> void: command_chosen.emit({ "target": e }))
		b.focus_entered.connect(func() -> void:
			_clear_selection()
			views[e].selected = true)
		if first == null:
			first = b
	var back := _make_button("BACK")
	back.pressed.connect(func() -> void: command_chosen.emit({ "back": true }))
	first.grab_focus()

func _skill_text(s: SkillData, reason: String) -> String:
	var t := s.display_name.to_upper()
	if reason != "":
		return "%s  %s" % [t, reason]
	if s.mp_cost > 0:
		return "%s  %dMP" % [t, s.mp_cost]
	return t

func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(92, 9)
	command_list.add_child(b)
	return b

func _clear_buttons() -> void:
	for c in command_list.get_children():
		command_list.remove_child(c)
		c.queue_free()

func _clear_selection() -> void:
	for v in views.values():
		v.selected = false

func _first_alive(list: Array[Combatant]) -> Combatant:
	for c in list:
		if c.is_alive():
			return c
	return null

# ------------------------------------------------------------------ presentation

func _present(events: Array[Dictionary]) -> void:
	var mover: BattleActorView = null      # HD user that ran up to its target
	for ev in events:
		match ev.type:
			"use":
				var u: Combatant = ev.user
				var dir := 1.0 if u.side == Combatant.Team.PARTY else -1.0
				_log("%s: %s" % [u.display_name.to_upper(), ev.skill.display_name.to_upper()])
				if fast:
					pass
				elif views[u].has_anim(&"idle"):
					var tv: BattleActorView = _first_target_view(events, u)
					await views[u].perform(ev.skill, tv, dir)
					if views[u].is_away():
						mover = views[u]
				elif ev.skill.is_offensive():
					await views[u].lunge(dir)
			"damage":
				_popup(ev.target, str(ev.amount), Color("f4f0e6"))
				if not fast:
					await _hitstop(0.06)
					await views[ev.target].hit(ev.amount >= 12)
				if ev.ko:
					_log("%s IS DEFEATED!" % ev.target.display_name.to_upper())
					if not fast:
						await views[ev.target].die()
			"heal":
				_popup(ev.target, "+%d" % ev.amount, Color("9fd16b"))
			"miss":
				_popup(ev.target, "MISS", Color("6b4f8a"))
			"status":
				_popup(ev.target, ev.status.display_name.to_upper(), ev.status.color, -8)
			"dot":
				_popup(ev.target, str(ev.amount), ev.status.color)
				_log("%s TAKES %s DAMAGE" % [ev.target.display_name.to_upper(), ev.status.display_name.to_upper()])
				if not fast:
					await views[ev.target].hit(false)
				if not ev.target.is_alive() and not fast:
					await views[ev.target].die()
			"fail":
				_log("%s FAILED (%s)" % [ev.skill.display_name.to_upper(), ev.reason])
		_refresh_ui()
		await _wait(0.25)
	if mover != null:
		await mover.return_home()

func _first_target_view(events: Array[Dictionary], user: Combatant) -> BattleActorView:
	for ev in events:
		if ev.has("target") and ev.target != user and views.has(ev.target):
			return views[ev.target]
	return null

func _popup(target: Combatant, text: String, color: Color, dy: int = 0) -> void:
	if fast:
		return
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color("1a1423"))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.position = (views[target].top() + Vector2(-6, dy)).round()
	fx.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", l.position.y - 10, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.3)
	tw.tween_callback(l.queue_free)

func _hitstop(t: float) -> void:
	Engine.time_scale = 0.05
	await get_tree().create_timer(t, true, false, true).timeout
	Engine.time_scale = 1.0

func _wait(t: float) -> void:
	if fast:
		await get_tree().process_frame
	else:
		await get_tree().create_timer(t).timeout

func _log(t: String) -> void:
	log_label.text = t

func _refresh_ui(current: Combatant = null) -> void:
	var h := party[0]
	hero_name.text = h.display_name.to_upper()
	hero_hp.text = "HP %d/%d" % [h.hp, h.stats.max_hp]
	hero_mp.text = "MP %d/%d" % [h.mp, h.stats.max_mp]
	var names := []
	for c in queue.preview(5):
		names.append(c.display_name.to_upper())
	turn_label.text = "NEXT: " + " > ".join(names)
	for v in views.values():
		v.queue_redraw()

func debug_state() -> String:
	var lines := ["advantage=%s turn=%d %s" % [EncounterRules.Advantage.keys()[advantage], turn_count, queue.debug_state()]]
	for c in party + enemies:
		lines.append("  " + c.debug_state())
	return "\n".join(lines)
