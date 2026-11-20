extends Node3D

signal unloading(origin: Vector3)
signal cannon_disabled

const Cannon = preload("res://scripts/actors/aircraft_cannon.gd")
const APPROACH_TIME := 4.5
const DESCENT_TIME := 3.5
const LIFT_TIME := 3.5
const EXIT_TIME := 4.5
const CRUISE_HEIGHT := 38.0
const HOVER_HEIGHT := 4.1
const LAND_HEIGHT := 0.08

var helicopter := true
var lands := false
var station: Vector3
var heading: Vector3
var player: Player
var _age := 0.0
var _unloaded := false
var _stay := 0.0
var _body := Node3D.new()
var _rotors: Array[Node3D] = []
var _cannons: Array[Cannon] = []
var _hatch := Node3D.new()
var _cable: MeshInstance3D
var _engines := AudioStreamPlayer3D.new()
var _hull := StaticBody3D.new()

func _ready() -> void:
	add_to_group("reinforcement_aircraft")
	_stay = 19.0 if helicopter else 6.0
	global_position = station + Vector3.UP * CRUISE_HEIGHT - heading * 112.0
	look_at(global_position + heading)
	add_child(_body)
	_build_airframe()
	_engines.stream = Sfx.aircraft_loop(helicopter)
	_engines.bus = Sfx.WORLD_BUS
	_engines.max_distance = 190.0
	_engines.unit_size = 25.0
	_engines.volume_db = -9.0
	add_child(_engines)
	_engines.play()

func _physics_process(delta: float) -> void:
	if not is_instance_valid(player) or player.is_dead or get_parent().over:
		queue_free()
		return
	_age += delta
	for rotor in _rotors:
		rotor.rotate_y(delta * 26.0)

	var cruise := station + Vector3.UP * CRUISE_HEIGHT
	var berth := station + Vector3.UP * (LAND_HEIGHT if lands else HOVER_HEIGHT)
	var phase := _age
	if phase < APPROACH_TIME:
		var t := phase / APPROACH_TIME
		global_position = cruise - heading * 112.0 * (1.0 - smoothstep(0.0, 1.0, t))
		_body.rotation.x = -0.12 * sin(PI * t)
		return
	phase -= APPROACH_TIME
	if phase < DESCENT_TIME:
		global_position = cruise.lerp(berth, smoothstep(0.0, DESCENT_TIME, phase))
		_body.rotation.x = 0.0
		return
	phase -= DESCENT_TIME
	if phase < _stay:
		global_position = berth
		_hatch.rotation.x = lerpf(0.0, 1.87 if lands else 1.55, smoothstep(0.0, 0.65, phase))
		if not _unloaded and phase >= 0.65:
			_unloaded = true
			var hatch_exit := to_global(Vector3(0, 0.83, 3.48))
			if not lands:
				_cable.show()
			unloading.emit(hatch_exit)
		if phase >= 3.8:
			_cable.hide()
			_hatch.rotation.x *= 1.0 - smoothstep(_stay - 1.0, _stay, phase)
		for cannon in _cannons:
			cannon.track(player, delta)
		return
	phase -= _stay
	for cannon in _cannons:
		cannon.cease_fire()
	if phase < LIFT_TIME:
		global_position = berth.lerp(cruise, smoothstep(0.0, LIFT_TIME, phase))
		return
	phase -= LIFT_TIME
	if phase >= EXIT_TIME:
		queue_free()
		return
	var exit_progress := smoothstep(0.0, EXIT_TIME, phase)
	global_position = cruise + heading * 112.0 * exit_progress
	_body.rotation.x = -0.12 * sin(PI * exit_progress)

