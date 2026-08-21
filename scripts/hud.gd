extends CanvasLayer

# --- SCAFFOLD: attach this to a CanvasLayer node with Label children ---
# --- named "LootLabel" and "TimerLabel" (see setup steps) ---

@onready var loot_label: Label = $LootLabel
@onready var timer_label: Label = $TimerLabel

func _ready() -> void:
	loot_label.text = "Loot: 0"
	timer_label.text = ""

# TODO: your logic here
# Ideas to implement:
# 1. update_loot_display() -> call this whenever GameManager.current_run_loot
#    changes, set loot_label.text to show item count or total value
# 2. update_extraction_timer(time_remaining: float) -> called from
#    extraction_zone.gd while the player is standing in the zone,
#    show a countdown in timer_label
