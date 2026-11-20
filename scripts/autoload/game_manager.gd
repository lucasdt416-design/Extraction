extends Node

# The one owner of everything that outlives a single scene: the saved profile
# (credits, stash, loadout), the state of the raid in progress (backpack), the
# seeded random stream, and the flow between menu and raid.
#
# Rule 2: every change to credits, stash, loadout or backpack goes through a
# function in this file. UI and gameplay call these; they never edit the
# dictionaries themselves.

signal profile_changed
signal backpack_changed
signal settings_changed
# result: {"outcome": "extracted" | "died" | "lost", "items": Array[String], "value": int, "kills": int, "time": float}
signal raid_ended(result: Dictionary)

var SAVE_PATH: String = "user://profile.json"
const MENU_SCENE: String = "res://scenes/menu.tscn"
const RAID_SCENE: String = "res://scenes/raid.tscn"
const BASE_CAPACITY: int = 10
const MAX_MEDKITS: int = 3
const SLOT_LABELS := {"primary": "Primary", "secondary": "Secondary", "armor": "Armor",
	"implant_a": "Implant A", "implant_b": "Implant B"}
const SLOT_KINDS := {"primary": "weapon", "secondary": "weapon", "armor": "armor",
	"implant_a": "implant", "implant_b": "implant"}
const EQUIP_SLOTS: Array[String] = ["primary", "secondary", "armor", "implant_a", "implant_b"]

# --- Saved profile -----------------------------------------------------------
var credits: int = 0
var stash: Array[String] = []
var weapon_presets: Dictionary = {}
var selected_contract := ""
var active_contract := ""
var _containers_searched := 0
var loadout: Dictionary = {"primary": "", "secondary": "", "armor": "", "implant_a": "", "implant_b": ""}
var frame_id: String = "striker"
var map_id: String = "aster_city"
var stats: Dictionary = {"raids": 0, "extracted": 0, "kills": 0, "earned": 0}

# --- Settings ---------------------------------------------------------------
# Player preferences. Saved with the profile but never lost on death or reset.
# quality: 0 = low, 1 = medium, 2 = high (see Raid.apply_quality).
const SETTING_RANGES: Dictionary = {
	"sensitivity": [0.2, 3.0, 0.1], "fov": [65.0, 110.0, 1.0], "volume": [0.0, 1.0, 0.05], "quality": [0.0, 2.0, 1.0],
	"fullscreen": [0.0, 1.0, 1.0], "window": [0.0, 4.0, 1.0], "scale": [0.5, 1.0, 0.05],
}
# window: an index into WINDOW_SIZES, used when not fullscreen.
# scale: the fraction of the window's pixels the 3D view is rendered at.
const WINDOW_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3200, 1800)]
const DISPLAY_SETTINGS: Array[String] = ["fullscreen", "window", "scale"]
var settings: Dictionary = {"sensitivity": 1.0, "fov": 82.0, "volume": 0.8, "quality": 2.0, "fullscreen": 1.0, "window": 1.0, "scale": 1.0}

# --- Raid in progress --------------------------------------------------------
var in_raid: bool = false
var backpack: Array[String] = []
# Only weapons that have already been used need an entry here. Keys follow
# backpack indices so two copies of the same gun retain their individual ammo.
var _packed_guns: Dictionary = {}
var raid_kills: int = 0
var last_result: Dictionary = {}

# --- Seeded randomness (rule 4) ----------------------------------------------
# Loot rolls, spread, AI decisions: all derive from this. Systems that need
# their own stream seed it from rng.randi() once, at spawn.
var run_seed: int = 0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bind_inputs()
	# Automated checks run against a throwaway profile, never the real save.
	if OS.get_cmdline_user_args().has("--test-profile"):
		SAVE_PATH = "user://profile_test.json"
	load_profile()
	seed_run(0)

func seed_run(new_seed: int) -> void:
	run_seed = new_seed
	rng.seed = run_seed

