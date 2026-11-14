extends Control

# The base between raids: loadout, stash, trader and frame choice. UI only
# (rule 6): every button calls a GameManager function, and the screen redraws
# itself from GameManager's state when profile_changed fires.

const TABS: Array[String] = ["Deploy", "Stash", "Trader", "Frame"]
const SLOT_NAMES: Dictionary = {"primary": "Primary", "secondary": "Secondary", "armor": "Armor", "implant_a": "Implant", "implant_b": "Implant"}

var _tab: String = "Deploy"
var _content: VBoxContainer
var _credits: Label
var _tab_buttons: Dictionary = {}

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var backdrop := ColorRect.new()
	backdrop.color = UiKit.BACKDROP
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 72)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 72)
	margin.add_child(columns)

	# Left: title, credits, navigation.
	var side_bar := VBoxContainer.new()
	side_bar.custom_minimum_size.x = 240
	side_bar.add_theme_constant_override("separation", 6)
	columns.add_child(side_bar)
	side_bar.add_child(UiKit.text("Extraction", 34))
	side_bar.add_child(UiKit.text("Kestrel  ·  salvage courier", 15, UiKit.DIM))
	side_bar.add_child(_gap(36))
	_credits = UiKit.text("", 22)
	side_bar.add_child(_credits)
	side_bar.add_child(UiKit.text("credits", 13, UiKit.DIM))
	side_bar.add_child(_gap(36))
	for tab in TABS:
		var b := Button.new()
		b.text = tab
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(func() -> void:
			Sfx.play("click", -8.0)
			_tab = tab
			_refresh())
		side_bar.add_child(b)
		_tab_buttons[tab] = b
	var filler := Control.new()
	filler.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_bar.add_child(filler)
	var stats := GameManager.stats
	side_bar.add_child(UiKit.text("%d raids   ·   %d extracted   ·   %d kills" % [stats["raids"], stats["extracted"], stats["kills"]], 13, UiKit.DIM))

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_content)

	columns.add_child(_showcase())

	GameManager.profile_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	_credits.text = _money(GameManager.credits)
	for tab: String in _tab_buttons:
		var b: Button = _tab_buttons[tab]
		var color := UiKit.INK if tab == _tab else UiKit.DIM
		for color_name: String in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(color_name, UiKit.TEAL if color_name == "font_hover_color" and tab != _tab else color)
	for child in _content.get_children():
		child.queue_free()
	match _tab:
		"Deploy": _deploy()
		"Stash": _stash()
		"Trader": _trader()
		"Frame": _frames()

# --- Tabs --------------------------------------------------------------------

func _deploy() -> void:
	var last := GameManager.last_result
	if not last.is_empty():
		var summary := "Last raid: extracted with %s." % _money(last["value"]) if last["outcome"] == "extracted" else "Last raid: lost with %d items." % last["items"].size()
		_content.add_child(UiKit.text(summary, 15, UiKit.TEAL if last["outcome"] == "extracted" else UiKit.DIM))
		_content.add_child(_gap(8))
	_heading("Loadout", "What you wear into the raid is lost if you die there.")
	for slot in GameManager.EQUIP_SLOTS:
		var id: String = GameManager.loadout[slot]
		var shown := Catalog.item_name(id) if id != "" else ("P9 Sidearm (issued)" if slot == "secondary" else "Empty")
		var remove: Button = null
		if id != "":
			remove = UiKit.button("Unequip", false, true)
			remove.pressed.connect(GameManager.unequip.bind(slot))
		_row(SLOT_NAMES[slot], shown, Catalog.rarity_color(id) if id != "" else UiKit.DIM, "", [remove])
	_content.add_child(_gap(18))

	var frame: Dictionary = Catalog.FRAMES[GameManager.frame_id]
	var stats := GameManager.player_stats()
	_heading("%s frame" % frame["name"], "%s  ·  Q %s  ·  E %s" % [frame["role"], frame["tactical"]["name"], frame["prime"]["name"]])
	_content.add_child(UiKit.text("%d health   ·   %d shield   ·   %d backpack slots   ·   %d medkits coming (of %d in stash)" % [
		stats["health"], stats["shield"], stats["capacity"], mini(GameManager.medkits_in_stash(), GameManager.MAX_MEDKITS), GameManager.medkits_in_stash()], 15, UiKit.DIM))
	_content.add_child(_gap(28))
	var deploy := UiKit.button("Deploy to Relay Station", true)
	deploy.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	deploy.pressed.connect(GameManager.start_raid)
	_content.add_child(deploy)
	_content.add_child(_gap(20))
	_content.add_child(UiKit.text("WASD move  ·  Shift sprint  ·  Ctrl crouch  ·  Space jump  ·  Mouse aim and fire  ·  R reload  ·  F use  ·  H medkit  ·  Q and E abilities  ·  1 / 2 weapons", 13, UiKit.DIM, true))
	_content.add_child(UiKit.text("Find loot, reach an extraction point and hold it for seven seconds. Twelve minutes until the station locks down.", 13, UiKit.DIM, true))

