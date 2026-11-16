class_name VesperKit
extends Node3D

# Loader for the Vesper Reach art kit in res://vesper_reach (made outside this
# repo; see vesper_reach/HANDOFF.md). The kit describes a 2 km island as a
# manifest of placements. A level asks this node for the part it wants:
#
#   kit.load_data()
#   kit.build(centre, playable half-extents, scenery radius)
#
# Everything is created in the kit's own coordinates under this node, and the
# node is offset so that `centre` lands on the level's origin with the ground
# at y = 0. Repeated meshes are drawn as MultiMeshes; colliders are only made
# near the playable area, and only those inside it feed the navmesh.

const ROOT: String = "res://vesper_reach/"
# Purely decorative ground cover is dropped beyond this distance from the centre.
const DETAIL_RADIUS: float = 170.0
# Things that are kept however far away they are, because they make the skyline.
const LANDMARKS: Array[String] = ["heliograph", "observatory"]

var manifest: Dictionary = {}
var catalog: Dictionary = {}
# Set by the level before build(): return true to leave a placement out.
var skip: Callable = Callable()

var _centre := Vector3.ZERO
var _half := Vector2.ZERO
var _scenes: Dictionary = {}
var _materials: Dictionary = {}
var _batches: Dictionary = {}
var _terrain_material: ShaderMaterial

func load_data() -> void:
	manifest = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "data/world_manifest.json"))
	catalog = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "data/asset_catalog.json"))

func build(centre: Vector3, half: Vector2, scenery_radius: float) -> void:
	_centre = centre
	_half = half
	position = -centre
	_terrain()
	_roads()
	for placement: Dictionary in manifest["placements"]:
		var asset: String = placement["asset"]
		var at := _v3(placement["position"])
		var distance := Vector2(at.x - centre.x, at.z - centre.z).length()
		if not asset in LANDMARKS:
			if distance > scenery_radius:
				continue
			if distance > DETAIL_RADIUS and (asset.begins_with("meadow") or asset in ["fern", "red_scrub", "storm_drain"]):
				continue
		if skip.is_valid() and skip.call(asset, to_level(at), placement):
			continue
		var scale_by := _v3(placement["scale"])
		var xform := Transform3D(Basis(Vector3.UP, float(placement["rotation_y"])) * Basis.from_scale(scale_by), at)
		_queue(asset, xform, bool(placement["collision"]))
	_signage()
	_street_lights()
	_cables()
	_ocean()

# Adds one more kit asset, positioned in level coordinates. Call before flush().
func add(asset: String, at: Vector3, yaw: float = 0.0, solid: bool = true) -> void:
	_queue(asset, Transform3D(Basis(Vector3.UP, yaw), at + _centre), solid)

# Turns everything queued into MultiMeshes. Call once, after the last add().
func flush() -> void:
	for asset: String in _batches:
		var transforms: Array = _batches[asset]
		var template: Node3D = _scene(asset).instantiate()
		var foliage := asset.begins_with("canopy") or asset.begins_with("meadow") or asset in ["fern", "red_scrub"]
		for source in _meshes(template):
			_convert_materials(source.mesh)
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = source.mesh
			multi.instance_count = transforms.size()
			for i in transforms.size():
				multi.set_instance_transform(i, (transforms[i] as Transform3D) * source.transform)
			var batch := MultiMeshInstance3D.new()
			batch.name = asset
			batch.multimesh = multi
			if foliage:
				batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if not asset.begins_with("canopy") else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			else:
				batch.gi_mode = GeometryInstance3D.GI_MODE_STATIC
			add_child(batch)
		template.free()
	_batches.clear()

func to_level(kit_position: Vector3) -> Vector3:
	return kit_position - _centre

func inside(level_position: Vector3, margin: float = 0.0) -> bool:
	return absf(level_position.x) <= _half.x + margin and absf(level_position.z) <= _half.y + margin

# --- Pieces ------------------------------------------------------------------

func _queue(asset: String, xform: Transform3D, solid: bool) -> void:
	if not _batches.has(asset):
		_batches[asset] = []
	(_batches[asset] as Array).append(xform)
	var local := to_level(xform.origin)
	# Solid only where a player or a bullet can reach it.
	if solid and inside(local, 45.0):
		_collide(asset, xform, inside(local, 4.0))

