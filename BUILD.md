# BUILD.md

What exists in this repo right now, how to run and check it, and where to change things.
`CLAUDE.md` holds the rules; `PLAN.md` holds where this is going and how to work on it.
Last updated 2026-11-16.

## State in one paragraph

A first-person 3D extraction shooter in Godot 4.7 (GDScript). The loop is complete: menu →
deploy → loot and fight AI squads → hold an extraction pad → stash, with loss on death.
Three maps: Relay Station 07 (all code-built), Aster City (the Vesper Reach art kit plus
code-built set pieces) and Cairn Divide (the Cairn Divide art kit: a mountain colony). The player character is Kestrel, an imported rigged model; everything else is
built in code from primitives, generated textures and synthesized sound. An automated
play-through passes. It has had **one outside playtest** (2026-11-15); the fixes from it
are listed under "Playtest log" below and have not been re-played yet.

## Branches

Everything is on `main`. Work happens on a short branch per job, merged by PR.

## Maps

| Map | Level class | What it is |
|---|---|---|
| Relay Station 07 | `Level` (`world/level.gd`) | 90 × 70 m compound, every piece built in code. The default. |
| Aster City | `AsterLevel` (`world/aster_level.gd`) | The whole 2 km island: the cordoned town in the middle (168 × 224 m) and seven more places beyond its gates. 30 minutes, seven exits. |
| Cairn Divide | `CairnLevel` (`world/cairn_level.gd`) | 1.5 km square valley: five abandoned colonies, guard posts on the trails, rock shelters. 25 minutes, five exits. |

A map is an entry in `Catalog.MAPS`; its `"level"` (`"aster"`, `"cairn"`) picks the class in `Raid._ready`.
A level subclass overrides `build()`, `bake()` and optionally `tune(env, sun)`, and fills
`containers`, `extracts`, `squads`, `reinforce_points`, `player_spawn`.

**Aster City** is made of two layers:

- **The Vesper Reach kit** (`vesper_reach/`, made by ChatGPT; its notes are in
  `vesper_reach/HANDOFF.md`, licences in `LICENSES.md`). A 2 km island described by
  `data/world_manifest.json`: terrain cells, roads, 4,581 placements, signage, lights.
  `VesperKit` (`world/vesper_kit.gd`) loads the part within 440 m of the city centre, moves
  it so the crossroads is the origin, draws repeated meshes as MultiMeshes and only makes
  colliders near the playable area. The other seven districts are not loaded.
- **What is authored here** in `AsterLevel`, in the same code-built language as Relay
  Station: the relay spire on the crossroads (deck, two ramps, mast), two glass bridges
  over the avenue between roofs, the depot hangar (bay door, raised deck, vault), roof
  landings, the cordon wall and gates, street cover, interior lighting and shelving, loot,
  squads and exits.

**Doors, gates and grass** (added 2026-11-16):

- `Door` (`world/door.gd`) is a sliding slab that blocks movement, shots and sight while
  shut. `DoorSwitch` (`world/door_switch.gd`) is the button beside it: amber when shut,
  teal when open, pressed with the use key. Levels place them with `Level._door` and
  `Level._switch`. Every Aster building has one (about a third start open), the depot bay
  is a two-leaf shutter on one button, and the depot's three side doors each have their own.
- Doors are not navmesh obstacles. Guards open any door by walking up to it and it shuts
  2.5 s after the last of them is through, so a door working by itself means someone is
  coming. The player working a door makes noise (7 m for a door, 22 m for the shutter,
  32 m for a gate). A door never shuts on a body standing in it.
- The cordon's **north and south gates open** from a button on either side. Past each is
  one more block of the kit's city: four buildings, the boulevard and a service lane, with
  two squads and ten loot spots a side, walled at z = ±112. The third way out, "North
  road", is at the far end of the north quarter. East and west gates are still the exits
  and stay shut.
