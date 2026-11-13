class_name InputFrame
extends RefCounted

# One tick of intent. Produced by the keyboard and mouse today; a replay or a
# network packet could produce the same thing later. Whatever fills this in is
# never the thing that acts on it (rule 1).

# x = strafe (right positive), y = forward (forward positive). Length 0..1.
var move: Vector2 = Vector2.ZERO
# Radians to turn this tick: x = yaw, y = pitch.
var look: Vector2 = Vector2.ZERO

var jump: bool = false
var sprint: bool = false
var crouch: bool = false
var shoot: bool = false          # trigger held
var shoot_pressed: bool = false  # trigger went down this tick
var aim: bool = false
var reload: bool = false
var interact: bool = false       # held
var tactical: bool = false
var prime: bool = false
var heal: bool = false
var weapon_slot: int = -1        # 0 / 1 to pick a slot, -1 for no change
var weapon_next: bool = false
