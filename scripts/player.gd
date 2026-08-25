class_name Player
extends CharacterBody2D

# Emitted once when health reaches zero, for anything that wants to react
# locally (HUD, sound, a future spectator camera). The authoritative reaction
# lives in GameManager.player_died(), which this also calls.
signal died

@export var speed: float = 220.0

@export_group("Health")
@export var max_health: int = 5

@export_group("Weapon")
# Seconds between shots while the fire button is held down.
@export var fire_interval: float = 0.12
# Shots are hitscan -- this is how far one carries, not how fast it flies.
@export var shot_range: float = 900.0
@export var shot_damage: int = 1
# Clear of our own collider (radius ~21), so shots don't start inside us.
@export var muzzle_offset: float = 28.0
# How long the shot's tracer lingers, in seconds. Cosmetic; 0.0 draws none.
@export var tracer_lifetime: float = 0.05
# Where tracers get parented. Leave empty to use our own parent.
@export var tracer_container_path: NodePath

var health: int = 0
# Once true the player stops acting, but stays in the world: the body is still
# there, enemies still simulate around it and still shoot. Only this client's
# view goes dark. Nothing here stops or pauses anyone else.
var is_dead: bool = false

var input_source := PlayerInputSource.new()
var weapon := Weapon.new()

func _ready() -> void:
	health = max_health

	weapon.fire_interval = fire_interval
	weapon.shot_range = shot_range
	weapon.damage = shot_damage
	weapon.muzzle_offset = muzzle_offset
	weapon.tracer_lifetime = tracer_lifetime

func _physics_process(delta: float) -> void:
	if is_dead:
		# Dead players produce no input. Feeding an empty frame rather than
		# skipping Movement.apply keeps the body settling through the one place
		# allowed to touch velocity (CLAUDE.md rule 1)
		Movement.apply(self, InputFrame.new(), speed)
		return

	var frame := input_source.poll(self)

	Movement.apply(self, frame, speed)

	weapon.tick(delta)
	if frame.shoot:
		weapon.fire(_tracer_container(), self, frame.aim)

# The one place player health changes (CLAUDE.md rule 2).
func take_damage(amount: int, _from: Node = null) -> void:
	if is_dead:
		return

	health -= amount

	if health <= 0:
		health = 0
		is_dead = true
		died.emit()
		GameManager.player_died(self)

func _tracer_container() -> Node:
	if tracer_container_path.is_empty():
		return get_parent()
	return get_node(tracer_container_path)
	
#Placeholder function for now
func extracted():
	queue_free()
