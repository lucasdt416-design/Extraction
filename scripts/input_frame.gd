class_name InputFrame
extends RefCounted

# One tick of intent. Produced by a keyboard, by AI, or later by a replay or a
# network packet -- whatever produces it is never the thing that acts on it.
# See CLAUDE.md rule 1.

# Desired movement direction, length 0..1 (0 = stand still).
var move: Vector2 = Vector2.ZERO

# Desired facing, unit length. Zero means "keep facing where you already are".
var aim: Vector2 = Vector2.ZERO

var shoot: bool = false
var interact: bool = false
