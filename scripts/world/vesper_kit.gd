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
const CELL: float = 128.0          # scenery is batched by map square, so far squares are not drawn
const CANOPY_SWAP: float = 320.0   # a tree is the kit's model this close to the camera; a stand-in beyond
const GRID: float = 4.0            # spacing of the terrain's vertices
# Things that are kept however far away they are, because they make the skyline.
const LANDMARKS: Array[String] = ["heliograph", "observatory"]

var manifest: Dictionary = {}
var catalog: Dictionary = {}
# Set by the level before build(): return true to leave a placement out.
var skip: Callable = Callable()
# The places a player can be, as rectangles in level coordinates. Colliders are
# only made in and near them, and only what stands inside one feeds the navmesh.
# Left empty, build() makes one from its `half`.
var zones: Array[Rect2] = []
# Kit models within this distance of the centre are solid even outside a zone.
var solid_radius: float = 0.0

var _centre := Vector3.ZERO
var _half := Vector2.ZERO
var _scenes: Dictionary = {}
var _materials: Dictionary = {}
var _batches: Dictionary = {}
var _terrain_material: ShaderMaterial
var _heights: Dictionary = {}   # Vector2i (terrain grid, kit coordinates) -> y

# The colony buildings ChatGPT made to replace the kit's blocks
# (art/architecture_v3): solid by their own mesh, with walk-in entrances.
const COLONY_BUILDINGS: Array[String] = ["aster_habitat", "aster_clinic", "aster_workshop", "aster_tower", "aster_skybridge"]

func load_data() -> void:
	manifest = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "data/world_manifest.json"))
	catalog = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "data/asset_catalog.json"))
	for id in COLONY_BUILDINGS:
		catalog[id] = {"path": "art/architecture_v3/%s.glb" % id, "colliders": [], "trimesh": true}

func build(centre: Vector3, half: Vector2, scenery_radius: float) -> void:
	_centre = centre
	_half = half
	if zones.is_empty():
		zones.append(Rect2(-half, half * 2.0))
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
# Ground cover, trees and rocks are split by map square and only drawn near the
# camera; a tree beyond CANOPY_SWAP is a stand-in of a few dozen triangles.
func flush() -> void:
	for asset: String in _batches:
		var transforms: Array = _batches[asset]
		var template: Node3D = _scene(asset).instantiate()
		var canopy := asset.begins_with("canopy")
		var small := asset.begins_with("meadow") or asset in ["fern", "red_scrub", "storm_drain"]
		var rock := asset.begins_with("basalt") or asset.begins_with("salt") or asset.begins_with("cinder") or asset == "crystal_cluster"
		var reach := 150.0 if small else (CANOPY_SWAP if canopy else (520.0 if rock else 0.0))
		var groups: Dictionary = {}
		for xform: Transform3D in transforms:
			var key := Vector2i.ZERO if reach == 0.0 else Vector2i(floori(xform.origin.x / CELL), floori(xform.origin.z / CELL))
			if not groups.has(key):
				groups[key] = []
			(groups[key] as Array).append(xform)
		var whole := AABB()
		var leaf := Color(0.1, 0.2, 0.13)
		for source in _meshes(template):
			var box := source.transform * source.get_aabb()
			whole = box if whole.size == Vector3.ZERO else whole.merge(box)
			for i in source.mesh.get_surface_count():
				var old := source.mesh.surface_get_material(i) as StandardMaterial3D
				if old != null and old.resource_name.begins_with("Leaf"):
					leaf = old.albedo_color.darkened(0.15)
			_convert_materials(source.mesh)
			for key: Vector2i in groups:
				var batch := MultiMeshInstance3D.new()
				batch.name = asset
				batch.multimesh = _multi(source.mesh, groups[key], source.transform)
				if canopy or small:
					batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if canopy else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				else:
					batch.gi_mode = GeometryInstance3D.GI_MODE_STATIC
					# Godot's automatic levels of detail turn far buildings to blocks; keep more of them.
					batch.lod_bias = 3.0
				if reach > 0.0:
					batch.visibility_range_end = reach
					batch.visibility_range_end_margin = 20.0
				add_child(batch)
		if canopy:
			var far := _canopy_stand_in(whole, leaf)
			for key: Vector2i in groups:
				var batch := MultiMeshInstance3D.new()
				batch.name = asset + "_far"
				batch.multimesh = _multi(far, groups[key], Transform3D.IDENTITY)
				batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				batch.visibility_range_begin = CANOPY_SWAP
				batch.visibility_range_begin_margin = 20.0
				add_child(batch)
		template.free()
	_batches.clear()

