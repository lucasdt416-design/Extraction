# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this project is

A **first-person 3D extraction shooter** built in **Godot 4.7** with **GDScript**
(standard build, not .NET), fought against AI squads. It began as a 2D top-down
prototype; on 2026-11-13 the user moved it to 3D. The 2D version is still on `main`.

Two people are building it. The goal is a small, complete, *playable* game we can
expand later. When choosing between "more features" and "the loop actually works",
pick the loop.

It is an original game in the extraction-shooter genre. Other games are reference for
mechanics only: don't copy another game's names, characters, factions, art or look.

### The core loop

```
Menu (loadout, stash, trader, frame) -> Deploy -> [ loot, fight ] -> hold an extract point -> Stash
                                                        |
                                                        +- die / clock runs out -> lose backpack and equipped kit
```

## Where the project is now

The whole loop is playable end to end. Everything below was run through
`tools/selftest.tscn`; how it *feels* to play has only been judged from screenshots.

- **Flow and saves** (`autoload/game_manager.gd`). Owns credits, stash, loadout, frame,
  the raid backpack, the seeded RNG and scene changes. Saves to `user://profile.json`.
  Every change to those goes through a function there (rule 2).
- **Data** (`data/catalog.gd`). Items, weapons, frames, enemy archetypes, loot tables
  and trader stock as plain dictionaries. Balance changes happen here.
- **Player** (`actors/player.gd`). First-person controller: sprint, crouch, jump, ADS,
  two weapon slots, reload, recoil and bloom, regenerating shield over health, medkits,
  hold-to-use, and a frame's two abilities. Consumes one `InputFrame` per tick.
- **Kestrel** (`actors/kestrel_body.gd`, `assets/characters/kestrel/kestrel.glb`). The
  player character: a rigged android courier with Idle/Walk/Run clips. Used as the body
  you see looking down in first person (head and arms hidden), as a shadow-only copy so
  your shadow is complete, and on a turntable in the menu. Enemy bodies (`actors/rig.gd`)
  are still built in code, in the same design language.
- **Frames** (classes): Striker (Dash / Overcharge), Wraith (Cloak / Pulse), Mender
  (Stim / Fortify). Armor and two implant slots adjust stats.
- **Shooting** (`core/gun.gd`). Hitscan, shared by player and enemies: magazine, fire
  rate, reload, spread cone, pellets, damage falloff, headshots.
- **Enemy AI** (`actors/enemy.gd`, `actors/squad.gd`). See "How the AI works" below.
- **Map** (`world/level.gd`). "Relay Station": warehouse with mezzanine, lab with a
  vault, barracks, courtyard, container yard, two extract points. Hand-authored in code
  from boxes; bakes its own navmesh from its colliders.
- **Loot** (`world/loot.gd`, `world/loot_container.gd`). Crates, lockers and vaults
  (contents rolled from the seeded stream at build time; vaults trip an alarm), item
  pickups, drops from kills, limited backpack slots.
- **Extraction** (`world/extract_point.gd`), raid clock and win/lose (`world/raid.gd`).
- **Interface** (`ui/hud.gd`, `ui/menu.gd`, `ui/ui_kit.gd`). HUD with health/shield,
  ammo, abilities, detection meter, damage direction, extract markers, the enemy comms
  feed, pause and result screens. The menu is a title screen, then Play, Loadout, Trader, Frame and
  Settings over a live 3D staging bay with Kestrel in it.
- **Look and sound** (`fx/mats.gd`, `fx/shapes.gd`, `fx/fx.gd`, `actors/rig.gd`,
  `autoload/sfx.gd`, `shaders/`). No imported assets. Props, armour and weapons use
  bevelled meshes from `Shapes.rounded_box`. `shaders/surface.gdshader` gives walls and
  floors world-space panel seams, a painted band, grime and patchy wear;
  `shaders/sky.gdshader` draws the sky, clouds and ringed planet; `shaders/post.gdshader`
  is the lens (vignette, slight fringing, grain). The raid adds SDFGI, screen-space
  reflections, per-building reflection probes, volumetric fog, glow, auto exposure and
  drifting dust. Buildings get trim, lit windows, rooftop plant and painted lettering
  from `Level._dress_shell` / `_dress_site`. All sound is synthesized at startup.

### How the AI works

Individuals perceive and act; the `Squad` pools what they know and coordinates them.

- **Perception.** Sight is a cone plus a line-of-sight ray, feeding an awareness meter
  that fills faster the closer and more exposed you are (crouching, cloak and distance
  slow it). Noise (shots, sprinting, landing, vault alarms) is broadcast to the `enemy`
  group with a radius.
- **Last known position.** A squad fights where it last saw or heard you, not where you
  are. Break line of sight and they lose you, announce it, then search, then stand down.
- **Attack tokens.** Only two members (three with an Overseer) may fire at once; the rest
  reposition. A unit with you inside 8 m fires regardless.
- **Roles.** Anchors hold a firing spot and suppress your last position, flankers are
  rewarded for spots off to one side, pushers close in. Everyone pushes when you reload,
  heal or are badly hurt.
