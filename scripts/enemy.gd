class_name Enemy
extends CharacterBody2D

# Wanders around where it spawned until the player gets close, then fights from
# cover: it finds a spot the player has no line to, sits there while the burst
# clock winds up, steps out to spray the burst, and drops straight back behind
# the wall. Every decision produces an InputFrame and goes through
# Movement.apply, the same path the player's keyboard takes.

# Emitted once, the moment we die. The node stays in the tree afterwards as an
# inert corpse, so anything listening can still read our position or loot table
# off `enemy` instead of having to copy it out beforehand.
signal died(enemy: Enemy)

enum State { PATROL, CHASE }
# What we're doing inside CHASE. COVER is "behind something, reloading"; PEEK is
# "out in the open with a loaded burst". The burst clock is the only thing that
# switches between them.
enum Stance { COVER, PEEK }

@export_group("Movement")
@export var speed: float = 100.0
@export var chase_speed: float = 150.0

@export_group("Detection")
@export var detection_radius: float = 250.0
# Deliberately larger than detection_radius. Without the gap an enemy sitting
# exactly on the edge flips between states every tick.
@export var lose_radius: float = 340.0
# How long we keep hunting after losing the player. The clock is refreshed every
# tick we can still see them, and does not run at all while we are deliberately
# sitting in cover -- hiding on purpose is not losing contact, or every enemy
# would forget the player halfway through its own reload. It is also what stops
# a hit from long range being undone by _update_state on the very next tick,
# which would leave the enemy never visibly reacting to being shot.
@export var min_chase_time: float = 4.0
# What blocks sight. Walls are on `world`; deliberately NOT player or enemy, or
# a pack would blind itself by standing in its own way. Corpses zero their
# layers when they die, so they don't provide cover either.
@export_flags_2d_physics var sight_blocker_mask: int = CollisionLayers.WORLD

@export_group("Combat")
# How far from the player we'd like to fight. Cover spots are scored against
# this, and it's what we hold when there is no cover at all. Keep it under
# lose_radius, or backing off would walk us out of our own engagement and
# straight back to patrolling.
@export var preferred_range: float = 220.0
# Half-width of the band around preferred_range where we stop correcting
# distance. Only used out in the open, where without it we jitter in and out on
# the exact radius.
@export var range_band: float = 24.0
# Aim error, so a pack doesn't land every shot on the same pixel. Wide enough
# that a burst sprays rather than stacks -- an enemy that hits with all three
# shots every time is not survivable at this fire rate.
@export var spread_degrees: float = 25.0

@export_group("Cover")
# Candidate spots are sampled on rings around us: cover_search_samples
# directions per ring, cover_search_rings rings out to cover_search_radius. Each
# candidate costs up to two raycasts, which is why a search only runs when the
# cover we have goes bad, not every tick.
@export var cover_search_radius: float = 260.0
@export var cover_search_samples: int = 10
@export var cover_search_rings: int = 2
# Don't hide behind something in the player's face -- a "cover" spot a stride
# away from them is just a box they walk around.
@export var cover_min_player_distance: float = 110.0
# How much a candidate's distance from preferred_range counts against it,
# relative to how far we'd have to walk to reach it. Above 1.0 we'll cross the
# room for a better firing distance; below it we grab whatever is nearest.
@export var cover_range_weight: float = 0.6
# Close enough to count as standing on the spot.
@export var cover_arrive_distance: float = 14.0
# How often the cover we're sitting behind is re-checked against where the
# player has moved to. One raycast.
@export var cover_recheck_interval: float = 0.35
# Safety net: we walk to cover in a straight line with no pathfinding, so if a
# corner eats us this is what makes us pick somewhere else.
@export var cover_leg_timeout: float = 2.5
# How far out of cover one peek step is, and how many steps out we'll try before
# giving up on the angle. Sideways along the wall first -- leaning out is
# cheaper than walking into the open.
@export var peek_offset: float = 42.0
@export var peek_steps: int = 3
# Stepped out, waited this long, and never got a line on them: the angle is
# dead. We dump the loaded burst and reposition rather than stand in the open
# holding it.
@export var peek_timeout: float = 2.0

