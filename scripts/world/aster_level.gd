class_name AsterLevel
extends Level

# Aster City: the four central blocks of the Vesper Reach colony, cordoned off,
# and the two quarters north and south of the cordon, reached through its gates.
#
# The streets, buildings, terrain and skyline come from the Vesper Reach art
# kit (res://vesper_reach, loaded through VesperKit). Everything that makes it
# a place to fight is authored here, in the same code-built language as Relay
# Station: the relay spire on the crossroads, two glass bridges over the
# avenue, the depot hangar, roof landings, the cordon, cover, loot and squads.
#
# Axes: +x east, +z south, ground y = 0, the crossroads at the origin.
# Buildings sit on a grid: columns x = -66, -33, 33, 66, rows z = -62, -31, 31,
# 62. The avenue runs east-west along z = 0, the boulevard north-south along
# x = 0. North-row buildings open to the south, south-row buildings to the north.

# The crossroads, in the kit's own coordinates.
const CENTRE := Vector3(-245.0, 26.0, -130.0)
const HALF := Vector2(84.0, 112.0)
# The cordon proper: the wall across the north and south of the centre, with a
# gate in each. Past them the map runs on to the outer wall at HALF.y.
const INNER: float = 80.0
const SCENERY_RADIUS: float = 1500.0
# The other places on the island, from the kit's own list of districts:
# [name, where it is in the kit's coordinates, half the side of its level ground,
#  the three kinds of building this game adds there].
const SITES: Array[Array] = [
	["The Heliograph", Vector3(135.0, 65.0, -285.0), 68.0, ["workshop", "clinic", "workshop"]],
	["Tideworks", Vector3(650.0, 9.0, -120.0), 72.0, ["workshop", "workshop", "habitat"]],
	["Saltglass Terraces", Vector3(-650.0, 53.0, -310.0), 68.0, ["clinic", "habitat", "clinic"]],
	["Viridian Conservatory", Vector3(350.0, 29.0, 425.0), 72.0, ["habitat", "clinic", "habitat"]],
	["Cinder Excavation", Vector3(-490.0, 59.0, 485.0), 68.0, ["workshop", "habitat", "workshop"]],
	["Northwatch", Vector3(-90.0, 98.0, -735.0), 40.0, []],
	["Southshore Ferry", Vector3(-20.0, 10.0, 770.0), 40.0, []],
]
# Where a building may be added on a site, about its middle: (x, z, which way its door faces).
const SLOTS: Array[Vector3] = [Vector3(-33.0, -31.0, 1.0), Vector3(0.0, -31.0, 1.0), Vector3(33.0, -31.0, 1.0),
	Vector3(-33.0, 31.0, -1.0), Vector3(0.0, 31.0, -1.0), Vector3(33.0, 31.0, -1.0)]
const SCENERY_ONLY: Array[String] = ["meadow_patch", "red_scrub", "fern", "basalt0", "basalt1", "basalt2", "salt0", "salt1", "salt2",
	"cinder0", "cinder1", "cinder2", "crystal_cluster", "basalt_columns", "loot_crate", "storm_drain"]
const ROOF: float = 5.24            # top of a low building's roof
const COLUMNS: Array[float] = [-66.0, -33.0, 33.0, 66.0]
const ROWS: Array[float] = [-93.0, -62.0, -31.0, 31.0, 62.0, 93.0]
# The lot the depot stands on: the kit's buildings there are left out.
const DEPOT := Rect2(20.0, 26.0, 26.0, 48.0)
# Lots with a residential tower on them: a bigger ground floor than the rest.
const TOWERS: Array[Vector2] = [Vector2(-66.0, -62.0), Vector2(66.0, -62.0), Vector2(-33.0, -31.0), Vector2(-66.0, 62.0), Vector2(66.0, 62.0),
	Vector2(33.0, -93.0), Vector2(-33.0, 93.0)]

var kit: VesperKit
var _islands: Array[AABB] = []       # one island of navmesh each: the city, then every site
var _starts: Array[Array] = []       # [position, yaw] of each place a raid can begin

func _init() -> void:
	player_spawn = Vector3(-4.0, 0.2, 75.0)
	player_yaw = 0.0
	reinforce_points = [
		Vector3(0.0, 0.2, -100.0), Vector3(-40.0, 0.2, 104.0), Vector3(-79.0, 0.2, -46.0), Vector3(79.0, 0.2, -46.0),
		Vector3(-79.0, 0.2, 46.0), Vector3(79.0, 0.2, 46.0), Vector3(-79.0, 0.2, 8.0),
	]

func build() -> void:
	kit = VesperKit.new()
	kit.name = "Kit"
	add_child(kit)
	kit.load_data()
	kit.skip = _leave_out
	kit.zones.append(Rect2(-HALF, HALF * 2.0))
	for site: Array in SITES:
		var middle := kit.to_level(site[1])
		var reach: float = site[2]
		kit.zones.append(Rect2(middle.x - reach, middle.z - reach, reach * 2.0, reach * 2.0))
	kit.solid_radius = 230.0   # the rest of the city, outside the cordon, is solid too
	separate_regions = true
	reinforce_range = 170.0
	minimap = load(VesperKit.ROOT + "art/textures/minimap.png")
	minimap_span = 2048.0
	minimap_centre = Vector2(-CENTRE.x, -CENTRE.z)
	places.append({"name": "Aster City", "position": Vector3.ZERO})
	_starts.append([player_spawn, player_yaw])
	kit.build(CENTRE, HALF, SCENERY_RADIUS)
	_roof_access()
	_spire()
	_glass_bridge(-66.0)
	_glass_bridge(66.0)
	_depot()
	_cordon()
	_streets()
	_outskirts()
	_interiors()
	_doors()
	_colony_gear()
	for i in SITES.size():
		_site(i)
	_grass()
	kit.flush()
	_squads_and_exits()
	var pick := spawn_at if spawn_at >= 0 else int(GameManager.rng.randi() % _starts.size())
	player_spawn = _starts[pick][0]
	player_yaw = _starts[pick][1]
	_placements()

# The environment is the raid's; this map only wants a longer view.
func tune(env: Environment, sun: DirectionalLight3D) -> void:
	env.volumetric_fog_density = 0.0016
	env.volumetric_fog_length = 220.0
	env.sdfgi_max_distance = 180.0
	sun.directional_shadow_max_distance = 150.0

func bake() -> void:
	# The terrain collider is the whole island; only the cordon and the sites are walkable.
	_islands.push_front(AABB(Vector3(-HALF.x, -1.0, -HALF.y), Vector3(HALF.x * 2.0, 12.0, HALF.y * 2.0)))
	_bake_islands(_islands, 0.3)

# --- What the kit's manifest gets wrong for this game -------------------------

