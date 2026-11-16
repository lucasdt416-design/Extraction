class_name CairnLevel
extends Level

# Cairn Divide: Hearth Colony, the middle settlement of the Cairn Divide kit.
# Five two-storey houses on a mountain shelf above the river gorge, the front
# three joined on both floors by glass walkways.
#
# The houses, walkways, door leaves, terrain, firs and rocks come from the kit
# (res://cairn_divide, loaded through CairnKit). The kit also says where its
# doors and loot cases go; this file turns those into the game's own doors,
# buttons and containers, and adds what makes it a raid: the fence, cover in
# the yards, lamps, squads and exits.
#
# Axes: +x east, +z south, the shelf at y = 0, the middle house at the origin.
# Each house is 20 m wide and 16 deep, with its front door on the south side,
# stairs inside on the north-west, and a locked archive upstairs.

# Hearth Colony, in the kit's own coordinates.
const CENTRE := Vector3(0.0, 90.0, 0.0)
# The fenced shelf. East of it the ground falls into the gorge.
const LOW := Vector2(-86.0, -72.0)
const HIGH := Vector2(86.0, 84.0)
const SCENERY_RADIUS: float = 760.0
const UPPER: float = 5.0            # the upstairs floor
const HOUSES: Array[Vector2] = [Vector2(-36.0, 0.0), Vector2(0.0, 0.0), Vector2(36.0, 0.0), Vector2(-36.0, 36.0), Vector2(36.0, 36.0)]
# Which archives hold a vault (the rest hold a locker).
const VAULTS: Array[Vector2] = [Vector2(0.0, 0.0), Vector2(36.0, 36.0)]

var kit: CairnKit

func _init() -> void:
	player_spawn = Vector3(-60.0, 0.3, 58.0)
	player_yaw = -PI * 0.25

func build() -> void:
	kit = CairnKit.new()
	kit.name = "Kit"
	add_child(kit)
	kit.load_data()
	kit.skip = _leave_out
	kit.build(CENTRE, LOW, HIGH, SCENERY_RADIUS)
	_doors()
	_loot()
	_rooms()
	_yards()
	_fence()
	_grass()
	kit.flush()
	_squads_and_exits()
	_placements()

# Thinner, clearer air than the plateau maps, and shadows that reach the trees.
func tune(env: Environment, sun: DirectionalLight3D) -> void:
	env.volumetric_fog_density = 0.0009
	env.volumetric_fog_albedo = Color(0.78, 0.86, 0.92)
	env.volumetric_fog_length = 260.0
	env.sdfgi_max_distance = 200.0
	sun.directional_shadow_max_distance = 170.0

func bake() -> void:
	var mesh := NavigationMesh.new()
	mesh.agent_radius = 0.5
	mesh.agent_height = 1.75
	mesh.agent_max_climb = 0.3
	mesh.agent_max_slope = 40.0
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	mesh.region_min_size = 220.0
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = NAV_SOURCE
	# The terrain colliders are whole 512 m cells; only the shelf is walkable.
	# The top stops under the roofs, which nobody can reach.
	mesh.filter_baking_aabb = AABB(Vector3(LOW.x, -8.0, LOW.y), Vector3(HIGH.x - LOW.x, 17.0, HIGH.y - LOW.y))
	navigation_mesh = mesh
	bake_navigation_mesh(false)

func _leave_out(asset: String, at: Vector3, _placement: Dictionary) -> bool:
	# Nothing may stand on the fence line, or in the way out of either exit.
	if not kit.inside(at, 3.0):
		return false
	if absf(at.x - LOW.x) < 3.0 or absf(at.x - HIGH.x) < 3.0 or absf(at.z - LOW.y) < 3.0 or absf(at.z - HIGH.y) < 3.0:
		return true
	return asset == "fern" and Vector2(at.x - 55.0, at.z + 38.0).length() < 6.0