@export_group("Weapon")
# Enemies fire in bursts: burst_size shots burst_shot_interval apart, then a
# burst_delay pause before the next one. The pause is what they spend behind
# cover, so it runs down for as long as we're in a fight -- out of sight
# included -- and the moment it lands the burst is loaded and we step out. It is
# armed up front, so the first burst after spotting the player costs the same
# wind-up as every one after it.
@export var burst_size: int = 3
# Spacing between the shots inside one burst.
@export var burst_shot_interval: float = 0.12
# Between bursts, rolled from our own seeded stream so a pack doesn't fire in
# unison. This is also roughly how long we stay hidden for.
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
var stance: Stance = Stance.COVER

var weapon := Weapon.new()

var _home: Vector2 = Vector2.ZERO
var _patrol_target: Vector2 = Vector2.ZERO
var _leg_time: float = 0.0
var _pause_time: float = 0.0
var _chase_time_left: float = 0.0
var _player: Node2D = null
# Whether we could see the player on this tick. Cast once in _update_state and
# reused by _think_chase, which needs the same answer to decide whether to
# shoot -- casting it twice a tick would just cost twice.
var _has_los: bool = false
# The spot we hide on and the spot we step out to, both in world space.
# _has_cover false means the search came up empty and we're fighting in the open
# instead.
var _has_cover: bool = false
var _cover_point: Vector2 = Vector2.ZERO
var _peek_point: Vector2 = Vector2.ZERO
var _cover_recheck: float = 0.0
# How long we've been walking at the current spot without arriving, and how long
# we've been stood out in the open on this peek.
var _move_leg_time: float = 0.0
var _peek_time: float = 0.0
# Which way along the wall we lean out first. Flipped each peek, so we don't
# offer the same shoulder every time.
var _peek_side: float = 1.0
# Shots left in the burst we're currently firing; 0 means we're between bursts.
var _burst_left: int = 0
# Time until the next burst may start.
var _burst_delay: float = 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	health = max_health
	_home = global_position

	# Our own stream, derived from the run seed, so a given raid always plays
	# out the same way. Bare randf() would not (CLAUDE.md rule 4).
	_rng.seed = GameManager.rng.randi()

	# Stagger which shoulder a pack leans out on.
	_peek_side = 1.0 if _rng.randf() < 0.5 else -1.0

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
	_update_burst(delta)
	# frame.shoot is false for the whole time we're behind cover, and while
	# we're out but the line is broken. can_fire() before _with_spread so we
	# only roll spread on shots we actually take -- otherwise the seeded stream
	# advances once per tick just to be discarded.
	if frame.shoot and _burst_left > 0 and weapon.can_fire():
		# Only a shot that actually left the barrel counts against the burst.
		if weapon.fire(_tracer_container(), self, _with_spread(frame.aim)):
			_burst_left -= 1
			if _burst_left <= 0:
				_arm_burst_delay()

# The burst clock, and the thing that drives the whole cover cycle. It runs for
# as long as we're in a fight, whether or not we can see anyone: waiting it out
# behind a wall is the point, and freezing it there would leave us hidden
# forever. A burst that is already loaded ticks nothing -- its shots are paced
# by the weapon's own cooldown, and holding fire keeps it loaded, so a peek
# spends the shots we hid to earn rather than starting a fresh wind-up.
func _update_burst(delta: float) -> void:
	if state != State.CHASE:
		return

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
	# The give-up clock only runs while we're actually exposed and looking. A
	# reload spent behind a wall is our own doing, not the player breaking
	# contact, and running it down through cover would have us wander off
	# mid-fight.
	if not _is_holding_cover():
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
				# Lost them long enough. Because the clock is frozen while we
				# hold cover, this can only run out across peeks -- we gave up
				# after stepping out and finding nobody, not while hiding. A hit
				# from out of sight refreshes the same clock through
				# _enter_chase, so we don't shrug off being shot from cover.
				_give_up()

# Behind cover on purpose, as opposed to merely not being able to see anyone.
func _is_holding_cover() -> bool:
	return state == State.CHASE and stance == Stance.COVER and _has_cover

