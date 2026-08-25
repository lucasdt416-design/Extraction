# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this project is

A **simple 2D top-down extraction shooter** built in **Godot 4.7** with **GDScript**
(standard build, not .NET — ignore the leftover `[dotnet]` block in `project.godot`).

Two people are building it over a few weeks. The goal is a small, complete, *playable*
game we can expand later — not a broad engine of half-finished systems. When choosing
between "more features" and "the loop actually works", pick the loop.

### The core loop

```
Menu ─▶ Insert into raid ─▶ [ loot, fight ] ─▶ Reach extract zone (hold N seconds) ─▶ Stash
                                    │
                                    └─ die ─▶ lose everything you were carrying
```

Persistent stash between raids is what makes it an *extraction* shooter rather than a
top-down shooter. It's core, not a stretch goal.

### Build order

1. Player movement + aiming + shooting that feels decent. — **done**
2. The extraction loop end to end: insert → pick up items → extract zone → stash persists.
   — **not started, and now the critical path**
3. Basic hostile AI (patrol → detect → take cover → peek and shoot) so raids have
   threat. — **done**
4. Everything else.

Steps 1–3 are the MVP. Step 2 is what makes this an *extraction* shooter rather than a
top-down shooter with no stakes, so it comes before any more combat polish.

## Where the project is now

Combat works and now has cover to fight around; the extraction loop doesn't exist yet.
Everything below is playable in `main.tscn`, which is currently a player, two
hand-placed enemies, one enemy spawner and six walls in otherwise empty space — no loot,
no extract zone, no HUD.

### Built and working

- **Input pipeline.** `input_frame.gd` defines the `InputFrame` struct.
  `player_input_source.gd` is the only place in the project that reads `Input` or the
  mouse. `movement.gd` (`Movement.apply`) is the only place that touches `velocity` or
  `rotation`. The player and the AI both produce `InputFrame`s and both move through
  `Movement.apply` — rule 1 below, in practice rather than in theory.
- **Player** (`player.gd`). WASD movement, faces the mouse cursor continuously,
  auto-fires while left mouse is held. Has health and `take_damage()`. At 0 HP it sets
  `is_dead`, emits `died`, and calls `GameManager.player_died()`. After that it keeps
  feeding an empty `InputFrame` through `Movement.apply` rather than skipping the call,
  so the body settles through the one path allowed to touch `velocity`. The corpse stays
  in the raid and enemies go on shooting at it; only this client's view goes black.
- **Camera** (`player_camera.gd`). A `Camera2D` child of the player body, so it moves on
  the physics tick in lockstep with what it follows rather than a frame behind it.
  `ignore_rotation` is forced on in code — without it the whole world would spin every
  time the mouse moved, since the player rotates to face the cursor. Note that
  `player.tscn` sets `position_smoothing_speed = 8.0` but leaves
  `position_smoothing_enabled` at its default `false`, so the camera is rigid today and
  that speed does nothing; tick the box in the inspector if you want the lag.
- **Shooting** (`weapon.gd`, `hitscan.gd`, `tracer.gd`). Shots are **hitscan**: there
  is no projectile node and no travel time. `Hitscan.resolve()` casts one ray along
  the aim line and returns the first body that stops it, passing through the shooter
  and through up to `MAX_PASS_THROUGH` bodies in the weapon's `ignore_group`. Shots
  ignore `Area2D`s entirely (`collide_with_areas = false`), so loot pickups and the
  extract zone will never stop one. `Weapon` owns fire-rate timing and applies the
  damage, and is shared by the player and the AI, so both fire by identical rules.
  Because a shot resolves on the tick it is fired, nothing can tunnel past a target
  between frames. Damage is routed by `has_method("take_damage")`, not
  by class or group, so anything damageable works without editing `weapon.gd`.
  `Tracer` is the only visual: a white streak along the resolved path that fades over
  `tracer_lifetime` seconds and frees itself. It has no collider and decides nothing;
  set `tracer_lifetime` to 0 and no tracer is spawned.
