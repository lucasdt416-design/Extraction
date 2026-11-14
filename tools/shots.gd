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
	for tab: String in ["Deploy", "Trader", "Frame"]:
		menu.set("_tab", tab)
		menu.call("_refresh")
		await get_tree().create_timer(0.4).timeout
		get_viewport().get_texture().get_image().save_png("%s/menu_%s.png" % [out, tab])
	menu.queue_free()
	var raid: Raid = load("res://scenes/raid.tscn").instantiate()
	add_child(raid)
	await get_tree().create_timer(0.3).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var player := raid.player
	if args.has("--fps"):
		# Clean frame-rate samples, with nothing else going on.
		for spot: Vector3 in [Vector3(-39.0, 0.1, 30.0), Vector3(-1.0, 0.1, 1.5), Vector3(-20.0, 0.1, -8.0)]:
			player.global_position = spot
			await get_tree().create_timer(3.0).timeout
			print("FPS at %s: %d (vsync %d)" % [str(spot), Engine.get_frames_per_second(), DisplayServer.window_get_vsync_mode()])
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
		await get_tree().create_timer(2.5 if i == 0 else 1.2).timeout
		get_viewport().get_texture().get_image().save_png("%s/shot_%d.png" % [out, i])
	# Close-ups of two archetypes, for judging the character rigs.
	var n := 0
	for kind: String in ["lobber", "trooper", "marksman"]:
		for node in get_tree().get_nodes_in_group("enemy"):
			var enemy := node as Enemy
			if enemy.kind != kind or enemy.is_dead or enemy.global_position.distance_to(Vector3(2, 0, 4)) > 22.0:
				continue
			enemy.set_physics_process(false)
			var front := enemy.global_position - enemy.global_transform.basis.z * 2.6 + enemy.global_transform.basis.x * 0.9
			player.set_physics_process(true)
			player.global_position = front
			var to := enemy.global_position + Vector3.UP * 1.15 - (front + Vector3.UP * 1.64)
			player.set("_yaw", atan2(-to.x, -to.z))
			player.set("_pitch", atan2(to.y, Vector2(to.x, to.z).length()))
			await get_tree().create_timer(0.5).timeout
			get_viewport().get_texture().get_image().save_png("%s/closeup_%d.png" % [out, n])
			n += 1
			break
	var states := {}
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		var key := "%s:%s%s" % [enemy.kind, Enemy.State.keys()[enemy.state], " dead" if enemy.is_dead else ""]
		states[key] = states.get(key, 0) + 1
	print("ENEMIES ", states)
	print("PERF process %.2fms physics %.2fms viewport %s draws %d prims %d" % [Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, str(get_viewport().size), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	print("NAV polygons ", raid.level.navigation_mesh.get_polygon_count(), " fps ", Engine.get_frames_per_second())
	get_tree().quit()
