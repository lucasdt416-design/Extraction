extends Control

# The base between raids, designed as a poster you can walk through. A bright
# studio fills the screen: Kestrel stands on a chalk floor in front of a huge
# word painted on the wall and a disc of flat colour. Every page has its own
# word, colour and camera angle, and the camera travels between them.
#
# UI only (rule 6): every control calls a GameManager function, and the screen
# redraws itself from GameManager's state when profile_changed fires.

const TABS: Array[String] = ["Play", "Loadout", "Trader", "Frame", "Settings"]
const SLOT_NAMES: Dictionary = {"primary": "PRIMARY", "secondary": "SECONDARY", "armor": "ARMOR", "implant_a": "IMPLANT", "implant_b": "IMPLANT"}

const CHALK := Color(0.925, 0.93, 0.905)
const INK := Color(0.09, 0.10, 0.12)
const DIM := Color(0.09, 0.10, 0.12, 0.6)
const LINE := Color(0.09, 0.10, 0.12, 0.16)
const ACID := UiKit.ACID
const CORAL := UiKit.CORAL

# Per page: the word on the wall and where it sits, the disc's colour, and the
# camera's position, aim and lens.
const PAGES: Dictionary = {
	"Title": {"word": "EXTRACTION", "at": Vector3(1.9, 2.35, -5.86), "height": 2.35, "disc": ACID, "disc_at": Vector3(1.9, 2.45, -5.89),
		"camera": Vector3(1.9, 1.45, 8.4), "look": Vector3(1.9, 1.85, 0.0), "fov": 33.0},
	"Play": {"word": "07", "at": Vector3(8.5, 2.7, -5.86), "height": 4.4, "disc": ACID, "disc_at": Vector3(6.9, 2.7, -5.89),
		"camera": Vector3(-1.5, 1.3, 6.4), "look": Vector3(0.95, 1.2, 0.0), "fov": 36.0},
	"Loadout": {"word": "KIT", "at": Vector3(6.9, 2.25, -5.86), "height": 2.6, "disc": Color(0.13, 0.14, 0.16), "disc_at": Vector3(6.6, 2.3, -5.89), "word_color": CHALK,
		"camera": Vector3(-0.3, 1.5, 4.3), "look": Vector3(1.35, 1.3, 0.0), "fov": 36.0},
	"Trader": {"word": "TRADE", "at": Vector3(7.6, 2.8, -5.86), "height": 2.4, "disc": CORAL, "disc_at": Vector3(7.2, 2.8, -5.89),
		"camera": Vector3(-2.0, 1.05, 6.8), "look": Vector3(0.8, 1.25, 0.0), "fov": 36.0},
	"Frame": {"word": "", "at": Vector3(7.7, 2.75, -5.86), "height": 2.0, "disc": ACID, "disc_at": Vector3(6.6, 3.0, -5.89),
		"camera": Vector3(-0.2, 0.55, 5.2), "look": Vector3(1.3, 1.3, 0.0), "fov": 36.0},
	"Settings": {"word": "SETUP", "at": Vector3(7.5, 2.6, -5.86), "height": 2.3, "disc": Color(0.74, 0.75, 0.73), "disc_at": Vector3(7.0, 2.5, -5.89),
		"camera": Vector3(-1.4, 2.4, 7.6), "look": Vector3(0.9, 1.0, 0.0), "fov": 36.0},
}

# The title screen shows once per launch, not every time a raid ends.
static var _seen_title: bool = false

var _tab: String = "Play"
var _content: VBoxContainer
var _credits: Label
var _tab_buttons: Dictionary = {}
var _marker: ColorRect
var _interface: Control
var _title: Control
var _prompt: Control
var _fade: ColorRect
var _ticker: Label
var _busy: bool = false

