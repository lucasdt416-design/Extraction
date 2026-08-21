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

1. Player movement + aiming + shooting that feels decent.
2. The extraction loop end to end: insert → pick up items → extract zone → stash persists.
3. Basic hostile AI (patrol → detect → chase → shoot) so raids have threat.
4. Everything else.

Steps 1–3 are the MVP. *(Assumption on my part — say so if you'd rather reorder.)*

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

```
scenes/      # .tscn files
scripts/     # .gd files
assets/      # art, audio, fonts
  models/
  textures/
  audio/
addons/      # third-party plugins
```

Create these as needed — most don't exist yet. Keep `res://` root clean.

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
