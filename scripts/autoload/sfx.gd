extends Node

# Every sound in the game, synthesized at startup so the project needs no audio
# files. Cosmetic only: nothing here decides anything, and its randomness is
# its own (it never touches GameManager.rng, so sound can't shift a raid's
# seeded outcome).

const RATE: int = 22050

var _streams: Dictionary = {}
var _noise := RandomNumberGenerator.new()
var _lp: float = 0.0
var _ambience: AudioStreamPlayer
const WORLD_BUS: StringName = &"World"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_noise.seed = 7
	_build_buses()
	# Gunshots: a noise crack over a falling sine thump. `tone` is the body.
	_streams["shot_sidearm"] = _shot(0.22, 190.0, 0.55, 0.5)
	_streams["shot_smg"] = _shot(0.16, 230.0, 0.45, 0.62)
	_streams["shot_rifle"] = _shot(0.28, 150.0, 0.7, 0.42)
	_streams["shot_shotgun"] = _shot(0.42, 95.0, 1.0, 0.25)
	_streams["shot_dmr"] = _shot(0.5, 120.0, 0.9, 0.3)
	_streams["explosion"] = _shot(1.1, 55.0, 1.0, 0.08)
	_streams["hit"] = _make(0.07, func(t: float) -> float: return sin(TAU * 1900.0 * t) * exp(-t * 60.0) * 0.5)
	_streams["headshot"] = _make(0.12, func(t: float) -> float: return (sin(TAU * 2600.0 * t) + sin(TAU * 3900.0 * t) * 0.5) * exp(-t * 40.0) * 0.4)
	_streams["kill"] = _make(0.25, func(t: float) -> float: return sin(TAU * (700.0 + 900.0 * t) * t) * exp(-t * 14.0) * 0.45)
	_streams["hurt"] = _make(0.2, func(t: float) -> float: return (_n() * 0.5 + sin(TAU * 110.0 * t)) * exp(-t * 22.0) * 0.7)
	_streams["shield_break"] = _make(0.4, func(t: float) -> float: return sin(TAU * (1400.0 - 2400.0 * t) * t) * exp(-t * 9.0) * 0.4 + _n() * exp(-t * 30.0) * 0.3)
	_streams["pickup"] = _make(0.16, func(t: float) -> float: return sin(TAU * (880.0 if t < 0.07 else 1320.0) * t) * exp(-t * 14.0) * 0.35)
	_streams["rare"] = _make(0.5, func(t: float) -> float: return (sin(TAU * 660.0 * t) + sin(TAU * 990.0 * t) + sin(TAU * 1320.0 * t)) * exp(-t * 6.0) * 0.18)
	_streams["open"] = _make(0.3, func(t: float) -> float: return _lowpass(_n(), 0.2) * exp(-t * 12.0) * 1.4 + sin(TAU * 240.0 * t) * exp(-t * 30.0) * 0.4)
	_streams["reload"] = _make(0.34, func(t: float) -> float: return _n() * (exp(-t * 90.0) + exp(-absf(t - 0.24) * 110.0)) * 0.4)
	_streams["empty"] = _make(0.05, func(t: float) -> float: return _n() * exp(-t * 140.0) * 0.3)
	_streams["step"] = _make(0.09, func(t: float) -> float: return _lowpass(_n(), 0.12) * exp(-t * 55.0) * 1.6)
	_streams["ability"] = _make(0.45, func(t: float) -> float: return sin(TAU * (240.0 + 1500.0 * t) * t) * exp(-t * 7.0) * 0.32)
	_streams["tick"] = _make(0.05, func(t: float) -> float: return sin(TAU * 1100.0 * t) * exp(-t * 70.0) * 0.3)
	_streams["alert"] = _make(0.3, func(t: float) -> float: return signf(sin(TAU * 520.0 * t)) * exp(-t * 10.0) * 0.14 * (1.0 if fmod(t, 0.1) < 0.06 else 0.0))
	_streams["click"] = _make(0.03, func(t: float) -> float: return sin(TAU * 1500.0 * t) * exp(-t * 120.0) * 0.2)
	_streams["extract"] = _make(1.2, func(t: float) -> float: return (sin(TAU * 440.0 * t) + sin(TAU * 554.0 * t) + sin(TAU * 659.0 * t)) * minf(t * 8.0, 1.0) * exp(-t * 2.5) * 0.2)
	_streams["beep"] = _make(0.08, func(t: float) -> float: return sin(TAU * 1800.0 * t) * exp(-t * 30.0) * 0.25)

