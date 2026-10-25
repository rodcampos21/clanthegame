## The single execution pipeline every skill goes through, for player and AI alike:
##
##   1. validate   (alive, MP, cooldown, at least one valid target)
##   2. pay cost   (MP) and start the cooldown
##   3. per target: accuracy roll -> amount -> apply -> status roll
##   4. return a list of events for the presentation layer to animate
##
## No nodes, no animation: the battle view consumes the events. That keeps the
## rules testable headless (see tests/run_tests.gd).
class_name SkillExecutor
extends RefCounted

const VARIANCE := 0.1   # +-10% damage spread

static func resolve_targets(user: Combatant, skill: SkillData, chosen: Combatant,
		allies: Array, enemies: Array) -> Array[Combatant]:
	var out: Array[Combatant] = []
	match skill.target:
		SkillData.Target.SELF:
			out.append(user)
		SkillData.Target.SINGLE_ALLY:
			out.append(chosen if chosen != null and chosen.is_alive() else user)
		SkillData.Target.SINGLE_ENEMY:
			if chosen != null and chosen.is_alive():
				out.append(chosen)
			else:
				for e in enemies:
					if e.is_alive():
						out.append(e)
						break
		SkillData.Target.ALL_ENEMIES:
			for e in enemies:
				if e.is_alive():
					out.append(e)
	return out

static func execute(user: Combatant, skill: SkillData, targets: Array[Combatant],
		rng: RandomNumberGenerator) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var reason := user.can_use(skill)
	if reason != "":
		events.append({ "type": "fail", "user": user, "skill": skill, "reason": reason })
		return events
	if targets.is_empty():
		events.append({ "type": "fail", "user": user, "skill": skill, "reason": "NO TARGET" })
		return events

	# 2. pay
	user.mp -= skill.mp_cost
	if skill.cooldown_turns > 0:
		# +1 because the user's own end_of_turn() ticks once right after this.
		user.cooldowns[skill.id] = skill.cooldown_turns + 1
	events.append({ "type": "use", "user": user, "skill": skill, "targets": targets })

	# 3. apply
	for t in targets:
		if skill.targets_enemies() and rng.randf() > skill.accuracy:
			events.append({ "type": "miss", "user": user, "target": t, "skill": skill })
			continue
		match skill.kind:
			SkillData.Kind.PHYSICAL, SkillData.Kind.MAGIC:
				var amount := compute_damage(user, t, skill, rng)
				var real := -t.apply_hp_delta(-amount)
				events.append({ "type": "damage", "user": user, "target": t, "amount": real,
					"skill": skill, "ko": not t.is_alive() })
			SkillData.Kind.HEAL:
				var heal := skill.power + user.get_mag() / 2
				var real_h := t.apply_hp_delta(heal)
				events.append({ "type": "heal", "user": user, "target": t, "amount": real_h, "skill": skill })
		if skill.applies_status != null and t.is_alive() and rng.randf() <= skill.status_chance:
			t.add_status(skill.applies_status)
			events.append({ "type": "status", "target": t, "status": skill.applies_status })
	return events

static func compute_damage(user: Combatant, target: Combatant, skill: SkillData,
		rng: RandomNumberGenerator) -> int:
	## Spec (docs/ARCHITECTURE.md, "Combat balance"):
	##   physical = power + ATK - DEF/2
	##   magic    = power + MAG - DEF/4
	var base: float
	if skill.kind == SkillData.Kind.MAGIC:
		base = skill.power + user.get_mag() - target.get_def() * 0.25
	else:
		base = skill.power + user.get_atk() - target.get_def() * 0.5
	var spread := 1.0 + rng.randf_range(-VARIANCE, VARIANCE)
	return maxi(1, roundi(base * spread))
