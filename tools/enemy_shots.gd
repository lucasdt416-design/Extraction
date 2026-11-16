extends Node3D

# Development helper: every enemy type's body in a row, at rest, alert and
# ducked, then hit, lit like a raid. Saves one picture per pose.
#   godot --path . res://tools/enemy_shots.tscn -- <output dir> --test-profile

const TYPES: Array[String] = ["trooper", "rusher", "bulwark", "marksman", "lobber", "overseer"]

func _ready() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.6, 0.66)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.75, 0.8)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	floor.mesh = plane
	floor.material_override = Mats.ground(Color(0.4, 0.4, 0.42))
	add_child(floor)
	var bodies: Array[Rig] = []
	for i in TYPES.size():
		var body := ModelRig.new()
		body.scale = Vector3.ONE * float(Catalog.ENEMIES[TYPES[i]]["scale"])
		add_child(body)
		body.setup(TYPES[i], 0.6)
		body.position = Vector3((i - 2.5) * 1.6, 0.0, 0.0)
		# Turned three-quarters to the camera, as units usually are.
		body.rotation.y = -PI * 0.5   # side on, to judge where the guns point
		bodies.append(body)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.6, 7.2)
	camera.rotation_degrees = Vector3(-6.0, 0.0, 0.0)
	camera.fov = 60.0
	add_child(camera)
	camera.make_current()
	var marks: Array[MeshInstance3D] = []
	for body in bodies:
		var mark := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.04
		ball.height = 0.08
		mark.mesh = ball
		mark.material_override = Mats.glow(Color(1.0, 0.1, 0.6), 6.0)
		add_child(mark)
		marks.append(mark)
	for pose: Array in [["rest", false, 0.0, false], ["alert", true, 0.0, false], ["aim_up", true, 0.4, false], ["ducked", true, 0.0, true], ["walking", true, 0.0, false]]:
		for t in 60:
			for i in bodies.size():
				bodies[i].animate(1.0 / 60.0, 1.6 if pose[0] == "walking" else 0.0, pose[1], pose[2], pose[3])
				marks[i].global_position = bodies[i].muzzle_position()
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/enemies_%s.png" % [out, pose[0]])
	for body in bodies:
		body.flinch()
	for t in 12:
		for body in bodies:
			body.animate(1.0 / 60.0, 0.0, true, 0.0, false)
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/enemies_hit.png" % out)
	get_tree().quit()
