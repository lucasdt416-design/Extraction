class_name LootContainer
extends StaticBody3D

# A crate, locker or vault that is searched by holding the use key. Its
# contents are rolled from the raid's seeded stream when it is built, not when
# it is opened, so the same seed always hides the same loot (rule 4).

const SPECS: Dictionary = {
	"crate": {"size": Vector3(1.1, 0.75, 0.7), "time": 1.0, "items": [1, 3], "color": Color(0.36, 0.40, 0.42), "label": "Search crate"},
	"locker": {"size": Vector3(0.75, 1.9, 0.55), "time": 1.4, "items": [1, 2], "color": Color(0.62, 0.63, 0.62), "label": "Search locker"},
	"vault": {"size": Vector3(1.3, 1.15, 0.9), "time": 3.5, "items": [3, 4], "color": Color(0.12, 0.12, 0.14), "label": "Crack vault (loud)"},
}

var kind: String = "crate"
var opened: bool = false
var _contents: Array[String] = []
var _has_ammo: bool = false
var _light: MeshInstance3D

func setup(container_kind: String, rng: RandomNumberGenerator) -> void:
	kind = container_kind
	var spec: Dictionary = SPECS[kind]
	var count := rng.randi_range(spec["items"][0], spec["items"][1])
	for i in count:
		_contents.append(Catalog.roll(kind, rng))
	_has_ammo = rng.randf() < 0.6

func _ready() -> void:
	var spec: Dictionary = SPECS[kind]
	var size: Vector3 = spec["size"]
	collision_layer = Layers.WORLD | Layers.INTERACT | Level.NAV_SOURCE
	collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = size.y * 0.5
	add_child(collider)
	_add(Vector3(0.0, size.y * 0.5, 0.0), size, Mats.surface(spec["color"], "metal", 0.45, 0.55))
	_add(Vector3(0.0, size.y * 0.82, 0.0), size * Vector3(1.03, 0.06, 1.03), Mats.surface(Color(0.1, 0.1, 0.11), "plain", 0.4, 0.5))
	# The status light: lit means unopened.
	var color := Level.RUST if kind == "vault" else Level.TEAL.lightened(0.2)
	_light = _add(Vector3(0.0, size.y * 0.62, -size.z * 0.5 - 0.005), Vector3(size.x * 0.4, 0.035, 0.01), Mats.glow(color, 4.0))

func _add(at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = at
	add_child(instance)
	return instance

func can_interact() -> bool:
	return not opened

func interact_label() -> String:
	return SPECS[kind]["label"]

func interact_time() -> float:
	return SPECS[kind]["time"]

func interact(player: Player) -> void:
	opened = true
	_light.material_override = Mats.surface(Color(0.05, 0.05, 0.05), "plain", 0.5)
	Sfx.play("open")
	# Spill the contents out in front, toward whoever opened it.
	var toward := (player.global_position - global_position)
	toward.y = 0.0
	toward = toward.normalized() if toward.length() > 0.1 else Vector3.BACK
	var side := toward.cross(Vector3.UP)
	var drops: Array[String] = _contents.duplicate()
	if _has_ammo:
		drops.append(Pickup.AMMO)
	for i in drops.size():
		var offset := toward * 0.95 + side * (i - (drops.size() - 1) * 0.5) * 0.5
		Pickup.drop(get_parent(), drops[i], Vector3(global_position.x, player.global_position.y, global_position.z) + offset)
	if kind == "vault":
		# Cracking a vault trips its alarm: everyone within earshot comes to look.
		Sfx.play_at("alert", global_position, 8.0, 0.7, 80.0)
		get_tree().call_group("enemy", "hear", global_position, 38.0, player)
		player.notice.emit("Vault alarm tripped")
