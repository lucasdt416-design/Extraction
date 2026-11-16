class_name CairnKit
extends Node3D

# Loader for the Cairn Divide art kit in res://cairn_divide (made outside this
# repo; see cairn_divide/HANDOFF.md). The kit describes a 2 km mountain valley
# as a manifest. A level asks for the part it wants:
#
#   kit.load_data()
#   kit.ground(centre, core)
#   kit.populate(zones)
#   ... kit.height(x, z) while it places its own things ...
#   kit.flush()
#
# Everything is made in the kit's own coordinates under this node, and the node
# is offset so that `centre` lands on the level's origin. `zones` are the
# settlements, as rectangles in level coordinates: only what stands inside one
# feeds the navmesh. `core` is half the side of the square a player can reach.

const ROOT: String = "res://cairn_divide/"
const BUILT: Array[String] = ["habitation", "laboratory", "utility", "glass_bridge", "relay_mast", "pump_station", "quarry_gantry", "survey_dish"]
const SWAP: float = 60.0      # a scanned fir is drawn this close to the camera; a stand-in beyond
const FERN_CELL: float = 96.0
const WEAR: float = 0.5       # how run-down the painted walls look (0 new, 1 derelict)
const GRID: float = 4.0   # spacing of the terrain's vertices

var manifest: Dictionary = {}
var catalog: Dictionary = {}
# Set by the level before build(): return true to leave a placement out.
var skip: Callable = Callable()
var real_trees: int = 0
var far_trees: int = 0

var _centre := Vector3.ZERO
var _zones: Array[Rect2] = []
var _core: float = 768.0
var _scenes: Dictionary = {}
var _materials: Dictionary = {}
var _batches: Dictionary = {}
var _heights: Dictionary = {}       # Vector2i (terrain grid, kit coordinates) -> y
var _far_firs: Array[Transform3D] = []
var _stand_in: ArrayMesh

func load_data() -> void:
	manifest = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "data/world_manifest.json"))
	catalog = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "data/asset_catalog.json"))

# First the ground, so the level can ask for heights while it decides where
# its own places go...
func ground(centre: Vector3, core: float) -> void:
	_centre = centre
	_core = core
	position = -centre
	_terrain()
	_paths()
	_river()

# ...then everything that stands on it.
func populate(zones: Array[Rect2]) -> void:
	_zones = zones
	var fir: Mesh = null
	var fir_offset := Transform3D.IDENTITY
	for placement: Dictionary in manifest["placements"]:
		var asset: String = placement["asset"]
		var at := _v3(placement["position"])
		var local := to_level(at)
		var reachable := absf(local.x) < _core and absf(local.z) < _core
		var scale_by := _v3(placement["scale"])
		if asset == "meadow":
			continue   # the game grows its own grass
		if asset == "young_fir":
			# One fir model is shipped; a young one is the same tree, smaller.
			asset = "alpine_fir"
			scale_by *= 0.3
		if not catalog.has(asset):
			continue
		if asset == "fern" and not reachable:
			continue
		if skip.is_valid() and skip.call(asset, local, placement):
			continue
		var xform := Transform3D(Basis(Vector3.UP, float(placement["rotation_y"])) * Basis.from_scale(scale_by), at)
		if asset == "fern":
			# Ferns are batched by map square, so far squares are not drawn at all.
			var key := "fern:%d:%d" % [floori(at.x / FERN_CELL), floori(at.z / FERN_CELL)]
			if not _batches.has(key):
				_batches[key] = []
			(_batches[key] as Array).append(xform)
			continue
		if asset != "alpine_fir":
			_queue(asset, xform, bool(placement["collision"]) and reachable)
			continue
		if not reachable:
			_far_firs.append(xform)
			continue
		# The scanned fir is 220,000 triangles, so it is only drawn close to: past
		# SWAP metres the stand-in takes over, and the stand-in casts its shadow.
		if fir == null:
			var template: Node3D = _scene(asset).instantiate()
			var source: MeshInstance3D = _meshes(template)[0]
			fir = source.mesh
			fir_offset = source.transform
			template.free()
		var tree := MeshInstance3D.new()
		tree.mesh = fir
		tree.transform = xform * fir_offset
		tree.lod_bias = 0.5
		tree.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tree.visibility_range_end = SWAP
		tree.visibility_range_end_margin = 8.0
		tree.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		add_child(tree)
		for shadow_only: bool in [true, false]:
			var stand_in := MeshInstance3D.new()
			stand_in.mesh = _fir_stand_in()
			stand_in.transform = xform
			if shadow_only:
				stand_in.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
				stand_in.visibility_range_end = 220.0
			else:
				stand_in.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				stand_in.visibility_range_begin = SWAP
				stand_in.visibility_range_begin_margin = 8.0
				stand_in.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			add_child(stand_in)
		real_trees += 1
		_collide(asset, xform, inside(local, 4.0))
	far_trees = _far_firs.size()
	_lights()
	_rails()
	_piers()