# --- Doors --------------------------------------------------------------------
# The kit lists every doorway: where, which way it faces, how wide, and whether
# it is an archive. Each becomes two of the game's sliding leaves wearing the
# kit's door model, with a button on either side of the wall.

func _doors() -> void:
	var leaf_model := kit.door_leaf()
	var n := 0
	for spec: Dictionary in kit.manifest["doors"]:
		var at := kit.to_level(CairnKit._v3(spec["position"]))
		if not kit.inside(at):
			continue
		n += 1
		var yaw: float = spec["rotation_y"]
		var width: float = spec["width"]
		var locked: bool = spec.get("locked", false)
		var turn := Basis(Vector3.UP, yaw)
		var leaves: Array[Door] = []
		for side: float in [-1.0, 1.0]:
			var leaf := Door.new()
			leaf.position = at + turn * Vector3(side * width * 0.25, 0.0, 0.0)
			leaf.rotation.y = yaw
			leaf.size = Vector3(width * 0.5 - 0.035, 3.3, 0.25)
			leaf.slide = Vector3(side * (width * 0.5 + 0.08), 0.0, 0.0)
			leaf.travel = 0.8
			leaf.model = leaf_model
			leaf.model_scale = Vector3(width / 3.2, 1.0, 1.0)
			leaf.way = Vector3(-side * width * 0.25, 0.0, 0.0)
			leaf.way_width = width
			leaf.what = "archive" if locked else "door"
			leaf.locked = locked
			# Some stand open, so the place looks lived in and not sealed.
			leaf.is_open = not locked and n % 3 == 0
			add_child(leaf)
			leaves.append(leaf)
		for side: float in [-1.0, 1.0]:
			_switch(at + turn * Vector3(side * (width * 0.5 + 0.42), 1.35, side * 0.22), yaw + (PI if side < 0.0 else 0.0), leaves)

# --- Loot ---------------------------------------------------------------------
# The kit's loot cases, as this game's containers: supplies downstairs,
# lockers upstairs, and whatever is in the archive behind its locked door.

func _loot() -> void:
	for spec: Dictionary in kit.manifest["loot"]:
		var at := kit.to_level(CairnKit._v3(spec["position"]))
		if not kit.inside(at):
			continue
		at.y = UPPER if at.y > 2.0 else 0.02
		var kind := "crate"
		if int(spec["tier"]) == 3:
			var house := Vector2(roundf(at.x / 36.0) * 36.0, roundf(at.z / 36.0) * 36.0)
			kind = "vault" if VAULTS.has(house) else "locker"
			at.z -= 1.4   # against the archive's back wall
		elif int(spec["tier"]) == 2:
			kind = "locker"
		_mark(at, kind, 0.0)

# A lamp over each floor of each house, and its name by the front door.
func _rooms() -> void:
	var names: Array[String] = ["H1 STORES", "H2 COMMONS", "H3 WORKSHOP", "H4 QUARTERS", "H5 CLINIC"]
	for i in HOUSES.size():
		var house := HOUSES[i]
		for floor_y: float in [0.0, UPPER]:
			var light := OmniLight3D.new()
			light.position = Vector3(house.x + 2.0, floor_y + 3.6, house.y + 2.0)
			light.light_color = LIGHT_WARM if i % 2 == 0 else LIGHT_COOL
			light.light_energy = 3.2
			light.omni_range = 13.0
			light.omni_attenuation = 0.8
			light.shadow_enabled = false
			light.distance_fade_enabled = true
			light.distance_fade_begin = 80.0
			light.distance_fade_length = 25.0
			add_child(light)
		_sign(names[i], Vector3(house.x - 5.2, 3.9, house.y + 8.2), 0.0, 0.42, TEAL.lightened(0.45), true)

# --- Outside ------------------------------------------------------------------
# The shelf between the houses is open ground. Cover to cross it: the square
# between the two rows, the salvage yard on the north side, the lanes down
# either flank, and the ground in front of both exits.

