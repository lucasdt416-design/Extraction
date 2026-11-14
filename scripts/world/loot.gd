class_name Pickup
extends StaticBody3D

# A single item lying in the world. Found by the player's use-ray on the
# `interact` layer; it blocks nothing. Taking it goes through
# GameManager.add_to_backpack, the one place the backpack grows (rule 2).

const AMMO: String = "ammo"

var item_id: String = ""
var _spin: Node3D

static func drop(parent: Node, id: String, at: Vector3) -> Pickup:
	var pickup := Pickup.new()
	pickup.item_id = id
	parent.add_child(pickup)
	pickup.global_position = at
	return pickup

func _ready() -> void:
	collision_layer = Layers.INTERACT
	collision_mask = 0
	var shape := SphereShape3D.new()
	shape.radius = 0.38
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 0.3
	add_child(collider)

	var color := Color(0.9, 0.85, 0.7) if item_id == AMMO else Catalog.rarity_color(item_id)
	var rarity := 0 if item_id == AMMO else int(Catalog.item(item_id).get("rarity", 0))
	_spin = Node3D.new()
	_spin.position.y = 0.32
	add_child(_spin)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.3, 0.12, 0.2) if item_id == AMMO else Vector3(0.24, 0.24, 0.24)
	var body := MeshInstance3D.new()
	body.mesh = mesh
	body.material_override = Mats.surface(Color(0.14, 0.15, 0.17), "plain", 0.4, 0.6)
	_spin.add_child(body)
	var band := BoxMesh.new()
	band.size = mesh.size * Vector3(1.04, 0.22, 1.04)
	var stripe := MeshInstance3D.new()
	stripe.mesh = band
	stripe.material_override = Mats.glow(color, 2.5 + rarity)
	_spin.add_child(stripe)
	# Rare finds get a thin column of light you can spot across a room.
	if rarity >= 2:
		var beam := MeshInstance3D.new()
		var column := BoxMesh.new()
		column.size = Vector3(0.03, 2.4, 0.03)
		beam.mesh = column
		beam.position.y = 1.4
		beam.material_override = Mats.beam(color, 1.5, 0.4)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(beam)

func _process(delta: float) -> void:
	_spin.rotation.y += delta * 1.2
	_spin.position.y = 0.32 + sin(Time.get_ticks_msec() * 0.003 + position.x) * 0.04

func can_interact() -> bool:
	return true

func interact_label() -> String:
	if item_id == AMMO:
		return "Take ammo"
	return "Take %s" % Catalog.item_name(item_id)

func interact_time() -> float:
	return 0.0

func interact(player: Player) -> void:
	if item_id == AMMO:
		player.add_ammo(1)
		Sfx.play("pickup", -6.0, 0.8)
	elif GameManager.add_to_backpack(item_id):
		Sfx.play("rare" if int(Catalog.item(item_id).get("rarity", 0)) >= 2 else "pickup", -6.0)
	else:
		player.notice.emit("Backpack full")
		return
	queue_free()