- **Enemy AI** (`enemy.gd`). Seeded wander around its spawn point; on spotting the
  player *or* being shot it commits to CHASE for at least `min_chase_time`, and then
  **fights from cover** rather than closing in. Inside CHASE there are two stances,
  and the burst clock is the only thing that switches between them: in `COVER` it
  sits on a spot the player has no line to and holds fire while the next burst winds
  up; the moment the burst is loaded it flips to `PEEK`, steps out of cover, sprays
  it, and drops straight back behind the wall. Fire is **burst-based**: `burst_size`
  shots `burst_shot_interval` apart, at 25° of seeded spread, then a
  `burst_delay_min`–`burst_delay_max` pause rolled from the enemy's own stream. The
  pause is armed before the first burst too, so being spotted buys you a second or
  two before anything is coming at you, and it runs down *behind cover* — that pause
  is what the enemy spends hidden. Cover spots are found by sampling rings around
  the enemy (`cover_search_*`) and keeping the cheapest one where the line to the
  player is blocked and the line from the enemy is not; the peek spot is the nearest
  step sideways along that wall (`peek_offset`, alternating shoulders) that opens a
  firing line. Cover is re-checked every `cover_recheck_interval` and abandoned if
  the player walks somewhere that can see it, if the walk there stalls
  (`cover_leg_timeout`), or if a peek produces no line within `peek_timeout` — in
  which case the loaded burst is dumped and it repositions. With no usable cover
  anywhere it falls back to holding `preferred_range` in the open, on the same burst
  rhythm. The give-up clock is frozen while it deliberately holds cover, so an enemy
  can't forget you mid-reload; it only runs while patrolling or exposed on a peek.
  Has health, dies, emits `died`. A dead enemy is not freed: it stays put as an inert
  red corpse with its collision layer and mask zeroed, so shots pass through it and the
  living can walk over it — which also means corpses provide no cover.
- **Enemy spawners** (`enemy_spawner.gd`, `enemy_spawner.tscn`). A `@tool` `Node2D`
  marker that repopulates its own spot. Two clocks: `spawn_interval` (300s) counts down
  from each spawn, and `observation_cooldown` (60s) is how long the spot must have been
  clear of the player — anywhere inside `observation_radius`, distance only, no
  sightline — before an armed spawner may fire. `initial_spawn_delay` is 0, so a fresh
  map populates on the first tick rather than starting empty. An armed spawner that is
  being watched *stays* armed rather than restarting its interval, so camping a corner
  costs the player one spawn's delay, not a whole map's worth, and nothing ever appears
  in front of them. `max_alive` (2) caps living enemies per spawner; corpses don't hold a
  slot, since `is_dead` enemies stay in the tree. Spawned enemies are parented to the
  spawner's parent (or `spawn_container_path`), positioned *before* `add_child` so
  `Enemy._ready()` reads the spawn point as its patrol home. `show_debug` draws the
  radius in game (amber = watched, green = cold) and prints each spawn; the marker and
  radius are always drawn in the editor.

  **Spawners are how enemies get into a map from here on.** Dropping an `Enemy` into a
  scene by hand is the old way: it gives one enemy, once, and an emptied-out map stays
  empty for the rest of the raid, which is the wrong shape for raids you're meant to
  spend time in. Place `enemy_spawner.tscn` instead and let it own the population. The
  two hand-placed enemies still in `main.tscn` are leftovers from before this existed
  and should be replaced with spawners; don't add more of them.
