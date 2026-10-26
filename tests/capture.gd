## Visual check (ForgeSkills gamedev-verification): drives a scripted run and
## saves screenshots. Needs a real renderer:
##   xvfb-run godot --path . --rendering-driver opengl3 res://tests/capture.tscn -- <out_dir>
extends Node

var out_dir := "user://shots"
var n := 0

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	process_mode = Node.PROCESS_MODE_ALWAYS
	await get_tree().process_frame
	# Load the overworld as the *current scene* next to this node, so later
	# scene swaps (done by BattleTransition) free it but not the capture driver.
	var first: Node = load("res://scenes/overworld/overworld.tscn").instantiate()
	get_tree().root.add_child(first)
	get_tree().current_scene = first
	await _frames(40)
	await shot("01_overworld")

	var ow := get_tree().current_scene
	var player: OverworldPlayer = ow.get_node("Actors/Player")
	var slime: OverworldEnemy = ow.get_node("Actors/SlimePath")
	player.input_enabled = false
	slime.patrol_points = PackedVector2Array()
	slime.facing_angle = 0.0
	player.global_position = slime.global_position + Vector2(52, 6)
	player.camera.reset_smoothing()
	await _frames(40)
	await shot("02_suspicious")
	await _frames(40)
	await shot("03_alert_chase")

	# back-strike the red slime -> PLAYER advantage
	slime.process_mode = Node.PROCESS_MODE_DISABLED
	var red: OverworldEnemy = ow.get_node("Actors/RedSlime")
	red.patrol_points = PackedVector2Array()
	red.facing_angle = 0.0
	player.global_position = red.global_position + Vector2(-14, 0)
	player.facing = Vector2.RIGHT
	player.camera.reset_smoothing()
	await _frames(4)
	await shot("04_sneak_up")
	player._strike()
	await _seconds(0.45)
	await shot("05_transition_out")
	await BattleTransition.midpoint
	await _seconds(0.25)
	await shot("06_transition_in")
	await _seconds(1.6)
	await shot("07_battle_menu")
	var battle: BattleManager = get_tree().current_scene
	battle.command_chosen.emit({ "skill": load("res://data/skills/fire.tres") })
	await _frames(5)
	await shot("08_target_select")
	# HD knight: attack swing (wind-up / impact), then Guard pose on his next turn
	battle.command_chosen.emit({ "back": true })
	await _frames(2)
	battle.command_chosen.emit({ "skill": load("res://data/skills/attack.tres") })
	await _frames(2)
	var target: Combatant = battle.enemies.filter(func(e: Combatant) -> bool: return e.is_alive())[0]
	battle.command_chosen.emit({ "target": target })
	await _seconds(0.15)
	await shot("10_attack_run")
	for i in 8:   # run-up -> swing -> hit, one shot every 0.1 s
		await _seconds(0.1)
		await shot("11_attack_%d" % i)
	var waited := 0.0
	while not battle.command_panel.visible and waited < 12.0:
		await _seconds(0.1)
		waited += 0.1
	if battle.command_panel.visible:
		battle.command_chosen.emit({ "skill": load("res://data/skills/guard.tres") })
		await _seconds(0.8)
		await shot("12_guard")
	BattleTransition.set_crt(true)
	await _frames(3)
	await shot("09_crt_on")
	get_tree().quit()

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	# overworld renders on the 320x180 grid (viewport stretch); the battle renders at the
	# 1280x720 output (canvas_items stretch, HD sprites). Save both at 1280x720.
	if img.get_width() < 1280:
		img.resize(img.get_width() * (1280 / img.get_width()), img.get_height() * (1280 / img.get_width()), Image.INTERPOLATE_NEAREST)
	img.save_png("%s/%s.png" % [out_dir, name])
	print("shot ", name, " ", get_tree().current_scene.name)

func _frames(k: int) -> void:
	for i in k:
		await get_tree().process_frame

func _seconds(t: float) -> void:
	await get_tree().create_timer(t, true).timeout
