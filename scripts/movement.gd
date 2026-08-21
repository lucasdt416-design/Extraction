class_name Movement
extends RefCounted

# The one place that turns an InputFrame into actual motion. Player, AI and
# (later) a replay all move by identical rules because they all come through
# here -- that is the whole point of keeping intent separate from action.

static func apply(body: CharacterBody2D, frame: InputFrame, speed: float) -> void:
	body.velocity = frame.move * speed
	body.move_and_slide()

	if frame.aim.length_squared() > 0.0001:
		body.rotation = frame.aim.angle()
