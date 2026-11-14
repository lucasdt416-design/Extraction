# BUILD.md

What exists in this repo right now, how to run and check it, and where to change things.
`CLAUDE.md` holds the rules; `PLAN.md` holds where this is going and how to work on it.
Last updated 2026-11-13.

## State in one paragraph

A first-person 3D extraction shooter in Godot 4.7 (GDScript). The loop is complete: menu →
deploy → loot and fight AI squads → hold an extraction pad → stash, with loss on death.
One map. The player character is Kestrel, an imported rigged model; everything else is
built in code from primitives, generated textures and synthesized sound. An automated
play-through passes. **No person has played it yet**, so feel and balance are unverified.

## Branches

| Branch | What | Status |
|---|---|---|
| `main` | The original 2D top-down prototype | Will be replaced when PR #1 merges |
| `three-d` | The 3D rebuild | PR #1, open |
| `graphics` | Graphics pass, Kestrel, enemy rebuild, death view, these docs | Pushed, built on `three-d`, no PR until #1 merges |
| `settings` | Settings screen (sensitivity, FOV, volume, quality), enemy stagger | Pushed, built on `graphics` |
| `menu` | Title screen and poster-style main menu over a live 3D studio; bundled fonts | Pushed, built on `settings` |
| `polish` | Death and extraction sequences, Armoury page, map list, animated controls | Pushed, built on `menu` |

Merging PR #1 deletes the 42 2D files from `main`'s working tree (they stay in git
history) and adds the 3D game. Nothing else in the repo is touched.

## Run it

Godot 4.7 is **not installed** on the main dev Mac; install it from godotengine.org.
Open the folder in Godot and press Play. It starts at the menu (`scenes/menu.tscn`).

From a terminal, with `GODOT` pointing at the binary
(`Godot.app/Contents/MacOS/Godot` on macOS):

```sh
$GODOT --path .                                   # play
$GODOT --headless --path . --import               # after adding/renaming files; surfaces parse errors
$GODOT --headless --path . res://tools/selftest.tscn -- --test-profile   # core loop, PASS/FAIL
$GODOT --headless --path . res://tools/sim.tscn -- --test-profile        # menu↔raid flow + survival time
$GODOT --path . res://tools/shots.tscn --resolution 1600x900 -- <dir> --test-profile   # screenshots
$GODOT --path . res://tools/shots.tscn -- <dir> --test-profile --fps     # draw calls, triangles, frame time
```

`--test-profile` makes saves go to `user://profile_test.json`. Always pass it from tools,
or a test run will overwrite the real save.

## Where things live

```
assets/characters/kestrel/   kestrel.glb (rigged, Idle/Walk/Run), concept image
scenes/                      menu.tscn, raid.tscn: a root node + script each
shaders/                     surface (walls/floors), sky, post (lens)
scripts/
  autoload/game_manager.gd   profile, stash, loadout, backpack, RNG, scene flow, input map
  autoload/sfx.gd            every sound, synthesized at startup
  data/catalog.gd            ALL tuning data: items, weapons, frames, enemies, loot, trader
  core/                      InputFrame, PlayerInputSource, Gun (shared hitscan), Layers
  actors/player.gd           first-person controller, abilities, view model, death view
  actors/kestrel_body.gd     wraps the Kestrel model: FULL / FIRST_PERSON / SHADOW modes
  actors/enemy.gd            perception, states, position scoring, fire control
  actors/squad.gd            shared knowledge, attack tokens, roles, search, barks
  actors/rig.gd              enemy body, built and animated in code
  actors/grenade.gd
  world/raid.gd              assembles a raid: environment, level, player, squads, HUD, clock
  world/level.gd             Relay Station, hand-authored as code; bakes its navmesh
  world/loot.gd, loot_container.gd, extract_point.gd
  fx/mats.gd, shapes.gd, fx.gd   materials, bevelled meshes, one-shot effects
  ui/hud.gd, menu.gd, ui_kit.gd
tools/                       selftest, sim, shots: development helpers
```

## "I want to change X" → go here