var _camera: Camera3D
var _camera_base: Vector3
var _camera_look: Vector3
var _word: Label3D
var _disc_material: StandardMaterial3D
var _disc: MeshInstance3D
var _rim: OmniLight3D
var _drift: Vector2 = Vector2.ZERO

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var first: String = "Play" if _seen_title else "Title"
	_camera_base = PAGES[first]["camera"]
	_camera_look = PAGES[first]["look"]
	_build_stage()
	_build_interface()
	_build_title()

	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 0.8)

	GameManager.profile_changed.connect(_refresh)
	if _seen_title:
		_title.visible = false
	else:
		_interface.modulate.a = 0.0
		_interface.visible = false
	_set_scene(first, false)
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
	env.background_color = CHALK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 1.0, 0.98)
	env.ambient_light_energy = 0.56
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.6
	var world := WorldEnvironment.new()
	world.environment = env
	viewport.add_child(world)

	var stage := Node3D.new()
	viewport.add_child(stage)
	var paper := StandardMaterial3D.new()
	paper.albedo_color = CHALK
	paper.roughness = 0.9
	_slab(stage, Vector3(0.0, -0.05, 0.0), Vector3(80.0, 0.1, 60.0), paper)
	_slab(stage, Vector3(0.0, 15.0, -6.0), Vector3(80.0, 30.0, 0.2), paper)

	# The disc: one flat field of colour behind Kestrel.
	_disc_material = StandardMaterial3D.new()
	_disc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_disc_material.albedo_color = ACID
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 2.75
	disc_mesh.bottom_radius = 2.75
	disc_mesh.height = 0.02
	disc_mesh.radial_segments = 96
	var disc := MeshInstance3D.new()
	disc.mesh = disc_mesh
	disc.material_override = _disc_material
	disc.rotation.x = PI * 0.5
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(disc)
	_disc = disc

	# The word on the wall, in front of the disc and behind Kestrel.
	_word = Label3D.new()
	_word.font = UiKit.display(900)
	_word.font_size = 256
	_word.outline_size = 0
	_word.modulate = INK
	_word.shaded = false
	_word.double_sided = false
	_word.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	stage.add_child(_word)

	# A spec caption, small, the way a studio shot labels its subject.
	var caption := Label3D.new()
	caption.font = UiKit.mono()
	caption.text = "K-27  KESTREL\nSALVAGE COURIER\nHEIGHT 2.05 M"
	caption.font_size = 160
	caption.pixel_size = 0.00078
	caption.line_spacing = 14.0
	caption.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	caption.modulate = INK
	caption.shaded = false
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	caption.position = Vector3(3.55, 0.42, -0.1)
	caption.rotation.y = -0.25
	stage.add_child(caption)

	# Floor marks: a ring to stand on and registration ticks either side.
	var ink_flat := StandardMaterial3D.new()
	ink_flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink_flat.albedo_color = INK
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.985
	ring_mesh.outer_radius = 1.0
	ring_mesh.rings = 96
	var ring := MeshInstance3D.new()
	ring.mesh = ring_mesh
	ring.material_override = ink_flat
	ring.scale.y = 0.02
	ring.position = Vector3(1.9, 0.003, 0.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(ring)
	for tick: Array in [[Vector3(0.55, 0.003, 0.0), Vector3(0.3, 0.004, 0.012)], [Vector3(3.25, 0.003, 0.0), Vector3(0.3, 0.004, 0.012)],
			[Vector3(1.9, 0.003, 1.35), Vector3(0.012, 0.004, 0.3)], [Vector3(1.9, 0.003, -1.35), Vector3(0.012, 0.004, 0.3)]]:
		_slab(stage, tick[0], tick[1], ink_flat).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Studio light: one soft key throwing a long shadow, and a kiss of the
	# page's colour from behind.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38.0, 42.0, 0.0)
	key.light_color = Color(1.0, 0.98, 0.94)
	key.light_energy = 0.5
	key.shadow_enabled = true
	key.shadow_blur = 2.4
	key.light_angular_distance = 2.5
	key.directional_shadow_max_distance = 40.0
	stage.add_child(key)
	_rim = OmniLight3D.new()
	_rim.position = Vector3(2.9, 1.9, -1.5)
	_rim.light_energy = 1.6
	_rim.omni_range = 4.5
	_rim.light_color = ACID
	stage.add_child(_rim)

	var kestrel := KestrelBody.new()
	kestrel.position = Vector3(1.9, 0.0, 0.0)
	kestrel.rotation.y = PI + 0.38
	stage.add_child(kestrel)
	kestrel.build(KestrelBody.MODEL_HEIGHT)

	_camera = Camera3D.new()
	_camera.position = _camera_base
	viewport.add_child(_camera)

func _slab(parent: Node3D, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = at
	parent.add_child(instance)
	return instance

# Moves the stage to a page: camera, wall word and disc colour.
func _set_scene(page: String, animate: bool = true) -> void:
	var spec: Dictionary = PAGES[page]
	var word: String = spec["word"]
	var disc: Color = spec["disc"]
	if page == "Frame":
		var frame: Dictionary = Catalog.FRAMES[GameManager.frame_id]
		word = (frame["name"] as String).to_upper()
		disc = frame["accent"]
	var height: float = spec["height"]
	var word_color: Color = spec.get("word_color", INK)
	var place := func() -> void:
		_word.text = word
		_word.modulate = Color(word_color, _word.modulate.a)
		_word.pixel_size = height / (256.0 * 0.72)
		_word.position = spec["at"]
	if not animate:
		place.call()
		_disc_material.albedo_color = disc
		_disc.position = spec["disc_at"]
		_rim.light_color = disc
		_camera.fov = spec["fov"]
		_camera_base = spec["camera"]
		_camera_look = spec["look"]
		return
	var tween := create_tween().set_parallel(true).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "_camera_base", spec["camera"], 1.1)
	tween.tween_property(self, "_camera_look", spec["look"], 1.1)
	tween.tween_property(_camera, "fov", spec["fov"], 1.1)
	tween.tween_property(_disc_material, "albedo_color", disc, 0.6)
	tween.tween_property(_disc, "position", spec["disc_at"], 1.1)
	tween.tween_property(_rim, "light_color", disc, 0.6)
	if _word.text != word:
		var swap := create_tween()
		swap.tween_property(_word, "modulate:a", 0.0, 0.18)
		swap.tween_callback(place)
		swap.tween_property(_word, "modulate:a", 1.0, 0.35)

# The camera breathes on its own and leans a little toward the mouse.
func _process(delta: float) -> void:
	var size := get_viewport_rect().size
	var mouse := (get_viewport().get_mouse_position() / size - Vector2(0.5, 0.5)).clamp(Vector2(-0.5, -0.5), Vector2(0.5, 0.5))
	_drift = _drift.lerp(mouse, minf(delta * 2.0, 1.0))
	var t := Time.get_ticks_msec() * 0.001
	_camera.position = _camera_base + Vector3(_drift.x * 0.3 + sin(t * 0.21) * 0.05, -_drift.y * 0.12 + sin(t * 0.33) * 0.025, 0.0)
	_camera.look_at(_camera_look, Vector3.UP)
	if _title.visible:
		_prompt.modulate.a = 0.55 + 0.45 * sin(t * 2.4)
	# The ticker crawls left and wraps on its own repeat.
	_ticker.position.x -= delta * 46.0
	if _ticker.position.x < -_ticker.size.x / 3.0:
		_ticker.position.x += _ticker.size.x / 3.0

# --- Title -------------------------------------------------------------------

func _build_title() -> void:
	_title = Control.new()
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	var top := _text("RELAY STATION 07   /   A SALVAGE RUN", 13, INK, "mono", 2)
	top.set_anchors_preset(Control.PRESET_TOP_LEFT)
	top.offset_left = 72.0
	top.offset_top = 56.0
	_title.add_child(top)
	_prompt = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = INK
	box.content_margin_left = 22
	box.content_margin_right = 22
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	_prompt.add_theme_stylebox_override("panel", box)
	_prompt.add_child(_text("PRESS ANY KEY", 14, CHALK, "mono", 3))
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_left = -110.0
	_prompt.offset_right = 110.0
	_prompt.offset_top = -74.0
	_prompt.offset_bottom = -36.0
	_title.add_child(_prompt)

func _unhandled_input(event: InputEvent) -> void:
	if not _title.visible or _busy:
		return
	if (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed():
		_enter()

# Title to menu: the camera sweeps in to the Play angle as the page comes up.
func _enter() -> void:
	if not _title.visible or _busy:
		return
	_busy = true
	_seen_title = true
	Sfx.play("ability", -10.0, 0.6)
	_set_scene(_tab)
	_interface.visible = true
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_title, "modulate:a", 0.0, 0.35)
	tween.tween_property(_interface, "modulate:a", 1.0, 0.6).set_delay(0.6)
	tween.chain().tween_callback(func() -> void:
		_title.visible = false
		_busy = false
		_place_marker(false))

# --- Interface ---------------------------------------------------------------

func _build_interface() -> void:
	_interface = Control.new()
	_interface.set_anchors_preset(Control.PRESET_FULL_RECT)
	_interface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_interface)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 72)
	margin.add_theme_constant_override("margin_top", 44)
	margin.add_theme_constant_override("margin_bottom", 64)
	_interface.add_child(margin)
	var page := VBoxContainer.new()
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_theme_constant_override("separation", 0)
	margin.add_child(page)

	# Top line: wordmark left; credits and quit right.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 28)
	page.add_child(top)
	top.add_child(_text("EXTRACTION", 34, INK, "display", 1))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	_credits = _text("", 15, INK, "mono-bold", 1)
	_credits.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_credits)
	var quit := _link("QUIT")
	quit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	quit.pressed.connect(func() -> void: get_tree().quit())
	top.add_child(quit)
	page.add_child(_gap(22))

	# Tabs. A block of acid slides behind whichever is active.
	var nav_holder := Control.new()
	nav_holder.custom_minimum_size.y = 34
	nav_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	page.add_child(nav_holder)
	_marker = ColorRect.new()
	_marker.color = ACID
	_marker.size = Vector2(60, 30)
	_marker.position.y = 2
	nav_holder.add_child(_marker)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 26)
	nav_holder.add_child(nav)
	for i in TABS.size():
		var tab := TABS[i]
		var b := Button.new()
		b.text = "%02d  %s" % [i + 1, tab.to_upper()]
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_override("font", UiKit.display(700, 1))
		b.add_theme_font_size_override("font_size", 24)
		for state: String in ["normal", "hover", "pressed", "focus"]:
			var pad := StyleBoxEmpty.new()
			pad.content_margin_left = 10
			pad.content_margin_right = 10
			b.add_theme_stylebox_override(state, pad)
		b.pressed.connect(_show_tab.bind(tab))
		nav.add_child(b)
		_tab_buttons[tab] = b
	page.add_child(_gap(38))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 760
	scroll.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	page.add_child(scroll)
	_content = VBoxContainer.new()
	_content.custom_minimum_size.x = 740
	_content.add_theme_constant_override("separation", 8)
	scroll.add_child(_content)

	# A slow ticker along the foot of the screen: the facts of the run.
	var band := ColorRect.new()
	band.color = INK
	band.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	band.offset_top = -34.0
	band.clip_contents = true
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_interface.add_child(band)
	_ticker = _text("", 12, CHALK, "mono", 2)
	_ticker.position.y = 8
	band.add_child(_ticker)