func _multi(mesh: Mesh, transforms: Array, offset: Transform3D) -> MultiMesh:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, (transforms[i] as Transform3D) * offset)
	return multi

# A trunk and a rounded crown the size of the real tree, for far away.
func _canopy_stand_in(box: AABB, leaf: Color) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = box.size.x * 0.03
	trunk.bottom_radius = box.size.x * 0.045
	trunk.height = box.size.y * 0.5
	trunk.radial_segments = 5
	trunk.rings = 1
	var crown := SphereMesh.new()
	crown.radius = box.size.x * 0.42
	crown.height = box.size.y * 0.62
	crown.radial_segments = 12
	crown.rings = 6
	var parts: Array = [[trunk, Vector3(0.0, box.position.y + box.size.y * 0.25, 0.0), Color(0.13, 0.1, 0.08)],
		[crown, Vector3(0.0, box.position.y + box.size.y * 0.68, 0.0), leaf]]
	for part: Array in parts:
		var tool := SurfaceTool.new()
		tool.append_from(part[0], 0, Transform3D(Basis.IDENTITY, part[1]))
		var material := StandardMaterial3D.new()
		material.albedo_color = part[2]
		material.roughness = 1.0
		tool.set_material(material)
		tool.commit(mesh)
	return mesh

func to_level(kit_position: Vector3) -> Vector3:
	return kit_position - _centre

# Whether a point is in a zone (or within `margin` of one).
func inside(level_position: Vector3, margin: float = 0.0) -> bool:
	var at := Vector2(level_position.x, level_position.z)
	for zone in zones:
		if zone.grow(margin).has_point(at):
			return true
	return false

# Height of the ground at a point, in level coordinates.
func height(x: float, z: float) -> float:
	var gx := (x + _centre.x) / GRID
	var gz := (z + _centre.z) / GRID
	var x0 := floori(gx)
	var z0 := floori(gz)
	var fx := gx - x0
	var fz := gz - z0
	var a: float = _heights.get(Vector2i(x0, z0), _centre.y)
	var b: float = _heights.get(Vector2i(x0 + 1, z0), _centre.y)
	var c: float = _heights.get(Vector2i(x0, z0 + 1), _centre.y)
	var d: float = _heights.get(Vector2i(x0 + 1, z0 + 1), _centre.y)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz) - _centre.y

# --- Pieces ------------------------------------------------------------------

func _queue(asset: String, xform: Transform3D, solid: bool) -> void:
	if not _batches.has(asset):
		_batches[asset] = []
	(_batches[asset] as Array).append(xform)
	var local := to_level(xform.origin)
	# The whole island can be walked, so anything the kit calls solid is solid
	# everywhere. Trees and rocks, which the kit leaves without colliders, get a
	# trunk or a block (see _rough_collide). Only inside a zone does it feed the navmesh.
	if solid:
		_collide(asset, xform, inside(local, 4.0))
	elif asset.begins_with("canopy") or ROUGH.has(asset.rstrip("0123456789")):
		_rough_collide(asset, xform)

# Kit pieces the kit gives no collider, but a player should not walk through.
const ROUGH: Array[String] = ["basalt", "salt", "cinder", "basalt_columns", "crystal_cluster", "scanned_boulder"]
var _rough_shapes: Dictionary = {}

