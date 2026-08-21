extends Area2D

# --- SCAFFOLD: signal connection happens automatically via the "body_entered" ---
# --- signal below (wired up in the editor - see setup steps) ---
# --- YOUR TODO: fill in what happens when the player picks this up ---

@export var loot_name: String = "Scrap"
@export var loot_value: int = 10

func _on_body_entered(body: Node2D) -> void:
	# This fires automatically when something enters this Area2D's collision shape.
	# TODO: your logic here
	# Ideas to implement:
	# 1. Check if `body` is the player (e.g. body.is_in_group("player"))
	# 2. Add this item to the player's inventory (you'll need to design
	#    what "inventory" looks like - could be as simple as an Array
	#    or Dictionary on GameManager, see game_manager.gd)
	# 3. Call queue_free() to remove this loot item from the world after pickup
	pass
