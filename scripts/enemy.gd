class_name Enemy
extends CharacterBody2D

# Wanders around where it spawned until the player gets close, then holds a ring
# at orbit_radius -- closing in from outside it, backing off from inside it, and
# strafing along it while shooting inward. Every decision produces an InputFrame
# and goes through Movement.apply, the same path the player's keyboard takes.

# Emitted once, the moment we die. The node stays in the tree afterwards as an
# inert corpse, so anything listening can still read our position or loot table
# off `enemy` instead of having to copy it out beforehand.
signal died(enemy: Enemy)

enum State { PATROL, CHASE }

@export_group("Movement")
@export var speed: float = 100.0
@export var chase_speed: float = 150.0

@export_group("Detection")
@export var detection_radius: float = 250.0
# Deliberately larger than detection_radius. Without the gap an enemy sitting
# exactly on the edge flips between states every tick.
@export var lose_radius: float = 340.0
# How long we keep hunting after losing the player -- out of range, or out of
# sight behind a wall. The clock is refreshed every tick we can still see them,
# so this is "give up N seconds after they break contact", not "chase for N
# seconds total". It is also what stops a hit from long range being undone by
# _update_state on the very next tick, which would leave the enemy never
# visibly reacting to being shot.
@export var min_chase_time: float = 4.0
# What blocks sight. Walls are on `world`; deliberately NOT player or enemy, or
# a pack would blind itself by standing in its own way. Corpses zero their
# layers when they die, so they don't provide cover either.
@export_flags_2d_physics var sight_blocker_mask: int = CollisionLayers.WORLD

@export_group("Combat")
# The ring we try to hold around the player. Keep it under lose_radius, or
# backing off would walk us out of our own engagement and straight back to
# patrolling.
@export var orbit_radius: float = 250.0
# Half-width of the band around orbit_radius where we stop correcting distance
# and purely strafe. Without it we jitter in and out on the exact radius.
@export var orbit_band: float = 24.0
# How long we strafe one way before reversing.
@export var strafe_flip_min: float = 0.8
@export var strafe_flip_max: float = 2.2
# Aim error, so a pack doesn't land every shot on the same pixel. Wide enough
# that a burst sprays rather than stacks -- an enemy that hits with all three
# shots every time is not survivable at this fire rate.
@export var spread_degrees: float = 25.0

@export_group("Weapon")
# Enemies fire in bursts: burst_size shots burst_shot_interval apart, then a
# burst_delay pause before the next one. The pause is armed up front, so the
# first burst after spotting the player costs the same wind-up as every one
# after it -- that gap is the player's window to close, break away, or shoot
# first. It only runs down while we have someone to shoot at, and breaking
# line of sight pauses it rather than resetting it.
@export var burst_size: int = 3
# Spacing between the shots inside one burst.
@export var burst_shot_interval: float = 0.12
# Between bursts, rolled from our own seeded stream so a pack doesn't fire in
# unison.
@export var burst_delay_min: float = 1.8
@export var burst_delay_max: float = 3.0
# Shots are hitscan -- this is how far one carries, not how fast it flies.
@export var shot_range: float = 700.0
@export var shot_damage: int = 1
# Clear of our own collider (radius ~21), so shots don't start inside us.
@export var muzzle_offset: float = 28.0
# How long the shot's tracer lingers, in seconds. Cosmetic; 0.0 draws none.
@export var tracer_lifetime: float = 0.05
# Where tracers get parented. Leave empty to use our own parent.
@export var tracer_container_path: NodePath

@export_group("Patrol")
@export var patrol_radius: float = 160.0
@export var arrive_distance: float = 12.0
# Safety net so a wander target behind a wall can't stall us forever.
@export var patrol_leg_timeout: float = 6.0
@export var patrol_pause_min: float = 0.4
@export var patrol_pause_max: float = 1.4

@export_group("Health")
@export var max_health: int = 3

@export_group("Death")
# Corpses stay in the world as a red marker of what happened here. Tinting the
# body tints the sprite under it, so this works without touching the scene.
@export var dead_tint: Color = Color(0.72, 0.11, 0.11)
# Behind everything living, so a corpse never hides an enemy standing on it.
@export var corpse_z_index: int = -1

var health: int = 0
# A dead enemy stops thinking, stops moving, stops colliding -- but stays in the
# tree. Nothing else in the raid pauses on our account.
var is_dead: bool = false

var state: State = State.PATROL

var weapon := Weapon.new()