func _collide(asset: String, xform: Transform3D, walkable: bool) -> void:
	var spec: Dictionary = catalog[asset]
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD | (Level.NAV_SOURCE if walkable else 0)
	body.collision_mask = 0
	body.transform = xform
	if spec.get("trimesh", false):
		var template: Node3D = _scene(asset).instantiate()
		for source in _meshes(template):
			var collider := CollisionShape3D.new()
			collider.shape = source.mesh.create_trimesh_shape()
			collider.transform = source.transform
			body.add_child(collider)
		template.free()
	else:
		# The catalog's boxes are in the modelling tool's axes (z up).
		for box: Dictionary in spec["colliders"]:
			var shape := BoxShape3D.new()
			shape.size = Vector3(box["size"][0], box["size"][2], box["size"][1])
			var collider := CollisionShape3D.new()
			collider.shape = shape
			collider.position = Vector3(box["position"][0], box["position"][2], -float(box["position"][1]))
			body.add_child(collider)
	if body.get_child_count() == 0:
		body.free()
		return
	add_child(body)

func _terrain() -> void:
	_terrain_material = ShaderMaterial.new()
	_terrain_material.shader = load(ROOT + "shaders/terrain.gdshader")
	for key: String in ["rock_albedo", "rock_normal", "forest_albedo", "forest_normal"]:
		_terrain_material.set_shader_parameter(key, load(ROOT + "art/textures/" + key + ".jpg"))
	for cell: Dictionary in manifest["terrain"]:
		var node: Node3D = (load(ROOT + str(cell["path"])) as PackedScene).instantiate()
		add_child(node)
		var low := _v3(cell["bounds_min"])
		var high := _v3(cell["bounds_max"])
		var underfoot := _centre.x >= low.x and _centre.x <= high.x and _centre.z >= low.z and _centre.z <= high.z
		for source in _meshes(node):
			source.material_override = _terrain_material
			source.gi_mode = GeometryInstance3D.GI_MODE_STATIC
			if underfoot:
				_trimesh_body(source, true)

func _roads() -> void:
	var roads: Node3D = (load(ROOT + str(manifest["roads"])) as PackedScene).instantiate()
	add_child(roads)
	for source in _meshes(roads):
		_convert_materials(source.mesh)
		source.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_trimesh_body(source, true)

func _trimesh_body(source: MeshInstance3D, walkable: bool) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD | (Level.NAV_SOURCE if walkable else 0)
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	collider.shape = source.mesh.create_trimesh_shape()
	body.add_child(collider)
	source.add_child(body)

# The kit's models carry plain named materials; the look comes from swapping
# those for its shaders here (painted concrete, wet asphalt, textured stone).
func _convert_materials(mesh: Mesh) -> void:
	for i in mesh.get_surface_count():
		var old := mesh.surface_get_material(i) as StandardMaterial3D
		if old == null:
			continue
		var id: String = old.resource_name
		if id in ["Window", "IceLight", "AmberLight", "Crystal"]:
			continue
		if _materials.has(id):
			mesh.surface_set_material(i, _materials[id])
			continue
		var made := ShaderMaterial.new()
		if id in ["HQ_Ceramic", "HQ_Concrete", "HQ_Coral", "HQ_Teal"]:
			made.shader = load(ROOT + "shaders/painted_surface.gdshader")
			made.set_shader_parameter("paint", old.albedo_color)
			made.set_shader_parameter("metalness", old.metallic)
			made.set_shader_parameter("base_roughness", old.roughness)
			made.set_shader_parameter("surface_albedo", load(ROOT + "art/textures/concrete_albedo.jpg"))
			made.set_shader_parameter("surface_normal", load(ROOT + "art/textures/concrete_normal.jpg"))
		elif id.begins_with("HQ_") or id.begins_with("PH_"):
			continue
		elif id == "World / asphalt":
			made.shader = load(ROOT + "shaders/wet_asphalt.gdshader")
			made.set_shader_parameter("micro_normal", load(ROOT + "art/textures/concrete_normal.jpg"))
		elif id.begins_with("Leaf"):
			made.shader = load(ROOT + "shaders/foliage.gdshader")
			made.set_shader_parameter("leaf_color", old.albedo_color.darkened(0.15))
		else:
			var stone := id in ["Basalt", "SaltRock", "RustRock", "Bark"]
			var prefix := "rock" if stone else "concrete"
			made.shader = load(ROOT + "shaders/surface.gdshader")
			made.set_shader_parameter("base_color", old.albedo_color)
			made.set_shader_parameter("metallic", old.metallic)
			made.set_shader_parameter("roughness", old.roughness)
			made.set_shader_parameter("albedo_detail", load(ROOT + "art/textures/" + prefix + "_albedo.jpg"))
			made.set_shader_parameter("normal_detail", load(ROOT + "art/textures/" + prefix + "_normal.jpg"))
			made.set_shader_parameter("texture_strength", 0.82 if stone else 0.38)
			made.set_shader_parameter("texture_scale", 0.35 if stone else 0.65)
		_materials[id] = made
		mesh.surface_set_material(i, made)

