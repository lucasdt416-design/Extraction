class_name Gun
extends RefCounted

# Magazine, fire-rate and reload timing plus shot resolution, shared by the
# player and every enemy so both sides shoot by identical rules. Shots are
# hitscan: a ray resolved on the tick the trigger is pulled, so nothing can
# tunnel and there is no projectile to keep in sync.

signal fired
signal reloaded

var id: String = "sidearm"
var def: Dictionary = {}
var mag: int = 0
var reserve: int = 0
# Multipliers the owner sets from its build (implants, abilities).
var rate_mult: float = 1.0
var reload_mult: float = 1.0
# Enemies override the per-pellet damage so one weapon table serves both sides.
var damage_override: float = -1.0
var infinite_reserve: bool = false

var _cooldown: float = 0.0
var _reload_left: float = 0.0

func _init(weapon_id: String = "sidearm") -> void:
	id = weapon_id
	def = Catalog.WEAPONS[weapon_id]
	mag = def["mag"]
	reserve = int(def["mag"]) * 4

func tick(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _reload_left > 0.0:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()

func is_reloading() -> bool:
	return _reload_left > 0.0

func reload_progress() -> float:
	if _reload_left <= 0.0:
		return 0.0
	return 1.0 - _reload_left / (float(def["reload"]) * reload_mult)

func can_fire() -> bool:
	return _cooldown <= 0.0 and _reload_left <= 0.0 and mag > 0

func start_reload(instant: bool = false) -> bool:
	if is_reloading() or mag >= int(def["mag"]) or (reserve <= 0 and not infinite_reserve):
		return false
	if instant:
		_finish_reload()
		return true
	_reload_left = float(def["reload"]) * reload_mult
	return true

func cancel_reload() -> void:
	_reload_left = 0.0

func _finish_reload() -> void:
	_reload_left = 0.0
	var want := int(def["mag"]) - mag
	var take := want if infinite_reserve else mini(want, reserve)
	mag += take
	if not infinite_reserve:
		reserve -= take
	reloaded.emit()

# Fires one trigger pull (all pellets). `origin`/`direction` are where the shot
# is resolved from: the eye, for both sides, so what you can see is what you
# can hit. `muzzle` is only where the tracer is drawn from.
# Returns one entry per pellet that hit something:
#   {"position", "normal", "collider", "result"}  -- result is whatever the
#   target's take_damage returned (0 = no effect, 1 = hit, 2 = headshot, 3 = kill).
func fire(shooter: Node3D, origin: Vector3, direction: Vector3, muzzle: Vector3, spread_deg: float,
		rng: RandomNumberGenerator, pass_group: StringName = &"", tracer_color: Color = Color(1.0, 0.85, 0.6)) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	if not can_fire():
		return hits
	mag -= 1
	_cooldown = 60.0 / (float(def["rpm"]) * rate_mult)

	var space := shooter.get_world_3d().direct_space_state
	var aim := direction.normalized()
	# Any two axes perpendicular to the aim line, to spread pellets across.
	var side := aim.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(aim)
	var max_range: float = def["range"]

	for pellet in int(def["pellets"]):
		# Uniform over a disc, so shots cluster toward the centre the way a
		# cone of fire should rather than filling a square.
		var angle := rng.randf() * TAU
		var radius := sqrt(rng.randf()) * tan(deg_to_rad(spread_deg))
		var dir := (aim + (side * cos(angle) + up * sin(angle)) * radius).normalized()
		var hit := Gun.cast(space, origin, dir, max_range, shooter, pass_group)
		var end := origin + dir * max_range
		if not hit.is_empty():
			end = hit["position"]
			var target: Object = hit["collider"]
			var result := 0
			if target != null and target.has_method("take_damage"):
				result = target.take_damage(_damage_at(origin.distance_to(end)), shooter, end, dir)
			hit["result"] = result
			hits.append(hit)
			Fx.impact(shooter, end, hit["normal"], result > 0)
		Fx.tracer(shooter, muzzle, end, tracer_color)
	fired.emit()
	return hits

func _damage_at(distance: float) -> float:
	var base: float = damage_override if damage_override >= 0.0 else float(def["damage"])
	var falloff: Array = def["falloff"]
	var t := clampf((distance - float(falloff[0])) / maxf(float(falloff[1]) - float(falloff[0]), 0.01), 0.0, 1.0)
	return base * lerpf(1.0, Catalog.MIN_FALLOFF, t)

# The one place a shot decides what it hit. Passes through the shooter and
# through anything in `pass_group` (so a squad can't shoot itself in the back).
static func cast(space: PhysicsDirectSpaceState3D, from: Vector3, dir: Vector3, max_range: float,
		shooter: Node = null, pass_group: StringName = &"") -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * max_range, Layers.SHOOTABLE)
	var excluded: Array[RID] = []
	if shooter is CollisionObject3D:
		excluded.append((shooter as CollisionObject3D).get_rid())
	query.exclude = excluded
	for _pass in 8:
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return {}
		var body: Object = hit["collider"]
		if pass_group != &"" and body is Node and (body as Node).is_in_group(pass_group):
			excluded.append(hit["rid"])
			query.exclude = excluded
			continue
		return hit
	return {}
