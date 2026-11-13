class_name Fx
extends RefCounted

# One-shot visual effects. Purely cosmetic: none of these have colliders and
# none of them decide anything. Each takes any node in the tree as `ctx`, only
# to find the scene to parent itself under.

static var _tracer_mesh: BoxMesh
static var _spark_mesh: BoxMesh

static func _root(ctx: Node) -> Node:
	return ctx.get_tree().current_scene

static func tracer(ctx: Node, from: Vector3, to: Vector3, color: Color) -> void:
	var length := from.distance_to(to)
	if length < 0.5:
		return
	if _tracer_mesh == null:
		_tracer_mesh = BoxMesh.new()
		_tracer_mesh.size = Vector3(0.009, 0.009, 1.0)
	var streak := MeshInstance3D.new()
	streak.mesh = _tracer_mesh
	streak.material_override = Mats.beam(color, 1.3, 0.6)
	streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root(ctx).add_child(streak)
	var dir := (to - from) / length
	streak.look_at_from_position((from + to) * 0.5, to, Vector3.RIGHT if absf(dir.y) > 0.99 else Vector3.UP)
	streak.scale = Vector3(1.0, 1.0, length)
	var tween := streak.create_tween()
	tween.tween_property(streak, "transparency", 1.0, 0.09)
	tween.tween_callback(streak.queue_free)

static func impact(ctx: Node, position: Vector3, normal: Vector3, on_target: bool) -> void:
	if _spark_mesh == null:
		_spark_mesh = BoxMesh.new()
		_spark_mesh.size = Vector3(0.025, 0.025, 0.09)
	var sparks := CPUParticles3D.new()
	sparks.mesh = _spark_mesh
	sparks.material_override = Mats.glow(Color(0.5, 0.9, 1.0) if on_target else Color(1.0, 0.75, 0.4), 5.0)
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.amount = 7 if on_target else 5
	sparks.lifetime = 0.28
	sparks.direction = normal
	sparks.spread = 55.0
	sparks.initial_velocity_min = 2.0
	sparks.initial_velocity_max = 6.5
	sparks.gravity = Vector3(0.0, -14.0, 0.0)
	sparks.particle_flag_align_y = true
	sparks.scale_amount_min = 0.5
	sparks.scale_amount_max = 1.2
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root(ctx).add_child(sparks)
	sparks.global_position = position + normal * 0.02
	sparks.emitting = true
	ctx.get_tree().create_timer(0.7).timeout.connect(sparks.queue_free)

# A light that pops and dies: muzzle flashes, explosions, pickups.
static func flash(ctx: Node, position: Vector3, color: Color, energy: float = 3.0, time: float = 0.06, reach: float = 7.0) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	light.shadow_enabled = false
	_root(ctx).add_child(light)
	light.global_position = position
	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, time)
	tween.tween_callback(light.queue_free)

# An expanding ring/sphere that fades. Explosions, ability pulses, extraction.
static func burst(ctx: Node, position: Vector3, radius: float, color: Color, time: float = 0.35) -> void:
	var ball := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	ball.mesh = mesh
	ball.material_override = Mats.beam(color, 1.6, 0.5)
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root(ctx).add_child(ball)
	ball.global_position = position
	ball.scale = Vector3.ONE * 0.2
	var tween := ball.create_tween().set_parallel(true)
	tween.tween_property(ball, "scale", Vector3.ONE * radius, time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(ball, "transparency", 1.0, time)
	tween.chain().tween_callback(ball.queue_free)

static func explosion(ctx: Node, position: Vector3, radius: float) -> void:
	burst(ctx, position, radius, Color(1.0, 0.55, 0.2), 0.4)
	flash(ctx, position + Vector3.UP * 0.5, Color(1.0, 0.6, 0.3), 14.0, 0.35, radius * 3.0)
	for i in 3:
		impact(ctx, position + Vector3.UP * 0.2, Vector3.UP, false)
	Sfx.play_at("explosion", position, 4.0, 1.0, 90.0)
