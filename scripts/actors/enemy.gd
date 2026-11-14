class_name Enemy
extends CharacterBody3D

# One hostile unit. It perceives (sight with an awareness meter, hearing),
# reports what it finds to its Squad, and carries out the squad's current mode
# in its own way: where to stand is chosen by scoring candidate spots on the
# navmesh for cover, range, flank angle and crowding.
#
# The archetype table in Catalog.ENEMIES sets the numbers and switches on the
# specials (frontal shield, cloak, charged laser shot, grenades, commander).

signal died(enemy: Enemy, killer: Node)

enum State { PATROL, INVESTIGATE, COMBAT, SEARCH }

const SIGHT_RANGE: float = 55.0
const FOV_COS: float = 0.5          # ~120 degree cone while unalerted
const EYE_HEIGHT: float = 1.62
const GRAVITY: float = 19.0

var kind: String = "trooper"
var arch: Dictionary = {}
var squad: Squad
var state: State = State.PATROL
var role: StringName = &"anchor"
var flank_side: float = 1.0
var health: float = 0.0
var is_dead: bool = false
# 0..1. Fills while the player is in view; at 1 they are spotted.
var awareness: float = 0.0

var gun: Gun
var rig: Rig
var _agent: NavigationAgent3D
var _rng := RandomNumberGenerator.new()
var _player: Player
var _index: int = 0
var _scale: float = 1.0

var _sees: bool = false
var _los_timer: float = 0.0
var _sight_time: float = 0.0
var _aim_at: Vector3 = Vector3.ZERO
var _aim_pitch: float = 0.0

var _goal: Vector3 = Vector3.ZERO
var _has_goal: bool = false
var _decide_left: float = 0.0
var _react_left: float = 0.0
var _wait_left: float = 0.0
var _stuck_time: float = 0.0
var _patrol_index: int = 0
var _in_low_cover: bool = false
var _hide_left: float = 0.0
var _scan: float = 0.0

var _burst_left: int = 0
var _pause_left: float = 0.0
var _charge: float = 0.0
var _grenade_cooldown: float = 6.0
var _shield_health: float = 0.0
var _shield_mesh: MeshInstance3D
var _laser: MeshInstance3D
var _fade: float = 0.0

func setup(kind_id: String, owner_squad: Squad, index: int) -> void:
	kind = kind_id
	arch = Catalog.ENEMIES[kind_id]
	squad = owner_squad
	_index = index
	_patrol_index = index
	_scale = arch["scale"]
	health = arch["health"]

func _ready() -> void:
	add_to_group("enemy")
	collision_layer = Layers.ENEMY
	# Not each other: a squad that body-blocks itself jams every doorway.
	collision_mask = Layers.WORLD | Layers.PLAYER
	floor_snap_length = 0.4
	_rng.seed = GameManager.rng.randi()

	var shape := CapsuleShape3D.new()
	shape.radius = 0.36 * _scale
	shape.height = 1.82 * _scale
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = shape.height * 0.5
	add_child(collider)

	gun = Gun.new(arch["weapon"])
	gun.damage_override = arch["damage"]
	gun.infinite_reserve = true

	rig = Rig.new()
	rig.scale = Vector3.ONE * _scale
	add_child(rig)
	rig.build(arch["color"], arch["accent"], gun.def["length"], 1.25 if arch.get("shield", false) or arch.get("commander", false) else 1.0)

	_agent = NavigationAgent3D.new()
	_agent.path_desired_distance = 0.7
	_agent.target_desired_distance = 0.7
	_agent.radius = 0.5
	add_child(_agent)

	if arch.get("shield", false):
		_shield_health = 160.0
		_shield_mesh = MeshInstance3D.new()
		var plate := BoxMesh.new()
		plate.size = Vector3(0.95, 1.45, 0.04)
		_shield_mesh.mesh = plate
		_shield_mesh.material_override = Mats.beam(arch["accent"], 1.2, 0.3)
		_shield_mesh.position = Vector3(0.0, 1.0, -0.62) * _scale
		_shield_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_shield_mesh)
	if arch.get("laser", false):
		_laser = MeshInstance3D.new()
		var line := BoxMesh.new()
		line.size = Vector3(0.012, 0.012, 1.0)
		_laser.mesh = line
		_laser.material_override = Mats.beam(arch["accent"], 3.0, 0.9)
		_laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_laser.top_level = true
		_laser.visible = false
		add_child(_laser)
	_wait_left = _rng.randf_range(0.0, 3.0)

