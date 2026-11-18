class_name CairnLevel
extends Level

# Cairn Divide: the whole valley of the Cairn Divide kit. Five abandoned
# colonies -- Hearth in the middle, Lichen Research, the Spillway, Crown Relay
# and the Old Quarry round it -- with a river gorge down the middle, two long
# glass crossings over it, trails between the colonies, guard posts on the
# trails and rock shelters in the hills.
#
# The houses, walkways, door leaves, terrain, firs and rocks come from the kit
# (res://cairn_divide, loaded through CairnKit). The kit also says where its
# doors and loot cases go; this file turns those into the game's own doors,
# buttons and containers, and adds what makes it a raid: cover in the yards,
# lamps, the posts and shelters, squads and exits.
#
# Axes: +x east, +z south. Hearth's shelf is y = 0 with its middle house at the
# origin; the other colonies sit higher (see DISTRICTS). Every house is 20 m
# wide and 16 deep, front door on the south side, stairs inside on the
# north-west, and most have a locked archive upstairs.
#
# Guards only know their own colony or post: each has its own island of
# navmesh, and the ground between them is the player's alone.

# Hearth Colony, in the kit's own coordinates.
const CENTRE := Vector3(0.0, 90.0, 0.0)
const CORE: float = 760.0           # half the side of the square you can walk
const UPPER: float = 5.0            # the upstairs floor of a house
# [name, middle (x, z), height of its shelf]
const DISTRICTS: Array[Array] = [
	["Hearth Colony", Vector2(0.0, 0.0), 0.0],
	["Lichen Research", Vector2(-300.0, -300.0), 40.0],
	["The Spillway", Vector2(340.0, -290.0), 10.0],
	["Crown Relay", Vector2(-285.0, 350.0), 70.0],
	["Old Quarry", Vector2(365.0, 305.0), 35.0],
]
const HEARTH := Rect2(-86.0, -72.0, 172.0, 156.0)
const HOUSES: Array[String] = ["habitation", "laboratory", "utility"]
# Guard posts on the trails: [name, (x, z), manned].
const POSTS: Array[Array] = [
	["Post 1", Vector2(-126.0, -124.0), true], ["Post 2", Vector2(-158.0, 160.0), true],
	["Bridge post", Vector2(252.0, -172.0), true], ["South crossing", Vector2(80.0, 96.0), false],
	["Post 5", Vector2(498.0, -100.0), true], ["High post", Vector2(-486.0, 150.0), false],
]
# Drone outposts out on the far slopes, where you can call a drone to fly you
# out: [name, (x, z) to look near].
const OUTPOSTS: Array[Array] = [
	["North drone pad", Vector2(-40.0, -600.0)], ["East drone pad", Vector2(620.0, 120.0)], ["West drone pad", Vector2(-600.0, -160.0)],
]
# Rock shelters in the hills: (x, z).
const SHELTERS: Array[Vector2] = [Vector2(-96.0, 138.0), Vector2(-66.0, -118.0), Vector2(440.0, 132.0), Vector2(-190.0, 20.0)]

var kit: CairnKit
var zones: Array[Dictionary] = []   # {"rect": Rect2, "ground": float}: one island of navmesh each
var _houses: Array[Vector3] = []    # every house, in level coordinates
var _vaults: int = 0
var _sites: Array[Vector2] = []     # where each post ended up
var _pads: Array[Vector3] = []      # where each drone outpost ended up (middle of the deck)

