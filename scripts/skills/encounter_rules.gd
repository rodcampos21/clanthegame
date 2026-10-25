## Turns an overworld collision into a battle opening.
##
## SPEC (ForgeSkills gameplay-systems, step 1)
##   PURPOSE  : reward sneaking up on enemies, punish being caught from behind
##   INPUTS   : who struck, enemy awareness state, both facings and positions
##   STATE    : Advantage enum carried in GameState.pending_encounter
##   RULES    : player strike on an UNAWARE enemy from BEHIND  -> PLAYER
##              enemy CHASING touches the player from BEHIND   -> ENEMY
##              anything else (frontal, aware, walking into)    -> NEUTRAL
##   FEEDBACK : banner text + colour in battle, statuses on the turn order bar
##
## "Behind" = the other body sits in the rear half-plane of the facing vector,
## narrowed by BEHIND_DOT so a side-on hit at 90 degrees is not a back attack.
class_name EncounterRules
extends RefCounted

enum Advantage { NEUTRAL, PLAYER, ENEMY }

const BEHIND_DOT := -0.25    # cos(~105 deg): must be clearly behind

const STATUS_SURPRISE := preload("res://data/statuses/surprise_boost.tres")
const STATUS_STUNNED := preload("res://data/statuses/stunned.tres")
const STATUS_OFF_GUARD := preload("res://data/statuses/off_guard.tres")

static func is_behind(facing: Vector2, self_pos: Vector2, other_pos: Vector2) -> bool:
	## True when `other_pos` is behind something at `self_pos` looking along `facing`.
	var to_other := (other_pos - self_pos).normalized()
	if to_other == Vector2.ZERO or facing == Vector2.ZERO:
		return false
	return facing.normalized().dot(to_other) < BEHIND_DOT

static func resolve_player_strike(enemy_is_aware: bool, enemy_facing: Vector2,
		enemy_pos: Vector2, player_pos: Vector2) -> Advantage:
	if not enemy_is_aware and is_behind(enemy_facing, enemy_pos, player_pos):
		return Advantage.PLAYER
	return Advantage.NEUTRAL

static func resolve_enemy_contact(enemy_is_chasing: bool, player_facing: Vector2,
		player_pos: Vector2, enemy_pos: Vector2) -> Advantage:
	if enemy_is_chasing and is_behind(player_facing, player_pos, enemy_pos):
		return Advantage.ENEMY
	return Advantage.NEUTRAL

static func apply_opening(advantage: Advantage, party: Array[Combatant],
		enemies: Array[Combatant]) -> void:
	## Called by BattleManager AFTER TurnQueue.setup(): bends the clocks and
	## applies the opening statuses through the normal status system.
	match advantage:
		Advantage.PLAYER:
			for p in party:
				p.ctb_time = 0.0                       # party acts first
				p.add_status(STATUS_SURPRISE)
			for e in enemies:
				e.add_status(STATUS_STUNNED, 1)        # each enemy loses its first turn
		Advantage.ENEMY:
			for e in enemies:
				e.ctb_time = 0.0
			for p in party:
				p.add_status(STATUS_OFF_GUARD)         # weaker + slower for 2 turns
		_:
			pass

static func label(advantage: Advantage) -> String:
	match advantage:
		Advantage.PLAYER: return "SURPRISE ATTACK!"
		Advantage.ENEMY: return "AMBUSHED!"
	return "BATTLE!"
