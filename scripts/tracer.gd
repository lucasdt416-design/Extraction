class_name Tracer
extends Node2D

# Purely cosmetic. A hitscan shot lands the same tick it is fired, so without
# something to look at, firing reads as nothing happening at all. This is a
# white streak along the path the shot took, fading out over a few frames.
#
# It has no collider, no mask and no physics: it never decides anything. Set
# Weapon.tracer_lifetime to 0.0 and none of these get spawned.

var _end: Vector2 = Vector2.ZERO
var _lifetime: float = 0.05
var _age: float = 0.0
var _color: Color = Color.WHITE

static func spawn(world: Node, from: Vector2, to: Vector2, lifetime: float, color: Color) -> Tracer:
	var tracer := Tracer.new()
	tracer._lifetime = lifetime
	tracer._color = color

	# Parent first: to_local() needs us in the tree, and it keeps the line
	# correct even if the container is moved or rotated.
	world.add_child(tracer)
	tracer.global_position = from
	tracer._end = tracer.to_local(to)
	return tracer

# Visuals only, so this belongs on the render frame rather than the physics
# tick (CLAUDE.md rule 3).
func _process(delta: float) -> void:
	_age += delta
	if _age >= _lifetime:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var fade := 1.0 - (_age / _lifetime)
	# Width 1 and no antialiasing, so it renders as a crisp line of pixels.
	draw_line(Vector2.ZERO, _end, Color(_color, _color.a * fade), 1.0)
