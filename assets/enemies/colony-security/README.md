# Colony Security

Eight original, metre-scale 3D enemies for the extraction game. This revision adds curved armor shells, wraparound optics, visible neck and limb joints, and more detailed body armor. Open `project.godot` in Godot 4.5 and run the viewer. Use the arrow keys to select a unit and Space to switch between Idle and Walk, and **H** to play the Stagger hit reaction.

| Model | Role reference | Visual cues |
| --- | --- | --- |
| Patrol | Recruit | Light pale chassis and short carbine |
| Breacher | Assault | Oxide armor and a forearm shield |
| Longshot | Sniper | Long rifle, asymmetrical range optic and cyan armor |
| Shade | Ghost | Narrow signal hood, slit optic and plum panels |
| Sapper | Grenadier | Twin payload drums and a heavy launcher |
| Marshal | Commander | Tall chassis, signal spine and antenna pair |
| Bastion | Warden | Heavy shoulder deflectors, shield and reinforced armor |
| Crawler | Tick | Low carapace, six legs and three recessed optics |

The references establish enemy roles and silhouettes. The meshes, weapon details, rigs, colors, and names are original. [Bungie's enemy roster notes](https://www.bungie.net/7/en/News/Article/marathon_update_1_0_9) · [Marathon Codex references](https://www.marathonwiki.com/Lore%3AAutonomous_Robotic_Soldier)

Each GLB includes its own rig and in-place Idle, Walk, and Stagger clips. The weapons are modeled as part of the robots. Attack, locomotion blending, cloak, and death states still need gameplay and animation work. The models face +Z. `catalog.json` lists IDs, model paths, and approximate heights. The editable Blender assembly is under `source/`.

Both map manifests expose four `enemy_spawns` markers with a matching role ID. The host decides whether to spawn a model and supplies AI, combat, collision bodies, and replication. In Godot, load the relevant PackedScene and play the imported animation with its AnimationPlayer. The viewer's validation imports every model and plays all three clips.
