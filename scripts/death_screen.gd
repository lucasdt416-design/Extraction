class_name DeathScreen
extends CanvasLayer

# Local, per-client death view. It blacks out this player's window and says so;
# it does not touch the tree, the physics tick, or anyone else's simulation.
# In co-op later, only the client whose own player died ever builds one of these
# -- the raid keeps running for everybody, including for the corpse watching it.
#
# UI only (CLAUDE.md rule 6): it decides nothing, it just renders a fact that
# GameManager already established.

# Above anything else we might add later (HUD sits at the default 0).
const OVERLAY_LAYER: int = 100

@export var message: String = "You died"
@export var font_size: int = 64
@export var fade_time: float = 0.6

var _shade: ColorRect
var _label: Label

func _init() -> void:
	layer = OVERLAY_LAYER
	# Keep drawing (and keep fading in) even if something pauses the tree.
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	_shade = ColorRect.new()
	_shade.color = Color.BLACK
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Swallow clicks so a dead player can't poke at anything behind the black.
	_shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_shade)

	_label = Label.new()
	_label.text = message
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", Color(0.85, 0.13, 0.13))
	_shade.add_child(_label)

	if fade_time > 0.0:
		_shade.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(_shade, "modulate:a", 1.0, fade_time)
