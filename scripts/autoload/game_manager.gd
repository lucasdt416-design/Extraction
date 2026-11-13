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
# result: {"outcome": "extracted" | "died" | "lost", "items": Array[String], "value": int, "kills": int, "time": float}
signal raid_ended(result: Dictionary)

var SAVE_PATH: String = "user://profile.json"
const MENU_SCENE: String = "res://scenes/menu.tscn"
const RAID_SCENE: String = "res://scenes/raid.tscn"
const BASE_CAPACITY: int = 10
const MAX_MEDKITS: int = 3
const EQUIP_SLOTS: Array[String] = ["primary", "secondary", "armor", "implant_a", "implant_b"]

# --- Saved profile -----------------------------------------------------------
var credits: int = 0
var stash: Array[String] = []
var loadout: Dictionary = {"primary": "", "secondary": "", "armor": "", "implant_a": "", "implant_b": ""}
var frame_id: String = "striker"
var stats: Dictionary = {"raids": 0, "extracted": 0, "kills": 0, "earned": 0}

# --- Raid in progress --------------------------------------------------------
var in_raid: bool = false
var backpack: Array[String] = []
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

# --- Derived player stats ----------------------------------------------------

# What the frame, armor and implants add up to. Read by Player at spawn.
func player_stats() -> Dictionary:
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
		var id: String = loadout[slot]
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

func set_frame(id: String) -> void:
	if Catalog.FRAMES.has(id):
		frame_id = id
		_profile_dirty()

# --- Raid flow ---------------------------------------------------------------

func start_raid() -> void:
	seed_run(randi())
	backpack.clear()
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
	get_tree().change_scene_to_file(RAID_SCENE)

# The one place the backpack grows. False means it was full.
func add_to_backpack(id: String) -> bool:
	if backpack.size() >= capacity():
		return false
	backpack.append(id)
	backpack_changed.emit()
	return true

func take_from_backpack(id: String) -> bool:
	var at := backpack.find(id)
	if at < 0:
		return false
	backpack.remove_at(at)
	backpack_changed.emit()
	return true

func backpack_value() -> int:
	var total := 0
	for id in backpack:
		total += Catalog.sell_price(id)
	return total

func register_kill() -> void:
	raid_kills += 1

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
	in_raid = false
	result["kills"] = raid_kills
	stats["kills"] += raid_kills
	backpack.clear()
	last_result = result
	save_profile()
	profile_changed.emit()
	raid_ended.emit(result)

func return_to_menu() -> void:
	get_tree().paused = false
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
	}, "\t"))

func load_profile() -> void:
	var data: Variant = null
	if FileAccess.file_exists(SAVE_PATH):
		data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not data is Dictionary:
		# First launch: enough to buy one real decision, not a whole kit.
		credits = 1200
		stash.assign(["medkit", "medkit"])
		return
	credits = int(data.get("credits", 0))
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
		"tactical": KEY_Q, "prime": KEY_E, "heal": KEY_H, "weapon_1": KEY_1, "weapon_2": KEY_2, "pause": KEY_ESCAPE,
	}
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
