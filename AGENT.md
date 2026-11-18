# Working on Extraction

Extraction is an original Godot 4.7 first-person shooter built in GDScript. Players deploy from the base with a frame and equipment, search the map while AI squads patrol, and hold an extraction point to bank loot. Death or timeout forfeits the backpack and equipped kit. The earlier top-down prototype is in the `main` branch history.

## Entry points and owners

| Area | Entry point and conventions |
| --- | --- |
| Project | Open `project.godot` in the standard Godot editor and press Play. `scenes/menu.tscn` is the main scene, and all three maps deploy into `scenes/raid.tscn`. |
| Profile and raid kit | `scripts/autoload/game_manager.gd` owns saved credits, stash, equipped IDs, preferences, temporary backpack, and the seeded raid RNG. Mutate inventory through its methods. Saves use `user://profile.json` and store catalog IDs. In-raid gear changes save when the raid resolves. |
| Catalog and balance | `scripts/data/catalog.gd` holds item, weapon, frame, squad archetype, loot table, and map definitions. Roll loot through the seeded stream at container setup. |
| Player and input | `scripts/actors/player.gd` owns the active build, health, shields, abilities, and equipped `Gun` instances. `scripts/core/player_input_source.gd` produces one `InputFrame` per physics tick. Dev tools supply their own input source. |
| Gunplay and sights | `scripts/core/gun.gd` handles hitscan, spread, ammo, and reloads for both sides. The player camera defines the aim line. Imported weapon rigs in `assets/viewmodels/` animate under the camera, with procedural fallbacks where applicable. `Player.sight_blend()` and `Hud._draw_scope()` drive the Longwatch sight picture. |
| Loot and gear | `LootContainer` search spills `Pickup` nodes on the interact layer. The live Tab backpack in `scripts/ui/hud.gd` delegates equip, stow, drop, and medkit intents to Player. The displaced item goes into the same backpack slot. A dropped or packed weapon carries its runtime Gun instance so swapping cannot refill ammo. An empty secondary slot uses the issued sidearm. Capacity changes validate the resulting pack before mutating it. |
| AI and extraction | `scripts/actors/enemy.gd` owns perception and individual actions. `squad.gd` coordinates alert state, attack tokens, and patrol/search/combat. `scripts/world/raid.gd` builds the level, spawns enemies and containers, and resolves the run. `extract_point.gd` handles holds and drone calls. |
| Presentation | `scripts/ui/ui_kit.gd` shares typography, palette, and controls. Geometry and imported kits are combined with materials in `scripts/fx/mats.gd`, shaders under `shaders/`, and synthesized audio from `scripts/autoload/sfx.gd`. |

## Level authoring

- **Relay Station 07** is authored directly in `scripts/world/level.gd`. Use it for fast iteration and the core automated flow.
- **Aster City** uses `scripts/world/aster_level.gd` and `vesper_kit.gd` with the `vesper_reach/` art and manifest. World authoring uses level coordinates after subtracting the kit centre.
- **Cairn Divide** uses `scripts/world/cairn_level.gd` and `cairn_kit.gd` with the `cairn_divide/` art and manifest. Check local terrain heights for placements away from the colony shelves.
- The large maps bake local navigation regions for squads. Players traverse the terrain between those regions. Author new search cases with `Level._mark()` and labelled locations through `Level.places`. Both big maps use `_roadside_depot()` for ramped supply stops and reserve space around those stops in their scenery passes.
- Doors stay out of the navmesh so guards can approach and open them. `BUILD.md` covers the map kits, collider conventions, doors, graphics, and scene tools. `CLAUDE.md` has historical notes and more detail on AI.

## Checks

Run from the project root. Pass `--test-profile` after the double dash to use the separate test save.

```sh
godot --headless --path . --editor --import --quit
godot --headless --path . res://tools/selftest.tscn -- --test-profile
godot --headless --path . res://tools/maptest.tscn -- aster_city --test-profile
godot --headless --path . res://tools/maptest.tscn -- cairn_divide --test-profile
godot --path . res://tools/view_shots.tscn --resolution 1600x900 -- /path/to/existing/output-directory --test-profile
```

The self-test runs the Relay Station raid loop, including combat, gear changes, healing, extraction, and loss. The large-map runs check terrain, navigation, loot placement, patrols, and extracts. The view shots helper exports hip-fire, aim, and reload images for all six weapons.
