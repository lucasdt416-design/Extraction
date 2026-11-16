# Cairn Divide — mountain colony / Godot handoff

This is the second map in the extraction project. Vesper Reach remains separate and unchanged. Cairn Divide is an original mountain-colony environment with functional interaction examples, authored for Godot 4.5 Forward+.

## Start the playable preview

Open `godot/project.godot` in Godot 4.5 or newer, let its assets import, and run. The preview starts outside the central Hearth residence. Click to capture the mouse.

- WASD moves, Shift sprints, Space jumps, and Escape releases the mouse.
- Aim at the small illuminated wall button and press **F** to open or close a door. Both sides have a button. Aim at a supply case and press F to emit its search interaction.
- **K** toggles demonstration archive keys. These exist only on the standalone preview actor. Without them, archive doors remain locked.
- **G** switches between ground movement and flight; Q/E descend/ascend in flight. **R** returns to the entrance. **1–6** select inspection viewpoints.
- The preview does not award inventory or finish raids. Its search notification demonstrates the integration event.

## Map content

The landscape spans **2,048 × 2,048 m**, with a nominal 1,536 m raid core and mountain scenery outside it. Metres are native Godot units: X east, Y up, -Z north.

| District | Identity |
| --- | --- |
| Hearth Colony | Five residential modules around an enclosed two-level circulation route |
| Lichen Research | Field laboratories, survey dish, archive rooms, and relay mast |
| The Spillway | Water recovery plant, tanks, pumps, and engineering buildings |
| Crown Relay | High-altitude communications and a large survey array |
| Old Quarry | Mineral-transfer gantry, cargo cassettes, and utility buildings |

The current build contains 16 terrain cells, 17 two-storey buildings, 47 glass-bridge modules, two long river-gorge crossings, 138 sliding doors (17 locked archive doors), 88 physical loot cases, 10 starting positions, and 5 extraction areas. There are 6,048 static kit placements, including scanned firs, ferns, ground cover, and rocks. Upper floors have real stair access; bridge openings align with the building portals.

The reference was Perimeter's outdoor colony structure: separated settlements, rocky travel routes, infrastructure landmarks, and valuable locked rooms. This is not a copied map or verified metre-for-metre match: the public references inspected did not establish reliable dimensions. Original layouts, names, meshes, and code are used here.

References reviewed:

- [Perimeter overview and region map](https://www.marathonwiki.com/Perimeter)
- [Perimeter interactive reference map](https://www.shackmaps.com/marathon/perimeter)
- [Bungie's description of Perimeter as an edge-site colony expansion](https://static01.bungie.net/7/en/News/Article/marathon-server-slam)

## Integrate with the existing game

Copy `godot/art`, `data`, `scenes`, `scripts`, and `shaders` together into a folder such as `res://maps/cairn_divide/`. Preserve their relative paths. Do not replace the game's project file or copy the generated `.godot` cache. Instance `scenes/cairn_divide.tscn` and wait for `ready_to_play` or `world_ready` before enabling the player.

The scene builds its meshes and gameplay nodes from `data/world_manifest.json` at runtime. `data/asset_catalog.json` maps asset IDs to GLBs and collider descriptions. The native scene is deliberately independent of Vesper Reach and can coexist with it.

Root properties:

- `build_collisions`: static environment collision generation; keep enabled for play.
- `create_environment`: disable if the host owns its environment and sun.
- `enhanced_atmosphere`: enables Forward+ GI, reflections, volumetric fog, and postprocessing.
- `preview_local_interactions`: **false by default** on the integration scene. Only the showcase sets it true.

## Door authority, locks, and safety

The world emits `door_access_requested(door_id, actor, desired_open)`. The host game should validate the player, proximity, key possession, powered state, and network authority, then call:

```gdscript
world.doors[door_id].apply_authorized_state(desired_open)
```

That method animates the two physical leaves and emits `state_changed`. It is a local presentation method, not an exposed RPC and not a permission check. Replicate authorized state through the game's existing networking. Door `set_locked(bool)` updates the lock and status lights; `key_id` is in the manifest. The sample local mode checks an actor's `has_access_key(key_id)` method. Production inventory and server logic must provide their own implementation.

Each doorway has an occupancy volume. Closing is refused while occupied, and closing reverses if a body enters. Actors must include **physics layer 2** to be seen by this sensor. Solid scenery and door leaves occupy layer 1; interaction targets use layer 4 (bitmask 8). The preview ray uses mask 9 so solid walls occlude interaction targets. Extraction areas see layers 1 and 2.

Some unused upper portals are protected with guard rails. Glass panes are physical colliders. Sliding leaves move into the adjacent wall volume; do not place gameplay objects in those pockets. There is no automatic door-closing timer, power puzzle, destruction, or persistence implementation.

## Loot and extraction hooks

The world emits `loot_search_requested(container_id, actor, loot_spec)`. Each physical container has a `LootAnchor`, belongs to `loot_containers`, and stores its authored data under `loot` metadata. The host chooses contents, validates access/range, and handles inventory atomically. Call `mark_searched()` only after the host has accepted the search. Loot pools, tiers, and archive key associations are proposed defaults.

Extraction areas emit `extraction_entered(id, body)` and `extraction_exited(id, body)`. All five belong to `extraction_points`. Conditions and hold durations are in the manifest; the map does not enforce a timer or award an extraction. Markers are also in `spawns_points`, `pois_points`, and `loot_points` for compatibility with the first kit.

The UI minimap is `art/textures/minimap.png` (1024 square). Map coordinates are pixel X=(world X+1024)/2 and pixel Y=(world Z+1024)/2. `previews/tactical-map.png` is the labelled overview.

## Verification and remaining production work

`data/gltf-validation.json` contains Khronos validation of the 40 GLBs: zero errors and zero warnings. `data/engine-validation.json` records 104 passing checks covering native scene/marker checks, spawn/extraction ground checks, bridge-deck checks, actual player stair traversal, both-side door interaction, key denial, opening/closing collision, range rejection, and obstruction safety.

```sh
godot --headless --path godot --script scripts/validate_world.gd
```

The screenshots in `previews/godot-*.png` are actual Godot Forward+ renders, not concept paintings. This is an environment and interaction kit; it does not yet meet a finished AAA art standard. More bespoke environmental storytelling, terrain erosion detail, and district-specific interiors remain useful art work. Test combat routes, loot balance, and encounter pacing in the host game.

The supplied loader loads the whole map. Runtime streaming, AI navigation baking, occlusion-volume authoring, network relevancy, final collision budgets, audio, swimming/climbing, enemy placement, and target-platform FPS validation remain host integration work. High-detail nature and Forward+ effects are expensive; profile the real game. Do not infer a shipping performance guarantee from these previews.

## Editable source and rebuilds

`cairn-divide.blend` in the source package is an editable linked-mesh assembly with packed textures. Godot supplies animated interactions, the terrain/river shaders, light setup, bridge supports, and safety rails. The GLBs are independently reusable.

Rebuild in this order, from a copy if you have customized the content:

1. `python3 source/fetch_nature.py` downloads and verifies the CC0 scans.
2. Blender background mode with `source/build_colony.py`, `source/prepare_nature.py`, then `source/build_landmarks.py`.
3. Blender with `source/build_world.py` creates the landscape and manifest.
4. `python3 source/repair_tangents.py` repairs collapsed-UV tangent vectors.
5. Python with NumPy/Pillow runs `source/make_map.py`.
6. Blender with `source/assemble_source.py` creates the editable assembly.
7. Reimport in Godot and run the validation script.

The shared material textures and six mossy-rock GLBs are included as inputs from the Vesper Reach kit. High-resolution `vendor/` downloads and editor caches are excluded from the ZIPs. Attribution and source links are in `LICENSES.md`.