func build() -> void:
	separate_regions = true
	reinforce_range = 150.0
	minimap = load(CairnKit.ROOT + "art/textures/minimap.png")
	minimap_span = 2048.0
	for district: Array in DISTRICTS:
		var middle: Vector2 = district[1]
		var rect := HEARTH if middle == Vector2.ZERO else Rect2(middle - Vector2(78.0, 62.0), Vector2(156.0, 124.0))
		zones.append({"rect": rect, "ground": float(district[2])})
		places.append({"name": district[0], "position": Vector3(middle.x, district[2], middle.y)})
	kit = CairnKit.new()
	kit.name = "Kit"
	add_child(kit)
	kit.load_data()
	kit.ground(CENTRE, CORE)
	var rects: Array[Rect2] = []
	for zone in zones:
		rects.append(zone["rect"])
	for post: Array in POSTS:
		var site := _level_site(post[1])
		_sites.append(site)
		if post[2]:
			rects.append(Rect2(site - Vector2(20.0, 20.0), Vector2(40.0, 40.0)))
	for outpost: Array in OUTPOSTS:
		var site := _level_site(outpost[1], 13.0, 72)
		var top := -INF
		for dx in range(-13, 14, 13):
			for dz in range(-13, 14, 13):
				top = maxf(top, kit.height(site.x + dx, site.y + dz))
		_pads.append(Vector3(site.x, top + 0.3, site.y))
		rects.append(Rect2(site - Vector2(30.0, 30.0), Vector2(60.0, 60.0)))
	kit.skip = _leave_out
	kit.populate(rects)
	for placement: Dictionary in kit.manifest["placements"]:
		if placement["asset"] in HOUSES:
			_houses.append(kit.to_level(CairnKit._v3(placement["position"])))
	_edge()
	_doors()
	_loot()
	_rooms()
	_yards()
	for i in range(1, DISTRICTS.size()):
		_camp(i)
	for i in POSTS.size():
		_post(i)
	for i in SHELTERS.size():
		_shelter(i)
	for i in OUTPOSTS.size():
		_outpost(i)
	_grass()
	kit.flush()
	_squads_and_exits()
	_wilds()
	_placements()

# Thinner, clearer air than the plateau maps, and shadows that reach the trees.
func tune(env: Environment, sun: DirectionalLight3D) -> void:
	env.volumetric_fog_density = 0.0009
	env.volumetric_fog_albedo = Color(0.78, 0.86, 0.92)
	env.volumetric_fog_length = 260.0
	env.sdfgi_max_distance = 200.0
	sun.directional_shadow_max_distance = 170.0

# One island of navmesh per colony and manned post.
func bake() -> void:
	var boxes: Array[AABB] = []
	for zone in zones:
		var rect: Rect2 = zone["rect"]
		var ground: float = zone["ground"]
		# The top stops under the roofs, which nobody can reach.
		boxes.append(AABB(Vector3(rect.position.x, ground - 8.0, rect.position.y), Vector3(rect.size.x, 17.0, rect.size.y)))
	_bake_islands(boxes)

func _leave_out(asset: String, at: Vector3, _placement: Dictionary) -> bool:
	# Nothing grows through a post's deck.
	if asset != "fern" and asset != "alpine_fir":
		return false
	for site in _sites:
		if Vector2(at.x, at.z).distance_to(site) < 10.0:
			return true
	for pad in _pads:
		if absf(at.x - pad.x) < 24.0 and absf(at.z - pad.z + 8.0) < 32.0:
			return true
	return false

# The most level patch of ground within 28 m of a point, for a post's deck.
func _level_site(near: Vector2, half: float = 7.0, search: int = 28) -> Vector2:
	var best := near
	var least := INF
	var step := 4 if search <= 28 else 8
	var deep := half * 6.0 / 7.0
	for dx in range(-search, search + 1, step):
		for dz in range(-search, search + 1, step):
			var at := near + Vector2(dx, dz)
			var low := INF
			var high := -INF
			for corner: Vector2 in [Vector2(-half, -deep), Vector2(half, -deep), Vector2(-half, deep), Vector2(half, deep), Vector2.ZERO, Vector2(0, -deep), Vector2(0, deep)]:
				var h := kit.height(at.x + corner.x, at.y + corner.y)
				low = minf(low, h)
				high = maxf(high, h)
			if high - low < least:
				least = high - low
				best = at
	return best

# The edge of the map: nothing to see, you just cannot walk further.
func _edge() -> void:
	for side: Vector2 in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		var body := StaticBody3D.new()
		body.collision_layer = Layers.WORLD
		body.collision_mask = 0
		body.position = Vector3(side.x * CORE, 150.0, side.y * CORE)
		var shape := BoxShape3D.new()
		shape.size = Vector3(4.0 if side.x != 0.0 else CORE * 2.0, 700.0, 4.0 if side.y != 0.0 else CORE * 2.0)
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		add_child(body)

# --- Doors --------------------------------------------------------------------
# The kit lists every doorway: where, which way it faces, how wide, and whether
# it is an archive. Each becomes two of the game's sliding leaves wearing the
# kit's door model, with a button on either side of the wall.

