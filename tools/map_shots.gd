extends Node

# Development helper: loads a map, reports how long the build and navmesh bake
# took and how big the navmesh is, then saves a top-down plan and a list of
# eye-level views.
#   godot --path . res://tools/map_shots.tscn -- <output dir> <map id> --test-profile [--enemies]

const VIEWS: Dictionary = {
	"aster_city": [
		[Vector3(-4.0, 0.2, 75.0), 0.0, 2.0], [Vector3(-30.0, 0.2, 14.0), -70.0, 8.0], [Vector3(-50.0, 0.2, 2.0), -90.0, 6.0],
		[Vector3(0.0, 5.4, 5.5), 180.0, -8.0], [Vector3(-66.0, 5.4, -20.0), 180.0, -10.0], [Vector3(33.0, 0.3, 12.0), 180.0, 4.0],
		[Vector3(30.0, 0.3, 40.0), 200.0, 6.0], [Vector3(42.0, 3.5, 52.0), 20.0, -10.0], [Vector3(-33.0, 0.2, -18.0), 0.0, 0.0],
		[Vector3(-33.0, 0.2, -30.0), 30.0, 0.0], [Vector3(-56.0, 3.0, -30.0), 0.0, 10.0], [Vector3(-60.0, 5.4, -38.5), -90.0, -5.0],
		[Vector3(60.0, 0.2, -46.0), 90.0, 4.0], [Vector3(70.0, 0.2, 0.0), 90.0, 6.0],
	],
}

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	GameManager.map_id = args[1]
	GameManager.loadout["primary"] = "rifle"
	var started := Time.get_ticks_msec()
	var raid: Raid = load("res://scenes/raid.tscn").instantiate()
	add_child(raid)
	print("MAP built and baked in %d ms" % (Time.get_ticks_msec() - started))
	var nav := raid.level.navigation_mesh
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
	top.size = 190.0
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
		player.velocity = Vector3.ZERO
		player.set("_yaw", deg_to_rad(views[i][1]))
		player.set("_pitch", deg_to_rad(views[i][2]))
		await get_tree().create_timer(1.2).timeout
		_save(out, "view_%02d" % i)
	var rid := get_viewport().get_viewport_rid()
	print("MAP draws %d  prims %d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
	get_tree().quit()

func _save(out: String, name: String) -> void:
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
