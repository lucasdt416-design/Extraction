class_name Raid
extends Node3D

# The raid scene's root. It assembles the map, lighting, player, squads, loot
# and HUD, runs the raid clock, and turns "the player died" and "the player
# extracted" into calls on GameManager. It owns no gameplay state of its own
# beyond the clock.

const RAID_LENGTH: float = 12.0 * 60.0

var level: Level
var player: Player
var hud: Hud
var time_left: float = RAID_LENGTH
var elapsed: float = 0.0
var over: bool = false
var extract_points: Array[ExtractPoint] = []
var _squads: Array[Squad] = []

func _ready() -> void:
	Squad.all.clear()
	_build_environment()

	level = Level.new()
	level.name = "Level"
	add_child(level)
	level.build()
	for mark in level.containers:
		var container := LootContainer.new()
		container.setup(mark["kind"], GameManager.rng)
		container.position = mark["position"]
		container.rotation.y = mark["yaw"]
		level.add_child(container)
	level.bake()

	for spot in level.extracts:
		var point := ExtractPoint.new()
		point.label = spot["name"]
		point.position = spot["position"]
		add_child(point)
		point.extracted.connect(_on_extracted)
		extract_points.append(point)

	player = Player.new()
	player.position = level.player_spawn
	player.rotation.y = level.player_yaw
	add_child(player)
	player.died.connect(_on_player_died)

	_build_lens_and_dust()
	hud = Hud.new()
	add_child(hud)
	hud.bind(self)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# The navigation map only picks up the freshly baked mesh on the next
	# physics sync, and enemies read it the moment they spawn.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_spawn_squads()

func _spawn_squads() -> void:
	for spec in level.squads:
		var squad := Squad.new(spec["points"], GameManager.rng.randi())
		var members: Array = spec["members"]
		for i in members.size():
			var enemy := Enemy.new()
			enemy.setup(members[i], squad, i)
			var point: Vector3 = spec["points"][i % spec["points"].size()]
			enemy.position = point + Vector3(0.6 * i, 0.0, 0.0)
			enemy.rotation.y = GameManager.rng.randf() * TAU
			squad.members.append(enemy)
			add_child(enemy)
			enemy.died.connect(_on_enemy_died)
		_squads.append(squad)

func _physics_process(delta: float) -> void:
	if over:
		return
	elapsed += delta
	time_left -= delta
	for squad in _squads:
		squad.tick(delta)
	if time_left <= 0.0:
		# The station locks down. Whatever you were carrying stays here.
		_end("lost")

func _on_enemy_died(enemy: Enemy, killer: Node) -> void:
	if killer is Player:
		GameManager.register_kill()
	var rng := GameManager.rng
	var at := enemy.global_position + Vector3(rng.randf_range(-0.5, 0.5), 0.0, rng.randf_range(-0.5, 0.5))
	if rng.randf() < float(enemy.arch["loot"]):
		Pickup.drop(self, Catalog.roll("elite" if enemy.arch.get("commander", false) else "body", rng), at)
	if rng.randf() < 0.55:
		Pickup.drop(self, Pickup.AMMO, at + Vector3(0.5, 0.0, 0.3))

func _on_player_died(_killer: Node) -> void:
	_end("died")

func _on_extracted(_who: Player) -> void:
	if over:
		return
	over = true
	Sfx.play("extract")
	Fx.burst(self, player.global_position + Vector3.UP, 8.0, Level.TEAL.lightened(0.3), 0.8)
	GameManager.extract_success(elapsed)
	hud.show_result(GameManager.last_result)

func _end(outcome: String) -> void:
	if over:
		return
	over = true
	GameManager.raid_failed(outcome, elapsed)
	hud.show_result(GameManager.last_result)

func _build_lens_and_dust() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 0
	var lens := ColorRect.new()
	lens.set_anchors_preset(Control.PRESET_FULL_RECT)
	lens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/post.gdshader")
	lens.material = material
	layer.add_child(lens)
	add_child(layer)

	# Dust hanging in the air around the player; it catches the sun and the lamps.
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.03)
	var mote := StandardMaterial3D.new()
	mote.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mote.albedo_color = Color(1.0, 0.93, 0.8, 0.4)
	quad.material = mote
	var dust := CPUParticles3D.new()
	dust.mesh = quad
	dust.amount = 320
	dust.lifetime = 10.0
	dust.preprocess = 10.0
	dust.local_coords = false
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(12.0, 3.5, 12.0)
	dust.direction = Vector3(1.0, 0.1, 0.3)
	dust.spread = 50.0
	dust.gravity = Vector3.ZERO
	dust.initial_velocity_min = 0.05
	dust.initial_velocity_max = 0.3
	dust.scale_amount_min = 0.4
	dust.scale_amount_max = 1.4
	dust.position.y = 2.5
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	player.add_child(dust)

# Late afternoon on a dusty plateau: a low warm sun, long shadows, cool shade,
# haze in the distance. Interiors get their own lamps from the level.
func _build_environment() -> void:
	var sky_shader := ShaderMaterial.new()
	sky_shader.shader = load("res://shaders/sky.gdshader")
	sky_shader.set_shader_parameter("noise_tex", Mats.noise())
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.17, 0.33, 0.60)
	sky_material.sky_horizon_color = Color(0.86, 0.74, 0.66)
	sky_material.sky_curve = 0.14
	sky_material.ground_bottom_color = Color(0.16, 0.13, 0.13)
	sky_material.ground_horizon_color = Color(0.70, 0.60, 0.54)
	sky_material.sun_angle_max = 9.0
	sky_material.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_shader
	sky.radiance_size = Sky.RADIANCE_SIZE_256

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.05
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.1
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.2
	env.sdfgi_enabled = true
	env.sdfgi_cascades = 4
	env.sdfgi_max_distance = 110.0
	env.sdfgi_energy = 1.1
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssr_fade_in = 0.2
	env.ssr_fade_out = 2.5
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.0028
	env.volumetric_fog_albedo = Color(0.90, 0.88, 0.86)
	env.volumetric_fog_length = 140.0
	env.volumetric_fog_ambient_inject = 0.4
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.1
	env.adjustment_saturation = 1.08
	var world := WorldEnvironment.new()
	world.environment = env
	# Eyes adjust: stepping indoors opens up, stepping back out is briefly bright.
	var exposure := CameraAttributesPractical.new()
	exposure.auto_exposure_enabled = true
	exposure.auto_exposure_scale = 0.42
	exposure.auto_exposure_speed = 1.2
	exposure.auto_exposure_min_sensitivity = 90.0
	exposure.auto_exposure_max_sensitivity = 420.0
	world.camera_attributes = exposure
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-27.0), deg_to_rad(-118.0), 0.0)
	sun.light_color = Color(1.0, 0.84, 0.68)
	sun.light_energy = 3.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	sun.directional_shadow_blend_splits = true
	sun.light_angular_distance = 0.8
	sun.light_volumetric_fog_energy = 1.4
	add_child(sun)
