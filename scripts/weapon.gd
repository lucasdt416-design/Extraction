class_name Weapon
extends RefCounted

# Fire-rate timing and bullet spawning, shared by the player and the AI so both
# fire by identical rules. The owner keeps the tuning in @export vars and pushes
# it in here; the owner also picks the direction, which is where spread gets
# applied from its own seeded RNG rather than from a bare randf().

var fire_interval: float = 0.12
var bullet_speed: float = 900.0
var bullet_range: float = 900.0
var bullet_length: float = 14.0
var bullet_damage: int = 1
var muzzle_offset: float = 28.0
# Bodies in this group are passed straight through, so a faction can't shoot
# its own members in the back while circling.
var ignore_group: StringName = &""

var _cooldown: float = 0.0

func tick(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)

func can_fire() -> bool:
	return _cooldown <= 0.0

# Returns the bullet, or null if we're still cooling down or were handed a
# zero-length direction.
func fire(world: Node, shooter: Node2D, direction: Vector2) -> Bullet:
	if not can_fire() or direction.length_squared() < 0.0001:
		return null

	_cooldown = fire_interval

	var bullet := Bullet.new()
	bullet.speed = bullet_speed
	bullet.max_range = bullet_range
	bullet.length = bullet_length
	bullet.damage = bullet_damage
	bullet.shooter = shooter
	bullet.ignore_group = ignore_group

	# Parent first: Bullet._ready sizes its collider from the values above, and
	# launch() sets a global position, which needs it to be in the tree.
	world.add_child(bullet)
	bullet.launch(shooter.global_position + direction.normalized() * muzzle_offset, direction)
	return bullet