func _enter_chase() -> void:
	# Only on the way in, so repeated hits extend the chase without restarting
	# the cover search underneath a fight already in progress.
	if state != State.CHASE:
		stance = Stance.COVER
		_has_cover = false
		_cover_recheck = 0.0
		_move_leg_time = 0.0
		_peek_time = 0.0

	state = State.CHASE
	# Refreshed on every trigger, so repeated hits keep extending the chase
	# rather than running down a clock started by the first one.
	_chase_time_left = min_chase_time

func _give_up() -> void:
	state = State.PATROL
	stance = Stance.COVER
	_has_cover = false
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

	var player_position := target.global_position
	var to_player := player_position - global_position
	var distance := to_player.length()
	if distance < 0.001:
		return frame

	var toward := to_player / distance

	# Keep the gun on the player the whole time, including on the way back
	# behind the wall -- Movement.apply turns aim into our facing.
	frame.aim = toward

	_update_stance(delta, player_position)

	# We only shoot on a peek, and only with a line: no firing through the wall
	# we're hiding behind, and no burning shots that fall short of a player who
	# dragged us into CHASE from outside our own weapon range.
	frame.shoot = stance == Stance.PEEK and _has_los and distance <= shot_range

	if not _has_cover:
		# Nothing to hide behind anywhere near us. Hold the preferred range and
		# keep to the same burst rhythm -- worse, but it beats standing still in
		# the middle of an open room.
		frame.move = _think_in_the_open(toward, distance)
		return frame

	frame.move = _seek(_peek_point if stance == Stance.PEEK else _cover_point)
	return frame

# Hidden until the burst lands, out until it's spent. _update_burst is what
# drives the cycle; everything here just reacts to whether a burst is loaded.
func _update_stance(delta: float, player_position: Vector2) -> void:
	var want_peek := _burst_left > 0

	if want_peek and stance == Stance.COVER:
		_enter_peek(player_position)
	elif not want_peek and stance == Stance.PEEK:
		# Burst spent. Straight back behind something -- and a fresh search,
		# since the player just watched us fire from here.
		_enter_cover(player_position)

	if stance == Stance.PEEK:
		_peek_time += delta
		# Out in the open with a loaded burst and still no line: the angle is
		# dead. Drop the burst, wind up again, and try somewhere else rather
		# than stand there holding it.
		if _peek_time >= peek_timeout and not _has_los:
			_burst_left = 0
			_arm_burst_delay()
			_enter_cover(player_position)
		return

	_move_leg_time += delta
	# Walking at the spot too long without arriving: with no pathfinding, a
	# corner in the way is a stall until we pick somewhere else.
	if _has_cover and _move_leg_time >= cover_leg_timeout:
		_enter_cover(player_position)
		return

	_cover_recheck -= delta
	if _cover_recheck > 0.0:
		return
	_cover_recheck = cover_recheck_interval

	# Either we never had cover, or the player has walked somewhere that can see
	# the spot we're sitting on. Either way, find another.
	if not _has_cover or _line_clear(_cover_point, player_position):
		_enter_cover(player_position)

func _enter_cover(player_position: Vector2) -> void:
	stance = Stance.COVER
	_peek_time = 0.0
	_move_leg_time = 0.0
	_cover_recheck = cover_recheck_interval
	_has_cover = _find_cover(player_position)

func _enter_peek(player_position: Vector2) -> void:
	stance = Stance.PEEK
	_peek_time = 0.0
	_move_leg_time = 0.0
	# Other shoulder next time.
	_peek_side = -_peek_side

	if _has_cover:
		_peek_point = _find_peek_point(_cover_point, player_position)

# How we fight when there's nothing to fight from behind: hold the preferred
# range, in a straight line, and no closer. Deliberately not orbiting -- that
# was the old behaviour, and circling a player in the open reads as dancing
# rather than as a threat.
func _think_in_the_open(toward: Vector2, distance: float) -> Vector2:
	var offset := distance - preferred_range
	if absf(offset) <= range_band:
		return Vector2.ZERO
	return toward * signf(offset)