var _home: Vector2 = Vector2.ZERO
var _patrol_target: Vector2 = Vector2.ZERO
var _leg_time: float = 0.0
var _pause_time: float = 0.0
var _chase_time_left: float = 0.0
var _strafe_sign: float = 1.0
var _strafe_time: float = 0.0
var _player: Node2D = null
# Whether we could see the player on this tick. Cast once in _update_state and
# reused by _think_chase, which needs the same answer to decide whether to
# shoot -- casting it twice a tick would just cost twice.
var _has_los: bool = false
# Shots left in the burst we're currently firing; 0 means we're between bursts.
var _burst_left: int = 0
# Time until the next burst may start. Only counts down while we actually have
# something to shoot at, and is never reset short of a burst being spent.
var _burst_delay: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	health = max_health
	_home = global_position

	# Our own stream, derived from the run seed, so a given raid always plays
	# out the same way. Bare randf() would not (CLAUDE.md rule 4).
	_rng.seed = GameManager.rng.randi()

	# Stagger the strafe so a pack doesn't swing in unison.
	_strafe_sign = 1.0 if _rng.randf() < 0.5 else -1.0
	_strafe_time = _rng.randf_range(strafe_flip_min, strafe_flip_max)

	weapon.fire_interval = burst_shot_interval
	weapon.shot_range = shot_range
	weapon.damage = shot_damage
	weapon.muzzle_offset = muzzle_offset
	weapon.tracer_lifetime = tracer_lifetime
	weapon.ignore_group = &"enemy"

	# Armed before the first shot, not after it.
	_arm_burst_delay()

	_pick_patrol_target()

func _physics_process(delta: float) -> void:
	_update_state(delta)

	var frame := _think(delta)
	var current_speed := chase_speed if state == State.CHASE else speed
	Movement.apply(self, frame, current_speed)

	weapon.tick(delta)
	_update_burst(delta, frame.shoot)
	# frame.shoot is checked here and not only in _update_burst: a loaded burst
	# outlives losing the player, so this is what actually holds fire while
	# they're behind a wall. can_fire() before _with_spread so we only roll
	# spread on shots we actually take -- otherwise the seeded stream advances
	# once per tick just to be discarded.
	if frame.shoot and _burst_left > 0 and weapon.can_fire():
		# Only a shot that actually left the barrel counts against the burst.
		if weapon.fire(_tracer_container(), self, _with_spread(frame.aim)):
			_burst_left -= 1
			if _burst_left <= 0:
				_arm_burst_delay()

# Burst state, driven by whether _think_chase found something worth shooting at
# this tick. `has_target` already accounts for range and line of sight.
func _update_burst(delta: float, has_target: bool) -> void:
	# Contact broken -- out of range, or the player stepped behind a wall. The
	# clock freezes exactly where it is: an unfinished burst stays loaded and a
	# part-spent delay stays part-spent, so stepping back out resumes where we
	# left off instead of buying a fresh wind-up.
	if not has_target:
		return

	# Mid-burst: the shots inside it are paced by the weapon's own cooldown.
	if _burst_left > 0:
		return

	_burst_delay = maxf(_burst_delay - delta, 0.0)
	if _burst_delay <= 0.0:
		_burst_left = burst_size

# Rolled once per burst, as that burst's last shot goes out.
func _arm_burst_delay() -> void:
	_burst_delay = _rng.randf_range(burst_delay_min, burst_delay_max)

# The one place enemy health changes (CLAUDE.md rule 2). Weapon calls this
# because we answer has_method("take_damage"), not because it knows what an
# Enemy is -- anything else damageable just needs the same method.
func take_damage(amount: int, _from: Node = null) -> void:
	if is_dead:
		return

	health -= amount

	if health <= 0:
		health = 0
		_die()
		return

	# Being shot gets our attention wherever it came from, including well
	# outside lose_radius -- the commitment timer is what stops _update_state
	# from undoing this on the very next tick.
	_enter_chase()

# We are left in the tree rather than freed: the corpse is scenery, and later a
# lootable container. Everything that made us a participant gets switched off.
func _die() -> void:
	is_dead = true

	# Stop dead where we fell. set_physics_process off means no _think, no
	# Movement.apply, no weapon.tick -- the corpse can't move or shoot.
	velocity = Vector2.ZERO
	set_physics_process(false)

	# Deferred because we may be inside a physics callback right now, and the
	# space is locked while it runs. Dropping off both layer and mask is what
	# makes shots pass through us and lets the living walk over us; with the
	# collider left on, every corpse would soak shots meant for the enemy
	# behind it.
	set_deferred("collision_layer", 0)
	set_deferred("collision_mask", 0)

	modulate = dead_tint
	z_index = corpse_z_index

	died.emit(self)

