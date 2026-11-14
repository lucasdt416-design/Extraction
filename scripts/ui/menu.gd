extends Control

# The base between raids. A live 3D staging bay fills the screen -- Kestrel
# waiting by a hangar door, lit from behind -- and the interface sits over its
# darker left side: a title screen first, then Play, Loadout, Trader, Frame and
# Settings.
#
# UI only (rule 6): every button calls a GameManager function, and the screen
# redraws itself from GameManager's state when profile_changed fires.

const TABS: Array[String] = ["Play", "Loadout", "Trader", "Frame", "Settings"]
const SLOT_NAMES: Dictionary = {"primary": "Primary", "secondary": "Secondary", "armor": "Armor", "implant_a": "Implant", "implant_b": "Implant"}
const CAMERA_HOME := Vector3(-0.7, 1.38, 5.7)
const CAMERA_TITLE := Vector3(2.9, 0.75, 8.2)
const LOOK_AT := Vector3(1.25, 1.08, 0.0)

# The title screen shows once per launch, not every time a raid ends.
static var _seen_title: bool = false

var _tab: String = "Play"
var _content: VBoxContainer
var _credits: Label
var _tab_buttons: Dictionary = {}
var _underline: ColorRect
var _interface: Control
var _title: Control
var _prompt: Label
var _fade: ColorRect
var _camera: Camera3D
var _camera_base: Vector3 = CAMERA_TITLE
var _accent_light: OmniLight3D
var _drift: Vector2 = Vector2.ZERO
var _busy: bool = false

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_stage()
	_build_interface()
	_build_title()

	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 0.9)

	GameManager.profile_changed.connect(_refresh)
	if _seen_title:
		_title.visible = false
		_camera_base = CAMERA_HOME
	else:
		_interface.modulate.a = 0.0
		_interface.visible = false
	_refresh()

# --- The stage ---------------------------------------------------------------

