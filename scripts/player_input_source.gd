class_name PlayerInputSource
extends RefCounted

# The only place in the project that reads Input or the mouse. Everything
# downstream consumes the InputFrame this returns (CLAUDE.md rule 1).

# Takes the node it is aiming from, because "face the cursor" needs to know
# where we are as well as where the cursor is.
func poll(from: Node2D) -> InputFrame:
	var frame := InputFrame.new()

	# limit_length rather than normalized so a future gamepad keeps its analog
	# magnitude, while keyboard diagonals still cap at 1.
	frame.move = Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	).limit_length(1.0)

	# Always face the cursor. Zero-length (cursor exactly on us) means "keep
	# facing where you already are" -- see Movement.apply.
	frame.aim = (from.get_global_mouse_position() - from.global_position).normalized()

	frame.shoot = Input.is_action_pressed("shoot")

	return frame
