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
const MAP_SIZE: float = 190.0     # the corner map, in pixels
const MAP_SHOWS: float = 380.0    # how many metres across it shows

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
const DevConsole = preload("res://scripts/ui/dev_console.gd")
var _dev_console: DevConsole
var _inventory: Control
var _inventory_rows: VBoxContainer
var _inventory_slots: VBoxContainer
var _inventory_actions: HBoxContainer
var _inventory_heading: Label
var _inventory_detail: Label
var _inventory_message: Label
var _inventory_index: int = -1
var _inventory_slot: String = ""

var _hit_time: float = 0.0
var _hit_kind: int = 0
var _hurt_flash: float = 0.0
var _shield_flash: float = 0.0
var _hurt_sources: Array[Dictionary] = []   # {"position": Vector3, "left": float}
var _comm_lines: Array[Dictionary] = []     # {"text": String, "left": float}
var _notice_left: float = 0.0
var _toasts: Array[Dictionary] = []          # {"id": String, "left": float}
var _pack_size: int = 0
var _kill_time: float = 0.0
var _kills: int = 0
var _alert_text: String = ""
var _alert_left: float = 0.0
var _tracked_exit := -1

func _ready() -> void:
	add_to_group("hud")
	layer = 5   # above the lens layer the raid adds
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = UiKit.font(600)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_overlay)
	add_child(_canvas)

	_clock = _label(Control.PRESET_TOP_LEFT, Vector2(MARGIN, MARGIN - 14), 38, INK)
	_pack = _label(Control.PRESET_TOP_LEFT, Vector2(MARGIN, MARGIN + 34), 13, DIM)
	_status = _label(Control.PRESET_BOTTOM_LEFT, Vector2(MARGIN, -MARGIN - 18), 15, DIM)
	_ammo = _label(Control.PRESET_BOTTOM_RIGHT, Vector2(-MARGIN - 300, -MARGIN - 96), 46, INK, HORIZONTAL_ALIGNMENT_RIGHT, 230)
	_reserve = _label(Control.PRESET_BOTTOM_RIGHT, Vector2(-MARGIN - 62, -MARGIN - 48), 18, DIM, HORIZONTAL_ALIGNMENT_LEFT, 70)
	_weapon = _label(Control.PRESET_BOTTOM_RIGHT, Vector2(-MARGIN - 400, -MARGIN - 24), 22, DIM, HORIZONTAL_ALIGNMENT_RIGHT, 400)
	_abilities = _label(Control.PRESET_BOTTOM_RIGHT, Vector2(-MARGIN - 300, -MARGIN - 172), 15, DIM, HORIZONTAL_ALIGNMENT_RIGHT, 300)
	_prompt = _label(Control.PRESET_CENTER, Vector2(-250, 58), 26, INK, HORIZONTAL_ALIGNMENT_CENTER, 500)
	_notice = _label(Control.PRESET_CENTER, Vector2(-250, 150), 17, INK, HORIZONTAL_ALIGNMENT_CENTER, 500)
	_comms = _label(Control.PRESET_TOP_RIGHT, Vector2(-MARGIN - 420, MARGIN - 8), 15, DIM, HORIZONTAL_ALIGNMENT_RIGHT, 420)
	# Figures in the display face; everything else in the text face.
	for figure: Label in [_clock, _ammo, _weapon, _prompt]:
		figure.add_theme_font_override("font", UiKit.display(800, 1))
	_ammo.add_theme_font_size_override("font_size", 64)
	for small: Label in [_reserve, _comms, _pack]:
		small.add_theme_font_override("font", UiKit.mono())

func bind(raid: Raid) -> void:
	_raid = raid
	_player = raid.player
	_player.hit_confirmed.connect(func(result: int) -> void:
		_hit_time = 0.22
		_hit_kind = result
		if result == 3:
			_kill_time = 1.6
			_kills += 1)
	_player.damaged.connect(func(from: Vector3, _amount: float, shield_only: bool) -> void:
		if shield_only:
			_shield_flash = 1.0
		else:
			_hurt_flash = 1.0
		_hurt_sources.append({"position": from, "left": 1.4}))
	_player.notice.connect(show_notice)
	_pack_size = GameManager.backpack.size()
	GameManager.backpack_changed.connect(_on_backpack_changed)
	if raid.level.minimap != null:
		_comms.position.y += MAP_SIZE + 26.0   # the comms feed moves down to make room
	_play_intro()
	if OS.is_debug_build():
		_dev_console = DevConsole.new()
		_dev_console.raid = raid
		add_child(_dev_console)

# Something new in the backpack: announce it on the right of the screen.
func _on_backpack_changed() -> void:
	var size := GameManager.backpack.size()
	if size > _pack_size:
		_toasts.append({"id": GameManager.backpack[size - 1], "left": 3.5})
		if _toasts.size() > 4:
			_toasts.pop_front()
	_pack_size = size
	if _inventory != null:
		_refresh_inventory.call_deferred()