func _show_tab(tab: String) -> void:
	if tab == _tab:
		return
	Sfx.play("click", -8.0)
	_tab = tab
	_set_scene(tab)
	# Out, swap, in: the content slips sideways a few pixels as it changes.
	var tween := create_tween()
	tween.tween_property(_content, "modulate:a", 0.0, 0.09)
	tween.tween_callback(func() -> void:
		_refresh()
		_content.position.x = 24.0)
	tween.set_parallel(true)
	tween.tween_property(_content, "modulate:a", 1.0, 0.25)
	tween.tween_property(_content, "position:x", 0.0, 0.32).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

func _place_marker(animate: bool = true) -> void:
	var b: Button = _tab_buttons[_tab]
	if animate and _interface.visible:
		var tween := create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(_marker, "position:x", b.position.x, 0.3)
		tween.tween_property(_marker, "size:x", b.size.x, 0.3)
	else:
		_marker.position.x = b.position.x
		_marker.size.x = b.size.x

func _refresh() -> void:
	_credits.text = _money(GameManager.credits).to_upper()
	var stats := GameManager.stats
	var line := "RELAY STATION 07    ///    LOCKDOWN IN 12:00    ///    2 EXITS    ///    %d RAIDS    %d EXTRACTED    %d HOSTILES DOWN    ///    KESTREL K-27    ///    " % [stats["raids"], stats["extracted"], stats["kills"]]
	_ticker.text = line + line + line
	for tab: String in _tab_buttons:
		var b: Button = _tab_buttons[tab]
		b.add_theme_color_override("font_color", INK if tab == _tab else DIM)
		b.add_theme_color_override("font_hover_color", INK)
		b.add_theme_color_override("font_pressed_color", INK)
	_place_marker.call_deferred()
	for child in _content.get_children():
		child.queue_free()
	match _tab:
		"Play": _play()
		"Loadout": _loadout()
		"Trader": _trader()
		"Frame": _frames()
		"Settings": _settings()

