## A status effect definition (pure data). Lives in res://data/statuses/*.tres.
##
## Battle code never hard-codes "if stunned": it asks the Combatant for the
## combined modifiers of every active StatusEffectData. Adding a new status is a
## data edit, not a code edit (ForgeSkills: "balance numbers live in data").
class_name StatusEffectData
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
## Turns the status lasts. Counted down at the END of the owner's turn.
@export var duration_turns: int = 2
## Stat multipliers while active (1.0 = no change).
@export var atk_mult: float = 1.0
@export var mag_mult: float = 1.0
@export var def_mult: float = 1.0
@export var spd_mult: float = 1.0
## The owner loses its turn while this is active (Stun, Sleep...).
@export var skip_turn: bool = false
## Damage applied at the START of the owner's turn (negative = regen).
@export var damage_per_turn: int = 0
## Survives the battle -> overworld transition (e.g. Poison). Battle-only
## statuses such as "Surprise Boost" are cleared when the battle ends.
@export var persists_outside_battle: bool = false
## Tint used by the battle view and the overworld HUD.
@export var color: Color = Color.WHITE