# The first seconds of a raid: up from black, with the map's name on a card.
func _play_intro() -> void:
	var map: Dictionary = Catalog.MAPS[GameManager.map_id]
	var black := ColorRect.new()
	black.color = Color(0.03, 0.035, 0.04)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	var card := VBoxContainer.new()
	card.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	card.offset_left = MARGIN + 28.0
	card.offset_top = -420.0
	card.offset_bottom = -190.0
	card.offset_right = 1100.0
	card.alignment = BoxContainer.ALIGNMENT_END
	card.add_theme_constant_override("separation", 0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)
	card.add_child(_line("INSERTION", 13, UiKit.ACID, UiKit.mono(true, 4)))
	var name_line := _line((map["name"] as String).to_upper(), 132, INK, UiKit.display(900))
	card.add_child(name_line)
	card.add_child(_line("%02d:00 TO LOCKDOWN   /   %d EXITS   /   GET OUT WITH WHAT YOU CAN CARRY" % [map["minutes"], map["exits"]], 13, INK, UiKit.mono(false, 2)))
	card.modulate.a = 0.0
	_canvas.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(card, "modulate:a", 1.0, 0.35).set_delay(0.25)
	tween.parallel().tween_property(black, "color:a", 0.0, 1.6).set_delay(0.5)
	tween.tween_interval(1.5)
	tween.tween_property(card, "modulate:a", 0.0, 0.6)
	tween.parallel().tween_property(_canvas, "modulate:a", 1.0, 0.6)
	tween.tween_callback(func() -> void:
		black.queue_free()
		card.queue_free())

# Called through the "hud" group by Squad.bark.
func show_comm(speaker: String, line: String, _position: Vector3) -> void:
	_comm_lines.append({"text": "%s   %s" % [speaker.to_upper(), line], "left": 5.0})
	if _comm_lines.size() > 5:
		_comm_lines.pop_front()

# A warning that matters more than a notice: coral, large, top centre.
func show_alert(text: String) -> void:
	_alert_text = text
	_alert_left = 4.0

func show_notice(text: String) -> void:
	_notice.text = text
	_notice_left = 2.2

