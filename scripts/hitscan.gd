class_name Hitscan
extends RefCounted

# A shot resolved instantly by one raycast, instead of by a node that flies
# across the map and waits for a collision callback. There is no travel time
# and no bullet in the world, so nothing can tunnel past a target between
# physics ticks and nothing has to be sized to prevent it.
#
# This is the one place a shot decides what it hit. What happens to that thing
# is Weapon's business, and drawing anything about it is Tracer's.

# A shot passes through bodies in its ignore group and keeps going, so we may
# need several casts to find the first thing that actually stops it. Bounded so
# a pathological pile-up can't spin the frame.
const MAX_PASS_THROUGH: int = 8

# `source` is any node in the tree, used only to reach the physics space.
# Returns the raycast hit dictionary (`position`, `normal`, `collider`, `rid`),
# or an empty one if the shot reached its full range without stopping.
static func resolve(
	source: Node2D,
	from: Vector2,
	direction: Vector2,
	max_distance: float,
	shooter: Node = null,
	ignore_group: StringName = &""
) -> Dictionary:
	var space := source.get_world_2d().direct_space_state

	# SHOOTABLE is world + player + enemy: walls stop us, and both factions are
	# hittable, since who we spare is decided by shooter/ignore_group here and
	# not by layers.
	var query := PhysicsRayQueryParameters2D.create(
		from, from + direction.normalized() * max_distance, CollisionLayers.SHOOTABLE
	)
	# Loot pickups and the extract zone are Area2Ds; shots ignore them.
	query.collide_with_areas = false

	# The muzzle sits inside the shooter's own collider, so exclude them up
	# front rather than discovering it on the first hit.
	var excluded: Array[RID] = []
	if shooter is CollisionObject2D:
		excluded.append((shooter as CollisionObject2D).get_rid())
	query.exclude = excluded

	for _pass in MAX_PASS_THROUGH:
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return {}

		var body: Object = hit.get("collider")
		if ignore_group != &"" and body is Node and (body as Node).is_in_group(ignore_group):
			# Not a stopper -- drop it out of the query and cast again from the
			# same muzzle, so range still measures from where the shot started.
			excluded.append(hit["rid"])
			query.exclude = excluded
			continue

		return hit

	return {}
