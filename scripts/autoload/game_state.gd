## Global, persistent game state (autoload "GameState").
##
## Holds what must survive scene changes:
##   * the hero's Combatant (HP, MP, cooldowns, persistent statuses)
##   * the overworld snapshot to restore after battle (position, facing)
##   * which overworld enemies were defeated
##   * the pending encounter handed from the overworld to the battle scene
extends Node

signal hero_changed

const HERO_STATS := preload("res://data/combatants/hero.tres")
const OVERWORLD_SCENE := "res://scenes/overworld/overworld.tscn"
const BATTLE_SCENE := "res://scenes/battle/battle.tscn"

var hero: Combatant
var overworld_snapshot: Dictionary = {}   # { "position": Vector2, "facing": Vector2 }
var defeated_enemies: Dictionary = {}     # enemy_id -> true
## { "enemy_id": StringName, "enemies": Array[CombatantStats], "advantage": int }
var pending_encounter: Dictionary = {}
var last_battle_result: StringName = &""
## Enemy the player just fled from; it stays dazed for a moment on return.
var fled_from: StringName = &""
## Ticks (msec) until which overworld contact cannot start a new battle.
var grace_until_ms: int = 0
var crt_enabled: bool = false
var debug_overlay: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Controls under a CanvasLayer don't inherit the root Window theme, so the
	# pixel font/styles are merged into the engine default theme instead.
	var dt := ThemeDB.get_default_theme()
	dt.merge_with(PixelFont.theme())
	dt.default_font = PixelFont.font()
	dt.default_font_size = PixelFont.SIZE
	ThemeDB.fallback_font = PixelFont.font()
	ThemeDB.fallback_font_size = PixelFont.SIZE
	reset()

func reset() -> void:
	hero = Combatant.new(HERO_STATS, Combatant.Team.PARTY)
	overworld_snapshot = {}
	defeated_enemies = {}
	pending_encounter = {}
	fled_from = &""
	grace_until_ms = 0
	hero_changed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_crt"):
		crt_enabled = not crt_enabled
		BattleTransition.set_crt(crt_enabled)
	elif event.is_action_pressed("toggle_debug"):
		debug_overlay = not debug_overlay

func begin_encounter(enemy_id: StringName, enemies: Array[CombatantStats],
		advantage: EncounterRules.Advantage, player_pos: Vector2, player_facing: Vector2) -> void:
	overworld_snapshot = { "position": player_pos, "facing": player_facing }
	pending_encounter = { "enemy_id": enemy_id, "enemies": enemies, "advantage": advantage }

func finish_encounter(result: StringName) -> void:
	## result: &"victory", &"fled" or &"defeat"
	last_battle_result = result
	var id: StringName = pending_encounter.get("enemy_id", &"")
	hero.leave_battle()
	match result:
		&"victory":
			defeated_enemies[id] = true
		&"fled":
			fled_from = id
		&"defeat":
			# Prototype rule: wake up at the start with half HP.
			hero.hp = hero.stats.max_hp / 2
			hero.mp = hero.stats.max_mp
			overworld_snapshot = {}
	grace_until_ms = Time.get_ticks_msec() + 1500
	pending_encounter = {}
	hero_changed.emit()

func in_grace() -> bool:
	return Time.get_ticks_msec() < grace_until_ms

func is_defeated(enemy_id: StringName) -> bool:
	return defeated_enemies.has(enemy_id)

func debug_state() -> String:
	return "hero[%s] defeated=%s pending=%s grace=%s" % [
		hero.debug_state(), defeated_enemies.keys(), pending_encounter.get("enemy_id", "-"), in_grace()]