func _process(delta: float) -> void:
	if _player == null:
		return
	_hit_time = maxf(_hit_time - delta, 0.0)
	_kill_time = maxf(_kill_time - delta, 0.0)
	_alert_left = maxf(_alert_left - delta, 0.0)
	for i in range(_toasts.size() - 1, -1, -1):
		_toasts[i]["left"] -= delta
		if _toasts[i]["left"] <= 0.0:
			_toasts.remove_at(i)
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
	_weapon.text = Catalog.item_name(gun.id).to_upper() + ("   /   RELOADING" if gun.is_reloading() else "")
	var frame := _player.frame_def
	_abilities.text = ""
	var meds := GameManager.backpack.count("medkit")
	_status.text = ""
	var seconds := int(maxf(_raid.time_left, 0.0))
	_clock.text = "%02d:%02d" % [seconds / 60, seconds % 60]
	_clock.add_theme_color_override("font_color", DANGER if seconds < 120 else INK)
	_pack.text = ""

	var prompt := ""
	var nearby_drone := ""
	var drone_distance := 80.0
	for point in _raid.extract_points:
		var called: String = point.status()
		var distance := point.global_position.distance_to(_player.global_position)
		if called != "" and distance < drone_distance:
			nearby_drone = called
			drone_distance = distance
		if point.occupant != null and (point.drone_scene == null or point.eta == 0.0):
			prompt = "HOLD INSIDE PAD   %.1fS" % maxf(point.hold_time - point.progress, 0.0)
			break
		if point.occupant != null and point.drone_scene != null:
			prompt = "CALLING DRONE" if point.eta < 0.0 else called + "   /   RETURN TO PAD TO BOARD"
			break
	if prompt == "" and _player.interact_label != "":
		prompt = "[ F ]   " + _player.interact_label.to_upper()
	_prompt.text = nearby_drone if prompt.is_empty() else prompt
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

	var sight := _player.sight_blend() if _inventory == null else 0.0
	var sight_type: String = _player.gun().def["sight"]
	var scoped := _player.gun().has_scope() and sight > 0.0
	if scoped:
		_draw_scope(size, sight, sight_type == "prism")
	# Edge tint: red when hurt or low, blue when the shield took it.
	var low := clampf(1.0 - _player.health / (_player.max_health * 0.45), 0.0, 1.0) * 0.5
	_edge_tint(size, Color(DANGER.r, 0.1, 0.08, maxf(_hurt_flash * 0.2, low * (0.7 + 0.3 * sin(Time.get_ticks_msec() * 0.006)))))
	_edge_tint(size, Color(SHIELD.r, SHIELD.g, SHIELD.b, _shield_flash * 0.28))
	if _player.fortify_left > 0.0 or _player.overcharge_left > 0.0 or _player.cloak_left > 0.0:
		_edge_tint(size, Color(_player.frame_def["accent"], 0.16))

	var display := UiKit.display(800, 1)
	var mono := UiKit.mono(true, 1)
	var acid := UiKit.ACID
	var hurt := _player.health < _player.max_health * 0.3

	# Bottom left: health as a big numeral, with shield and health bars beside it.
	var base := Vector2(MARGIN, size.y - MARGIN)
	_canvas.draw_string(display, base + Vector2(0, -8), str(ceili(_player.health)), HORIZONTAL_ALIGNMENT_LEFT, -1, 64, DANGER if hurt else INK)
	var bar := base + Vector2(118, -44)
	var width := 240.0
	_canvas.draw_rect(Rect2(bar, Vector2(width, 5)), Color(1, 1, 1, 0.16))
	_canvas.draw_rect(Rect2(bar, Vector2(width * _player.shield / maxf(_player.max_shield, 1.0), 5)), acid)
	_canvas.draw_rect(Rect2(bar + Vector2(0, 10), Vector2(width, 10)), Color(1, 1, 1, 0.16))
	_canvas.draw_rect(Rect2(bar + Vector2(0, 10), Vector2(width * _player.health / _player.max_health, 10)), DANGER if hurt else INK)
	# Medkits: the key, then a pip for each one carried.
	var meds := GameManager.backpack.count("medkit")
	_keycap(bar + Vector2(0, 30), "H", _player.heal_left > 0.0)
	for i in GameManager.MAX_MEDKITS:
		_canvas.draw_rect(Rect2(bar + Vector2(32 + i * 14, 36), Vector2(9, 9)), INK if i < meds else Color(1, 1, 1, 0.18))
	_canvas.draw_string(mono, bar + Vector2(84, 45), "HEALING" if _player.heal_left > 0.0 else "MEDKIT", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)
	_keycap(bar + Vector2(145, 30), "G", _player.grenades > 0 or _player.dev_infinite_grenades)
	var charges := "INF" if _player.dev_infinite_grenades else str(_player.grenades)
	_canvas.draw_string(mono, bar + Vector2(176, 45), "%s BREACH" % charges, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)
	if _player.dev_invulnerable:
		_canvas.draw_string(mono, Vector2(center.x - 120.0, MARGIN + 12.0), "GOD MODE  /  CLOCK HELD",
			HORIZONTAL_ALIGNMENT_CENTER, 240, 12, TEAL)

	# Top left, under the clock: one square per backpack slot, then what it's worth.
	var slots := Vector2(MARGIN, MARGIN + 44)
	_canvas.draw_string(mono, slots + Vector2(96, -22), "TO LOCKDOWN", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)
	var carried := GameManager.backpack.size()
	var capacity := GameManager.capacity()
	for i in capacity:
		_canvas.draw_rect(Rect2(slots + Vector2(i * 13, 0), Vector2(9, 9)), (acid if carried >= capacity else INK) if i < carried else Color(1, 1, 1, 0.18))
	_canvas.draw_string(mono, slots + Vector2(capacity * 13 + 10, 9), "%d CR   [TAB] PACK" % GameManager.backpack_value(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DIM)

	if Catalog.CONTRACTS.has(GameManager.active_contract):
		var contract: Dictionary = Catalog.CONTRACTS[GameManager.active_contract]
		var progress := GameManager.contract_progress()
		var status := "READY TO EXTRACT" if progress >= contract["target"] else "%d/%d %s" % [progress, contract["target"], contract["unit"]]
		_canvas.draw_string(mono, slots + Vector2(0, 33), "%s   /   %s" % [contract["name"].to_upper(), status.to_upper()],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, acid if progress >= contract["target"] else INK)
	var navigation := "B  TRACK EXIT"
	if _tracked_exit >= 0:
		var exit_point := _raid.extract_points[_tracked_exit]
		var distance := roundi(_player.global_position.distance_to(exit_point.global_position))
		navigation = "B  %s  %d M" % [exit_point.label.to_upper(), distance]
		if exit_point.drone_scene != null:
			if exit_point.eta > 0.0:
				navigation += "  /  DRONE %dS" % ceili(exit_point.eta)
			elif exit_point.eta < 0.0:
				navigation += "  /  CALL DRONE"
			else:
				navigation += "  /  DRONE READY"
	_canvas.draw_string(mono, slots + Vector2(0, 52), navigation, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, TEAL)

	# Bottom right, above the ammo: the two abilities, each with its key and a
	# bar that fills as it comes off cooldown.
	var frame := _player.frame_def
	var chips := [["Q", frame["tactical"], _player.tactical_cooldown], ["E", frame["prime"], _player.prime_cooldown]]
	for i in 2:
		var ability: Dictionary = chips[i][1]
		var left: float = chips[i][2]
		var at := Vector2(size.x - MARGIN - 210, size.y - MARGIN - 196 + i * 34)
		var ready := left <= 0.0
		_keycap(at, chips[i][0], ready)
		_canvas.draw_string(display, at + Vector2(34, 19), (ability["name"] as String).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, INK if ready else DIM)
		_canvas.draw_rect(Rect2(at + Vector2(150, 9), Vector2(60, 4)), Color(1, 1, 1, 0.16))
		_canvas.draw_rect(Rect2(at + Vector2(150, 9), Vector2(60 * (1.0 - clampf(left / float(ability["cooldown"]), 0.0, 1.0)), 4)), acid if ready else INK)

	if _player.is_dead or (_raid != null and _raid.over):
		return
	if _inventory == null and _prompt.text.begins_with("[ F ]") and is_instance_valid(_player.aimed_pickup):
		var pickup := _player.aimed_pickup
		var id := pickup.item_id
		var details := "RESTOCKS CARRIED WEAPONS"
		var color := DIM
		if id != Pickup.AMMO:
			var rarity: int = Catalog.item(id)["rarity"]
			color = Catalog.rarity_color(id)
			details = "%s   /   %d CR SELL VALUE" % [Catalog.RARITY_NAMES[rarity].to_upper(), Catalog.sell_price(id)]
			if pickup.weapon != null:
				details += "   /   %d LOADED" % pickup.weapon.mag
		_canvas.draw_string(mono, center + Vector2(-250, 100), details, HORIZONTAL_ALIGNMENT_CENTER, 500, 12, color)

	# Crosshair: four ticks that open with the weapon's current spread.
	var def := _player.gun().def
	var spread: float = float(def["spread"]) * (float(def["ads"]) if _player.is_aiming else 1.0) + _player.bloom
	var gap := 5.0 + spread * 5.0 + Vector2(_player.velocity.x, _player.velocity.z).length() * 0.9
	if _inventory == null and not scoped:
		var cross := Color(INK, 0.9 * (1.0 - sight))
		for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			_canvas.draw_line(center + dir * gap, center + dir * (gap + 7.0), cross, 1.5, true)
		_canvas.draw_circle(center, 1.2, cross)
		if sight > 0.0:
			var dot := Color(1.0, 0.32, 0.18, sight) if sight_type == "reflex" else Color(TEAL, sight)
			_canvas.draw_circle(center, 3.1, Color(Color.BLACK, sight * 0.8), true, -1.0, true)
			_canvas.draw_circle(center, 1.65, dot, true, -1.0, true)
			if _player.gun().id == "shotgun":
				_canvas.draw_arc(center, gap * 0.75, 0.0, TAU, 40, Color(INK, sight * 0.55), 1.5, true)
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

	_draw_map(size)

	# Teal tracks the drone's approach. Acid tracks the boarding hold.
	for point in _raid.extract_points:
		if point.occupant != null:
			var inbound: bool = point.drone_scene != null and point.eta > 0.0
			var done: float = 1.0 - point.eta / ExtractPoint.DRONE_FLIGHT if inbound else point.progress / point.hold_time
			_canvas.draw_arc(center, 56.0, 0.0, TAU, 64, Color(1, 1, 1, 0.16), 5.0, true)
			if done > 0.0:
				_canvas.draw_arc(center, 56.0, -PI * 0.5, -PI * 0.5 + TAU * minf(done, 1.0), 64, TEAL if inbound else UiKit.ACID, 5.0, true)

	if _alert_left > 0.0:
		var show := clampf(_alert_left, 0.0, 1.0) * (0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.012))
		_canvas.draw_rect(Rect2(Vector2(center.x - 190.0, 118.0), Vector2(380.0, 3.0)), Color(UiKit.CORAL, show))
		_canvas.draw_string(UiKit.display(800, 3), Vector2(center.x - 300.0, 108.0), _alert_text, HORIZONTAL_ALIGNMENT_CENTER, 600, 34, Color(UiKit.CORAL, show))

	# A kill, confirmed in words for a moment.
	if _kill_time > 0.0:
		var fade := clampf(_kill_time / 0.5, 0.0, 1.0)
		_canvas.draw_string(UiKit.display(800, 2), center + Vector2(-150, -74 - (1.6 - _kill_time) * 6.0), "HOSTILE DOWN", HORIZONTAL_ALIGNMENT_CENTER, 300, 26, Color(UiKit.ACID, fade))

	# New loot, listed on the right: its worth, then its name.
	for i in _toasts.size():
		var toast: Dictionary = _toasts[_toasts.size() - 1 - i]
		var id: String = toast["id"]
		var alpha := clampf(toast["left"], 0.0, 1.0)
		var at := Vector2(size.x - MARGIN - 420.0, size.y * 0.46 - i * 46.0)
		_canvas.draw_rect(Rect2(Vector2(size.x - MARGIN - 5.0, at.y - 22.0), Vector2(5, 30)), Color(Catalog.rarity_color(id), alpha))
		_canvas.draw_string(UiKit.display(800, 1), at, Catalog.item_name(id).to_upper(), HORIZONTAL_ALIGNMENT_RIGHT, 400, 26, Color(INK, alpha))
		_canvas.draw_string(UiKit.mono(true, 1), at + Vector2(0, 14), "+ %d CR" % Catalog.sell_price(id), HORIZONTAL_ALIGNMENT_RIGHT, 400, 11, Color(INK, alpha * 0.6))

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
		# On a map with a corner map only the two nearest exits are marked in the
		# view; the rest are on the map.
		var marked: Array = _raid.extract_points.duplicate()
		if _tracked_exit >= 0:
			marked = [_raid.extract_points[_tracked_exit]]
		elif _raid.level.minimap != null:
			var from := _player.global_position
			marked.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_squared_to(from) < b.global_position.distance_squared_to(from))
			marked.resize(mini(marked.size(), 2))
		for point: ExtractPoint in marked:
			var world: Vector3 = point.global_position + Vector3.UP * 2.2
			var screen := _marker_position(camera, world, center)
			screen = screen.clamp(Vector2(140, 130), size - Vector2(140, 240))
			if _raid.level.minimap != null and screen.x > size.x - MARGIN - MAP_SIZE - 110.0:
				screen.y = maxf(screen.y, MARGIN + MAP_SIZE + 24.0)
			var distance := int(point.global_position.distance_to(_player.global_position))
			var color := UiKit.ACID if _tracked_exit >= 0 else TEAL
			_canvas.draw_arc(screen, 6.0, 0.0, TAU, 16, color, 1.5, true)
			_canvas.draw_string(_font, screen + Vector2(-100, 24), "%s  %dm" % [point.label, distance], HORIZONTAL_ALIGNMENT_CENTER, 200, 13, Color(color, 0.9))
		# Supply drops until they are opened, in coral, with the time to landing.
		for drop in _raid.drops:
			if drop == null or drop.is_open():
				continue
			var world: Vector3 = drop.global_position + Vector3.UP * 2.0
			var screen := _marker_position(camera, world, center)
			screen = screen.clamp(Vector2(140, 130), size - Vector2(140, 240))
			if _raid.level.minimap != null and screen.x > size.x - MARGIN - MAP_SIZE - 110.0:
				screen.y = maxf(screen.y, MARGIN + MAP_SIZE + 24.0)
			var distance := int(drop.global_position.distance_to(_player.global_position))
			var when := "  lands in %ds" % ceili(drop.eta) if drop.eta > 0.0 else ""
			_canvas.draw_rect(Rect2(screen - Vector2(5, 5), Vector2(10, 10)), UiKit.CORAL, false, 1.5)
			_canvas.draw_string(_font, screen + Vector2(-120, 24), "Supply drop  %dm%s" % [distance, when], HORIZONTAL_ALIGNMENT_CENTER, 240, 13, Color(UiKit.CORAL, 0.95))

