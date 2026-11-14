class_name ExtractPoint
extends Area3D

# Stand inside for hold_time seconds to leave with what you're carrying.
# Stepping out resets the count. It reports completion with a signal; what
# extraction means is GameManager's business.

signal extracted(player: Player)

var hold_time: float = 7.0
var label: String = "Extract"
var progress: float = 0.0
var occupant: Player = null
var _ring: MeshInstance3D
var _tick_at: int = 0

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
			progress = 0.0)

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
	if occupant == null or occupant.is_dead:
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
