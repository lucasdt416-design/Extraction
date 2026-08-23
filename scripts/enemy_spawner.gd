@tool
class_name EnemySpawner
extends Node2D

# A spawn point that quietly repopulates itself.
#
# Two clocks decide whether an enemy appears here:
#
#   spawn_interval       -- counts down from every spawn. At zero the spawner is
#                           "armed": it wants to put an enemy here.
#   observation_cooldown -- how long the spot has to have been out of the
#                           player's sight before an armed spawner is allowed to
#                           fire. Reset to zero every tick the player is inside
#                           observation_radius.
#
# An armed spawner that can't fire *stays* armed -- the interval clock does not
# restart. So camping a corner for ten minutes costs the player one spawn's
# delay rather than ten minutes of spawns, and the enemy walks in the moment
# they wander off. Nothing ever pops into existence in front of them.
#
# Observation is pure distance, not line of sight: standing on the far side of a
# wall a stride away still counts as being here. That's deliberate -- the rule is
# "the player was recently in this area", not "the player could see this exact
# pixel", and it costs one distance check per tick instead of a raycast.

# Emitted right after an enemy is placed in the world, so a wave counter, a HUD
# or an audio cue can hang off it later without this script knowing about them.
signal enemy_spawned(enemy: Node2D)

@export_group("Spawning")
# What to spawn. Anything whose root is a Node2D works: the spawner places it
# and then only ever reads `is_dead` off it, so it doesn't care what script it
# carries.
@export var enemy_scene: PackedScene = preload("res://enemy.tscn")
# Seconds between spawns. 300 is five minutes. Turn it down to something like 10
# while you're testing -- that's the whole point of it being an export.
@export var spawn_interval: float = 300.0
# What the spawn clock reads when the raid starts. Zero means the spawner is
# armed from the very first tick, so a fresh map populates immediately (nobody
# has observed anything yet, so the observation gate is open) instead of sitting
# empty for the first five minutes. Raise it if you want a map that fills up as
# the raid goes on.
@export var initial_spawn_delay: float = 0.0
# How many living enemies from this spawner may exist at once. Corpses don't
# count -- a dead enemy stays in the tree as a marker, but it isn't a threat and
# shouldn't hold a slot. At 1 this reads as "one enemy guards this spot, and
# comes back a while after you kill him".
@export var max_alive: int = 2
# Where spawned enemies are parented. Empty means our own parent, so they end up
# as siblings of the spawner rather than nested under it -- an enemy that walks
# away shouldn't still be hanging off the spot it came from. An exported
# NodePath rather than a hardcoded path, per rule 5.
@export var spawn_container_path: NodePath

@export_group("Observation")
# How close the player has to get for this spot to count as observed. Wants to
# comfortably exceed how much of the map fits on screen at once, or an enemy can
# appear at the edge of the view.
@export var observation_radius: float = 500.0:
	set(value):
		observation_radius = maxf(value, 0.0)
		queue_redraw()
# The spot must have been unobserved for longer than this before an armed
# spawner fires. 60 is one minute.
@export var observation_cooldown: float = 60.0

@export_group("Debug")
# Draws the observation radius in the running game (it is always drawn in the
# editor) and prints a line on every spawn. Tick this while tuning the timings
# above; it's how you confirm the rules fire when you think they do.
@export var show_debug: bool = false:
	set(value):
		show_debug = value
		queue_redraw()

# Counts down; at or below zero we are armed and looking for a chance to spawn.
var _time_to_spawn: float = 0.0
# Time since the player was last inside observation_radius. Starts high, not at
# zero: at raid start nobody has been here yet, and treating that as "just
# observed" would make every spawner sit idle through the first cooldown.
var _time_since_observed: float = INF
# Everything we have put in the world, living or dead. Pruned as nodes are freed.
var _spawned: Array[Node2D] = []
var _player: Node2D = null

func _ready() -> void:
	_time_to_spawn = initial_spawn_delay

	if Engine.is_editor_hint():
		# The editor never ticks the rules below; it only draws the gizmo.
		set_physics_process(false)

