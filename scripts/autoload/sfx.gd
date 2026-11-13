extends Node

# Every sound in the game, synthesized at startup so the project needs no audio
# files. Cosmetic only: nothing here decides anything, and its randomness is
# its own (it never touches GameManager.rng, so sound can't shift a raid's
# seeded outcome).

const RATE: int = 22050

var _streams: Dictionary = {}
var _noise := RandomNumberGenerator.new()
var _lp: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_noise.seed = 7
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
	player.max_distance = reach
	player.pitch_scale = pitch * randf_range(0.94, 1.06)
	scene.add_child(player)
	player.global_position = position
	player.finished.connect(player.queue_free)
	player.play()

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