func _doors() -> void:
	var leaf_model := kit.door_leaf()
	var n := 0
	for spec: Dictionary in kit.manifest["doors"]:
		var at := kit.to_level(CairnKit._v3(spec["position"]))
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
			# Left as they were when the place emptied: a third stand open.
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
		var kind := "crate"
		if int(spec["tier"]) == 3:
			# Every other archive holds a vault; the rest a locker.
			_vaults += 1
			kind = "vault" if _vaults % 2 == 1 else "locker"
			at.z -= 1.4   # against the archive's back wall
		elif int(spec["tier"]) == 2:
			kind = "locker"
		_mark(at, kind, 0.0)

# A lamp over each floor of each house. One in three has failed.
func _rooms() -> void:
	var n := 0
	for house in _houses:
		for floor_y: float in [0.0, UPPER]:
			n += 1
			if n % 3 == 0:
				continue
			var light := OmniLight3D.new()
			light.position = house + Vector3(2.0, floor_y + 3.6, 2.0)
			light.light_color = LIGHT_WARM if n % 2 == 0 else LIGHT_COOL
			light.light_energy = 2.6
			light.omni_range = 13.0
			light.omni_attenuation = 0.8
			light.shadow_enabled = false
			light.distance_fade_enabled = true
			light.distance_fade_begin = 80.0
			light.distance_fade_length = 25.0
			add_child(light)
	for district: Array in DISTRICTS:
		var middle: Vector2 = district[1]
		_sign((district[0] as String).to_upper(), Vector3(middle.x, float(district[2]) + 4.6, middle.y + 11.2), 0.0, 0.8, TEAL.lightened(0.4), true)

# --- Hearth -------------------------------------------------------------------
# The shelf between the houses is open ground. Cover to cross it: the square
# between the two rows, the salvage yard on the north side, the lanes down
# either flank, and the ground in front of the way out.

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
	# The flanks, and the ground in front of the exit.
	_cassette(-62.0, 14.0, PI * 0.5 + 0.1, HULL)
	_cassette(62.0, 20.0, PI * 0.5, RUST)
	_stack(-58.0, -8.0, 0.2)
	_stack(60.0, 2.0, -0.3)
	for spot: Array in [[-56.0, 30.0, 0.0], [-66.0, 44.0, PI * 0.5], [50.0, 48.0, 0.0], [66.0, -18.0, PI * 0.5], [46.0, -30.0, 0.0],
			[44.0, -46.0, 0.2], [-8.0, -54.0, 0.0], [8.0, -58.0, PI * 0.5], [-30.0, 62.0, 0.0], [20.0, 64.0, 0.2]]:
		_barrier(spot[0], spot[1], 3.2, spot[2])
	for spot: Vector2 in [Vector2(-18.0, -18.0), Vector2(18.0, 18.0), Vector2(0.0, 34.0), Vector2(-54.0, 18.0), Vector2(54.0, 18.0),
			Vector2(52.0, -34.0), Vector2(0.0, -60.0), Vector2(-56.0, 54.0), Vector2(48.0, 62.0), Vector2(-52.0, -40.0)]:
		_mast(spot.x, spot.y, int(spot.x + spot.y) % 3 != 0)
	_mark(Vector3(-58.0, 0.0, -10.2), "crate", 0.2)
	_mark(Vector3(62.0, 0.0, 16.6), "locker", PI * 0.5)
	_mark(Vector3(9.0, 0.0, 42.2), "crate", -0.4)
	_mark(Vector3(22.0, 0.0, -36.2), "crate", 0.2)
	_mark(Vector3(-62.0, 0.0, 17.6), "locker", PI * 0.5 + 0.1)
	_litter(Vector2(0.0, 20.0), 60.0, 11)

# --- The outer colonies -------------------------------------------------------
# Three houses in a row with a mast, pump house or gantry behind. Each gets the
# same kinds of cover as Hearth, laid out differently: mirrored on alternate
# colonies, with its own colours and its own wreckage.

func _camp(index: int) -> void:
	var middle: Vector2 = DISTRICTS[index][1]
	origin = Vector3(middle.x, DISTRICTS[index][2], middle.y)
	var flip := -1.0 if index % 2 == 0 else 1.0
	var tints: Array[Color] = [TEAL, OCHRE, RUST, HULL, TEAL]
	var tint := tints[index]
	for x: float in [-18.0, 18.0]:
		_barrier(x, 9.0, 3.0)
	for spot: Array in [[-20.0, 22.0, 0.0], [6.0, 27.0, PI * 0.5], [24.0, 35.0, 0.2], [-36.0, 39.0, 0.0], [42.0, 21.0, PI * 0.5],
			[-10.0, -19.0, 0.0], [22.0, -23.0, 0.3], [-42.0, -16.0, PI * 0.5], [52.0, -8.0, PI * 0.5], [-56.0, 4.0, PI * 0.5]]:
		_barrier(float(spot[0]) * flip, spot[1], 3.2, spot[2])
	_cassette(-8.0 * flip, 34.0, 0.15 * flip, tint)
	_cassette(34.0 * flip, -22.0, PI * 0.5 + 0.1, HULL if tint != HULL else RUST)
	if index >= 3:
		_cassette(-46.0 * flip, 24.0, PI * 0.5 - 0.2, OCHRE)
	_stack(12.0 * flip, 18.0, 0.3)
	_stack(-28.0 * flip, -22.0, -0.2)
	for spot: Vector2 in [Vector2(-18.0, -16.0), Vector2(18.0, 20.0), Vector2(-52.0, 12.0), Vector2(52.0, 12.0), Vector2(0.0, 44.0)]:
		_mast(spot.x * flip, spot.y, (index + int(spot.x)) % 3 != 0)
	_mark(Vector3(12.0 * flip, 0.0, 19.9), "crate", 0.3)
	_mark(Vector3(-28.0 * flip, 0.0, -23.9), "crate", -0.2)
	_mark(Vector3(34.0 * flip + 3.4, 0.0, -22.0), "locker", PI * 0.5 + 0.1)
	_litter(Vector2(0.0, 14.0), 56.0, 20 + index * 7)
	origin = Vector3.ZERO

# What was left lying about: scorched ground, rubble, a dropped panel or two.
func _litter(middle: Vector2, spread: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var soot := Mats.surface(Color(0.045, 0.04, 0.04), "plain", 0.95)
	var rubble := Mats.surface(Color(0.3, 0.29, 0.27), "plain", 0.9)
	var rust := Mats.surface(Color(0.16, 0.15, 0.14), "metal", 0.8, 0.3)
	for i in 16:
		var at := middle + Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread * 0.8, spread * 0.8))
		# Not inside a house: they stand on a 36 m grid, 21 m by 20.
		if absf(fposmod(at.x + 18.0, 36.0) - 18.0) < 12.5 and (absf(at.y) < 12.5 or absf(at.y - 36.0) < 12.5):
			continue
		match i % 3:
			0:
				_box(Vector3(at.x, 0.012, at.y), Vector3(rng.randf_range(2.0, 4.5), 0.02, rng.randf_range(2.0, 4.0)), soot, false, false, rng.randf() * TAU)
			1:
				for j in 4:
					var size := rng.randf_range(0.25, 0.7)
					_box(Vector3(at.x + rng.randf_range(-1.2, 1.2), size * 0.3, at.y + rng.randf_range(-1.2, 1.2)), Vector3(size, size * 0.6, size * 0.8), rubble, false, false, rng.randf() * TAU, 0.04)
			2:
				_box(Vector3(at.x, 0.05, at.y), Vector3(rng.randf_range(1.6, 2.6), 0.08, rng.randf_range(0.9, 1.4)), rust, false, false, rng.randf() * TAU, 0.02)

# --- Guard posts ---------------------------------------------------------------
# A deck levelled into the hillside beside a trail: a three-walled shelter with
# something to search, a wall to fight from, a lamp. Some are still manned.

