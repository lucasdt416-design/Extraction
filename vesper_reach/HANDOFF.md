# Vesper Reach — visual pass 02 / Godot integration handoff

Integrate this original sci-fi extraction map and equipment into the existing game. Keep the existing backend, character controller, inventory, and combat systems. The included `project.godot` is a standalone art preview, not a replacement game project.

## What changed in visual pass 02

The city uses new layered facades, taller articulated towers, recessed storefronts, sunshades, cooling pipes, rooftop equipment, detailed sidewalks, planters, transit gantries, and overhead service cables. Normal-mapped materials, patchy wet asphalt, a photographed HDR sky, local street lighting, reflection probes, screen-space reflections, and SDFGI replace the flatter first-pass look. The conservatory now has glazed roofs and planted growing beds. Scanned coastal trees and mossy boulders replace the initial abstract nature meshes, and the coarse grass has been replaced and cleared from walking surfaces.

New/replacement GLBs are in `art/detail/`. The asset catalog redirects existing names to them; copy the updated catalog and scripts together with the art. Do not load old replacement models directly from `art/architecture/` or `art/nature/`. The previous weapon and ammo kit is unchanged. Spawn, extraction, loot, and terrain-cell metadata are unchanged.

Forward+ with `enhanced_atmosphere = true` is the intended visual profile. This pass costs more GPU time than v1; it has been rendered on an Apple M5 Pro, but no target-game FPS guarantee is implied. Turning off `enhanced_atmosphere` disables the additional GI/reflection/postprocessing path. The updated Blender file is `vesper-reach-v2.blend`; the original `vesper-reach.blend` is a v1 archive and is not included in the v2 packages.

## Start here

1. Open `godot/project.godot` in Godot 4.5 or newer and run the showcase. Forward+ is the intended visual profile. Godot 4.5.1 was used for import, rendering, and collision checks.
2. Click to capture the mouse. WASD moves, Q/E moves vertically, Shift accelerates, 1–5 selects vistas, G switches to a grounded street-walk preview, and Escape releases the mouse. Space jumps in grounded mode. This controller is only for exploration.
3. For integration, copy `art`, `data`, `scenes`, `scripts`, and `shaders` into a folder such as `res://vesper_reach/`. Keep their relative structure. Let Godot import the GLBs and textures. Do not copy `.godot`, generated `.import` files, or the standalone `project.godot` into the existing project.
4. Instance `res://vesper_reach/scenes/vesper_reach.tscn` under the game's level root. The scene builds from `data/world_manifest.json` when entering the tree. It is not an editor-baked static scene. Every placement can be edited in the manifest; modular source GLBs are in `art/`.
5. The root exposes `ready_to_play` and `world_ready`. Keep the controller paused until world construction completes. Disable `create_environment` if the host game already owns its WorldEnvironment and sun. Set `enhanced_atmosphere = false` for a cheaper visual profile. Keep `build_collisions = true` for gameplay.

## World

The authored terrain is 2,048 × 2,048 metres (approximately 4.19 km²), including water and peripheral land. This is an original map inspired by bold industrial sci-fi art direction, not a recreation of a Marathon map or a verified match to its dimensions.

- 16 independently importable terrain cells, each 512 m square with a 4 m vertex grid.
- Eight locations: Aster City, The Heliograph, Tideworks, Saltglass Terraces, Viridian Conservatory, Cinder Excavation, Northwatch Observatory, and Southshore Ferry.
- Ten inter-district road connections plus city streets, alley spaces, rooftop stairs, elevated walkways, freight yards, greenhouses, water gardens, geological formations, and natural cover.
- 4,581 placed kit instances in the reviewed v2 build. Repeated visual meshes use spatial batches of MultiMeshInstance3D rather than one render node per prop. Terrain, architecture, and larger rocks have collision; foliage and small decorative pieces intentionally do not.
- Six extraction Area3D nodes, twelve spawn markers, and 88 loot markers. Exact positions and all world data use Godot coordinates: X east, Y up, -Z north. Units are metres.
- The HDR sky, water, scanned surface textures, street lighting, reflections, and original graphic signage are applied by the Godot loader. The Blender assembly has its own preview lighting and does not reproduce all Godot-only effects.

### Important layout limits

This remains an independently authored environment kit rather than finished AAA production art. Street-level architecture has real door openings and simple interiors; upper tower floors are skyline geometry rather than accessible furnished floors. Trees and boulders use simplified CC0 source models, while grass and other decorations use authored procedural geometry. Roads, cliffs, loot placement, combat sightlines, and roof routes still need in-game playtesting. Foot collision in the exploration controller does not include automatic stair stepping.

The map is split into cells, but the supplied loader loads the full world at startup. Runtime cell streaming, a baked AI navigation mesh, occlusion volumes, platform-specific budgets, network relevancy, swimming, destruction, audio, and weather gameplay are not implemented. The road graph is route metadata, not a substitute for a navigation mesh. Profile on target hardware before shipping; there is no guaranteed FPS budget.