# --- Pages -------------------------------------------------------------------

func _play() -> void:
	_content.add_child(_text("NEXT RAID", 13, INK, "mono-bold", 3))
	var title := _text("RELAY\nSTATION 07", 132, INK, "display-black")
	title.add_theme_constant_override("line_spacing", -30)
	_content.add_child(title)
	_content.add_child(_gap(4))
	_content.add_child(_text("Twelve minutes before the station locks down. Two ways out. Squads hold every building.", 18, DIM, "text", 0, true))
	_content.add_child(_gap(18))

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
	_fact("CARRYING", ", ".join(carrying))
	_fact("FRAME", "%s  ·  %d health  ·  %d shield  ·  %d slots" % [frame["name"], stats["health"], stats["shield"], stats["capacity"]])
	var last := GameManager.last_result
	if not last.is_empty():
		var extracted: bool = last["outcome"] == "extracted"
		_fact("LAST RAID", ("Extracted with %s" % _money(last["value"])) if extracted else ("Lost, with %d item%s" % [last["items"].size(), "" if last["items"].size() == 1 else "s"]),
			INK if extracted else CORAL.darkened(0.25))
	_content.add_child(_gap(22))

	var deploy := _block("DEPLOY  →", 34, Vector2(300, 74))
	deploy.pressed.connect(_deploy)
	_content.add_child(deploy)
	_content.add_child(_gap(18))
	_content.add_child(_text("WASD MOVE   SHIFT SPRINT   CTRL CROUCH   SPACE JUMP   R RELOAD\nF USE   H MEDKIT   Q / E ABILITIES   1 / 2 WEAPONS", 11, DIM, "mono", 1, true))