# Project points in front and send the others to the corresponding edge.
func _marker_position(camera: Camera3D, world: Vector3, center: Vector2) -> Vector2:
	var local := camera.get_camera_transform().affine_inverse() * world
	if local.z < -0.01:
		return camera.unproject_position(world)
	var direction := Vector2(local.x, -local.y)
	return center + (Vector2.DOWN if direction.is_zero_approx() else direction.normalized()) * 4000.0

func _draw_scope(size: Vector2, amount: float, prism: bool) -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * lerpf(0.46, 0.37 if prism else 0.32, amount)
	var outside := PackedVector2Array()
	var inside := PackedVector2Array()
	var angles: Array[float] = []
	for i in 64:
		angles.append(-PI + TAU * i / 64.0)
	# Include the screen corners so each outside edge follows the rectangle.
	for corner: Vector2 in [center, Vector2(-center.x, center.y), -center, Vector2(center.x, -center.y)]:
		angles.append(corner.angle())
	angles.sort()
	for angle in angles:
		var dir := Vector2.from_angle(angle)
		var edge := minf(center.x / maxf(absf(dir.x), 0.0001), center.y / maxf(absf(dir.y), 0.0001))
		outside.append(center + dir * edge)
		inside.append(center + dir * radius)
	for i in angles.size():
		var next := (i + 1) % angles.size()
		if inside[i].distance_squared_to(inside[next]) > 0.01:
			_canvas.draw_colored_polygon(PackedVector2Array([inside[i], outside[i], outside[next], inside[next]]),
				Color(0.015, 0.02, 0.024, amount * 0.9))
	_canvas.draw_arc(center, radius, 0.0, TAU, 96, Color(0.03, 0.04, 0.045, amount), 9.0, true)
	_canvas.draw_arc(center, radius - 6.0, 0.0, TAU, 96, Color(TEAL, amount * 0.42), 1.5, true)
	for dir: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN]:
		_canvas.draw_line(center + dir * 7.0, center + dir * radius * 0.67, Color(Color.BLACK, amount * 0.85), 3.5, true)
		_canvas.draw_line(center + dir * 7.0, center + dir * radius * 0.67, Color(INK, amount * 0.75), 1.1, true)
		for i in range(1, 5):
			var at := center + dir * radius * i * 0.1
			var tick := dir.orthogonal() * (5.0 if i % 2 == 0 else 3.0)
			_canvas.draw_line(at - tick, at + tick, Color(INK, amount * 0.75), 1.5, true)
	if prism:
		var chevron := PackedVector2Array([center + Vector2(-7, 7), center, center + Vector2(7, 7)])
		_canvas.draw_polyline(chevron, Color(Color.BLACK, amount), 4.0, true)
		_canvas.draw_polyline(chevron, Color(1.0, 0.44, 0.22, amount), 1.7, true)
	else:
		_canvas.draw_circle(center, 3.5, Color(Color.BLACK, amount * 0.8))
		_canvas.draw_circle(center, 1.8, Color(TEAL, amount))

