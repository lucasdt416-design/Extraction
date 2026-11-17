# Aster architecture and Kestrel first-person kit

## Preview

Import this folder's `project.godot` into Godot 4.5 and press F5. Click the viewport to look around. Use WASD to walk, Shift to sprint, 1–6 to switch weapons, R to reload, H to hide the viewmodel, and Esc to release the mouse.

| Key | Weapon ID |
| --- | --- |
| 1 | `arc_carbine` |
| 2 | `breach_shotgun` |
| 3 | `relay_pistol` |
| 4 | `k27_carbine` |
| 5 | `sable_smg` |
| 6 | `longwatch_dmr` |

## Weapon assets

`models/weapons/` contains the standalone world models. The Breach shotgun, Relay pistol and updated Arc Carbine have a separate `Magazine` node and `Grip`, `SupportGrip`, and `Muzzle` anchors. Weapon GLBs face +Z and use metre units. The K-27, Sable and Longwatch world files are the existing standard Vesper models.

`models/viewmodels/` contains six dedicated first-person GLBs with independently jointed gloves, forearms, a moving magazine, and `Idle`, `Reload`, `Holster`, and `Equip` clips. The K-27, Sable, and Longwatch use their standard Vesper finishes. The right hand stays on the weapon and the support hand performs the magazine exchange. Reload timing is shared across the clips. The receiving game's ammo, reload duration, firing, and weapon rules remain game logic.

Attach `scripts/viewmodel.gd` to a Node3D under the local camera. Copy the `scripts/viewmodel.gd` file and `models/viewmodels/` folder under the same kit directory in the receiving project so the script can resolve the GLBs. Call `equip(id)` or `reload()` after game authorization. Each returns whether the presentation accepted the request. The script emits `equipped(id)` after holster and equip, and `reload_finished(id)` after the reload animation. A single forward-facing world weapon mesh can still be mounted on the third-person character separately.

## Building assets

| Model | Geometry |
| --- | --- |
| `aster_habitat` | Rounded pressure hull, recessed window belt, entrance canopy, interior benches |
| `aster_clinic` | Angled wings, folded roof canopy and walk-in triage lobby |
| `aster_workshop` | Three sawtooth roof cassettes, shutter bays and open fabrication floor |
| `aster_tower` | Tapered twin residential wings, elevated sky lounge and a pass-through ground lobby |
| `aster_skybridge` | 16 m pedestrian module with two deck sockets and side balustrades |

The four Aster building replacements are already wired into the workspace Vesper Reach project at 48 existing Aster placements. They use the existing placement transforms and roughly the same foundation footprints. The interiors provide ground-level access. The elevated tower volume is exterior geometry, and the separate skybridge can be placed as a level-design module. Building signage is mesh geometry. Emission, roads, screens, and world lighting are deferred to the game's lighting pass.

To install the buildings into another copy of Vesper Reach, run `python3 source/install_aster.py /path/to/vesper-reach/godot`. The script copies the four GLBs and updates only Aster's matching asset IDs in the manifest. The skybridge ships separately from those placements.

## Editable source and verification

The Blender Python files in `source/` generate the meshes and baked animation actions. Run Blender 4.5 in background mode with `--python source/build_weapons.py` or `--python source/build_buildings.py` from the kit. The three original Vesper GLBs under `models/weapons/` are source inputs for their first-person variants. The in-engine renders in `previews/` show the studio kit and the assets in Godot. Run `godot --headless --path . --script scripts/validate_assets.gd` after import to check the rigs, reload and switching behavior, sockets, and collision at the building entrances.
