class_name Catalog
extends RefCounted

# Every tunable definition in the game lives here as plain data: items, weapons,
# frames (player classes) and enemy archetypes. Nothing in this file acts; the
# systems that own state read from it. Saves store item ids, never copies of
# these dictionaries, so rebalancing a number never needs a save migration.

const RARITY_NAMES: Array[String] = ["Common", "Uncommon", "Rare", "Prototype"]
const RARITY_COLORS: Array[Color] = [
	Color(0.78, 0.80, 0.82), Color(0.35, 0.78, 0.62), Color(0.36, 0.62, 1.0), Color(1.0, 0.42, 0.30),
]

# kind: loot | med | weapon | armor | implant
const ITEMS: Dictionary = {
	# --- Salvage: exists to be carried out and sold ---
	"copper_spool": {"name": "Copper spool", "kind": "loot", "value": 60, "rarity": 0},
	"coolant_cell": {"name": "Coolant cell", "kind": "loot", "value": 90, "rarity": 0},
	"servo_motor": {"name": "Servo motor", "kind": "loot", "value": 130, "rarity": 0},
	"optic_lens": {"name": "Optic lens", "kind": "loot", "value": 210, "rarity": 1},
	"data_shard": {"name": "Data shard", "kind": "loot", "value": 320, "rarity": 1},
	"fusion_cap": {"name": "Fusion capacitor", "kind": "loot", "value": 540, "rarity": 2},
	"encrypted_drive": {"name": "Encrypted drive", "kind": "loot", "value": 820, "rarity": 2},
	"prototype_core": {"name": "Prototype core", "kind": "loot", "value": 2400, "rarity": 3},
	# --- Consumable ---
	"medkit": {"name": "Medkit", "kind": "med", "value": 120, "rarity": 0, "heal": 60,
		"desc": "Restores 60 health over two seconds. Up to three come with you."},
	# --- Weapons ---
	"sidearm": {"name": "P9 Sidearm", "kind": "weapon", "value": 0, "rarity": 0,
		"desc": "Standard issue. Always replaced if you lose it."},
	"smg": {"name": "Vesper SMG", "kind": "weapon", "value": 900, "rarity": 1,
		"desc": "Fast and loose. Best inside a room."},
	"rifle": {"name": "Kestrel Rifle", "kind": "weapon", "value": 1500, "rarity": 1,
		"desc": "Controllable automatic fire at any sensible range."},
	"shotgun": {"name": "Maul Shotgun", "kind": "weapon", "value": 1200, "rarity": 1,
		"desc": "Nine pellets. Decides arguments in doorways."},
	"dmr": {"name": "Longwatch DMR", "kind": "weapon", "value": 2100, "rarity": 2,
		"desc": "Heavy single shots. Rewards a steady head-level aim."},
	# --- Armor: adds shield ---
	"armor_light": {"name": "Mesh vest", "kind": "armor", "value": 700, "rarity": 1, "shield": 25,
		"desc": "+25 shield."},
	"armor_heavy": {"name": "Plate carrier", "kind": "armor", "value": 1800, "rarity": 2, "shield": 60, "speed": -0.06,
		"desc": "+60 shield, 6% slower."},
	# --- Implants: two slots, small permanent edges for as long as you survive ---
	"implant_servo": {"name": "Servo implant", "kind": "implant", "value": 1100, "rarity": 2, "speed": 0.08,
		"desc": "8% faster movement."},
	"implant_capacitor": {"name": "Capacitor implant", "kind": "implant", "value": 1100, "rarity": 2, "shield": 25,
		"desc": "+25 shield."},
	"implant_loader": {"name": "Loader implant", "kind": "implant", "value": 950, "rarity": 2, "reload": -0.2,
		"desc": "20% faster reloads."},
	"implant_damper": {"name": "Damper implant", "kind": "implant", "value": 950, "rarity": 2, "noise": -0.4,
		"desc": "Footsteps and shots carry 40% less far."},
	"implant_satchel": {"name": "Satchel implant", "kind": "implant", "value": 800, "rarity": 1, "capacity": 4,
		"desc": "+4 backpack slots."},
}

