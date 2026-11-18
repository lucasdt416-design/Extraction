extends Node

# Development helper: every gun in first person, at the hip, aiming and
# half-way through a reload, on Relay Station. One picture each.
#   godot --path . res://tools/view_shots.tscn --resolution 1600x900 -- <output dir> --test-profile

class Bot extends PlayerInputSource:
	var aim := false
	func poll() -> InputFrame:
		var frame := InputFrame.new()
		frame.aim = aim
		return frame

func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	GameManager.map_id = "relay_07"
	GameManager.loadout["primary"] = "rifle"
	var raid: Raid = load("res://scenes/raid.tscn").instantiate()
	add_child(raid)
	# A stray key while the window is in the background must not pause the shots.
	raid.hud.set_process_unhandled_input(false)
	await get_tree().create_timer(4.0).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	raid.hud._resume()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for node in get_tree().get_nodes_in_group("enemy"):
		node.queue_free()
	var player := raid.player
	player.max_shield = 1.0e9
	player.shield = 1.0e9
	var bot := Bot.new()
	player.add_child(bot)
	player.input_source = bot
	player.global_position = Vector3(-12.0, 0.1, 8.0)
	player.set("_yaw", deg_to_rad(-75.0))
	for id: String in ["rifle", "smg", "dmr", "shotgun", "sidearm", "arc"]:
		player.add_gun(id)
		bot.aim = false
		await get_tree().create_timer(1.2).timeout
		get_viewport().get_texture().get_image().save_png("%s/%s_hip.png" % [out, id])
		bot.aim = true
		await get_tree().create_timer(0.8).timeout
		get_viewport().get_texture().get_image().save_png("%s/%s_aim.png" % [out, id])
		bot.aim = false
		await get_tree().create_timer(0.4).timeout
		player.gun().mag = 1
		player.gun().reserve = 999
		player.gun().start_reload()
		await get_tree().create_timer(float(player.gun().def["reload"]) * 0.45).timeout
		get_viewport().get_texture().get_image().save_png("%s/%s_reload.png" % [out, id])
		await get_tree().create_timer(float(player.gun().def["reload"]) * 0.7).timeout
	get_tree().quit()
