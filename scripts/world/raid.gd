class_name Raid
extends Node3D

# The raid scene's root. It assembles the map, lighting, player, squads, loot
# and HUD, runs the raid clock, and turns "the player died" and "the player
# extracted" into calls on GameManager. It owns no gameplay state of its own
# beyond the clock.

# Set from the map's entry in Catalog.MAPS when the raid starts.
var raid_length: float = 12.0 * 60.0

var level: Level
var player: Player
var hud: Hud
var time_left: float = raid_length
var elapsed: float = 0.0
var over: bool = false
var extract_points: Array[ExtractPoint] = []
var _squads: Array[Squad] = []
var _dev_aircraft: Array[Transport] = []
var _dev_squads: Array[Squad] = []
var drops: Array[SupplyDrop] = []
# When supply drops are called, as shares of the raid gone. Only on the big maps.
const DROPS_AT: Array[float] = [0.2, 0.55]
# Escalation: see _escalate.
# Seconds of fighting near the player (FIGHT_NEAR) before a squad is sent in.
const HEAT_FOR_WAVE: float = 100.0
const FIGHT_NEAR: float = 70.0
const WAVE_MIN_DISTANCE: float = 42.0
const Transport = preload("res://scripts/actors/reinforcement_aircraft.gd")
const MAX_WAVES: int = 2
# With this fraction of the clock left, one wave comes regardless.
const LATE_WAVE_AT: float = 0.3
const WAVES: Array = [["trooper", "trooper"], ["trooper", "bulwark", "lobber", "rusher"], ["overseer", "marksman", "trooper", "rusher"]]
var heat: float = 0.0
var waves_sent: int = 0
var _wave_cooldown: float = 240.0   # nothing comes in during the first four minutes
var _env: Environment
var _sun: DirectionalLight3D

func _ready() -> void:
	add_to_group("raid")
	Squad.all.clear()
	_build_environment()

	var map: Dictionary = Catalog.MAPS[GameManager.map_id]
	raid_length = float(map["minutes"]) * 60.0
	time_left = raid_length
	match map.get("level", ""):
		"aster": level = AsterLevel.new()
		"cairn": level = CairnLevel.new()
		_: level = Level.new()
	level.name = "Level"
	add_child(level)
	level.build()
	level.tune(_env, _sun)
	for mark in level.containers:
		var container := LootContainer.new()
		container.setup(mark["kind"], GameManager.rng, mark.get("supply", ""), level.separate_regions)
		container.position = mark["position"]
		container.rotation.y = mark["yaw"]
		level.add_child(container)
	level.bake()

	for spot in level.extracts:
		var point := ExtractPoint.new()
		point.label = spot["name"]
		point.position = spot["position"]
		if spot.has("drone"):
			point.drone_scene = load(spot["drone"])
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
	Sfx.start_ambience()

	# The navigation map only picks up the freshly baked mesh on the next
	# physics sync, and enemies read it the moment they spawn.
	await get_tree().physics_frame
	await get_tree().physics_frame
	_spawn_squads()

func _spawn_squads() -> void:
	for spec in level.squads:
		_spawn_squad(spec["members"], spec["points"])

func _spawn_squad(members: Array, points: Array, insertion: Dictionary = {}) -> Squad:
	var squad := Squad.new(points, GameManager.rng.randi())
	for i in members.size():
		var enemy := Enemy.new()
		enemy.setup(members[i], squad, i)
		var point: Vector3 = points[i % points.size()]
		enemy.position = point + Vector3(0.6 * i, 0.0, 0.0)
		enemy.rotation.y = GameManager.rng.randf() * TAU
		squad.members.append(enemy)
		add_child(enemy)
		enemy.died.connect(_on_enemy_died)
		if not insertion.is_empty():
			enemy.arrive_from_aircraft(insertion["origin"], point, i * 0.64, insertion["hover"])
	_squads.append(squad)
	return squad

func _physics_process(delta: float) -> void:
	if over:
		return
	if not player.dev_invulnerable:
		elapsed += delta
		time_left -= delta
	for squad in _squads:
		squad.tick(delta)
	_escalate(delta)
	if level.minimap != null and drops.size() < DROPS_AT.size() and elapsed > raid_length * DROPS_AT[drops.size()]:
		_call_drop()
	if time_left <= 0.0:
		# The station locks down. Whatever you were carrying stays here.
		_end("lost")