# Gameplay on the fixed tick (rule 3), so the timings don't drift with framerate.
func _physics_process(delta: float) -> void:
	_update_observation(delta)

	if _time_to_spawn > 0.0:
		_time_to_spawn -= delta

	if _is_ready_to_spawn():
		_spawn()

	if show_debug:
		# Visual only -- the drawing itself happens in _draw, on the render
		# frame. Nothing here decides anything.
		queue_redraw()

# --- The two clocks ----------------------------------------------------------

func _update_observation(delta: float) -> void:
	var player := _get_player()
	if player == null:
		# Nobody here to be seen by, so the spot keeps ageing. A spawner in a
		# raid the player hasn't been inserted into yet still arms.
		_time_since_observed += delta
		return

	if global_position.distance_to(player.global_position) <= observation_radius:
		_time_since_observed = 0.0
	else:
		_time_since_observed += delta

func _is_ready_to_spawn() -> bool:
	if enemy_scene == null:
		return false
	# Strictly greater, matching "more than a minute since they were here".
	if _time_to_spawn > 0.0 or _time_since_observed <= observation_cooldown:
		return false
	return _alive_count() < max_alive

# --- Spawning ----------------------------------------------------------------

func _spawn() -> void:
	var enemy := enemy_scene.instantiate() as Node2D
	if enemy == null:
		push_warning("EnemySpawner: enemy_scene's root is not a Node2D; nothing spawned.")
		# Re-arm anyway, or a misconfigured spawner retries every single tick.
		_time_to_spawn = spawn_interval
		return

	var container := _spawn_container()
	# The position is set BEFORE add_child on purpose. Enemy._ready() reads its
	# own global_position to decide where it patrols around, and _ready fires the
	# moment it enters the tree -- place it afterwards and it would spend the
	# rest of the raid wandering around wherever its scene file left it.
	var container_2d := container as Node2D
	enemy.position = container_2d.to_local(global_position) if container_2d != null else global_position
	container.add_child(enemy)

	_spawned.append(enemy)
	_time_to_spawn = spawn_interval

	if show_debug:
		print("[EnemySpawner] %s spawned %s (unobserved for %.1fs, next in %.0fs)"
			% [name, enemy.name, _time_since_observed, spawn_interval])

	enemy_spawned.emit(enemy)

func _spawn_container() -> Node:
	if not spawn_container_path.is_empty():
		var node := get_node_or_null(spawn_container_path)
		if node != null:
			return node
		push_warning("EnemySpawner: spawn_container_path points at nothing; using our parent.")

	var parent := get_parent()
	return parent if parent != null else self

# Living enemies only. An Enemy corpse stays in the tree with its collision
# layers zeroed, so is_instance_valid alone can't tell a threat from a body.
func _alive_count() -> int:
	var alive := 0
	for i in range(_spawned.size() - 1, -1, -1):
		var enemy := _spawned[i]
		if not is_instance_valid(enemy):
			_spawned.remove_at(i)
			continue
		if enemy.get("is_dead") == true:
			continue
		alive += 1
	return alive

func _get_player() -> Node2D:
	# Re-acquired whenever the reference goes stale: the player may not exist yet
	# when the raid loads. Looked up by group rather than by path, so this still
	# works the day there are two of them (rule 5).
	if not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node2D
	return _player

# --- Editor / debug gizmo ----------------------------------------------------

func _draw() -> void:
	if not (Engine.is_editor_hint() or show_debug):
		return

	# The spot itself: a small cross, so an empty spawner is still visible.
	var arm := 10.0
	var marker := Color(1.0, 0.55, 0.2)
	draw_line(Vector2(-arm, 0.0), Vector2(arm, 0.0), marker, 2.0)
	draw_line(Vector2(0.0, -arm), Vector2(0.0, arm), marker, 2.0)

	# The observation radius. In game it reads amber while the player is inside
	# the cooldown (spawning blocked) and green once the spot has gone cold.
	var ring := marker
	if not Engine.is_editor_hint():
		ring = Color(0.3, 0.9, 0.4) if _time_since_observed > observation_cooldown else Color(0.95, 0.75, 0.15)
	draw_arc(Vector2.ZERO, observation_radius, 0.0, TAU, 64, ring, 1.0)

func _get_configuration_warnings() -> PackedStringArray:
	if enemy_scene == null:
		return PackedStringArray(["No enemy_scene set -- this spawner will never spawn anything."])
	return PackedStringArray()
