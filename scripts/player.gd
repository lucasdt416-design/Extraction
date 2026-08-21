extends CharacterBody2D

# --- SCAFFOLD: movement is done for you, don't need to touch this ---

@export var speed: float = 220.0

func _physics_process(_delta: float) -> void:
	var input_dir := Vector2.ZERO
	input_dir.x = Input.get_axis("move_left", "move_right")
	input_dir.y = Input.get_axis("move_up", "move_down")
	input_dir = input_dir.normalized()

	velocity = input_dir * speed
	move_and_slide()

	# Rotate player to face movement direction (feels better for top-down)
	if input_dir.length() > 0.1:
		rotation = input_dir.angle()
