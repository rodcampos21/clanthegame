## Builds the test map from an ASCII layout (ForgeSkills "world from data").
##
##   .  grass        ,  flowers      =  dirt path
##   T  tree (solid) o  rock (solid)
##
## Ground is drawn in one _draw() pass; solids become StaticBody2D children
## (collision layer "world") so enemy vision rays and movement respect them.
## Props are y-sorted together with the player and enemies.
class_name OverworldMap
extends Node2D

const TILE := 16
const TEX_GRASS := preload("res://assets/sprites/tile_grass.png")
const TEX_FLOWERS := preload("res://assets/sprites/tile_flowers.png")
const TEX_PATH := preload("res://assets/sprites/tile_path.png")
const TEX_TREE := preload("res://assets/sprites/tree.png")
const TEX_ROCK := preload("res://assets/sprites/rock.png")

const LAYOUT := [
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
	"T......,...........T.........,.........T",
	"T..==========......T...............o...T",
	"T..=........=......T.....,.............T",
	"T..=..o.....=..........................T",
	"T..=........=====================......T",
	"T..=..,.................=.......=..,...T",
	"T..=....TT..............=.......=......T",
	"T..=....TT.......o......=..TTT..=......T",
	"T..=....................=..TTT..=......T",
	"T..======================.......=......T",
	"T.......=.......,...............=...,..T",
	"T.......=.......................=......T",
	"T.,.....=....TTTTT..............=......T",
	"T.......=.......................=......T",
	"T.......=..........o.....,......=......T",
	"T.......==========================.....T",
	"T......,.......=..........T............T",
	"T..............=..........T.......o....T",
	"T....o.........=.......,..T............T",
	"T..............=.......................T",
	"TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT",
]

var size_px := Vector2i.ZERO

func _ready() -> void:
	size_px = Vector2i(LAYOUT[0].length() * TILE, LAYOUT.size() * TILE)
	queue_redraw()

func build_props(props: Node2D) -> void:
	## Called by Overworld once the tree is ready. `props` is the y-sorted Actors node.
	for y in LAYOUT.size():
		var row: String = LAYOUT[y]
		for x in row.length():
			var c := row[x]
			if c == "T":
				props.add_child(_solid(TEX_TREE, Vector2(x * TILE + 8, y * TILE + 15), Vector2(10, 6)))
			elif c == "o":
				props.add_child(_solid(TEX_ROCK, Vector2(x * TILE + 8, y * TILE + 13), Vector2(14, 8)))

func _solid(tex: Texture2D, foot: Vector2, shape_size: Vector2) -> StaticBody2D:
	## A prop whose origin is its *feet* (bottom centre) so y-sorting works.
	var body := StaticBody2D.new()
	body.position = foot
	body.collision_layer = 1
	body.collision_mask = 0
	var spr := Sprite2D.new()
	spr.texture = tex
	spr.centered = false
	spr.offset = Vector2(-tex.get_width() / 2, -tex.get_height())
	body.add_child(spr)
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = shape_size
	col.shape = rect
	col.position = Vector2(0, -shape_size.y / 2)
	body.add_child(col)
	return body

func _draw() -> void:
	for y in LAYOUT.size():
		var row: String = LAYOUT[y]
		for x in row.length():
			var c := row[x]
			var tex: Texture2D = TEX_GRASS
			if c == "=":
				tex = TEX_PATH
			elif c == ",":
				tex = TEX_FLOWERS
			draw_texture(tex, Vector2(x * TILE, y * TILE))