func _leave_out(asset: String, at: Vector3, _placement: Dictionary) -> bool:
	# Loot and exits are this game's own objects.
	if asset in ["loot_crate", "extraction_pad"]:
		return true
	if not Rect2(-HALF, HALF * 2.0).grow(6.0).has_point(Vector2(at.x, at.z)):
		return false
	# The gantries stand where the glass bridges go; the kit's skywalks sit
	# 40 cm above the roofs they are meant to join.
	if asset in ["transit_gantry", "skywalk"]:
		return true
	# Stairs are re-added with a ramp to walk on (see _roof_access).
	if asset == "service_stairs":
		return true
	# The arcades' middle post stands a metre in front of the door it shelters,
	# which nothing but the player can squeeze past. Moved out from the wall.
	if asset == "street_arcade" and not DEPOT.grow(3.0).has_point(Vector2(at.x, at.z)):
		var deep := TOWERS.has(Vector2(roundf(at.x), roundf(at.z) - 9.0))   # a tower's front is 2 m further out
		kit.add("street_arcade", at + Vector3(0.0, 0.0, 3.6 if deep else 1.5), 0.0)
		return true
	# A few of the kit's barriers stand straight across a doorway.
	if asset == "barrier":
		for column in COLUMNS:
			for row in ROWS:
				var depth := 7.9 if TOWERS.has(Vector2(column, row)) else 5.9
				var door := Vector3(column, 0.0, row + (depth if row < 0.0 else -depth))
				if Vector2(at.x - door.x, at.z - door.z).length() < 4.0:
					return true
	# Cleared for the depot, the spire and the cordon line.
	if DEPOT.grow(3.0).has_point(Vector2(at.x, at.z)):
		return true
	if absf(at.x) < 21.0 and absf(at.z) < 9.0:
		return true
	if absf(absf(at.x) - HALF.x) < 3.0 or absf(absf(at.z) - HALF.y) < 3.0 or absf(absf(at.z) - INNER) < 3.0:
		return true
	return false

# --- Roofs --------------------------------------------------------------------
# The kit's service stairs stop a metre short of the roofs and a step below
# them. Each gets a ramp to walk on, a landing that reaches the roof, and
# something on the roof worth climbing for.

func _roof_access() -> void:
	var slab := Mats.wall(HULL, HULL_DARK, 0.0, 1.5, 0.7)
	var steel := Mats.surface(Color(0.2, 0.21, 0.23), "metal", 0.5, 0.7)
	for column: float in [-66.0, 66.0]:
		for row: float in [-31.0, 31.0]:
			var foot := Vector3(column + 10.0, 0.0, row + 5.0)
			kit.add("service_stairs", foot, 0.0, false)
			_slope(foot + Vector3(0.0, -0.05, 0.3), foot + Vector3(0.0, ROOF, -11.8), 3.0, null)
			# Landing: off the top of the stairs, round the corner, onto the roof.
			_box(Vector3(column + 7.8, ROOF - 0.15, row - 8.1), Vector3(7.6, 0.3, 3.8), slab, true, true, 0.0, 0.04)
			_box(Vector3(column + 7.8, ROOF + 0.55, row - 10.0), Vector3(7.6, 1.1, 0.12), steel)
			_box(Vector3(column + 11.6, ROOF + 0.55, row - 8.6), Vector3(0.12, 1.1, 2.8), steel)
			_box(Vector3(column + 4.0, ROOF + 0.55, row - 8.6), Vector3(0.12, 1.1, 2.8), steel)
			for post: float in [4.2, 11.4]:
				_box(Vector3(column + post, ROOF * 0.5 - 0.15, row - 9.8), Vector3(0.25, ROOF - 0.3, 0.25), steel, false)
			# Roof furniture: a vent block to shoot from behind, and a low wall on
			# the side that overlooks the avenue.
			_box(Vector3(column - 3.0, ROOF + 0.6, row + 1.5), Vector3(2.4, 1.2, 1.6), Mats.surface(STEEL, "metal", 0.5, 0.6), true, true, 0.0, 0.08)
			var edge := row + (5.9 if row < 0.0 else -5.9)
			_box(Vector3(column - 4.2, ROOF + 0.5, edge), Vector3(5.0, 1.0, 0.35), slab, true, true, 0.0, 0.05)
			_mark(Vector3(column + 3.0, ROOF, row + (2.5 if row < 0.0 else -2.5)), "crate", PI * 0.5)

# A walkable incline whose top surface runs from one point to the other.
# With no material it is collision only (it lies over a modelled staircase).
func _slope(from: Vector3, to: Vector3, width: float, mat: Material, thick: float = 0.3) -> void:
	var along := to - from
	var forward := along.normalized()
	var side := Vector3.UP.cross(forward).normalized()
	var up := forward.cross(side)
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD | NAV_SOURCE
	body.collision_mask = 0
	body.transform = Transform3D(Basis(side, up, forward), (from + to) * 0.5 - up * thick * 0.5)
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, thick, along.length())
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	if mat != null:
		var visual := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = shape.size
		visual.mesh = mesh
		visual.material_override = mat
		body.add_child(visual)
	add_child(body)

# --- The relay spire ------------------------------------------------------------
# On the crossroads: a concrete core with a deck round it at roof height, a
# ramp up from each side of the avenue, and a mast that marks the middle of the
# map from anywhere in it. The deck sees down all four streets, and can be
# seen from all four.

