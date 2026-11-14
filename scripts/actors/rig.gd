class_name Rig
extends Node3D

# A humanoid built from primitives and animated procedurally: no model files,
# no AnimationPlayer. Slim dark limbs under coloured armour plates, with a lit
# visor and spine so a unit's type and facing read from across the yard.
#
# View only (rule 6): the owner tells it how fast it's moving, where it's
# aiming and when it's hit; nothing here feeds back into the simulation.

var _upper: Node3D          # pivots at the waist: leans into aim pitch
var _head: Node3D
var _arms: Node3D           # pivots at the shoulders: raises and lowers the gun
var _legs: Array[Node3D] = []   # [left thigh, right thigh]
var _shins: Array[Node3D] = []
var _muzzle: Node3D
var _visor: MeshInstance3D
var _meshes: Array[MeshInstance3D] = []
var _phase: float = 0.0
var _raise: float = 0.0     # 0 = gun lowered, 1 = shouldered
var _flinch: float = 0.0
var _crouch: float = 0.0
var _accent: Color
var _dead: bool = false

func build(body_color: Color, accent: Color, weapon_length: float, bulk: float = 1.0) -> void:
	_accent = accent
	var joint := Mats.surface(Color(0.11, 0.12, 0.14), "plain", 0.45, 0.6)
	var cloth := Mats.surface(Color(0.16, 0.17, 0.2), "plain", 0.85, 0.0)
	var plate := Mats.surface(body_color.lightened(0.3), "plain", 0.38, 0.25)
	var trim := Mats.surface(accent.darkened(0.1), "plain", 0.4, 0.15)
	var lit := Mats.glow(accent, 4.0)

	# Legs: thigh pivots at the hip, shin at the knee. Tapered limbs under
	# armour shells, ball joints at hip and knee, a booted foot.
	for side: float in [-1.0, 1.0]:
		var thigh := _pivot(self, Vector3(0.105 * side * bulk, 0.92, 0.0))
		_ball(thigh, Vector3.ZERO, 0.075 * bulk, joint)
		_taper(thigh, Vector3(0.0, -0.22, 0.0), 0.08 * bulk, 0.06 * bulk, 0.42, cloth)
		_block(thigh, Vector3(0.0, -0.2, -0.04), Vector3(0.14 * bulk, 0.3, 0.11), plate)
		_block(thigh, Vector3(side * 0.07 * bulk, -0.16, 0.0), Vector3(0.03, 0.12, 0.09), trim)
		var shin := _pivot(thigh, Vector3(0.0, -0.45, 0.0))
		_ball(shin, Vector3.ZERO, 0.06 * bulk, joint)
		_taper(shin, Vector3(0.0, -0.22, 0.0), 0.055 * bulk, 0.04 * bulk, 0.42, cloth)
		_block(shin, Vector3(0.0, -0.19, -0.03), Vector3(0.11 * bulk, 0.32, 0.1), plate)
		_block(shin, Vector3(0.0, -0.435, -0.045), Vector3(0.105 * bulk, 0.085, 0.26), joint)
		_block(shin, Vector3(0.0, -0.47, -0.045), Vector3(0.115 * bulk, 0.025, 0.27), trim)
		_legs.append(thigh)
		_shins.append(shin)

	# Pelvis with belt pouches.
	_block(self, Vector3(0.0, 0.95, 0.0), Vector3(0.33 * bulk, 0.17, 0.21), cloth)
	_block(self, Vector3(0.0, 1.0, 0.0), Vector3(0.35 * bulk, 0.045, 0.23), joint)
	for side: float in [-1.0, 1.0]:
		_block(self, Vector3(side * 0.16 * bulk, 0.95, -0.07), Vector3(0.08, 0.1, 0.07), joint)

	_upper = _pivot(self, Vector3(0.0, 1.0, 0.0))
	# A ribbed waist under a rounded chest shell, a pack on the back.
	for rib in 3:
		_taper(_upper, Vector3(0.0, 0.05 + rib * 0.05, 0.0), 0.115 * bulk, 0.115 * bulk, 0.035, joint)
	_block(_upper, Vector3(0.0, 0.36, -0.005), Vector3(0.4 * bulk, 0.36, 0.26), plate)
	_block(_upper, Vector3(0.0, 0.3, -0.135), Vector3(0.16 * bulk, 0.11, 0.035), trim)
	_block(_upper, Vector3(0.0, 0.44, -0.132), Vector3(0.1 * bulk, 0.012, 0.012), lit)
	_block(_upper, Vector3(0.0, 0.36, 0.17), Vector3(0.27 * bulk, 0.32, 0.13), joint)
	for side: float in [-1.0, 1.0]:
		_taper(_upper, Vector3(side * 0.07 * bulk, 0.37, 0.25), 0.04, 0.04, 0.24, trim)
	_block(_upper, Vector3(0.0, 0.36, 0.238), Vector3(0.03, 0.26, 0.012), lit)
	_taper(_upper, Vector3(0.0, 0.565, 0.0), 0.1 * bulk, 0.12 * bulk, 0.05, trim)

	# Head: a smooth helmet with a horizontal visor slit and ear units.
	_head = _pivot(_upper, Vector3(0.0, 0.6, 0.0))
	_taper(_head, Vector3(0.0, 0.03, 0.0), 0.04, 0.05, 0.1, joint)
	var helmet := _ball(_head, Vector3(0.0, 0.17, 0.0), 0.118, plate)
	helmet.scale = Vector3(1.0, 1.14, 1.12)
	_block(_head, Vector3(0.0, 0.175, -0.09), Vector3(0.2, 0.055, 0.07), joint)
	_visor = _block(_head, Vector3(0.0, 0.175, -0.124), Vector3(0.15, 0.026, 0.012), lit)
	for side: float in [-1.0, 1.0]:
		var ear := _taper(_head, Vector3(side * 0.118, 0.16, 0.01), 0.04, 0.04, 0.03, trim)
		ear.rotation.z = PI * 0.5

	# Arms and weapon move as one unit about the shoulders.
	_arms = _pivot(_upper, Vector3(0.0, 0.42, 0.0))
	var gun_z := -0.3 - weapon_length * 0.5
	for side: float in [-1.0, 1.0]:
		var shoulder := Vector3(0.245 * side * bulk, 0.03, 0.0)
		var pauldron := _ball(_arms, shoulder, 0.09 * bulk, trim if side > 0.0 else plate)
		pauldron.scale = Vector3(1.0, 1.15, 1.1)
		var elbow := Vector3(0.22 * side * bulk, -0.17, -0.17)
		# Trigger hand on the grip; support hand forward under the barrel.
		var hand := Vector3(0.035, -0.2, -0.3) if side > 0.0 else Vector3(-0.03, -0.17, -0.34 - weapon_length * 0.4)
		_limb(_arms, shoulder, elbow, 0.05 * bulk, cloth)
		_ball(_arms, elbow, 0.052 * bulk, joint)
		_limb(_arms, elbow, hand, 0.042 * bulk, plate)
		_ball(_arms, hand, 0.045, joint)
	var gun_mat := Mats.surface(Color(0.09, 0.09, 0.1), "plain", 0.38, 0.7)
	_block(_arms, Vector3(0.0, -0.14, gun_z), Vector3(0.05, 0.085, weapon_length), gun_mat)
	_block(_arms, Vector3(0.0, -0.225, -0.3), Vector3(0.04, 0.12, 0.055), gun_mat)
	_block(_arms, Vector3(0.0, -0.215, gun_z + 0.02), Vector3(0.03, 0.12, 0.05), joint)
	var barrel := _taper(_arms, Vector3(0.0, -0.13, -0.3 - weapon_length - 0.04), 0.014, 0.014, 0.12, gun_mat)
	barrel.rotation.x = PI * 0.5
	_block(_arms, Vector3(0.0, -0.088, gun_z), Vector3(0.016, 0.018, weapon_length * 0.5), trim)
	_muzzle = _pivot(_arms, Vector3(0.0, -0.13, -0.4 - weapon_length))