# --- Tick --------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	gun.tick(delta)
	_react_left = maxf(_react_left - delta, 0.0)
	_hide_left = maxf(_hide_left - delta, 0.0)
	_grenade_cooldown = maxf(_grenade_cooldown - delta, 0.0)
	_perceive(delta)
	match state:
		State.PATROL: _patrol(delta)
		State.INVESTIGATE, State.SEARCH: _look_around(delta)
		State.COMBAT: _combat(delta)
	_steer(delta)
	_fire_control(delta)

# --- Perception --------------------------------------------------------------

func _perceive(delta: float) -> void:
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Player
	if _player == null or _player.is_dead:
		_sees = false
		awareness = 0.0
		return
	_los_timer -= delta
	if _los_timer <= 0.0:
		# Ten sight checks a second, staggered so a squad doesn't cast on the same tick.
		_los_timer = 0.1 + _rng.randf() * 0.02
		_sees = _can_see_player()
	var distance := global_position.distance_to(_player.global_position)
	if _sees:
		_sight_time += delta
		if state == State.COMBAT:
			awareness = 1.0
			squad.report_sighting(self, _player.global_position)
		else:
			# Close and standing: spotted in a fraction of a second. Far away or
			# crouched: long enough to slip back behind something.
			awareness += delta * _player.visibility(distance) * clampf(pow(11.0 / distance, 1.6), 0.08, 6.0) * (2.0 if state != State.PATROL else 1.0)
			if awareness >= 1.0:
				squad.report_sighting(self, _player.global_position)
			elif awareness > 0.3 and state == State.PATROL:
				# Something caught its eye: stop and stare before committing.
				_wait_left = maxf(_wait_left, 1.2)
				_has_goal = false
				_aim_at = _player.aim_point()
	else:
		_sight_time = 0.0
		awareness = maxf(awareness - delta * 0.3, 0.0)

func _can_see_player() -> bool:
	var eye := _eye()
	var target := _player.aim_point()
	var to := target - eye
	var distance := to.length()
	if distance > SIGHT_RANGE or _player.visibility(distance) <= 0.0:
		return false
	if state != State.COMBAT and distance > 2.5:
		var forward := -global_transform.basis.z
		if forward.dot(to / distance) < FOV_COS:
			return false
	# Chest or head: half of you showing over a barrier still counts.
	return _clear(eye, target) or _clear(eye, _player.eye_position())

# Called on the whole "enemy" group for every noise the player makes.
func hear(position: Vector3, radius: float, _source: Node) -> void:
	if is_dead or global_position.distance_to(position) > radius:
		return
	squad.report_noise(self, position)

# --- Squad orders ------------------------------------------------------------

func on_squad_mode(mode: Squad.Mode, order: int) -> void:
	_has_goal = false
	_burst_left = 0
	_charge = 0.0
	match mode:
		Squad.Mode.COMBAT:
			state = State.COMBAT
			# Nobody reacts instantly, and not all at once.
			_react_left = float(arch["reaction"]) * (1.0 + order * 0.4)
			_pause_left = 0.0
			_decide_left = _react_left
			_aim_at = squad.last_known + Vector3.UP * 1.1
		Squad.Mode.CALM:
			state = State.PATROL
			awareness = 0.0
			_wait_left = _rng.randf_range(0.5, 2.0)

func investigate(position: Vector3, go: bool) -> void:
	state = State.INVESTIGATE
	_aim_at = position + Vector3.UP * 1.1
	_wait_left = 3.0
	if go:
		_set_goal(_snap(position))

func search(position: Vector3) -> void:
	state = State.SEARCH
	_wait_left = _rng.randf_range(1.5, 3.0)
	_set_goal(_snap(position))

# --- States ------------------------------------------------------------------

func _patrol(delta: float) -> void:
	if _wait_left > 0.0:
		_wait_left -= delta
		_scan += delta
		return
	if not _has_goal or _arrived():
		if _has_goal:
			_wait_left = _rng.randf_range(1.5, 4.5)
			_has_goal = false
			return
		_patrol_index += 1
		var point: Vector3 = squad.points[_patrol_index % squad.points.size()]
		_set_goal(_snap(point + Vector3(_rng.randf_range(-1.5, 1.5), 0.0, _rng.randf_range(-1.5, 1.5))))

func _look_around(delta: float) -> void:
	if _has_goal and not _arrived():
		return
	_has_goal = false
	_scan += delta
	_wait_left -= delta
	if _wait_left <= 0.0 and state == State.SEARCH:
		search(squad.search_point())