# The corner map: a north-up window centered on the player.
func _draw_map(size: Vector2) -> void:
	var level := _raid.level
	if level.minimap == null:
		return
	var corner := Vector2(size.x - MARGIN - MAP_SIZE, MARGIN)
	var frame := Rect2(corner, Vector2(MAP_SIZE, MAP_SIZE))
	var here := Vector2(_player.global_position.x, _player.global_position.z)
	var per_metre := level.minimap.get_width() / level.minimap_span
	var window := MAP_SHOWS * per_metre
	var source := Rect2((here - level.minimap_centre + Vector2.ONE * level.minimap_span * 0.5) * per_metre - Vector2.ONE * window * 0.5, Vector2(window, window))
	_canvas.draw_rect(frame, Color(0.03, 0.05, 0.05, 0.75))
	_canvas.draw_texture_rect_region(level.minimap, frame, source, Color(1, 1, 1, 0.92))
	var scale := MAP_SIZE / MAP_SHOWS
	var middle := corner + Vector2.ONE * MAP_SIZE * 0.5
	var mono := UiKit.mono(true, 1)
	for place: Dictionary in level.places:
		var at: Vector3 = place["position"]
		var spot := middle + (Vector2(at.x, at.z) - here) * scale
		if frame.grow(-8.0).has_point(spot):
			_canvas.draw_string(mono, spot + Vector2(-60, -9), (place["name"] as String).to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 120, 9, Color(1, 1, 1, 0.8))
	for point in _raid.extract_points:
		var offset := (Vector2(point.global_position.x, point.global_position.z) - here) * scale
		var limit := MAP_SIZE * 0.5 - 7.0
		var edge := absf(offset.x) > limit or absf(offset.y) > limit
		if edge:
			offset *= limit / maxf(absf(offset.x), absf(offset.y))
		var spot := middle + offset
		var diamond := PackedVector2Array([spot + Vector2(0, -5), spot + Vector2(5, 0), spot + Vector2(0, 5), spot + Vector2(-5, 0)])
		var tracked := _tracked_exit >= 0 and point == _raid.extract_points[_tracked_exit]
		_canvas.draw_colored_polygon(diamond, Color(UiKit.ACID if tracked else TEAL, 0.55 if edge and not tracked else 1.0))
	for drop in _raid.drops:
		if drop == null or drop.is_open():
			continue
		var offset := (Vector2(drop.global_position.x, drop.global_position.z) - here) * scale
		var limit := MAP_SIZE * 0.5 - 7.0
		if absf(offset.x) > limit or absf(offset.y) > limit:
			offset *= limit / maxf(absf(offset.x), absf(offset.y))
		_canvas.draw_rect(Rect2(middle + offset - Vector2(4, 4), Vector2(8, 8)), UiKit.CORAL)
	var yaw := _player.rotation.y
	var ahead := Vector2(-sin(yaw), -cos(yaw))
	var side := Vector2(-ahead.y, ahead.x)
	_canvas.draw_colored_polygon(PackedVector2Array([middle + ahead * 8.0, middle - ahead * 5.0 + side * 5.0, middle - ahead * 2.0, middle - ahead * 5.0 - side * 5.0]), UiKit.ACID)
	_canvas.draw_rect(frame, Color(1, 1, 1, 0.5), false, 1.0)
	_canvas.draw_string(mono, corner + Vector2(6, 13), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.7))

