## Art of one pixel bar (pure data, data/ui/*.tres). Made by tools/sprite_pipeline/make_hud.py:
## frame, fill and trail are the same size; fill/trail only have pixels inside the channel
## (the dark slot of the frame), which spans columns channel_x .. channel_x + channel_w - 1.
class_name HudBarStyle
extends Resource

@export var frame: Texture2D
@export var fill: Texture2D
## Delayed "damage taken" strip drawn under the fill (optional).
@export var trail: Texture2D
@export var channel_x: int = 0
@export var channel_w: int = 1