func _post(index: int) -> void:
	var at := _sites[index]
	var manned: bool = POSTS[index][2]
	var top := -INF
	for corner: Vector2 in [Vector2(-7, -6), Vector2(7, -6), Vector2(-7, 6), Vector2(7, 6), Vector2.ZERO]:
		top = maxf(top, kit.height(at.x + corner.x, at.y + corner.y))
	top += 0.25
	origin = Vector3(at.x, top, at.y)
	var slab := Mats.wall(HULL, HULL_DARK, 0.0, 1.5, 0.7)
	var steel := Mats.surface(Color(0.17, 0.18, 0.2), "metal", 0.5, 0.6)
	var panel := Mats.wall(HULL.darkened(0.12), RUST if index % 2 == 0 else TEAL, 0.5, 1.4, 0.6)
	_box(Vector3(0.0, -4.0, 0.0), Vector3(14.0, 8.0, 12.0), slab)
	# The shelter: back and side walls, a roof, open to the south.
	_box(Vector3(-2.0, 1.4, -4.6), Vector3(6.4, 2.8, 0.25), panel)
	_box(Vector3(-5.1, 1.4, -2.6), Vector3(0.25, 2.8, 4.2), panel)
	_box(Vector3(1.1, 1.4, -2.6), Vector3(0.25, 2.8, 4.2), panel)
	_box(Vector3(-2.0, 2.9, -2.5), Vector3(6.9, 0.2, 4.8), steel, true, false)
	if manned:
		_box(Vector3(-2.0, 2.62, -0.5), Vector3(4.6, 0.06, 0.2), Mats.glow(LIGHT_WARM, 2.2), false)
	_mark(Vector3(-3.6, 0.0, -3.9), "locker" if index % 2 == 0 else "crate", 0.0)
	_crate(-0.4, -3.6, Vector3(1.1, 1.1, 1.1), OCHRE, 0.2)
	_barrier(3.6, 3.4, 3.2)
	_barrier(-4.0, 4.2, 3.2, 0.15)
	_barrier(5.6, -1.5, 3.0, PI * 0.5)
	_mast(5.0, 4.6, manned)
	_sign((POSTS[index][0] as String).to_upper(), Vector3(-2.0, 2.2, -0.42), 0.0, 0.3, HULL, true)
	if manned:
		zones.append({"rect": Rect2(at - Vector2(20.0, 20.0), Vector2(40.0, 40.0)), "ground": top})
		squads.append({"members": ["trooper", "marksman"] if index % 2 == 0 else ["rusher", "trooper"],
			"points": [origin + Vector3(2.0, 0.05, 1.0), origin + Vector3(-3.0, 0.05, 2.5), origin + Vector3(4.0, 0.05, -3.0)]})
	places.append({"name": POSTS[index][0], "position": origin})
	origin = Vector3.ZERO

# --- Drone outposts ------------------------------------------------------------
# A landing deck on a concrete footing cut into the slope, a crew shelter beside
# it, barriers, two lamps and a squad. The deck is a way out: step on it to call
# the drone (see ExtractPoint).

func _outpost(index: int) -> void:
	var deck := _pads[index]
	origin = deck
	var slab := Mats.wall(HULL, HULL_DARK, 0.0, 1.5, 0.7)
	# Footing under the deck and the shelter's yard, down into the hill.
	_box(Vector3(0.0, -6.15, 0.0), Vector3(27.0, 12.0, 27.0), slab)
	_box(Vector3(0.0, -6.15, -21.5), Vector3(19.0, 12.0, 16.0), slab)
	kit.add("frontier_pad", deck, 0.0)
	kit.add("frontier_shelter", deck + Vector3(0.0, 0.0, -21.5), PI)
	if index != 1:
		# A spare drone parked on the yard.
		kit.add("frontier_drone", deck + Vector3(7.0, 0.0, -24.5), 0.4 + index)
	for spot: Array in [[-9.0, -14.0, 0.0], [9.0, -14.5, 0.1], [-15.0, 4.0, PI * 0.5], [15.0, -4.0, PI * 0.5]]:
		kit.add("frontier_barrier", deck + Vector3(spot[0], 0.0, spot[1]), spot[2])
	_mast(-11.5, -11.5)
	_mast(11.5, 11.5)
	_mark(Vector3(-4.0, 0.15, -22.5), "vault" if index == 0 else "locker", PI)
	_mark(Vector3(4.0, 0.15, -22.5), "crate", PI)
	_sign((OUTPOSTS[index][0] as String).to_upper(), Vector3(0.0, 4.2, -16.2), 0.0, 0.4, HULL, true)
	zones.append({"rect": Rect2(Vector2(deck.x, deck.z) - Vector2(30.0, 30.0), Vector2(60.0, 60.0)), "ground": deck.y})
	squads.append({"members": ["trooper", "marksman", "trooper"] if index != 1 else ["bulwark", "trooper", "rusher"],
		"points": [deck + Vector3(-8.0, 0.05, 6.0), deck + Vector3(8.0, 0.05, -6.0), deck + Vector3(0.0, 0.05, -18.0)]})
	extracts.append({"position": deck + Vector3(0.0, 0.05, 0.0), "name": OUTPOSTS[index][0], "drone": CairnKit.ROOT + "art/detail/frontier_drone.glb"})
	places.append({"name": OUTPOSTS[index][0], "position": deck})
	origin = Vector3.ZERO

