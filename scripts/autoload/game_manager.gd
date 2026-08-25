extends Node

# --- SCAFFOLD: this script should be set as an Autoload/Singleton ---
# --- (see setup steps) so it persists across scene changes. ---
# --- Use it to track things that need to survive between the raid ---
# --- scene and the results/menu scenes. ---

# Emitted when the local player dies. UI and future scene flow hang off this.
signal local_player_died
signal local_player_extracted


# The local "you died" blackout, if one is up. Local view only -- never part of
# the raid state that would have to agree between host and client.
var _death_screen: DeathScreen = null

# Loot the player is currently carrying DURING a raid (lost if they die)
var current_run_loot: Array = []

# Loot the player has permanently banked (kept after successful extraction)
var stash: Array = []

func add_loot_to_run(item_name: String, value: int) -> void:
	current_run_loot.append({"name": item_name, "value": value})

# --- Seeded randomness (CLAUDE.md rule 4) ---
# Anything random in a raid -- loot rolls, weapon spread, AI wander -- pulls
# from this, never from bare randf(). Same seed in, same raid out, which is
# what makes bugs reproducible now and host/client agreement possible later.
var run_seed: int = 0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	seed_run(run_seed)

# Call this from start_new_run() once you want raids to vary:
#   GameManager.seed_run(randi())
func seed_run(new_seed: int) -> void:
	run_seed = new_seed
	rng.seed = run_seed

# Called by the local player when its health hits zero. This is the one place
# that reacts to a player death (CLAUDE.md rule 2) -- the player node itself
# only reports the fact.
#
# Deliberately does NOT pause the tree or change scene: the raid keeps
# simulating around the dead player, which is how it has to behave once a
# second player is in the same raid. Death is a local view change, not a world
# state change.
func player_died(_player: Node = null) -> void:
	if is_instance_valid(_death_screen):
		return

	# Carried loot is lost. That's the whole risk/reward of an extraction raid.
	current_run_loot.clear()

	local_player_died.emit()

	_death_screen = DeathScreen.new()
	add_child(_death_screen)

# Takes the blackout back down. Call this when a new raid starts.
func clear_death_screen() -> void:
	if is_instance_valid(_death_screen):
		_death_screen.queue_free()
	_death_screen = null

# TODO: your logic here
# Ideas to implement:
# 1. extract_success() -> called when player reaches extraction zone and timer completes
#    - move everything from current_run_loot into stash
#    - clear current_run_loot
#    - change_scene_to_file() to your results/menu scene
# 2. start_new_run() -> called when starting a new raid from the menu
#    - clear current_run_loot
#    - clear_death_screen()
#    - change_scene_to_file() to your main map scene

func extract_success(player: Node2D):
	stash.append_array(current_run_loot)
	current_run_loot.clear()
	local_player_extracted.emit()
	player.extracted()