- `Grass` (`world/grass.gd`, `shaders/grass.gdshader`) plants itself: two physics frames
  after the level is built it looks down on a 1 m grid and grows wherever the first thing
  hit is the terrain (marked with the `soil` meta in `VesperKit`), so roads, pavements and
  building pads stay clear without being listed. About 66,000 tufts in 24 m chunks, full
  tufts within 30 m and a 4-blade stand-in out to 80 m. In the shader it sways in gusts,
  parts round the player and the eight nearest guards, and is thrown flat by grenades
  (`call_group("grass", "blast", at, radius)`). Some tufts carry lit seed heads. Off at
  Low graphics quality.

Things in the kit that had to be corrected (all in `AsterLevel._leave_out` and
`_roof_access`): its roof stairs stop a metre short of the roofs; its arcades put a post
in front of the doors they shelter; a few barriers stand across doorways; its skywalks sit
40 cm above the roofs; its kerbs and door sills are too high to walk over, which is why
`core/steps.gd` now gives the player and enemies step-up movement.

Not used yet from the kit: the three weapon models in three skins
(`vesper_reach/art/weapons`, stats in `data/equipment.json`), the minimap image, and the
other districts.

**The island (2026-11-16).** Aster City no longer ends at its wall. The west, east and
outer south gates slide open like the inner ones (`_cordon`), and the kit's seven other
districts are playable (`AsterLevel.SITES`, built by `_site`):

- Five get a small colony built by rule: up to six more of the kit's buildings in two
  rows (`SLOTS`; a different mix of workshop, clinic and habitat at each place), skipped
  wherever the kit already stands something. `_fit` gives each a door, buttons, light,
  shelving and a container. Cover and containers go in the street between the rows, the
  kit's own loot cases become containers, two squads hold it, and a raid can start there.
- Northwatch and Southshore are left as the kit made them, with one squad: outposts.
- The six ways off the island are the kit's own extraction pads, out at the sites, plus
  North road inside the wall. The old West gate and East gate exits are gone.
- As on Cairn Divide: one island of navmesh per place (`Level._bake_islands`), guards
  stay home, reinforcements within 170 m, the corner map, a start chosen from the seed.
- `VesperKit` now makes the whole island's terrain solid, gives heights
  (`height(x, z)`), takes `zones` (where colliders and navmesh are wanted) and
  `solid_radius` (the rest of the town outside the wall is solid but has no doors), and
  draws ground cover, rocks and trees by 128 m square with a distance limit. A tree past
  230 m is a 60-triangle stand-in.

**Cairn Divide** (added 2026-11-16, widened to the whole valley the same day) is all of
ChatGPT's second kit (`cairn_divide/`; its notes are `cairn_divide/HANDOFF.md`, licences
in `LICENSES.md`): a 1.5 km square of mountain valley with five abandoned colonies either
side of a river gorge. `CairnKit` (`world/cairn_kit.gd`) loads it.

- From the kit: 17 houses (two real floors, stairs, most with a locked archive upstairs),
  glass walkways, the two long glass crossings over the gorge, masts, pump house, gantry,
  dishes, the door model, terrain, trails, river, ferns, boulders, one fir, the map picture.
- The kit's manifest lists its doorways and loot cases. `CairnLevel._doors` turns each
  doorway into two `Door` leaves wearing the kit's model with a `DoorSwitch` either side
  (138 doorways). `_loot` turns the loot cases into containers. Archive doors are
  `locked`: the button is red, takes 3 s to force and is loud; guards do not open them.
  Every other archive holds a vault, the rest a locker.
- Authored in code: cover and wreckage in each colony (`_yards` for Hearth, `_camp` for
  the other four, mirrored and recoloured), six guard posts on the trails (`_post`, four
  manned; each looks for the most level ground near its listed spot), four rock shelters
  in the hills made of the kit's boulders (`_shelter`), squads (29, 55 guards), an exit
  in every colony, meadow on each colony's shelf.
