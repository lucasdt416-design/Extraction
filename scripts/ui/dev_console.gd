extends Control

const QUICK_COMMANDS := [
	["Hover helicopter", "spawn heli hover"], ["Land helicopter", "spawn heli land"],
	["Hover dropship", "spawn dropship hover"], ["Land dropship", "spawn dropship land"],
	["Spawn trooper", "spawn enemy"], ["Go to aircraft", "goto"], ["Clear test spawns", "clear"],
]

var raid: Raid
var _field: LineEdit
var _output: RichTextLabel
var _status: Label
var _lines: Array[String] = []
var _history: Array[String] = []
var _history_at := 0
var _opened_before := false
var _mouse_mode: Input.MouseMode

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.014, 0.021, 0.027, 0.68)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_left = 64.0
	panel.offset_right = -64.0
	panel.offset_top = 42.0
	panel.offset_bottom = 410.0
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.027, 0.048, 0.058)
	box.border_color = UiKit.TEAL
	box.border_width_top = 2
	for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		box.set_content_margin(side, 18.0)
	panel.add_theme_stylebox_override("panel", box)
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := UiKit.text("Dev console", 24, UiKit.INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var resume := UiKit.button("Resume  [`]", true, true)
	resume.pressed.connect(func() -> void: close())
	header.add_child(resume)
	_status = UiKit.text("", 14, UiKit.TEAL)
	column.add_child(_status)

	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 8)
	actions.add_theme_constant_override("v_separation", 8)
	column.add_child(actions)
	for entry: Array in QUICK_COMMANDS:
		var button := UiKit.button(entry[0], false, true)
		button.pressed.connect(_submit.bind(entry[1]))
		actions.add_child(button)

	_output = RichTextLabel.new()
	_output.custom_minimum_size.y = 145.0
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.scroll_following = true
	_output.add_theme_font_override("normal_font", UiKit.mono())
	_output.add_theme_font_size_override("normal_font_size", 14)
	_output.add_theme_color_override("default_color", UiKit.INK)
	column.add_child(_output)

	_field = LineEdit.new()
	_field.custom_minimum_size.y = 38.0
	_field.placeholder_text = "Enter a command, or type help"
	_field.add_theme_font_override("font", UiKit.mono())
	_field.add_theme_font_size_override("font_size", 15)
	_field.text_submitted.connect(_submit)
	_field.gui_input.connect(_history_input)
	column.add_child(_field)
	hide()

func open() -> void:
	if visible or raid.over:
		return
	if not _opened_before:
		_opened_before = true
		raid.player.dev_invulnerable = true
		raid.player.dev_infinite_grenades = true
		_log("God mode blocks damage and holds the raid clock. Press G during play to throw a grenade.")
	_mouse_mode = Input.mouse_mode
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	show()
	_update_status()
	_field.grab_focus()

func close(restore_mouse: bool = true) -> void:
	if not visible:
		return
	_field.release_focus()
	hide()
	get_tree().paused = false
	if restore_mouse:
		Input.mouse_mode = _mouse_mode

func _submit(command: String) -> void:
	var text := command.strip_edges()
	if text.is_empty():
		return
	_history.append(text)
	if _history.size() > 40:
		_history.pop_front()
	_history_at = _history.size()
	_log("> " + text)
	_log(run_command(text))
	_update_status()
	_field.clear()
	_field.grab_focus()

func _history_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		_history_at = maxi(0, _history_at - 1)
	elif event.is_action_pressed("ui_down"):
		_history_at = mini(_history.size(), _history_at + 1)
	else:
		return
	_field.text = _history[_history_at] if _history_at < _history.size() else ""
	_field.caret_column = _field.text.length()
	_field.accept_event()

func _log(text: String) -> void:
	_lines.append(text)
	if _lines.size() > 48:
		_lines.pop_front()
	_output.text = "\n".join(_lines)

func _update_status() -> void:
	_status.text = "%s     /     %s     /     FROZEN WHILE CONSOLE IS OPEN" % [
		"GOD ON · CLOCK HELD" if raid.player.dev_invulnerable else "GOD OFF",
		"UNLIMITED GRENADES" if raid.player.dev_infinite_grenades else "%d GRENADES" % raid.player.grenades,
	]

func run_command(text: String) -> String:
	var words := text.strip_edges().to_lower().replace("\t", " ").split(" ", false)
	if words.is_empty():
		return ""
	var option := words[1] if words.size() > 1 else ""
	var player := raid.player
	match words[0]:
		"help":
			return ("spawn heli|dropship [hover|land]   /   spawn enemy [archetype]\n"
				+ "god [on|off]   /   grenades [infinite|normal|refill]   /   heal   /   goto   /   clear\n"
				+ "Enemy archetypes   " + ", ".join(Catalog.ENEMIES.keys()))
		"spawn":
			return _spawn(option, words[2] if words.size() > 2 else "")
		"god":
			if option not in ["", "on", "off"]:
				return "Usage  god [on|off]"
			player.dev_invulnerable = not player.dev_invulnerable if option.is_empty() else option == "on"
			return "God mode on. Raid clock held." if player.dev_invulnerable else "God mode off. Raid clock running."
		"grenades":
			match option:
				"infinite": player.dev_infinite_grenades = true
				"normal": player.dev_infinite_grenades = false
				"refill": player.grenades = Player.RAID_GRENADES
				_: return "Usage  grenades [infinite|normal|refill]"
			return "Grenades ready. Press G during play."
		"heal":
			player.health = player.max_health
			player.shield = player.max_shield
			return "Health and shields restored."
		"goto":
			if raid.dev_go_to_aircraft():
				return "Moved to the aircraft's unloading area."
			return "Spawn an aircraft with a walkable area nearby."
		"clear":
			raid.dev_clear_spawns()
			return "Removed console-spawned aircraft and troops."
	return "Unknown command. Type help for available commands."

func _spawn(target: String, variant: String) -> String:
	match target:
		"heli", "helicopter", "dropship":
			if variant not in ["", "hover", "land"]:
				return "Usage  spawn heli|dropship [hover|land]"
			var lands := variant == "land"
			var craft := raid.dev_spawn_aircraft(target != "dropship", lands)
			if craft == null:
				return "No clear approach and unloading area. Try from an open area."
			var distance := roundi(craft.station.distance_to(raid.player.global_position))
			return "%s inbound to %s, %d m away. Resume to watch it arrive." % [
				"Dropship" if target == "dropship" else "Helicopter", "land" if lands else "hover", distance,
			]
		"enemy":
			var kind := "trooper" if variant.is_empty() else variant
			if not Catalog.ENEMIES.has(kind):
				return "Unknown archetype. Type help for enemy IDs."
			if raid.dev_spawn_enemy(kind) != null:
				return "Spawned %s nearby." % kind
			return "No walkable ground nearby."
	return "Usage  spawn heli|dropship [hover|land] or spawn enemy [archetype]"