# --- Supply drops ------------------------------------------------------------
# A crate of good kit comes down somewhere in the open 110-240 m from the
# player: bare ground, not too steep, above the sea. Seeded like the loot.

func _call_drop() -> void:
	var rng := GameManager.rng
	var space := get_world_3d().direct_space_state
	for attempt in 60:
		var angle := rng.randf() * TAU
		var reach := rng.randf_range(110.0, 240.0)
		var at := player.global_position + Vector3(cos(angle), 0.0, sin(angle)) * reach
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(at.x, 700.0, at.z), Vector3(at.x, -400.0, at.z), Layers.WORLD))
		if hit.is_empty() or not (hit["collider"] as Node).has_meta("soil") or (hit["normal"] as Vector3).y < 0.88 or (hit["position"] as Vector3).y < level.drop_floor:
			continue
		var drop := SupplyDrop.new()
		drop.setup(rng)
		drop.position = hit["position"]
		add_child(drop)
		drops.append(drop)
		hud.show_alert("SUPPLY DROP INBOUND")
		return
	# Nowhere fit this time: count it as called so the next one still comes.
	drops.append(null)

# --- Escalation --------------------------------------------------------------
# A raid gets harder the longer and louder it goes. "Heat" builds while a squad
# near the player is in a firefight and bleeds off in the quiet; a long fight
# calls in a fresh squad. A vault alarm calls one too. One arrives in the last
# 30% of the clock so a careful raid still tightens. Aircraft need a clear
# approach corridor and a navigable place to offload the squad.

func _escalate(delta: float) -> void:
	_wave_cooldown = maxf(_wave_cooldown - delta, 0.0)
	var fighting := false
	for squad in _squads:
		if squad.mode == Squad.Mode.COMBAT and not squad.living().is_empty() and squad.center().distance_to(player.global_position) < FIGHT_NEAR:
			fighting = true
	heat = heat + delta if fighting else maxf(heat - delta * 0.35, 0.0)
	if heat >= HEAT_FOR_WAVE or (waves_sent == 0 and time_left < raid_length * LATE_WAVE_AT):
		send_reinforcements(player.global_position)

# Called through the "raid" group by anything that trips an alarm.
func alarm(position: Vector3) -> void:
	send_reinforcements(position)

func send_reinforcements(toward: Vector3) -> bool:
	if over or waves_sent >= mini(MAX_WAVES, WAVES.size()) or _wave_cooldown > 0.0:
		return false
	var helicopter := waves_sent % 2 == 0
	var land_first := GameManager.map_id == "aster_city"
	if GameManager.run_seed % 2 != 0:
		land_first = not land_first
	var lands := helicopter == land_first
	var route := _aircraft_route(toward, lands)
	if route.is_empty() and lands:
		lands = false
		route = _aircraft_route(toward, false)
	if route.is_empty():
		_wave_cooldown = 5.0
		return false
	_deploy_aircraft(route, toward, helicopter, lands, WAVES[waves_sent])
	waves_sent += 1
	heat = 0.0
	_wave_cooldown = 180.0
	return true

func _deploy_aircraft(route: Dictionary, toward: Vector3, helicopter: bool, lands: bool,
		members: Array, dev: bool = false) -> Transport:
	var craft := Transport.new()
	craft.helicopter = helicopter
	craft.lands = lands
	craft.station = route["station"]
	craft.heading = route["heading"]
	craft.player = player
	craft.unloading.connect(func(origin: Vector3) -> void:
		if over:
			return
		var squad := _spawn_squad(members, route["points"], {"origin": origin, "hover": not lands})
		if dev:
			_dev_squads.append(squad)
		squad.respond_to(toward))
	craft.cannon_disabled.connect(func() -> void: hud.show_alert("HELICOPTER CANNON DISABLED"))
	add_child(craft)
	Sfx.play("alert", 2.0, 0.6)
	var aircraft := "ARMED HELICOPTER" if helicopter else "DROPSHIP"
	hud.show_alert("%s INBOUND   /   %s" % [aircraft, "LANDING" if lands else "HOVER DROP"])
	return craft

