class_name Item
extends Resource

@export var name: String = "test"
@export var value: int = 0
@export var item_ID: int = 0


func describe() -> String:
	return "%s: %d" % [name, value]
