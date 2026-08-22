class_name Weapon
extends RefCounted

# Fire-rate timing and shot resolution, shared by the player and the AI so both
# fire by identical rules. The owner keeps the tuning in @export vars and pushes
# it in here; the owner also picks the direction, which is where spread gets
# applied from its own seeded RNG rather than from a bare randf().
#
# Shots are hitscan: Hitscan.resolve() raycasts along the aim line and we damage
# whatever it stopped on, on the same tick the trigger was pulled. Nothing flies
# through the world, so there is no travel time and nothing to tunnel.

var fire_interval: float = 0.12
# How far a shot carries before it simply stops.
var shot_range: float = 900.0
var damage: int = 1
var muzzle_offset: float = 28.0
# Bodies in this group are passed straight through, so a faction can't shoot
# its own members in the back while circling.
var ignore_group: StringName = &""

# Cosmetic only -- how long the streak lingers, and what colour it is. Zero
# lifetime spawns nothing at all.
var tracer_lifetime: float = 0.05
var tracer_color: Color = Color.WHITE

var _cooldown: float = 0.0

func tick(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)

func can_fire() -> bool:
	return _cooldown <= 0.0

# Resolves one shot. Returns false if we're still cooling down or were handed a
# zero-length direction, in which case nothing happened at all.
func fire(world: Node, shooter: Node2D, direction: Vector2) -> bool:
	if not can_fire() or direction.length_squared() < 0.0001:
		return false

	_cooldown = fire_interval

	var aim := direction.normalized()
	# Clear of the shooter's own collider, so a shot doesn't start inside them.
	var from := shooter.global_position + aim * muzzle_offset
	var to := from + aim * shot_range

	var hit := Hitscan.resolve(shooter, from, aim, shot_range, shooter, ignore_group)
	if not hit.is_empty():
		# Stop the streak where the shot stopped, whether or not the thing it
		# hit could be hurt by it.
		to = hit["position"]

		# Damage is routed by has_method(), not by class or group, so anything
		# damageable works without this file knowing what it is.
		var body: Object = hit["collider"]
		if body != null and body.has_method("take_damage"):
			body.take_damage(damage, shooter)

	if tracer_lifetime > 0.0:
		Tracer.spawn(world, from, to, tracer_lifetime, tracer_color)

	return true
