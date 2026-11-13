extends Node

# Test helper: counts squad barks sent to the "hud" group.
var counter: Array = [0]

func _ready() -> void:
	add_to_group("hud")

func show_comm(_speaker: String, _line: String, _position: Vector3) -> void:
	counter[0] += 1