func _seek(point: Vector2) -> Vector2:
	var to_point := point - global_position
	var distance := to_point.length()
	if distance <= cover_arrive_distance:
		# Arrived: stand still, and stop counting this leg against the stall
		# timeout.
		_move_leg_time = 0.0
		return Vector2.ZERO
	return to_point / distance

# Sample rings of spots around us and take the best one the player has no line
# to. Costs up to two raycasts per candidate, which is why it only runs when the
# cover we have goes bad rather than every tick. Returns false if the room is
# open enough that nothing hides us.
func _find_cover(player_position: Vector2) -> bool:
	if cover_search_samples <= 0 or cover_search_rings <= 0:
		return false

	var best_point := Vector2.ZERO
	var best_score := INF
	var found := false

	# Rotate the whole sample pattern, so a pack standing in a line doesn't all
	# test the same handful of spots. Seeded, like everything else we roll.
	var jitter := _rng.randf() * TAU

	for ring in cover_search_rings:
		var radius := cover_search_radius * float(ring + 1) / float(cover_search_rings)
		for i in cover_search_samples:
			var angle := jitter + TAU * float(i) / float(cover_search_samples)
			var candidate := global_position + Vector2.RIGHT.rotated(angle) * radius

			var player_distance := candidate.distance_to(player_position)
			# Too close to be cover, or so far that holding it would walk us out
			# of our own engagement.
			if player_distance < cover_min_player_distance or player_distance > lose_radius:
				continue

			# It has to actually hide us...
			if _line_clear(candidate, player_position):
				continue
			# ...and we have to be able to walk there. A straight line is a
			# crude stand-in for a path, but with no navmesh it's what we have,
			# and cover_leg_timeout catches the cases it gets wrong.
			if not _line_clear(global_position, candidate):
				continue

			var score := candidate.distance_to(global_position) \
				+ absf(player_distance - preferred_range) * cover_range_weight
			if score < best_score:
				best_score = score
				best_point = candidate
				found = true

	if found:
		_cover_point = best_point

	return found

# The spot we step out to. Sideways along the wall first, one peek_offset at a
# time and alternating shoulders: leaning out is cheaper than walking into the
# open, and it keeps us beside the thing we're about to duck back behind.
func _find_peek_point(cover: Vector2, player_position: Vector2) -> Vector2:
	var to_player := player_position - cover
	if to_player.length_squared() < 0.001:
		return cover

	var toward := to_player.normalized()

	# The player has already walked round to see our cover spot. No stepping out
	# required -- we're out. The recheck when we duck back finds new cover.
	if _line_clear(cover, player_position):
		return cover

	var along := Vector2(-toward.y, toward.x)

	for step in peek_steps:
		var lean := along * peek_offset * float(step + 1)
		# Preferred shoulder first, then the other one at the same distance out.
		var near_side := cover + lean * _peek_side
		if _peek_point_works(cover, near_side, player_position):
			return near_side
		var far_side := cover - lean * _peek_side
		if _peek_point_works(cover, far_side, player_position):
			return far_side

	# Nothing sideways works -- the wall runs too far in both directions. Lean
	# forward past the edge instead.
	for step in peek_steps:
		var candidate := cover + toward * peek_offset * float(step + 1)
		if _peek_point_works(cover, candidate, player_position):
			return candidate

	# No firing angle from this spot at all. Sit tight: peek_timeout gives up on
	# it and _enter_cover finds somewhere else.
	return cover

func _peek_point_works(cover: Vector2, candidate: Vector2, player_position: Vector2) -> bool:
	# Has to open a line on the player, and has to be somewhere we can step to
	# without walking through the cover itself.
	return _line_clear(candidate, player_position) and _line_clear(cover, candidate)

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
	return _line_clear(global_position, target.global_position)

# Nothing on sight_blocker_mask between two points. The one place sight, cover
# and peek angles are all decided, so they can never disagree about what counts
# as a wall.
func _line_clear(from: Vector2, to: Vector2) -> bool:
	var query := PhysicsRayQueryParameters2D.create(from, to, sight_blocker_mask)
	# No exclude list needed: bodies sit on `player` and `enemy` and the mask is
	# `world`, so a ray starting on top of one can't hit it.
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
