## A skill/ability definition (pure data). Lives in res://data/skills/*.tres.
##
## Execution is NOT here: see SkillExecutor, which runs every skill through the
## same pipeline (validate -> pay cost -> resolve targets -> apply -> cooldown).
class_name SkillData
extends Resource

enum Kind { PHYSICAL, MAGIC, HEAL, STATUS_ONLY, PASSIVE }
enum Target { SINGLE_ENEMY, ALL_ENEMIES, SELF, SINGLE_ALLY }

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var kind: Kind = Kind.PHYSICAL
@export var target: Target = Target.SINGLE_ENEMY
@export var element: StringName = &"none"

@export_group("Presentation")
## HD battle animation the user plays (attack, skill...). Empty = attack for offensive skills.
@export var user_anim: StringName = &""
## Melee: the user runs up to the target (advance), performs, and runs back afterwards.
@export var approach: bool = false

@export_group("Numbers")
@export var power: int = 10
@export var mp_cost: int = 0
## Turns before the skill can be used again (0 = every turn).
@export var cooldown_turns: int = 0
@export_range(0.0, 1.0) var accuracy: float = 0.95

@export_group("Status")
## Optional status applied to every target that is hit.
@export var applies_status: StatusEffectData
@export_range(0.0, 1.0) var status_chance: float = 1.0

@export_group("Skill tree")
## Skills that must be learned before this one unlocks (simple skill-tree edge).
@export var requires: Array[StringName] = []
## Learn cost in skill points. 0 = known from the start.
@export var unlock_cost: int = 0
## For PASSIVE skills: a permanent status applied when the battle starts.
@export var passive_status: StatusEffectData

func is_offensive() -> bool:
	return kind == Kind.PHYSICAL or kind == Kind.MAGIC \
		or (kind == Kind.STATUS_ONLY and (target == Target.SINGLE_ENEMY or target == Target.ALL_ENEMIES))

func targets_enemies() -> bool:
	return target == Target.SINGLE_ENEMY or target == Target.ALL_ENEMIES