func _build_stage() -> void:
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	holder.add_child(viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.022, 0.026)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.30, 0.36, 0.46)
	env.ambient_light_energy = 0.22
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.ssao_enabled = true
	env.ssr_enabled = true
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.011
	env.volumetric_fog_albedo = Color(0.9, 0.86, 0.8)
	env.volumetric_fog_length = 40.0
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	var world := WorldEnvironment.new()
	world.environment = env
	viewport.add_child(world)

	var stage := Node3D.new()
	viewport.add_child(stage)
	var wall := Mats.wall(Color(0.19, 0.2, 0.22), UiKit.ACID.darkened(0.35), 1.1, 2.5, 0.55, 0.3, 0.8)
	var dark := Mats.surface(Color(0.07, 0.075, 0.085), "plain", 0.5, 0.6)
	var warm := Color(1.0, 0.82, 0.62)

	# A polished floor, and a back wall split by a tall door standing ajar.
	_piece(stage, Vector3(0.0, -0.1, 0.0), Vector3(44.0, 0.2, 44.0), Mats.wall(Color(0.09, 0.095, 0.105), Color.BLACK, 0.0, 2.0, 0.14, 0.55, 0.5))
	_piece(stage, Vector3(-7.35, 6.0, -8.0), Vector3(25.3, 12.0, 0.6), wall)
	_piece(stage, Vector3(13.85, 6.0, -8.0), Vector3(12.3, 12.0, 0.6), wall)
	_piece(stage, Vector3(6.5, 9.6, -8.0), Vector3(2.4, 4.8, 0.6), wall)
	for edge: float in [5.3, 7.7]:
		_piece(stage, Vector3(edge, 3.6, -7.66), Vector3(0.16, 7.2, 0.1), Mats.glow(UiKit.ACID, 1.4))
	_piece(stage, Vector3(6.5, 4.0, -12.0), Vector3(9.0, 9.0, 0.1), Mats.glow(warm, 2.4))
	# Structure: pillars, overhead gantry, a low wall of crates, a lit rack.
	for x: float in [-9.0, -3.2, 10.0]:
		_piece(stage, Vector3(x, 6.0, -7.5), Vector3(0.8, 12.0, 0.5), dark)
	for z: float in [-4.0, 0.5]:
		_piece(stage, Vector3(0.0, 7.6, z), Vector3(44.0, 0.45, 0.45), dark)
		_piece(stage, Vector3(-2.5, 7.3, z), Vector3(3.0, 0.06, 0.3), Mats.glow(Color(0.75, 0.86, 1.0), 2.4))
	for crate: Array in [[-5.4, 0.7, -5.6, 1.4, 0.2], [-3.9, 0.55, -5.9, 1.1, -0.3], [-5.2, 1.85, -5.7, 0.9, 0.5], [9.6, 0.8, -4.6, 1.6, 0.35]]:
		var box := _piece(stage, Vector3(crate[0], crate[1], crate[2]), Vector3.ONE * float(crate[3]), Mats.surface(Color(0.3, 0.32, 0.34), "metal", 0.5, 0.5), 0.06)
		box.rotation.y = crate[4]
	for row in 5:
		_piece(stage, Vector3(-7.2, 0.6 + row * 0.5, -7.1), Vector3(1.6, 0.04, 0.05), Mats.glow(UiKit.TEAL, 2.0))
	_piece(stage, Vector3(-7.2, 1.7, -7.3), Vector3(2.0, 3.4, 0.4), dark)

	var number := Label3D.new()
	var stencil := FontVariation.new()
	stencil.base_font = UiKit.font(800)
	stencil.spacing_glyph = 10
	number.font = stencil
	number.text = "07"
	number.font_size = 200
	number.pixel_size = 4.2 / 200.0
	number.modulate = Color(0.3, 0.31, 0.33)
	number.position = Vector3(0.6, 4.9, -7.68)
	number.double_sided = false
	stage.add_child(number)

	# Light: a hard warm shaft through the door, a cool fill from the front,
	# and a rim in the colour of the chosen frame.
	var shaft := SpotLight3D.new()
	shaft.position = Vector3(6.5, 4.6, -11.0)
	shaft.light_color = warm
	shaft.light_energy = 10.0
	shaft.spot_range = 34.0
	shaft.spot_angle = 17.0
	shaft.shadow_enabled = true
	shaft.light_volumetric_fog_energy = 3.0
	stage.add_child(shaft)
	shaft.look_at(Vector3(1.7, 0.6, 2.5), Vector3.UP)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0.4, 2.3, 3.4)
	fill.light_color = Color(0.9, 0.93, 1.0)
	fill.light_energy = 4.2
	fill.omni_range = 12.0
	stage.add_child(fill)
	_accent_light = OmniLight3D.new()
	_accent_light.position = Vector3(0.2, 1.6, -1.6)
	_accent_light.light_energy = 2.2
	_accent_light.omni_range = 5.0
	_accent_light.light_color = Catalog.FRAMES[GameManager.frame_id]["accent"]
	stage.add_child(_accent_light)

	var kestrel := KestrelBody.new()
	kestrel.position = Vector3(2.2, 0.0, 0.0)
	kestrel.rotation.y = PI + 0.42
	stage.add_child(kestrel)
	kestrel.build(KestrelBody.MODEL_HEIGHT)

	# Dust turning over in the shaft.
	var quad := QuadMesh.new()
	quad.size = Vector2(0.009, 0.009)
	var mote := StandardMaterial3D.new()
	mote.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mote.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mote.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mote.albedo_color = Color(1.0, 0.9, 0.75, 0.4)
	quad.material = mote
	var dust := CPUParticles3D.new()
	dust.mesh = quad
	dust.amount = 260
	dust.lifetime = 12.0
	dust.preprocess = 12.0
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(5.0, 3.0, 6.0)
	dust.direction = Vector3(-0.4, 0.15, 1.0)
	dust.spread = 60.0
	dust.gravity = Vector3.ZERO
	dust.initial_velocity_min = 0.03
	dust.initial_velocity_max = 0.16
	dust.scale_amount_min = 0.5
	dust.scale_amount_max = 1.6
	dust.position = Vector3(2.0, 2.6, -2.0)
	stage.add_child(dust)

	_camera = Camera3D.new()
	_camera.fov = 36.0
	_camera.position = _camera_base
	viewport.add_child(_camera)
	_camera.look_at(LOOK_AT, Vector3.UP)

func _piece(parent: Node3D, at: Vector3, size: Vector3, mat: Material, bevel: float = 0.0) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	if bevel > 0.0:
		instance.mesh = Shapes.rounded_box(size, bevel, 2)
	else:
		var mesh := BoxMesh.new()
		mesh.size = size
		instance.mesh = mesh
	instance.material_override = mat
	instance.position = at
	parent.add_child(instance)
	return instance

# The camera breathes on its own and leans a little toward the mouse.
func _process(delta: float) -> void:
	var size := get_viewport_rect().size
	var mouse := (get_viewport().get_mouse_position() / size - Vector2(0.5, 0.5)).clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5))
	_drift = _drift.lerp(mouse, minf(delta * 2.0, 1.0))
	var t := Time.get_ticks_msec() * 0.001
	_camera.position = _camera_base + Vector3(_drift.x * 0.32 + sin(t * 0.21) * 0.06, -_drift.y * 0.14 + sin(t * 0.33) * 0.03, 0.0)
	_camera.look_at(LOOK_AT, Vector3.UP)
	if _title.visible:
		_prompt.modulate.a = 0.45 + 0.4 * sin(t * 2.2)