# Called every rendered frame by the owner.
#   speed    ground speed in m/s
#   raised   whether the weapon should be shouldered
#   pitch    aim pitch in radians (positive looks up)
func animate(delta: float, speed: float, raised: bool, pitch: float, crouched: bool = false) -> void:
	if _dead:
		return
	_phase += delta * (4.0 + speed * 2.4)
	var stride := clampf(speed / 3.5, 0.0, 1.0)
	_crouch = move_toward(_crouch, 1.0 if crouched else 0.0, delta * 5.0)
	_raise = move_toward(_raise, 1.0 if raised else 0.0, delta * 5.0)
	_flinch = move_toward(_flinch, 0.0, delta * 4.0)

	for i in 2:
		var swing := sin(_phase + PI * i) * 0.75 * stride
		_legs[i].rotation.x = swing - _crouch * 0.9
		_shins[i].rotation.x = -(maxf(-cos(_phase + PI * i), 0.0) * 0.9 * stride) - _crouch * -1.7
	position.y = absf(sin(_phase)) * 0.035 * stride - _crouch * 0.3
	_upper.rotation.x = clampf(pitch, -0.5, 0.5) * 0.45 + _crouch * -0.2 - stride * 0.1 - _flinch * 0.3
	_upper.rotation.z = sin(_phase) * 0.04 * stride + _flinch * 0.15
	_upper.rotation.y = sin(_phase) * 0.08 * stride
	_arms.rotation.x = lerpf(-0.75, 0.0, _raise) + clampf(pitch, -0.6, 0.6) * 0.5 + sin(_phase * 0.5) * 0.02
	_head.rotation.x = clampf(pitch, -0.5, 0.5) * 0.4

