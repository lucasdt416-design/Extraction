extends Node

# --- SCAFFOLD: this script should be set as an Autoload/Singleton ---
# --- (see setup steps) so it persists across scene changes. ---
# --- Use it to track things that need to survive between the raid ---
# --- scene and the results/menu scenes. ---

# Loot the player is currently carrying DURING a raid (lost if they die)
var current_run_loot: Array = []

# Loot the player has permanently banked (kept after successful extraction)
var stash: Array = []

func add_loot_to_run(item_name: String, value: int) -> void:
	current_run_loot.append({"name": item_name, "value": value})

# TODO: your logic here
# Ideas to implement:
# 1. extract_success() -> called when player reaches extraction zone and timer completes
#    - move everything from current_run_loot into stash
#    - clear current_run_loot
#    - change_scene_to_file() to your results/menu scene
# 2. player_died() -> called when player health hits 0
#    - clear current_run_loot (they lose it, that's the risk/reward!)
#    - change_scene_to_file() to a "you died" or menu scene
# 3. start_new_run() -> called when starting a new raid from the menu
#    - clear current_run_loot
#    - change_scene_to_file() to your main map scene