func _stash() -> void:
	var salvage := 0
	var counts: Dictionary = {}
	for i in GameManager.stash.size():
		var id := GameManager.stash[i]
		if not counts.has(id):
			counts[id] = [0, i]
		counts[id][0] += 1
		if Catalog.item(id)["kind"] == "loot":
			salvage += Catalog.sell_price(id)
	_heading("Stash", "%d items. Everything here is safe." % GameManager.stash.size())
	if salvage > 0:
		var sell_all := UiKit.button("Sell all salvage for %s" % _money(salvage), true, true)
		sell_all.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		sell_all.pressed.connect(func() -> void: GameManager.sell_all_salvage())
		_content.add_child(sell_all)
		_content.add_child(_gap(8))
	if counts.is_empty():
		_content.add_child(UiKit.text("Nothing yet. Bring something back.", 15, UiKit.DIM))
	var ids := counts.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return Catalog.item(a)["value"] > Catalog.item(b)["value"])
	for id: String in ids:
		var it := Catalog.item(id)
		var index: int = counts[id][1]
		var equip: Button = null
		if it["kind"] in ["weapon", "armor", "implant"]:
			equip = UiKit.button("Equip", false, true)
			equip.pressed.connect(GameManager.equip.bind(index, ""))
		var sell := UiKit.button("Sell  %s" % _money(Catalog.sell_price(id)), false, true)
		sell.pressed.connect(GameManager.sell.bind(index))
		var count: int = counts[id][0]
		_row(it["name"] + ("  × %d" % count if count > 1 else ""), Catalog.RARITY_NAMES[it["rarity"]] + " " + it["kind"], Catalog.rarity_color(id), it.get("desc", ""), [equip, sell])

func _trader() -> void:
	_heading("Trader", "Bought gear goes to your stash. Selling it back returns half.")
	for id in Catalog.TRADER_STOCK:
		var it := Catalog.item(id)
		var buy := UiKit.button("Buy  %s" % _money(it["value"]), false, true)
		buy.disabled = GameManager.credits < int(it["value"])
		buy.pressed.connect(func() -> void: GameManager.buy(id))
		_row(it["name"], it["kind"].capitalize(), Catalog.rarity_color(id), it.get("desc", ""), [buy])

func _frames() -> void:
	_heading("Frame", "Your body for the raid. Free to change between raids.")
	for id: String in Catalog.FRAMES:
		var frame: Dictionary = Catalog.FRAMES[id]
		var current := id == GameManager.frame_id
		var pick := UiKit.button("Selected" if current else "Select", current, true)
		pick.disabled = current
		pick.pressed.connect(GameManager.set_frame.bind(id))
		_row(frame["name"], frame["role"], frame["accent"], "", [pick])
		for line: String in [frame["passive"], "Q  %s: %s" % [frame["tactical"]["name"], frame["tactical"]["desc"]],
				"E  %s: %s" % [frame["prime"]["name"], frame["prime"]["desc"]]]:
			_content.add_child(UiKit.text(line, 14, UiKit.DIM, true))
		_content.add_child(_gap(16))

# Kestrel on a slow turntable, in its own small lit world.
func _showcase() -> Control:
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.custom_minimum_size = Vector2(430, 0)
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	holder.add_child(viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.36, 0.44)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.ssao_enabled = true
	var world := WorldEnvironment.new()
	world.environment = env
	viewport.add_child(world)
	# Key from the front-left, a cool rim from behind, a soft fill.
	for light: Array in [[Vector3(-38, 35, 0), Color(1.0, 0.95, 0.88), 2.4, true], [Vector3(-20, -150, 0), Color(0.55, 0.8, 1.0), 2.2, false], [Vector3(-10, -60, 0), Color(1.0, 0.9, 0.8), 0.5, false]]:
		var lamp := DirectionalLight3D.new()
		lamp.rotation_degrees = light[0]
		lamp.light_color = light[1]
		lamp.light_energy = light[2]
		lamp.shadow_enabled = light[3]
		viewport.add_child(lamp)

	var turntable := Node3D.new()
	viewport.add_child(turntable)
	var kestrel := KestrelBody.new()
	turntable.add_child(kestrel)
	kestrel.build(KestrelBody.MODEL_HEIGHT)
	var pad := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.75
	disc.bottom_radius = 0.8
	disc.height = 0.05
	disc.radial_segments = 64
	pad.mesh = disc
	pad.position.y = -0.025
	pad.material_override = Mats.surface(Color(0.1, 0.11, 0.13), "plain", 0.35, 0.6)
	turntable.add_child(pad)
	turntable.rotation.y = PI - 0.5
	var spin := turntable.create_tween().set_loops()
	spin.tween_property(turntable, "rotation:y", PI - 0.5 + TAU, 36.0).from(PI - 0.5)

	var camera := Camera3D.new()
	camera.fov = 30.0
	camera.position = Vector3(0.0, 1.12, 4.9)
	camera.rotation.x = -0.02
	viewport.add_child(camera)
	return holder

# --- Pieces ------------------------------------------------------------------

func _heading(title: String, sub: String) -> void:
	_content.add_child(UiKit.text(title, 28))
	_content.add_child(UiKit.text(sub, 15, UiKit.DIM, true))
	_content.add_child(_gap(10))

# One line of a list: name, a dim tag, an optional description, actions on the
# right, and a hairline under it.
func _row(title: String, tag: String, color: Color, desc: String, actions: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var name_label := UiKit.text(title, 17, color)
	name_label.custom_minimum_size.x = 250
	row.add_child(name_label)
	var tag_label := UiKit.text(tag, 14, UiKit.DIM)
	tag_label.custom_minimum_size.x = 150
	row.add_child(tag_label)
	var desc_label := UiKit.text(desc, 14, UiKit.DIM)
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_label.clip_text = true
	row.add_child(desc_label)
	for action: Variant in actions:
		if action != null:
			row.add_child(action)
	_content.add_child(row)
	var line := ColorRect.new()
	line.color = UiKit.FAINT
	line.custom_minimum_size.y = 1
	_content.add_child(line)

func _gap(height: float) -> Control:
	var gap := Control.new()
	gap.custom_minimum_size.y = height
	return gap

func _money(amount: int) -> String:
	var digits := str(amount)
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out + " cr"
