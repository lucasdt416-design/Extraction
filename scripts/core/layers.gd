class_name Layers
extends RefCounted

# The one place the 3D physics layer numbers are written down. Named to match
# project.godot [layer_names].
const WORLD: int = 1 << 0     # level geometry: blocks movement, shots and sight
const PLAYER: int = 1 << 1
const ENEMY: int = 1 << 2
const INTERACT: int = 1 << 3  # loot, containers, extract points: found by the player's use-ray only

const SHOOTABLE: int = WORLD | PLAYER | ENEMY
