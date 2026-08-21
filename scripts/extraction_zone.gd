extends Area2D

# --- SCAFFOLD: this is an Area2D the player walks into to extract ---
# --- YOUR TODO: fill in the extraction logic below ---

@export var extraction_time: float = 3.0  # how long player must stand in zone

var player_inside: bool = false
var timer: float = 0.0

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_inside = true
		timer = 0.0

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_inside = false
		timer = 0.0

func _process(delta: float) -> void:
	# TODO: your logic here
	# Ideas to implement:
	# 1. If player_inside is true, count up `timer` by delta
	# 2. If timer >= extraction_time, trigger a successful extraction:
	#    - call a function on GameManager (autoload) like GameManager.extract_success()
	#    - that function should save the loot the player collected and
	#      change scenes to a "results" or "main menu" screen
	# 3. Bonus: show a progress bar or countdown text on the HUD while extracting
	pass