# The one place a setting changes. Clamped to its range, saved, announced.
func set_setting(key: String, value: float) -> void:
	if not SETTING_RANGES.has(key):
		return
	var limits: Array = SETTING_RANGES[key]
	settings[key] = clampf(snappedf(value, limits[2]), limits[0], limits[1])
	_apply_volume()
	if key in DISPLAY_SETTINGS:
		_apply_display()
	save_profile()
	settings_changed.emit()

# Fullscreen or a window of the chosen size, and the 3D render scale. Tools and
# headless runs keep whatever window they were launched with.
func _apply_display() -> void:
	if DisplayServer.get_name() == "headless" or OS.get_cmdline_user_args().has("--test-profile"):
		return
	var window := get_window()
	var full: bool = settings["fullscreen"] >= 0.5
	var mode := Window.MODE_FULLSCREEN if full else Window.MODE_WINDOWED
	if window.mode != mode:
		window.mode = mode
	if not full:
		var size := WINDOW_SIZES[int(settings["window"])]
		var room := DisplayServer.screen_get_usable_rect(window.current_screen).size
		size = Vector2i(mini(size.x, room.x), mini(size.y, room.y))
		if window.size != size:
			window.size = size
			window.move_to_center()
	get_tree().root.scaling_3d_scale = settings["scale"]

func _apply_volume() -> void:
	var volume: float = settings["volume"]
	AudioServer.set_bus_mute(0, volume <= 0.001)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.001)))

# --- Derived player stats ----------------------------------------------------

# What the frame, armor and implants add up to. Read by Player at spawn.
func player_stats(kit: Dictionary = {}) -> Dictionary:
	if kit.is_empty():
		kit = loadout
	var frame: Dictionary = Catalog.FRAMES[frame_id]
	var out := {
		"health": 100.0 + float(frame.get("health", 0)),
		"shield": 40.0 + float(frame.get("shield", 0)),
		"speed": 1.0, "reload": 1.0,
		"noise": 1.0 + float(frame.get("noise", 0.0)),
		"capacity": BASE_CAPACITY,
		"regen_delay": 4.5 + float(frame.get("regen_delay", 0.0)),
		"med_speed": float(frame.get("med_speed", 1.0)),
		"stealth": float(frame.get("stealth", 1.0)),
	}
	for slot: String in ["armor", "implant_a", "implant_b"]:
		var id: String = kit[slot]
		if id == "":
			continue
		var it := Catalog.item(id)
		out["shield"] += float(it.get("shield", 0))
		out["speed"] += float(it.get("speed", 0.0))
		out["reload"] += float(it.get("reload", 0.0))
		out["noise"] += float(it.get("noise", 0.0))
		out["capacity"] += int(it.get("capacity", 0))
	out["noise"] = maxf(out["noise"], 0.15)
	return out

func capacity() -> int:
	return player_stats()["capacity"]

# The weapons going into the raid. An empty secondary always becomes the free
# sidearm, so a wiped player can still deploy.
func raid_weapons() -> Array[String]:
	var out: Array[String] = []
	if loadout["primary"] != "":
		out.append(loadout["primary"])
	out.append(loadout["secondary"] if loadout["secondary"] != "" else "sidearm")
	return out

func set_attachment(weapon_id: String, slot: String, part_id: String) -> bool:
	if in_raid or not Catalog.attachment_slots(weapon_id).has(slot):
		return false
	if part_id != "" and not Catalog.ATTACHMENTS[slot].has(part_id):
		return false
	var parts: Dictionary = weapon_presets.get(weapon_id, {}).duplicate()
	if parts.get(slot, "") == part_id:
		return true
	if part_id.is_empty():
		parts.erase(slot)
	else:
		parts[slot] = part_id
	if parts.is_empty():
		weapon_presets.erase(weapon_id)
	else:
		weapon_presets[weapon_id] = parts
	save_profile()
	return true

func medkits_in_stash() -> int:
	return stash.count("medkit")

