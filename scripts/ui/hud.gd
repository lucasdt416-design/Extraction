class_name Hud
extends CanvasLayer

# Everything drawn over the raid. It reads the player, the raid and
# GameManager and draws what it finds; it decides nothing (rule 6). The only
# intents it emits are "return to base" and "abandon raid", both of which it
# hands to GameManager / the raid to act on.

const INK := Color(0.94, 0.95, 0.96)
const DIM := Color(0.94, 0.95, 0.96, 0.55)
const TEAL := Color(0.40, 0.86, 0.82)
const SHIELD := Color(0.62, 0.82, 1.0)
const DANGER := Color(1.0, 0.36, 0.30)
const MARGIN: float = 44.0

var _raid: Raid
var _player: Player
var _canvas: Control
var _font: Font
var _ammo: Label
var _reserve: Label
var _weapon: Label
var _abilities: Label
var _status: Label
var _clock: Label
var _pack: Label
var _prompt: Label
var _notice: Label
var _comms: Label
var _overlay: Control
var _paused_panel: Control

var _hit_time: float = 0.0
var _hit_kind: int = 0
var _hurt_flash: float = 0.0
var _shield_flash: float = 0.0
var _hurt_sources: Array[Dictionary] = []   # {"position": Vector3, "left": float}
var _comm_lines: Array[Dictionary] = []     # {"text": String, "left": float}
var _notice_left: float = 0.0

func _ready() -> void:
	add_to_group("hud")
	layer = 5   # above the lens layer the raid adds
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = ThemeDB.fallback_font
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_overlay)
	add_child(_canvas)

	_clock = _label(Control.PRESET_TOP_LEFT, Vector2(MARGIN, MARGIN - 8), 26, INK)
	_pack = _label(Control.PRESET_TOP_LEFT, Vector2(MARGIN, MARGIN + 28), 15, DIM)
	_status = _label(Control.PRESET_BOTTOM_LEFT, Vector2(MARGIN, -MARGIN - 18), 15, DIM)
	_ammo = _label(Control.PRESET_BOTTOM_RIGHT, Vector2(-MARGIN - 300, -MARGIN - 74), 46, INK, HORIZONTAL_ALIGNMENT_RIGHT, 230)
	_reserve = _label(Control.PRESET_BOTTOM_RIGHT, Vector2(-MARGIN - 62, -MARGIN - 48), 18, DIM, HORIZONTAL_ALIGNMENT_LEFT, 70)
	_weapon = _label(Control.PRESET_BOTTOM_RIGHT, Vector2(-MARGIN - 300, -MARGIN - 18), 15, DIM, HORIZONTAL_ALIGNMENT_RIGHT, 300)
	_abilities = _label(Control.PRESET_BOTTOM_RIGHT, Vector2(-MARGIN - 300, -MARGIN - 128), 15, DIM, HORIZONTAL_ALIGNMENT_RIGHT, 300)
	_prompt = _label(Control.PRESET_CENTER, Vector2(-200, 62), 17, INK, HORIZONTAL_ALIGNMENT_CENTER, 400)
	_notice = _label(Control.PRESET_CENTER, Vector2(-250, 150), 17, INK, HORIZONTAL_ALIGNMENT_CENTER, 500)
	_comms = _label(Control.PRESET_TOP_RIGHT, Vector2(-MARGIN - 420, MARGIN - 8), 15, DIM, HORIZONTAL_ALIGNMENT_RIGHT, 420)

func bind(raid: Raid) -> void:
	_raid = raid
	_player = raid.player
	_player.hit_confirmed.connect(func(result: int) -> void:
		_hit_time = 0.22
		_hit_kind = result)
	_player.damaged.connect(func(from: Vector3, _amount: float, shield_only: bool) -> void:
		if shield_only:
			_shield_flash = 1.0
		else:
			_hurt_flash = 1.0
		_hurt_sources.append({"position": from, "left": 1.4}))
	_player.notice.connect(show_notice)

# Called through the "hud" group by Squad.bark.
func show_comm(speaker: String, line: String, _position: Vector3) -> void:
	_comm_lines.append({"text": "%s   %s" % [speaker.to_upper(), line], "left": 5.0})
	if _comm_lines.size() > 5:
		_comm_lines.pop_front()

