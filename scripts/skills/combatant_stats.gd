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
## Optional HD battle sprite (SpriteFrames with idle/attack/hurt/death/defend/advance...).
## When set, it replaces battle_texture. HD art is drawn for the 1280x720 output (4x the
## 320x180 grid), so battle_frames_scale = 0.25 shows 1 art pixel = 1 screen pixel.
@export var battle_frames: SpriteFrames
## Point between the feet on the ground, in pixels from each cell's top-left.
@export var battle_frames_origin: Vector2 = Vector2(96, 222)
@export var battle_frames_scale: float = 0.25
## Colours of the HD art (1 px tall strip): added to the CRT palette in battle.
@export var battle_frames_palette: Texture2D
## XP-like reward, used later by the progression system.
@export var reward_points: int = 1
