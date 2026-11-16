extends Node

# Development helper: screenshots of the screens the main `shots` tool doesn't
# reach -- the Settings page, loot containers up close, the pause panel, and
# the result screen with a full backpack.
#   godot --path . res://tools/ui_shots.tscn -- <output dir> --test-profile

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://"
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	await _wait(1.0)
	menu.call("_enter")
	await _wait(2.2)
	menu.call("_show_tab", "Settings")
	await _wait(1.4)
	_save(out, "settings")
	menu.queue_free()

	GameManager.loadout["primary"] = "rifle"
	GameManager.in_raid = true
	var raid: Raid = load("res://scenes/raid.tscn").instantiate()
	add_child(raid)
	await _wait(4.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var player := raid.player
	player.max_shield = 1.0e9
	player.shield = 1.0e9
	for node in get_tree().get_nodes_in_group("enemy"):
		node.queue_free()
	# [position, yaw degrees, pitch degrees]
	var views: Array = [
		[Vector3(-30.0, 0.1, -14.0), 20.0, -6.0], [Vector3(-3.0, 0.1, -4.0), -20.0, -8.0],
		[Vector3(30.0, 0.1, 5.0), -110.0, -8.0], [Vector3(-8.0, 0.1, 10.0), 200.0, -8.0],
	]
	for i in views.size():
		player.global_position = views[i][0]
		player.velocity = Vector3.ZERO
		player.set("_yaw", deg_to_rad(views[i][1]))
		player.set("_pitch", deg_to_rad(views[i][2]))
		await _wait(1.0)
		_save(out, "loot_%d" % i)

	var pause := InputEventAction.new()
	pause.action = "pause"
	pause.pressed = true
	raid.hud._unhandled_input(pause)
	await _wait(0.8)
	_save(out, "pause")
	raid.hud._unhandled_input(pause)

	for id: String in ["fusion_cap", "optic_lens", "medkit", "fusion_cap", "optic_lens", "medkit", "fusion_cap", "optic_lens", "medkit", "fusion_cap", "optic_lens", "medkit", "fusion_cap"]:
		GameManager.backpack.append(id)
	GameManager.extract_success(100.0)
	raid._end("extracted")
	await _wait(16.0)
	# Rendering can stall when the window isn't in front, so measure as well.
	for node in raid.hud.find_children("*", "Button", true, false):
		var button := node as Button
		if button.text.begins_with("RETURN"):
			print("RESULT button ", button.get_global_rect(), " in ", get_viewport().get_visible_rect().size)
	for node in raid.hud.find_children("*", "GridContainer", true, false):
		print("RESULT list ", (node as Control).get_global_rect())
	_save(out, "result_full")
	get_tree().quit()

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout

func _save(out: String, name: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