func show_notice(text: String) -> void:
	_notice.text = text
	_notice_left = 2.2

func _process(delta: float) -> void:
	if _player == null:
		return
	_hit_time = maxf(_hit_time - delta, 0.0)
	_hurt_flash = maxf(_hurt_flash - delta * 1.6, 0.0)
	_shield_flash = maxf(_shield_flash - delta * 2.4, 0.0)
	_notice_left = maxf(_notice_left - delta, 0.0)
	_notice.modulate.a = clampf(_notice_left, 0.0, 1.0)
	for i in range(_hurt_sources.size() - 1, -1, -1):
		_hurt_sources[i]["left"] -= delta
		if _hurt_sources[i]["left"] <= 0.0:
			_hurt_sources.remove_at(i)
	var feed := ""
	for i in range(_comm_lines.size() - 1, -1, -1):
		_comm_lines[i]["left"] -= delta
		if _comm_lines[i]["left"] <= 0.0:
			_comm_lines.remove_at(i)
	for line in _comm_lines:
		feed += line["text"] + "\n"
	_comms.text = feed

	var gun := _player.gun()
	_ammo.text = str(gun.mag)
	_ammo.add_theme_color_override("font_color", DANGER if gun.mag <= int(gun.def["mag"]) / 4 else INK)
	_reserve.text = "/ ∞" if gun.infinite_reserve else "/ %d" % gun.reserve
	_weapon.text = Catalog.item_name(gun.id) + ("   reloading" if gun.is_reloading() else "")
	var frame := _player.frame_def
	_abilities.text = "%s\n%s" % [
		_ability_line("Q", frame["tactical"]["name"], _player.tactical_cooldown),
		_ability_line("E", frame["prime"]["name"], _player.prime_cooldown)]
	var meds := GameManager.backpack.count("medkit")
	_status.text = "H  Medkit × %d" % meds if _player.heal_left <= 0.0 else "Healing…"
	var seconds := int(maxf(_raid.time_left, 0.0))
	_clock.text = "%02d:%02d" % [seconds / 60, seconds % 60]
	_clock.add_theme_color_override("font_color", DANGER if seconds < 120 else INK)
	_pack.text = "Backpack %d / %d   ·   %d cr" % [GameManager.backpack.size(), GameManager.capacity(), GameManager.backpack_value()]

	var prompt := ""
	for point in _raid.extract_points:
		if point.occupant != null:
			prompt = "Extracting   %.1f" % maxf(point.hold_time - point.progress, 0.0)
	if prompt == "" and _player.interact_label != "":
		prompt = "F   " + _player.interact_label
	_prompt.text = prompt
	_canvas.queue_redraw()

func _ability_line(key: String, ability_name: String, cooldown: float) -> String:
	return "%s   %s   %s" % [ability_name, ("%ds" % ceili(cooldown)) if cooldown > 0.0 else "ready", key]

# --- Drawing -----------------------------------------------------------------

