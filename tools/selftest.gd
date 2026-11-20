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
	GameManager.map_id = "relay_07"   # these checks use Relay Station's coordinates
	GameManager.reset_profile()
	GameManager.credits = 5000
	check("buy rifle", GameManager.buy("rifle") and GameManager.stash.has("rifle"))
	GameManager.equip(GameManager.stash.find("rifle"))
	check("equip rifle", GameManager.loadout["primary"] == "rifle")
	check("attachment slots enforce compatibility",
		not GameManager.set_attachment("sidearm", "stock", "stabilized")
		and not GameManager.set_attachment("rifle", "magazine", "prism"))
	check("armoury saves attachment choices",
		GameManager.set_attachment("rifle", "magazine", "quick")
		and GameManager.set_attachment("rifle", "stock", "stabilized")
		and GameManager.set_attachment("rifle", "barrel", "precision")
		and GameManager.set_attachment("rifle", "sight", "reflex")
		and GameManager.set_attachment("sidearm", "sight", "prism"))
	GameManager.load_profile()
	check("attachment preset round trip", GameManager.weapon_presets.get("rifle", {}) ==
		{"magazine": "quick", "stock": "stabilized", "barrel": "precision", "sight": "reflex"})
	GameManager.select_contract("survey")
	GameManager.load_profile()
	check("contract selection survives a profile reload", GameManager.selected_contract == "survey")
	GameManager.active_contract = GameManager.selected_contract
	GameManager.in_raid = true
	GameManager.backpack.assign(["medkit"])

	var raid: Raid = load("res://scenes/raid.tscn").instantiate()
	add_child(raid)
	await wait(1.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var player := raid.player
	var track_input := InputEventAction.new()
	track_input.action = "track_extract"
	track_input.pressed = true
	raid.hud._input(track_input)
	check("exit tracking selects a waypoint", raid.hud.get("_tracked_exit") == 0)
	for i in raid.extract_points.size():
		raid.hud._input(track_input)
	check("exit tracking cycles back to automatic markers", raid.hud.get("_tracked_exit") == -1)
	var bot := Bot.new()
	player.add_child(bot)
	player.input_source = bot
	var enemies := get_tree().get_nodes_in_group("enemy")
	check("enemies spawned", enemies.size() >= 15, str(enemies.size()))
	check("weapons", player.guns.size() == 2 and player.guns[0].id == "rifle")
	var tuned := player.gun()
	var factory := Gun.new("rifle")
	check("deployed attachments compose without modifying factory stats",
		tuned.mag == 22 and factory.mag == 28 and tuned.def["reload"] < factory.def["reload"]
		and tuned.def["range"] > factory.def["range"] and tuned.def["falloff"][1] > factory.def["falloff"][1]
		and tuned.def["recoil"] < factory.def["recoil"] and tuned.def["aim_speed"] < factory.def["aim_speed"]
		and tuned.def["spread"] < factory.def["spread"] and tuned.def["sight"] == "reflex" and not tuned.has_scope())
	check("issued sidearm brings its selected scope",
		player.guns[1].has_scope() and player.guns[1].def["sight"] == "prism")
	check("raid locks the armoury", not GameManager.set_attachment("sidearm", "sight", ""))
	tuned.mag = 1
	var ammo_before := tuned.mag + tuned.reserve
	check("modified reload respects magazine capacity and conserves ammo",
		tuned.start_reload(true) and tuned.mag == 22 and tuned.mag + tuned.reserve == ammo_before)

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

	# Exercise the live backpack and round-trip a used weapon through the floor.
	var tab := InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	tab.pressed = true
	get_viewport().push_input(tab)
	check("Tab opens the live backpack", raid.hud.get("_inventory") != null and not get_tree().paused)
	get_viewport().push_input(tab)
	check("Tab closes the backpack", raid.hud.get("_inventory") == null)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var used_gun := player.gun()
	used_gun.mag = 3
	used_gun.reserve = 7
	GameManager.add_to_backpack("dmr")
	check("swap primary in raid", player.equip_packed(GameManager.backpack.find("dmr"), "primary")
		and player.gun().id == "dmr" and player.guns.size() == 2)
	check("drop old primary", player.drop_packed(GameManager.backpack.find("smg")) and not GameManager.backpack.has("smg"))
	var dropped: Pickup
	for child in raid.get_children():
		if child is Pickup and child.weapon == used_gun:
			dropped = child
			break
	check("dropped weapon exists in the raid", dropped != null)
	if dropped != null:
		dropped.interact(player)
	check("swap back preserves loaded and reserve ammo",
		player.equip_packed(GameManager.backpack.find("smg"), "primary")
		and player.gun() == used_gun and used_gun.mag == 3 and used_gun.reserve == 7)
	check("equip secondary from pack", player.equip_packed(GameManager.backpack.find("dmr"), "secondary")
		and player.gun().id == "dmr" and player.guns.size() == 2)
	check("stow secondary restores issued sidearm", player.stow_equipped("secondary")
		and player.gun().id == "sidearm" and player.gun().infinite_reserve)
	GameManager.remove_packed(GameManager.backpack.find("dmr"))

	GameManager.add_to_backpack("armor_heavy")
	check("armor swap updates shield cap and stores old vest",
		player.equip_packed(GameManager.backpack.find("armor_heavy"), "armor")
		and player.max_shield == shield_cap + 60 and GameManager.backpack.has("armor_light"))
	GameManager.remove_packed(GameManager.backpack.find("armor_light"))
	GameManager.add_to_backpack("implant_satchel")
	check("satchel grants pack space", player.equip_packed(GameManager.backpack.find("implant_satchel"), "implant_a")
		and GameManager.capacity() == GameManager.BASE_CAPACITY + 4)
	GameManager.add_to_backpack("implant_loader")
	while GameManager.add_to_backpack("copper_spool"):
		pass
	check("capacity loss rejects an overflowing swap",
		not player.equip_packed(GameManager.backpack.find("implant_loader"), "implant_a")
		and GameManager.loadout["implant_a"] == "implant_satchel")
	while GameManager.backpack.has("copper_spool"):
		GameManager.remove_packed(GameManager.backpack.find("copper_spool"))
	check("implant swap updates all reload multipliers",
		player.equip_packed(GameManager.backpack.find("implant_loader"), "implant_a")
		and is_equal_approx(player.guns[0].reload_mult, 0.8) and is_equal_approx(player.guns[1].reload_mult, 0.8))
	GameManager.remove_packed(GameManager.backpack.find("implant_satchel"))

	GameManager.add_to_backpack("medkit")
	player.health = 50.0
	player.heal_left = 0.0
	var med_count := GameManager.backpack.count("medkit")
	check("backpack medkit uses the normal healing channel", player.use_medkit(GameManager.backpack.find("medkit"))
		and player.heal_is_medkit and GameManager.backpack.count("medkit") == med_count - 1)
	await wait(0.18)
	check("backpack medkit restores health over time", player.health > 50.0)
	player.heal_left = 0.0

	await _check_aircraft(raid, player, bot)

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
	check("opening a case advances the survey once", GameManager.contract_progress() == 1)
	container.interact(player)
	check("reopening a case cannot double count", GameManager.contract_progress() == 1)
	for node in raid.level.get_children():
		if node is LootContainer and not node.opened:
			node.interact(player)
			if GameManager.contract_progress() == 3:
				break

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
	var credits_before := GameManager.credits
	player.health = player.max_health
	player.global_position = raid.extract_points[1].global_position + Vector3.UP * 0.1
	await wait(8.5)
	check("extraction ends raid", raid.over and GameManager.last_result.get("outcome", "") == "extracted", str(GameManager.last_result.get("outcome", "none")))
	check("result screen shown", raid.hud.get("_overlay") != null)
	check("loot banked in stash", GameManager.stash.has("fusion_cap"))
	check("completed contract pays on extraction", GameManager.credits == credits_before + 300
		and GameManager.last_result.get("contract", {}).get("paid") == 300 and GameManager.active_contract.is_empty())
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
	GameManager.active_contract = "recovery"
	GameManager.backpack.assign(["data_shard", "copper_spool", "coolant_cell"])
	credits_before = GameManager.credits
	GameManager.raid_failed("died", 10.0)
	check("death clears loadout", GameManager.loadout["primary"] == "" and not GameManager.stash.has("data_shard"))
	check("contract progress is forfeited on death", GameManager.credits == credits_before
		and GameManager.last_result.get("contract", {}).get("paid") == 0)
	print("SELFTEST %s (%d failed)" % ["OK" if _fails == 0 else "FAILED", _fails])
	get_tree().quit(1 if _fails > 0 else 0)

func _check_aircraft(raid: Raid, player: Player, bot: Bot) -> void:
	# The aircraft reaches its station before the squad dismounts.
	var count_before := get_tree().get_nodes_in_group("enemy").size()
	raid.set("_wave_cooldown", 0.0)
	var sent := raid.send_reinforcements(player.global_position)
	var helicopter := get_tree().get_first_node_in_group("reinforcement_aircraft") as Node3D
	check("armed helicopter approaches before spawning its squad",
		sent and helicopter != null and helicopter.helicopter and not helicopter.lands
		and helicopter.global_position.y > helicopter.station.y + 30.0
		and get_tree().get_nodes_in_group("enemy").size() == count_before)
	if helicopter != null:
		helicopter.set("_age", 8.85)
		await wait(2.45)
		var squad := Squad.all[-1]
		check("helicopter fast-ropes a squad that can fight",
			get_tree().get_nodes_in_group("enemy").size() == count_before + 2
			and squad.living().size() == 2 and squad.living()[1].is_physics_processing())
		var cannons := get_tree().get_nodes_in_group("aircraft_weapon")
		check("helicopter mounts two cannons", cannons.size() == 2)
		if cannons.size() == 2:
			var cannon := cannons[0] as Node3D
			var thrower_position := player.global_position
			var origin: Vector3 = cannon.global_position + cannon.global_basis.x * cannon.side * 3.0
			var charge := Grenade.new()
			raid.add_child(charge)
			charge.launch_charge(origin, origin.direction_to(cannon.global_position), player)
			await wait(0.35)
			check("breach grenade disables one armored cannon", not cannon.is_in_group("aircraft_weapon")
				and cannons[1].is_in_group("aircraft_weapon") and player.global_position.distance_to(thrower_position) < 3.0)
		if squad.living().size() == 2:
			var target := squad.living()[0]
			var charge := Grenade.new()
			raid.add_child(charge)
			charge.launch_charge(target.global_position + Vector3.UP * 3.0, Vector3.DOWN, player)
			await wait(0.95)
			check("breach grenade kills infantry", target.is_dead)
		helicopter.set("_age", 60.0)
		await wait(0.1)
		check("helicopter flies out and is removed", not is_instance_valid(helicopter))
	raid.set("_wave_cooldown", 0.0)
	count_before = get_tree().get_nodes_in_group("enemy").size()
	sent = raid.send_reinforcements(player.global_position)
	var dropship := get_tree().get_first_node_in_group("reinforcement_aircraft") as Node3D
	check("dropship approaches unarmed", sent and dropship != null and not dropship.helicopter
		and get_tree().get_nodes_in_group("aircraft_weapon").is_empty())
	if dropship != null:
		dropship.set("_age", 8.85)
		await wait(2.85)
		check("dropship lands and unloads infantry", dropship.lands
			and is_equal_approx(dropship.global_position.y, dropship.station.y + 0.08)
			and get_tree().get_nodes_in_group("enemy").size() == count_before + 4)
		dropship.set("_age", 60.0)
	await wait(0.1)
	var grenades_before := player.grenades
	bot.frame.grenade = true
	await wait(0.1)
	check("grenade input spends one issued charge", player.grenades == grenades_before - 1)