# damage is per pellet. spread is degrees at the hip; ads multiplies it.
# falloff: [full-damage range, zero-bonus range] in metres; past the second the
# shot does min_falloff of its damage.
const WEAPONS: Dictionary = {
	"sidearm": {"damage": 24.0, "rpm": 330.0, "mag": 12, "reload": 1.3, "spread": 1.4, "ads": 0.35, "pellets": 1,
		"recoil": 1.5, "range": 120.0, "falloff": [18.0, 40.0], "auto": false, "ads_fov": 62.0, "length": 0.26, "noise": 34.0},
	"smg": {"damage": 15.0, "rpm": 820.0, "mag": 32, "reload": 1.7, "spread": 2.6, "ads": 0.5, "pellets": 1,
		"recoil": 0.85, "range": 120.0, "falloff": [14.0, 34.0], "auto": true, "ads_fov": 64.0, "length": 0.42, "noise": 38.0},
	"rifle": {"damage": 25.0, "rpm": 570.0, "mag": 28, "reload": 2.1, "spread": 1.6, "ads": 0.22, "pellets": 1,
		"recoil": 1.15, "range": 200.0, "falloff": [32.0, 70.0], "auto": true, "ads_fov": 54.0, "length": 0.62, "noise": 46.0},
	"shotgun": {"damage": 12.0, "rpm": 75.0, "mag": 6, "reload": 2.6, "spread": 5.5, "ads": 0.75, "pellets": 9,
		"recoil": 4.5, "range": 60.0, "falloff": [7.0, 20.0], "auto": false, "ads_fov": 64.0, "length": 0.58, "noise": 52.0},
	"dmr": {"damage": 62.0, "rpm": 190.0, "mag": 10, "reload": 2.4, "spread": 2.2, "ads": 0.05, "pellets": 1,
		"recoil": 3.2, "range": 300.0, "falloff": [60.0, 120.0], "auto": false, "ads_fov": 36.0, "length": 0.78, "noise": 54.0},
}
const MIN_FALLOFF: float = 0.45
const HEADSHOT_MULT: float = 1.75

# Raid maps. One today; the Play page lists whatever is here, so a new map is a
# new entry plus its level. `scene` is what GameManager loads.
const MAPS: Dictionary = {
	"relay_07": {"name": "Relay Station 07", "title": "RELAY\nSTATION 07", "mark": "07", "scene": "res://scenes/raid.tscn",
		"minutes": 12, "exits": 2, "brief": "Twelve minutes before the station locks down. Two ways out. Squads hold every building."},
}

# Player classes. Each has a passive, a tactical (short cooldown) and a prime
# (long cooldown). The ability ids are resolved in player.gd.
const FRAMES: Dictionary = {
	"striker": {"name": "Striker", "role": "Assault",
		"passive": "+20 shield, and shield starts recharging sooner.",
		"tactical": {"id": "dash", "name": "Dash", "cooldown": 6.0, "desc": "A hard burst of speed in the direction you're moving."},
		"prime": {"id": "overcharge", "name": "Overcharge", "cooldown": 55.0, "duration": 8.0, "desc": "Refills shield. For 8 seconds you fire 25% faster and reload instantly."},
		"shield": 20, "regen_delay": -1.2, "accent": Color(1.0, 0.45, 0.25)},
	"wraith": {"name": "Wraith", "role": "Infiltrator",
		"passive": "Half the noise. Crouched, you are much harder to spot.",
		"tactical": {"id": "cloak", "name": "Cloak", "cooldown": 18.0, "duration": 6.0, "desc": "Six seconds unseen beyond arm's reach. Firing ends it."},
		"prime": {"id": "pulse", "name": "Pulse", "cooldown": 45.0, "duration": 9.0, "desc": "Marks every hostile within 45 metres through walls."},
		"noise": -0.5, "stealth": 0.5, "accent": Color(0.45, 0.75, 1.0)},
	"mender": {"name": "Mender", "role": "Survivor",
		"passive": "+20 health. Medkits work twice as fast.",
		"tactical": {"id": "stim", "name": "Stim", "cooldown": 20.0, "duration": 3.0, "desc": "Restores 40 health over three seconds without a medkit."},
		"prime": {"id": "fortify", "name": "Fortify", "cooldown": 60.0, "duration": 8.0, "desc": "Halves all damage taken for eight seconds."},
		"health": 20, "med_speed": 2.0, "accent": Color(0.4, 0.9, 0.6)},
}

