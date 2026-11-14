# PLAN.md

Where this game is going, in what order, and how to work on it. Written so a different
model (or person) can pick the project up cold. Read `CLAUDE.md` for the rules and
`BUILD.md` for what exists. Last updated 2026-11-13.

## The target, stated honestly

The owner wants a first-person extraction shooter with the polish, immersion and
atmosphere of a studio game like Marathon. That game took hundreds of people several
years. What two people and an AI can reach is **a small game with one strong, consistent
look and a tight loop**: think a striking indie, not a AAA clone. Aim there on purpose.
A small thing finished to a high standard beats a big thing at placeholder quality.

Reference games are for mechanics and quality bar only. Names, factions, characters and
visual identity are our own (see Kestrel).

**Where we are against that bar:** systems are ahead of presentation. The loop, AI, saves
and tooling are solid foundations. Art, animation and sound are placeholder-grade, and
nobody has played it.

## What limits quality right now (in order)

1. **It has never been played.** Every number is a guess. This is the cheapest and most
   valuable thing to fix.
2. **Sound.** Synthesized beeps and noise. Sound is about half of immersion in a shooter
   and currently contributes almost nothing.
3. **Animation.** No reloads worth the name, no hit reactions, no crouch/jump/death on
   Kestrel, capsule arms.
4. **Environment art.** Boxes with a good shader and good lighting. Reads as a blockout.
5. **Interface.** Functional and clean, but no identity and no inventory depth.
6. **Content.** One map, five guns, six enemies.

Note the order: more maps and more guns are last. Adding content at the current
presentation level multiplies placeholder work that will be redone.

## Who should make what

Code-built art has a ceiling, and we are near it. Past here, quality comes from real
assets, and those are better made elsewhere:

| Work | Best done by | Why |
|---|---|---|
| Concept art, style frames | Image model (ChatGPT) | This model cannot generate images |
| Characters, weapons, props, environment kit as `.glb` | ChatGPT's Blender pipeline, or another asset tool | It produced Kestrel; Blender isn't installed on the dev Mac |
| Textures | Image model, or keep generated/shader-based | |
| Sound effects, ambience, music | Sourced CC0 libraries or an audio tool | Synthesis can't get there |
| Map layout, cover, sightlines, pacing | **Here** | It's design logic, and it needs the AI and navmesh |
| Lighting, shaders, post, effects | **Here** | |
| Gameplay, AI, UI code, saves, tooling | **Here** | |
| Integrating and checking every asset | **Here** | Scale, pivots, materials, animation hookup |

So: yes, hand environment *pieces* and weapon *models* to ChatGPT or another asset tool.
Do not hand over whole maps. Ask for a **modular kit** (walls, floors, doors, railings,
props on a 1 m grid) and assemble the map here, where cover, navigation and enemy
placement can be tested. Give every asset request the contract in `BUILD.md`, plus one
concept image for the look.

## Roadmap

Each phase ends with something playable and a merged PR. Don't start a phase before the
previous one's exit test is met.

### Phase 0 — Land it and play it  *(now)*
- Merge PR #1, then open and merge `graphics`.
- Install Godot 4.7. Play three raids. Write down everything that feels wrong.
- **Exit:** a punch list from real play exists.

### Phase 1 — Feel
The game has to feel good with boxes before art is worth buying.
- ~~Settings screen: mouse sensitivity, FOV, volume, graphics quality.~~ Done (`settings` branch).
- Fix the punch list: movement, recoil, time-to-kill, AI aggression and accuracy.
- Hit feedback: enemy stagger on headshots and heavy hits is done; clearer kill confirm still to do.
- Real sound, first pass: guns, footsteps per surface, impacts, ambience bed.
- **Exit:** the owner plays ten raids and wants an eleventh.

### Phase 2 — Vertical slice
One small area at final quality, to prove the look before building more.
- Lock a one-page style guide from Kestrel's palette (white / graphite / acid / coral).
- Environment kit v1 from outside; rebuild **only the lab** with it.
- Two weapons as real models with reload animations on Kestrel's actual arms.
- Kestrel clips: crouch, jump, aim, death. Enemy model in the same family.
- **Exit:** a screenshot of the lab that the owner would put on a store page.

### Phase 3 — The map
- Decide: keep levels as code, or move to editor scenes built from the kit. Recommended:
  **scenes**, so both people can edit in Godot. Keep `level.gd`'s lists (squads,
  containers, extracts) as marker nodes.
- Rebuild Relay Station with the kit. Add vertical play, interiors with real props.
- Then a second map with a different shape (tight interior vs. the open compound) to
  prove the squad AI holds up outside the layout it was tuned on.
- **Exit:** two maps, both pass `selftest`, both fun.

### Phase 4 — Depth
- Extraction variety: one-use exits, exits that need a key item or a fee, a late exit
  that opens when the clock is low, a loud exit that calls enemies.