| Change | File |
|---|---|
| Weapon damage, fire rate, recoil, magazine | `Catalog.WEAPONS` |
| Enemy health, speed, accuracy, aggression, specials | `Catalog.ENEMIES` |
| Item values, loot odds, trader stock | `Catalog.ITEMS`, `LOOT_TABLES`, `TRADER_STOCK` |
| Frame abilities and cooldowns | `Catalog.FRAMES`; behaviour in `Player._use_ability` |
| Player speeds, jump, shield regen | constants at the top of `player.gd` |
| How enemies pick where to stand | `Enemy._decide` (the scoring block) |
| How many enemies may shoot at once | `Squad.max_tokens` |
| What enemies say | `Squad.BARKS` |
| Map geometry, squads, loot spots, extracts | `level.gd` (`_warehouse`, `_lab`, …) |
| Raid length | `Raid.RAID_LENGTH` |
| Sky, fog, exposure, reflections | `Raid._build_environment` |
| Wall/floor look | `shaders/surface.gdshader`, `Mats.wall` |
| First-person weapon models | `Player._build_view_models` |
| Menu pages and their content | `ui/menu.gd` (`_play`, `_armoury`, `_loadout`, `_trader`, `_frames`, `_settings`) |
| Adding a map to the Play page | a new entry in `Catalog.MAPS` (name, title, wall mark, scene, brief) |
| Death fall, slow motion, raid-over screen | `KestrelBody.collapse`, `Player._death_view`, `Raid._end`, `Hud.show_result` |
| Each page's wall word, disc colour and camera angle | `PAGES` at the top of `ui/menu.gd` |
| The menu's 3D studio | `ui/menu.gd` `_build_stage` |
| Typefaces and accent colours | `UiKit.display` / `font` / `mono`, `UiKit.ACID` / `CORAL`; files in `assets/fonts/` |
| Key bindings | `GameManager._bind_inputs` |
| Settings and their ranges | `GameManager.SETTING_RANGES`; controls in `UiKit.settings_rows` |
| What each graphics quality level turns off | `Raid.apply_quality` |
| Starting credits and items | `GameManager.load_profile` |

## How a raid is put together

`Raid._ready` runs in this order, and the order matters:

1. Environment and sun.
2. `Level.build()` creates geometry and fills `containers`, `extracts`, `squads`.
3. Loot containers are added **into the level**, then `Level.bake()`, so the navmesh
   routes round them.
4. Extraction points, player, lens and dust, HUD.
5. Wait two physics frames (the navigation map only syncs then), then spawn squads.

Physics layers: 1 world, 2 player, 3 enemy, 4 interact, 5 navmesh source (roofs are left
off layer 5 so no navmesh forms on them).

## Asset contract (for anything made outside this repo)

Give this to whoever or whatever makes models:

- **Format:** `.glb`, self-contained, no external textures, no Draco.
- **Units and axes:** metres, Y up, origin on the ground at the object's base centre.
  Characters and weapons face **+Z** in the file (the game flips them).
- **Scale:** Kestrel is 2.05 m in the file and scaled to 1.8 m in game. A doorway is
  2.2 m wide × 2.6 m high. A cover barrier is 1.1 m high.
- **Palette:** chalk white `#E6E8E3`, graphite `#2B3237`, acid yellow `#E2F016`,
  coral `#FC6142`, gunmetal `#5D696F`. Teal `#29A0A0` marks things you can interact with.
- **Characters:** one mesh, one skeleton, clips as separate looping animations. Wanted
  next for Kestrel: `Crouch_Idle`, `Crouch_Walk`, `Jump`, `Fall`, `Aim_Idle`, `Death`.
- **Weapons:** barrel along +Z, grip at the origin, an empty named `muzzle` at the tip
  and `mag` on the magazine (as a separate object, so it can drop on reload).
- **Environment pieces:** snap to a 1 m grid, pivots on the ground corner or centre,
  named `wall_4m`, `door_frame`, `crate_a`…; under 5k triangles for a prop, 15k for a
  hero piece.
- Drop files in `assets/<kind>/<name>/` with a short `README.md` of what's in the file.

## Known gaps (the honest list)

- Never played by a person. Balance, recoil, movement feel and AI pacing are guesses.
- One map. No reinforcements or respawns during a raid.
- Kestrel has no crouch, jump, aim or death clips; crouch squashes the model.
- First-person arms are capsules, not Kestrel's real arms. No weapon inspect/equip
  animation, no melee.
- Enemy bodies are code-built; their crouch doesn't lower their hit capsule.
- All audio is synthesized placeholder. No music, no ambience, no voices.
- Level geometry is boxes with a shader. No modelled environment art.
- Inventory is a flat list with a slot count: no grid, no weight, no item inspection.
- The level is code, not a scene, so it can't be edited in the Godot editor.

## Performance notes

Measured on an Apple M5 Pro at 1600×900: ~2,500–3,400 draw calls and 0.7–1.1 M triangles
(shadow passes included), 60 fps. SDFGI, SSR, volumetric fog, glow and auto exposure are
all on at High; the quality setting turns the expensive ones off. The frame-rate number from the `shots` tool is unreliable
when its window isn't in front (macOS throttles it); trust the triangle and draw counts.
Every box is its own draw call; if the map grows, merge static geometry or move to
MultiMesh before cutting effects.
