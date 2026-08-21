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
3. Basic hostile AI (patrol → detect → chase → shoot) so raids have threat. — **done**
4. Everything else.

Steps 1–3 are the MVP. Step 2 is what makes this an *extraction* shooter rather than a
top-down shooter with no stakes, so it comes before any more combat polish.

## Where the project is now

Combat works; the loop doesn't exist yet. Everything below is playable in `main.tscn`.

### Built and working

- **Input pipeline.** `input_frame.gd` defines the `InputFrame` struct.
  `player_input_source.gd` is the only place in the project that reads `Input` or the
  mouse. `movement.gd` (`Movement.apply`) is the only place that touches `velocity` or
  `rotation`. The player and the AI both produce `InputFrame`s and both move through
  `Movement.apply` — rule 1 below, in practice rather than in theory.
- **Player** (`player.gd`). WASD movement, faces the mouse cursor continuously,
  auto-fires while left mouse is held. Has health and `take_damage()`, and emits `died`
  at 0 HP — which nothing consumes yet, so the player currently plays on past death.
- **Shooting** (`weapon.gd`, `bullet.gd`). `Weapon` owns fire-rate timing and bullet
  spawning and is shared by the player and the AI, so both fire by identical rules.
  `Bullet` is an `Area2D` built entirely in code — no `.tscn` — drawn as a white line
  by `_draw()`. Its collider is deliberately sized to cover a full physics tick of
  travel so fast shots can't tunnel past a target between frames. Damage is routed by
  `has_method("take_damage")`, not by class or group, so anything damageable works
  without editing `bullet.gd`.
- **Enemy AI** (`enemy.gd`). Seeded wander around its spawn point; on spotting the
  player *or* being shot it commits to CHASE for at least `min_chase_time`, holds a
  ring at `orbit_radius`, strafes along it with a randomized direction flip, and fires
  with seeded spread. Has health, dies, emits `died`.
- **Seeded randomness** (`game_manager.gd`). `GameManager.rng` is seeded from
  `run_seed`; each enemy derives its own stream from it at `_ready`. It is currently
  seeded to 0, so every run plays out identically — good for debugging. Call
  `seed_run(randi())` from `start_new_run()` when raids should vary.

### Not built yet

Everything the extraction loop needs. These are still the original scaffold stubs with
`TODO` comments and `pass` bodies — treat the comments inside them as the spec:

- `game_manager.gd` — `extract_success()`, `player_died()`, `start_new_run()`
- `extraction_zone.gd` — the hold timer
- `loot_item.gd` — pickup
- `hud.gd` — loot count and extraction countdown

Also absent: stash persistence to disk, any menu or results scene, any map beyond
`main.tscn`, and any consumer for the `died` signals on either the player or enemies.

### Known shortcuts

Fine for now, but don't mistake them for finished work:

- **Everything is on collision layer 1.** Self-hits are prevented by `Bullet.shooter`
  and friendly fire by `Bullet.ignore_group`, not by layers. Real named layers
  (player / enemy / bullet / world) are worth doing once there's level geometry.
- **Enemy detection is pure distance** — no line of sight, so they "see" through walls.
  There are no walls yet, so nothing is wrong today.
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
main.tscn            # the raid scene — player, enemies, nothing else yet
player.tscn
enemy.tscn
icon.svg             # placeholder sprite for both player and enemies
project.godot
scripts/
  autoload/
    game_manager.gd  # registered as the GameManager autoload
  bullet.gd  enemy.gd  hud.gd  input_frame.gd  loot_item.gd
  movement.gd  player.gd  player_input_source.gd  weapon.gd
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
