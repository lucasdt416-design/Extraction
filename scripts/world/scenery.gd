class_name Scenery
extends Node3D

# The wild ground between a big map's colonies: trees, shrubs, flowers, logs
# and rock formations from the Colony Biomes kit (assets/scenery/colony-biomes,
# made outside this repo; see its README).
#
# Like Grass it plants itself: once the level's colliders exist it looks down
# on a jittered grid and puts something wherever the first thing it meets is
# bare terrain (a body with the "soil" meta), away from the places listed in
# `avoid` and `keep_clear`. What grows where is the level's call: `biome` is
# given (x, z, ground height) and returns the names it may use there, or an
# empty array for nothing. Trees, rocks and logs are solid; plants are not.
#
# Drawn as MultiMeshes per kind per map square, each kind only out to a
# distance that suits its size.

const ROOT: String = "res://assets/scenery/colony-biomes/"
const CELL: float = 128.0
# How often each kind of thing is picked, against the others allowed there.
const WEIGHT: Dictionary = {"tree": 1.0, "rock": 1.3, "understory": 2.2, "ground_cover": 3.0, "debris": 0.6}
# How far away each kind is still drawn.
const REACH: Dictionary = {"tree": 260.0, "rock": 320.0, "understory": 110.0, "ground_cover": 75.0, "debris": 140.0}
# Rocks whose layers should show strongly in the stone shader.
const STRATA: Array[String] = ["sc_shale_ledge", "sc_rust_spires", "sc_salt_shelves"]

var area := Rect2(-500.0, -500.0, 1000.0, 1000.0)
var step: float = 8.0
var avoid: Array[Rect2] = []
var keep_clear: Array[Vector3] = []     # nothing within 9 m of these (spawns, exits)
var lowest: float = -INF                # nothing below this height (the sea)
var biome: Callable = Callable()
var seed_value: int = 5
var planted: int = 0
var solid: int = 0

var _catalog: Dictionary = {}
var _scenes: Dictionary = {}
var _shapes: Dictionary = {}           # "asset:scale" -> Array of [Shape3D, Vector3]

func _ready() -> void:
	_catalog = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "data/scenery_catalog.json"))
	await get_tree().physics_frame
	await get_tree().physics_frame
	_plant()

func _plant() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var clumps := FastNoiseLite.new()
	clumps.seed = seed_value
	clumps.frequency = 0.012
	var space := get_world_3d().direct_space_state
	var groups: Dictionary = {}        # "asset:cx:cz" -> Array[Transform3D]
	var x := area.position.x
	while x < area.end.x:
		var z := area.position.y
		while z < area.end.y:
			var at := Vector2(x + rng.randf_range(-step, step) * 0.45, z + rng.randf_range(-step, step) * 0.45)
			z += step
			# Clumps and clearings, not an even sprinkle.
			if clumps.get_noise_2d(at.x, at.y) < -0.05 or rng.randf() < 0.35:
				continue
			if _blocked(at):
				continue
			var query := PhysicsRayQueryParameters3D.create(Vector3(at.x, 600.0, at.y), Vector3(at.x, -300.0, at.y), Layers.WORLD)
			var hit := space.intersect_ray(query)
			if hit.is_empty() or not (hit["collider"] as Node).has_meta("soil"):
				continue
			var ground: Vector3 = hit["position"]
			var normal: Vector3 = hit["normal"]
			if ground.y < lowest or normal.y < 0.7:
				continue
			var allowed: Array = biome.call(at.x, at.y, ground.y) if biome.is_valid() else []
			var asset := _pick(allowed, rng)
			if asset == "":
				continue
			var kind: String = _catalog[asset]["scenery_class"]
			var size := rng.randf_range(0.8, 1.3)
			if kind == "rock":
				size = rng.randf_range(0.8, 1.9)
			elif kind == "tree":
				size = rng.randf_range(0.85, 1.25)
			var basis := Basis(Vector3.UP, rng.randf() * TAU)
			if kind == "rock" or kind == "debris":
				# Rocks and logs lie with the slope, a little sunk in.
				var tilt := Vector3.UP.cross(normal)
				if tilt.length() > 0.01:
					basis = Basis(tilt.normalized(), Vector3.UP.angle_to(normal)) * basis
				ground.y -= 0.12 * size
			var xform := Transform3D(basis.scaled(Vector3.ONE * size), ground)
			var key := "%s:%d:%d" % [asset, floori(ground.x / CELL), floori(ground.z / CELL)]
			if not groups.has(key):
				groups[key] = []
			(groups[key] as Array).append(xform)
			planted += 1
			if not (_catalog[asset]["colliders"] as Array).is_empty():
				_collide(asset, xform, size)
		x += step
	for key: String in groups:
		var asset := key.split(":")[0]
		_batch(asset, groups[key])