func play(id: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not _streams.has(id):
		return
	var player := AudioStreamPlayer.new()
	player.stream = _streams[id]
	player.bus = WORLD_BUS if _is_world_sound(id) else &"Master"
	player.volume_db = volume_db
	player.pitch_scale = pitch * randf_range(0.96, 1.04)
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()

# Positional, for anything that happens somewhere other than in your hands.
func play_at(id: String, position: Vector3, volume_db: float = 0.0, pitch: float = 1.0, reach: float = 60.0) -> void:
	if not _streams.has(id):
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = _streams[id]
	player.volume_db = volume_db
	player.unit_size = 9.0
	player.bus = WORLD_BUS
	player.max_distance = reach
	player.pitch_scale = pitch * randf_range(0.94, 1.06)
	scene.add_child(player)
	player.global_position = position
	player.finished.connect(player.queue_free)
	player.play()

# --- Space ---------------------------------------------------------------------
# Everything that happens in the world goes through one bus with a reverb on
# it, so shots and footsteps sit in a place instead of in your ears. Interface
# sounds stay dry on the master bus, which carries a limiter so a firefight
# can't clip.

func _build_buses() -> void:
	if AudioServer.get_bus_index(WORLD_BUS) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, WORLD_BUS)
	AudioServer.set_bus_send(index, &"Master")
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.62
	reverb.damping = 0.55
	reverb.spread = 0.8
	reverb.predelay_msec = 28.0
	reverb.wet = 0.2
	reverb.dry = 1.0
	reverb.hipass = 0.25
	AudioServer.add_bus_effect(index, reverb)
	var limiter := AudioEffectCompressor.new()
	limiter.threshold = -8.0
	limiter.ratio = 6.0
	limiter.attack_us = 300.0
	limiter.release_ms = 180.0
	AudioServer.add_bus_effect(0, limiter)

func _is_world_sound(id: String) -> bool:
	return id.begins_with("shot_") or id in ["step", "hurt", "explosion", "reload", "open", "empty", "shield_break"]

# A bed of wind and a low hum under the raid, looping. Without it, the moments
# between shots are dead silent, which reads as the game being broken.
func start_ambience() -> void:
	if _ambience != null:
		return
	const LENGTH := 9.0
	const BLEND := 1.0
	var total := int((LENGTH + BLEND) * RATE)
	var body := int(LENGTH * RATE)
	var blend := int(BLEND * RATE)
	var raw := PackedFloat32Array()
	raw.resize(total)
	var slow := 0.0
	var mid := 0.0
	for i in total:
		var t := float(i) / RATE
		var white := _n()
		slow += (white - slow) * 0.012
		mid += (white - mid) * 0.09
		var gust := 0.55 + 0.45 * sin(TAU * t / LENGTH) * sin(TAU * t / (LENGTH / 3.0) + 1.3)
		var hum := sin(TAU * 55.0 * t) * 0.05 + sin(TAU * 82.5 * t) * 0.025
		raw[i] = slow * 5.0 * gust + mid * 0.22 * gust + hum
	# Fold the tail back over the start so the loop point can't be heard.
	var data := PackedByteArray()
	data.resize(body * 2)
	for i in body:
		var sample := raw[i]
		if i < blend:
			var mix := float(i) / blend
			sample = raw[i] * mix + raw[body + i] * (1.0 - mix)
		data.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 30000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = body
	_ambience = AudioStreamPlayer.new()
	_ambience.stream = stream
	_ambience.volume_db = -40.0
	_ambience.bus = WORLD_BUS
	add_child(_ambience)
	_ambience.play()
	create_tween().tween_property(_ambience, "volume_db", -15.0, 3.0)

func stop_ambience() -> void:
	if _ambience != null:
		_ambience.queue_free()
		_ambience = null

func _n() -> float:
	return _noise.randf_range(-1.0, 1.0)

func _lowpass(x: float, k: float) -> float:
	_lp += (x - _lp) * k
	return _lp

func _shot(length: float, tone: float, weight: float, brightness: float) -> AudioStreamWAV:
	_lp = 0.0
	return _make(length, func(t: float) -> float:
		var crack := _n() * exp(-t * 55.0 * (0.4 + brightness))
		var tail := _lowpass(_n(), 0.05 + brightness * 0.25) * exp(-t * (5.0 / length)) * 0.9
		var thump := sin(TAU * tone * t * exp(-t * 9.0)) * exp(-t * 16.0) * weight
		return clampf((crack * 0.7 + tail + thump) * 0.8, -1.0, 1.0))

func _make(length: float, sample: Callable) -> AudioStreamWAV:
	var count := int(length * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var t := float(i) / RATE
		# A few ms of fade at the end so nothing clicks when it stops.
		var fade := minf(float(count - i) / 200.0, 1.0)
		data.encode_s16(i * 2, int(clampf(sample.call(t) * fade, -1.0, 1.0) * 32000.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream
