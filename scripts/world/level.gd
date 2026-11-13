class_name Level
extends NavigationRegion3D

# Relay Station: the raid map. Hand-authored as code -- every wall, crate and
# light below was placed deliberately; nothing is generated at random. Being a
# NavigationRegion3D, it bakes its own navmesh from the colliders it builds, so
# the AI can path through anything added here without extra setup.
#
# Axes: +x is east, +z is south, ground is y = 0. The compound spans
# x -45..45, z -35..35.
#
# After build() the raid reads the public lists below to place the player, the
# loot containers, the extraction points and the enemy squads.

const NAV_SOURCE: int = 1 << 4   # colliders the navmesh is baked from (roofs are left off)

const SAND := Color(0.56, 0.50, 0.44)
const HULL := Color(0.80, 0.79, 0.76)
const HULL_DARK := Color(0.30, 0.32, 0.35)
const STEEL := Color(0.42, 0.45, 0.49)
const TEAL := Color(0.16, 0.62, 0.62)
const RUST := Color(0.72, 0.33, 0.20)
const OCHRE := Color(0.80, 0.62, 0.26)
const LIGHT_COOL := Color(0.78, 0.90, 1.0)
const LIGHT_WARM := Color(1.0, 0.78, 0.55)

var player_spawn := Vector3(-39.0, 0.1, 30.0)
var player_yaw: float = deg_to_rad(-50.0)
var extracts: Array[Dictionary] = []     # {"position": Vector3, "name": String}
var containers: Array[Dictionary] = []   # {"position": Vector3, "kind": String, "yaw": float}
var squads: Array[Dictionary] = []       # {"members": Array[String], "points": Array[Vector3]}

func build() -> void:
	_ground_and_perimeter()
	_warehouse()
	_lab()
	_barracks()
	_courtyard()
	_container_yard()
	_horizon()
	_dress_site()
	_placements()

# --- Primitives --------------------------------------------------------------

func _box(center: Vector3, size: Vector3, mat: Material, solid: bool = true, nav: bool = true, yaw: float = 0.0, bevel: float = 0.0) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	if bevel > 0.0:
		visual.mesh = Shapes.rounded_box(size, bevel, 2)
	else:
		var mesh := BoxMesh.new()
		mesh.size = size
		visual.mesh = mesh
	visual.material_override = mat
	if not solid:
		visual.position = center
		visual.rotation.y = yaw
		add_child(visual)
		return visual
	var body := StaticBody3D.new()
	body.collision_layer = Layers.WORLD | (NAV_SOURCE if nav else 0)
	body.collision_mask = 0
	body.position = center
	body.rotation.y = yaw
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	body.add_child(visual)
	add_child(body)
	return visual

# A straight wall between two ground points (axis-aligned), with openings.
# gaps: [[centre along the wall's varying axis, width, opening height], ...]
func _wall(a: Vector2, b: Vector2, height: float, mat: Material, gaps: Array = [], thick: float = 0.4) -> void:
	var along_x := absf(a.x - b.x) > absf(a.y - b.y)
	var lo := minf(a.x, b.x) if along_x else minf(a.y, b.y)
	var hi := maxf(a.x, b.x) if along_x else maxf(a.y, b.y)
	var fixed := a.y if along_x else a.x
	var sorted := gaps.duplicate()
	sorted.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	var cursor := lo
	for gap: Array in sorted:
		var g_lo: float = gap[0] - gap[1] * 0.5
		var g_hi: float = gap[0] + gap[1] * 0.5
		_wall_piece(along_x, cursor, g_lo, fixed, 0.0, height, mat, thick)
		# The lintel over the opening, and a lit frame so doors read from afar.
		_wall_piece(along_x, g_lo, g_hi, fixed, gap[2], height, mat, thick)
		_wall_piece(along_x, g_lo, g_hi, fixed, gap[2] - 0.06, gap[2], Mats.glow(TEAL, 2.2), thick + 0.04, false)
		var door_light := OmniLight3D.new()
		door_light.position = Vector3(gap[0], gap[2] - 0.35, fixed) if along_x else Vector3(fixed, gap[2] - 0.35, gap[0])
		door_light.light_color = TEAL.lightened(0.3)
		door_light.light_energy = 1.1
		door_light.omni_range = 5.5
		add_child(door_light)
		cursor = g_hi
	_wall_piece(along_x, cursor, hi, fixed, 0.0, height, mat, thick)

func _wall_piece(along_x: bool, from: float, to: float, fixed: float, y0: float, y1: float, mat: Material, thick: float, solid: bool = true) -> void:
	if to - from < 0.01 or y1 - y0 < 0.01:
		return
	var mid := (from + to) * 0.5
	var center := Vector3(mid, (y0 + y1) * 0.5, fixed) if along_x else Vector3(fixed, (y0 + y1) * 0.5, mid)
	var size := Vector3(to - from, y1 - y0, thick) if along_x else Vector3(thick, y1 - y0, to - from)
	_box(center, size, mat, solid)

