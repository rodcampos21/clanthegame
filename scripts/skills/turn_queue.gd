## Charge-time turn order (Final Fantasy X style CTB).
##
## Every combatant has a clock (ctb_time). The lowest clock acts; after acting,
## its clock advances by BASE / speed. Faster units therefore act more often,
## and speed buffs/debuffs (statuses) change the order immediately.
class_name TurnQueue
extends RefCounted

const BASE := 100.0

var combatants: Array[Combatant] = []

func setup(all: Array[Combatant], rng: RandomNumberGenerator) -> void:
	combatants = all
	for c in combatants:
		# Initial delay: one "tick" of its own speed, with a small jitter so equal
		# speeds don't always resolve in array order.
		c.ctb_time = BASE / c.get_spd() * rng.randf_range(0.9, 1.1)

func next_actor() -> Combatant:
	var best: Combatant = null
	for c in combatants:
		if c.is_alive() and (best == null or c.ctb_time < best.ctb_time):
			best = c
	return best

func advance(c: Combatant) -> void:
	c.ctb_time += BASE / c.get_spd()

func preview(count: int) -> Array[Combatant]:
	## Simulates the next `count` turns without touching real clocks (for the UI).
	var clocks := {}
	for c in combatants:
		if c.is_alive():
			clocks[c] = c.ctb_time
	var out: Array[Combatant] = []
	for i in count:
		if clocks.is_empty():
			break
		var best: Combatant = null
		for c in clocks:
			if best == null or clocks[c] < clocks[best]:
				best = c
		out.append(best)
		clocks[best] += BASE / best.get_spd()
	return out

func debug_state() -> String:
	var parts := []
	for c in preview(6):
		parts.append(c.display_name)
	return "order: " + " > ".join(parts)