# A small square with a key's letter on it. Lit when the thing is available.
func _keycap(at: Vector2, letter: String, lit: bool) -> void:
	_canvas.draw_rect(Rect2(at, Vector2(24, 24)), INK if lit else Color(1, 1, 1, 0.2))
	_canvas.draw_string(UiKit.mono(true), at + Vector2(0, 17), letter, HORIZONTAL_ALIGNMENT_CENTER, 24, 13, Color(0.06, 0.07, 0.08) if lit else INK)

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

# The moment the raid ends: the play HUD clears and the frame goes widescreen.
func begin_ending() -> void:
	_close_inventory(false)
	if _dev_console != null:
		_dev_console.close(false)
	_canvas.visible = false
	for top: bool in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0.03, 0.035, 0.04)
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE if top else Control.PRESET_BOTTOM_WIDE)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bar)
		var tween := bar.create_tween().set_ignore_time_scale(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(bar, "offset_bottom" if top else "offset_top", 96.0 if top else -96.0, 0.7)

# The result, told in beats: a headline slams in, a line of explanation, then
# each item lost or secured ticks onto the screen, the totals, and the way out.
func show_result(result: Dictionary) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# Tolerates an empty result (a raid scene run on its own, outside the menu flow).
	var outcome: String = result.get("outcome", "died")
	var items: Array = result.get("items", [])
	var won := outcome == "extracted"
	var accent := UiKit.ACID if won else UiKit.CORAL
	var headline := "EXTRACTED" if won else ("KESTREL DOWN" if outcome == "died" else "LOCKED IN")
	var detail := "You made it out. Everything in the backpack is yours."
	if outcome == "died":
		detail = "Killed in the raid. What you carried and wore stays where you fell."
	elif outcome == "lost":
		detail = "The station sealed before you got out. Your kit stays inside."
	var contract: Dictionary = result.get("contract", {})
	if not contract.is_empty():
		var summary := "+%d CR" % contract["paid"] if int(contract["paid"]) > 0 else "%d/%d · no payout" % [contract["progress"], contract["target"]]
		detail += "\n%s  /  %s" % [contract["name"], summary]
	var seconds := int(result.get("time", 0.0))

	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.035, 0.04, 0.0)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	move_child(shade, 1)
	_overlay = shade
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	column.offset_left = 96.0
	column.offset_right = 900.0
	column.offset_top = 112.0
	column.offset_bottom = -200.0
	column.add_theme_constant_override("separation", 6)
	shade.add_child(column)

	var kicker := _line("RAID OVER   /   %02d:%02d   /   %d HOSTILE%s DOWN" % [seconds / 60, seconds % 60, result.get("kills", 0), "" if result.get("kills", 0) == 1 else "S"], 13, INK, UiKit.mono(true, 3))
	var title := _line(headline, 168, accent, UiKit.display(900))
	title.add_theme_constant_override("line_spacing", -40)
	var sub := _line(detail, 19, INK, UiKit.font(500))
	var rule := ColorRect.new()
	rule.color = accent
	rule.custom_minimum_size = Vector2(0, 4)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 10
	for node: Control in [kicker, title, sub, spacer, rule]:
		node.modulate.a = 0.0
		column.add_child(node)

	var tween := create_tween().set_ignore_time_scale(true)
	tween.tween_property(shade, "color:a", 0.45 if won else 0.5, 0.5)
	tween.tween_callback(func() -> void: Sfx.play("extract" if won else "shield_break", -4.0, 1.0 if won else 0.55))
	# The headline lands oversized and settles.
	title.pivot_offset = Vector2(0, 90)
	title.scale = Vector2(1.18, 1.18)
	tween.tween_property(title, "modulate:a", 1.0, 0.12)
	tween.parallel().tween_property(title, "scale", Vector2.ONE, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tween.parallel().tween_property(kicker, "modulate:a", 1.0, 0.4)
	tween.tween_property(sub, "modulate:a", 1.0, 0.35)
	tween.parallel().tween_property(rule, "modulate:a", 1.0, 0.35)

	# One line per item in two columns, capped so that however much comes out,
	# the list is a fixed height and can't reach the button below it.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 48)
	grid.add_theme_constant_override("v_separation", 2)
	column.add_child(grid)
	var shown := mini(items.size(), 10)
	for i in shown:
		var id: String = items[i]
		var text := "%s   %s" % [("+ %d CR" % Catalog.sell_price(id)).rpad(11) if won else "LOST".rpad(6), Catalog.item_name(id).to_upper()]
		var row := _line(text, 14, DIM, UiKit.mono(false, 1))
		row.modulate.a = 0.0
		grid.add_child(row)
		tween.tween_callback(func() -> void: Sfx.play("tick", -12.0, 1.0 + i * 0.05))
		tween.tween_property(row, "modulate:a", 1.0, 0.1)
	if items.size() > shown:
		var more := _line("AND %d MORE" % (items.size() - shown), 14, DIM, UiKit.mono(false, 1))
		more.modulate.a = 0.0
		column.add_child(more)
		tween.tween_property(more, "modulate:a", 1.0, 0.1)
	if items.is_empty():
		var none := _line("NOTHING IN THE BACKPACK" if won else "NOTHING TO LOSE THIS TIME", 14, DIM, UiKit.mono(false, 1))
		none.modulate.a = 0.0
		column.add_child(none)
		tween.tween_property(none, "modulate:a", 1.0, 0.2)

	# The total counts up on a win.
	if won:
		var total := _line("0 CR", 72, INK, UiKit.display(800, 1))
		total.modulate.a = 0.0
		column.add_child(total)
		var value: int = result.get("value", 0)
		tween.tween_property(total, "modulate:a", 1.0, 0.2)
		tween.tween_method(func(v: float) -> void: total.text = "%d CR SECURED" % int(v), 0.0, float(value), 0.9).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	# The way out is pinned to the bottom of the screen, not the end of the list.
	var leave := UiKit.button("RETURN TO BASE  →", true)
	leave.add_theme_font_override("font", UiKit.display(800, 2))
	leave.add_theme_font_size_override("font_size", 28)
	leave.custom_minimum_size = Vector2(320, 66)
	leave.modulate.a = 0.0
	leave.pressed.connect(GameManager.return_to_menu)
	shade.add_child(leave)
	leave.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	leave.offset_left = 96.0
	leave.offset_right = 416.0
	leave.offset_top = -184.0
	leave.offset_bottom = -118.0
	tween.tween_property(leave, "modulate:a", 1.0, 0.4)

func _line(text: String, size: int, color: Color, face: Font) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", face)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.5))
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _input(event: InputEvent) -> void:
	if _dev_console != null and _raid != null and not _raid.over:
		if _dev_console.visible:
			if not event.is_echo() and (event.is_action_pressed("dev_console") or event.is_action_pressed("pause")):
				get_viewport().set_input_as_handled()
				_dev_console.close()
			return
		if event.is_action_pressed("dev_console") and not event.is_echo() and _inventory == null and _paused_panel == null:
			get_viewport().set_input_as_handled()
			_dev_console.open()
			return
	if event.is_action_pressed("inventory"):
		_toggle_inventory(event)
	elif event.is_action_pressed("track_extract") and not event.is_echo() and _raid != null and not _raid.over:
		if _inventory == null and _paused_panel == null and not _raid.extract_points.is_empty():
			_tracked_exit += 1
			if _tracked_exit == _raid.extract_points.size():
				_tracked_exit = -1
			get_viewport().set_input_as_handled()

func _toggle_inventory(event: InputEvent) -> void:
	if _raid == null or _raid.over or event.is_echo():
		return
	if event.is_action_pressed("inventory") and _paused_panel == null:
		get_viewport().set_input_as_handled()
		if _inventory == null:
			_open_inventory()
		else:
			_close_inventory()

func _unhandled_input(event: InputEvent) -> void:
	if _raid == null or _raid.over or event.is_echo() or not event.is_action_pressed("pause"):
		return
	if _dev_console != null and _dev_console.visible:
		return
	if _inventory != null:
		get_viewport().set_input_as_handled()
		_close_inventory()
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

func _open_inventory() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.018, 0.024, 0.029, 0.58)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_inventory = shade
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -350.0
	panel.offset_top = -278.0
	panel.offset_right = 350.0
	panel.offset_bottom = 278.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.075, 0.085, 0.98)
	style.border_color = TEAL
	style.border_width_top = 3
	for side: Side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_content_margin(side, 20.0)
	panel.add_theme_stylebox_override("panel", style)
	shade.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	_inventory_heading = UiKit.text("", 28, INK)
	_inventory_heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_inventory_heading)
	var close := UiKit.button("Close  [Tab]", false, true)
	close.pressed.connect(_close_inventory)
	header.add_child(close)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(columns)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	columns.add_child(scroll)
	_inventory_rows = VBoxContainer.new()
	_inventory_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_inventory_rows)
	_inventory_slots = VBoxContainer.new()
	_inventory_slots.custom_minimum_size.x = 245
	_inventory_slots.add_theme_constant_override("separation", 10)
	columns.add_child(_inventory_slots)
	_inventory_detail = UiKit.text("", 14, DIM, true)
	_inventory_detail.custom_minimum_size.y = 38
	column.add_child(_inventory_detail)
	_inventory_actions = HBoxContainer.new()
	_inventory_actions.custom_minimum_size.y = 34
	column.add_child(_inventory_actions)
	_inventory_message = UiKit.text("Raid is live while your pack is open.", 13, TEAL)
	column.add_child(_inventory_message)
	_inventory_index = -1
	_inventory_slot = ""
	_refresh_inventory()