# --- Rock shelters --------------------------------------------------------------
# A ring of the kit's boulders, grown to the size of a house, leaning over a
# hollow with a gap to walk in by. Dark inside but for what glows.

func _shelter(index: int) -> void:
	var at: Vector2 = SHELTERS[index]
	var floor_y := kit.height(at.x, at.y)
	var gap := index * 1.7 + 0.6          # which way the way in faces
	for i in 7:
		var angle := gap + PI * 0.36 + i * (TAU - PI * 0.72) / 6.0
		var out := Vector2(cos(angle), sin(angle)) * 8.2
		var ground := kit.height(at.x + out.x, at.y + out.y)
		kit.add("boulder%d" % ((i + index) % 6), Vector3(at.x + out.x, minf(ground, floor_y) - 0.8, at.y + out.y), angle * 1.7 + index, 5.6 + (i % 3) * 0.6)
	# The roof: two long rocks laid across the top.
	kit.add("boulder%d" % (index % 6), Vector3(at.x - 1.5, floor_y + 4.2, at.y), gap + 0.4, 5.6)
	kit.add("boulder%d" % ((index + 3) % 6), Vector3(at.x + 2.5, floor_y + 4.6, at.y + 1.0), gap + 2.0, 5.0)
	origin = Vector3(at.x, floor_y, at.y)
	var glow := Color(0.35, 0.95, 0.85) if index % 2 == 0 else Color(1.0, 0.62, 0.3)
	for i in 5:
		var angle := i * 1.3 + index
		var size := 0.25 + (i % 3) * 0.14
		_box(Vector3(cos(angle) * 3.4, size * 0.5 + 0.05, sin(angle) * 3.4), Vector3(size * 0.5, size * 1.6, size * 0.5), Mats.glow(glow, 2.6), false, false, angle)
	var light := OmniLight3D.new()
	light.position = origin + Vector3(0.0, 1.6, 0.0)
	light.light_color = glow
	light.light_energy = 1.6
	light.omni_range = 9.0
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 70.0
	light.distance_fade_length = 20.0
	add_child(light)
	_mark(Vector3(0.6, 0.15, -0.4), "vault" if index == 3 else "locker", gap)
	_crate(-1.6, 0.9, Vector3(0.9, 0.7, 0.9), RUST, 0.4, 0.1)
	places.append({"name": "Shelter", "position": origin})
	origin = Vector3.ZERO

# Two crates and a smaller one on top.
func _stack(x: float, z: float, yaw: float) -> void:
	_crate(x, z, Vector3(1.4, 1.4, 1.4), STEEL, yaw)
	var beside := Vector3(1.45, 0.0, 0.1).rotated(Vector3.UP, yaw)
	_crate(x + beside.x, z + beside.z, Vector3(1.3, 1.1, 1.3), OCHRE, yaw + 0.15)
	_crate(x + beside.x * 0.4, z + beside.z * 0.4, Vector3(0.9, 0.8, 0.9), RUST, yaw - 0.2, 1.4)

# A cargo cassette: a long sled-mounted box, tall enough to stand behind.
func _cassette(x: float, z: float, yaw: float, color: Color) -> void:
	_box(Vector3(x, 1.45, z), Vector3(5.6, 2.3, 2.3), Mats.wall(color.darkened(0.15), HULL_DARK, 0.3, 1.2, 0.6), true, true, yaw, 0.08)
	for side: float in [-1.0, 1.0]:
		var skid := Vector3(0.0, 0.0, side * 0.85).rotated(Vector3.UP, yaw)
		_box(Vector3(x + skid.x, 0.15, z + skid.z), Vector3(5.9, 0.3, 0.3), Mats.surface(Color(0.12, 0.13, 0.14), "metal", 0.5, 0.6), true, true, yaw, 0.04)
		var cap := Vector3(side * 2.82, 0.0, 0.0).rotated(Vector3.UP, yaw)
		_box(Vector3(x + cap.x, 1.45, z + cap.z), Vector3(0.08, 1.7, 1.7), Mats.surface(HULL_DARK, "metal", 0.5, 0.6), false, false, yaw, 0.02)

