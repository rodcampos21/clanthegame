## Overworld root: builds the map, restores the hero after a battle, runs the HUD.
extends Node2D

@onready var map: OverworldMap = $Map
@onready var actors: Node2D = $Actors
@onready var player: OverworldPlayer = $Actors/Player
@onready var hp_label: Label = $HUD/Status/Margin/VBox/HP
@onready var status_label: Label = $HUD/Status/Margin/VBox/Statuses
@onready var hint_label: Label = $HUD/Hint
@onready var debug_label: Label = $HUD/Debug
@onready var toast_label: Label = $HUD/Toast

func _ready() -> void:
	map.build_props(actors)
	player.setup_camera(map.size_px)
	if not GameState.overworld_snapshot.is_empty():
		player.restore(GameState.overworld_snapshot)
	player.camera.reset_smoothing()
	_show_result_toast()
	GameState.hero_changed.connect(_refresh_hud)
	_refresh_hud()

func _process(_delta: float) -> void:
	debug_label.visible = GameState.debug_overlay
	if GameState.debug_overlay:
		var lines := [player.debug_state()]
		for n in get_tree().get_nodes_in_group("overworld_enemies"):
			lines.append(n.debug_state())
		lines.append(GameState.debug_state())
		debug_label.text = "\n".join(lines)

func _refresh_hud() -> void:
	var h := GameState.hero
	hp_label.text = "HP %d/%d  MP %d/%d" % [h.hp, h.stats.max_hp, h.mp, h.stats.max_mp]
	var names := []
	for s in h.statuses:
		names.append(s.data.display_name)
	status_label.text = " ".join(names)
	status_label.visible = not names.is_empty()

func _show_result_toast() -> void:
	var msg := ""
	match GameState.last_battle_result:
		&"victory": msg = "VICTORY!"
		&"fled": msg = "GOT AWAY..."
		&"defeat": msg = "YOU WAKE UP AT THE START."
	GameState.last_battle_result = &""
	toast_label.text = msg
	toast_label.visible = msg != ""
	if msg != "":
		var tw := create_tween()
		tw.tween_interval(1.4)
		tw.tween_callback(func() -> void: toast_label.visible = false)
	if get_tree().get_nodes_in_group("overworld_enemies").filter(
			func(e: Node) -> bool: return not GameState.is_defeated(e.enemy_id)).is_empty():
		toast_label.text = "AREA CLEAR! ALL SLIMES DEFEATED."
		toast_label.visible = true