- **Walls** (`wall.gd`, `wall.tscn`). A `@tool` `StaticBody2D` on the `world` layer with
  its mask at 0 — it stops things, it never looks for them. One `size` export drives both
  the drawn rectangle and the collider, so the art and the collision can't drift apart,
  and the `RectangleShape2D` is `resource_local_to_scene` so resizing one wall doesn't
  resize every wall. They are gameplay rather than scenery: they stop shots, block enemy
  sight, and are what the AI hides behind. **Resize with the `Size` property, never the
  editor's drag handles** — the handles write `scale`/`skew` on the node, and Godot's 2D
  physics cannot collide a skewed or unevenly scaled shape, so bodies that touch such a
  wall get ejected to one of its corners. `_bake_transform()` folds any such transform
  back into `size` when the scene loads and `_get_configuration_warnings()` flags one in
  the meantime, so the state is self-healing, but the handles still aren't the way to do
  it. `main.tscn` has six walls.
- **Collision layers** (`collision_layers.gd`, named in `project.godot`).
  `world` is walls, and it is also what blocks enemy sight; `player` and `enemy`
  collide with the world and with each other; `bullet` is currently unused, since
  shots are rays rather than bodies. Scenes set their own layer/mask in the
  inspector — a `.tscn` stores a raw integer and can't reference the constants, so
  the two have to be renumbered together.
- **Line of sight** (`enemy.gd`). `_line_clear(from, to)` is the one place a sightline
  is decided, so awareness, cover choice and peek angles can never disagree about what
  counts as a wall. One raycast per enemy per tick tests the player and is cached in
  `_has_los`; the cover search casts more, but only when the cover it has goes bad.
  Enemies only notice the player down a clear line, hold fire when the line breaks,
  and give up `min_chase_time` after losing contact rather than after a fixed
  commitment. Being shot from out of sight still pulls them into CHASE.
- **Seeded randomness** (`game_manager.gd`). `GameManager.rng` is seeded from
  `run_seed`; each enemy derives its own stream from it at `_ready`. It is currently
  seeded to 0, so every run plays out identically — good for debugging. Call
  `seed_run(randi())` from `start_new_run()` when raids should vary.

### Not built yet

Everything the extraction loop needs. These are still the original scaffold stubs with
`TODO` comments and `pass` bodies — treat the comments inside them as the spec:

- `game_manager.gd` — `extract_success()` and `start_new_run()` are the only TODOs left
  in it, and most of what they need is already there: `current_run_loot`, `stash`,
  `add_loot_to_run()` (the one place carried loot is mutated — rule 2), the
  `local_player_died` signal, and `clear_death_screen()`. `player_died()` is done: it
  clears carried loot and raises a local black "You died" overlay while the raid keeps
  simulating — see `death_screen.gd`. `stash` is an in-memory `Array` that nothing
  writes to disk.
- `extraction_zone.gd` — the hold timer. `_on_body_entered`/`_on_body_exited` already
  track `player_inside`, but `_process` counts nothing.
- `loot_item.gd` — pickup. `_on_body_entered` is an empty `pass`.
- `hud.gd` — loot count and extraction countdown.

Note that **none of those three scripts has ever run**: there is no `hud.tscn`, no loot
scene and no extraction-zone scene, so nothing in `main.tscn` instantiates them. `hud.gd`
additionally expects `LootLabel` and `TimerLabel` children that don't exist anywhere yet,
and both `Area2D` scaffolds expect their `body_entered`/`body_exited` signals to be wired
up in the editor.

Also absent: stash persistence to disk, any menu or results scene, any map beyond
`main.tscn`, any way to restart after dying (`GameManager.clear_death_screen()` is the
hook, and nothing calls it), and any consumer for the enemies' `died` signal.

### Known shortcuts

Fine for now, but don't mistake them for finished work:

- **Friendly fire is filtered in code, not by layers.** Named layers exist now
  (`world` / `player` / `enemy` / `bullet`, see `collision_layers.gd`), but a shot
  still masks *both* factions (`CollisionLayers.SHOOTABLE`) and spares its own side
  via `Hitscan.resolve()`'s `shooter` and `ignore_group` arguments — because the
  player and the AI share one `Weapon`.