# Adds one more kit model, placed in level coordinates. Call before flush().
func add(asset: String, at: Vector3, yaw: float = 0.0, size: float = 1.0, solid: bool = true) -> void:
	_queue(asset, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), at + _centre), solid)

# Turns everything queued into MultiMeshes. Call once, after the level is done.
func flush() -> void:
	for key: String in _batches:
		var asset: String = key.split(":")[0]
		var transforms: Array = _batches[key]
		var template: Node3D = _scene(asset).instantiate()
		for source in _meshes(template):
			_convert_materials(source.mesh)
			var batch := MultiMeshInstance3D.new()
			batch.name = key.replace(":", "_")
			batch.multimesh = _multi(source.mesh, transforms, source.transform)
			if asset == "fern":
				batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				batch.visibility_range_end = 150.0
				batch.visibility_range_end_margin = 20.0
			else:
				batch.gi_mode = GeometryInstance3D.GI_MODE_STATIC
			add_child(batch)
		template.free()
	_batches.clear()
	if not _far_firs.is_empty():
		var forest := MultiMeshInstance3D.new()
		forest.name = "FarFirs"
		forest.multimesh = _multi(_fir_stand_in(), _far_firs, Transform3D.IDENTITY)
		forest.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(forest)
		_far_firs.clear()

func to_level(kit_position: Vector3) -> Vector3:
	return kit_position - _centre

# Whether a point is in a settlement (or within `margin` of one).
func inside(level_position: Vector3, margin: float = 0.0) -> bool:
	var at := Vector2(level_position.x, level_position.z)
	for zone in _zones:
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
	if solid:
		_collide(asset, xform, inside(to_level(xform.origin), 4.0))

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
		# The catalog's shapes are in the modelling tool's axes (z up).
		for piece: Dictionary in spec["colliders"]:
			var collider := CollisionShape3D.new()
			if piece.has("vertices"):
				var points := PackedVector3Array()
				for v: Array in piece["vertices"]:
					points.append(Vector3(v[0], v[2], -float(v[1])))
				var hull := ConvexPolygonShape3D.new()
				hull.points = points
				collider.shape = hull
			else:
				var shape := BoxShape3D.new()
				shape.size = Vector3(piece["size"][0], piece["size"][2], piece["size"][1])
				collider.shape = shape
				collider.position = Vector3(piece["position"][0], piece["position"][2], -float(piece["position"][1]))
			body.add_child(collider)
	if body.get_child_count() == 0:
		body.free()
		return
	add_child(body)

func _terrain() -> void:
	var ground := ShaderMaterial.new()
	ground.shader = load(ROOT + "shaders/mountain.gdshader")
	for key: String in ["rock_albedo", "rock_normal", "forest_albedo", "forest_normal"]:
		ground.set_shader_parameter(key, load(ROOT + "art/textures/" + key + ".jpg"))
	# The shader paints moss and snow by height; it has to be told the level sits lower.
	ground.set_shader_parameter("lift", _centre.y)
	for cell: Dictionary in manifest["terrain"]:
		var node: Node3D = (load(ROOT + str(cell["path"])) as PackedScene).instantiate()
		add_child(node)
		for source in _meshes(node):
			source.material_override = ground
			source.gi_mode = GeometryInstance3D.GI_MODE_STATIC
			# Marked so the grass knows bare ground from everything built on it.
			_trimesh_body(source).set_meta("soil", true)
			var vertices: PackedVector3Array = source.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var at := source.transform * vertex
				_heights[Vector2i(roundi(at.x / GRID), roundi(at.z / GRID))] = at.y