# Fade to black, then hand over to the raid.
func _deploy() -> void:
	if _busy:
		return
	_busy = true
	Sfx.play("extract", -8.0, 0.8)
	_fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_fade, "color:a", 1.0, 0.6)
	tween.tween_property(self, "_camera_base", _camera_base + Vector3(1.6, -0.1, -3.2), 0.7).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(GameManager.start_raid)

func _loadout() -> void:
	_heading("LOADOUT", "What you wear into the raid is lost if you die there.")
	for slot in GameManager.EQUIP_SLOTS:
		var id: String = GameManager.loadout[slot]
		var shown := Catalog.item_name(id) if id != "" else ("P9 Sidearm (issued)" if slot == "secondary" else "—")
		var remove: Button = null
		if id != "":
			remove = _link("UNEQUIP")
			remove.pressed.connect(GameManager.unequip.bind(slot))
		_row(SLOT_NAMES[slot], shown, Catalog.rarity_color(id) if id != "" else LINE, [remove], id == "" and slot != "secondary")
	_content.add_child(_gap(22))

	var salvage := 0
	var counts: Dictionary = {}
	for i in GameManager.stash.size():
		var id := GameManager.stash[i]
		if not counts.has(id):
			counts[id] = [0, i]
		counts[id][0] += 1
		if Catalog.item(id)["kind"] == "loot":
			salvage += Catalog.sell_price(id)
	var stash_line := HBoxContainer.new()
	stash_line.add_theme_constant_override("separation", 18)
	stash_line.add_child(_text("STASH", 44, INK, "display"))
	var count_label := _text("%d ITEM%s, SAFE BETWEEN RAIDS" % [GameManager.stash.size(), "" if GameManager.stash.size() == 1 else "S"], 12, DIM, "mono", 2)
	count_label.size_flags_vertical = Control.SIZE_SHRINK_END
	stash_line.add_child(count_label)
	_content.add_child(stash_line)
	if salvage > 0:
		var sell_all := _block("SELL ALL SALVAGE   %s" % _money(salvage), 20, Vector2(0, 44))
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
			equip = _link("EQUIP")
			equip.pressed.connect(GameManager.equip.bind(index, ""))
		var sell := _link("SELL  %s" % _money(Catalog.sell_price(id)))
		sell.pressed.connect(GameManager.sell.bind(index))
		var count: int = counts[id][0]
		_row((it["kind"] as String).to_upper(), it["name"] + ("  × %d" % count if count > 1 else ""), Catalog.rarity_color(id), [equip, sell])