- **Guards stay home.** The navmesh is one island per colony and manned post
  (`CairnLevel.zones`, baked in `bake()` from one parse of the colliders). The ground
  between is the player's alone. `Level.separate_regions` tells the tools; reinforcements
  only arrive within `Level.reinforce_range` (150 m) of the player.
- You start at one of the kit's ten insertion points, chosen from the raid's seed
  (`CairnLevel.spawn_at` pins it for the tools).
- `Level.origin` is added to everything the box helpers build, so one layout function
  can build at any height: set it, build, set it back.
- `CairnKit.height(x, z)` gives the ground height anywhere.
- The corner map (`Hud._draw_map`) shows for any level that sets `Level.minimap`,
  `minimap_span` and `places`. Only Cairn Divide does.
- "Run-down": `WEAR` in `CairnKit` drives stains and flaked paint in
  `cairn_divide/shaders/painted_surface.gdshader`; a third of the lamps are dead.
- Left out of the repo: the kit's own grass, cliff, sky image, loot-case and button
  models, and the young-fir model (a young fir is the big one at 0.3 scale).
- The scanned fir is 220,000 triangles. Each of the 1,500 is drawn as the scan only
  within 60 m of the camera; beyond that, and for its shadow, a 130-triangle stand-in
  built in `CairnKit._fir_stand_in`.

## Playtest log

**2026-11-16, playability pass (asked for by the user).** Reported: "when I shoot 1, 3
others spawn"; some buildings on Aster's outskirts can be walked through; distant
structures look blocky. Changed:

- Reinforcements (`Raid._escalate`, `send_reinforcements`): none in the first four
  minutes, at most two a raid, three minutes apart, only after 100 s of fighting within
  70 m of the player, and never closer than 80 m (30 m on Relay Station) or in sight.
  The first wave is two troopers.
- Backup (`Squad._call_backup`): only the single nearest quiet squad within 16 m comes,
  7–12 s later. It used to be every squad within 22 m, 4–8 s later.
- Collision (`VesperKit._queue`): every kit piece the kit calls solid is solid anywhere on
  the island, not only near the zones. Trees get a trunk and rocks a block
  (`_rough_collide`); the kit gave them none.
- Distance: kit buildings on both big maps keep more detail far off (`lod_bias = 3`);
  Aster's tree stand-ins start at 320 m with a rounder crown; Cairn's scanned firs are
  drawn to 90 m and the stand-in beyond is a ragged ten-skirt fir, not a stack of cones.
- Aster's buildings re-finished as colony modules (see Known gaps).

All checks pass. Standing in the open on Relay Station: dead at 14.5 s. Not played.

**2026-11-16, Aster City opened onto the island.** Not played by a person. `maptest
aster_city` passes (all the old checks, the new road gate, every exit on ground, 79
containers, 62 of 62 guards moving). Four of the seven sites were looked at in screenshots.
About 2.4 M triangles a frame from the town spawn.

**2026-11-16, Cairn Divide added, then widened to the whole valley.** Not played by a
person. `maptest cairn_divide` passes (Hearth on both floors, the walkways, an archive, a
shut door, every exit on navmesh, every container standing on ground); 46 of 55 guards
moved in ten seconds of patrol. About 3.5 M triangles a frame from the Hearth spawn. Builds
and bakes in about 3 s.

**2026-11-15, first outside playtest.** Reported: a freed-instance error in
`Fx._bullet_hole`; enemies run you down; one shot brings the whole map; the window is
tiny with no way to change it; a long loot list pushes the result button off screen; too
few loot boxes and they look like ordinary crates. What changed in response:

- Hearing: weapon noise radii roughly halved, walls halve them again
  (`Enemy.WALL_MUFFLE`), and a squad only walks to a noise inside 14 m
  (`Squad.WALK_TO_NOISE`); further off it turns to face it. Backup from neighbouring
  squads needs the fight within 22 m (`BACKUP_RANGE`).