func _draw_overlay() -> void:
	if _player == null:
		return
	var size := _canvas.size
	var center := size * 0.5
	var camera := get_viewport().get_camera_3d()

	# Edge tint: red when hurt or low, blue when the shield took it.
	var low := clampf(1.0 - _player.health / (_player.max_health * 0.45), 0.0, 1.0) * 0.5
	_edge_tint(size, Color(DANGER.r, 0.1, 0.08, maxf(_hurt_flash * 0.2, low * (0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.006)))))
	_edge_tint(size, Color(SHIELD.r, SHIELD.g, SHIELD.b, _shield_flash * 0.28))
	if _player.fortify_left > 0.0 or _player.overcharge_left > 0.0 or _player.cloak_left > 0.0:
		_edge_tint(size, Color(_player.frame_def["accent"], 0.16))

	# Health and shield: two thin bars, shield on top.
	var bar := Vector2(MARGIN, size.y - MARGIN - 52.0)
	var width := 280.0
	_canvas.draw_rect(Rect2(bar, Vector2(width, 3.0)), Color(1, 1, 1, 0.14))
	_canvas.draw_rect(Rect2(bar, Vector2(width * _player.shield / maxf(_player.max_shield, 1.0), 3.0)), SHIELD)
	_canvas.draw_rect(Rect2(bar + Vector2(0, 8), Vector2(width, 7.0)), Color(1, 1, 1, 0.14))
	_canvas.draw_rect(Rect2(bar + Vector2(0, 8), Vector2(width * _player.health / _player.max_health, 7.0)), DANGER if _player.health < _player.max_health * 0.3 else INK)
	_canvas.draw_string(_font, bar + Vector2(width + 12.0, 16.0), str(ceili(_player.health)), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, INK)

	if _player.is_dead or (_raid != null and _raid.over):
		return

	# Crosshair: four ticks that open with the weapon's current spread.
	var def := _player.gun().def
	var spread: float = float(def["spread"]) * (float(def["ads"]) if _player.is_aiming else 1.0) + _player.bloom
	var gap := 5.0 + spread * 5.0 + Vector2(_player.velocity.x, _player.velocity.z).length() * 0.9
	var cross := Color(INK, 0.9 if not _player.is_aiming or float(def["ads"]) > 0.3 else 0.35)
	for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
		_canvas.draw_line(center + dir * gap, center + dir * (gap + 7.0), cross, 1.5, true)
	_canvas.draw_circle(center, 1.2, cross)
	if _hit_time > 0.0:
		var color := DANGER if _hit_kind >= 2 else INK
		var reach := 9.0 + (0.22 - _hit_time) * 30.0 + (4.0 if _hit_kind == 3 else 0.0)
		for dir: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			_canvas.draw_line(center + dir * reach, center + dir * (reach + 7.0), Color(color, _hit_time / 0.22), 2.0, true)

	# Hold-to-use and reload progress, as a short line under the crosshair.
	var progress := _player.interact_progress
	if _player.gun().is_reloading():
		progress = _player.gun().reload_progress()
	elif _player.heal_left > 0.0:
		progress = 1.0 - _player.heal_left / 3.0
	if progress > 0.0:
		_canvas.draw_rect(Rect2(center + Vector2(-40, 44), Vector2(80, 2)), Color(1, 1, 1, 0.2))
		_canvas.draw_rect(Rect2(center + Vector2(-40, 44), Vector2(80 * clampf(progress, 0.0, 1.0), 2)), TEAL)

	# Where the damage came from.
	for source in _hurt_sources:
		var to: Vector3 = (source["position"] as Vector3) - _player.global_position
		var local := _player.global_transform.basis.inverse() * to
		var angle := atan2(local.x, -local.z)
		_canvas.draw_arc(center, 120.0, angle - PI * 0.5 - 0.22, angle - PI * 0.5 + 0.22, 12, Color(DANGER, clampf(source["left"], 0.0, 1.0) * 0.85), 4.0, true)

	# Detection: how close the most suspicious enemy is to spotting you.
	var seen := 0.0
	for node in get_tree().get_nodes_in_group("enemy"):
		var enemy := node as Enemy
		if enemy == null or enemy.is_dead:
			continue
		if enemy.state != Enemy.State.COMBAT:
			seen = maxf(seen, enemy.awareness)
		if _player.pulse_left > 0.0 and camera != null and enemy.global_position.distance_to(_player.global_position) < 45.0:
			var at := enemy.global_position + Vector3.UP * 1.1
			if not camera.is_position_behind(at):
				var screen := camera.unproject_position(at)
				_canvas.draw_arc(screen, 9.0, 0.0, TAU, 20, Color(DANGER, 0.9), 1.5, true)
	if seen > 0.03 and seen < 0.999:
		_canvas.draw_arc(center, 30.0, -PI * 0.5 - seen * PI, -PI * 0.5 + seen * PI, 32, Color(1.0, 0.85, 0.5, 0.4 + seen * 0.6), 2.0, true)

	# Extraction markers, pinned to the screen edge when off screen.
	if camera != null:
		for point in _raid.extract_points:
			var world: Vector3 = point.global_position + Vector3.UP * 2.2
			var screen := camera.unproject_position(world)
			if camera.is_position_behind(world):
				screen = center + (center - screen).normalized() * 4000.0
			screen = screen.clamp(Vector2(140, 130), size - Vector2(140, 240))
			var distance := int(point.global_position.distance_to(_player.global_position))
			_canvas.draw_arc(screen, 6.0, 0.0, TAU, 16, TEAL, 1.5, true)
			_canvas.draw_string(_font, screen + Vector2(-100, 24), "%s  %dm" % [point.label, distance], HORIZONTAL_ALIGNMENT_CENTER, 200, 13, Color(TEAL, 0.9))