func _trader() -> void:
	_heading("TRADER", "Bought gear goes to your stash. Selling it back returns half.")
	for id in Catalog.TRADER_STOCK:
		var it := Catalog.item(id)
		var buy := _link("BUY  %s" % _money(it["value"]))
		buy.disabled = GameManager.credits < int(it["value"])
		buy.pressed.connect(func() -> void: GameManager.buy(id))
		_row((it["kind"] as String).to_upper(), it["name"], Catalog.rarity_color(id), [buy], false, it.get("desc", ""))

# Three names stacked like a poster; the chosen one is inked, the others faint.
func _frames() -> void:
	_content.add_child(_text("FRAME", 13, INK, "mono-bold", 3))
	_content.add_child(_gap(2))
	for id: String in Catalog.FRAMES:
		var frame: Dictionary = Catalog.FRAMES[id]
		var current := id == GameManager.frame_id
		var b := Button.new()
		b.text = (frame["name"] as String).to_upper()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_override("font", UiKit.display(900))
		b.add_theme_font_size_override("font_size", 96)
		for state: String in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		b.add_theme_color_override("font_color", INK if current else Color(INK, 0.2))
		b.add_theme_color_override("font_hover_color", INK)
		b.add_theme_color_override("font_pressed_color", INK)
		b.custom_minimum_size.y = 84
		b.pressed.connect(func() -> void:
			if id != GameManager.frame_id:
				Sfx.play("ability", -12.0, 1.2)
				GameManager.set_frame(id)
				_set_scene("Frame"))
		_content.add_child(b)
	_content.add_child(_gap(14))
	var chosen: Dictionary = Catalog.FRAMES[GameManager.frame_id]
	_content.add_child(_text((chosen["role"] as String).to_upper(), 13, INK, "mono-bold", 3))
	_content.add_child(_text(chosen["passive"], 18, INK, "text", 0, true))
	_content.add_child(_gap(8))
	for ability: Array in [["Q", chosen["tactical"]], ["E", chosen["prime"]]]:
		var info: Dictionary = ability[1]
		_fact("%s   %s" % [ability[0], (info["name"] as String).to_upper()], "%s  (%ds)" % [info["desc"], int(info["cooldown"])])
	_content.add_child(_gap(6))
	_content.add_child(_text("FREE TO CHANGE BETWEEN RAIDS", 11, DIM, "mono", 2))