- Pressure: at most two units fire at once across all squads (`Squad.MAX_SHOOTERS`), with
  a gap after each burst (`FIRE_GAP`). Aim settles more slowly, firing on the move is
  wild, and your own movement throws their aim more. Trooper and Stalker damage down,
  Stalker slower than your walk.
- Respect: only Stalkers rush. Everyone else avoids open ground, keeps 6 m off
  (`Enemy.KEEP_OFF`), ducks when hit, and a squad that loses members gets cautious
  (`Squad.caution`): it stands further back and stops pushing. The last survivor of a
  squad falls back.
- Reinforcements need about twice the sustained fighting, and the timed wave moved from
  the halfway mark to the last 30% of the clock.
- Display, window size and render resolution settings; fullscreen by default.
- Loot containers are chalk white with a lit teal band and a pool of light; 34 on the
  map, up from 19.

**2026-11-15, second note from the user after playing.** "Guards are still too fast", the
new map couldn't be found, and the image "looks like it was built in 1982". Changed: every
enemy type about 18% slower with gentler acceleration (Trooper 2.7 m/s against the player's
5.0 walk); the Play page's map links became two large blocks and Aster City is the default
map; walls, floors and ground now carry photographed concrete and rock detail with relief
and grooved panel seams (`shaders/surface.gdshader`, `Mats.ground`), with 4x MSAA, 16x
anisotropic filtering and a larger shadow atlas.

Measured after: standing still in the open courtyard with two squads in view, death in
about 11.5 s (was 7). That is the only number; whether it now *feels* fair needs playing.

