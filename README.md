# Extraction

A first-person extraction shooter built in Godot 4.7. Deploy into Relay Station, loot it,
fight or avoid the squads guarding it, and reach an extraction point before the station
locks down. Die inside and you lose what you carried and what you wore.

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
| Q / E | Frame abilities |
| 1 / 2 / wheel | Switch weapon |
| Esc | Pause |

## How a raid goes

- You start in the south-west corner with twelve minutes on the clock.
- Crates, lockers and the lab vault hold salvage, gear and medkits. The vault is loud.
- Enemies work in squads. They react to what they see and hear, lose you when you break
  line of sight, and search where they last had you. Their radio chatter shows top right.
- Stand on either extraction pad for seven seconds to leave with your backpack.
- Back at base, sell salvage, buy weapons, armor and implants, and pick a frame.

## Built with

Godot 4.7 and GDScript. There are no imported assets: geometry is built from primitives
in code, textures are generated, and sound is synthesized at startup.

The earlier 2D top-down prototype is on the `main` branch history.

See `CLAUDE.md` for how the code is organised.
