## Runtime state of one fighter: HP, MP, cooldowns, active statuses, turn timer.
##
## The SAME Combatant object for the hero lives in GameState, so HP/MP/cooldowns
## and persistent statuses survive Overworld <-> Battle transitions untouched.
class_name Combatant
extends RefCounted

signal hp_changed(combatant: Combatant, old_hp: int, new_hp: int)
signal status_added(combatant: Combatant, status: StatusEffectData)
signal status_removed(combatant: Combatant, status: StatusEffectData)
signal died(combatant: Combatant)

enum Team { PARTY, ENEMY }

var _in_turn := false          # between start_of_turn() and end_of_turn()
var stats: CombatantStats
var side: Team = Team.PARTY
var display_name: String = ""
var hp: int = 0
var mp: int = 0
## skill id -> turns remaining
var cooldowns: Dictionary = {}
## Array of { "data": StatusEffectData, "turns": int }
var statuses: Array[Dictionary] = []
## Charge-time-battle clock: the combatant with the lowest value acts next.
var ctb_time: float = 0.0
## Index in its side (used for naming "Slime A", "Slime B").
var slot: int = 0

func _init(p_stats: CombatantStats = null, p_side: Team = Team.PARTY, p_slot: int = 0) -> void:
	if p_stats == null:
		return
	stats = p_stats
	side = p_side
	slot = p_slot
	display_name = p_stats.display_name
	hp = p_stats.max_hp
	mp = p_stats.max_mp

# --- derived stats -------------------------------------------------------

func _mult(prop: StringName) -> float:
	var m := 1.0
	for s in statuses:
		m *= float(s.data.get(prop))
	return m

func get_atk() -> int: return maxi(1, roundi(stats.atk * _mult(&"atk_mult")))
func get_mag() -> int: return maxi(1, roundi(stats.mag * _mult(&"mag_mult")))
func get_def() -> int: return maxi(0, roundi(stats.def * _mult(&"def_mult")))
func get_spd() -> float: return maxf(1.0, stats.spd * _mult(&"spd_mult"))

func is_alive() -> bool:
	return hp > 0

func must_skip_turn() -> bool:
	for s in statuses:
		if s.data.skip_turn:
			return true
	return false

# --- resources -----------------------------------------------------------

func apply_hp_delta(delta: int) -> int:
	var old := hp
	hp = clampi(hp + delta, 0, stats.max_hp)
	if hp != old:
		hp_changed.emit(self, old, hp)
	if old > 0 and hp == 0:
		died.emit(self)
	return hp - old

func can_use(skill: SkillData) -> String:
	## Returns "" if usable, otherwise a short reason (shown in the menu).
	if not is_alive():
		return "KO"
	if skill.kind == SkillData.Kind.PASSIVE:
		return "PASSIVE"
	if mp < skill.mp_cost:
		return "NO MP"
	if int(cooldowns.get(skill.id, 0)) > 0:
		return "CD %d" % int(cooldowns[skill.id])
	return ""

func usable_skills() -> Array[SkillData]:
	var out: Array[SkillData] = []
	for s in stats.skills:
		if can_use(s) == "":
			out.append(s)
	return out

# --- statuses ------------------------------------------------------------

func has_status(id: StringName) -> bool:
	for s in statuses:
		if s.data.id == id:
			return true
	return false

func add_status(data: StatusEffectData, turns: int = -1) -> void:
	if data == null:
		return
	var t := data.duration_turns if turns < 0 else turns
	for s in statuses:
		if s.data.id == data.id:      # refresh instead of stacking
			s.turns = maxi(s.turns, t)
			return
	# A status put on yourself during your own turn (Guard) must not tick down at the end of
	# that same turn, or "until your next turn" would expire before anyone else acts.
	statuses.append({ "data": data, "turns": t, "fresh": _in_turn })
	status_added.emit(self, data)

func remove_status(id: StringName) -> void:
	for i in range(statuses.size() - 1, -1, -1):
		if statuses[i].data.id == id:
			var d: StatusEffectData = statuses[i].data
			statuses.remove_at(i)
			status_removed.emit(self, d)

func start_of_turn() -> Array[Dictionary]:
	## Damage-over-time ticks. Returns presentation events.
	_in_turn = true
	var events: Array[Dictionary] = []
	for s in statuses.duplicate():
		var d: StatusEffectData = s.data
		if d.damage_per_turn != 0 and is_alive():
			var real := -apply_hp_delta(-d.damage_per_turn)
			events.append({ "type": "dot", "target": self, "amount": real, "status": d })
	return events

func end_of_turn() -> void:
	## Count down statuses and cooldowns owned by this combatant.
	_in_turn = false
	for i in range(statuses.size() - 1, -1, -1):
		if statuses[i].get("fresh", false):
			statuses[i].fresh = false
			continue
		statuses[i].turns -= 1
		if statuses[i].turns <= 0:
			var d: StatusEffectData = statuses[i].data
			statuses.remove_at(i)
			status_removed.emit(self, d)
	for k in cooldowns.keys():
		cooldowns[k] = int(cooldowns[k]) - 1
		if cooldowns[k] <= 0:
			cooldowns.erase(k)

func leave_battle() -> void:
	## Called when a battle ends: drop battle-only statuses, keep persistent ones.
	for i in range(statuses.size() - 1, -1, -1):
		if not statuses[i].data.persists_outside_battle:
			statuses.remove_at(i)
	ctb_time = 0.0

func debug_state() -> String:
	var st := []
	for s in statuses:
		st.append("%s(%d)" % [s.data.id, s.turns])
	return "%s hp=%d/%d mp=%d/%d spd=%.1f t=%.2f cd=%s st=%s" % [
		display_name, hp, stats.max_hp, mp, stats.max_mp, get_spd(), ctb_time, cooldowns, st]
