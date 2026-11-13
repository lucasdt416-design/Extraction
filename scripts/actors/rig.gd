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
	var limb := Mats.surface(Color(0.17, 0.18, 0.2), "plain", 0.6, 0.2)
	var plate := Mats.surface(body_color.lightened(0.3), "metal", 0.5, 0.3)
	var trim := Mats.surface(accent.darkened(0.15), "plain", 0.45, 0.2)
	var lit := Mats.glow(accent, 4.0)

	# Legs: thigh pivots at the hip, shin pivots at the knee.
	for side: float in [-1.0, 1.0]:
		var thigh := _pivot(self, Vector3(0.11 * side * bulk, 0.92, 0.0))
		_capsule(thigh, Vector3(0.0, -0.22, 0.0), 0.075 * bulk, 0.46, limb)
		_block(thigh, Vector3(0.0, -0.2, -0.05), Vector3(0.15 * bulk, 0.3, 0.1), plate)
		var shin := _pivot(thigh, Vector3(0.0, -0.45, 0.0))
		_capsule(shin, Vector3(0.0, -0.22, 0.0), 0.06 * bulk, 0.46, limb)
		_block(shin, Vector3(0.0, -0.2, -0.045), Vector3(0.12 * bulk, 0.3, 0.08), plate)
		_block(shin, Vector3(0.0, -0.44, -0.05), Vector3(0.11 * bulk, 0.07, 0.24), limb)
		_legs.append(thigh)
		_shins.append(shin)

	_block(self, Vector3(0.0, 0.94, 0.0), Vector3(0.34 * bulk, 0.16, 0.2), limb)
	_upper = _pivot(self, Vector3(0.0, 1.0, 0.0))
	_capsule(_upper, Vector3(0.0, 0.25, 0.0), 0.13 * bulk, 0.5, limb)
	# Chest and back plates, a coloured collar, and a lit spine.
	_block(_upper, Vector3(0.0, 0.3, -0.09), Vector3(0.36 * bulk, 0.34, 0.14), plate)
	_block(_upper, Vector3(0.0, 0.3, 0.1), Vector3(0.3 * bulk, 0.36, 0.1), plate)
	_block(_upper, Vector3(0.0, 0.5, 0.0), Vector3(0.44 * bulk, 0.07, 0.26), trim)
	_block(_upper, Vector3(0.0, 0.3, 0.155), Vector3(0.035, 0.3, 0.012), lit)
	_block(_upper, Vector3(0.0, 0.08, -0.07), Vector3(0.26 * bulk, 0.12, 0.1), plate)

	_head = _pivot(_upper, Vector3(0.0, 0.6, 0.0))
	_capsule(_head, Vector3(0.0, 0.03, 0.0), 0.05, 0.12, limb)
	_block(_head, Vector3(0.0, 0.15, 0.0), Vector3(0.19, 0.2, 0.22), plate)
	_block(_head, Vector3(0.0, 0.26, 0.02), Vector3(0.12, 0.03, 0.2), trim)
	_visor = _block(_head, Vector3(0.0, 0.16, -0.112), Vector3(0.15, 0.045, 0.01), lit)

	# Arms and the weapon move as one unit about the shoulders.
	_arms = _pivot(_upper, Vector3(0.0, 0.42, 0.0))
	for side: float in [-1.0, 1.0]:
		_block(_arms, Vector3(0.24 * side * bulk, 0.02, 0.0), Vector3(0.14 * bulk, 0.13, 0.18), plate)
		var upper_arm := _capsule(_arms, Vector3(0.23 * side * bulk, -0.1, -0.1), 0.05 * bulk, 0.3, limb)
		upper_arm.rotation = Vector3(deg_to_rad(-50.0), 0.0, 0.0)
		var forearm := _capsule(_arms, Vector3(0.14 * side * bulk, -0.16, -0.33), 0.045 * bulk, 0.3, limb)
		forearm.rotation = Vector3(deg_to_rad(-88.0), deg_to_rad(28.0 * side), 0.0)
	var gun_mat := Mats.surface(Color(0.1, 0.1, 0.11), "plain", 0.35, 0.7)
	_block(_arms, Vector3(0.0, -0.14, -0.3 - weapon_length * 0.5), Vector3(0.05, 0.085, weapon_length), gun_mat)
	_block(_arms, Vector3(0.0, -0.22, -0.3), Vector3(0.04, 0.13, 0.06), gun_mat)
	_block(_arms, Vector3(0.0, -0.09, -0.34 - weapon_length * 0.3), Vector3(0.02, 0.02, weapon_length * 0.45), trim)
	_muzzle = _pivot(_arms, Vector3(0.0, -0.14, -0.32 - weapon_length))

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
	parent.add_child(instance)
	_meshes.append(instance)
	return instance