func dev_spawn_aircraft(helicopter: bool, lands: bool) -> Transport:
	if over:
		return null
	var at := player.global_position
	var forward := -player.global_basis.z
	var space := get_world_3d().direct_space_state
	var nav := get_world_3d().navigation_map
	var route := {}
	for angle: float in [0.0, PI * 0.25, -PI * 0.25, PI * 0.5, -PI * 0.5, PI]:
		var direction := forward.rotated(Vector3.UP, angle)
		for distance: float in [18.0, 26.0, 34.0]:
			var ground := _aircraft_ground(space, at + direction * distance)
			if ground.is_empty():
				continue
			var station: Vector3 = ground["position"]
			if absf(station.y - at.y) > 5.0 or (ground["normal"] as Vector3).y < 0.8:
				continue
			route = _aircraft_corridor(space, nav, station, direction.cross(Vector3.UP), lands)
			if not route.is_empty():
				break
		if not route.is_empty():
			break
	if route.is_empty():
		route = _aircraft_route(at, lands)
	if route.is_empty():
		return null
	var craft := _deploy_aircraft(route, at, helicopter, lands, WAVES[0 if helicopter else 1], true)
	_dev_aircraft.append(craft)
	return craft

func dev_spawn_enemy(kind: String) -> Enemy:
	if over or not Catalog.ENEMIES.has(kind):
		return null
	var at := player.global_position
	var nav := get_world_3d().navigation_map
	for angle: float in [0.0, PI * 0.25, -PI * 0.25, PI * 0.5, -PI * 0.5, PI]:
		var ahead := at - player.global_basis.z.rotated(Vector3.UP, angle) * 7.0
		var point := NavigationServer3D.map_get_closest_point(nav, ahead)
		if point.distance_to(ahead) > 3.0 or point.distance_to(at) < 4.0:
			continue
		var squad := _spawn_squad([kind], [point + Vector3.UP * 0.1])
		_dev_squads.append(squad)
		squad.respond_to(at)
		return squad.members[0]
	return null

func dev_clear_spawns() -> void:
	for craft in _dev_aircraft:
		if is_instance_valid(craft):
			craft.queue_free()
	_dev_aircraft.clear()
	for squad in _dev_squads:
		for enemy in squad.members:
			if is_instance_valid(enemy):
				enemy.queue_free()
		_squads.erase(squad)
		Squad.all.erase(squad)
	_dev_squads.clear()

func dev_go_to_aircraft() -> bool:
	var nav := get_world_3d().navigation_map
	for i in range(_dev_aircraft.size() - 1, -1, -1):
		var craft := _dev_aircraft[i]
		if not is_instance_valid(craft) or craft.is_queued_for_deletion():
			continue
		var across := craft.heading.cross(Vector3.UP)
		for offset: Vector3 in [across * 10.0, -across * 10.0, -craft.heading * 8.0, craft.heading * 8.0]:
			var candidate := craft.station + offset
			var at := NavigationServer3D.map_get_closest_point(nav, candidate)
			var distance := at.distance_to(craft.station)
			if at.distance_to(candidate) < 5.0 and distance >= 5.5:
				player.dev_move_to(at + Vector3.UP * 0.2, craft.station)
				return true
	return false

func _aircraft_route(toward: Vector3, lands: bool) -> Dictionary:
	var candidates := level.reinforce_points.duplicate()
	candidates.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return a.distance_squared_to(toward) < b.distance_squared_to(toward))
	var space := get_world_3d().direct_space_state
	var nav := get_world_3d().navigation_map
	var closest := WAVE_MIN_DISTANCE if level.separate_regions else 25.0
	for point: Vector3 in candidates:
		var distance := point.distance_to(player.global_position)
		if distance < closest or distance > maxf(level.reinforce_range, closest + 60.0):
			continue
		for offset: Vector3 in [Vector3.ZERO, Vector3(7, 0, 0), Vector3(-7, 0, 0), Vector3(0, 0, 7), Vector3(0, 0, -7)]:
			var pad := point + offset
			var ground := _aircraft_ground(space, pad)
			if ground.is_empty():
				continue
			var station: Vector3 = ground["position"]
			if absf(station.y - pad.y) > 4.0 or (ground["normal"] as Vector3).y < 0.8:
				continue
			if station.distance_to(player.global_position) < closest:
				continue
			var approach := station.direction_to(Vector3(player.position.x, station.y, player.position.z)).cross(Vector3.UP)
			if approach.is_zero_approx():
				continue
			var route := _aircraft_corridor(space, nav, station, approach, lands)
			if not route.is_empty():
				return route
	return {}