# --- Title -------------------------------------------------------------------

func _build_title() -> void:
	_title = Control.new()
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	column.offset_left = 88.0
	column.offset_top = -300.0
	column.offset_bottom = -96.0
	column.offset_right = 1000.0
	column.alignment = BoxContainer.ALIGNMENT_END
	column.add_theme_constant_override("separation", 4)
	_title.add_child(column)
	column.add_child(UiKit.text("EXTRACTION", 92, UiKit.INK, false, 700, 18))
	column.add_child(UiKit.text("RELAY STATION 07", 16, UiKit.ACID, false, 600, 9))
	column.add_child(_gap(40))
	_prompt = UiKit.text("Press any key", 16, UiKit.INK, false, 500, 2)
	column.add_child(_prompt)

func _unhandled_input(event: InputEvent) -> void:
	if not _title.visible or _busy:
		return
	if (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
		_enter()

# Title to menu: the camera rises and swings round to Kestrel while the
# wordmark fades and the interface comes up.
func _enter() -> void:
	if not _title.visible or _busy:
		return
	_busy = true
	_seen_title = true
	Sfx.play("ability", -10.0, 0.6)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_title, "modulate:a", 0.0, 0.5)
	tween.tween_property(self, "_camera_base", CAMERA_HOME, 1.8).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	_interface.visible = true
	tween.tween_property(_interface, "modulate:a", 1.0, 0.7).set_delay(0.9)
	tween.chain().tween_callback(func() -> void:
		_title.visible = false
		_busy = false
		_place_underline(false))

# --- Interface ---------------------------------------------------------------

func _build_interface() -> void:
	_interface = Control.new()
	_interface.set_anchors_preset(Control.PRESET_FULL_RECT)
	_interface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_interface)

	# Darkens the left of the scene so type sits on something quiet.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.02, 0.024, 0.03, 0.94))
	gradient.set_color(1, Color(0.02, 0.024, 0.03, 0.0))
	gradient.add_point(0.42, Color(0.02, 0.024, 0.03, 0.78))
	var ramp := GradientTexture2D.new()
	ramp.gradient = gradient
	ramp.fill_to = Vector2(0.72, 0.0)
	var scrim := TextureRect.new()
	scrim.texture = ramp
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interface.add_child(scrim)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 88)
	margin.add_theme_constant_override("margin_top", 56)
	margin.add_theme_constant_override("margin_bottom", 48)
	_interface.add_child(margin)
	var page := VBoxContainer.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_theme_constant_override("separation", 0)
	margin.add_child(page)

	# Top line: wordmark left, credits right.
	var top := HBoxContainer.new()
	page.add_child(top)
	top.add_child(UiKit.text("EXTRACTION", 20, UiKit.INK, false, 700, 9))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_credits = UiKit.text("", 20, UiKit.INK, false, 600)
	top.add_child(_credits)
	page.add_child(_gap(34))

	# Tabs, with one underline that slides to whichever is active.
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 38)
	page.add_child(nav)
	for tab in TABS:
		var b := Button.new()
		b.text = tab.to_upper()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", UiKit.font(600, 4))
		b.add_theme_font_size_override("font_size", 15)
		for state: String in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		b.pressed.connect(_show_tab.bind(tab))
		nav.add_child(b)
		_tab_buttons[tab] = b
	var rail := Control.new()
	rail.custom_minimum_size.y = 10
	rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(rail)
	_underline = ColorRect.new()
	_underline.color = UiKit.ACID
	_underline.size = Vector2(40, 2)
	_underline.position.y = 6
	rail.add_child(_underline)
	page.add_child(_gap(40))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 800
	scroll.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	page.add_child(scroll)
	_content = VBoxContainer.new()
	_content.custom_minimum_size.x = 780
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_content)

	# Bottom line: career numbers left, quit right.
	page.add_child(_gap(20))
	var bottom := HBoxContainer.new()
	page.add_child(bottom)
	var stats := GameManager.stats
	bottom.add_child(UiKit.text("%d raids   ·   %d extracted   ·   %d hostiles down" % [stats["raids"], stats["extracted"], stats["kills"]], 13, UiKit.DIM, false, 500, 1))
	var push := Control.new()
	push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(push)
	var quit := Button.new()
	quit.text = "QUIT"
	quit.flat = true
	quit.focus_mode = Control.FOCUS_NONE
	quit.add_theme_font_override("font", UiKit.font(600, 4))
	quit.add_theme_font_size_override("font_size", 13)
	quit.add_theme_color_override("font_color", UiKit.DIM)
	quit.add_theme_color_override("font_hover_color", UiKit.INK)
	quit.pressed.connect(func() -> void: get_tree().quit())
	bottom.add_child(quit)