## Extraction and loot hooks

Extraction Areas are in the `extraction_points` group and hold an `extraction` metadata dictionary. The map emits `extraction_entered(extraction_id, body)` and `extraction_exited(extraction_id, body)`.

Use the existing game logic to check the body is an authorized player, check inventory/quest conditions, run the extraction hold timer, and commit the outcome server-side. The world does not award loot, consume items, or complete extraction on its own.

| ID | Location | Hold | Proposed condition |
|---|---|---:|---|
| `ex_ferry` | Ferry 09 | 12 s | Always available |
| `ex_east` | Tidegate Cargo Lift | 15 s | Activate generator |
| `ex_north` | Northwatch Uplink | 20 s | Signal key |
| `ex_west` | Saltglass Service Tram | 12 s | Always available |
| `ex_reserve` | Canopy Evacuation | 18 s | Flare charge |
| `ex_cinder` | Cinder Freight Elevator | 15 s | Power cell |

`loot_points`, `spawns_points`, and `pois_points` groups contain Marker3D nodes with corresponding metadata dictionaries. Marker positions also exist in the manifest. Loot tiers, pools, extraction conditions and timings are design defaults, not balance-tested rules. Some loot markers sit near buildings and need review against the final interaction system.

## Weapons, ammo and cosmetic variants

Instance `scenes/weapon_display.tscn`. Set `weapon_id` and `skin` in the Inspector or before adding it to the tree. It loads the selected mesh and creates named `Muzzle` and `Grip` Marker3D children. Visuals are static meshes; reload, recoil, muzzle flash, projectile simulation, weapon IK, sounds, and network behavior belong to the game.

| Weapon ID | Design | Ammo | Proposed magazine |
|---|---|---|---:|
| `k27_carbine` | K-27 Carbine | Medium | 30 |
| `sable_smg` | Sable SMG | Light | 32 |
| `longwatch_dmr` | Longwatch DMR | Heavy | 16 |

Each weapon has `standard` (porcelain/coral), `hazard` (acid yellow), and `abyss` (deep teal) GLBs: nine visual variants total. Three ammunition tray GLBs are included. Full proposed stats and attachment coordinates are in `data/equipment.json`. All weapons point +Z in Godot. Fit the grip orientation to the chosen character animation; do not assume the static grip marker implements an aiming rig.

The previous Kestrel character package remains at `assets/characters/kestrel/` in the shared workspace. Its GLB has Idle, Walk, and Run clips; it does not include weapon-specific animation.

## Art, source and attribution

- `art/`: original modular assets plus v2 replacements, 16 terrain cells, and a road network. `data/asset_catalog.json` is authoritative about which models the map currently uses.
- `art/textures/minimap.png`: unlabelled overhead map for the game's UI. Map pixels cover world X/Z bounds [-1024,1024]; pixel X=(world X+1024)/2 and pixel Y=(world Z+1024)/2 at 1024 pixels square.
- `previews/tactical-map.png`: annotated district/extraction overview.
- `previews/v2/godot-*.png`: actual updated Godot Forward+ screenshots. `previews/v1/` retains earlier views for comparison.
- `previews/weapons-and-skins.png`: renders of the nine modeled weapon variants.
- `vesper-reach-v2.blend`: updated editable assembled geometry with packed textures. Godot additionally creates its real-time materials, signage and cables.
- `source/`: deterministic geometry/layout generators, material downloader, render scripts, and the billboard-generation prompt.
- `LICENSES.md`: CC0 texture attribution and original-art notes.

## Validation

`data/gltf-validation.json` records Khronos validation of all 87 GLBs: zero errors and zero warnings. `data/engine-validation.json` records native scene load, extraction/loot counts, ground raycasts beneath the 12 spawns and 6 extraction centres, and all 9 weapon scene variants. These are structural checks, not a combat playtest or proof of optimal performance.

To rerun the Godot checks:

```sh
godot --headless --path godot --script scripts/validate_world.gd
```

The source rebuild order is `download_materials.py`, `build_art.py` (Blender), `build_world.py` (Blender), `render_weapons.py` (Blender), and `make_atlas.py` (Python with NumPy and Pillow). The generated billboard atlas is preserved rather than regenerated by those scripts. Rebuilds overwrite generated content; make a copy before customizing.

Those commands recreate the v1 base. To apply v2 afterward, run `source/v2/fetch_environment.py`, then Blender with `source/v2/build_city.py`, `source/v2/prepare_nature.py`, and `source/v2/finish_reserve.py`; run `source/v2/dress_city.py` using ordinary Python, then Blender with `source/v2/finalize_exports.py`. Run `source/v2/repair_tangents.py` using ordinary Python to repair degenerate tangent vectors on simplified scan geometry. Finally, run Blender with `source/v2/assemble_source.py` to create the editable assembly. The dressing script uses its preserved v1 manifest for deterministic updates. Full-resolution downloaded vendor sources are excluded from the ZIPs; `fetch_environment.py` retrieves and verifies them when rebuilding.