func _yards() -> void:
	# The square between the two rows of houses.
	_stack(-6.0, 30.0, 0.3)
	_stack(9.0, 40.0, -0.4)
	_cassette(0.0, 22.0, 0.1, TEAL)
	_cassette(-14.0, 44.0, PI * 0.5 - 0.15, RUST)
	for spot: Array in [[-16.0, 26.0, 0.0], [14.0, 28.0, PI * 0.5], [4.0, 48.0, 0.0], [-4.0, 36.0, PI * 0.5], [18.0, 46.0, 0.2]]:
		_barrier(spot[0], spot[1], 3.2, spot[2])
	# The lanes between the front houses, under the glass walkways.
	for x: float in [-18.0, 18.0]:
		_barrier(x, 9.0, 3.0)
		_barrier(x, -9.0, 3.0)
	# The salvage yard behind the front row.
	_cassette(-30.0, -27.0, 0.05, OCHRE)
	_cassette(-8.0, -31.0, PI * 0.5, TEAL)
	_cassette(12.0, -24.0, -0.2, HULL)
	_stack(-34.0, -18.0, 0.5)
	_stack(22.0, -34.0, 0.2)
	for spot: Array in [[-2.0, -20.0, 0.0], [-44.0, -30.0, PI * 0.5], [30.0, -22.0, 0.3], [4.0, -42.0, 0.0], [-24.0, -44.0, 0.2]]:
		_barrier(spot[0], spot[1], 3.2, spot[2])
	# The flanks, and the ground in front of the exits.
	_cassette(-62.0, 14.0, PI * 0.5 + 0.1, HULL)
	_cassette(62.0, 20.0, PI * 0.5, RUST)
	_stack(-58.0, -8.0, 0.2)
	_stack(60.0, 2.0, -0.3)
	for spot: Array in [[-56.0, 30.0, 0.0], [-66.0, 44.0, PI * 0.5], [50.0, 48.0, 0.0], [66.0, -18.0, PI * 0.5], [46.0, -30.0, 0.0],
			[44.0, -46.0, 0.2], [-8.0, -54.0, 0.0], [8.0, -58.0, PI * 0.5], [-30.0, 62.0, 0.0], [20.0, 64.0, 0.2]]:
		_barrier(spot[0], spot[1], 3.2, spot[2])
	# Mast lamps round the shelf.
	for spot: Vector2 in [Vector2(-18.0, -18.0), Vector2(18.0, 18.0), Vector2(0.0, 34.0), Vector2(-54.0, 18.0), Vector2(54.0, 18.0),
			Vector2(52.0, -34.0), Vector2(0.0, -60.0), Vector2(-56.0, 54.0), Vector2(48.0, 62.0), Vector2(-52.0, -40.0)]:
		_mast(spot.x, spot.y)
	# Something to search out in the open.
	_mark(Vector3(-58.0, 0.0, -10.2), "crate", 0.2)
	_mark(Vector3(62.0, 0.0, 16.6), "locker", PI * 0.5)
	_mark(Vector3(9.0, 0.0, 42.2), "crate", -0.4)
	_mark(Vector3(22.0, 0.0, -36.2), "crate", 0.2)
	_mark(Vector3(-62.0, 0.0, 17.6), "locker", PI * 0.5 + 0.1)
	_sign("HEARTH COLONY", Vector3(0.0, 4.6, 11.2), 0.0, 0.8, TEAL.lightened(0.4), true)

# Two crates and a smaller one on top.
func _stack(x: float, z: float, yaw: float) -> void:
	_crate(x, z, Vector3(1.4, 1.4, 1.4), STEEL, yaw)
	var beside := Vector3(1.45, 0.0, 0.1).rotated(Vector3.UP, yaw)
	_crate(x + beside.x, z + beside.z, Vector3(1.3, 1.1, 1.3), OCHRE, yaw + 0.15)
	_crate(x + beside.x * 0.4, z + beside.z * 0.4, Vector3(0.9, 0.8, 0.9), RUST, yaw - 0.2, 1.4)