- **Line of sight is a single centre-to-centre ray.** No corner peeking: an enemy
  is either fully aware of you or fully blind, and a player standing half-exposed
  at a corner reads as hidden. Three rays (centre + both flanks) is the usual fix
  if it starts to feel wrong.
- **Enemies walk to cover in a straight line.** There is no navmesh and no
  pathfinding, so a cover spot only counts as reachable if the direct line to it is
  clear, and getting there is `move_and_slide` scraping along whatever it hits.
  That rules out perfectly good cover round a corner, and `cover_leg_timeout` is
  what unsticks the cases the straight line gets wrong. A `NavigationAgent2D` is the
  real fix if the maps stop being one open room.
- **Cover is judged from one point, for one player.** A spot is "cover" if the
  centre-to-centre line to the player is blocked right now, so it says nothing about
  a second enemy's angle, and nothing about where the player is about to walk.
- **Input map** has `move_left/right/up/down` (WASD) and `shoot` (left mouse). There is
  no `interact` action yet; `loot_item.gd` will need one.
- `README.md` still has a placeholder title (`[Your Game Name]`) and no screenshot.

## Decisions already made

These were deliberate. Don't quietly reverse them; raise it with the user first.

| Decision | Choice | Why |
|---|---|---|
| Dimension | **2D top-down** | Fastest path to playable. Placeholder art is rectangles. |
| Players | **Single-player, network-shaped** | Offline now, structured so co-op can be added later. |
| Eventual MP target | **Co-op (you + a friend vs AI)**, host-authoritative | Achievable for two people. |
| PvP | **Explicitly not a goal** | Needs a real backend, server-side stash, and anti-cheat. |
| Physics | Godot 2D physics | The `3d/physics_engine="Jolt Physics"` line in `project.godot` is a leftover default and is irrelevant to a 2D game. |

## Network-readiness rules

**The project is single-player. Do not add networking code** — no `@rpc`, no
`MultiplayerSynchronizer`, no `ENetMultiplayerPeer`, no authority checks. Adding them
now buys nothing and costs momentum.

Instead, follow these structural rules. They cost ~nothing today and are what makes
co-op a spike rather than a rewrite later. They're also just good hygiene: they give us
AI reuse, replays, and testable gameplay regardless of whether MP ever ships.

**1. Input is data, produced once and consumed anywhere.**

Never read `Input` at the point where you act on it. Gather it into a struct, then feed
that struct to the controller. The same controller can then be driven by a keyboard, by
AI, by a replay — or later by a packet.

```gdscript
# Good
class_name InputFrame extends RefCounted
var move: Vector2
var aim: Vector2
var shoot: bool
var interact: bool

func _physics_process(_delta: float) -> void:
    controller.tick(input_source.poll())

# Bad — input read inline, state mutated inline, client asserts a fact
func _physics_process(delta):
    velocity = Input.get_vector("left","right","up","down") * SPEED
    if Input.is_action_just_pressed("interact"):
        inventory.append(item)
```

**2. One place mutates each piece of authoritative state.** Inventory, health, stash and
loot changes go through their owning system. No scattered `inventory.append()` call sites.

**3. Gameplay runs in `_physics_process`,** on the fixed tick — not `_process`. Use
`_process` for visuals and UI only.

**4. Randomness is seeded and owned.** Loot rolls, weapon spread and crits derive from a
`RandomNumberGenerator` we control, not bare `randf()`. Later this is what lets host and
client agree.

**5. No absolute node paths that assume one player.** `get_node("/root/World/Player")`
breaks the moment there are two. Use exported `NodePath`s, signals, or groups.

**6. No gameplay logic in UI scripts.** UI reads state and emits intent; it never decides
outcomes.

## Project layout

What actually exists today:

```
main.tscn            # the raid scene — 1 player, 2 hand-placed enemies (legacy,
                     # replace with spawners), 1 spawner, 6 walls; no loot,
                     # no extract zone, no HUD
player.tscn          # body + collider + sprite + the player camera
enemy.tscn
enemy_spawner.tscn   # placeable spawn point — the way enemies get into a map
wall.tscn            # placeable solid rectangle; size drives its own collider
                     # resize with Size, never the drag handles — see wall.gd
icon.svg             # placeholder sprite for both player and enemies
project.godot
scripts/
  autoload/
    game_manager.gd  # registered as the GameManager autoload
  collision_layers.gd  death_screen.gd  enemy.gd  enemy_spawner.gd
  hitscan.gd  hud.gd  input_frame.gd  loot_item.gd
  movement.gd  player.gd  player_camera.gd  player_input_source.gd  tracer.gd
  wall.gd  weapon.gd
  extraction_zone.gd
```

Where it's heading, as the project grows:

```
scenes/      # .tscn files
scripts/     # .gd files
assets/      # art, audio, fonts
  models/
  textures/
  audio/
addons/      # third-party plugins
```

Create these as needed. The `.tscn` files still sit at `res://` root; move them into
`scenes/` from Godot's own FileSystem dock rather than on disk, so it can fix up the
resource paths for you.

## Conventions

- **Static typing everywhere**: `var speed: float = 300.0`, `func fire() -> void:`.
  Godot's typed GDScript is meaningfully faster and catches real errors.
- `snake_case` for files, variables and functions; `PascalCase` for classes and nodes.
- Prefer `class_name` on scripts that are referenced elsewhere.
- Signals over polling; `@export` over hardcoded tuning values so the designer-facing
  numbers live in the inspector.
- 2D specifics: `CharacterBody2D` for player and enemies, `TileMapLayer` (not the
  deprecated `TileMap`) for levels, `Area2D` for loot pickups and extract zones.

## Working in this repo

**The user is writing the gameplay code now — don't write it for them.** The default
mode is advice, not edits: answer the question, show the shape of the solution as a
short snippet in chat, name the trap they're about to walk into, and leave the files
alone. A snippet that illustrates a pattern is not the same as implementing the feature,
and the first is what's wanted.

Edit files when asked to in the moment — "fix that", "make the change", "write this for
me". That's permission for *that* request, not a standing licence: go back to advising
on the next one. In particular, don't fill in `TODO`s, finish scaffolds, or tidy up
adjacent code just because it was open. Point it out in a sentence and let them decide.

This matters most for the extraction loop (build-order step 2), which is the part being
learned on. Explaining why a `Dictionary` beats a parallel array is the job; handing over
a finished `extraction_zone.gd` is not.

**Claude cannot run the game.** Godot is not on `PATH` in this environment, and a 2D
shooter can't be verified by reading code anyway. After making gameplay changes, tell
the user what to test and let them run it. Don't claim something works when it hasn't
been run.

**Never edit or commit `.godot/`.** It's machine-local cache, gitignored, regenerated.

**Be careful with `.tscn` and `.tres` files.** They're text and technically hand-editable,
but Godot writes them in a specific format with node paths and resource IDs that are easy
to corrupt. Prefer creating scenes' *scripts* by hand and letting the user wire up nodes
in the editor, unless the scene edit is small and obviously safe.

**Godot must be closed before the user pulls or switches branches** — it holds files open
and caches the scene tree. If they report phantom errors after a branch change, that's
usually the cause: close Godot, reopen.

See `README.md` for the git workflow (short-lived branches, small commits, PRs, and the
scene-file conflict procedure).

## Explicitly deferred

Not part of this project right now. Don't start building them; if one seems necessary,
raise it first.

- Any multiplayer or networking code
- PvP, matchmaking, lobbies, dedicated servers, anti-cheat
- Backend services or server-side persistence (stash saves to a local file)
- 3D anything
- Procedural map generation
- Meaningful art — placeholder shapes and colors are correct for now
