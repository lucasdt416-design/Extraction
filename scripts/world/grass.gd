class_name Grass
extends Node3D

# Grass on every patch of bare soil inside a rectangle. It finds the soil
# itself: once the level's colliders exist it looks straight down on a one-metre
# grid and plants wherever the first thing under the sky is a body marked
# "soil" (the terrain) -- so roads, pavements, building pads and anything
# standing on the ground stay clear without being listed.
#
# Purely visual. The blades move in the shader (shaders/grass.gdshader); this
# node only tells it where the player, the nearest guards and the last blast are.

const CHUNK: float = 24.0
const NEAR: float = 30.0      # full tufts out to here, a cheap stand-in beyond
const SEEN_TO: float = 80.0
const PUSHERS: int = 8

var area := Rect2(-80.0, -80.0, 160.0, 160.0)
var seed_value: int = 7
var density: float = 13.0     # tufts on a square metre of thick grass
var reach := Vector2(3.0, -4.0)   # how far above and below y = 0 the ground is looked for
var planted: int = 0

var _material: ShaderMaterial
var _blast_force: float = 0.0

func _ready() -> void:
	add_to_group("grass")
	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/grass.gdshader")
	_material.set_shader_parameter("noise_tex", Mats.noise())
	# Low graphics quality goes without.
	GameManager.settings_changed.connect(_apply_quality)
	_apply_quality()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_plant()

func _apply_quality() -> void:
	visible = int(GameManager.settings["quality"]) >= 1

# Called through the "grass" group by anything that goes off.
func blast(at: Vector3, radius: float) -> void:
	_material.set_shader_parameter("blast", Vector4(at.x, at.y, at.z, radius * 1.6))
	_blast_force = 1.0

func _process(delta: float) -> void:
	if _blast_force > 0.0:
		_blast_force = maxf(_blast_force - delta * 0.45, 0.0)
		_material.set_shader_parameter("blast_force", _blast_force * _blast_force)
	var bodies: Array[Vector4] = []
	var centre := Vector3.ZERO
	for node in get_tree().get_nodes_in_group("player"):
		var body := node as Node3D
		centre = body.global_position
		bodies.append(Vector4(centre.x, centre.y, centre.z, 1.1))
	for node in get_tree().get_nodes_in_group("enemy"):
		if bodies.size() >= PUSHERS:
			break
		var at := (node as Node3D).global_position
		if at.distance_squared_to(centre) < 45.0 * 45.0:
			bodies.append(Vector4(at.x, at.y, at.z, 1.0))
	while bodies.size() < PUSHERS:
		bodies.append(Vector4.ZERO)
	_material.set_shader_parameter("pushers", bodies)

func _plant() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var patches := FastNoiseLite.new()
	patches.seed = seed_value
	patches.frequency = 0.045
	var blooms := FastNoiseLite.new()
	blooms.seed = seed_value + 1
	blooms.frequency = 0.11
	var space := get_world_3d().direct_space_state
	var mesh := _tuft(rng, 12, 1.0)
	var far_mesh := _tuft(rng, 4, 2.6)
	var chunks: Dictionary = {}   # Vector2i -> Array of [Transform3D, Color]
	var x := area.position.x + 0.5
	while x < area.end.x:
		var z := area.position.y + 0.5
		while z < area.end.y:
			var cover := patches.get_noise_2d(x, z) * 0.5 + 0.5
			if cover > 0.34:
				var query := PhysicsRayQueryParameters3D.create(Vector3(x, reach.x, z), Vector3(x, reach.y, z), Layers.WORLD)
				var hit := space.intersect_ray(query)
				if not hit.is_empty() and (hit["collider"] as Node).has_meta("soil"):
					var ground: Vector3 = hit["position"]
					var slope: Vector3 = hit["normal"]
					var key := Vector2i(floori(x / CHUNK), floori(z / CHUNK))
					if not chunks.has(key):
						chunks[key] = []
					var thick := clampf((cover - 0.34) * 5.0, 0.25, 1.0)
					var glowing := blooms.get_noise_2d(x, z) > 0.42
					for i in int(round(density * thick)):
						var ox := rng.randf_range(-0.5, 0.5)
						var oz := rng.randf_range(-0.5, 0.5)
						# Follow the slope the ray found, so tufts neither float nor sink.
						var y := ground.y - (slope.x * ox + slope.z * oz) / maxf(slope.y, 0.2)
						var grow := rng.randf_range(0.7, 1.25) * (0.75 + thick * 0.45)
						var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(grow, grow * rng.randf_range(0.8, 1.3), grow))
						var custom := Color(rng.randf(), 1.0 if glowing and rng.randf() < 0.3 else 0.0, 0.0, 0.0)
						(chunks[key] as Array).append([Transform3D(basis, Vector3(x + ox, y - 0.02, z + oz)), custom])
			z += 1.0
		x += 1.0
	for key: Vector2i in chunks:
		var tufts: Array = chunks[key]
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.use_custom_data = true
		multi.mesh = mesh
		multi.instance_count = tufts.size()
		for i in tufts.size():
			multi.set_instance_transform(i, tufts[i][0])
			multi.set_instance_custom_data(i, tufts[i][1])
		# The same tufts, drawn close up in full and from further off as a few
		# broad blades each.
		var far := MultiMesh.new()
		far.transform_format = MultiMesh.TRANSFORM_3D
		far.use_custom_data = true
		far.mesh = far_mesh
		far.instance_count = tufts.size()
		for i in tufts.size():
			far.set_instance_transform(i, tufts[i][0])
			far.set_instance_custom_data(i, tufts[i][1])
		for pair: Array in [[multi, 0.0, NEAR], [far, NEAR, SEEN_TO]]:
			var batch := MultiMeshInstance3D.new()
			batch.multimesh = pair[0]
			batch.material_override = _material
			batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			batch.visibility_range_begin = pair[1]
			batch.visibility_range_end = pair[2]
			# Blades move in the shader: give the culling box room for it.
			batch.extra_cull_margin = 1.5
			add_child(batch)
		planted += tufts.size()

# One tuft: a handful of tapering blades leaning out from a point. UV.y runs
# from the root (0) to the tip (1); the shader bends by it.
func _tuft(rng: RandomNumberGenerator, blades: int, broad: float) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for blade in blades:
		var yaw := blade * TAU / blades + rng.randf_range(-0.5, 0.5)
		var out := Vector3(cos(yaw), 0.0, sin(yaw))
		# Blades face every way, so a tuft has body from any side.
		var turn := rng.randf() * TAU
		var side := Vector3(cos(turn), 0.0, sin(turn))
		var tall := rng.randf_range(0.2, 0.52)
		var lean := rng.randf_range(0.04, 0.24)
		var half := rng.randf_range(0.012, 0.021) * broad
		var foot := out * rng.randf_range(0.0, 0.16)
		var shade := rng.randf()
		var steps := 3 if broad < 1.5 else 2
		var rings: Array = []
		for step in steps + 1:
			var t := float(step) / steps
			var mid := foot + out * lean * t * t + Vector3.UP * tall * t
			var w := half * (1.0 - t * 0.9)
			rings.append([mid - side * w, mid + side * w, t])
		for step in steps:
			var a: Array = rings[step]
			var b: Array = rings[step + 1]
			for corner: Array in [[a[0], a[2]], [b[0], b[2]], [b[1], b[2]], [a[0], a[2]], [b[1], b[2]], [a[1], a[2]]]:
				tool.set_uv(Vector2(shade, corner[1]))
				tool.set_normal(Vector3.UP)
				tool.add_vertex(corner[0])
	return tool.commit()