- **Position scoring** (`Enemy._decide`). Candidate spots on the navmesh are scored for
  range, cover (best is a spot it can fire over and duck behind), travel, crowding and
  flank angle.
- **Fairness.** Reaction delays are staggered, aim error starts wide and settles while
  it holds you in view, and bursts are followed by a pause and often a move.
- **Archetypes** (`Catalog.ENEMIES`): Trooper, Stalker (cloaked shotgun rusher), Bulwark
  (frontal shield), Marksman (charged shot with a warning beam), Grenadier (flushes you
  out of cover), Overseer (commander, extra token).
- **Barks.** Each coordinated decision is announced through the HUD comms feed, and
  nearby squads come to investigate a firefight.

### Known gaps

- Nothing has been play-tested by a person yet: balance numbers, recoil, movement feel
  and AI pacing are first guesses.
- One map, no reinforcements or respawning enemies during a raid.
- Enemies have no melee and don't use doors, ladders or jumps.
- Crouching doesn't lower an enemy's hit capsule; only the player's.
- No settings screen (sensitivity, volume, graphics quality). SDFGI and volumetric fog
  are on unconditionally, tuned on an Apple M5 Pro.
- First-person weapons are modelled per type with hands and a magazine-drop reload,
  but there is no melee and no inspect or equip animation.
- Kestrel has only Idle, Walk and Run clips: no crouch, jump, aim or death animation,
  so crouching squashes the body and there is no third-person death view.

## Decisions already made

Don't quietly reverse these; raise it with the user first.

| Decision | Choice | Why |
|---|---|---|
| Dimension | **3D, first person** | User's call on 2026-11-13, replacing the 2D prototype. |
| Players | **Single-player vs AI, network-shaped** | Offline now, structured so co-op can be added later. |
| Eventual MP target | **Co-op vs AI**, host-authoritative | Achievable for two people. |
| PvP | **Explicitly not a goal** | Needs a real backend, server-side stash and anti-cheat. |
| Physics | Jolt (Godot 3D), 120 ticks/s | Mouse look is applied on the tick, so it needs to be fine-grained. |
| Assets | **Imported only for the player character** | Kestrel is a rigged GLB in `assets/characters/kestrel/` (user's call, 2026-11-13). Everything else is primitives, generated textures and synthesized audio. |

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
var look: Vector2
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
project.godot
assets/characters/kestrel/   # kestrel.glb (rigged model) and its concept image
scenes/
  menu.tscn  raid.tscn        # a root node and a script each; everything else is built in code
scripts/
  autoload/  game_manager.gd  sfx.gd
  data/      catalog.gd
  core/      input_frame.gd  player_input_source.gd  gun.gd  layers.gd
  actors/    player.gd  kestrel_body.gd  enemy.gd  squad.gd  rig.gd  grenade.gd
  world/     raid.gd  level.gd  loot.gd  loot_container.gd  extract_point.gd
  fx/        mats.gd  shapes.gd  fx.gd
  ui/        hud.gd  menu.gd  ui_kit.gd
shaders/     surface.gdshader  sky.gdshader  post.gdshader
tools/       selftest.*  shots.*  bark_counter.gd   # development helpers, not shipped gameplay
```

### Tools

```
godot --headless --path . res://tools/selftest.tscn -- --test-profile
godot --path . res://tools/shots.tscn -- <output dir> --test-profile
```

`selftest` drives the player with a scripted input source through buying, equipping,
patrols, combat, looting, abilities, grenades, extraction and death, and prints
PASS/FAIL. `--test-profile` points saves at a throwaway file so the real profile is
never touched. Run it after changing gameplay code.

## Conventions

- **Static typing everywhere**: `var speed: float = 5.0`, `func fire() -> void:`.
- `snake_case` for files, variables and functions; `PascalCase` for classes and nodes.
- Prefer `class_name` on scripts referenced elsewhere. Don't pick a name Godot already
  uses (`Container` is taken; that's why it's `LootContainer`).
- Tuning numbers live in `Catalog` or as constants at the top of the script that uses
  them.
- Interface: plain wording, flat and square, no decorative icons or boxes. One accent
  (`UiKit.ACID`, from Kestrel) for the primary action and the active tab; coral for loss.
  Type comes from `UiKit.font`. Motion is quiet: fades, a sliding underline, camera drift.

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

**Run the checks, but feel is the user's call.** Godot is usually not on `PATH`. If a
Godot 4.7 binary is available, `res://tools/selftest.tscn` plays the core loop headless
and `res://tools/shots.tscn` saves screenshots (see Tools above). Neither can tell you
whether shooting or the AI *feels* right: after gameplay changes, say what was run and
what the user still needs to play to judge. Don't claim something works when it hasn't
been run.

**Never edit or commit `.godot/`.** It's machine-local cache, gitignored, regenerated.

**Scenes are built in code.** The two `.tscn` files are a root node with a script and
nothing else; the level, characters, HUD and menu are all assembled by their scripts.
Keep it that way unless the user asks otherwise: it keeps the whole game reviewable as
text and avoids hand-editing Godot's scene format.

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
- Procedural map generation
- Imported art or audio beyond the Kestrel character model — raise it before adding more