**2026-11-16, asked for by the user.** Doors with buttons, gates that open onto more of
the city, and grass that moves, "make it feel alive". All three are in (see "Doors, gates
and grass" above). `maptest` now also checks that a shut door and a shut gate stop the
player, that their buttons open them, and that grass found ground to grow on. Not played
by a person yet.

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
$GODOT --headless --path . res://tools/maptest.tscn -- aster_city --test-profile     # a map is walkable: exits, roofs, doors, loot, kerbs
$GODOT --path . res://tools/map_shots.tscn -- <dir> aster_city --test-profile       # plan view and eye-level views of a map
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
  world/aster_level.gd       Aster City: the kit's streets plus code-built set pieces
  world/vesper_kit.gd        loads part of the Vesper Reach kit as a level's scenery
  world/cairn_level.gd       Cairn Divide: the kit's houses, doors and loot as game objects
  world/cairn_kit.gd         loads Hearth Colony and the valley round it from the Cairn Divide kit
  core/steps.gd              step-up movement over kerbs and sills
  world/door.gd, door_switch.gd   sliding doors and gates, and the buttons that work them
  world/grass.gd             self-planting grass; movement is in shaders/grass.gdshader
  world/loot.gd, loot_container.gd, extract_point.gd
  fx/mats.gd, shapes.gd, fx.gd   materials, bevelled meshes, one-shot effects
  ui/hud.gd, menu.gd, ui_kit.gd
vesper_reach/                the Vesper Reach art kit: models, textures, shaders, manifest
cairn_divide/                the Cairn Divide art kit (the part this game uses)
tools/                       selftest, sim, maptest, shots, ui_shots, map_shots: development helpers
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
| Map geometry, squads, loot spots, extracts | `level.gd` (`_warehouse`, `_lab`, …); `aster_level.gd` (`_spire`, `_glass_bridge`, `_depot`, …) |
| Raid length | `Raid.RAID_LENGTH` |
| Sky, fog, exposure, reflections | `Raid._build_environment` |
| Wall/floor look | `shaders/surface.gdshader`, `Mats.wall` |
| First-person weapon models | `Player._build_view_models` |
| Menu pages and their content | `ui/menu.gd` (`_play`, `_armoury`, `_loadout`, `_trader`, `_frames`, `_settings`) |
| Adding a map to the Play page | a new entry in `Catalog.MAPS` (name, title, wall mark, scene, brief) |
| In-raid HUD: numerals, key caps, ability bars, slot squares, loot toasts, intro card | `ui/hud.gd` (`_draw_overlay`, `_play_intro`, `_on_backpack_changed`) |
| How far enemies hear, and what they do about it | `Catalog.WEAPONS` `noise`, `Enemy.hear`, `Squad.report_noise` |
| How many fire at once, and the gap between bursts | `Squad.MAX_SHOOTERS`, `FIRE_GAP`, `max_tokens` |
| How shaken a squad gets by losses | `Squad.caution`, `report_death`, `Enemy.take_cover` |
| Fullscreen, window sizes, render scale | `GameManager._apply_display`, `WINDOW_SIZES` |
| Where loot containers are, and how they look | `_mark(...)` calls in `level.gd`; `LootContainer._ready` |
| Reinforcement waves, heat, alarm response | `Raid._escalate`, `send_reinforcements`, `WAVES`; entry points in `Level.reinforce_points` |
| Reverb, limiter, ambience bed | `Sfx._build_buses`, `start_ambience` |
| Equipping a weapon found mid-raid | `GameManager.wield_found`, `Player.add_gun` |
| Wearing armour found mid-raid | `GameManager.wear_found`, `Pickup.interact`, `Player.refresh_build` |
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

- Played once by an outside tester; the balance changes made in response are untested by a person.
- Aster City has not been played by a person. Its buildings have one door each, so the
  rooms are dead ends; upper floors of the towers are skyline only.
- Cairn Divide has not been played by a person. Unknown: whether fights across the open
  shelves are fair with this little cover, whether guards cope with stairs and the upper
  walkways in a real fight, how the houses' glass walls play (glass stops shots), whether
  55 guards and 1,500 trees hold the frame rate, and whether you can get stuck in the
  river gorge (its sides are steep and nothing lifts you out).
- Cairn Divide's guard posts and rock shelters were placed by rule and only two were looked
  at. A post on a slope stands on a tall concrete block; a shelter's way in may be tight.
- Guards never leave their colony or post, so nothing hunts you on the trails yet. Drone
  drops and roaming patrols are the planned next step.
- Relay Station has no corner map.
- Aster's outer sites were laid out by rule. Not checked by eye: Saltglass, Northwatch,
  Southshore; whether an added building ever blocks a road; whether the cover in each
  street is enough. The buildings added are the same three models as the town's.
- The user asked for the town's buildings to look more like a future colony and less
  like apartment blocks. Done as a finish, not as new models: `VesperKit.FINISH` re-tunes
  the kit's HQ_ materials (pale hull, dark glass with a faint glow, lit accent stripes)
  and `AsterLevel._colony_gear` adds a lit band under each roofline, masts, radomes and
  solar wings. The shapes are still the kit's three blocks and one tower.
- Doors, gates and grass (2026-11-16) are checked by `maptest` only. Unknown until played:
  whether guards opening doors reads as a warning or as noise, whether 33 guards on the
  bigger map is too many, and the frame rate with grass on a slower machine.
- Aster City draws about 5 M triangles a frame, nearly all of it the kit's buildings (the
  grass is about 0.3 M). The kit's towers are 84,000 triangles each with no lower-detail
  version; that is the first thing to fix if the map runs slowly.
- Ideas not built for "make it feel alive": loose props that can be knocked over, birds
  that scatter at gunfire, banners that move in the wind, doors on Relay Station.
- Kestrel has no crouch, jump, aim or death clips; crouch squashes the model.
- First-person arms are capsules, not Kestrel's real arms. No weapon inspect/equip
  animation, no melee.
- Enemy bodies are code-built; their crouch doesn't lower their hit capsule.
- All audio is synthesized placeholder. No music, no voices.
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