func _combat(delta: float) -> void:
	_aim_at = _player.aim_point() if _sees and is_instance_valid(_player) else squad.last_known + Vector3.UP * 1.1
	if _react_left > 0.0:
		return
	_decide_left -= delta
	if _decide_left <= 0.0 or (_has_goal and _stuck_time > 1.0):
		_decide()
	_try_grenade()

# Pick where to be for the next couple of seconds.
func _decide() -> void:
	_decide_left = _rng.randf_range(1.4, 2.8)
	_stuck_time = 0.0
	var threat := squad.last_known
	var hide := gun.is_reloading() or _hide_left > 0.0
	var pushing := role == &"push" or (squad.should_push(_player) and float(arch["aggression"]) > 0.35)
	var want_range: float = arch["range"]
	if pushing and not hide:
		want_range *= 0.45

	var map := get_world_3d().navigation_map
	var away := (squad.center() - threat)
	away.y = 0.0
	away = away.normalized() if away.length() > 0.5 else Vector3.FORWARD
	var candidates: Array[Vector3] = [global_position]
	for ring: float in [3.5, 7.0, 11.0]:
		for i in 8:
			var angle := TAU * i / 8.0 + _rng.randf() * 0.6
			candidates.append(global_position + Vector3(cos(angle), 0.0, sin(angle)) * ring)
	for i in 10:
		var angle := TAU * i / 10.0 + _rng.randf() * 0.5
		candidates.append(threat + Vector3(cos(angle), 0.0, sin(angle)) * want_range)

	var best := global_position
	var best_score := INF
	var best_low := false
	for sample in candidates:
		var spot := NavigationServer3D.map_get_closest_point(map, sample)
		if spot.distance_to(sample) > 1.6 or absf(spot.y - global_position.y) > 3.5:
			continue
		var to_threat := threat - spot
		to_threat.y = 0.0
		var distance := to_threat.length()
		var target := threat + Vector3.UP * 1.2
		var can_fire := _clear(spot + Vector3.UP * EYE_HEIGHT * _scale, target)
		var low_blocked := not _clear(spot + Vector3.UP * 0.6, target)

		var score := absf(distance - want_range) * 0.9 + spot.distance_to(global_position) * 0.45
		score += squad.crowding(self, spot) * 3.0 + _rng.randf() * 1.5
		if hide:
			# Out of the line of fire first; everything else is secondary.
			score += 14.0 if can_fire else (0.0 if low_blocked else 4.0)
		else:
			if not can_fire:
				score += 9.0 if squad.contact_age < 3.0 else 3.0
			elif low_blocked:
				score -= 7.0   # can shoot over it and duck behind it: the best spot there is
			elif not pushing:
				score += 5.0 * (1.0 - float(arch["aggression"]))
		if distance < 3.0 and kind != "rusher":
			score += 10.0
		if role == &"flank" and distance > 0.5:
			# Reward spots off to our assigned side of the squad-to-threat line.
			var bearing := -to_threat / distance
			var side := away.cross(Vector3.UP).dot(bearing) * flank_side
			score -= side * 7.0 + (2.0 if away.dot(bearing) < 0.3 else 0.0)
		if score < best_score:
			best_score = score
			best = spot
			best_low = can_fire and low_blocked

	_in_low_cover = best_low
	squad.claim(self, best)
	if best.distance_to(global_position) > 0.8:
		_set_goal(best)
	else:
		_has_goal = false

func _try_grenade() -> void:
	if not arch.get("grenades", false) or _grenade_cooldown > 0.0:
		return
	var distance := global_position.distance_to(squad.last_known)
	# Thrown to dig out a player who has gone to ground, not at one in the open.
	if squad.contact_age < 1.2 or squad.contact_age > 7.0 or distance < 8.0 or distance > 30.0:
		return
	_grenade_cooldown = _rng.randf_range(9.0, 14.0)
	squad.bark(self, "grenade")
	var grenade := Grenade.new()
	get_parent().add_child(grenade)
	grenade.launch(_eye(), squad.last_known + Vector3(_rng.randf_range(-1.2, 1.2), 0.0, _rng.randf_range(-1.2, 1.2)), self)

# --- Movement ----------------------------------------------------------------