# A cargo cassette: a long sled-mounted box, tall enough to stand behind.
func _cassette(x: float, z: float, yaw: float, color: Color) -> void:
	_box(Vector3(x, 1.45, z), Vector3(5.6, 2.3, 2.3), Mats.wall(color, HULL_DARK, 0.3, 1.2, 0.6), true, true, yaw, 0.08)
	for side: float in [-1.0, 1.0]:
		var skid := Vector3(0.0, 0.0, side * 0.85).rotated(Vector3.UP, yaw)
		_box(Vector3(x + skid.x, 0.15, z + skid.z), Vector3(5.9, 0.3, 0.3), Mats.surface(Color(0.12, 0.13, 0.14), "metal", 0.5, 0.6), true, true, yaw, 0.04)
		var cap := Vector3(side * 2.82, 0.0, 0.0).rotated(Vector3.UP, yaw)
		_box(Vector3(x + cap.x, 1.45, z + cap.z), Vector3(0.08, 1.7, 1.7), Mats.surface(HULL_DARK, "metal", 0.5, 0.6), false, false, yaw, 0.02)

# A lamp on a pole.
func _mast(x: float, z: float) -> void:
	var steel := Mats.surface(Color(0.16, 0.17, 0.19), "metal", 0.5, 0.6)
	_box(Vector3(x, 2.4, z), Vector3(0.14, 4.8, 0.14), steel, true, true)
	_box(Vector3(x, 0.12, z), Vector3(0.5, 0.24, 0.5), steel, false, false, 0.0, 0.04)
	_box(Vector3(x, 4.74, z), Vector3(0.9, 0.08, 0.3), Mats.glow(LIGHT_WARM, 4.0), false)
	var light := OmniLight3D.new()
	light.position = Vector3(x, 4.5, z)
	light.light_color = LIGHT_WARM
	light.light_energy = 3.2
	light.omni_range = 15.0
	light.omni_attenuation = 0.9
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 90.0
	light.distance_fade_length = 30.0
	add_child(light)

# The perimeter: wire mesh on posts, stepping with the ground. It stops
# movement and shots; you can see the valley through it.
func _fence() -> void:
	var wire := ShaderMaterial.new()
	wire.shader = load("res://shaders/fence.gdshader")
	var steel := Mats.surface(Color(0.15, 0.16, 0.18), "metal", 0.5, 0.6)
	var corners: Array[Vector2] = [LOW, Vector2(HIGH.x, LOW.y), HIGH, Vector2(LOW.x, HIGH.y)]
	for i in 4:
		var from := corners[i]
		var to := corners[(i + 1) % 4]
		var spans := int(ceil(from.distance_to(to) / 6.0))
		var along_x := absf(to.x - from.x) > absf(to.y - from.y)
		for j in spans:
			var a := from.lerp(to, float(j) / spans)
			var b := from.lerp(to, float(j + 1) / spans)
			var mid := (a + b) * 0.5
			var ground := maxf(maxf(kit.height(a.x, a.y), kit.height(b.x, b.y)), kit.height(mid.x, mid.y))
			var length := a.distance_to(b)
			var top := ground + 3.4
			var bottom := ground - 5.0
			var body := StaticBody3D.new()
			body.collision_layer = Layers.WORLD | NAV_SOURCE
			body.collision_mask = 0
			body.position = Vector3(mid.x, (top + bottom) * 0.5, mid.y)
			var shape := BoxShape3D.new()
			shape.size = Vector3(length if along_x else 0.2, top - bottom, 0.2 if along_x else length)
			var collider := CollisionShape3D.new()
			collider.shape = shape
			body.add_child(collider)
			var panel := MeshInstance3D.new()
			var sheet := BoxMesh.new()
			sheet.size = Vector3(length if along_x else 0.02, top - bottom, 0.02 if along_x else length)
			panel.mesh = sheet
			panel.material_override = wire
			panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(panel)
			add_child(body)
			_box(Vector3(a.x, (top + bottom) * 0.5 + 0.1, a.y), Vector3(0.14, top - bottom + 0.2, 0.14), steel, false, false)
			_box(Vector3(mid.x, top, mid.y), Vector3(length if along_x else 0.07, 0.07, 0.07 if along_x else length), steel, false, false)