func _spire() -> void:
	var concrete := Mats.wall(HULL, RUST, 1.0, 2.0, 0.6)
	var dark := Mats.wall(HULL_DARK, OCHRE, 0.0, 1.5, 0.6, 0.3)
	var steel := Mats.surface(Color(0.2, 0.21, 0.23), "metal", 0.5, 0.7)
	var deck := 5.2
	_box(Vector3(0.0, 5.5, 0.0), Vector3(5.0, 11.0, 5.0), concrete, true, true, 0.0, 0.1)
	_box(Vector3(0.0, deck - 0.15, 0.0), Vector3(13.0, 0.3, 13.0), dark, true, true, 0.0, 0.05)
	_box(Vector3(0.0, deck - 0.36, 0.0), Vector3(13.3, 0.12, 13.3), Mats.surface(OCHRE, "plain", 0.5), false)
	for corner: Vector2 in [Vector2(-5.9, -5.9), Vector2(5.9, -5.9), Vector2(-5.9, 5.9), Vector2(5.9, 5.9)]:
		_box(Vector3(corner.x, (deck - 0.3) * 0.5, corner.y), Vector3(0.8, deck - 0.3, 0.8), concrete, true, true, 0.0, 0.06)
	for direction: float in [-1.0, 1.0]:
		_slope(Vector3(direction * 19.5, -0.1, 0.0), Vector3(direction * 6.5, deck, 0.0), 3.4, dark)
		# Ramp side walls, low enough to fire over.
		for side: float in [-1.0, 1.0]:
			_slope(Vector3(direction * 19.5, 0.5, side * 1.78), Vector3(direction * 6.5, deck + 0.9, side * 1.78), 0.16, steel, 0.9)
		# Parapet on the ramp sides of the deck, with a gap for the ramp.
		for side: float in [-1.0, 1.0]:
			_box(Vector3(direction * 6.33, deck + 0.55, side * 4.15), Vector3(0.34, 1.1, 4.7), concrete, true, true, 0.0, 0.05)
		# And along the other two sides, unbroken.
		_box(Vector3(0.0, deck + 0.55, direction * 6.33), Vector3(13.0, 1.1, 0.34), concrete, true, true, 0.0, 0.05)
		_box(Vector3(0.0, deck + 1.13, direction * 6.33), Vector3(13.04, 0.06, 0.4), Mats.surface(OCHRE, "plain", 0.5), false)
	# Under the deck: lit, with hard cover either side of the core.
	_barrier(-3.6, 9.5, 3.2)
	_barrier(3.6, -9.5, 3.2)
	_crate(4.4, 3.6, Vector3(1.4, 1.4, 1.4), RUST, 0.2)
	_crate(-4.4, -3.6, Vector3(1.6, 1.2, 1.2), STEEL, -0.3)
	for spot: Vector2 in [Vector2(-4.2, 0.0), Vector2(4.2, 0.0)]:
		_lamp(Vector3(spot.x, deck - 0.6, spot.y), LIGHT_COOL, 1.6, 9.0, false, true)
	_mark(Vector3(0.0, 0.0, 3.0), "locker", PI)
	_mark(Vector3(0.0, 0.0, -3.0), "crate")
	_mark(Vector3(-4.6, deck, -4.4), "crate", PI * 0.5)
	_sign("RELAY 01", Vector3(0.0, 8.6, 2.53), 0.0, 1.1, Color(0.16, 0.17, 0.19))
	_sign("RELAY 01", Vector3(0.0, 8.6, -2.53), PI, 1.1, Color(0.16, 0.17, 0.19))
	# Mast.
	for leg: Vector2 in [Vector2(-0.9, -0.9), Vector2(0.9, -0.9), Vector2(-0.9, 0.9), Vector2(0.9, 0.9)]:
		_box(Vector3(leg.x, 23.0, leg.y), Vector3(0.16, 24.0, 0.16), steel, false)
	for level in 8:
		var y := 12.5 + level * 3.0
		for brace: Array in [[Vector3(0, y, -0.9), Vector3(1.96, 0.1, 0.1)], [Vector3(0, y, 0.9), Vector3(1.96, 0.1, 0.1)], [Vector3(-0.9, y, 0), Vector3(0.1, 0.1, 1.96)], [Vector3(0.9, y, 0), Vector3(0.1, 0.1, 1.96)]]:
			_box(brace[0], brace[1], steel, false)
	for dish: Array in [[Vector3(1.3, 20.0, 0.0), Vector3.RIGHT], [Vector3(0.0, 24.0, -1.3), Vector3.BACK], [Vector3(-1.3, 28.0, 0.0), Vector3.RIGHT]]:
		_cylinder(dish[0], 0.9, 0.18, Mats.surface(HULL, "metal", 0.4, 0.5), dish[1])
	_box(Vector3(0.0, 35.6, 0.0), Vector3(0.4, 0.4, 0.4), Mats.glow(Color(1.0, 0.25, 0.2), 8.0), false)
	var beacon := OmniLight3D.new()
	beacon.position = Vector3(0.0, 35.6, 0.0)
	beacon.light_color = Color(1.0, 0.3, 0.25)
	beacon.light_energy = 4.0
	beacon.omni_range = 18.0
	add_child(beacon)

# --- Glass bridges ---------------------------------------------------------------
# Roof to roof across the avenue, fifty metres with nothing to hide behind.
# The floor and rails are glass: you can see who is under you, and they you.

func _glass_bridge(x: float) -> void:
	var steel := Mats.surface(Color(0.2, 0.21, 0.23), "metal", 0.45, 0.8)
	var glass := Mats.glass(Color(0.62, 0.86, 0.92))
	var near := -31.0 + 6.35
	var far := 31.0 - 6.35
	var length := far - near
	_box(Vector3(x, ROOF - 0.05, 0.0), Vector3(4.0, 0.1, length), glass)
	for side: float in [-1.0, 1.0]:
		_box(Vector3(x + side * 2.1, ROOF - 0.3, 0.0), Vector3(0.28, 0.6, length), steel, false, false, 0.0, 0.03)
		_box(Vector3(x + side * 2.1, ROOF - 0.62, 0.0), Vector3(0.1, 0.05, length - 0.4), Mats.glow(TEAL.lightened(0.3), 2.5), false)
		_box(Vector3(x + side * 2.02, ROOF + 0.55, 0.0), Vector3(0.05, 1.1, length), glass, true, false)
		_box(Vector3(x + side * 2.02, ROOF + 1.12, 0.0), Vector3(0.1, 0.07, length), steel, false)
	var z := near
	while z <= far + 0.01:
		_box(Vector3(x, ROOF - 0.17, z), Vector3(4.2, 0.24, 0.16), steel, false)
		z += length / 12.0
	for pier: float in [-9.0, 9.0]:
		for side: float in [-1.0, 1.0]:
			_box(Vector3(x + side * 2.3, (ROOF - 0.6) * 0.5, pier), Vector3(0.5, ROOF - 0.6, 0.5), steel, true, true, 0.0, 0.05)
		_box(Vector3(x, ROOF - 0.75, pier), Vector3(5.1, 0.3, 0.5), steel, false, false, 0.0, 0.04)
		_box(Vector3(x, 0.3, pier), Vector3(5.6, 0.6, 1.1), Mats.wall(HULL_DARK, OCHRE, 0.3, 1.2, 0.7), true, true, 0.0, 0.06)

# --- The depot --------------------------------------------------------------------
# A freight hangar on the south-east lot: one big bay door onto the avenue,
# a side door on each flank and one at the back, a raised deck inside with the
# vault on it.

