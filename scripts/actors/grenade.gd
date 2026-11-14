class_name Grenade
extends Node3D

# Thrown by grenadiers to flush the player out of cover. It flies a fixed arc
# (no physics body), lands, beeps through a fuse with its blast radius drawn on
# the floor, then damages whatever has line of sight to it.

const RADIUS: float = 5.5
const DAMAGE: float = 80.0
const FUSE: float = 1.3

var _from: Vector3
var _to: Vector3
var _flight: float = 1.0
var _age: float = 0.0
var _thrower: Node
var _ring: MeshInstance3D
var _beeps: int = 0

func launch(from: Vector3, to: Vector3, thrower: Node) -> void:
	_from = from
	_to = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, to) + Vector3.UP * 0.1
	_flight = clampf(from.distance_to(_to) / 15.0, 0.6, 1.6)
	_thrower = thrower
	global_position = from
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	var ball := MeshInstance3D.new()
	ball.mesh = mesh
	ball.material_override = Mats.glow(Color(1.0, 0.4, 0.2), 5.0)
	add_child(ball)
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS - 0.08
	torus.outer_radius = RADIUS
	torus.rings = 64
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.material_override = Mats.beam(Color(1.0, 0.35, 0.2), 2.0, 0.7)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)

func _physics_process(delta: float) -> void:
	_age += delta
	if _age < _flight:
		var t := _age / _flight
		global_position = _from.lerp(_to, t) + Vector3.UP * (4.0 * t * (1.0 - t)) * (2.0 + _from.distance_to(_to) * 0.12)
		return
	global_position = _to
	_ring.visible = true
	var fuse := _age - _flight
	if int(fuse / 0.3) >= _beeps:
		_beeps += 1
		Sfx.play_at("beep", _to, 2.0, 1.0 + fuse * 0.4)
	if fuse >= FUSE:
		_explode()

func _explode() -> void:
	Fx.explosion(self, _to + Vector3.UP * 0.3, RADIUS)
	var space := get_world_3d().direct_space_state
	for body in get_tree().get_nodes_in_group("player"):
		var player := body as Player
		if player == null:
			continue
		var distance := player.aim_point().distance_to(_to)
		if distance > RADIUS:
			continue
		var query := PhysicsRayQueryParameters3D.create(_to + Vector3.UP * 0.4, player.aim_point(), Layers.WORLD)
		if space.intersect_ray(query).is_empty():
			player.take_damage(DAMAGE * (1.0 - distance / RADIUS * 0.7), _thrower)
	queue_free()