func _blocked(at: Vector2) -> bool:
	for rect in avoid:
		if rect.has_point(at):
			return true
	for spot in keep_clear:
		if Vector2(spot.x, spot.z).distance_to(at) < 9.0:
			return true
	return false

func _pick(allowed: Array, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for asset: String in allowed:
		if _catalog.has(asset):
			total += float(WEIGHT.get(_catalog[asset]["scenery_class"], 1.0))
	if total <= 0.0:
		return ""
	var roll := rng.randf() * total
	for asset: String in allowed:
		if not _catalog.has(asset):
			continue
		roll -= float(WEIGHT.get(_catalog[asset]["scenery_class"], 1.0))
		if roll <= 0.0:
			return asset
	return allowed[allowed.size() - 1]

func _batch(asset: String, transforms: Array) -> void:
	var kind: String = _catalog[asset]["scenery_class"]
	var template: Node3D = _scene(asset).instantiate()
	for node in template.find_children("*", "MeshInstance3D", true, false):
		var source := node as MeshInstance3D
		if kind == "rock":
			_stone(asset, source.mesh)
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = source.mesh
		multi.instance_count = transforms.size()
		for i in transforms.size():
			multi.set_instance_transform(i, (transforms[i] as Transform3D) * source.transform)
		var batch := MultiMeshInstance3D.new()
		batch.name = asset
		batch.multimesh = multi
		# The leafy trees are tens of thousands of triangles each: drawn nearer.
		var heavy := int(_catalog[asset].get("triangles", 0)) > 10000
		batch.visibility_range_end = 150.0 if heavy else REACH.get(kind, 150.0)
		batch.visibility_range_end_margin = 20.0
		batch.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		if kind == "ground_cover" or kind == "understory":
			batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(batch)
	template.free()

# The kit's stone shader in place of a rock's flat colours, keeping each colour as the tint.
var _stoned: Dictionary = {}
func _stone(asset: String, mesh: Mesh) -> void:
	if _stoned.has(mesh):
		return
	_stoned[mesh] = true
	for i in mesh.get_surface_count():
		var old := mesh.surface_get_material(i) as StandardMaterial3D
		if old == null:
			continue
		var stone := ShaderMaterial.new()
		stone.shader = load(ROOT + "shaders/scenery_stone.gdshader")
		stone.set_shader_parameter("rock_detail", load(ROOT + "art/textures/rock_albedo.jpg"))
		stone.set_shader_parameter("tint", old.albedo_color)
		stone.set_shader_parameter("stratum", 0.6 if asset in STRATA else 0.25)
		mesh.surface_set_material(i, stone)

# The catalog's boxes are in the modelling tool's axes (z up): position (x, y, z)
# is (x, z, -y) here and size (x, y, z) is (x, z, y). Scaled into the shape, as
# physics bodies should not be scaled.
func _collide(asset: String, xform: Transform3D, size: float) -> void:
	var rounded := snappedf(size, 0.1)
	var key := "%s:%.1f" % [asset, rounded]
	if not _shapes.has(key):
		var made: Array = []
		for box: Dictionary in _catalog[asset]["colliders"]:
			var shape := BoxShape3D.new()
			shape.size = Vector3(box["size"][0], box["size"][2], box["size"][1]) * rounded
			made.append([shape, Vector3(box["position"][0], box["position"][2], -float(box["position"][1])) * rounded])
		_shapes[key] = made
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.transform = Transform3D(xform.basis.orthonormalized(), xform.origin)
	for part: Array in _shapes[key]:
		var collider := CollisionShape3D.new()
		collider.shape = part[0]
		collider.position = part[1]
		body.add_child(collider)
	add_child(body)
	solid += 1

func _scene(asset: String) -> PackedScene:
	if not _scenes.has(asset):
		_scenes[asset] = load(ROOT + "art/scenery/" + asset + ".glb")
	return _scenes[asset]