# A lamp on a pole. Not all of them still work.
func _mast(x: float, z: float, lit: bool = true) -> void:
	var steel := Mats.surface(Color(0.16, 0.17, 0.19), "metal", 0.5, 0.6)
	_box(Vector3(x, 2.4, z), Vector3(0.14, 4.8, 0.14), steel, true, true)
	_box(Vector3(x, 0.12, z), Vector3(0.5, 0.24, 0.5), steel, false, false, 0.0, 0.04)
	_box(Vector3(x, 4.74, z), Vector3(0.9, 0.08, 0.3), Mats.glow(LIGHT_WARM, 4.0) if lit else steel, false)
	if not lit:
		return
	var light := OmniLight3D.new()
	light.position = origin + Vector3(x, 4.5, z)
	light.light_color = LIGHT_WARM
	light.light_energy = 3.2
	light.omni_range = 15.0
	light.omni_attenuation = 0.9
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 90.0
	light.distance_fade_length = 30.0
	add_child(light)

# Meadow over each colony's shelf. The hills between are bare ground and fern.
func _grass() -> void:
	for i in DISTRICTS.size():
		var rect: Rect2 = zones[i]["rect"]
		var grass := Grass.new()
		grass.name = "Grass" if i == 0 else "Grass%d" % i
		grass.area = rect.grow(8.0)
		grass.density = 6.0
		var ground: float = zones[i]["ground"]
		grass.reach = Vector2(ground + 9.5, ground - 12.0)
		grass.seed_value = 19 + i
		add_child(grass)

func _squads_and_exits() -> void:
	# Hearth. The middle house: a squad downstairs, the commander upstairs by the vault.
	squads.append({"members": ["trooper", "trooper", "lobber"], "points": [Vector3(-5.0, 0.05, 3.0), Vector3(6.0, 0.05, 5.0), Vector3(2.0, 0.05, -1.0)]})
	squads.append({"members": ["overseer", "trooper"], "points": [Vector3(-5.0, UPPER + 0.05, 3.0), Vector3(6.0, UPPER + 0.05, 4.0), Vector3(0.0, UPPER + 0.05, 6.5)]})
	squads.append({"members": ["bulwark", "trooper"], "points": [Vector3(-41.0, 0.05, 3.0), Vector3(-30.0, 0.05, 5.0), Vector3(-36.0, 0.05, 12.0)]})
	squads.append({"members": ["marksman"], "points": [Vector3(30.0, UPPER + 0.05, 9.5), Vector3(42.0, UPPER + 0.05, 9.5)]})
	squads.append({"members": ["trooper", "rusher"], "points": [Vector3(-41.0, 0.05, 39.0), Vector3(-30.0, 0.05, 41.0), Vector3(-36.0, 0.05, 24.0)]})
	squads.append({"members": ["trooper", "lobber"], "points": [Vector3(31.0, 0.05, 39.0), Vector3(42.0, 0.05, 41.0), Vector3(36.0, 0.05, 50.0)]})
	squads.append({"members": ["trooper", "rusher", "trooper"], "points": [Vector3(0.0, 0.05, 30.0), Vector3(-12.0, 0.05, 40.0), Vector3(12.0, 0.05, 24.0)]})
	squads.append({"members": ["trooper", "lobber"], "points": [Vector3(-20.0, 0.05, -28.0), Vector3(8.0, 0.05, -34.0), Vector3(-40.0, 0.05, -22.0)]})
	squads.append({"members": ["bulwark", "rusher"], "points": [Vector3(50.0, 0.05, -30.0), Vector3(62.0, 0.05, -44.0), Vector3(40.0, 0.05, -44.0)]})
	# The outer colonies: the west house, the middle house on both floors, the yard.
	for i in range(1, DISTRICTS.size()):
		var middle: Vector2 = DISTRICTS[i][1]
		var base := Vector3(middle.x, float(DISTRICTS[i][2]) + 0.05, middle.y)
		var flip := -1.0 if i % 2 == 0 else 1.0
		squads.append({"members": ["trooper", "trooper"], "points": [base + Vector3(-41.0, 0.0, 3.0), base + Vector3(-30.0, 0.0, 5.0), base + Vector3(-36.0, 0.0, 13.0)]})
		squads.append({"members": ["bulwark", "trooper"] if i % 2 == 1 else ["trooper", "lobber"], "points": [base + Vector3(-5.0, 0.0, 3.0), base + Vector3(6.0, 0.0, 5.0), base + Vector3(2.0, 0.0, -1.0)]})
		squads.append({"members": ["overseer"] if i == 4 else ["marksman"], "points": [base + Vector3(-5.0, UPPER, 3.0), base + Vector3(6.0, UPPER, 4.0), base + Vector3(0.0, UPPER, 9.5)]})
		squads.append({"members": ["rusher", "trooper"], "points": [base + Vector3(10.0 * flip, 0.0, 24.0), base + Vector3(-22.0 * flip, 0.0, 30.0), base + Vector3(30.0 * flip, 0.0, 16.0)]})
	# Every colony has a way out.
	for spec: Dictionary in kit.manifest["extractions"]:
		var at := kit.to_level(CairnKit._v3(spec["position"]))
		extracts.append({"position": at, "name": (spec["name"] as String).replace(" evac", "")})
	reinforce_points.clear()
	for zone in zones:
		# Well in from the edge, where the shelf is still level.
		var rect: Rect2 = (zone["rect"] as Rect2).grow(-30.0)
		if rect.size.x < 60.0:
			continue
		for corner: Vector2 in [rect.position, rect.end, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y)]:
			reinforce_points.append(Vector3(corner.x, kit.height(corner.x, corner.y) + 0.2, corner.y))
	# Where you come in: one of the kit's ten insertion points, facing its colony.
	var spawns: Array = kit.manifest["spawns"]
	var pick := spawn_at if spawn_at >= 0 else int(GameManager.rng.randi() % spawns.size())
	var start := kit.to_level(CairnKit._v3(spawns[pick]["position"]))
	player_spawn = Vector3(start.x, kit.height(start.x, start.z) + 0.4, start.z)
	var facing := Vector2.ZERO
	var nearest := INF
	for district: Array in DISTRICTS:
		var away := Vector2(start.x, start.z).distance_to(district[1])
		if away < nearest:
			nearest = away
			facing = district[1]
	player_yaw = atan2(-(facing.x - start.x), -(facing.y - start.z))