# --- Profile mutations (menu) ------------------------------------------------

func buy(id: String) -> bool:
	var price: int = Catalog.item(id)["value"]
	if credits < price:
		return false
	credits -= price
	stash.append(id)
	_profile_dirty()
	return true

func sell(stash_index: int) -> void:
	if stash_index < 0 or stash_index >= stash.size():
		return
	credits += Catalog.sell_price(stash[stash_index])
	stash.remove_at(stash_index)
	_profile_dirty()

func sell_all_salvage() -> int:
	var total := 0
	for i in range(stash.size() - 1, -1, -1):
		if Catalog.item(stash[i])["kind"] == "loot":
			total += Catalog.sell_price(stash[i])
			stash.remove_at(i)
	credits += total
	_profile_dirty()
	return total

# Moves a stash item into the first slot that takes its kind, sending whatever
# was there back to the stash.
func equip(stash_index: int, slot: String = "") -> void:
	if stash_index < 0 or stash_index >= stash.size():
		return
	var id := stash[stash_index]
	var kind: String = Catalog.item(id)["kind"]
	if slot == "":
		match kind:
			"weapon": slot = "primary" if loadout["primary"] == "" or loadout["secondary"] != "" else "secondary"
			"armor": slot = "armor"
			"implant": slot = "implant_a" if loadout["implant_a"] == "" or loadout["implant_b"] != "" else "implant_b"
			_: return
	stash.remove_at(stash_index)
	if loadout[slot] != "":
		stash.append(loadout[slot])
	loadout[slot] = id
	_profile_dirty()

func unequip(slot: String) -> void:
	if loadout.get(slot, "") == "":
		return
	stash.append(loadout[slot])
	loadout[slot] = ""
	_profile_dirty()

func set_map(id: String) -> void:
	if Catalog.MAPS.has(id):
		map_id = id
		profile_changed.emit()

func set_frame(id: String) -> void:
	if Catalog.FRAMES.has(id):
		frame_id = id
		_profile_dirty()

# --- Raid flow ---------------------------------------------------------------

func start_raid() -> void:
	seed_run(randi())
	active_contract = selected_contract
	_containers_searched = 0
	backpack.clear()
	_packed_guns.clear()
	# Up to three medkits ride along. They leave the stash now: they're at risk.
	for i in MAX_MEDKITS:
		var at := stash.find("medkit")
		if at < 0:
			break
		stash.remove_at(at)
		backpack.append("medkit")
	raid_kills = 0
	in_raid = true
	stats["raids"] += 1
	save_profile()
	get_tree().paused = false
	get_tree().change_scene_to_file(Catalog.MAPS[map_id]["scene"])

# The one place the backpack grows. False means it was full.
func add_to_backpack(id: String, weapon: Gun = null) -> bool:
	if backpack.size() >= capacity():
		return false
	if weapon != null:
		_packed_guns[backpack.size()] = weapon
	backpack.append(id)
	backpack_changed.emit()
	return true

# Armour found mid-raid goes straight on if nothing is being worn. Worn kit
# takes no backpack slot and comes home with you if you extract.
func wear_found(id: String) -> bool:
	if not in_raid or Catalog.item(id)["kind"] != "armor" or loadout["armor"] != "":
		return false
	loadout["armor"] = id
	backpack_changed.emit()
	return true

# A weapon found mid-raid fills the primary slot if it is empty.
func wield_found(id: String) -> bool:
	if not in_raid or Catalog.item(id)["kind"] != "weapon" or loadout["primary"] != "":
		return false
	loadout["primary"] = id
	backpack_changed.emit()
	return true

func packed_gun(index: int) -> Gun:
	return _packed_guns.get(index)

func remove_packed(index: int) -> String:
	if not in_raid or index < 0 or index >= backpack.size():
		return ""
	var id := _remove_packed(index)
	backpack_changed.emit()
	return id