func _steer(delta: float) -> void:
	var speed: float = arch["speed"]
	match state:
		State.PATROL: speed *= 0.42
		State.INVESTIGATE: speed *= 0.6
		State.SEARCH: speed *= 0.75
	var wish := Vector3.ZERO
	if _has_goal and _react_left <= 0.0 and not _agent.is_navigation_finished():
		var next := _agent.get_next_path_position()
		wish = next - global_position
		wish.y = 0.0
		wish = wish.normalized() if wish.length() > 0.05 else Vector3.ZERO
	var flat := Vector3(velocity.x, 0.0, velocity.z).move_toward(wish * speed, 22.0 * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()

	if _has_goal and wish != Vector3.ZERO and flat.length() < 0.3:
		_stuck_time += delta
	else:
		_stuck_time = 0.0

	# Facing: at the threat when there is one, otherwise where we're walking,
	# otherwise a slow scan left and right.
	var facing := Vector3.ZERO
	if state == State.COMBAT or (state != State.PATROL and not _has_goal) or awareness > 0.3:
		facing = _aim_at - global_position
	elif flat.length() > 0.4:
		facing = flat
	facing.y = 0.0
	var turn_speed := 7.5 if state == State.COMBAT else 3.5
	if facing.length() > 0.1:
		var want := atan2(-facing.x, -facing.z)
		if state != State.COMBAT and flat.length() < 0.4 and awareness < 0.3:
			want += sin(_scan * 0.9) * 0.9
		rotation.y = rotate_toward(rotation.y, want, turn_speed * delta)
	elif flat.length() < 0.4:
		rotation.y += cos(_scan * 0.9) * 0.6 * delta

	var eye := _eye()
	var to_aim := _aim_at - eye
	_aim_pitch = atan2(to_aim.y, Vector2(to_aim.x, to_aim.z).length()) if state == State.COMBAT else 0.0

func _set_goal(position: Vector3) -> void:
	_goal = position
	_has_goal = true
	_stuck_time = 0.0
	_agent.target_position = position

func _arrived() -> bool:
	return _agent.is_navigation_finished() or global_position.distance_to(_goal) < 1.0

func _snap(position: Vector3) -> Vector3:
	return NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, position)

# --- Shooting ----------------------------------------------------------------

func _fire_control(delta: float) -> void:
	if state != State.COMBAT or _react_left > 0.0 or not is_instance_valid(_player) or _player.is_dead:
		squad.release_token(self)
		_charge = 0.0
		return
	if gun.mag <= 0 and not gun.is_reloading():
		gun.start_reload()
		squad.release_token(self)
		squad.bark(self, "reload")
		_burst_left = 0
		_decide_left = 0.0   # go and find somewhere to do it
		return
	if gun.is_reloading():
		return

	# Shooting where the player was a moment ago keeps them pinned while the
	# flankers move. Only the anchor does it, and only briefly.
	var suppress := not _sees and role == &"anchor" and squad.contact_age < 2.5 and _clear(_eye(), _aim_at)
	var has_target := _sees or suppress
	var close := _sees and global_position.distance_to(_player.global_position) < 8.0

	if _burst_left <= 0:
		_pause_left -= delta
		if _pause_left > 0.0 or not has_target:
			_charge = 0.0
			return
		# A threat in your face gets shot regardless of whose turn it is.
		if not close and not squad.request_token(self):
			return
		var burst: Array = arch["burst"]
		_burst_left = _rng.randi_range(burst[0], burst[1])
		if suppress:
			squad.bark(self, "suppress")
	if not has_target:
		_end_burst()
		return

	if arch.get("laser", false):
		# Charged shot: the beam is the warning. Break line of sight to cancel it.
		_charge += delta
		if _charge < float(arch["reaction"]):
			return
	if not gun.can_fire():
		return

	# Aim error starts wide and settles the longer it holds you in view, so the
	# first burst after rounding a corner mostly misses. Moving makes it worse
	# for both of us.
	var error: float = arch["accuracy"] * (1.0 + 2.2 * exp(-_sight_time * 1.6))
	error += Vector2(_player.velocity.x, _player.velocity.z).length() * 0.22
	error += Vector2(velocity.x, velocity.z).length() * 0.3
	if suppress:
		error = float(arch["accuracy"]) * 2.5 + 1.5
	if arch.get("laser", false):
		error = arch["accuracy"]
	var eye := _eye()
	gun.fire(self, eye, _aim_at - eye, rig.muzzle_position(), error, _rng, &"enemy", (arch["accent"] as Color).lightened(0.4))
	Sfx.play_at("shot_" + gun.id, global_position, 0.0, 0.9, 110.0)
	Fx.flash(self, rig.muzzle_position(), arch["accent"], 1.6, 0.05, 5.0)
	_fade = 0.0
	_charge = 0.0
	_burst_left -= 1
	if _burst_left <= 0:
		_end_burst()