func _close_inventory(capture: bool = true) -> void:
	if _inventory == null:
		return
	_inventory.hide()
	_inventory.queue_free()
	_inventory = null
	if capture:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _refresh_inventory() -> void:
	if _inventory == null:
		return
	var items := GameManager.backpack
	_inventory_heading.text = "BACKPACK   %d / %d" % [items.size(), GameManager.capacity()]
	for section in [_inventory_rows, _inventory_slots, _inventory_actions]:
		for child in section.get_children():
			section.remove_child(child)
			child.queue_free()
	for slot in GameManager.EQUIP_SLOTS:
		var id: String = GameManager.loadout[slot]
		var name := "Issued sidearm" if slot == "secondary" else "Empty"
		if not id.is_empty():
			name = Catalog.item_name(id)
		_inventory_slots.add_child(UiKit.text(GameManager.SLOT_LABELS[slot].to_upper(), 11, TEAL))
		var gun: Gun
		if slot == "primary" and not id.is_empty():
			gun = _player.guns[0]
		elif slot == "secondary":
			gun = _player.guns[-1]
		if id.is_empty():
			var label := UiKit.text(name, 16, DIM)
			if gun != null:
				label.mouse_filter = Control.MOUSE_FILTER_PASS
				label.tooltip_text = UiKit.item_tooltip(gun.id, gun)
			_inventory_slots.add_child(label)
		else:
			var equipped := UiKit.button(name, _inventory_slot == slot, true)
			equipped.alignment = HORIZONTAL_ALIGNMENT_LEFT
			equipped.tooltip_text = UiKit.item_tooltip(id, gun)
			equipped.pressed.connect(func() -> void:
				_inventory_slot = slot
				_inventory_index = -1
				_inventory_message.text = "Raid is live while your pack is open."
				_refresh_inventory.call_deferred())
			_inventory_slots.add_child(equipped)
	if items.is_empty():
		_inventory_rows.add_child(UiKit.text("Backpack empty", 16, DIM))
	for index in items.size():
		var id := items[index]
		var row := UiKit.button("%s   ·   %d CR" % [Catalog.item_name(id), Catalog.sell_price(id)], index == _inventory_index, true)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.tooltip_text = UiKit.item_tooltip(id, GameManager.packed_gun(index))
		if index != _inventory_index:
			row.add_theme_color_override("font_color", Catalog.rarity_color(id))
		row.pressed.connect(func() -> void:
			_inventory_index = index
			_inventory_slot = ""
			_inventory_message.text = "Raid is live while your pack is open."
			_refresh_inventory.call_deferred())
		_inventory_rows.add_child(row)
	_inventory_detail.text = "Select a carried or equipped item."
	if not _inventory_slot.is_empty():
		var equipped: String = GameManager.loadout[_inventory_slot]
		_inventory_detail.text = Catalog.item(equipped).get("desc", "")
		_inventory_action("Stow in backpack", _player.stow_equipped.bind(_inventory_slot),
			"Make room in your backpack before stowing this item.", true)
		return
	if _inventory_index < 0 or _inventory_index >= items.size():
		return
	var selected := items[_inventory_index]
	var item := Catalog.item(selected)
	_inventory_detail.text = item.get("desc", "%s salvage" % Catalog.RARITY_NAMES[item["rarity"]])
	var packed := GameManager.packed_gun(_inventory_index)
	if packed != null:
		_inventory_detail.text += "   ·   %d loaded / %d reserve" % [packed.mag, packed.reserve]
	for slot in GameManager.EQUIP_SLOTS:
		if item["kind"] == GameManager.SLOT_KINDS[slot]:
			_inventory_action("Equip " + GameManager.SLOT_LABELS[slot], _player.equip_packed.bind(_inventory_index, slot),
				"Make room in your backpack before replacing that implant.", true)
	if selected == "medkit":
		_inventory_action("Use medkit", _player.use_medkit.bind(_inventory_index),
			"Medkits require missing health and an idle healing channel.", true)
	_inventory_action("Drop", _player.drop_packed.bind(_inventory_index), "Find solid ground to drop this item.")

func _inventory_action(label: String, action: Callable, failure: String, primary: bool = false) -> void:
	var button := UiKit.button(label, primary, true)
	button.pressed.connect(func() -> void:
		if action.call():
			_inventory_index = -1
			_inventory_slot = ""
			_inventory_message.text = "Raid is live while your pack is open."
		else:
			_inventory_message.text = failure)
	_inventory_actions.add_child(button)

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
	column.offset_left = -400.0 if with_settings else -280.0
	column.offset_right = 400.0 if with_settings else 280.0
	column.offset_top = -330.0 if with_settings else -150.0
	column.offset_bottom = 330.0 if with_settings else 150.0
	column.add_theme_constant_override("separation", 18)
	shade.add_child(column)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_override("font", UiKit.display(800, 1))
	heading.add_theme_font_size_override("font_size", 76)
	heading.add_theme_color_override("font_color", INK)
	column.add_child(heading)
	var text := Label.new()
	text.text = body
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_font_override("font", UiKit.font(500))
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
	label.add_theme_font_override("font", UiKit.font(600))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	label.add_theme_constant_override("shadow_offset_y", 1)
	_canvas.add_child(label)
	return label