# Four walls, a roof and a tinted floor. doors: {"n"|"s"|"e"|"w": [[at, width, height], ...]}
func _shell(x0: float, z0: float, x1: float, z1: float, height: float, doors: Dictionary, wall_mat: Material, floor_color: Color) -> void:
	_wall(Vector2(x0, z0), Vector2(x1, z0), height, wall_mat, doors.get("n", []))
	_wall(Vector2(x0, z1), Vector2(x1, z1), height, wall_mat, doors.get("s", []))
	_wall(Vector2(x0, z0), Vector2(x0, z1), height, wall_mat, doors.get("w", []))
	_wall(Vector2(x1, z0), Vector2(x1, z1), height, wall_mat, doors.get("e", []))
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	# Roof: solid to shots and sight, but not walkable ground for the navmesh.
	_box(Vector3(cx, height + 0.2, cz), Vector3(x1 - x0 + 0.8, 0.4, z1 - z0 + 0.8), Mats.wall(HULL_DARK, Color.BLACK, 0.0, 3.0, 0.8), true, false)
	# Polished floor: picks up the ceiling lights in screen-space reflections.
	_box(Vector3(cx, 0.01, cz), Vector3(x1 - x0, 0.04, z1 - z0), Mats.wall(floor_color, Color.BLACK, 0.0, 1.5, 0.28, 0.25, 0.7), false)
	_dress_shell(x0, z0, x1, z1, height, doors)

func _lamp(position: Vector3, color: Color, energy: float = 2.2, reach: float = 11.0, shadows: bool = false, fixture: bool = true) -> void:
	var light := OmniLight3D.new()
	light.position = position
	light.light_color = color
	light.light_energy = energy * 2.6
	light.omni_range = reach * 1.35
	light.omni_attenuation = 0.9
	light.shadow_enabled = shadows
	add_child(light)
	if fixture:
		_box(position + Vector3(0.0, 0.22, 0.0), Vector3(1.6, 0.06, 0.28), Mats.glow(color, 4.0), false)

func _crate(x: float, z: float, size: Vector3 = Vector3(1.2, 1.2, 1.2), color: Color = STEEL, yaw: float = 0.0, y: float = 0.0) -> void:
	_box(Vector3(x, y + size.y * 0.5, z), size, Mats.surface(color, "metal", 0.5, 0.55), true, true, yaw, 0.05)
	# Corner straps, so a crate reads as a made thing rather than a cube.
	for side: float in [-1.0, 1.0]:
		_box(Vector3(x, y + size.y * 0.5, z) + Vector3(side * size.x * 0.36, 0.0, 0.0).rotated(Vector3.UP, yaw), Vector3(0.09, size.y + 0.02, size.z + 0.02), Mats.surface(Color(0.12, 0.13, 0.14), "plain", 0.5, 0.6), false, false, yaw, 0.01)

# Waist-high cover: you can crouch behind it, and enemies can fire over it.
func _barrier(x: float, z: float, length: float = 3.0, yaw: float = 0.0) -> void:
	_box(Vector3(x, 0.55, z), Vector3(length, 1.1, 0.45), Mats.wall(HULL, HULL_DARK, 0.25, 1.0, 0.6), true, true, yaw, 0.06)
	_box(Vector3(x, 1.11, z), Vector3(length + 0.02, 0.07, 0.5), Mats.surface(OCHRE, "plain", 0.5), false, false, yaw, 0.02)
	_box(Vector3(x, 0.08, z), Vector3(length + 0.1, 0.16, 0.7), Mats.surface(HULL_DARK, "plain", 0.7), false, false, yaw, 0.03)

func _rack(x: float, z: float, yaw: float = 0.0) -> void:
	_box(Vector3(x, 1.1, z), Vector3(0.9, 2.2, 0.7), Mats.surface(Color(0.1, 0.11, 0.13), "metal", 0.35, 0.7), true, true, yaw)
	for row in 4:
		_box(Vector3(x, 0.5 + row * 0.45, z) + Vector3(0.0, 0.0, 0.36).rotated(Vector3.UP, yaw), Vector3(0.7, 0.04, 0.02), Mats.glow(TEAL.lightened(0.2), 3.0), false, false, yaw)

# Exterior trim for a building: corner posts, a dark plinth, a cornice, a roof
# parapet, lit window slits and rooftop plant. Visual only -- no colliders.
func _dress_shell(x0: float, z0: float, x1: float, z1: float, height: float, doors: Dictionary) -> void:
	var dark := Mats.surface(Color(0.13, 0.14, 0.16), "metal", 0.6, 0.4)
	var window := Mats.glow(LIGHT_WARM, 1.6)
	for corner: Vector2 in [Vector2(x0, z0), Vector2(x1, z0), Vector2(x0, z1), Vector2(x1, z1)]:
		_box(Vector3(corner.x, height * 0.5, corner.y), Vector3(0.7, height, 0.7), dark, false, false, 0.0, 0.05)
	# side: [door key, along x?, fixed coord, from, to, outward sign]
	for side: Array in [["n", true, z0, x0, x1, -1.0], ["s", true, z1, x0, x1, 1.0], ["w", false, x0, z0, z1, -1.0], ["e", false, x1, z0, z1, 1.0]]:
		var along_x: bool = side[1]
		var out: float = side[5]
		var length: float = side[4] - side[3]
		var mid: float = (side[3] + side[4]) * 0.5
		var gaps: Array = doors.get(side[0], [])
		# Cornice and parapet run the full length; the plinth breaks at doors.
		for strip: Array in [[height - 0.2, 0.4, 0.32], [height + 0.75, 0.7, 0.2]]:
			var y: float = strip[0]
			var across: float = side[2] + out * 0.12
			_box(Vector3(mid, y, across) if along_x else Vector3(across, y, mid),
				Vector3(length + 0.6, strip[1], strip[2]) if along_x else Vector3(strip[2], strip[1], length + 0.6), dark, false, false, 0.0, 0.03)
		var t: float = side[3] + 2.5
		while t < side[4] - 2.0:
			var blocked := false
			for gap: Array in gaps:
				if absf(t - float(gap[0])) < float(gap[1]) * 0.5 + 1.2:
					blocked = true
			if not blocked:
				var face: float = side[2] + out * 0.215
				if height > 4.2:
					_box(Vector3(t, height - 1.15, face) if along_x else Vector3(face, height - 1.15, t),
						Vector3(1.7, 0.38, 0.03) if along_x else Vector3(0.03, 0.38, 1.7), window, false)
				_box(Vector3(t, 0.2, face) if along_x else Vector3(face, 0.2, t),
					Vector3(4.0, 0.4, 0.1) if along_x else Vector3(0.1, 0.4, 4.0), dark, false, false, 0.0, 0.02)
			t += 4.0
	# Rooftop plant: a pair of vent units and a duct.
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	var top := height + 0.4
	_box(Vector3(cx - 3.0, top + 0.5, cz - 2.0), Vector3(2.2, 1.0, 1.6), Mats.surface(STEEL, "metal", 0.5, 0.6), false, false, 0.0, 0.08)
	_box(Vector3(cx + 2.5, top + 0.4, cz + 2.5), Vector3(1.4, 0.8, 1.4), Mats.surface(STEEL, "metal", 0.5, 0.6), false, false, 0.0, 0.08)
	_box(Vector3(cx - 0.3, top + 0.25, cz + 0.3), Vector3(4.6, 0.3, 0.3), dark, false, false, 0.7)
	# A reflection probe per interior, so glossy surfaces inside don't mirror the sky.
	var probe := ReflectionProbe.new()
	probe.position = Vector3(cx, height * 0.5, cz)
	probe.size = Vector3(x1 - x0, height, z1 - z0)
	probe.interior = true
	probe.box_projection = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.ambient_mode = ReflectionProbe.AMBIENT_COLOR
	probe.ambient_color = Color(0.05, 0.055, 0.065)
	add_child(probe)

# Painted lettering on a wall. `yaw` turns the text to face outward.
func _sign(text: String, at: Vector3, yaw: float, letter_height: float, color: Color, lit: bool = false) -> void:
	var font := FontVariation.new()
	font.base_font = ThemeDB.fallback_font
	font.variation_embolden = 1.1
	font.spacing_glyph = 6
	var label := Label3D.new()
	label.text = text
	label.font = font
	label.font_size = 160
	label.pixel_size = letter_height / 160.0
	label.outline_size = 0
	label.modulate = color
	label.shaded = not lit
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	label.position = at
	label.rotation.y = yaw
	add_child(label)

func _cylinder(at: Vector3, radius: float, length: float, mat: Material, axis: Vector3 = Vector3.UP) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 16
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = at
	if axis.is_equal_approx(Vector3.RIGHT):
		instance.rotation.z = PI * 0.5
	elif axis.is_equal_approx(Vector3.BACK):
		instance.rotation.x = PI * 0.5
	add_child(instance)

# Everything that makes the compound read as a place: lettering, pipe runs on
# the perimeter, painted lanes, and a comms mast that marks the centre of the
# map from anywhere on it.
func _dress_site() -> void:
	var paint := Color(0.92, 0.9, 0.84)
	_sign("RELAY STATION 07", Vector3(0.0, 4.6, -34.45), 0.0, 2.0, paint.darkened(0.25))
	_sign("STORAGE  A1", Vector3(-17.74, 5.4, 0.5), PI * 0.5, 1.1, Color(0.16, 0.17, 0.19))
	_sign("LAB 02", Vector3(1.0, 3.55, -13.76), 0.0, 0.7, Color(0.16, 0.17, 0.19))
	_sign("CONTROL", Vector3(21.76, 3.15, 1.0), -PI * 0.5, 0.7, Color(0.16, 0.17, 0.19))
	_sign("EXIT  N", Vector3(44.45, 3.4, -29.0), -PI * 0.5, 1.3, TEAL.lightened(0.35), true)
	_sign("EXIT  S", Vector3(44.45, 3.4, 30.0), -PI * 0.5, 1.3, TEAL.lightened(0.35), true)
	_sign("VAULT", Vector3(9.72, 3.3, -19.0), -PI * 0.5, 0.45, RUST.lightened(0.2), true)

	# Pipe runs along the north and west perimeter, with brackets.
	var pipe := Mats.surface(STEEL, "metal", 0.4, 0.7)
	var pipe_alt := Mats.surface(RUST, "metal", 0.5, 0.5)
	_cylinder(Vector3(0.0, 2.3, -34.25), 0.16, 86.0, pipe, Vector3.RIGHT)
	_cylinder(Vector3(0.0, 2.75, -34.3), 0.09, 86.0, pipe_alt, Vector3.RIGHT)
	_cylinder(Vector3(-44.25, 2.3, 0.0), 0.16, 66.0, pipe, Vector3.BACK)
	_cylinder(Vector3(-44.3, 2.75, 0.0), 0.09, 66.0, pipe_alt, Vector3.BACK)
	for i in 11:
		_box(Vector3(-40.0 + i * 8.0, 2.45, -34.3), Vector3(0.12, 0.8, 0.4), Mats.surface(HULL_DARK, "plain", 0.6), false)
	for i in 8:
		_box(Vector3(-44.3, 2.45, -28.0 + i * 8.0), Vector3(0.4, 0.8, 0.12), Mats.surface(HULL_DARK, "plain", 0.6), false)

	# Painted lanes: a dashed centre line across the yard and solid edges.
	var line := Mats.surface(paint, "plain", 0.8)
	for i in 21:
		_box(Vector3(-40.0 + i * 4.0, 0.012, 17.6), Vector3(2.0, 0.02, 0.16), line, false)
	for z: float in [15.6, 19.6]:
		_box(Vector3(0.0, 0.012, z), Vector3(86.0, 0.02, 0.1), Mats.surface(OCHRE, "plain", 0.8), false)
	# Hazard chevrons in front of the roll-up door.
	for i in 7:
		_box(Vector3(-16.6, 0.013, -10.4 + i * 0.8), Vector3(1.6, 0.02, 0.28), Mats.surface(OCHRE, "plain", 0.8), false, false, 0.6)

	# Comms mast: four legs, ring bracing, dishes, and a beacon on top.
	var steel := Mats.surface(Color(0.2, 0.21, 0.23), "metal", 0.5, 0.7)
	var base := Vector3(19.0, 0.0, -19.0)
	_box(base + Vector3(0.0, 0.6, 0.0), Vector3(2.4, 1.2, 2.4), Mats.wall(HULL_DARK, OCHRE, 0.3, 1.2, 0.7), true, true, 0.0, 0.08)
	for leg: Vector2 in [Vector2(-0.8, -0.8), Vector2(0.8, -0.8), Vector2(-0.8, 0.8), Vector2(0.8, 0.8)]:
		_box(base + Vector3(leg.x, 13.2, leg.y), Vector3(0.14, 24.0, 0.14), steel, false)
	for level in 8:
		var y := 2.0 + level * 3.0
		for brace: Array in [[Vector3(0, y, -0.8), Vector3(1.74, 0.09, 0.09)], [Vector3(0, y, 0.8), Vector3(1.74, 0.09, 0.09)], [Vector3(-0.8, y, 0), Vector3(0.09, 0.09, 1.74)], [Vector3(0.8, y, 0), Vector3(0.09, 0.09, 1.74)]]:
			_box(base + brace[0], brace[1], steel, false)
	for dish: Array in [[Vector3(1.1, 17.0, 0.0), Vector3.RIGHT], [Vector3(0.0, 20.0, -1.1), Vector3.BACK], [Vector3(-1.1, 22.5, 0.0), Vector3.RIGHT]]:
		_cylinder(base + dish[0], 0.75, 0.16, Mats.surface(HULL, "metal", 0.4, 0.5), dish[1])
	_box(base + Vector3(0.0, 26.2, 0.0), Vector3(0.08, 2.4, 0.08), steel, false)
	_box(base + Vector3(0.0, 27.5, 0.0), Vector3(0.3, 0.3, 0.3), Mats.glow(Color(1.0, 0.25, 0.2), 8.0), false)
	var beacon := OmniLight3D.new()
	beacon.position = base + Vector3(0.0, 27.5, 0.0)
	beacon.light_color = Color(1.0, 0.3, 0.25)
	beacon.light_energy = 3.0
	beacon.omni_range = 14.0
	add_child(beacon)

func _mark(position: Vector3, kind: String, yaw: float = 0.0) -> void:
	containers.append({"position": position, "kind": kind, "yaw": yaw})

# --- Areas -------------------------------------------------------------------

func _ground_and_perimeter() -> void:
	var ground := Mats.wall(SAND, Color.BLACK, 0.0, 8.0, 0.92, 0.0, 1.0)
	ground.set_shader_parameter("seam_strength", 0.2)
	_box(Vector3(0.0, -0.5, 0.0), Vector3(140.0, 1.0, 120.0), ground)
	var wall_mat := Mats.wall(HULL_DARK, Color(0.17, 0.18, 0.2), 1.4, 3.0, 0.75, 0.2)
	for side: Array in [[Vector2(-45, -35), Vector2(45, -35)], [Vector2(-45, 35), Vector2(45, 35)], [Vector2(-45, -35), Vector2(-45, 35)], [Vector2(45, -35), Vector2(45, 35)]]:
		_wall(side[0], side[1], 7.0, wall_mat, [], 1.0)
	# Corner pylons with beacons, so the edges of the map read at a glance.
	for corner: Vector2 in [Vector2(-45, -35), Vector2(45, -35), Vector2(-45, 35), Vector2(45, 35)]:
		_box(Vector3(corner.x, 5.0, corner.y), Vector3(2.4, 10.0, 2.4), wall_mat)
		_box(Vector3(corner.x, 10.2, corner.y), Vector3(0.5, 0.4, 0.5), Mats.glow(RUST, 6.0), false)

func _warehouse() -> void:
	# x -42..-18, z -22..6. One tall hall: shelving lanes, a mezzanine, a roll-up door.
	var wall_mat := Mats.wall(HULL, RUST, 1.15, 2.0, 0.65)
	_shell(-42.0, -22.0, -18.0, 6.0, 7.0, {
		"e": [[-8.0, 5.0, 3.6]], "s": [[-30.0, 2.2, 2.6]], "n": [[-24.0, 2.2, 2.6]],
	}, wall_mat, Color(0.33, 0.35, 0.37))
	_box(Vector3(-17.76, 1.3, -8.0), Vector3(0.06, 0.5, 12.0), Mats.surface(RUST, "plain", 0.5), false)
	# Shelving lanes.
	for x: float in [-37.0, -32.0, -27.0]:
		_box(Vector3(x, 1.6, -15.0), Vector3(1.1, 3.2, 9.0), Mats.surface(STEEL, "metal", 0.5, 0.6))
		_box(Vector3(x, 3.25, -15.0), Vector3(1.3, 0.1, 9.2), Mats.surface(OCHRE, "plain", 0.5), false)
	_crate(-23.0, -17.0, Vector3(1.6, 1.6, 1.6), RUST, 0.3)
	_crate(-22.6, -14.6, Vector3(1.2, 1.2, 1.2), STEEL, -0.2)
	_crate(-23.0, -3.0, Vector3(2.0, 1.4, 1.4), TEAL.darkened(0.3), 0.1)
	_crate(-21.5, -11.5, Vector3(1.2, 1.2, 1.2), OCHRE)
	_crate(-21.5, -11.5, Vector3(1.0, 1.0, 1.0), STEEL, 0.5, 1.2)
	_barrier(-25.0, -6.0, 3.0, PI * 0.5)
	_barrier(-30.0, 2.0, 3.0)
	# Mezzanine along the west wall, reached by a ramp. A marksman's perch.
	var deck := Mats.surface(HULL_DARK, "metal", 0.5, 0.6)
	_box(Vector3(-38.0, 3.0, -1.0), Vector3(7.6, 0.3, 13.6), deck)
	for post: Vector2 in [Vector2(-34.4, -7.5), Vector2(-34.4, 5.5), Vector2(-34.4, -1.0)]:
		_box(Vector3(post.x, 1.42, post.y), Vector3(0.3, 2.85, 0.3), deck)
	_box(Vector3(-34.3, 3.65, -3.0), Vector3(0.12, 1.0, 9.4), Mats.surface(OCHRE, "plain", 0.5))
	var ramp := _box(Vector3(-29.9, 1.5, 4.2), Vector3(9.2, 0.3, 2.6), deck)
	(ramp.get_parent() as Node3D).rotation.z = -atan2(3.0, 8.6)
	for z: float in [-17.0, -8.0, 1.0]:
		_lamp(Vector3(-30.0, 6.4, z), LIGHT_WARM, 3.2, 16.0, z == -8.0)
	_mark(Vector3(-40.6, 0.0, -20.0), "crate", PI * 0.5)
	_mark(Vector3(-34.5, 0.0, -20.5), "crate")
	_mark(Vector3(-20.0, 0.0, 4.0), "crate", -PI * 0.5)
	_mark(Vector3(-40.8, 3.15, -6.5), "locker", PI * 0.5)
	_mark(Vector3(-29.5, 0.0, -20.6), "crate")
	squads.append({"members": ["trooper", "rusher", "bulwark", "trooper"], "points": [
		Vector3(-24.0, 0.0, -8.0), Vector3(-34.5, 0.0, -9.0), Vector3(-29.5, 0.0, -19.5), Vector3(-22.0, 0.0, 0.0)]})
	squads.append({"members": ["marksman"], "points": [Vector3(-38.0, 3.2, -4.0), Vector3(-38.0, 3.2, 3.0)]})

func _lab() -> void:
	# x -10..16, z -32..-14. Two labs and, behind the last door, the vault.
	var wall_mat := Mats.wall(Color(0.86, 0.87, 0.88), TEAL.darkened(0.2), 0.95, 1.5, 0.45, 0.05, 0.6)
	_shell(-10.0, -32.0, 16.0, -14.0, 4.4, {
		"s": [[-4.0, 2.4, 2.6], [6.0, 2.4, 2.6]], "w": [[-27.0, 2.0, 2.6]],
	}, wall_mat, Color(0.42, 0.45, 0.48))
	_wall(Vector2(2.0, -32.0), Vector2(2.0, -14.0), 4.4, wall_mat, [[-24.0, 2.2, 2.6]], 0.3)
	_wall(Vector2(10.0, -32.0), Vector2(10.0, -14.0), 4.4, Mats.wall(HULL_DARK, RUST, 0.95, 1.5, 0.5, 0.4, 0.6), [[-19.0, 1.8, 2.5]], 0.5)
	# Lab A: benches and a glass partition.
	for z: float in [-29.0, -24.5]:
		_box(Vector3(-5.0, 0.5, z), Vector3(4.6, 1.0, 1.1), Mats.surface(Color(0.9, 0.9, 0.9), "plain", 0.4, 0.1))
		_box(Vector3(-5.0, 1.06, z), Vector3(4.6, 0.04, 1.1), Mats.glow(LIGHT_COOL, 0.6), false)
	_box(Vector3(-1.5, 1.5, -18.5), Vector3(0.08, 3.0, 4.0), Mats.glass(), true, true)
	_rack(-9.2, -20.0, PI * 0.5)
	_rack(-9.2, -18.6, PI * 0.5)
	# Lab B: server racks in two rows -- tight, lots of corners.
	for z: float in [-30.0, -27.6]:
		for x: float in [4.0, 5.2, 6.4, 7.6]:
			_rack(x, z)
	_box(Vector3(6.0, 0.5, -19.5), Vector3(3.0, 1.0, 1.0), Mats.surface(Color(0.9, 0.9, 0.9), "plain", 0.4, 0.1))
	# Vault: dim, red, valuable.
	_box(Vector3(13.0, 0.6, -28.0), Vector3(2.4, 1.2, 2.4), Mats.surface(Color(0.1, 0.1, 0.12), "metal", 0.3, 0.8))
	_box(Vector3(13.0, 1.25, -28.0), Vector3(1.6, 0.06, 1.6), Mats.glow(RUST, 3.0), false)
	_lamp(Vector3(-4.0, 4.0, -23.0), LIGHT_COOL, 2.6, 13.0, true)
	_lamp(Vector3(6.0, 4.0, -23.0), LIGHT_COOL, 2.2, 12.0)
	_lamp(Vector3(13.0, 4.0, -23.0), Color(1.0, 0.35, 0.25), 2.0, 11.0)
	_mark(Vector3(-9.0, 0.0, -30.6), "locker", PI * 0.5)
	_mark(Vector3(0.6, 0.0, -30.8), "crate")
	_mark(Vector3(8.8, 0.0, -16.0), "locker", -PI * 0.5)
	_mark(Vector3(13.0, 0.0, -31.0), "vault")
	_mark(Vector3(15.0, 0.0, -17.0), "vault", -PI * 0.5)
	squads.append({"members": ["trooper", "trooper", "rusher"], "points": [
		Vector3(-4.0, 0.0, -21.0), Vector3(-7.0, 0.0, -27.0), Vector3(5.5, 0.0, -24.5), Vector3(-4.0, 0.0, -11.0)]})
	squads.append({"members": ["overseer", "bulwark"], "points": [Vector3(13.0, 0.0, -22.0), Vector3(7.0, 0.0, -22.0), Vector3(13.0, 0.0, -18.0)]})

func _barracks() -> void:
	# x 22..42, z -12..14. Bunks to the north, the control room to the south.
	var wall_mat := Mats.wall(HULL, OCHRE, 1.15, 2.0, 0.6)
	_shell(22.0, -12.0, 42.0, 14.0, 4.0, {
		"w": [[-6.0, 2.2, 2.6], [7.0, 2.2, 2.6]], "s": [[36.0, 2.2, 2.6]], "n": [[30.0, 2.2, 2.6]],
	}, wall_mat, Color(0.36, 0.36, 0.38))
	_wall(Vector2(22.0, 0.0), Vector2(42.0, 0.0), 4.0, wall_mat, [[32.0, 2.2, 2.6]], 0.3)
	for x: float in [26.0, 30.5, 35.0, 39.5]:
		_box(Vector3(x, 0.35, -10.0), Vector3(1.1, 0.7, 2.2), Mats.surface(STEEL, "metal", 0.6, 0.3))
		_box(Vector3(x, 1.5, -10.0), Vector3(1.1, 0.12, 2.2), Mats.surface(STEEL, "metal", 0.6, 0.3))
	_barrier(32.0, -4.5, 3.4)
	# Control room: a console bank and a wall of screens.
	_box(Vector3(32.0, 0.55, 6.5), Vector3(7.0, 1.1, 1.2), Mats.surface(HULL_DARK, "metal", 0.4, 0.6))
	_box(Vector3(32.0, 1.14, 6.5), Vector3(6.6, 0.04, 0.8), Mats.glow(TEAL, 1.6), false)
	_box(Vector3(41.7, 2.2, 7.0), Vector3(0.06, 1.6, 8.0), Mats.glow(Color(0.25, 0.6, 0.75), 1.3), false)
	_crate(25.0, 11.5, Vector3(1.4, 1.4, 1.4), RUST, 0.2)
	_lamp(Vector3(32.0, 3.6, -6.0), LIGHT_WARM, 2.2, 13.0)
	_lamp(Vector3(32.0, 3.6, 7.0), LIGHT_COOL, 2.2, 13.0, true)
	_mark(Vector3(23.0, 0.0, -11.0), "locker", PI * 0.5)
	_mark(Vector3(41.0, 0.0, -5.0), "locker", -PI * 0.5)
	_mark(Vector3(40.6, 0.0, 12.6), "crate", -PI * 0.5)
	_mark(Vector3(27.0, 0.0, 1.0), "crate")
	squads.append({"members": ["trooper", "lobber", "rusher"], "points": [
		Vector3(32.0, 0.0, 3.0), Vector3(36.0, 0.0, 10.5), Vector3(28.0, 0.0, -7.0), Vector3(18.0, 0.0, 7.0)]})

func _courtyard() -> void:
	# Landing pad, a parked hauler, coolant tanks, and enough cover to cross on.
	var pad := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 7.0
	disc.bottom_radius = 7.0
	disc.height = 0.06
	disc.radial_segments = 48
	pad.mesh = disc
	pad.material_override = Mats.surface(HULL_DARK, "concrete", 0.6, 0.2)
	pad.position = Vector3(2.0, 0.03, 4.0)
	add_child(pad)
	for i in 12:
		var angle := TAU * i / 12.0
		_box(Vector3(2.0, 0.07, 4.0) + Vector3(cos(angle), 0.0, sin(angle)) * 6.4, Vector3(0.9, 0.03, 0.16), Mats.glow(OCHRE, 2.0), false, false, -angle + PI * 0.5)
	_barrier(-6.5, 1.0, 3.2, PI * 0.5)
	_barrier(10.5, 8.0, 3.2, PI * 0.5)
	_barrier(2.0, -6.0, 3.6)
	_barrier(4.0, 14.0, 3.6)
	_barrier(15.0, -4.0, 3.0, 0.5)
	# Hauler: cab and bed, good hard cover in the open.
	_box(Vector3(-10.0, 1.3, 12.0), Vector3(2.6, 2.2, 6.4), Mats.surface(TEAL.darkened(0.25), "metal", 0.45, 0.5), true, true, 0.25)
	_box(Vector3(-9.1, 1.5, 15.6), Vector3(2.4, 2.6, 2.2), Mats.surface(HULL, "metal", 0.45, 0.5), true, true, 0.25)
	_box(Vector3(-10.0, 0.25, 12.6), Vector3(2.9, 0.5, 8.0), Mats.surface(Color(0.08, 0.08, 0.09), "plain", 0.9), false, false, 0.25)
	# Coolant tanks.
	for spot: Vector2 in [Vector2(13.0, -9.0), Vector2(16.4, -9.6)]:
		var tank := CylinderMesh.new()
		tank.top_radius = 1.4
		tank.bottom_radius = 1.4
		tank.height = 4.2
		var body := StaticBody3D.new()
		body.collision_layer = Layers.WORLD | NAV_SOURCE
		body.collision_mask = 0
		body.position = Vector3(spot.x, 2.1, spot.y)
		var visual := MeshInstance3D.new()
		visual.mesh = tank
		visual.material_override = Mats.surface(HULL, "metal", 0.35, 0.7)
		var shape := CylinderShape3D.new()
		shape.radius = 1.4
		shape.height = 4.2
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		body.add_child(visual)
		add_child(body)
		_box(Vector3(spot.x, 3.0, spot.y), Vector3(2.86, 0.25, 2.86), Mats.surface(RUST, "plain", 0.5), false)
	_crate(-14.0, -4.0, Vector3(1.4, 1.4, 1.4), OCHRE, 0.4)
	_crate(-15.3, -3.2, Vector3(1.2, 1.2, 1.2), STEEL, 0.1)
	_crate(17.0, 14.0, Vector3(1.6, 1.6, 1.6), STEEL, 0.6)
	_crate(-2.0, -11.0, Vector3(1.4, 1.0, 2.4), RUST)
	# Floodlight masts.
	for spot: Vector2 in [Vector2(-14.0, 6.0), Vector2(18.0, -1.0)]:
		_box(Vector3(spot.x, 4.0, spot.y), Vector3(0.25, 8.0, 0.25), Mats.surface(HULL_DARK, "metal", 0.5, 0.6))
		_box(Vector3(spot.x, 8.0, spot.y), Vector3(1.2, 0.3, 0.5), Mats.glow(LIGHT_WARM, 5.0), false)
		_lamp(Vector3(spot.x, 7.6, spot.y), LIGHT_WARM, 3.5, 20.0, false, false)
	_mark(Vector3(-11.8, 0.0, 16.6), "crate", 0.25)
	_mark(Vector3(14.6, 0.0, -11.6), "crate")
	squads.append({"members": ["trooper", "trooper", "lobber"], "points": [
		Vector3(2.0, 0.0, 4.0), Vector3(-9.0, 0.0, -2.0), Vector3(12.0, 0.0, 0.0), Vector3(8.0, 0.0, 14.0), Vector3(-4.0, 0.0, 14.0)]})