func _update_state(delta: float) -> void:
	_chase_time_left = maxf(_chase_time_left - delta, 0.0)

	var target := _find_player()
	if target == null:
		state = State.PATROL
		_has_los = false
		return

	var distance := global_position.distance_to(target.global_position)
	_has_los = _can_see(target)

	match state:
		State.PATROL:
			# Being close is no longer enough -- there has to be a clear line
			# between us, or every wall in the level is a window.
			if distance <= detection_radius and _has_los:
				_enter_chase()
		State.CHASE:
			if _has_los and distance <= lose_radius:
				# Still on them: keep the commitment topped up, so the give-up
				# clock only starts running once contact is actually broken.
				_chase_time_left = min_chase_time
			elif _chase_time_left <= 0.0:
				# Lost them long enough. A hit from out of sight refreshes this
				# same clock through _enter_chase, so we don't shrug off being
				# shot from cover.
				_give_up()

func _enter_chase() -> void:
	state = State.CHASE
	# Refreshed on every trigger, so repeated hits keep extending the chase
	# rather than running down a clock started by the first one.
	_chase_time_left = min_chase_time

func _give_up() -> void:
	state = State.PATROL
	# Walk back to where we started; normal wandering picks up again once we
	# arrive.
	_patrol_target = _home
	_leg_time = 0.0
	_pause_time = 0.0

func _think(delta: float) -> InputFrame:
	if state == State.CHASE:
		return _think_chase(delta)
	return _think_patrol(delta)

func _think_chase(delta: float) -> InputFrame:
	var frame := InputFrame.new()

	var target := _find_player()
	if target == null:
		return frame

	var to_player := target.global_position - global_position
	var distance := to_player.length()
	if distance < 0.001:
		return frame

	var toward := to_player / distance

	# Keep the gun on the player the whole time, including while strafing --
	# Movement.apply turns aim into our facing.
	frame.aim = toward
	# Don't burn shots that fall short: a long-range hit now drags us into
	# CHASE from well outside our own weapon range. And don't fire into a wall
	# we can't see past -- while hunting a player who broke line of sight we
	# still advance and aim, we just hold fire.
	frame.shoot = distance <= shot_range and _has_los

	_strafe_time -= delta
	if _strafe_time <= 0.0:
		_strafe_sign = -_strafe_sign
		_strafe_time = _rng.randf_range(strafe_flip_min, strafe_flip_max)

	# Perpendicular to the player direction, which is the tangent of the ring.
	var tangent := Vector2(-toward.y, toward.x) * _strafe_sign

	var offset := distance - orbit_radius
	if absf(offset) > orbit_band:
		# Off the ring: correct the distance, but keep some sideways drift so
		# closing in doesn't look like a straight tram line.
		frame.move = (toward * signf(offset) + tangent * 0.5).normalized()
	else:
		frame.move = tangent

	return frame

func _think_patrol(delta: float) -> InputFrame:
	var frame := InputFrame.new()

	# Standing still between legs. Empty frame = no movement, keep facing.
	if _pause_time > 0.0:
		_pause_time -= delta
		return frame

	_leg_time += delta

	var to_target := _patrol_target - global_position
	if to_target.length() <= arrive_distance or _leg_time >= patrol_leg_timeout:
		_pause_time = _rng.randf_range(patrol_pause_min, patrol_pause_max)
		_pick_patrol_target()
		return frame

	frame.move = to_target.normalized()
	frame.aim = frame.move

	return frame

# A clear line to the player, with nothing on sight_blocker_mask in between.
func _can_see(target: Node2D) -> bool:
	var query := PhysicsRayQueryParameters2D.create(
		global_position, target.global_position, sight_blocker_mask
	)
	# No exclude list needed: we sit on `enemy` and the mask is `world`, so the
	# ray can't start by hitting ourselves.
	query.collide_with_areas = false

	return get_world_2d().direct_space_state.intersect_ray(query).is_empty()

func _with_spread(direction: Vector2) -> Vector2:
	if spread_degrees <= 0.0:
		return direction
	var half := deg_to_rad(spread_degrees) * 0.5
	return direction.rotated(_rng.randf_range(-half, half))

func _pick_patrol_target() -> void:
	var angle := _rng.randf_range(0.0, TAU)
	var distance := _rng.randf_range(patrol_radius * 0.3, patrol_radius)
	_patrol_target = _home + Vector2.RIGHT.rotated(angle) * distance
	_leg_time = 0.0

func _tracer_container() -> Node:
	if tracer_container_path.is_empty():
		return get_parent()
	return get_node(tracer_container_path)

func _find_player() -> Node2D:
	# Re-acquire if the player died or hasn't spawned yet. Group lookup rather
	# than an absolute path, so this survives a second player (CLAUDE.md rule 5).
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	return _player
