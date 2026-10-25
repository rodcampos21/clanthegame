## Base stats + known skills for a character or enemy type (pure data).
## Lives in res://data/combatants/*.tres.
class_name CombatantStats
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var max_hp: int = 30
@export var max_mp: int = 10
@export var atk: int = 8
@export var mag: int = 6
@export var def: int = 4
@export var spd: int = 10
@export var skills: Array[SkillData] = []
## Battle sprite (horizontal strip) and frame count.
@export var battle_texture: Texture2D
@export var battle_hframes: int = 1
@export var battle_scale: int = 3
## XP-like reward, used later by the progression system.
@export var reward_points: int = 1
