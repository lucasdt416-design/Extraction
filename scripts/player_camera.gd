class_name PlayerCamera
extends Camera2D

# Rides along as a child of the player body, so it moves on the physics tick in
# lockstep with the thing it is following. A camera that chased the player from
# outside _physics_process would always render a frame behind it.
#
# This is a local view, not raid state: nothing here affects the simulation, and
# no other player would ever need to agree about it. When co-op lands,
# make_current() picks up an "is this my player?" check and nothing else in this
# file changes (CLAUDE.md rule 6 -- UI and view decide nothing).

func _ready() -> void:
	# The player rotates to face the cursor. Without this the camera would
	# inherit that rotation and spin the entire world around the player every
	# time the mouse moved. Godot defaults this to true; set it explicitly
	# because it is load-bearing here, not incidental.
	ignore_rotation = true

	make_current()