func flinch() -> void:
	_flinch = 1.0

func muzzle_position() -> Vector3:
	return _muzzle.global_position

func head_position() -> Vector3:
	return _head.global_position + Vector3(0.0, 0.15, 0.0)

# 0 = solid, 1 = invisible. Used by cloaking units.
func set_fade(amount: float) -> void:
	for mesh in _meshes:
		mesh.transparency = amount

# Lights out and topple over, away from whatever killed us.
func die(push: Vector3) -> void:
	_dead = true
	set_fade(0.0)
	_visor.material_override = Mats.surface(Color(0.05, 0.05, 0.05), "plain", 0.4)
	var flat := Vector3(push.x, 0.0, push.z)
	var local := (global_transform.basis.inverse() * flat).normalized() if flat.length() > 0.01 else Vector3.BACK
	var tween := create_tween().set_parallel(true).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "rotation:x", local.z * 1.5, 0.45)
	tween.tween_property(self, "rotation:z", -local.x * 1.5, 0.45)
	tween.tween_property(self, "position:y", -0.72, 0.45)
	tween.tween_property(_arms, "rotation:x", -1.1, 0.3)

func _pivot(parent: Node3D, at: Vector3) -> Node3D:
	var node := Node3D.new()
	node.position = at
	parent.add_child(node)
	return node

func _block(parent: Node3D, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	# Bevelled, so armour plates catch a highlight along their edges.
	return _add(parent, at, Shapes.rounded_box(size, minf(size.x, minf(size.y, size.z)) * 0.28, 1), mat)

func _ball(parent: Node3D, at: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 14
	mesh.rings = 7
	return _add(parent, at, mesh, mat)

# A cylinder that can narrow toward one end: limbs, collars, canisters.
func _taper(parent: Node3D, at: Vector3, top: float, bottom: float, height: float, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 10
	return _add(parent, at, mesh, mat)

# A capsule between two points.
func _limb(parent: Node3D, from: Vector3, to: Vector3, radius: float, mat: Material) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = from.distance_to(to) + radius * 2.0
	mesh.radial_segments = 14
	mesh.rings = 4
	var instance := _add(parent, Vector3.ZERO, mesh, mat)
	var up := (to - from).normalized()
	var side := up.cross(Vector3.FORWARD).normalized()
	instance.transform = Transform3D(Basis(side, up, side.cross(up)), (from + to) * 0.5)

func _capsule(parent: Node3D, at: Vector3, radius: float, height: float, mat: Material) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 4
	return _add(parent, at, mesh, mat)

func _add(parent: Node3D, at: Vector3, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = at
	# Only the big shapes cast shadows; small trim wouldn't show in one anyway.
	if mesh.get_aabb().get_longest_axis_size() < 0.2:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	_meshes.append(instance)
	return instance