func _depot() -> void:
	var x0 := DEPOT.position.x
	var z0 := DEPOT.position.y
	var x1 := DEPOT.end.x
	var z1 := DEPOT.end.y
	var floor_y := 0.12
	var wall_mat := Mats.wall(HULL, RUST, 1.3, 2.5, 0.65)
	_shell(x0, z0, x1, z1, 8.0, {
		"n": [[33.0, 10.0, 5.5]], "w": [[52.0, 2.6, 2.9]], "e": [[38.0, 2.6, 2.9]], "s": [[26.0, 2.6, 2.9]],
	}, wall_mat, Color(0.33, 0.35, 0.37))
	_box(Vector3((x0 + x1) * 0.5, floor_y * 0.5 - 0.05, (z0 + z1) * 0.5), Vector3(x1 - x0 + 1.2, floor_y + 0.1, z1 - z0 + 1.2),
		Mats.wall(Color(0.33, 0.35, 0.37), Color.BLACK, 0.0, 2.0, 0.3, 0.25, 0.7))
	_sign("DEPOT 4", Vector3(33.0, 6.7, z0 - 0.26), PI, 1.5, Color(0.16, 0.17, 0.19))
	_sign("VAULT", Vector3(x1 - 0.26, 5.2, 66.0), PI * 0.5, 0.5, RUST.lightened(0.2), true)
	# Hazard chevrons across the bay threshold.
	for i in 11:
		_box(Vector3(28.4 + i * 0.92, floor_y + 0.012, z0 + 0.9), Vector3(0.3, 0.02, 1.5), Mats.surface(OCHRE, "plain", 0.8), false, false, 0.6)
	# Freight on the floor: containers to fight round, a rover, crates.
	kit.add("container_coral", Vector3(25.2, floor_y, 37.0), 0.0)
	kit.add("container_white", Vector3(25.2, floor_y, 44.0), 0.0)
	kit.add("container_teal", Vector3(31.5, floor_y, 58.0), PI * 0.5)
	kit.add("cargo_rover", Vector3(34.0, floor_y, 33.0), 0.4)
	_crate(41.5, 31.0, Vector3(1.6, 1.6, 1.6), RUST, 0.3, floor_y)
	_crate(43.0, 32.8, Vector3(1.2, 1.2, 1.2), STEEL, -0.2, floor_y)
	_crate(30.0, 50.0, Vector3(1.4, 1.4, 1.4), OCHRE, 0.5, floor_y)
	_crate(24.0, 68.0, Vector3(1.8, 1.4, 1.4), STEEL, 0.1, floor_y)
	_barrier(33.0, 42.0, 3.2)
	_barrier(28.0, 64.0, 3.0, PI * 0.5)
	# The raised deck over the south-east corner, and the ramp up to it.
	var deck := Mats.surface(HULL_DARK, "metal", 0.5, 0.6)
	var deck_y := 3.3
	_box(Vector3(40.8, deck_y - 0.15, 59.5), Vector3(9.8, 0.3, 22.0), deck)
	for post: Vector2 in [Vector2(36.2, 49.0), Vector2(36.2, 59.5), Vector2(36.2, 70.0), Vector2(41.0, 49.0)]:
		_box(Vector3(post.x, (deck_y - 0.3) * 0.5, post.y), Vector3(0.3, deck_y - 0.3, 0.3), deck)
	_slope(Vector3(37.6, floor_y - 0.02, 39.0), Vector3(37.6, deck_y, 48.6), 2.8, deck)
	_box(Vector3(35.95, deck_y + 0.5, 60.0), Vector3(0.12, 1.0, 21.0), Mats.surface(OCHRE, "plain", 0.5))
	_box(Vector3(42.4, deck_y + 0.5, 48.55), Vector3(6.6, 1.0, 0.12), Mats.surface(OCHRE, "plain", 0.5))
	_crate(40.0, 55.0, Vector3(1.3, 1.3, 1.3), STEEL, 0.2, deck_y)
	for z: float in [34.0, 50.0, 66.0]:
		_lamp(Vector3(31.0, 7.4, z), LIGHT_WARM, 3.0, 16.0, z == 50.0)
	_lamp(Vector3(41.0, deck_y - 0.5, 60.0), LIGHT_COOL, 1.2, 8.0)
	_lamp(Vector3(42.0, 7.4, 66.0), Color(1.0, 0.35, 0.25), 1.6, 9.0)
	_mark(Vector3(43.5, deck_y, 68.5), "vault", -PI * 0.5)
	_mark(Vector3(44.6, deck_y, 52.0), "locker", -PI * 0.5)
	_mark(Vector3(44.2, floor_y, 60.0), "locker", -PI * 0.5)
	_mark(Vector3(40.0, floor_y, 72.8), "crate")
	_mark(Vector3(21.2, floor_y, 30.0), "crate", PI * 0.5)
	_mark(Vector3(21.2, floor_y, 58.0), "locker", PI * 0.5)

# --- The cordon -------------------------------------------------------------------
# The district is sealed: a wall down the middle of the four surrounding
# streets, gated where the avenue and the boulevard cross it.

func _cordon() -> void:
	var wall_mat := Mats.wall(HULL_DARK, Color(0.17, 0.18, 0.2), 1.4, 3.0, 0.75, 0.2)
	var hazard := Mats.surface(OCHRE, "plain", 0.6)
	var gate := Mats.wall(Color(0.16, 0.17, 0.19), RUST, 0.6, 1.5, 0.5, 0.5)
	# The outer wall: unbroken along the north, a gateway in each other side.
	var gateway: Array = [[0.0, 12.0, 5.2]]
	for side: Array in [[Vector2(-HALF.x, -HALF.y), Vector2(HALF.x, -HALF.y), []], [Vector2(-HALF.x, HALF.y), Vector2(HALF.x, HALF.y), gateway],
			[Vector2(-HALF.x, -HALF.y), Vector2(-HALF.x, HALF.y), gateway], [Vector2(HALF.x, -HALF.y), Vector2(HALF.x, HALF.y), gateway]]:
		_wall(side[0], side[1], 6.5, wall_mat, side[2], 1.0)
	# The cordon across the north and south of the centre, open where the
	# boulevard runs through it. The gates stand in those openings.
	for z: float in [-INNER, INNER]:
		_wall(Vector2(-HALF.x, z), Vector2(HALF.x, z), 6.5, wall_mat, [[0.0, 12.0, 5.2]], 1.0)
	for corner: Vector2 in [Vector2(-HALF.x, -HALF.y), Vector2(HALF.x, -HALF.y), Vector2(-HALF.x, HALF.y), Vector2(HALF.x, HALF.y),
			Vector2(-HALF.x, -INNER), Vector2(HALF.x, -INNER), Vector2(-HALF.x, INNER), Vector2(HALF.x, INNER)]:
		_box(Vector3(corner.x, 4.5, corner.y), Vector3(2.4, 9.0, 2.4), wall_mat)
		_box(Vector3(corner.x, 9.2, corner.y), Vector3(0.5, 0.4, 0.5), Mats.glow(RUST, 6.0), false)
	# Gates: [centre, along x?, label]. Each slides open from a button on either
	# side. North and south are inside the cordon; the other three lead out of
	# the city onto the island.
	for spec: Array in [[Vector3(-HALF.x, 0.0, 0.0), false, "WEST ROAD"], [Vector3(HALF.x, 0.0, 0.0), false, "EAST ROAD"],
			[Vector3(0.0, 0.0, -INNER), true, "GATE  N"], [Vector3(0.0, 0.0, INNER), true, "GATE  S"], [Vector3(0.0, 0.0, HALF.y), true, "SOUTH ROAD"]]:
		var at: Vector3 = spec[0]
		var along_x: bool = spec[1]
		# The leaf runs back into the thickness of the wall.
		var leaf := _door(at, 0.0 if along_x else PI * 0.5, Vector3(12.3, 5.2, 0.36), Vector3(-12.1, 0.0, 0.0), false, "gate")
		leaf.material = gate
		leaf.travel = 3.2
		leaf.noise = 32.0
		for face: float in [-1.0, 1.0]:
			var out := Vector3(0.0, 0.0, face * 0.56) if along_x else Vector3(face * 0.56, 0.0, 0.0)
			var yaw := (0.0 if face > 0.0 else PI) if along_x else (PI * 0.5 if face > 0.0 else -PI * 0.5)
			var beside := Vector3(7.3, 0.0, 0.0) if along_x else Vector3(0.0, 0.0, -7.3)
			_switch(at + beside + out * 1.02 + Vector3(0.0, 1.3, 0.0), yaw, [leaf])
			_box(at + beside + out * 0.95 + Vector3(0.0, 2.0, 0.0), Vector3(0.7, 0.08, 0.06) if along_x else Vector3(0.06, 0.08, 0.7), hazard, false)
			_box(at + out + Vector3(0.0, 5.35, 0.0), Vector3(12.6, 0.3, 0.2) if along_x else Vector3(0.2, 0.3, 12.6), hazard, false)
			for post: float in [-6.3, 6.3]:
				_box(at + out + (Vector3(post, 3.4, 0.0) if along_x else Vector3(0.0, 3.4, post)), Vector3(0.6, 6.8, 0.5) if along_x else Vector3(0.5, 6.8, 0.6), wall_mat, false, false, 0.0, 0.05)
			_sign(spec[2], at + out * 1.3 + Vector3(0.0, 5.95, 0.0), yaw, 0.7, Color(0.75, 0.74, 0.7), false)

