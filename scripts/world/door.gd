class_name Door
extends AnimatableBody3D

# A sliding slab: a building door, a shutter leaf or a cordon gate. It blocks
# movement, shots and sight while shut. The player works it from a DoorSwitch;
# guards carry a pass, so it opens for them as they walk up and shuts again
# behind them -- which is also how you hear them coming.
#
# The door owns its own state (rule 2): everything else calls open(), close()
# or toggle() and listens to `changed`.

signal changed

var size := Vector3(2.4, 3.3, 0.12)
var slide := Vector3(-2.3, 0.0, 0.0)   # where it goes when open, in its own axes
var travel: float = 0.7                # seconds to open or shut
var noise: float = 7.0                 # how far the guards hear the player work it
var what: String = "door"
var is_open: bool = false
var material: Material

var _amount: float = 0.0               # 0 shut, 1 open
var _home := Vector3.ZERO
var _threshold: Area3D
var _approach: Area3D
var _guard_opened: bool = false
var _empty_for: float = 0.0

func _ready() -> void:
	add_to_group("door")
	collision_layer = Layers.WORLD
	collision_mask = 0
	sync_to_physics = false
	_home = position
	_amount = 1.0 if is_open else 0.0
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = size.y * 0.5
	add_child(collider)
	var slab := MeshInstance3D.new()
	slab.mesh = Shapes.rounded_box(size, minf(0.03, size.z * 0.3), 2)
	slab.material_override = material if material != null else Mats.wall(Color(0.2, 0.21, 0.23), Level.OCHRE, 0.5, 1.2, 0.5, 0.5)
	slab.position.y = size.y * 0.5
	add_child(slab)
	# A lit slot at eye height, so a shut door reads as a door and not a wall.
	for face: float in [-1.0, 1.0]:
		var slot := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(size.x * 0.5, 0.05, 0.02)
		slot.mesh = mesh
		slot.material_override = Mats.glow(Level.OCHRE, 2.0)
		slot.position = Vector3(0.0, minf(1.6, size.y * 0.5), face * (size.z * 0.5 + 0.005))
		slot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(slot)
	# The doorway itself does not move with the slab, so the sensors sit on the
	# parent, where the slab stands when shut.
	_threshold = _sensor(Vector3(size.x, size.y, 1.3), Layers.PLAYER | Layers.ENEMY)
	_approach = _sensor(Vector3(size.x + 1.0, minf(size.y, 3.0), 6.4), Layers.ENEMY)
	_place()

func _sensor(extent: Vector3, mask: int) -> Area3D:
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = mask
	area.monitorable = false
	var shape := BoxShape3D.new()
	shape.size = extent
	var collider := CollisionShape3D.new()
	collider.shape = shape
	area.add_child(collider)
	area.transform = Transform3D(transform.basis, _home + Vector3(0.0, extent.y * 0.5, 0.0))
	get_parent().add_child.call_deferred(area)
	return area

func open(by: Node = null) -> void:
	_set_open(true, by)

func close(by: Node = null) -> void:
	_set_open(false, by)

func toggle(by: Node = null) -> void:
	_guard_opened = false
	_set_open(not is_open, by)

func moving() -> bool:
	return absf(_amount - (1.0 if is_open else 0.0)) > 0.001

func _set_open(value: bool, by: Node) -> void:
	if is_open == value:
		return
	is_open = value
	Sfx.play_at("door", global_position + Vector3.UP * 1.5, 2.0 if what == "door" else 7.0, 1.0 if what == "door" else 0.6, 30.0 if what == "door" else 90.0)
	if by is Player:
		get_tree().call_group("enemy", "hear", global_position, noise, by)
	changed.emit()

func _physics_process(delta: float) -> void:
	# Guards: open as one walks up, shut once they have all gone through.
	if _approach.is_inside_tree() and _approach.has_overlapping_bodies():
		_empty_for = 0.0
		if not is_open:
			_guard_opened = true
			open()
	elif _guard_opened and is_open:
		_empty_for += delta
		if _empty_for > 2.5:
			_guard_opened = false
			close()
	var target := 1.0 if is_open else 0.0
	if is_equal_approx(_amount, target):
		return
	# Never shuts on someone standing in the doorway.
	if not is_open and _threshold.is_inside_tree() and _threshold.has_overlapping_bodies():
		return
	_amount = move_toward(_amount, target, delta / maxf(travel, 0.05))
	_place()

func _place() -> void:
	var eased := _amount * _amount * (3.0 - 2.0 * _amount)
	position = _home + transform.basis * (slide * eased)
