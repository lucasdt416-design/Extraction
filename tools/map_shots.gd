extends Node

# Development helper: loads a map, reports how long the build and navmesh bake
# took and how big the navmesh is, then saves a top-down plan and a list of
# eye-level views.
#   godot --path . res://tools/map_shots.tscn -- <output dir> <map id> --test-profile [--enemies]

const VIEWS: Dictionary = {
	"aster_city": [
		[Vector3(-4.0, 0.2, 75.0), 0.0, 2.0], [Vector3(-20.0, 0.3, 4.0), 60.0, 10.0], [Vector3(-49.5, 0.2, 20.0), 180.0, 8.0],
		[Vector3(0.0, 5.4, 5.5), 150.0, 4.0], [Vector3(847.0, 0.4, 60.0), -43.8, 2.0], [Vector3(547.0, 0.4, 605.0), -43.8, 2.0],
		[Vector3(-293.0, 0.4, 665.0), -43.8, 2.0], [Vector3(-453.0, 0.4, -130.0), -43.8, 2.0], [Vector3(332.0, 0.4, -105.0), -43.8, 6.0],
	],
	"cairn_divide": [
		[Vector3(-60.0, 0.3, 58.0), -45.0, 2.0], [Vector3(-126.0, 6.0, -96.0), 0.0, -8.0], [Vector3(-82.8, 1.0, 147.0), 55.6, 0.0],
		[Vector3(252.0, 6.0, -146.0), 0.0, -8.0], [Vector3(-158.0, 6.0, 190.0), 0.0, -8.0], [Vector3(70.0, 10.4, -180.0), -90.0, -4.0],
		[Vector3(340.0, 0.3, -262.0), 20.0, 4.0], [Vector3(-285.0, 0.3, 392.0), 10.0, 6.0],
	],
}

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	GameManager.map_id = args[1]
	Level.spawn_at = 0
	GameManager.loadout["primary"] = "rifle"
	var started := Time.get_ticks_msec()
	var raid: Raid = load("res://scenes/raid.tscn").instantiate()
	add_child(raid)
	print("MAP built and baked in %d ms" % (Time.get_ticks_msec() - started))
	var nav := raid.level.navigation_mesh
	if raid.level is CairnLevel:
		print("MAP firs: %d real, %d stand-ins" % [(raid.level as CairnLevel).kit.real_trees, (raid.level as CairnLevel).kit.far_trees])
	print("MAP navmesh polygons %d, containers %d, squads %d" % [nav.get_polygon_count(), raid.level.containers.size(), raid.level.squads.size()])
	await get_tree().create_timer(4.0).timeout
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var player := raid.player
	player.max_shield = 1.0e9
	player.shield = 1.0e9
	if not args.has("--enemies"):
		for node in get_tree().get_nodes_in_group("enemy"):
			node.queue_free()
	print("MAP player on floor %s at %s" % [player.is_on_floor(), player.global_position])
	raid.hud.visible = false
	# Plan view.
	var top := Camera3D.new()
	top.projection = Camera3D.PROJECTION_ORTHOGONAL
	top.size = 240.0
	top.far = 400.0
	top.position = Vector3(0.0, 150.0, 0.0)
	top.rotation.x = -PI * 0.5
	add_child(top)
	top.make_current()
	await get_tree().create_timer(1.5).timeout
	_save(out, "plan")
	top.queue_free()
	player.get_node("Camera3D").make_current() if player.has_node("Camera3D") else null
	for camera in player.find_children("*", "Camera3D", true, false):
		(camera as Camera3D).make_current()
	raid.hud.visible = true
	var views: Array = VIEWS.get(args[1], [])
	for i in views.size():
		player.global_position = views[i][0]
		if raid.level.separate_regions:
			# Heights on these maps are looked up, not written down: y is metres above the ground.
			var at: Vector3 = views[i][0]
			player.global_position.y = raid.level.get("kit").height(at.x, at.z) + at.y
		player.velocity = Vector3.ZERO
		player.set("_yaw", deg_to_rad(views[i][1]))
		player.set("_pitch", deg_to_rad(views[i][2]))
		await get_tree().create_timer(1.2).timeout
		_save(out, "view_%02d" % i)
	# --place <name>: also a view from the middle of that named place, looking north and up.
	var named := args.find("--place")
	if named >= 0:
		for place: Dictionary in raid.level.places:
			if (place["name"] as String).begins_with(args[named + 1]):
				var at: Vector3 = place["position"]
				player.global_position = Vector3(at.x - 16.5, at.y + 0.5, at.z + 4.0)
				player.velocity = Vector3.ZERO
				player.set("_yaw", 0.0)
				player.set("_pitch", deg_to_rad(22.0))
				await get_tree().create_timer(2.0).timeout
				_save(out, "place")
	var rid := get_viewport().get_viewport_rid()
	print("MAP fps %d" % Performance.get_monitor(Performance.TIME_FPS))
	await get_tree().create_timer(1.0).timeout
	print("MAP draws %d  prims %d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	var grass := raid.level.get_node_or_null("Grass") as Node3D
	if grass != null:
		grass.visible = false
		await get_tree().create_timer(1.0).timeout
		print("MAP without grass: fps %d  prims %d" % [Performance.get_monitor(Performance.TIME_FPS), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	get_tree().quit()

func _save(out: String, name: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