# --- Doors ------------------------------------------------------------------------
# Every building's doorway has a sliding door with a button outside and in.
# About one in three stands open at the start. The depot's bay is a two-leaf
# shutter; its three side doors are the quiet way in.

func _doors() -> void:
	var n := 0
	for column in COLUMNS:
		for row in ROWS:
			if DEPOT.grow(3.0).has_point(Vector2(column, row)):
				continue
			n += 1
			var front := 1.0 if row < 0.0 else -1.0   # which way the doorway faces
			var depth := 7.88 if TOWERS.has(Vector2(column, row)) else 5.88
			var door := _door(Vector3(column, 0.0, row + front * (depth - 0.27)), 0.0, Vector3(2.56, 3.34, 0.12), Vector3(-2.5, 0.0, 0.0), n % 3 == 1)
			_switch(Vector3(column + 1.8, 1.25, row + front * (depth + 0.2)), 0.0 if front > 0.0 else PI, [door])
			_switch(Vector3(column + 1.8, 1.25, row + front * (depth - 0.2)), PI if front > 0.0 else 0.0, [door])
	var x0 := DEPOT.position.x
	var z0 := DEPOT.position.y
	var x1 := DEPOT.end.x
	var z1 := DEPOT.end.y
	var plate := Mats.wall(Color(0.24, 0.25, 0.27), OCHRE, 0.7, 1.25, 0.5, 0.5)
	var bay: Array[Door] = []
	for half: float in [-1.0, 1.0]:
		var leaf := _door(Vector3(33.0 + half * 2.52, 0.0, z0 + 0.34), 0.0, Vector3(5.06, 5.5, 0.2), Vector3(half * 5.0, 0.0, 0.0), false, "shutter")
		leaf.material = plate
		leaf.travel = 2.0
		leaf.noise = 22.0
		bay.append(leaf)
	_switch(Vector3(38.7, 1.3, z0 - 0.27), PI, bay)
	_switch(Vector3(38.7, 1.3, z0 + 0.27), 0.0, bay)
	var side := Vector3(2.7, 2.96, 0.12)
	var west := _door(Vector3(x0 + 0.3, 0.0, 52.0), PI * 0.5, side, Vector3(-2.65, 0.0, 0.0))
	_switch(Vector3(x0 - 0.27, 1.25, 53.9), -PI * 0.5, [west])
	_switch(Vector3(x0 + 0.27, 1.25, 53.9), PI * 0.5, [west])
	var east := _door(Vector3(x1 - 0.3, 0.0, 38.0), PI * 0.5, side, Vector3(-2.65, 0.0, 0.0))
	_switch(Vector3(x1 + 0.27, 1.25, 39.9), PI * 0.5, [east])
	_switch(Vector3(x1 - 0.27, 1.25, 39.9), -PI * 0.5, [east])
	var south := _door(Vector3(26.0, 0.0, z1 - 0.3), 0.0, side, Vector3(-2.65, 0.0, 0.0))
	_switch(Vector3(27.9, 1.25, z1 + 0.27), 0.0, [south])
	_switch(Vector3(27.9, 1.25, z1 - 0.27), PI, [south])

# --- Past the gates ---------------------------------------------------------------
# North and south of the cordon the city carries on for a block: four more
# buildings each side, the boulevard between them and a service lane behind.
# Quieter than the centre, with a third way out at the far end of the north road.

func _outskirts() -> void:
	for far: float in [-1.0, 1.0]:
		# The boulevard beyond the gate: cover to work up it from the gate.
		kit.add("container_white" if far < 0.0 else "container_coral", Vector3(-8.0 * far, 0.0, far * 90.0), 0.25)
		kit.add("container_teal", Vector3(10.0 * far, 0.0, far * 99.0), PI * 0.5 - 0.1)
		kit.add("cargo_rover", Vector3(-13.0 * far, 0.0, far * 103.0), 0.8 * far)
		_barrier(3.0 * far, far * 86.5, 3.2)
		_barrier(-16.0, far * 94.0, 3.2, PI * 0.5)
		_barrier(17.0, far * 92.0, 3.2, PI * 0.5)
		_crate(15.5, far * 104.0, Vector3(1.5, 1.5, 1.5), RUST, 0.4)
		_crate(16.8, far * 105.3, Vector3(1.1, 1.1, 1.1), STEEL, 0.1)
		# The service lane behind the buildings, and the gaps between them.
		for x: float in [-49.5, 49.5]:
			_barrier(x, far * 96.0, 3.2)
			_crate(x - 2.0 * far, far * 106.5, Vector3(1.3, 1.3, 1.3), OCHRE if x < 0.0 else STEEL, 0.3)
		kit.add("container_coral" if far < 0.0 else "container_white", Vector3(-30.0 * far, 0.0, far * 107.0), 0.05)
		kit.add("container_teal", Vector3(62.0 * far, 0.0, far * 106.5), -0.1)
		for x: float in [-70.0, -20.0, 28.0, 74.0]:
			_lamp(Vector3(x, 5.6, far * 110.9), LIGHT_WARM if far < 0.0 else LIGHT_COOL, 2.0, 13.0)
		_mark(Vector3(-49.5 * far, 0.0, far * 109.5), "locker", PI if far > 0.0 else 0.0)
		_mark(Vector3(24.0 * far, 0.0, far * 109.5), "crate", PI if far > 0.0 else 0.0)
		_mark(Vector3(-80.5, 0.0, far * 96.0), "crate", PI * 0.5)
		_mark(Vector3(80.5, 0.0, far * 100.0), "locker", -PI * 0.5)
		_mark(Vector3(49.5, 0.0, far * 87.0), "crate", 0.0 if far > 0.0 else PI)
	_sign("NORTH ROAD", Vector3(0.0, 4.4, -HALF.y + 0.55), 0.0, 0.9, TEAL.lightened(0.35), true)