func _paths() -> void:
	var gravel := ShaderMaterial.new()
	gravel.shader = load(ROOT + "shaders/surface.gdshader")
	gravel.set_shader_parameter("base_color", Color(0.25, 0.26, 0.21))
	gravel.set_shader_parameter("roughness", 0.95)
	gravel.set_shader_parameter("albedo_detail", load(ROOT + "art/textures/rock_albedo.jpg"))
	gravel.set_shader_parameter("normal_detail", load(ROOT + "art/textures/rock_normal.jpg"))
	gravel.set_shader_parameter("texture_strength", 0.8)
	gravel.set_shader_parameter("texture_scale", 0.7)
	var paths: Node3D = (load(ROOT + str(manifest["roads"])) as PackedScene).instantiate()
	add_child(paths)
	for source in _meshes(paths):
		source.material_override = gravel
		source.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_trimesh_body(source)

func _river() -> void:
	var water := ShaderMaterial.new()
	water.shader = load(ROOT + "shaders/river.gdshader")
	water.set_shader_parameter("normal_texture", load(ROOT + "art/textures/rock_normal.jpg"))
	var river: Node3D = (load(ROOT + str(manifest["river"])) as PackedScene).instantiate()
	add_child(river)
	for source in _meshes(river):
		source.material_override = water
		source.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _trimesh_body(source: MeshInstance3D) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD | Level.NAV_SOURCE
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	collider.shape = source.mesh.create_trimesh_shape()
	body.add_child(collider)
	source.add_child(body)
	return body

# The lamps the kit hangs in its rooms.
func _lights() -> void:
	var lamp := 0
	for spec: Dictionary in manifest["lights"]:
		var at := _v3(spec["position"])
		lamp += 1
		if lamp % 4 == 0:
			continue   # a quarter of them have failed
		var light := OmniLight3D.new()
		light.position = at
		light.light_color = Color(spec["color"][0], spec["color"][1], spec["color"][2])
		light.light_energy = float(spec["energy"]) * 1.8
		light.omni_range = float(spec["radius"]) * 1.3
		light.omni_attenuation = 1.0
		light.shadow_enabled = false
		light.distance_fade_enabled = true
		light.distance_fade_begin = 80.0
		light.distance_fade_length = 30.0
		add_child(light)

# Rails across the upper doorways that open onto nothing.
func _rails() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.1, 0.15, 0.14)
	steel.metallic = 0.75
	steel.roughness = 0.43
	for spec: Dictionary in manifest.get("guard_rails", []):
		var at := _v3(spec["position"])
		var width: float = spec["width"]
		var body := StaticBody3D.new()
		body.collision_layer = Layers.WORLD
		body.collision_mask = 0
		body.position = at
		body.rotation.y = spec["rotation_y"]
		var shape := BoxShape3D.new()
		shape.size = Vector3(width, 1.15, 0.08)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		collider.position.y = 0.575
		body.add_child(collider)
		for bar: Array in [[Vector3(0.0, 1.1, 0.0), Vector3(width, 0.06, 0.06)], [Vector3(0.0, 0.55, 0.0), Vector3(width, 0.035, 0.035)],
				[Vector3(-width * 0.5, 0.55, 0.0), Vector3(0.06, 1.1, 0.06)], [Vector3(width * 0.5, 0.55, 0.0), Vector3(0.06, 1.1, 0.06)]]:
			var mesh := BoxMesh.new()
			mesh.size = bar[1]
			var piece := MeshInstance3D.new()
			piece.mesh = mesh
			piece.position = bar[0]
			piece.material_override = steel
			body.add_child(piece)
		add_child(body)