func _remove_packed(index: int) -> String:
	var id := backpack[index]
	backpack.remove_at(index)
	_packed_guns.erase(index)
	for i in range(index + 1, backpack.size() + 1):
		if _packed_guns.has(i):
			_packed_guns[i - 1] = _packed_guns[i]
			_packed_guns.erase(i)
	return id

# Validates the complete resulting kit before either item moves.
func swap_packed(index: int, slot: String, outgoing: Gun = null) -> bool:
	if not in_raid or index < 0 or index >= backpack.size():
		return false
	var incoming := backpack[index]
	if Catalog.item(incoming)["kind"] != SLOT_KINDS.get(slot):
		return false
	var previous: String = loadout[slot]
	var next_kit := loadout.duplicate()
	next_kit[slot] = incoming
	if backpack.size() - int(previous.is_empty()) > int(player_stats(next_kit)["capacity"]):
		return false
	loadout[slot] = incoming
	if previous.is_empty():
		_remove_packed(index)
	else:
		backpack[index] = previous
		_packed_guns.erase(index)
		if outgoing != null:
			_packed_guns[index] = outgoing
	backpack_changed.emit()
	return true

func stow_equipped(slot: String, weapon: Gun = null) -> bool:
	var id: String = loadout.get(slot, "")
	if not in_raid or id.is_empty():
		return false
	var next_kit := loadout.duplicate()
	next_kit[slot] = ""
	if backpack.size() + 1 > int(player_stats(next_kit)["capacity"]):
		return false
	loadout[slot] = ""
	return add_to_backpack(id, weapon)

func backpack_value() -> int:
	var total := 0
	for id in backpack:
		total += Catalog.sell_price(id)
	return total

func register_kill() -> void:
	raid_kills += 1

func select_contract(id: String) -> void:
	if in_raid or (not id.is_empty() and not Catalog.CONTRACTS.has(id)):
		return
	selected_contract = id
	_profile_dirty()

func register_container_search() -> void:
	if in_raid:
		_containers_searched += 1

func contract_progress() -> int:
	match active_contract:
		"survey": return _containers_searched
		"security": return raid_kills
		"recovery":
			var carried := 0
			for id in backpack:
				if Catalog.item(id)["kind"] == "loot":
					carried += 1
			return carried
	return 0

func extract_success(time: float) -> void:
	if not in_raid:
		return
	var items := backpack.duplicate()
	var value := backpack_value()
	stash.append_array(backpack)
	stats["extracted"] += 1
	stats["earned"] += value
	_finish({"outcome": "extracted", "items": items, "value": value, "time": time})

# Death, or the raid clock running out: the backpack and everything equipped is
# gone. That loss is the whole point of the genre.
func raid_failed(outcome: String, time: float) -> void:
	if not in_raid:
		return
	var lost := backpack.duplicate()
	for slot in EQUIP_SLOTS:
		if loadout[slot] != "":
			lost.append(loadout[slot])
			loadout[slot] = ""
	_finish({"outcome": outcome, "items": lost, "value": 0, "time": time})

func _finish(result: Dictionary) -> void:
	if Catalog.CONTRACTS.has(active_contract):
		var contract: Dictionary = Catalog.CONTRACTS[active_contract]
		var progress := contract_progress()
		var paid: int = contract["reward"] if result["outcome"] == "extracted" and progress >= contract["target"] else 0
		credits += paid
		stats["earned"] += paid
		result["contract"] = {"name": contract["name"], "progress": progress, "target": contract["target"], "paid": paid}
	active_contract = ""
	_containers_searched = 0
	in_raid = false
	result["kills"] = raid_kills
	stats["kills"] += raid_kills
	backpack.clear()
	_packed_guns.clear()
	last_result = result
	save_profile()
	profile_changed.emit()
	raid_ended.emit(result)

func return_to_menu() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	Sfx.stop_ambience()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().change_scene_to_file(MENU_SCENE)

# --- Persistence -------------------------------------------------------------

func _profile_dirty() -> void:
	save_profile()
	profile_changed.emit()