func _end_burst() -> void:
	_burst_left = 0
	_charge = 0.0
	_pause_left = _rng.randf_range(0.7, 1.6) * (1.6 if arch.get("laser", false) else 1.0)
	squad.release_token(self)
	# Often move after shooting: a target that fires from the same spot twice
	# is a target that has been pre-aimed.
	if _rng.randf() < 0.45:
		_decide_left = minf(_decide_left, 0.25)

# The one place enemy health changes (rule 2).
# Returns 0 = absorbed, 1 = hit, 2 = headshot, 3 = kill.
func take_damage(amount: float, from: Node = null, position: Vector3 = Vector3.ZERO, direction: Vector3 = Vector3.ZERO) -> int:
	if is_dead:
		return 0
	var result := 1
	# Frontal shield: soaks shots that arrive from the front until it breaks.
	if _shield_health > 0.0 and direction.dot(-global_transform.basis.z) < -0.35:
		_shield_health -= amount
		Fx.flash(self, position, arch["accent"], 1.5, 0.08, 3.0)
		if _shield_health <= 0.0:
			_shield_mesh.queue_free()
			Sfx.play_at("shield_break", global_position, 4.0)
			_react_left = 1.2   # staggered
		amount *= 0.1
		result = 0
	elif position.y > global_position.y + 1.5 * _scale:
		amount *= Catalog.HEADSHOT_MULT
		result = 2
	health -= amount
	rig.flinch()
	# A headshot or a heavy hit knocks it off its aim for a moment.
	if result == 2 or amount >= float(arch["health"]) * 0.25:
		_react_left = maxf(_react_left, 0.35)
		_sight_time = 0.0
		_charge = 0.0
	if health <= 0.0:
		_die(from, direction)
		return 3
	if from is Node3D:
		squad.report_hit(self, (from as Node3D).global_position)
	# Hurt and not the pushing type: break off and get behind something.
	if health < float(arch["health"]) * 0.5 and float(arch["aggression"]) < 0.7 and _hide_left <= 0.0:
		_hide_left = 2.5
		_decide_left = 0.0
	return result

func _die(killer: Node, direction: Vector3) -> void:
	is_dead = true
	health = 0.0
	velocity = Vector3.ZERO
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)
	if is_instance_valid(_shield_mesh):
		_shield_mesh.queue_free()
	if _laser != null:
		_laser.visible = false
	rig.die(direction)
	# It goes down in a spit of sparks and a flare of its own colour.
	var chest := global_position + Vector3.UP * 1.25 * _scale
	Fx.impact(self, chest, -direction if direction.length() > 0.1 else Vector3.UP, true)
	Fx.impact(self, chest + Vector3.UP * 0.3, Vector3.UP, true)
	Fx.flash(self, chest, arch["accent"], 4.0, 0.25, 6.0)
	Sfx.play_at("shield_break", global_position, -2.0, 0.8)
	squad.report_death(self, killer)
	died.emit(self, killer)

func _eye() -> Vector3:
	return global_position + Vector3.UP * EYE_HEIGHT * _scale

func _clear(from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, Layers.WORLD)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

# --- View (cosmetic) ---------------------------------------------------------

func _process(delta: float) -> void:
	if is_dead:
		return
	var speed := Vector2(velocity.x, velocity.z).length()
	var ducked := state == State.COMBAT and _in_low_cover and not _has_goal and _burst_left <= 0 and _pause_left > 0.25
	rig.animate(delta, speed, state == State.COMBAT or awareness > 0.3, _aim_pitch, ducked)
	if arch.get("cloak", false):
		# Shimmer rather than vanish: a careful player can still pick it out.
		var hidden := state == State.COMBAT and _burst_left <= 0 and is_instance_valid(_player) and global_position.distance_to(_player.global_position) > 7.0
		_fade = move_toward(_fade, 0.88 if hidden else 0.0, delta * (1.2 if hidden else 4.0))
		rig.set_fade(_fade)
	if _laser != null:
		_laser.visible = _charge > 0.0 and _sees
		if _laser.visible:
			var from := rig.muzzle_position()
			var length := from.distance_to(_aim_at)
			if length > 0.5:
				_laser.look_at_from_position((from + _aim_at) * 0.5, _aim_at, Vector3.UP)
				var width := 1.0 + _charge / float(arch["reaction"]) * 2.0
				_laser.scale = Vector3(width, width, length)