func _aircraft_corridor(space: PhysicsDirectSpaceState3D, nav: RID, station: Vector3,
		approach: Vector3, lands: bool) -> Dictionary:
	for craft in get_tree().get_nodes_in_group("reinforcement_aircraft"):
		if not craft.is_queued_for_deletion() and station.distance_to(craft.station) < 12.0:
			return {}
	for angle: float in [0.0, PI, PI * 0.5, -PI * 0.5]:
		var heading := approach.rotated(Vector3.UP, angle)
		var across := heading.cross(Vector3.UP)
		var cruise := station + Vector3.UP * Transport.CRUISE_HEIGHT
		if not space.intersect_ray(PhysicsRayQueryParameters3D.create(cruise - heading * 112.0,
				cruise + heading * 112.0, Layers.WORLD)).is_empty():
			continue
		var clear := true
		for offset: Vector3 in [across * 4.0, -across * 4.0, heading * 3.4, -heading * 5.8]:
			var ground := _aircraft_ground(space, station + offset)
			if ground.is_empty():
				clear = false
				break
			var rise := (ground["position"] as Vector3).y - station.y
			if (lands and (absf(rise) > 0.65 or (ground["normal"] as Vector3).y < 0.84)) or rise > 1.2:
				clear = false
				break
		if not clear:
			continue
		var points: Array[Vector3] = []
		for i in 4:
			var at := station - heading * (4.15 + i * 0.42) + across * (1.6 if i % 2 == 0 else -1.6)
			var point := NavigationServer3D.map_get_closest_point(nav, at)
			if point.distance_to(at) > 1.6:
				break
			points.append(point + Vector3.UP * 0.1)
		if points.size() == 4:
			return {"station": station, "heading": heading, "points": points}
	return {}

func _aircraft_ground(space: PhysicsDirectSpaceState3D, at: Vector3) -> Dictionary:
	return space.intersect_ray(PhysicsRayQueryParameters3D.create(at + Vector3.UP * 96.0,
		at - Vector3.UP * 11.0, Layers.WORLD))

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
	hud.begin_ending()
	hud.show_result(GameManager.last_result)

func _end(outcome: String) -> void:
	if over:
		return
	over = true
	GameManager.raid_failed(outcome, elapsed)
	# The world slows and drains of colour; the result waits for the fall.
	Engine.time_scale = 0.22
	var tween := create_tween().set_ignore_time_scale(true).set_parallel(true)
	tween.tween_property(Engine, "time_scale", 1.0, 2.4).set_delay(0.7).set_ease(Tween.EASE_IN)
	tween.tween_property(_env, "adjustment_saturation", 0.12, 1.6)
	tween.tween_property(_env, "adjustment_contrast", 1.25, 1.6)
	tween.tween_property(_env, "adjustment_brightness", 0.96, 1.6)
	tween.chain().tween_callback(func() -> void: hud.show_result(GameManager.last_result))
	hud.begin_ending()

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
	# Lit trim, screens and visors should bloom; daylight should not.
	env.glow_intensity = 0.85
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.1
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
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
	_env = env
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
	sun.rotation = Vector3(deg_to_rad(-23.0), deg_to_rad(-118.0), 0.0)
	sun.light_color = Color(1.0, 0.86, 0.72)
	sun.light_energy = 3.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 110.0
	sun.directional_shadow_blend_splits = true
	sun.light_angular_distance = 0.8
	sun.light_volumetric_fog_energy = 1.7   # shafts through gaps and doorways
	add_child(sun)
	_sun = sun
	apply_quality()
	GameManager.settings_changed.connect(apply_quality)

# Graphics quality, from the settings. High is everything; medium drops the two
# most expensive effects; low keeps only what the look can't do without.
func apply_quality() -> void:
	var quality := int(GameManager.settings["quality"])
	_env.sdfgi_enabled = quality >= 2
	_env.ssr_enabled = quality >= 2
	_env.volumetric_fog_enabled = quality >= 1
	_env.ssao_enabled = quality >= 1
	# Without volumetric fog, plain distance fog keeps the haze.
	_env.fog_enabled = quality < 1
	_env.fog_light_color = Color(0.86, 0.78, 0.72)
	_env.fog_density = 0.0022
	_env.fog_sky_affect = 0.1
	# Without bounce light the shade goes too dark, so lift the ambient.
	_env.ambient_light_energy = 0.9 if quality >= 2 else 1.5
	_sun.directional_shadow_max_distance = 110.0 if quality >= 1 else 60.0