# Enemy archetypes. `weapon` reuses a player weapon's handling with these
# overrides, so both sides shoot by the same rules (damage scaled for fairness).
#   range        preferred fighting distance
#   aggression   0..1, how readily it pushes instead of holding cover
#   reaction     seconds between seeing you and the first trigger pull
#   accuracy     degrees of aim error once settled; it starts triple that
const ENEMIES: Dictionary = {
	"trooper": {"name": "Trooper", "health": 90.0, "speed": 3.6, "weapon": "rifle", "damage": 7.0, "burst": [3, 5],
		"range": 16.0, "aggression": 0.45, "reaction": 0.55, "accuracy": 2.6, "scale": 1.0,
		"color": Color(0.30, 0.33, 0.38), "accent": Color(1.0, 0.36, 0.22), "loot": 0.55},
	"rusher": {"name": "Stalker", "health": 70.0, "speed": 5.2, "weapon": "shotgun", "damage": 5.5, "burst": [1, 2],
		"range": 6.0, "aggression": 0.95, "reaction": 0.4, "accuracy": 3.5, "scale": 0.94, "cloak": true,
		"color": Color(0.16, 0.18, 0.22), "accent": Color(0.65, 0.4, 1.0), "loot": 0.6},
	"bulwark": {"name": "Bulwark", "health": 220.0, "speed": 2.5, "weapon": "smg", "damage": 5.0, "burst": [6, 10],
		"range": 11.0, "aggression": 0.7, "reaction": 0.7, "accuracy": 3.8, "scale": 1.14, "shield": true,
		"color": Color(0.36, 0.34, 0.30), "accent": Color(1.0, 0.72, 0.2), "loot": 0.85},
	"marksman": {"name": "Marksman", "health": 70.0, "speed": 3.2, "weapon": "dmr", "damage": 34.0, "burst": [1, 1],
		"range": 30.0, "aggression": 0.1, "reaction": 1.25, "accuracy": 0.7, "scale": 1.0, "laser": true,
		"color": Color(0.26, 0.31, 0.30), "accent": Color(1.0, 0.15, 0.2), "loot": 0.7},
	"lobber": {"name": "Grenadier", "health": 110.0, "speed": 3.2, "weapon": "smg", "damage": 5.0, "burst": [4, 6],
		"range": 18.0, "aggression": 0.3, "reaction": 0.6, "accuracy": 3.4, "scale": 1.04, "grenades": true,
		"color": Color(0.33, 0.30, 0.27), "accent": Color(0.55, 1.0, 0.3), "loot": 0.7},
	"overseer": {"name": "Overseer", "health": 380.0, "speed": 3.4, "weapon": "rifle", "damage": 9.0, "burst": [5, 8],
		"range": 14.0, "aggression": 0.6, "reaction": 0.4, "accuracy": 2.0, "scale": 1.24, "commander": true, "grenades": true,
		"color": Color(0.12, 0.13, 0.15), "accent": Color(1.0, 0.9, 0.75), "loot": 1.0},
}

# What a container or a body can hold: [item id, weight]. Rolled from the raid's
# seeded stream by Loot.roll.
const LOOT_TABLES: Dictionary = {
	"crate": [["copper_spool", 30], ["coolant_cell", 26], ["servo_motor", 20], ["optic_lens", 12], ["data_shard", 8], ["medkit", 10], ["fusion_cap", 3]],
	"locker": [["medkit", 30], ["servo_motor", 14], ["optic_lens", 16], ["data_shard", 14], ["armor_light", 4], ["implant_satchel", 3], ["smg", 3]],
	"vault": [["fusion_cap", 28], ["encrypted_drive", 24], ["data_shard", 18], ["prototype_core", 6], ["implant_servo", 5], ["implant_capacitor", 5],
		["implant_loader", 5], ["implant_damper", 5], ["rifle", 4], ["dmr", 3], ["armor_heavy", 3]],
	"body": [["copper_spool", 22], ["coolant_cell", 20], ["servo_motor", 16], ["medkit", 14], ["optic_lens", 8], ["data_shard", 5]],
	"elite": [["encrypted_drive", 30], ["fusion_cap", 30], ["prototype_core", 10], ["implant_capacitor", 8], ["implant_servo", 8], ["shotgun", 6], ["dmr", 6]],
}

const TRADER_STOCK: Array[String] = [
	"medkit", "smg", "shotgun", "rifle", "dmr", "armor_light", "armor_heavy",
	"implant_satchel", "implant_loader", "implant_damper", "implant_servo", "implant_capacitor",
]

static func item(id: String) -> Dictionary:
	return ITEMS.get(id, {"name": id, "kind": "loot", "value": 0, "rarity": 0})

static func item_name(id: String) -> String:
	return item(id)["name"]

static func rarity_color(id: String) -> Color:
	return RARITY_COLORS[int(item(id).get("rarity", 0))]

# Selling returns half of what buying costs; salvage sells at face value.
static func sell_price(id: String) -> int:
	var it := item(id)
	var value: int = it["value"]
	return value if it["kind"] == "loot" else int(value * 0.5)

static func roll(table: String, rng: RandomNumberGenerator) -> String:
	var rows: Array = LOOT_TABLES[table]
	var total := 0.0
	for row: Array in rows:
		total += float(row[1])
	var pick := rng.randf() * total
	for row: Array in rows:
		pick -= float(row[1])
		if pick <= 0.0:
			return row[0]
	return rows[0][0]