func _show_tab(tab: String) -> void:
	if tab == _tab:
		return
	Sfx.play("click", -8.0)
	_tab = tab
	# Out, swap, in: the content slips sideways a few pixels as it changes.
	var tween := create_tween()
	tween.tween_property(_content, "modulate:a", 0.0, 0.09)
	tween.tween_callback(func() -> void:
		_refresh()
		_content.position.x = 18.0)
	tween.set_parallel(true)
	tween.tween_property(_content, "modulate:a", 1.0, 0.22)
	tween.tween_property(_content, "position:x", 0.0, 0.26).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

func _place_underline(animate: bool = true) -> void:
	var b: Button = _tab_buttons[_tab]
	var left := b.position.x
	var width := b.size.x
	if animate and _interface.visible:
		var tween := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(_underline, "position:x", left, 0.28)
		tween.tween_property(_underline, "size:x", width, 0.28)
	else:
		_underline.position.x = left
		_underline.size.x = width

func _refresh() -> void:
	_credits.text = _money(GameManager.credits)
	for tab: String in _tab_buttons:
		var b: Button = _tab_buttons[tab]
		b.add_theme_color_override("font_color", UiKit.INK if tab == _tab else UiKit.DIM)
		b.add_theme_color_override("font_hover_color", UiKit.INK)
		b.add_theme_color_override("font_pressed_color", UiKit.INK)
	_place_underline.call_deferred()
	for child in _content.get_children():
		child.queue_free()
	match _tab:
		"Play": _play()
		"Loadout": _loadout()
		"Trader": _trader()
		"Frame": _frames()
		"Settings": _settings()

# --- Tabs --------------------------------------------------------------------

func _play() -> void:
	_content.add_child(UiKit.text("NEXT RAID", 13, UiKit.ACID, false, 600, 6))
	_content.add_child(UiKit.text("Relay Station 07", 64, UiKit.INK, false, 700))
	_content.add_child(UiKit.text("Twelve minutes before the station locks down. Two ways out. Squads hold every building.", 17, UiKit.DIM, true))
	_content.add_child(_gap(22))

	var frame: Dictionary = Catalog.FRAMES[GameManager.frame_id]
	var stats := GameManager.player_stats()
	var carrying: Array[String] = []
	for id in GameManager.raid_weapons():
		carrying.append(Catalog.item_name(id))
	for slot: String in ["armor", "implant_a", "implant_b"]:
		if GameManager.loadout[slot] != "":
			carrying.append(Catalog.item_name(GameManager.loadout[slot]))
	var medkits := mini(GameManager.medkits_in_stash(), GameManager.MAX_MEDKITS)
	if medkits > 0:
		carrying.append("%d medkit%s" % [medkits, "" if medkits == 1 else "s"])
	_fact("Going in with", ", ".join(carrying))
	_fact("Frame", "%s  ·  %d health  ·  %d shield  ·  %d backpack slots" % [frame["name"], stats["health"], stats["shield"], stats["capacity"]])
	var last := GameManager.last_result
	if not last.is_empty():
		var extracted: bool = last["outcome"] == "extracted"
		_fact("Last raid", ("Extracted with %s" % _money(last["value"])) if extracted else ("Lost, with %d item%s" % [last["items"].size(), "" if last["items"].size() == 1 else "s"]),
			UiKit.INK if extracted else UiKit.CORAL)
	_content.add_child(_gap(26))

	var deploy := UiKit.button("DEPLOY", true)
	deploy.add_theme_font_override("font", UiKit.font(700, 4))
	deploy.add_theme_font_size_override("font_size", 18)
	deploy.custom_minimum_size = Vector2(250, 58)
	deploy.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	deploy.pressed.connect(_deploy)
	_content.add_child(deploy)
	_content.add_child(_gap(26))
	_content.add_child(UiKit.text("WASD move  ·  Shift sprint  ·  Ctrl crouch  ·  Space jump  ·  R reload  ·  F use  ·  H medkit  ·  Q and E abilities  ·  1 / 2 weapons", 13, UiKit.DIM, true))