func _edge_tint(size: Vector2, color: Color) -> void:
	if color.a <= 0.005:
		return
	var clear := Color(color, 0.0)
	var depth := size.y * 0.22
	for edge: Array in [
		[Vector2(0, 0), Vector2(size.x, 0), Vector2(size.x, depth), Vector2(0, depth)],
		[Vector2(0, size.y), Vector2(size.x, size.y), Vector2(size.x, size.y - depth), Vector2(0, size.y - depth)],
		[Vector2(0, 0), Vector2(0, size.y), Vector2(depth, size.y), Vector2(depth, 0)],
		[Vector2(size.x, 0), Vector2(size.x, size.y), Vector2(size.x - depth, size.y), Vector2(size.x - depth, 0)],
	]:
		_canvas.draw_polygon(PackedVector2Array(edge), PackedColorArray([color, color, clear, clear]))

# --- Overlays ----------------------------------------------------------------

func show_result(result: Dictionary) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var title := "Extracted"
	# Tolerates an empty result (a raid scene run on its own, outside the menu flow).
	var outcome: String = result.get("outcome", "died")
	var detail := "%d items secured, worth %d credits." % [result.get("items", []).size(), result.get("value", 0)]
	if outcome == "died":
		title = "Killed in the raid"
		detail = "Everything you carried and wore is gone."
	elif outcome == "lost":
		title = "Locked in"
		detail = "The station sealed before you got out. Your kit stays inside."
	var seconds := int(result.get("time", 0.0))
	var lines := "%s\n\n%d hostiles down   ·   %02d:%02d in the raid" % [detail, result.get("kills", 0), seconds / 60, seconds % 60]
	_overlay = _panel(title, lines, [["Return to base", GameManager.return_to_menu]], 0.62 if outcome != "extracted" else 0.72)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause") or _raid == null or _raid.over:
		return
	if _paused_panel != null:
		_resume()
		return
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_paused_panel = _panel("Paused", "Abandoning the raid counts as dying: you lose what you brought.", [
		["Resume", _resume],
		["Abandon raid", func() -> void:
			get_tree().paused = false
			_paused_panel.queue_free()
			_paused_panel = null
			_raid._end("died")],
	], 0.78, true)

func _resume() -> void:
	if _paused_panel != null:
		_paused_panel.queue_free()
		_paused_panel = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _panel(title: String, body: String, actions: Array, dim: float, with_settings: bool = false) -> Control:
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.035, 0.045, 0.0)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	shade.create_tween().tween_property(shade, "color:a", dim, 0.5)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.offset_left = -280.0
	column.offset_right = 280.0
	column.offset_top = -220.0 if with_settings else -150.0
	column.offset_bottom = 220.0 if with_settings else 150.0
	column.add_theme_constant_override("separation", 18)
	shade.add_child(column)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 44)
	heading.add_theme_color_override("font_color", INK)
	column.add_child(heading)
	var text := Label.new()
	text.text = body
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_size_override("font_size", 17)
	text.add_theme_color_override("font_color", DIM)
	column.add_child(text)
	if with_settings:
		column.add_child(UiKit.settings_rows())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	for action: Array in actions:
		var button := UiKit.button(action[0], row.get_child_count() == 0)
		button.pressed.connect(action[1])
		row.add_child(button)
	return shade

func _label(preset: Control.LayoutPreset, offset: Vector2, font_size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = 400.0) -> Label:
	var label := Label.new()
	label.set_anchors_preset(preset)
	label.offset_left = offset.x
	label.offset_top = offset.y
	label.offset_right = offset.x + width
	label.offset_bottom = offset.y + font_size * 1.4
	label.grow_vertical = Control.GROW_DIRECTION_END
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	label.add_theme_constant_override("shadow_offset_y", 1)
	_canvas.add_child(label)
	return label
