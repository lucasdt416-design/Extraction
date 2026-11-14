class_name UiKit
extends RefCounted

# The few shared pieces of interface styling: one button, one text helper.
# Flat, square-cornered, no icons; hierarchy comes from size and weight of
# contrast rather than from boxes.

const INK := Color(0.94, 0.95, 0.96)
const DIM := Color(0.94, 0.95, 0.96, 0.55)
const FAINT := Color(0.94, 0.95, 0.96, 0.10)
const TEAL := Color(0.40, 0.86, 0.82)
const BACKDROP := Color(0.055, 0.062, 0.075)

static func button(text: String, primary: bool = false, small: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14 if small else 16)
	var pad_x := 14.0 if small else 26.0
	var pad_y := 6.0 if small else 12.0
	var states := {
		"normal": TEAL if primary else Color(1, 1, 1, 0.07),
		"hover": TEAL.lightened(0.2) if primary else Color(1, 1, 1, 0.14),
		"pressed": TEAL.darkened(0.15) if primary else Color(1, 1, 1, 0.2),
		"disabled": Color(1, 1, 1, 0.03),
	}
	for state: String in states:
		var box := StyleBoxFlat.new()
		box.bg_color = states[state]
		box.set_corner_radius_all(2)
		box.content_margin_left = pad_x
		box.content_margin_right = pad_x
		box.content_margin_top = pad_y
		box.content_margin_bottom = pad_y
		b.add_theme_stylebox_override(state, box)
	var ink := Color(0.03, 0.08, 0.08) if primary else INK
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(color_name, ink)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.25))
	b.pressed.connect(func() -> void: Sfx.play("click", -8.0))
	return b

static func text(content: String, size: int = 16, color: Color = INK, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