# Fade to black, then hand over to the raid.
func _deploy() -> void:
	if _busy:
		return
	_busy = true
	Sfx.play("extract", -8.0, 0.8)
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_fade, "color:a", 1.0, 0.6)
	tween.tween_property(self, "_camera_base", CAMERA_HOME + Vector3(1.2, -0.2, -2.6), 0.7).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(GameManager.start_raid)

func _loadout() -> void:
	_heading("Loadout", "What you wear into the raid is lost if you die there.")
	for slot in GameManager.EQUIP_SLOTS:
		var id: String = GameManager.loadout[slot]
		var shown := Catalog.item_name(id) if id != "" else ("P9 Sidearm (issued)" if slot == "secondary" else "Empty")
		var remove: Button = null
		if id != "":
			remove = UiKit.button("Unequip", false, true)
			remove.pressed.connect(GameManager.unequip.bind(slot))
		_row(shown, SLOT_NAMES[slot], Catalog.rarity_color(id) if id != "" else UiKit.DIM, Catalog.item(id).get("desc", "") if id != "" else "", [remove])
	_content.add_child(_gap(24))

	var salvage := 0
	var counts: Dictionary = {}
	for i in GameManager.stash.size():
		var id := GameManager.stash[i]
		if not counts.has(id):
			counts[id] = [0, i]
		counts[id][0] += 1
		if Catalog.item(id)["kind"] == "loot":
			salvage += Catalog.sell_price(id)
	_content.add_child(UiKit.text("STASH", 13, UiKit.ACID, false, 600, 6))
	_content.add_child(UiKit.text("%d item%s, safe between raids." % [GameManager.stash.size(), "" if GameManager.stash.size() == 1 else "s"], 15, UiKit.DIM))
	if salvage > 0:
		_content.add_child(_gap(4))
		var sell_all := UiKit.button("Sell all salvage for %s" % _money(salvage), true, true)
		sell_all.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		sell_all.pressed.connect(func() -> void: GameManager.sell_all_salvage())
		_content.add_child(sell_all)
	_content.add_child(_gap(4))
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
	_heading("Frame", "How Kestrel is tuned for the raid. Free to change between raids.")
	for id: String in Catalog.FRAMES:
		var frame: Dictionary = Catalog.FRAMES[id]
		var current := id == GameManager.frame_id
		var pick := UiKit.button("Selected" if current else "Select", current, true)
		pick.disabled = current
		pick.pressed.connect(func() -> void:
			GameManager.set_frame(id)
			# The rim light on Kestrel takes the frame's colour.
			create_tween().tween_property(_accent_light, "light_color", frame["accent"], 0.5))
		_row(frame["name"], frame["role"], frame["accent"], "", [pick])
		for line: String in [frame["passive"], "Q  %s: %s" % [frame["tactical"]["name"], frame["tactical"]["desc"]],
				"E  %s: %s" % [frame["prime"]["name"], frame["prime"]["desc"]]]:
			_content.add_child(UiKit.text(line, 14, UiKit.DIM, true))
		_content.add_child(_gap(14))

func _settings() -> void:
	_heading("Settings", "Saved with your profile. Also on the pause screen during a raid.")
	_content.add_child(UiKit.settings_rows())
	_content.add_child(_gap(10))
	_content.add_child(UiKit.text("High quality adds bounced light and reflections. Medium drops those. Low also drops fog and soft shading: use it if the game runs slowly.", 13, UiKit.DIM, true))

# --- Pieces ------------------------------------------------------------------

func _heading(title: String, sub: String) -> void:
	_content.add_child(UiKit.text(title, 40, UiKit.INK, false, 700))
	_content.add_child(UiKit.text(sub, 15, UiKit.DIM, true))
	_content.add_child(_gap(12))

# A label and its value on one line, for the Play tab's summary.
func _fact(label: String, value: String, color: Color = UiKit.INK) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var name_label := UiKit.text(label.to_upper(), 12, UiKit.DIM, false, 600, 4)
	name_label.custom_minimum_size.x = 170
	row.add_child(name_label)
	var value_label := UiKit.text(value, 16, color, true)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value_label)
	_content.add_child(row)

# One line of a list: name, a dim tag, an optional description, actions on the
# right, and a hairline under it.
func _row(title: String, tag: String, color: Color, desc: String, actions: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var name_label := UiKit.text(title, 17, color, false, 600)
	name_label.custom_minimum_size.x = 230
	row.add_child(name_label)
	var tag_label := UiKit.text(tag, 13, UiKit.DIM)
	tag_label.custom_minimum_size.x = 130
	row.add_child(tag_label)
	var desc_label := UiKit.text(desc, 13, UiKit.DIM)
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
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gap

func _money(amount: int) -> String:
	var digits := str(amount)
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out + " cr"
