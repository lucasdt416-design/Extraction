class_name Steps
extends RefCounted

# Lets a walking body get over kerbs, door sills and stair treads instead of
# stopping dead against them. Call it just before move_and_slide().
#
# It looks a body-width ahead: if the way is blocked at foot level but clear
# one step higher, and there is level ground to stand on up there, the body is
# lifted by the height of the step and its own movement carries it on.

const HEIGHT: float = 0.42
const REACH: float = 0.4

static func climb(body: CharacterBody3D, height: float = HEIGHT) -> void:
	if not body.is_on_floor():
		return
	var flat := Vector3(body.velocity.x, 0.0, body.velocity.z)
	if flat.length() < 0.3:
		return
	var ahead := flat.normalized() * REACH
	var from := body.global_transform
	if not body.test_move(from, ahead):
		return
	var up := Vector3.UP * height
	if body.test_move(from, up):
		return   # no headroom
	var raised := from.translated(up)
	if body.test_move(raised, ahead):
		return   # still blocked up there: a wall, not a step
	var landing := KinematicCollision3D.new()
	if not body.test_move(raised.translated(ahead), -up, landing):
		return   # nothing to stand on
	if landing.get_normal().angle_to(Vector3.UP) > body.floor_max_angle:
		return
	var rise := height - landing.get_travel().length()
	if rise > 0.02:
		body.global_position.y += rise + 0.02