# The hills between the colonies: aspen and deadfall low down, heather, lupine
# and broken shale on the slopes, bare snags and scree up high, cobbles and
# willow by the river.
func _wilds() -> void:
	var wild := Scenery.new()
	wild.name = "Wilds"
	wild.area = Rect2(-CORE, -CORE, CORE * 2.0, CORE * 2.0)
	wild.seed_value = 31
	for zone in zones:
		wild.avoid.append((zone["rect"] as Rect2).grow(4.0))
	for site in _sites:
		wild.avoid.append(Rect2(site - Vector2(12.0, 12.0), Vector2(24.0, 24.0)))
	for shelter in SHELTERS:
		wild.avoid.append(Rect2(shelter - Vector2(13.0, 13.0), Vector2(26.0, 26.0)))
	for pad in _pads:
		wild.avoid.append(Rect2(pad.x - 32.0, pad.z - 40.0, 64.0, 74.0))
	wild.keep_clear.append(player_spawn)
	for spot: Dictionary in extracts:
		wild.keep_clear.append(spot["position"])
	for spec: Dictionary in kit.manifest["spawns"]:
		wild.keep_clear.append(kit.to_level(CairnKit._v3(spec["position"])))
	wild.biome = func(x: float, z: float, y: float) -> Array:
		# The river runs north-south through the gorge east of Hearth.
		if y < -6.0:
			return ["sc_river_willow", "sc_dwarf_willow", "sc_stream_cobbles", "sc_moss_back", "sc_cattail", "sc_rushes"]
		if y < 30.0:
			return ["sc_aspen_grove", "sc_fungal_log", "sc_moss_back", "sc_berry_scrub", "sc_broadleaf", "sc_oxeye", "sc_dwarf_willow"]
		if y < 110.0:
			return ["sc_aspen_grove", "sc_weathered_snag", "sc_heather", "sc_lupine", "sc_shale_ledge", "sc_glacial_erratic", "sc_tussock"]
		return ["sc_weathered_snag", "sc_quartz_scree", "sc_glacial_erratic", "sc_shale_ledge", "sc_tussock"]
	add_child(wild)
