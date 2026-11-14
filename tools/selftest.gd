extends Node

# Development helper: plays through the core loop with a scripted input source
# and prints PASS/FAIL per check. Run headless:
#   godot --headless --path . res://tools/selftest.tscn -- --test-profile

class Bot extends PlayerInputSource:
	var frame := InputFrame.new()
	func poll() -> InputFrame:
		var out := frame
		frame = InputFrame.new()
		frame.shoot = out.shoot
		frame.interact = out.interact
		frame.move = out.move
		return out

var _fails: int = 0

func check(label: String, ok: bool, detail: String = "") -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		_fails += 1

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func aim(player: Player, at: Vector3) -> void:
	var to := at - player.eye_position()
	player.set("_yaw", atan2(-to.x, -to.z))
	player.set("_pitch", atan2(to.y, Vector2(to.x, to.z).length()))

func _ready() -> void:
	GameManager.reset_profile()
	GameManager.credits = 5000
	check("buy rifle", GameManager.buy("rifle") and GameManager.stash.has("rifle"))
	GameManager.equip(GameManager.stash.find("rifle"))
	check("equip rifle", GameManager.loadout["primary"] == "rifle")
	GameManager.in_raid = true
	GameManager.backpack.assign(["medkit"])

	var raid: Raid = load("res://scenes/raid.tscn").instantiate()
	add_child(raid)
	await wait(1.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var player := raid.player
	var bot := Bot.new()
	player.add_child(bot)
	player.input_source = bot
	var enemies := get_tree().get_nodes_in_group("enemy")
	check("enemies spawned", enemies.size() >= 15, str(enemies.size()))
	check("weapons", player.guns.size() == 2 and player.guns[0].id == "rifle")

	# Patrols actually move along the navmesh.
	var before: Array[Vector3] = []
	for e in enemies:
		before.append((e as Enemy).global_position)
	await wait(6.0)
	var moved := 0
	for i in enemies.size():
		if (enemies[i] as Enemy).global_position.distance_to(before[i]) > 1.0:
			moved += 1
	check("patrols move", moved >= enemies.size() / 2, "%d of %d" % [moved, enemies.size()])

	var fighting := 0
	for squad in Squad.all:
		if squad.mode == Squad.Mode.COMBAT:
			fighting += 1
	check("spawn point is not spotted in the first seconds", fighting == 0, str(fighting))

	# Walking forward moves the player.
	var start := player.global_position
	bot.frame.move = Vector2(0, 1)
	await wait(1.0)
	bot.frame.move = Vector2.ZERO
	check("player walks", player.global_position.distance_to(start) > 3.0, "%.1fm" % player.global_position.distance_to(start))

	# Stand in the open courtyard: get spotted, get shot, shoot back, get a kill.
	player.global_position = Vector3(0.0, 0.1, 9.0)
	var target: Enemy = null
	var health_before := player.health + player.shield
	var kills := 0
	var combat_seen := false
	var barks := [0]
	var listener := Node.new()
	listener.set_script(load("res://tools/bark_counter.gd"))
	listener.set("counter", barks)
	add_child(listener)
	for step in 500:
		if target == null or target.is_dead:
			target = null
			var best := 1e9
			for e in get_tree().get_nodes_in_group("enemy"):
				var enemy := e as Enemy
				var d := enemy.global_position.distance_to(player.global_position)
				if not enemy.is_dead and d < best and enemy.call("_clear", player.eye_position(), enemy.global_position + Vector3.UP):
					best = d
					target = enemy
		if target != null:
			aim(player, target.global_position + Vector3.UP * 1.2)
			bot.frame.shoot = true
			if target.state == Enemy.State.COMBAT:
				combat_seen = true
		player.health = maxf(player.health, 50.0)
		await get_tree().physics_frame
		await get_tree().physics_frame
		kills = GameManager.raid_kills
		if kills >= 2 and combat_seen and player.health + player.shield < health_before:
			break
	bot.frame.shoot = false
	check("enemies enter combat", combat_seen)
	check("player gets kills", kills >= 1, str(kills))
	check("player takes damage", player.health + player.shield < health_before or player.health == 50.0, "%.0f" % (player.health + player.shield))
	check("squad barks reach hud", barks[0] > 0, str(barks[0]))

	# Loot: drop an item at our feet and take it.
	player.global_position = Vector3(-39.0, 0.1, 30.0)
	await wait(0.3)
	Pickup.drop(raid, "fusion_cap", player.global_position + Vector3(0, 0, -1.2))
	var size_before := GameManager.backpack.size()
	for step in 40:
		aim(player, player.global_position + Vector3(0, 0.35, -1.2))
		bot.frame.interact = true
		await get_tree().physics_frame
	bot.frame.interact = false
	check("pickup into backpack", GameManager.backpack.size() == size_before + 1 and GameManager.backpack.has("fusion_cap"))

	# Armour found with nothing worn goes straight on and raises the shield cap.
	var shield_cap := player.max_shield
	var vest := Pickup.drop(raid, "armor_light", player.global_position + Vector3(0, 0, -1.2))
	vest.interact(player)
	check("found armour is worn", GameManager.loadout["armor"] == "armor_light" and player.max_shield > shield_cap, "%.0f" % player.max_shield)

	# A weapon found with the primary slot empty is equipped and usable at once.
	GameManager.loadout["primary"] = ""
	player.guns.remove_at(0)
	player.gun_index = 0
	var smg := Pickup.drop(raid, "smg", player.global_position + Vector3(0, 0, -1.2))
	smg.interact(player)
	await wait(0.5)
	check("found weapon is equipped", GameManager.loadout["primary"] == "smg" and player.guns.size() == 2 and player.gun().id == "smg")

	# Reinforcements arrive out of sight and head for the trouble.
	var count_before := get_tree().get_nodes_in_group("enemy").size()
	raid.set("_wave_cooldown", 0.0)
	var sent := raid.send_reinforcements(player.global_position)
	await wait(0.3)
	check("reinforcements arrive", sent and get_tree().get_nodes_in_group("enemy").size() > count_before and Squad.all[-1].mode == Squad.Mode.SEARCH,
		"%d -> %d" % [count_before, get_tree().get_nodes_in_group("enemy").size()])

	# Container opens and spills pickups.
	var container: LootContainer = null
	for node in raid.level.get_children():
		if node is LootContainer:
			container = node
			break
	container.interact(player)
	await wait(0.2)
	var pickups := 0
	for node in raid.level.get_children():
		if node is Pickup:
			pickups += 1
	check("container spills loot", container.opened and pickups >= 1, str(pickups))

	# Every ability on every frame runs without error and starts its cooldown.
	for id: String in Catalog.FRAMES:
		player.frame_def = Catalog.FRAMES[id]
		player.health = 50.0
		player.tactical_cooldown = 0.0
		player.prime_cooldown = 0.0
		player.call("_use_ability", player.frame_def["tactical"], InputFrame.new(), true)
		player.call("_use_ability", player.frame_def["prime"], InputFrame.new(), false)
		await wait(0.3)
		check("abilities: " + id, player.tactical_cooldown > 0.0 and player.prime_cooldown > 0.0)
	check("stim heals", player.health > 50.0, "%.0f" % player.health)

	# A grenade at our feet goes off and hurts.
	player.health = player.max_health
	player.shield = player.max_shield
	player.fortify_left = 0.0
	var grenade := Grenade.new()
	raid.add_child(grenade)
	grenade.launch(player.global_position + Vector3(6, 2, 0), player.global_position, null)
	await wait(3.5)
	check("grenade damages", player.health + player.shield < player.max_health + player.max_shield, "%.0f" % (player.health + player.shield))

	# Extraction banks the backpack.
	player.health = player.max_health
	player.global_position = raid.extract_points[1].global_position + Vector3.UP * 0.1
	await wait(8.5)
	check("extraction ends raid", raid.over and GameManager.last_result.get("outcome", "") == "extracted", str(GameManager.last_result.get("outcome", "none")))
	check("result screen shown", raid.hud.get("_overlay") != null)
	check("loot banked in stash", GameManager.stash.has("fusion_cap"))
	# The SMG picked up mid-raid is the primary now, and extracting keeps it.
	check("loadout kept", GameManager.loadout["primary"] == "smg")

	# Settings clamp, persist through a reset, and reach the game.
	GameManager.set_setting("sensitivity", 99.0)
	GameManager.set_setting("quality", 0.0)
	check("settings clamp", is_equal_approx(GameManager.settings["sensitivity"], 3.0))
	check("quality applies", not raid.get("_env").sdfgi_enabled and raid.get("_env").fog_enabled)
	GameManager.reset_profile()
	check("settings survive a reset", is_equal_approx(GameManager.settings["sensitivity"], 3.0))
	GameManager.set_setting("sensitivity", 1.0)
	GameManager.set_setting("quality", 2.0)
	GameManager.loadout["primary"] = "rifle"

	# Death loses the kit.
	GameManager.in_raid = true
	GameManager.backpack.assign(["data_shard"])
	GameManager.raid_failed("died", 10.0)
	check("death clears loadout", GameManager.loadout["primary"] == "" and not GameManager.stash.has("data_shard"))
	print("SELFTEST %s (%d failed)" % ["OK" if _fails == 0 else "FAILED", _fails])
	get_tree().quit(1 if _fails > 0 else 0)
