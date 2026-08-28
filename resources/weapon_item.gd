class_name WeaponItem
extends Item

@export var damage: int = 1

func _ready() -> void:
	name = "Gun"
	value = 100

func describe() -> String:
	return "%s\nDmg: %d" % [super.describe(), damage]