- Raid goals: contracts ("recover the drive from the vault") with payouts.
- Weapons: attachments, ammo types, a melee, three or four more guns.
- Enemies: reinforcements on alarm, a second faction, a boss room.
- Inventory: grid, item sizes, secure pouch, insurance.
- Progression: trader levels, frame upgrades.

### Phase 5 — Interface and identity
- Redesign HUD and menus to the style guide. Title, logo, loading screens, map screen.

### Phase 6 — Co-op
- Two players vs AI, host-authoritative. The network-readiness rules in `CLAUDE.md`
  exist so this is a spike, not a rewrite.

## How to work in this repo (cheat sheet)

### The loop for any change

1. Read `CLAUDE.md` (rules) and the file you're about to touch. Don't guess at APIs you
   wrote three sessions ago.
2. Branch from the newest branch. One job per PR; the owner dislikes stacked PRs, so if
   the base isn't merged, push the branch and hold the PR.
3. Make the change. Tuning numbers go in `Catalog`, not scattered through scripts.
4. `--import` headless. This is the parse check; fix everything it prints.
5. `selftest` headless. Must end `SELFTEST OK`. If you added a system, add a check.
6. If it's visible, run `shots` and **look at the images**. Do not judge visuals from code.
7. Commit with what changed and why. Push. Update `BUILD.md` if the build changed.
8. Say plainly what was run and what still needs a person to play.

### Getting Godot

Not on PATH. Download the macOS build into a scratch folder and call the binary directly:

```sh
gh release download 4.7.2-stable -R godotengine/godot -p 'Godot_v4.7.2-stable_macos.universal.zip'
unzip -q Godot_v4.7.2-stable_macos.universal.zip
./Godot.app/Contents/MacOS/Godot --version
```

Windowed runs (screenshots) briefly open a window on the owner's screen. That's fine.

### Traps already hit

- **`class_name` clashes with built-ins fail quietly.** `Container` is a Godot class;
  ours is `LootContainer`. Check before naming.
- **Typed arrays and ternaries:** `var a: Array[int] = x if c else y` errors at runtime.
  Use an untyped `Array` and type the loop variable.
- **`Label` positions:** after `set_anchors_preset`, set `offset_*`, not `position`.
- **The use-key latch:** holding F must still pick up an item you sweep onto; only
  re-latch after a completed interaction.
- **Navmesh timing:** bake after all colliders exist, then wait two physics frames
  before anything queries it.
- **Roofs** must not be on the navmesh-source layer, or enemies path onto them.
- **Never run tools without `--test-profile`.** They reset and rewrite the save.
- **A raid scene run directly** (not via the menu) has `GameManager.in_raid == false`;
  code that reads `last_result` must tolerate it being empty.
- **Frame-rate readings lie** when the test window isn't frontmost. Compare triangle and
  draw-call counts instead.
- **`.gd.uid` files are committed.** `.godot/` never is.
- **Every script that reads `Input`** other than `PlayerInputSource` breaks rule 1.
  UI may react to input *events* (pause), nothing else.
- **Glow blooms bright albedo.** Saturated light colours near white will glow; raise the
  threshold or darken the material rather than adding effects to hide it.

### Judging quality

- Take the screenshot, then ask: what is the weakest thing in this frame? Fix that one.
  Repeat. Don't add a new effect while something on screen still looks broken.
- Remove before adding. The owner dislikes interfaces that look AI-made: no decorative
  icons, no boxes round everything, plain words, restraint.
- Lighting and materials do more than geometry. Bevels, a painted band on walls, grime
  at the floor, and a sky with something in it moved this further than any model would.
- Performance is part of quality. After a visual change, check the triangle count.

### Judging AI

The enemy AI is tuned by rules, not by feel, so check the rules still hold:

- A player standing in the open courtyard should die in roughly 6–10 s (`tools/sim`).
- Nothing should spot the player at the spawn point in the first seconds (`selftest`).
- Only `Squad.max_tokens()` enemies fire at once unless the player is inside 8 m.
- Enemies act on `squad.last_known`, never on the player's true position, except while
  they have line of sight.
- Every coordinated decision produces a bark. If you add a behaviour, add its line.

### Working with outside assets

- Assets from ChatGPT land in `~/Documents/ChatGPT/extraction/assets/`, a separate
  folder. Read its handoff note, then **copy** files into `assets/` here; don't run its
  scripts.
- After copying: `--import`, then inspect the node tree, bones, clips and materials
  before writing code against them. Names with dots become underscores in Godot.
- Wrap each imported model in one small script (see `kestrel_body.gd`) so the rest of
  the game doesn't know about its node tree.

### When to stop and ask

- Reversing anything in `CLAUDE.md`'s "Decisions already made".
- Adding networking, a backend, or any paid/external service.
- Deleting or rewriting the other collaborator's work.
- Importing assets with unclear licences.
Otherwise: decide, do it, say what you chose.
