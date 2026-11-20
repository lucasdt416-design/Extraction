extends StaticBody3D

signal disabled

const RANGE := 84.0
const ARMOR := 120.0
const WARNING := 1.0

var side: float = 1.0
var _health := ARMOR
var _delay := 0.0
var _charge := 0.0
var _shots := 0
var _aim := Vector3.ZERO
var _assembly := Node3D.new()
var _beam := MeshInstance3D.new()

func _ready() -> void:
	collision_layer = Layers.ENEMY
	collision_mask = 0
	add_to_group("aircraft_weapon")

	var hitbox := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.35, 1.3, 1.45)
	hitbox.shape = box
	add_child(hitbox)

	var plate := Mats.surface(Color(0.18, 0.22, 0.23), "plain", 0.4, 0.75)
	var trim := Mats.surface(Color(0.52, 0.23, 0.11), "plain", 0.5, 0.4)
	_piece(self, Vector3(0, -0.28, 0), Vector3(1.35, 0.37, 1.35), plate)
	_piece(self, Vector3(-0.32 * side, 0.22, 0), Vector3(0.35, 0.85, 1.35), plate)
	add_child(_assembly)
	_piece(_assembly, Vector3.ZERO, Vector3(0.72, 0.56, 0.78), trim)
	for x: float in [-0.16, 0.16]:
		_piece(_assembly, Vector3(x, 0.03, -0.7), Vector3(0.17, 0.18, 1.15), plate)
	_piece(_assembly, Vector3(0, 0.19, -0.44), Vector3(0.12, 0.12, 0.08), Mats.glow(Color(1, 0.32, 0.13), 3.0))

	var line := BoxMesh.new()
	line.size = Vector3(0.024, 0.024, 1.0)
	_beam.mesh = line
	_beam.material_override = Mats.beam(Color(1, 0.32, 0.13), 2.5, 0.7)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.top_level = true
	_beam.hide()
	add_child(_beam)

func track(player: Player, delta: float) -> void:
	if _health <= 0.0:
		return
	_delay = maxf(0.0, _delay - delta)
	var origin := global_position
	var to_player := player.aim_point() - origin
	var facing := global_basis.x * side
	var distance := to_player.length()
	if player.is_dead or distance > RANGE or player.visibility(distance) <= 0.0 or facing.dot(to_player.normalized()) < 0.12:
		cease_fire()
		return

	var space := get_world_3d().direct_space_state
	var sight := PhysicsRayQueryParameters3D.create(origin, player.aim_point(), Layers.WORLD)
	if not space.intersect_ray(sight).is_empty():
		cease_fire()
		return
	if _shots > 0:
		if _delay == 0.0:
			_shoot(origin, space, player)
		return
	if _delay > 0.0:
		return

	_charge += delta
	if not _beam.visible:
		Sfx.play_at("beep", origin, 3.0, 0.7, RANGE)
	# Commit to a point before the burst so the player can dodge the warning line.
	if _charge < WARNING * 0.72:
		_aim = player.aim_point()
	_assembly.look_at(_aim)
	_beam.show()
	_beam.look_at_from_position(origin.lerp(_aim, 0.5), _aim)
	_beam.scale = Vector3(1.0, 1.0, origin.distance_to(_aim))
	if _charge >= WARNING:
		_charge = 0.0
		_shots = 3
		_beam.hide()

func _shoot(origin: Vector3, space: PhysicsDirectSpaceState3D, player: Player) -> void:
	_shots -= 1
	_delay = 0.17 if _shots > 0 else 3.3
	var aim := origin.direction_to(_aim)
	var hit := Gun.cast(space, origin, aim, RANGE, self)
	var end: Vector3 = hit.get("position", origin + aim * RANGE)
	if hit.get("collider") == player:
		player.take_damage(29.0, self, end, aim)
	elif not hit.is_empty():
		Fx.impact(self, end, hit["normal"], false)
	var muzzle := _assembly.to_global(Vector3(0, 0, -1.15))
	Fx.tracer(self, muzzle, end, Color(1, 0.35, 0.12))
	Fx.flash(self, muzzle, Color(1, 0.64, 0.32), 4.0, 0.09, 8.0)
	Sfx.play_at("shot_dmr", muzzle, 2.0, 0.72, RANGE + 20.0)

func cease_fire() -> void:
	_charge = 0.0
	_shots = 0
	_beam.hide()

func take_damage(amount: float, _source: Node = null, _at: Vector3 = Vector3.ZERO,
		_direction: Vector3 = Vector3.ZERO) -> int:
	return _damage_armor(amount * 0.12)

func take_blast(amount: float) -> void:
	_damage_armor(amount * 1.8)

func _damage_armor(amount: float) -> int:
	if _health <= 0.0:
		return 0
	_health -= amount
	if _health > 0.0:
		return 1
	cease_fire()
	remove_from_group("aircraft_weapon")
	set_deferred("collision_layer", 0)
	_assembly.hide()
	Fx.explosion(self, global_position, 1.8)
	disabled.emit()
	return 1

func _piece(parent: Node3D, at: Vector3, size: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = Shapes.rounded_box(size, 0.045, 2)
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)
