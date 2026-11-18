class_name SupplyDrop
extends Node3D

# A supply drone bringing a crate of good kit down into the open. It is
# announced and marked on the map as soon as it is called, takes FLIGHT seconds
# to come in, sets the crate down and leaves. A tall coral column stands over
# the crate until someone opens it, and opening it is loud (LootContainer,
# "drop"). Placed by Raid; the contents are rolled from the raid's stream.

const FLIGHT: float = 30.0
const DRONE: String = "res://cairn_divide/art/detail/frontier_drone.glb"

var eta: float = FLIGHT
var crate: LootContainer
var _drone: Node3D
var _carried: MeshInstance3D
var _beam: MeshInstance3D
var _from := Vector3.ZERO
var _leaving: float = -1.0
var _rng: RandomNumberGenerator

func setup(rng: RandomNumberGenerator) -> void:
	_rng = rng
	var angle := rng.randf() * TAU
	_from = Vector3(cos(angle) * 300.0, 170.0, sin(angle) * 300.0)

func _ready() -> void:
	_drone = (load(DRONE) as PackedScene).instantiate()
	add_child(_drone)
	_carried = MeshInstance3D.new()
	_carried.mesh = Shapes.rounded_box(LootContainer.SPECS["drop"]["size"], 0.04, 2)
	_carried.material_override = Mats.surface(LootContainer.SPECS["drop"]["color"], "metal", 0.45, 0.55)
	_carried.position = Vector3(0.0, -0.6, 0.0)
	_drone.add_child(_carried)
	var column := CylinderMesh.new()
	column.top_radius = 0.3
	column.bottom_radius = 1.2
	column.height = 60.0
	column.cap_top = false
	column.cap_bottom = false
	_beam = MeshInstance3D.new()
	_beam.mesh = column
	_beam.position.y = 30.0
	_beam.material_override = Mats.beam(UiKit.CORAL, 1.2, 0.12)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	_place(0.0)

func is_open() -> bool:
	return crate != null and crate.opened

func _physics_process(delta: float) -> void:
	if eta > 0.0:
		eta = maxf(eta - delta, 0.0)
		_place(1.0 - eta / FLIGHT)
		if eta == 0.0:
			_set_down()
	elif _leaving >= 0.0:
		_leaving += delta
		_drone.position += Vector3(0.0, 6.0 + _leaving * 4.0, 0.0) * delta + (-_from.normalized()) * 12.0 * delta * _leaving
		if _leaving > 12.0:
			_drone.queue_free()
			_leaving = -1.0
	if is_open() and _beam.visible:
		_beam.visible = false

# Fast and high, then slowing and dropping onto the spot.
func _place(t: float) -> void:
	var glide := 1.0 - pow(1.0 - t, 3.0)
	var at := _from.lerp(Vector3.ZERO, glide)
	at.y = lerpf(_from.y, 1.3, pow(clampf((t - 0.3) / 0.7, 0.0, 1.0), 0.6))
	_drone.position = at
	var ahead := -_from
	_drone.rotation.y = atan2(ahead.x, ahead.z)
	_drone.rotation.z = sin(t * 11.0) * 0.03

func _set_down() -> void:
	_carried.queue_free()
	crate = LootContainer.new()
	crate.setup("drop", _rng)
	crate.rotation.y = _rng.randf() * TAU
	crate.position.y = -0.12   # bedded into the slope a little
	add_child(crate)
	Sfx.play_at("door", global_position, 2.0, 0.6, 70.0)
	_leaving = 0.0
