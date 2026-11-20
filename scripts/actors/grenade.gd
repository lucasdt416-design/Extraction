class_name Grenade
extends Node3D

# Enemy grenades flush the player out of cover. The player charge collides
# along its flight arc and also damages hostile troops and aircraft mounts.

const RADIUS: float = 5.5
const DAMAGE: float = 80.0
const FUSE: float = 1.3
const CHARGE_RADIUS := 7.0
const CHARGE_DAMAGE := 185.0
const CHARGE_FUSE := 0.75

var _from: Vector3
var _to: Vector3
var _flight: float = 1.0
var _age: float = 0.0
var _thrower: Node
var _ring: MeshInstance3D
var _beeps: int = 0
var _player_charge := false
var _burst_in_air := false
var _radius := RADIUS
var _launch_direction := Vector3.ZERO

func launch(from: Vector3, to: Vector3, thrower: Node) -> void:
	_from = from
	_to = NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, to) + Vector3.UP * 0.1
	_flight = clampf(from.distance_to(_to) / 15.0, 0.6, 1.6)
	_build(thrower, from)

func launch_charge(from: Vector3, direction: Vector3, thrower: Player) -> void:
	_player_charge = true
	_radius = CHARGE_RADIUS
	_launch_direction = direction.normalized()
	_from = from
	_flight = 1.45
	_build(thrower, from)

func _build(thrower: Node, from: Vector3) -> void:
	_thrower = thrower
	global_position = from
	var mesh := SphereMesh.new()
	mesh.radius = 0.09
	mesh.height = 0.18
	var ball := MeshInstance3D.new()
	ball.mesh = mesh
	var color := Color(0.25, 0.85, 1.0) if _player_charge else Color(1.0, 0.4, 0.2)
	ball.material_override = Mats.glow(color, 5.0)
	add_child(ball)
	var torus := TorusMesh.new()
	torus.inner_radius = _radius - 0.08
	torus.outer_radius = _radius
	torus.rings = 64
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.material_override = Mats.beam(color, 2.0, 0.7)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)

func _physics_process(delta: float) -> void:
	_age += delta
	if _player_charge and _age - delta < _flight:
		_fly_charge()
		if _age < _flight:
			return
	if _age < _flight:
		var t := _age / _flight
		global_position = _from.lerp(_to, t) + Vector3.UP * (4.0 * t * (1.0 - t)) * (2.0 + _from.distance_to(_to) * 0.12)
		return
	global_position = _to
	_ring.visible = not _burst_in_air
	var fuse := _age - _flight
	if int(fuse / 0.3) >= _beeps:
		_beeps += 1
		Sfx.play_at("beep", _to, 2.0, 1.0 + fuse * 0.4)
	if fuse >= (CHARGE_FUSE if _player_charge else FUSE):
		_explode()

func _fly_charge() -> void:
	var t := minf(_age, _flight)
	var next := _from + _launch_direction * 30.0 * t + Vector3.UP * (4.0 * t - 9.0 * t * t)
	var query := PhysicsRayQueryParameters3D.create(global_position, next, Layers.WORLD | Layers.ENEMY)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var normal: Vector3 = hit["normal"]
		_to = hit["position"] + normal * 0.12
		_flight = _age
		var target := hit["collider"] as CollisionObject3D
		_burst_in_air = normal.y < 0.65 or (target != null and (target.collision_layer & Layers.ENEMY) != 0)
		# Impact bursts in the air or against a wall; on the ground the fuse gives a warning.
		if _burst_in_air:
			_age += CHARGE_FUSE
	elif _age >= _flight:
		_to = next
		_burst_in_air = true
	else:
		global_position = next

func _explode() -> void:
	Fx.explosion(self, _to + Vector3.UP * 0.3, _radius)
	get_tree().call_group("grass", "blast", _to, _radius)
	var space := get_world_3d().direct_space_state
	if _player_charge:
		for body in get_tree().get_nodes_in_group("enemy"):
			var enemy := body as Enemy
			if enemy.is_dead or not enemy.is_physics_processing():
				continue
			var at := enemy.global_position + Vector3.UP * 0.95
			var damage := _blast_damage(space, at, CHARGE_DAMAGE)
			if damage > 0.0:
				enemy.take_damage(damage, _thrower, at)
		for cannon in get_tree().get_nodes_in_group("aircraft_weapon"):
			var damage := _blast_damage(space, cannon.global_position, CHARGE_DAMAGE)
			if damage > 0.0:
				cannon.take_blast(damage)
	for body in get_tree().get_nodes_in_group("player"):
		var player := body as Player
		if player == null:
			continue
		var damage := _blast_damage(space, player.aim_point(), DAMAGE)
		if damage > 0.0:
			player.take_damage(damage, _thrower)
	queue_free()

func _blast_damage(space: PhysicsDirectSpaceState3D, at: Vector3, base_damage: float) -> float:
	var distance := at.distance_to(_to)
	if distance > _radius:
		return 0.0
	var origin := _to if _burst_in_air else _to + Vector3.UP * 0.4
	var query := PhysicsRayQueryParameters3D.create(origin, at, Layers.WORLD)
	return base_damage * (1.0 - distance / _radius * 0.7) if space.intersect_ray(query).is_empty() else 0.0