# What holds up the two long crossings over the gorge. Scenery: no colliders.
func _piers() -> void:
	var concrete := StandardMaterial3D.new()
	concrete.albedo_color = Color(0.22, 0.26, 0.24)
	concrete.roughness = 0.9
	for bridge: Dictionary in manifest["bridges"]:
		if bridge["type"] != "ravine":
			continue
		var a := _v3(bridge["from"])
		var b := _v3(bridge["to"])
		for t: float in [0.0, 0.25, 0.75, 1.0]:
			var at := a.lerp(b, t)
			var foot := 40.0
			var mesh := BoxMesh.new()
			mesh.size = Vector3(2.4, at.y - foot, 5.4)
			var pier := MeshInstance3D.new()
			pier.mesh = mesh
			pier.position = Vector3(at.x, (at.y + foot) * 0.5, at.z)
			pier.material_override = concrete
			add_child(pier)

# The kit's models carry plain named materials; the painted ones are swapped for
# its shader here. The rest are finished materials and are left alone.
func _convert_materials(mesh: Mesh) -> void:
	for i in mesh.get_surface_count():
		var old := mesh.surface_get_material(i) as StandardMaterial3D
		if old == null:
			continue
		var id: String = old.resource_name.split(".")[0]
		if not id in ["HQ_Ceramic", "HQ_Concrete", "HQ_Coral", "HQ_Teal"]:
			continue
		if not _materials.has(id):
			var paint := ShaderMaterial.new()
			paint.shader = load(ROOT + "shaders/painted_surface.gdshader")
			paint.set_shader_parameter("paint", old.albedo_color)
			paint.set_shader_parameter("metalness", old.metallic)
			paint.set_shader_parameter("base_roughness", old.roughness)
			paint.set_shader_parameter("wear", WEAR)
			paint.set_shader_parameter("surface_albedo", load(ROOT + "art/textures/concrete_albedo.jpg"))
			paint.set_shader_parameter("surface_normal", load(ROOT + "art/textures/concrete_normal.jpg"))
			_materials[id] = paint
		mesh.surface_set_material(i, _materials[id])

func door_leaf() -> PackedScene:
	var scene: PackedScene = load(ROOT + "art/detail/door_leaf.glb")
	var template: Node3D = scene.instantiate()
	for source in _meshes(template):
		_convert_materials(source.mesh)
	template.free()
	return scene

func _multi(mesh: Mesh, transforms: Array, offset: Transform3D) -> MultiMesh:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, (transforms[i] as Transform3D) * offset)
	return multi

# A fir for the far hillsides: a trunk and a stack of drooping skirts, about a
# hundred triangles, the same height as the scanned one (23 m).
func _fir_stand_in() -> ArrayMesh:
	if _stand_in != null:
		return _stand_in
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cone(tool, 0.0, 9.0, 0.3, 0.18, Color(0.1, 0.08, 0.06), Color(0.1, 0.08, 0.06))
	for tier in 8:
		var base := 5.0 + tier * 2.2
		var spread := (3.0 if tier % 2 == 0 else 2.5) * (1.0 - tier / 8.8)
		_cone(tool, base, base + 3.6, spread, spread * 0.1, Color(0.035, 0.055, 0.035), Color(0.075, 0.11, 0.065))
	tool.generate_normals()
	var needles := StandardMaterial3D.new()
	needles.vertex_color_use_as_albedo = true
	needles.roughness = 1.0
	tool.set_material(needles)
	_stand_in = tool.commit()
	return _stand_in

func _cone(tool: SurfaceTool, y0: float, y1: float, r0: float, r1: float, low: Color, high: Color) -> void:
	var sides := 8
	for k in sides:
		var a := k * TAU / sides
		var b := (k + 1) * TAU / sides
		var corners: Array[Vector3] = [
			Vector3(cos(a) * r0, y0, sin(a) * r0), Vector3(cos(b) * r0, y0, sin(b) * r0),
			Vector3(cos(b) * r1, y1, sin(b) * r1), Vector3(cos(a) * r1, y1, sin(a) * r1)]
		for index: int in [0, 2, 1, 0, 3, 2]:
			tool.set_color(low if index < 2 else high)
			tool.add_vertex(corners[index])

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