func _settings() -> void:
	_heading("SETTINGS", "Saved with your profile. Also on the pause screen during a raid.")
	_content.add_child(_gap(6))
	_content.add_child(UiKit.settings_rows(true, INK, DIM, LINE, INK))
	_content.add_child(_gap(14))
	_content.add_child(_text("High quality adds bounced light and reflections. Medium drops those. Low also drops fog and soft shading: use it if the game runs slowly.", 14, DIM, "text", 0, true))

# --- Pieces ------------------------------------------------------------------

# kind: "text" | "display" | "display-black" | "mono" | "mono-bold"
func _text(content: String, size: int, color: Color, kind: String = "text", tracking: int = 0, wrap: bool = false) -> Label:
	var label := Label.new()
	label.text = content
	var face: Font
	match kind:
		"display": face = UiKit.display(800, tracking)
		"display-black": face = UiKit.display(900, tracking)
		"mono": face = UiKit.mono(false, tracking)
		"mono-bold": face = UiKit.mono(true, tracking)
		_: face = UiKit.font(500, tracking)
	label.add_theme_font_override("font", face)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if wrap:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _heading(title: String, sub: String) -> void:
	_content.add_child(_text(title, 96, INK, "display-black"))
	_content.add_child(_text(sub, 16, DIM, "text", 0, true))
	_content.add_child(_gap(12))

# A small label and its value on one line.
func _fact(label: String, value: String, color: Color = INK) -> void:
	var row := HBoxContainer.new()
	var name_label := _text(label, 12, DIM, "mono", 2)
	name_label.custom_minimum_size.x = 170
	name_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(name_label)
	var value_label := _text(value, 16, color, "text", 0, true)
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value_label)
	_content.add_child(row)

# One line of a list: a rarity tick, a small tag, the name, an optional
# description, actions on the right, and a hairline under it.
func _row(tag: String, title: String, tick: Color, actions: Array, faint: bool = false, desc: String = "") -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.custom_minimum_size.y = 34
	var mark := ColorRect.new()
	mark.color = tick
	mark.custom_minimum_size = Vector2(5, 20)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(mark)
	var tag_label := _text(tag, 11, DIM, "mono", 2)
	tag_label.custom_minimum_size.x = 96
	row.add_child(tag_label)
	var name_label := _text(title, 18, DIM if faint else INK)
	name_label.add_theme_font_override("font", UiKit.font(600))
	name_label.custom_minimum_size.x = 210
	row.add_child(name_label)
	var desc_label := _text(desc, 13, DIM)
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_label.clip_text = true
	row.add_child(desc_label)
	for action: Variant in actions:
		if action != null:
			row.add_child(action)
	_content.add_child(row)
	var line := ColorRect.new()
	line.color = LINE
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_child(line)

# A small text action. It takes an acid highlight when the pointer is on it.
func _link(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", UiKit.mono(true, 1))
	b.add_theme_font_size_override("font_size", 12)
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = ACID if state == "hover" else (INK if state == "pressed" else Color(0, 0, 0, 0))
		box.content_margin_left = 9
		box.content_margin_right = 9
		box.content_margin_top = 5
		box.content_margin_bottom = 5
		b.add_theme_stylebox_override(state, box)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", CHALK)
	b.add_theme_color_override("font_disabled_color", Color(INK, 0.28))
	b.pressed.connect(func() -> void: Sfx.play("click", -8.0))
	return b

# The one heavy button: an ink block that turns acid under the pointer.
func _block(text: String, font_size: int, minimum: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = minimum
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_font_override("font", UiKit.display(800, 2))
	b.add_theme_font_size_override("font_size", font_size)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = ACID if state == "hover" else (INK.lightened(0.15) if state == "pressed" else INK)
		box.content_margin_left = 26
		box.content_margin_right = 26
		b.add_theme_stylebox_override(state, box)
	b.add_theme_color_override("font_color", CHALK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", CHALK)
	b.pressed.connect(func() -> void: Sfx.play("click", -8.0))
	return b

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
