extends Node

# Development helper, not part of the game: loads the raid, moves the camera to
# a list of viewpoints and saves a screenshot of each, then quits.
#   godot --path . res://tools/shots.tscn -- <output dir>

const VIEWS: Array = [
	# [position, yaw degrees, pitch degrees]
	[Vector3(-39.0, 0.1, 30.0), -50.0, 2.0],
	[Vector3(-12.0, 0.1, 8.0), -75.0, 0.0],
	[Vector3(-1.0, 0.1, 1.5), -60.0, -2.0],
	[Vector3(-20.0, 0.1, -8.0), 90.0, 4.0],
	[Vector3(-4.0, 0.1, -17.0), 20.0, 0.0],
	[Vector3(30.0, 0.1, -22.0), -60.0, 0.0],
	[Vector3(0.0, 30.0, 40.0), 0.0, -42.0],
]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "user://"
	var menu: Control = load("res://scenes/menu.tscn").instantiate()
	add_child(menu)
	await get_tree().create_timer(1.2).timeout
	get_viewport().get_texture().get_image().save_png("%s/menu_Title.png" % out)
	menu.call("_enter")
	await get_tree().create_timer(2.2).timeout
	for tab: String in ["Play", "Armoury", "Loadout", "Trader", "Frame", "Settings"]:
		menu.call("_show_tab", tab)
		await get_tree().create_timer(1.4).timeout
		get_viewport().get_texture().get_image().save_png("%s/menu_%s.png" % [out, tab])
	menu.queue_free()
	GameManager.loadout["primary"] = "rifle"
	GameManager.set_setting("quality", 0.0 if args.has("--low") else 2.0)
	GameManager.loadout["secondary"] = "dmr" if args.has("--dmr") else ""
	var raid: Raid = load("res://scenes/raid.tscn").instantiate()
	add_child(raid)
	await get_tree().create_timer(1.3).timeout
	get_viewport().get_texture().get_image().save_png("%s/intro.png" % out)
	await get_tree().create_timer(2.6).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var player := raid.player
	# Unkillable until the death shot, so earlier views can't end the raid.
	player.max_shield = 1.0e9
	player.shield = 1.0e9
	if args.has("--no-enemies"):
		for node in get_tree().get_nodes_in_group("enemy"):
			node.queue_free()
	if args.has("--no-body"):
		player.get("_body").visible = false
		player.get("_shadow_body").visible = false
	if args.has("--no-probes"):
		for node in raid.level.find_children("*", "ReflectionProbe", true, false):
			node.queue_free()
	if args.has("--no-sdfgi"):
		get_viewport().world_3d.environment.sdfgi_enabled = false
	if args.has("--fps"):
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		# Clean frame-rate samples, with nothing else going on.
		for spot: Vector3 in [Vector3(-39.0, 0.1, 30.0), Vector3(-1.0, 0.1, 1.5), Vector3(-20.0, 0.1, -8.0)]:
			player.global_position = spot
			await get_tree().create_timer(3.0).timeout
			# Measured render cost, which unlike the frame rate isn't affected by
			# macOS throttling a window that isn't in front.
			var rid := get_viewport().get_viewport_rid()
			print("AT %s: cpu %.1fms  gpu %.1fms  draws %d  prims %d  script %.1fms  physics %.1fms" % [str(spot),
				RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu(),
				RenderingServer.viewport_get_measured_render_time_gpu(rid),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])
		get_tree().quit()
		return
	for i in VIEWS.size():
		var view: Array = VIEWS[i]
		player.set_physics_process(i < VIEWS.size() - 1)
		player.global_position = view[0]
		player.velocity = Vector3.ZERO
		player.set("_yaw", deg_to_rad(view[1]))
		player.rotation.y = deg_to_rad(view[1])
		player.set("_pitch", deg_to_rad(view[2]))
		player.health = player.max_health
		player.is_dead = false
		if i == 1:
			GameManager.add_to_backpack("fusion_cap")
			GameManager.add_to_backpack("optic_lens")
			player.hit_confirmed.emit(3)
		await get_tree().create_timer(2.5 if i == 0 else 1.2).timeout
		get_viewport().get_texture().get_image().save_png("%s/shot_%d.png" % [out, i])
	# Looking down at Kestrel's own body, then at its shadow on the ground.
	player.set_physics_process(true)
	player.global_position = Vector3(-1.0, 0.1, 9.0)
	player.set("_yaw", deg_to_rad(40.0))
	player.set("_pitch", deg_to_rad(-62.0))
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png("%s/body_down.png" % out)
	# Face the way the sunlight travels, so our own shadow is in front of us.
	var sun: DirectionalLight3D = raid.find_children("*", "DirectionalLight3D", false, false)[0]
	var travel := -sun.global_transform.basis.z
	player.global_position = Vector3(-14.0, 0.1, 17.0)
	player.set("_pitch", deg_to_rad(-35.0))
	player.set("_yaw", atan2(-travel.x, -travel.z))
	await get_tree().create_timer(0.4).timeout
	get_viewport().get_texture().get_image().save_png("%s/body_shadow.png" % out)
	# Close-ups of two archetypes, for judging the character rigs.
	var n := 0
	for kind: String in ["trooper", "bulwark", "overseer", "rusher"]:
		for node in get_tree().get_nodes_in_group("enemy"):
			var enemy := node as Enemy
			if enemy.kind != kind or enemy.is_dead :
				continue
			enemy.set_physics_process(false)
			enemy.global_position = Vector3(-8.0 + n * 4.0, 0.1, 17.5)
			enemy.rotation.y = 0.5
			var front := enemy.global_position - enemy.global_transform.basis.z * 2.4 + enemy.global_transform.basis.x * 0.8
			player.set_physics_process(true)
			player.global_position = front
			var to := enemy.global_position + Vector3.UP * 1.15 - (front + Vector3.UP * 1.64)
			player.set("_yaw", atan2(-to.x, -to.z))
			player.set("_pitch", atan2(to.y, Vector2(to.x, to.z).length()))
			await get_tree().create_timer(0.5).timeout
			get_viewport().get_texture().get_image().save_png("%s/closeup_%d.png" % [out, n])
			n += 1
			break
	# The death view.
	player.global_position = Vector3(-39.0, 0.1, 30.0)
	player.set("_yaw", deg_to_rad(-50.0))
	await get_tree().create_timer(0.4).timeout
	GameManager.in_raid = true
	GameManager.backpack.assign(["fusion_cap", "data_shard", "medkit"])
	player.shield = 0.0
	player.take_damage(9999.0, null)
	for stamp: Array in [[1.0, "death_a"], [1.3, "death_b"], [1.4, "death_c"], [4.0, "death"]]:
		await get_tree().create_timer(stamp[0], true, false, true).timeout
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, stamp[1]])
	var states := {}
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		var key := "%s:%s%s" % [enemy.kind, Enemy.State.keys()[enemy.state], " dead" if enemy.is_dead else ""]
		states[key] = states.get(key, 0) + 1
	print("ENEMIES ", states)
	print("PERF process %.2fms physics %.2fms viewport %s draws %d prims %d" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, str(get_viewport().size), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	print("NAV polygons ", raid.level.navigation_mesh.get_polygon_count(), " fps ", Engine.get_frames_per_second())
	get_tree().quit()
