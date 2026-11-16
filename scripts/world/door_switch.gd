class_name DoorSwitch
extends StaticBody3D

# The button beside a door or a gate. Amber while the way is shut, teal once it
# is open. One switch can work several slabs (the two leaves of a shutter).

var doors: Array[Door] = []
var _button: MeshInstance3D
var _light: OmniLight3D

func _ready() -> void:
	collision_layer = Layers.WORLD | Layers.INTERACT
	collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.34, 0.46, 0.14)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	add_child(collider)
	var plate := MeshInstance3D.new()
	plate.mesh = Shapes.rounded_box(Vector3(0.34, 0.46, 0.1), 0.02, 2)
	plate.material_override = Mats.surface(Color(0.1, 0.1, 0.11), "metal", 0.45, 0.6)
	add_child(plate)
	_button = MeshInstance3D.new()
	_button.mesh = Shapes.rounded_box(Vector3(0.2, 0.2, 0.06), 0.02, 2)
	_button.position = Vector3(0.0, 0.04, 0.06)
	_button.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_button)
	_light = OmniLight3D.new()
	_light.position = Vector3(0.0, 0.0, 0.35)
	_light.light_energy = 0.5
	_light.omni_range = 2.2
	_light.shadow_enabled = false
	_light.distance_fade_enabled = true
	_light.distance_fade_begin = 40.0
	_light.distance_fade_length = 10.0
	add_child(_light)
	for door in doors:
		door.changed.connect(_show)
	_show()

func _show() -> void:
	var color := Level.TEAL.lightened(0.25) if _open() else Level.OCHRE
	_button.material_override = Mats.glow(color, 4.0)
	_light.light_color = color

func _open() -> bool:
	return not doors.is_empty() and doors[0].is_open

func can_interact() -> bool:
	for door in doors:
		if door.moving():
			return false
	return not doors.is_empty()

func interact_label() -> String:
	return ("Close " if _open() else "Open ") + doors[0].what

func interact_time() -> float:
	return 0.0

func interact(player: Player) -> void:
	Sfx.play("click")
	for door in doors:
		door.toggle(player)