# Meadow over the whole shelf and a little way past the fence.
func _grass() -> void:
	var grass := Grass.new()
	grass.name = "Grass"
	grass.area = Rect2(LOW, HIGH - LOW).grow(10.0)
	grass.density = 8.0
	grass.reach = Vector2(9.5, -12.0)   # the ground rises and falls toward the fence
	grass.seed_value = 19
	add_child(grass)

func _squads_and_exits() -> void:
	# The middle house: a squad downstairs, the commander upstairs by the vault.
	squads.append({"members": ["trooper", "trooper", "lobber"], "points": [Vector3(-5.0, 0.05, 3.0), Vector3(6.0, 0.05, 5.0), Vector3(2.0, 0.05, -1.0)]})
	squads.append({"members": ["overseer", "trooper"], "points": [Vector3(-5.0, UPPER + 0.05, 3.0), Vector3(6.0, UPPER + 0.05, 4.0), Vector3(0.0, UPPER + 0.05, 6.5)]})
	# The other four houses.
	squads.append({"members": ["bulwark", "trooper"], "points": [Vector3(-41.0, 0.05, 3.0), Vector3(-30.0, 0.05, 5.0), Vector3(-36.0, 0.05, 12.0)]})
	squads.append({"members": ["marksman"], "points": [Vector3(30.0, UPPER + 0.05, 9.5), Vector3(42.0, UPPER + 0.05, 9.5)]})
	squads.append({"members": ["trooper", "rusher"], "points": [Vector3(-41.0, 0.05, 39.0), Vector3(-30.0, 0.05, 41.0), Vector3(-36.0, 0.05, 24.0)]})
	squads.append({"members": ["trooper", "trooper", "lobber"], "points": [Vector3(31.0, 0.05, 39.0), Vector3(42.0, 0.05, 41.0), Vector3(36.0, 0.05, 50.0)]})
	squads.append({"members": ["marksman"], "points": [Vector3(30.0, UPPER + 0.05, 45.5), Vector3(42.0, UPPER + 0.05, 45.5)]})
	# Out in the open: the square, the salvage yard, and the guard on each exit.
	squads.append({"members": ["trooper", "rusher", "trooper"], "points": [Vector3(0.0, 0.05, 30.0), Vector3(-12.0, 0.05, 40.0), Vector3(12.0, 0.05, 24.0)]})
	squads.append({"members": ["trooper", "lobber"], "points": [Vector3(-20.0, 0.05, -28.0), Vector3(8.0, 0.05, -34.0), Vector3(-40.0, 0.05, -22.0)]})
	squads.append({"members": ["bulwark", "rusher"], "points": [Vector3(50.0, 0.05, -30.0), Vector3(62.0, 0.05, -44.0), Vector3(40.0, 0.05, -44.0)]})
	squads.append({"members": ["trooper", "trooper"], "points": [Vector3(-6.0, 0.05, -56.0), Vector3(10.0, 0.05, -62.0), Vector3(-20.0, 0.05, -60.0)]})
	extracts.append({"position": Vector3(55.0, 0.0, -38.0), "name": "Spillway road"})
	extracts.append({"position": Vector3(0.0, kit.height(0.0, -65.0), -65.0), "name": "Lichen trail"})
	reinforce_points.clear()
	for spot: Vector2 in [Vector2(-78.0, -62.0), Vector2(78.0, -62.0), Vector2(-66.0, 70.0), Vector2(66.0, 70.0), Vector2(-80.0, 10.0), Vector2(80.0, 30.0), Vector2(30.0, -66.0)]:
		reinforce_points.append(Vector3(spot.x, kit.height(spot.x, spot.y) + 0.2, spot.y))
