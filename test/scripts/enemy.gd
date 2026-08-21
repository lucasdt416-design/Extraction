extends CharacterBody2D

# --- SCAFFOLD: node references and export vars are set up for you ---
# --- YOUR TODO: fill in the chase/detect logic below ---

@export var speed: float = 100.0
@export var detection_radius: float = 250.0

var player: Node2D = null

func _ready() -> void:
	# Scaffold: grabs the player node so you don't have to figure out
	# the node path yourself. Assumes player is in a "player" group
	# (we'll add the player to that group when wiring up the scene).
	player = get_tree().get_first_node_in_group("player")

func _physics_process(_delta: float) -> void:
	# TODO: your logic here
	# Ideas to implement:
	# 1. Check distance to `player` using global_position.distance_to(player.global_position)
	# 2. If within detection_radius, move toward the player:
	#    var direction = (player.global_position - global_position).normalized()
	#    velocity = direction * speed
	#    move_and_slide()
	# 3. If player is out of range, maybe idle or patrol instead
	pass