func save_profile() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Could not write %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify({
		"version": 1, "credits": credits, "stash": stash, "loadout": loadout, "frame": frame_id, "stats": stats,
		"settings": settings, "weapon_presets": weapon_presets, "contract": selected_contract,
	}, "\t"))

func load_profile() -> void:
	weapon_presets.clear()
	selected_contract = ""
	var data: Variant = null
	if FileAccess.file_exists(SAVE_PATH):
		data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if data is Dictionary:
		for key: String in settings:
			var saved: Variant = data.get("settings", {}).get(key)
			if saved is float or saved is int:
				var limits: Array = SETTING_RANGES[key]
				settings[key] = clampf(float(saved), limits[0], limits[1])
	_apply_volume()
	_apply_display.call_deferred()
	if not data is Dictionary:
		# First launch: enough to buy one real decision, not a whole kit.
		credits = 1200
		stash.assign(["medkit", "medkit"])
		return
	var saved_presets: Variant = data.get("weapon_presets")
	if saved_presets is Dictionary:
		for id: String in Catalog.WEAPONS:
			var parts := Catalog.weapon_attachments(id, saved_presets.get(id))
			if not parts.is_empty():
				weapon_presets[id] = parts
	credits = int(data.get("credits", 0))
	var saved_contract: Variant = data.get("contract")
	if saved_contract is String and Catalog.CONTRACTS.has(saved_contract):
		selected_contract = saved_contract
	stash.clear()
	for id: Variant in data.get("stash", []):
		if Catalog.ITEMS.has(id):
			stash.append(id)
	var saved_loadout: Dictionary = data.get("loadout", {})
	for slot in EQUIP_SLOTS:
		var id: String = saved_loadout.get(slot, "")
		loadout[slot] = id if Catalog.ITEMS.has(id) else ""
	frame_id = data.get("frame", "striker") if Catalog.FRAMES.has(data.get("frame", "")) else "striker"
	for key: String in stats:
		stats[key] = int(data.get("stats", {}).get(key, 0))

func reset_profile() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	stash.clear()
	for slot in EQUIP_SLOTS:
		loadout[slot] = ""
	frame_id = "striker"
	for key: String in stats:
		stats[key] = 0
	load_profile()
	_profile_dirty()

# --- Input map ---------------------------------------------------------------
# Registered in code so the bindings live in one readable table instead of in
# project.godot's serialized event blobs. This only names the actions; reading
# them is PlayerInputSource's job and nobody else's (rule 1).

func _bind_inputs() -> void:
	var keys := {
		"move_forward": KEY_W, "move_back": KEY_S, "move_left": KEY_A, "move_right": KEY_D,
		"jump": KEY_SPACE, "sprint": KEY_SHIFT, "crouch": KEY_CTRL, "reload": KEY_R, "interact": KEY_F,
		"tactical": KEY_Q, "prime": KEY_E, "heal": KEY_H, "weapon_1": KEY_1, "weapon_2": KEY_2, "pause": KEY_ESCAPE, "inventory": KEY_TAB,
		"grenade": KEY_G,
		"track_extract": KEY_B,
	}
	if OS.is_debug_build():
		keys["dev_console"] = KEY_QUOTELEFT
	for action: String in keys:
		_add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = keys[action]
		InputMap.action_add_event(action, event)
	var alt := InputEventKey.new()
	alt.physical_keycode = KEY_C
	InputMap.action_add_event("crouch", alt)
	for pair: Array in [["shoot", MOUSE_BUTTON_LEFT], ["aim", MOUSE_BUTTON_RIGHT], ["weapon_next", MOUSE_BUTTON_WHEEL_DOWN], ["weapon_next", MOUSE_BUTTON_WHEEL_UP]]:
		_add_action(pair[0])
		var click := InputEventMouseButton.new()
		click.button_index = pair[1]
		InputMap.action_add_event(pair[0], click)

func _add_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