func _container_yard() -> void:
	# z 19..33: stacked shipping containers. Long sightlines down the lanes,
	# none across them.
	var colors: Array[Color] = [RUST, TEAL.darkened(0.2), OCHRE, HULL, STEEL]
	var spots: Array = [
		[-24.0, 22.0, 0.0, 0], [-24.0, 28.5, 0.0, 3], [-14.0, 25.0, PI * 0.5, 1], [-6.0, 21.0, 0.0, 2],
		[-6.0, 29.5, 0.0, 4], [3.0, 25.0, PI * 0.5, 0], [12.0, 22.0, 0.0, 1], [12.0, 30.0, 0.0, 2],
		[21.0, 26.0, PI * 0.5, 3], [29.0, 22.5, 0.0, 4], [29.0, 30.0, 0.0, 0],
	]
	for spot: Array in spots:
		_box(Vector3(spot[0], 1.3, spot[1]), Vector3(6.4, 2.6, 2.5), Mats.surface(colors[spot[3]], "metal", 0.55, 0.45), true, true, spot[2], 0.07)
		# Corrugation ribs and a door frame at one end.
		for rib in 9:
			for face: float in [-1.0, 1.0]:
				_box(Vector3(spot[0], 1.3, spot[1]) + Vector3(-2.6 + rib * 0.65, 0.0, face * 1.27).rotated(Vector3.UP, spot[2]), Vector3(0.2, 2.3, 0.09), Mats.surface((colors[spot[3]] as Color).darkened(0.2), "metal", 0.55, 0.45), false, false, spot[2], 0.02)
		_box(Vector3(spot[0], 1.3, spot[1]) + Vector3(3.21, 0.0, 0.0).rotated(Vector3.UP, spot[2]), Vector3(0.05, 2.3, 2.2), Mats.surface((colors[spot[3]] as Color).darkened(0.3), "metal", 0.5, 0.5), false, false, spot[2], 0.02)
	# A few stacked two-high.
	_box(Vector3(-24.0, 3.9, 22.0), Vector3(6.4, 2.6, 2.5), Mats.surface(OCHRE, "metal", 0.55, 0.45), true, false)
	_box(Vector3(12.0, 3.9, 30.0), Vector3(6.4, 2.6, 2.5), Mats.surface(RUST, "metal", 0.55, 0.45), true, false)
	_barrier(-32.0, 24.0, 3.0, 0.4)
	_barrier(36.0, 26.0, 3.0, PI * 0.5)
	_crate(-18.5, 31.0, Vector3(1.2, 1.2, 1.2), STEEL, 0.3)
	_mark(Vector3(-20.0, 0.0, 25.2), "crate", PI)
	_mark(Vector3(7.0, 0.0, 32.6), "crate")
	_mark(Vector3(24.6, 0.0, 22.0), "locker", PI * 0.5)
	squads.append({"members": ["trooper", "rusher"], "points": [
		Vector3(8.0, 0.0, 26.0), Vector3(17.0, 0.0, 20.0), Vector3(-1.0, 0.0, 31.5), Vector3(24.0, 0.0, 31.0)]})
	squads.append({"members": ["marksman", "trooper"], "points": [Vector3(36.0, 0.0, -26.0), Vector3(28.0, 0.0, -22.0), Vector3(38.0, 0.0, -17.0)]})
	extracts.append({"position": Vector3(39.0, 0.0, -29.0), "name": "North pad"})
	extracts.append({"position": Vector3(39.5, 0.0, 30.0), "name": "South gate"})

# Mesas beyond the wall. Scenery only: no colliders, no shadows.
func _horizon() -> void:
	var rock := Mats.surface(Color(0.40, 0.31, 0.30), "concrete", 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4   # fixed: this is set dressing, the same every raid
	for i in 22:
		var angle := TAU * i / 22.0 + rng.randf() * 0.2
		var distance := rng.randf_range(190.0, 360.0)
		var height := rng.randf_range(10.0, 38.0)
		var mesa := _box(Vector3(cos(angle) * distance, height * 0.5 - 4.0, sin(angle) * distance),
			Vector3(rng.randf_range(30.0, 90.0), height, rng.randf_range(30.0, 80.0)), rock, false, false, rng.randf() * PI)
		mesa.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _placements() -> void:
	# Raise patrol and container points a hair so nothing starts inside the floor.
	for squad in squads:
		var points: Array = squad["points"]
		for i in points.size():
			points[i] += Vector3(0.0, 0.05, 0.0)

# Called by the raid once the loot containers are in, so the navmesh routes
# round them too.
func bake() -> void:
	var mesh := NavigationMesh.new()
	mesh.agent_radius = 0.5
	mesh.agent_height = 1.75
	mesh.agent_max_climb = 0.25
	mesh.agent_max_slope = 40.0
	mesh.cell_size = 0.25
	mesh.cell_height = 0.25
	# Drops the islands that form on top of crates and containers.
	mesh.region_min_size = 220.0
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = NAV_SOURCE
	navigation_mesh = mesh
	bake_navigation_mesh(false)
