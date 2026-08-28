class_name ConsumableItem
extends Item

@export var healing: int = 5

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	name = "Stim"
	value = 25

func describe() -> String:
	return "%s\nHeal: %d" % [super.describe(), healing]
