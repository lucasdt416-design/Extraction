class_name ExtractPoint
extends Area3D

# Stand inside for hold_time seconds to leave with what you're carrying.
# Stepping out resets the count. It reports completion with a signal; what
# extraction means is GameManager's business.
#
# A drone pad works the same, but first you have to call the drone: stepping on
# the pad calls it, and it takes DRONE_FLIGHT seconds to come in, loud enough
# that guards nearby hear it every few seconds. Once it has landed the hold is
# short. You can leave the pad while it flies in.

signal extracted(player: Player)

var hold_time: float = 7.0
var label: String = "Extract"
var progress: float = 0.0
var occupant: Player = null
var _ring: MeshInstance3D
var _tick_at: int = 0

const DRONE_FLIGHT: float = 35.0
const DRONE_HEARD: float = 70.0      # how far the drone's noise carries
var drone_scene: PackedScene = null  # set for a drone pad
var eta: float = -1.0                # -1 not called, then seconds to landing, 0 landed
var _drone: Node3D
var _from := Vector3.ZERO
var _next_noise: float = 0.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = Layers.PLAYER
	var shape := CylinderShape3D.new()
	shape.radius = 3.2
	shape.height = 4.0
	var collider := CollisionShape3D.new()
	collider.shape = shape
	collider.position.y = 2.0
	add_child(collider)
	body_entered.connect(func(body: Node3D) -> void:
		if body is Player:
			occupant = body
			progress = 0.0)
	body_exited.connect(func(body: Node3D) -> void:
		if body == occupant:
			occupant = null
			progress = 0.0
			_tick_at = 0)

	var teal := Level.TEAL.lightened(0.25)
	var pad := CylinderMesh.new()
	pad.top_radius = 3.2
	pad.bottom_radius = 3.2
	pad.height = 0.05
	pad.radial_segments = 48
	var base := MeshInstance3D.new()
	base.mesh = pad
	base.position.y = 0.03
	base.material_override = Mats.wall(Level.HULL_DARK, Color.BLACK, 0.0, 1.6, 0.5, 0.3, 0.6)
	add_child(base)
	var torus := TorusMesh.new()
	torus.inner_radius = 3.05
	torus.outer_radius = 3.2
	torus.rings = 64
	_ring = MeshInstance3D.new()
	_ring.mesh = torus
	_ring.position.y = 0.08
	_ring.material_override = Mats.glow(teal, 3.5)
	add_child(_ring)
	# A tall faint column so the way out is visible from across the compound.
	var column := CylinderMesh.new()
	column.top_radius = 0.5
	column.bottom_radius = 3.1
	column.height = 40.0
	column.cap_top = false
	column.cap_bottom = false
	var beam := MeshInstance3D.new()
	beam.mesh = column
	beam.position.y = 20.0
	beam.material_override = Mats.beam(teal, 1.0, 0.07)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	var light := OmniLight3D.new()
	light.position.y = 2.0
	light.light_color = teal
	light.light_energy = 1.6
	light.omni_range = 9.0
	add_child(light)

func _physics_process(delta: float) -> void:
	if drone_scene != null:
		_fly(delta)
	if occupant == null or occupant.is_dead:
		return
	if drone_scene != null and eta != 0.0:
		progress = 0.0
		return
	progress += delta
	if int(progress) != _tick_at:
		_tick_at = int(progress)
		Sfx.play("tick", -4.0, 1.0 + progress / hold_time * 0.6)
	if progress >= hold_time:
		var who := occupant
		occupant = null
		extracted.emit(who)

func _process(_delta: float) -> void:
	_ring.scale = Vector3.ONE * (1.0 - (progress / hold_time) * 0.5 if occupant != null else 1.0)

# What the HUD should say about this pad, or "" when nothing is happening.
func status() -> String:
	if drone_scene == null or eta < 0.0:
		return ""
	if eta > 0.0:
		return "DRONE INBOUND   %dS" % ceili(eta)
	return "DRONE DOWN"

func _fly(delta: float) -> void:
	if eta < 0.0:
		if occupant == null or occupant.is_dead:
			return
		eta = DRONE_FLIGHT
		hold_time = 4.0
		# It comes in from wherever is farthest from the player's way in.
		var away := Vector3(global_position.x, 0.0, global_position.z).normalized()
		if away.length() < 0.1:
			away = Vector3.FORWARD
		_from = away * 320.0 + Vector3(0.0, 160.0, 0.0)
		_drone = drone_scene.instantiate()
		add_child(_drone)
		Sfx.play("alert", -4.0, 0.7)
	if eta > 0.0:
		eta = maxf(eta - delta, 0.0)
		_next_noise -= delta
		if _next_noise <= 0.0:
			_next_noise = 5.0
			get_tree().call_group("enemy", "hear", global_position, DRONE_HEARD, self)
	# Fast and high, then slowing and dropping onto the pad.
	var t := 1.0 - eta / DRONE_FLIGHT
	var glide := 1.0 - pow(1.0 - t, 3.0)
	var at := _from.lerp(Vector3.ZERO, glide)
	at.y = lerpf(_from.y, 0.15, clampf((t - 0.35) / 0.65, 0.0, 1.0) ** 0.6)
	_drone.position = at
	if eta > 0.0:
		var ahead := -_from
		_drone.rotation.y = atan2(ahead.x, ahead.z)
		_drone.rotation.z = sin(t * 9.0) * 0.03
