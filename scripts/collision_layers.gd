class_name CollisionLayers
extends RefCounted

# The one place the physics layer numbers are written down. Names for these live
# in project.godot under [layer_names], so the inspector shows "world / player /
# enemy / bullet" instead of "Layer 1..4".
#
# .tscn files can't reference these constants -- a scene stores a raw integer --
# so the bodies set their layer and mask in the inspector and only code that
# casts rays (Hitscan shots, Enemy sight) uses these. If you renumber anything
# here, the scenes have to move with it.

const WORLD: int = 1 << 0    # 1 -- walls; anything solid, static and sight-blocking
const PLAYER: int = 1 << 1   # 2
const ENEMY: int = 1 << 2    # 4
# Nothing occupies this today -- shots are hitscan rays, not bodies -- but the
# number is named in project.godot and reserved for anything projectile-shaped
# we add later (grenades, rockets).
const BULLET: int = 1 << 3   # 8

# Everything a shot is allowed to stop on. Note this includes ENEMY and PLAYER
# both: shots do NOT filter friendly fire by layer, because the player and the
# AI share one Weapon. That's Hitscan's shooter/ignore_group arguments' job.
const SHOOTABLE: int = WORLD | PLAYER | ENEMY
