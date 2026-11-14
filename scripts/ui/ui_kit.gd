class_name UiKit
extends RefCounted

# The few shared pieces of interface styling: one button, one text helper.
# Flat, square-cornered, no icons; hierarchy comes from size and weight of
# contrast rather than from boxes.

const INK := Color(0.94, 0.95, 0.96)
const DIM := Color(0.94, 0.95, 0.96, 0.55)
const FAINT := Color(0.94, 0.95, 0.96, 0.10)
const TEAL := Color(0.40, 0.86, 0.82)
# Kestrel's colours. Acid is the one accent: the primary action and the active tab.
const ACID := Color(0.886, 0.94, 0.086)
const CORAL := Color(0.99, 0.38, 0.26)

static var _fonts: Dictionary = {}

# Three bundled typefaces (all SIL Open Font License, in assets/fonts):
#   font()     Space Grotesk       -- running text and controls
#   display()  Big Shoulders Display -- headlines, numerals, the wordmark
#   mono()     Space Mono          -- small technical labels and figures
# `tracking` adds letter spacing in pixels.
static func font(weight: int = 500, tracking: int = 0) -> Font:
	return _variable("res://assets/fonts/SpaceGrotesk.ttf", weight, tracking)

static func display(weight: int = 800, tracking: int = 0) -> Font:
	return _variable("res://assets/fonts/BigShouldersDisplay.ttf", weight, tracking)

static func mono(bold: bool = false, tracking: int = 0) -> Font:
	return _variable("res://assets/fonts/SpaceMono-%s.ttf" % ("Bold" if bold else "Regular"), 0, tracking)

static func _variable(path: String, weight: int, tracking: int) -> Font:
	var key := "%s%d/%d" % [path, weight, tracking]
	if _fonts.has(key):
		return _fonts[key]
	var variation := FontVariation.new()
	variation.base_font = load(path)
	if weight > 0:
		variation.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
	variation.spacing_glyph = tracking
	_fonts[key] = variation
	return variation

static func button(text: String, primary: bool = false, small: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14 if small else 16)
	b.add_theme_font_override("font", font(600))
	var pad_x := 14.0 if small else 26.0
	var pad_y := 6.0 if small else 12.0
	var states := {
		"normal": ACID if primary else Color(1, 1, 1, 0.08),
		"hover": ACID.lightened(0.35) if primary else Color(1, 1, 1, 0.16),
		"pressed": ACID.darkened(0.15) if primary else Color(1, 1, 1, 0.22),
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
	var ink := Color(0.07, 0.08, 0.02) if primary else INK
	for color_name: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(color_name, ink)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.25))
	b.pressed.connect(func() -> void: Sfx.play("click", -8.0))
	return b

# The settings controls, as a column of rows. Used by the menu's Settings tab
# and the pause screen. It only calls GameManager.set_setting (rule 6).
static func settings_rows(include_quality: bool = true, ink: Color = INK, dim: Color = DIM, faint: Color = FAINT, accent: Color = ACID) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	var rows := [
		["sensitivity", "Mouse sensitivity", func(v: float) -> String: return "%.1f" % v],
		["fov", "Field of view", func(v: float) -> String: return "%d°" % v],
		["volume", "Volume", func(v: float) -> String: return "%d%%" % roundi(v * 100.0)],
	]
	if include_quality:
		rows.append(["quality", "Graphics quality", func(v: float) -> String: return ["Low", "Medium", "High"][int(v)]])
	for row: Array in rows:
		var key: String = row[0]
		var format: Callable = row[2]
		var limits: Array = GameManager.SETTING_RANGES[key]
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 16)
		var name_label := text(row[1], 16, ink)
		name_label.custom_minimum_size.x = 210
		line.add_child(name_label)
		var slider := HSlider.new()
		slider.min_value = limits[0]
		slider.max_value = limits[1]
		slider.step = limits[2]
		slider.value = GameManager.settings[key]
		slider.custom_minimum_size = Vector2(260, 24)
		slider.focus_mode = Control.FOCUS_NONE
		for part: String in ["slider", "grabber_area", "grabber_area_highlight"]:
			var bar := StyleBoxFlat.new()
			bar.bg_color = faint if part == "slider" else accent
			bar.content_margin_top = 2
			bar.content_margin_bottom = 2
			slider.add_theme_stylebox_override(part, bar)
		line.add_child(slider)
		var value_label := text(format.call(GameManager.settings[key]), 15, dim)
		value_label.add_theme_font_override("font", mono())
		value_label.custom_minimum_size.x = 80
		line.add_child(value_label)
		slider.value_changed.connect(func(v: float) -> void:
			GameManager.set_setting(key, v)
			value_label.text = format.call(GameManager.settings[key]))
		column.add_child(line)
	return column

static func text(content: String, size: int = 16, color: Color = INK, wrap: bool = false, weight: int = 500, tracking: int = 0) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_override("font", font(weight, tracking))
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