# Billboards on the towers and clinics, from the kit's signage atlas.
func _signage() -> void:
	var faces: Array[ShaderMaterial] = []
	for i in 4:
		var face := ShaderMaterial.new()
		face.shader = load(ROOT + "shaders/signage.gdshader")
		face.set_shader_parameter("atlas", load(ROOT + "art/textures/colony-signage.png"))
		face.set_shader_parameter("quadrant", Vector2(i % 2, i / 2))
		faces.append(face)
	for asset: String in ["residential_tower", "clinic"]:
		for xform: Transform3D in _batches.get(asset, []):
			var quad := QuadMesh.new()
			var panel := MeshInstance3D.new()
			panel.mesh = quad
			if asset == "residential_tower":
				quad.size = Vector2(6.8, 9.5)
				panel.transform = xform * Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-7.31, 15.0, -1.0))
				panel.material_override = faces[0]
			else:
				quad.size = Vector2(2.7, 2.7)
				panel.transform = xform * Transform3D(Basis.IDENTITY, Vector3(4.0, 2.1, 6.055))
				panel.material_override = faces[3]
			add_child(panel)

func _street_lights() -> void:
	for spec: Dictionary in manifest.get("local_lights", []):
		var at := _v3(spec["position"])
		if not inside(to_level(at), 30.0):
			continue
		var light := OmniLight3D.new()
		light.position = at
		light.light_color = Color(spec["color"][0], spec["color"][1], spec["color"][2])
		light.light_energy = float(spec["energy"]) * 1.6
		light.omni_range = spec["radius"]
		light.omni_attenuation = 1.5
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 90.0
		light.distance_fade_length = 40.0
		add_child(light)

# Service cables slung across the streets, as one mesh.
func _cables() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.035, 0.045, 0.05)
	material.metallic = 0.7
	material.roughness = 0.45
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for spec: Dictionary in manifest.get("cables", []):
		var a := _v3(spec["from"])
		var b := _v3(spec["to"])
		var points: Array[Vector3] = []
		for j in 17:
			var t := j / 16.0
			points.append(a.lerp(b, t) - Vector3.UP * sin(t * PI) * float(spec["sag"]))
		for j in 16:
			var along := (points[j + 1] - points[j]).normalized()
			var u := along.cross(Vector3.UP).normalized() * float(spec["radius"])
			var v := along.cross(u).normalized() * float(spec["radius"])
			for k in 6:
				var o1 := u * cos(k * TAU / 6.0) + v * sin(k * TAU / 6.0)
				var o2 := u * cos((k + 1) * TAU / 6.0) + v * sin((k + 1) * TAU / 6.0)
				for corner: Vector3 in [points[j] + o1, points[j + 1] + o1, points[j + 1] + o2, points[j] + o1, points[j + 1] + o2, points[j] + o2]:
					tool.add_vertex(corner)
	tool.generate_normals()
	tool.set_material(material)
	var cables := MeshInstance3D.new()
	cables.mesh = tool.commit()
	cables.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cables)

# The sea beyond the island. Only ever seen from far off.
func _ocean() -> void:
	var material := ShaderMaterial.new()
	material.shader = load(ROOT + "shaders/water.gdshader")
	for spec: Dictionary in manifest["water"]:
		if spec["kind"] != "ocean":
			continue
		var plane := PlaneMesh.new()
		plane.size = Vector2(spec["size"][0], spec["size"][1])
		plane.subdivide_width = 64
		plane.subdivide_depth = 64
		var water := MeshInstance3D.new()
		water.mesh = plane
		water.position = _v3(spec["position"])
		water.material_override = material
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(water)

func _scene(asset: String) -> PackedScene:
	if not _scenes.has(asset):
		_scenes[asset] = load(ROOT + str(catalog[asset]["path"]))
	return _scenes[asset]

func _meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node)
	for child in node.get_children():
		found.append_array(_meshes(child))
	return found

static func _v3(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])