func _rough_collide(asset: String, xform: Transform3D) -> void:
	if not _rough_shapes.has(asset):
		var box := AABB()
		var template: Node3D = _scene(asset).instantiate()
		for source in _meshes(template):
			var part := source.transform * source.get_aabb()
			box = part if box.size == Vector3.ZERO else box.merge(part)
		template.free()
		var made: Shape3D
		var at := box.get_center()
		if asset.begins_with("canopy"):
			var trunk := CylinderShape3D.new()
			trunk.radius = clampf(box.size.x * 0.045, 0.25, 0.7)
			trunk.height = box.size.y * 0.55
			made = trunk
			at = Vector3(0.0, box.position.y + trunk.height * 0.5, 0.0)
		else:
			# A little inside the rock's bounds, so it never stops you short of the surface.
			var block := BoxShape3D.new()
			block.size = box.size * Vector3(0.78, 0.92, 0.78)
			made = block
		_rough_shapes[asset] = [made, at]
	var spec: Array = _rough_shapes[asset]
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD
	body.collision_mask = 0
	body.transform = xform
	var collider := CollisionShape3D.new()
	collider.shape = spec[0]
	collider.position = spec[1]
	body.add_child(collider)
	add_child(body)

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
		for source in _meshes(node):
			source.material_override = _terrain_material
			source.gi_mode = GeometryInstance3D.GI_MODE_STATIC
			# Marked so the grass knows bare ground from everything built on it.
			_trimesh_body(source, true).set_meta("soil", true)
			var vertices: PackedVector3Array = source.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var at := source.transform * vertex
				_heights[Vector2i(roundi(at.x / GRID), roundi(at.z / GRID))] = at.y

func _roads() -> void:
	var roads: Node3D = (load(ROOT + str(manifest["roads"])) as PackedScene).instantiate()
	add_child(roads)
	for source in _meshes(roads):
		_convert_materials(source.mesh)
		source.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_trimesh_body(source, true)

func _trimesh_body(source: MeshInstance3D, walkable: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD | (Level.NAV_SOURCE if walkable else 0)
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	collider.shape = source.mesh.create_trimesh_shape()
	body.add_child(collider)
	source.add_child(body)
	return body

# The kit's models carry plain named materials. Its built things (names starting
# HQ_) are re-finished here as a colony's prefabricated modules: pale ceramic
# hull in place of bare concrete, dark glass that glows from inside, and accent
# stripes that are lit. Everything else gets the kit's own shaders (wet
# asphalt, textured stone, foliage).
const FINISH: Dictionary = {
	# id: [albedo or null to keep, metallic, roughness, emission energy (0 = none), emission colour or null for the albedo]
	"HQ_Concrete": [Color(0.74, 0.76, 0.75), 0.12, 0.4, 0.0, null],
	"HQ_Ceramic": [Color(0.84, 0.86, 0.86), 0.15, 0.3, 0.0, null],
	"HQ_Slate": [Color(0.09, 0.11, 0.13), 0.8, 0.28, 0.0, null],
	"HQ_Metal": [null, 0.9, 0.22, 0.0, null],
	"HQ_Glass": [Color(0.03, 0.07, 0.09), 0.9, 0.06, 0.1, Color(0.2, 0.8, 0.85)],
	"HQ_Teal": [null, 0.4, 0.3, 1.5, null],
	"HQ_Acid": [null, 0.2, 0.4, 1.3, null],
	"HQ_Coral": [null, 0.3, 0.4, 0.9, null],
}

func _convert_materials(mesh: Mesh) -> void:
	for i in mesh.get_surface_count():
		var old := mesh.surface_get_material(i) as StandardMaterial3D
		if old == null:
			continue
		var id: String = old.resource_name.split(".")[0]
		if id in ["Window", "IceLight", "AmberLight", "Crystal"]:
			continue
		if _materials.has(id):
			mesh.surface_set_material(i, _materials[id])
			continue
		if FINISH.has(id):
			var finish: Array = FINISH[id]
			var tuned := old.duplicate() as StandardMaterial3D
			if finish[0] != null:
				tuned.albedo_color = finish[0]
			tuned.metallic = finish[1]
			tuned.roughness = finish[2]
			if float(finish[3]) > 0.0:
				tuned.emission_enabled = true
				tuned.emission = finish[4] if finish[4] != null else tuned.albedo_color
				tuned.emission_energy_multiplier = finish[3]
			_materials[id] = tuned
			mesh.surface_set_material(i, tuned)
			continue
		if id.begins_with("HQ_") or id.begins_with("PH_"):
			continue
		var made := ShaderMaterial.new()
		if id == "World / asphalt":
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