func _build_airframe() -> void:
	var hull := Mats.surface(Color(0.22, 0.25, 0.24) if helicopter else Color(0.29, 0.32, 0.38), "plain", 0.45, 0.52)
	var dark := Mats.surface(Color(0.055, 0.067, 0.072), "plain", 0.42, 0.45)
	var stripe := Mats.surface(Color(0.61, 0.29, 0.12), "plain", 0.56, 0.3)
	var glass := Mats.surface(Color(0.075, 0.23, 0.27), "plain", 0.19, 0.72)
	var amber := Mats.glow(Color(1, 0.31, 0.09), 3.0)
	var lift := Mats.glow(Color(0.25, 0.77, 1.0), 4.0)

	_part(_body, Vector3(0, 1.48, 0.04), Vector3(3.4, 1.9, 5.85), 0.32, hull)
	_part(_body, Vector3(0, 1.38, -2.87), Vector3(2.72, 1.5, 2.0), 0.29, hull)
	_part(_body, Vector3(0, 1.84, -3.35), Vector3(2.23, 0.61, 0.95), 0.18, glass)
	_part(_body, Vector3(0, 1.9, -3.71), Vector3(0.12, 0.62, 0.11), 0.04, dark)
	_part(_body, Vector3(0, 1.05, -3.59), Vector3(1.9, 0.15, 0.35), 0.06, stripe)
	_part(_body, Vector3(0, 1.22, 2.96), Vector3(1.9, 1.27, 0.07), 0.04, dark)
	_body.add_child(_hatch)
	_hatch.position = Vector3(0, 0.65, 3.02)
	_part(_hatch, Vector3(0, 0.6, 0), Vector3(1.68, 1.22, 0.18), 0.07, hull)
	for strip in 3:
		_part(_hatch, Vector3(0, 0.26 + strip * 0.25, 0.11), Vector3(1.4, 0.07, 0.04), 0.018, stripe)

	# The fuselage shields the far-side mount from shots and blasts.
	_body.add_child(_hull)
	_hull.collision_layer = Layers.WORLD
	_hull.collision_mask = 0
	var collision := CollisionShape3D.new()
	var bounds := BoxShape3D.new()
	bounds.size = Vector3(3.3, 1.81, 5.8)
	collision.shape = bounds
	collision.position.y = 1.48
	_hull.add_child(collision)
	var cable_height := HOVER_HEIGHT + 0.68
	_cable = _part(self, Vector3(0, 0.83 - cable_height * 0.5, 3.48),
		Vector3(0.055, cable_height, 0.055), 0.018, stripe)
	_cable.hide()

	for side: float in [-1.0, 1.0]:
		_part(_body, Vector3(side * 1.68, 1.74, -1.46), Vector3(0.1, 0.55, 1.53), 0.04, glass)
		_part(_body, Vector3(side * 1.69, 1.08, 0.1), Vector3(0.12, 0.32, 4.55), 0.06, stripe)
		_part(_body, Vector3(side * 1.21, 1.53, 2.99), Vector3(0.17, 0.23, 0.1), 0.04, amber)
		if helicopter:
			_part(_body, Vector3(side * 1.23, 0.14, 0), Vector3(0.22, 0.23, 5.4), 0.08, dark)
			for z: float in [-1.64, 1.65]:
				_part(_body, Vector3(side * 1.05, 0.36, z), Vector3(0.22, 0.63, 0.22), 0.08, hull)
			var cannon := Cannon.new()
			cannon.side = side
			cannon.position = Vector3(side * 2.26, 1.45, 0.15)
			_body.add_child(cannon)
			cannon.disabled.connect(func() -> void: cannon_disabled.emit())
			_cannons.append(cannon)
		else:
			_part(_body, Vector3(side * 2.2, 1.6, 0.34), Vector3(2.18, 0.32, 4.4), 0.12, hull)
			_part(_body, Vector3(side * 3.1, 1.34, 0.32), Vector3(1.2, 1.47, 3.9), 0.28, dark)
			_part(_body, Vector3(side * 3.1, 0.62, 0.32), Vector3(0.91, 0.16, 2.82), 0.07, lift)
			_part(_body, Vector3(side * 1.31, 0.22, 1.55), Vector3(0.65, 0.42, 1.0), 0.12, dark)
			_part(_body, Vector3(side * 1.31, 0.22, -1.68), Vector3(0.65, 0.42, 1.0), 0.12, dark)
	if helicopter:
		_part(_body, Vector3(0, 1.91, 4.14), Vector3(0.51, 0.51, 3.9), 0.16, hull)
		_part(_body, Vector3(0, 2.38, 5.96), Vector3(0.25, 1.48, 0.74), 0.1, stripe)
		_rotor(Vector3(0, 3.05, -0.22), 9.8, false, dark, stripe)
		_rotor(Vector3(0.2, 2.53, 5.91), 2.18, true, dark, stripe)
	else:
		_part(_body, Vector3(0, 2.25, 1.17), Vector3(1.65, 1.05, 2.5), 0.22, hull)
		_part(_body, Vector3(0, 2.74, 1.78), Vector3(0.25, 0.77, 1.97), 0.1, stripe)

func _rotor(at: Vector3, diameter: float, vertical: bool, dark: Material, stripe: Material) -> void:
	var mount := Node3D.new()
	mount.position = at
	mount.rotation.z = PI * 0.5 if vertical else 0.0
	_body.add_child(mount)
	var rotor := Node3D.new()
	mount.add_child(rotor)
	_rotors.append(rotor)
	_part(rotor, Vector3.ZERO, Vector3(0.44, 0.36, 0.44), 0.13, dark)
	_part(rotor, Vector3.ZERO, Vector3(diameter, 0.07, 0.26), 0.03, dark)
	_part(rotor, Vector3.ZERO, Vector3(0.26, 0.07, diameter), 0.03, dark)
	for side: float in [-1.0, 1.0]:
		_part(rotor, Vector3(side * diameter * 0.46, 0.01, 0), Vector3(diameter * 0.06, 0.08, 0.27), 0.03, stripe)
		_part(rotor, Vector3(0, 0.01, side * diameter * 0.46), Vector3(0.27, 0.08, diameter * 0.06), 0.03, stripe)

func _part(parent: Node3D, at: Vector3, size: Vector3, bevel: float, material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = Shapes.rounded_box(size, bevel, 2)
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)
	return mesh