# Grass on whatever bare ground the kit leaves between its pavements.
func _grass() -> void:
	var grass := Grass.new()
	grass.name = "Grass"
	grass.area = Rect2(-HALF.x + 1.0, -HALF.y + 1.0, HALF.x * 2.0 - 2.0, HALF.y * 2.0 - 2.0)
	add_child(grass)

# --- Streets ------------------------------------------------------------------------
# Hard cover so the avenue and the boulevard can be crossed, not just watched.

func _streets() -> void:
	# The avenue, west and east of the spire.
	kit.add("container_teal", Vector3(-38.0, 0.0, -6.0), 0.2)
	kit.add("container_white", Vector3(-46.0, 0.0, 8.0), PI * 0.5 + 0.1)
	kit.add("container_coral", Vector3(42.0, 0.0, -9.0), PI * 0.5)
	kit.add("container_teal", Vector3(52.0, 0.0, 6.0), -0.15)
	kit.add("cargo_rover", Vector3(-27.0, 0.0, 10.0), 1.2)
	kit.add("cargo_rover", Vector3(30.0, 0.0, -12.0), -0.6)
	for spot: Array in [[-30.0, -10.0, 0.0], [-54.0, -4.0, PI * 0.5], [-72.0, 6.0, PI * 0.5], [28.0, 10.0, 0.3], [60.0, -6.0, PI * 0.5], [72.0, 5.0, PI * 0.5]]:
		_barrier(spot[0], spot[1], 3.2, spot[2])
	# The boulevard, north and south.
	kit.add("container_white", Vector3(-7.0, 0.0, -34.0), 0.0)
	kit.add("container_coral", Vector3(8.0, 0.0, -52.0), PI * 0.5)
	kit.add("container_teal", Vector3(-9.0, 0.0, 40.0), 0.1)
	kit.add("container_white", Vector3(6.0, 0.0, 58.0), PI * 0.5)
	kit.add("cargo_rover", Vector3(9.0, 0.0, -30.0), 0.3)
	for spot: Array in [[6.0, -24.0, 0.0], [-10.0, -62.0, 0.2], [0.0, -70.0, 0.0], [10.0, 28.0, 0.0], [-6.0, 68.0, 0.0], [12.0, 70.0, PI * 0.5]]:
		_barrier(spot[0], spot[1], 3.2, spot[2])
	_crate(-12.0, -20.0, Vector3(1.4, 1.4, 1.4), OCHRE, 0.4)
	_crate(-13.3, -19.0, Vector3(1.2, 1.2, 1.2), STEEL, 0.1)
	_crate(14.0, 22.0, Vector3(1.6, 1.6, 1.6), RUST, 0.6)
	# The two back streets.
	for z: float in [-46.5, 46.5]:
		for x: float in [-49.5, 49.5]:
			if z > 0.0 and x > 0.0:
				continue   # the depot's flank
			_barrier(x, z, 3.2, PI * 0.5)
			_crate(x + 3.0, z + 4.0, Vector3(1.3, 1.3, 1.3), STEEL, 0.3)
	_mark(Vector3(-49.5, 0.0, -41.0), "crate")
	_mark(Vector3(49.5, 0.0, -52.0), "crate")
	_mark(Vector3(-49.5, 0.0, 52.0), "crate")
	_mark(Vector3(-78.0, 0.0, -20.0), "crate", PI * 0.5)
	_mark(Vector3(78.0, 0.0, 22.0), "crate", -PI * 0.5)
	_mark(Vector3(-20.0, 0.0, 76.0), "crate")

# The kit's ground floors are an empty room with a counter. Each gets a lit
# ceiling strip, shelving down one side, a bench, and something to search.
func _interiors() -> void:
	var n := 0
	for column in COLUMNS:
		for row in ROWS:
			if DEPOT.grow(3.0).has_point(Vector2(column, row)):
				continue
			n += 1
			var tower := TOWERS.has(Vector2(column, row))
			var back := -1.0 if row < 0.0 else 1.0   # which way the back wall is
			var half_x := 8.3 if tower else 6.3
			var half_z := 7.5 if tower else 5.5
			var tint := LIGHT_WARM if n % 2 == 0 else LIGHT_COOL
			for offset: float in [-0.45, 0.45]:
				_box(Vector3(column + offset * half_x, 4.86, row), Vector3(0.3, 0.06, half_z * 1.3), Mats.glow(tint, 1.4), false)
			var light := OmniLight3D.new()
			light.position = Vector3(column, 4.2, row)
			light.light_color = tint
			light.light_energy = 4.5
			light.omni_range = 13.0 if tower else 11.0
			light.omni_attenuation = 0.8
			light.distance_fade_enabled = true
			light.distance_fade_begin = 70.0
			light.distance_fade_length = 20.0
			add_child(light)
			# Shelving down the west wall, a lit bench by the east one.
			for i in 3:
				_rack(column - half_x + 0.3, row + back * (0.6 + i * 1.3), PI * 0.5)
			_box(Vector3(column + half_x - 0.5, 0.5, row + back * 2.2), Vector3(1.0, 1.0, 3.2), Mats.surface(Color(0.88, 0.88, 0.87), "plain", 0.4, 0.1), true, true, 0.0, 0.04)
			_box(Vector3(column + half_x - 0.5, 1.03, row + back * 2.2), Vector3(0.8, 0.04, 3.0), Mats.glow(tint, 0.7), false)
			_box(Vector3(column, 0.012, row - back * (half_z - 1.2)), Vector3(half_x * 1.7, 0.02, 0.22), Mats.surface(OCHRE, "plain", 0.8), false)
			_mark(Vector3(column + 4.0 * back, 0.0, row + (half_z - 0.6) * back), "locker" if n % 3 == 0 else "crate", 0.0 if back < 0.0 else PI)

func _squads_and_exits() -> void:
	squads.append({"members": ["trooper", "trooper", "lobber"], "points": [
		Vector3(-9.0, 0.0, 9.0), Vector3(9.0, 0.0, -9.0), Vector3(-9.0, 0.0, -9.0), Vector3(9.0, 0.0, 9.0)]})
	squads.append({"members": ["marksman"], "points": [Vector3(-4.6, 5.25, 4.6), Vector3(4.6, 5.25, -4.6), Vector3(4.6, 5.25, 4.6)]})
	squads.append({"members": ["trooper", "bulwark", "rusher", "trooper"], "points": [
		Vector3(33.0, 0.2, 36.0), Vector3(30.0, 0.2, 52.0), Vector3(24.0, 0.2, 62.0), Vector3(36.0, 0.2, 68.0)]})
	squads.append({"members": ["overseer", "trooper"], "points": [Vector3(41.0, 3.35, 54.0), Vector3(41.0, 3.35, 66.0), Vector3(38.0, 3.35, 60.0)]})
	squads.append({"members": ["trooper", "rusher"], "points": [Vector3(-52.0, 0.0, -46.5), Vector3(-20.0, 0.0, -46.5), Vector3(-66.0, 0.0, -46.5)]})
	squads.append({"members": ["trooper", "trooper", "lobber"], "points": [Vector3(52.0, 0.0, -46.5), Vector3(20.0, 0.0, -46.5), Vector3(70.0, 0.0, -46.5)]})
	squads.append({"members": ["trooper", "rusher", "trooper"], "points": [Vector3(-52.0, 0.0, 46.5), Vector3(-20.0, 0.0, 46.5), Vector3(-70.0, 0.0, 46.5)]})
	squads.append({"members": ["bulwark", "trooper"], "points": [Vector3(-42.0, 0.0, 2.0), Vector3(-30.0, 0.0, 12.0), Vector3(-58.0, 0.0, -8.0)]})
	squads.append({"members": ["trooper", "lobber"], "points": [Vector3(48.0, 0.0, -2.0), Vector3(62.0, 0.0, 10.0), Vector3(36.0, 0.0, 12.0)]})
	squads.append({"members": ["marksman"], "points": [Vector3(66.0, ROOF + 0.05, -10.0), Vector3(66.0, ROOF + 0.05, 10.0)]})
	# The ways off the island are out at the sites: the kit's own six.
	for spec: Dictionary in kit.manifest["extractions"]:
		var at := kit.to_level(VesperKit._v3(spec["position"]))
		extracts.append({"position": Vector3(at.x, kit.height(at.x, at.z), at.z), "name": spec["name"]})
	# Past the gates.
	squads.append({"members": ["trooper", "marksman", "trooper"], "points": [Vector3(0.0, 0.0, -94.0), Vector3(-20.0, 0.0, -106.0), Vector3(20.0, 0.0, -106.0)]})
	squads.append({"members": ["bulwark", "rusher"], "points": [Vector3(-49.5, 0.0, -100.0), Vector3(-70.0, 0.0, -106.5), Vector3(-49.5, 0.0, -90.0)]})
	squads.append({"members": ["trooper", "lobber", "trooper"], "points": [Vector3(4.0, 0.0, 96.0), Vector3(24.0, 0.0, 106.0), Vector3(-22.0, 0.0, 106.0)]})
	squads.append({"members": ["rusher", "trooper"], "points": [Vector3(49.5, 0.0, 100.0), Vector3(70.0, 0.0, 106.5), Vector3(49.5, 0.0, 90.0)]})
	extracts.append({"position": Vector3(0.0, 0.0, -106.0), "name": "North road"})

# --- The rest of the island ------------------------------------------------------
# Each of the kit's other districts is a patch of level ground with a landmark
# and little else. This game builds a small colony on it: up to six more of the
# kit's buildings (a different mix at each place) with doors, lamps, shelving
# and something to search, cover in the street between the two rows, the
# kit's own loot cases as containers, a squad or two, and a place to start.
# The two smallest are left as they are: outposts.

func _site(index: int) -> void:
	var site: Array = SITES[index]
	var middle := kit.to_level(site[1])
	var reach: float = site[2]
	var kinds: Array = site[3]
	origin = middle
	places.append({"name": site[0], "position": middle})
	_islands.append(AABB(Vector3(middle.x - reach, middle.y - 3.0, middle.z - reach), Vector3(reach * 2.0, 7.5, reach * 2.0)))
	# What the kit already stands here, so nothing is built on top of it.
	var taken: Array[Vector3] = []     # (x, z about the middle, radius it needs)
	for placement: Dictionary in kit.manifest["placements"]:
		var asset: String = placement["asset"]
		if asset in SCENERY_ONLY or asset.begins_with("canopy"):
			continue
		var at := kit.to_level(VesperKit._v3(placement["position"])) - middle
		if absf(at.x) < reach + 20.0 and absf(at.z) < reach + 20.0:
			var room := 24.0 if asset in ["heliograph", "observatory", "conservatory_frame", "hangar"] else (9.0 if asset.begins_with("container") or asset == "pipeline" else 5.0)
			taken.append(Vector3(at.x, at.z, room))
	var free := func(x: float, z: float, room: float) -> bool:
		for spot in taken:
			if Vector2(x - spot.x, z - spot.y).length() < room + spot.z:
				return false
		return true
	var built := 0
	var first := Vector3.ZERO
	for i in SLOTS.size():
		var slot := SLOTS[i]
		if kinds.is_empty() or not free.call(slot.x, slot.y, 12.0):
			continue
		built += 1
		kit.add(kinds[i % kinds.size()], middle + Vector3(slot.x, 0.0, slot.y), 0.0 if slot.z > 0.0 else PI)
		_fit(slot.x, slot.y, slot.z, index * 7 + i, "vault" if built == 2 and index % 2 == 0 else ("locker" if i % 2 == 0 else "crate"))
		taken.append(Vector3(slot.x, slot.y, 10.0))
		if built == 1:
			first = slot
	if built > 0:
		_sign((site[0] as String).to_upper(), Vector3(first.x, 4.5, first.y + first.z * 6.1), 0.0 if first.z > 0.0 else PI, 0.55, TEAL.lightened(0.4), true)
	# The street between the rows: cover, lamps, a container or two.
	var tints: Array[String] = ["container_teal", "container_coral", "container_white"]
	for spot: Array in [[-18.0, 6.0, 0.0], [15.0, -7.0, 0.0], [0.0, 13.0, PI * 0.5], [-40.0, -4.0, PI * 0.5], [42.0, 5.0, PI * 0.5], [22.0, 12.0, 0.2], [-8.0, -12.0, 0.0]]:
		if reach >= 60.0 and free.call(spot[0], spot[1], 2.5):
			_barrier(spot[0], spot[1], 3.2, spot[2])
			taken.append(Vector3(spot[0], spot[1], 2.0))
	for spot: Array in [[-28.0, 2.0, 0.3], [30.0, -3.0, PI * 0.5 + 0.1], [6.0, -2.0, -0.2]]:
		if reach >= 60.0 and free.call(spot[0], spot[1], 6.0):
			kit.add(tints[(index + int(spot[0])) % 3], middle + Vector3(spot[0], 0.0, spot[1]), spot[2])
			taken.append(Vector3(spot[0], spot[1], 5.0))
	for x: float in [-24.0, 24.0]:
		if free.call(x, 0.0, 1.5):
			_lamp(Vector3(x, 5.2, 0.0), LIGHT_WARM if index % 2 == 0 else LIGHT_COOL, 2.0, 13.0, false, false)
			_box(Vector3(x, 2.6, 0.0), Vector3(0.14, 5.2, 0.14), Mats.surface(Color(0.16, 0.17, 0.19), "metal", 0.5, 0.6))
	origin = Vector3.ZERO
	# The kit's own loot cases, wherever they are not now inside a building.
	for spec: Dictionary in kit.manifest["loot"]:
		var at := kit.to_level(VesperKit._v3(spec["position"]))
		var local := at - middle
		if absf(local.x) > reach - 3.0 or absf(local.z) > reach - 3.0:
			continue
		var clear := true
		for slot in SLOTS:
			if not kinds.is_empty() and absf(local.x - slot.x) < 8.5 and absf(local.z - slot.y) < 8.0:
				clear = false
		if clear:
			_mark(Vector3(at.x, middle.y, at.z), "crate", local.x * 0.3)
	# Who holds it.
	var base := middle + Vector3(0.0, 0.05, 0.0)
	if reach >= 60.0:
		squads.append({"members": ["trooper", "trooper", "lobber"] if index % 2 == 0 else ["trooper", "rusher", "trooper"],
			"points": [base + Vector3(-12.0, 0.0, 2.0), base + Vector3(14.0, 0.0, -3.0), base + Vector3(0.0, 0.0, 16.0)]})
		squads.append({"members": ["bulwark", "trooper"] if index % 3 != 1 else ["marksman", "trooper"],
			"points": [base + Vector3(-44.0, 0.0, 8.0), base + Vector3(-50.0, 0.0, -40.0), base + Vector3(-16.0, 0.0, -50.0)]})
		for corner: Vector2 in [Vector2(-52.0, -52.0), Vector2(52.0, 52.0), Vector2(52.0, -52.0)]:
			reinforce_points.append(middle + Vector3(corner.x, 0.2, corner.y))
		_starts.append([middle + Vector3(-48.0, 0.4, 50.0), atan2(-48.0, 50.0)])
		var grass := Grass.new()
		grass.name = "Grass%d" % (index + 1)
		grass.area = Rect2(middle.x - reach, middle.z - reach, reach * 2.0, reach * 2.0)
		grass.density = 7.0
		grass.reach = Vector2(middle.y + 3.0, middle.y - 4.0)
		grass.seed_value = 40 + index
		add_child(grass)
	else:
		squads.append({"members": ["marksman", "trooper"], "points": [base + Vector3(-10.0, 0.0, 10.0), base + Vector3(12.0, 0.0, 14.0), base + Vector3(0.0, 0.0, 24.0)]})

# One added building made usable: its door and buttons, a lit ceiling strip,
# shelving down one side, a bench, and a container against the back wall.
# (x, z) is its middle about the site's; `front` is +1 when its door faces south.
func _fit(x: float, z: float, front: float, n: int, kind: String) -> void:
	var door := _door(Vector3(x, 0.0, z + front * 5.61), 0.0, Vector3(2.56, 3.34, 0.12), Vector3(-2.5, 0.0, 0.0), n % 3 == 1)
	_switch(Vector3(x + 1.8, 1.25, z + front * 6.08), 0.0 if front > 0.0 else PI, [door])
	_switch(Vector3(x + 1.8, 1.25, z + front * 5.68), PI if front > 0.0 else 0.0, [door])
	var back := -front
	var tint := LIGHT_WARM if n % 2 == 0 else LIGHT_COOL
	for offset: float in [-0.45, 0.45]:
		_box(Vector3(x + offset * 6.3, 4.86, z), Vector3(0.3, 0.06, 7.1), Mats.glow(tint, 1.4), false)
	var light := OmniLight3D.new()
	light.position = origin + Vector3(x, 4.2, z)
	light.light_color = tint
	light.light_energy = 4.5
	light.omni_range = 11.0
	light.omni_attenuation = 0.8
	light.distance_fade_enabled = true
	light.distance_fade_begin = 70.0
	light.distance_fade_length = 20.0
	add_child(light)
	for i in 3:
		_rack(x - 6.0, z + back * (0.6 + i * 1.3), PI * 0.5)
	_box(Vector3(x + 5.8, 0.5, z + back * 2.2), Vector3(1.0, 1.0, 3.2), Mats.surface(Color(0.88, 0.88, 0.87), "plain", 0.4, 0.1), true, true, 0.0, 0.04)
	_box(Vector3(x + 5.8, 1.03, z + back * 2.2), Vector3(0.8, 0.04, 3.0), Mats.glow(tint, 0.7), false)
	_mark(Vector3(x + 4.0 * back, 0.0, z + 4.9 * back), kind, 0.0 if back < 0.0 else PI)

# --- A colony, not a housing estate ---------------------------------------------
# What the kit's blocks lack is anything on them. Every building in the town
# gets a lit band under its roofline, and something on the roof: a mast with a
# beacon, and a radome or a pair of solar wings. Towers get a spire. None of
# it is solid.

func _colony_gear() -> void:
	var steel := Mats.surface(Color(0.13, 0.14, 0.16), "metal", 0.5, 0.7)
	var shell := Mats.surface(Color(0.86, 0.87, 0.86), "plain", 0.35, 0.1)
	var cell := Mats.surface(Color(0.03, 0.06, 0.14), "metal", 0.15, 0.9)
	var n := 0
	for column in COLUMNS:
		for row in ROWS:
			if DEPOT.grow(3.0).has_point(Vector2(column, row)):
				continue
			n += 1
			var back := -1.0 if row < 0.0 else 1.0
			var glow := Mats.glow(TEAL.lightened(0.3) if n % 3 != 0 else Color(1.0, 0.55, 0.3), 2.4)
			if TOWERS.has(Vector2(column, row)):
				_box(Vector3(column, 47.5, row), Vector3(0.22, 11.0, 0.22), steel, false)
				_box(Vector3(column, 53.2, row), Vector3(0.45, 0.45, 0.45), Mats.glow(Color(1.0, 0.25, 0.2), 8.0), false)
				continue
			_box(Vector3(column, 5.02, row + back * 6.42), Vector3(14.5, 0.12, 0.08), glow, false)
			for side: float in [-1.0, 1.0]:
				_box(Vector3(column + side * 7.47, 5.02, row + back * 0.6), Vector3(0.08, 0.12, 11.4), glow, false)
			# Roof gear, kept to the back half so the roof routes stay clear.
			var mast := Vector3(column - 4.6, ROOF, row + back * 4.2)
			_box(mast + Vector3(0.0, 3.0, 0.0), Vector3(0.12, 6.0, 0.12), steel, false)
			_box(mast + Vector3(0.0, 4.6, 0.0), Vector3(1.4, 0.06, 0.06), steel, false)
			_box(mast + Vector3(0.0, 6.1, 0.0), Vector3(0.22, 0.22, 0.22), Mats.glow(Color(1.0, 0.3, 0.25), 6.0), false)
			if n % 2 == 0:
				var dome := MeshInstance3D.new()
				var ball := SphereMesh.new()
				ball.radius = 1.25
				ball.height = 2.5
				ball.radial_segments = 20
				ball.rings = 10
				dome.mesh = ball
				dome.material_override = shell
				dome.position = Vector3(column + 3.6, ROOF + 1.0, row + back * 3.8)
				add_child(dome)
				_box(Vector3(column + 3.6, ROOF + 0.15, row + back * 3.8), Vector3(1.9, 0.3, 1.9), steel, false, false, 0.0, 0.05)
			else:
				for wing: float in [-1.0, 1.0]:
					var panel := _box(Vector3(column + 3.4 + wing * 1.5, ROOF + 0.95, row + back * 3.8), Vector3(2.6, 0.06, 1.7), cell, false)
					panel.rotation.x = -back * 0.45
					_box(Vector3(column + 3.4 + wing * 1.5, ROOF + 0.45, row + back * 3.8), Vector3(0.1, 0.9, 0.1), steel, false)
