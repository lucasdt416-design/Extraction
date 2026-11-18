# Extraction

A first-person extraction shooter built in Godot 4.7. Deploy into Relay Station 07, Aster City, or Cairn Divide. Search for loot, fight or avoid the local squads, and reach an extraction point before the raid clock runs out. Die inside and you lose what you carried and what you wore.

## Run it

Open the folder in Godot 4.7 and press Play. The game starts at the base menu.

## Controls

| | |
|---|---|
| WASD | Move |
| Mouse | Look, left button fires, right button aims |
| Shift / Ctrl or C / Space | Sprint / crouch / jump |
| R | Reload |
| F | Use: take items, search containers (hold) |
| H | Medkit |
| Tab | Backpack: use or drop items, equip gear, and stow equipped items |
| Q / E | Frame abilities |
| 1 / 2 / wheel | Switch weapon |
| Esc | Pause |

## How a raid goes

- Search crates and lockers for supplies, gear, and salvage. Vaults hold higher-value loot and trigger an alarm.
- Aster City and Cairn Divide have marked resupply stops between their larger settlements.
- The raid keeps running while the backpack is open. Equip a replacement to move the old item into your pack, or drop an item on nearby ground to free a slot.
- Squads react to what they see and hear and search where they last had you. Their radio chatter appears at the top right.
- Hold an extraction point to secure your pack and equipped gear. Some points call a drone first.
- Back at base, sell salvage, buy equipment, and pick a frame.

## Built with

Godot 4.7 and GDScript, with code-built levels, imported environment and character kits, and sound synthesized at startup.

The earlier 2D top-down prototype is on the `main` branch history.

See `AGENT.md` for the project architecture and test commands.
