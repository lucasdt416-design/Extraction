extends CharacterBody2D

# Emitted once when health reaches zero. Nothing consumes it yet -- wiring it
# to GameManager.player_died() is the TODO in game_manager.gd.
signal died

@export var speed: float = 220.0

@export_group("Health")
@export var max_health: int = 5

@export_group("Weapon")
# Seconds between shots while the fire button is held down.
@export var fire_interval: float = 0.12
@export var bullet_speed: float = 900.0
@export var bullet_range: float = 900.0
@export var bullet_length: float = 14.0
@export var bullet_damage: int = 1
# Clear of our own collider (radius ~21), so shots don't start inside us.
@export var muzzle_offset: float = 28.0
# Where bullets get parented. Leave empty to use our own parent.
@export var bullet_container_path: NodePath

var health: int = 0

var input_source := PlayerInputSource.new()
var weapon := Weapon.new()

func _ready() -> void:
	health = max_health

	weapon.fire_interval = fire_interval
	weapon.bullet_speed = bullet_speed
	weapon.bullet_range = bullet_range
	weapon.bullet_length = bullet_length
	weapon.bullet_damage = bullet_damage
	weapon.muzzle_offset = muzzle_offset

func _physics_process(delta: float) -> void:
	var frame := input_source.poll(self)

	Movement.apply(self, frame, speed)

	weapon.tick(delta)
	if frame.shoot:
		weapon.fire(_bullet_container(), self, frame.aim)

# The one place player health changes (CLAUDE.md rule 2).
func take_damage(amount: int, _from: Node = null) -> void:
	if health <= 0:
		return

	health -= amount

	if health <= 0:
		died.emit()

func _bullet_container() -> Node:
	if bullet_container_path.is_empty():
		return get_parent()
	return get_node(bullet_container_path)
