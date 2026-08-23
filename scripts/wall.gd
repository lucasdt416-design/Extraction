@tool
class_name Wall
extends StaticBody2D

# Placeholder level geometry: a solid rectangle nothing gets through.
#
# It blocks all three things without any of them needing to know what a Wall is:
#   - player and enemies, because they move with move_and_slide() and we are a
#     StaticBody2D in their way
#   - shots, because we sit on `world`, which is in CollisionLayers.SHOOTABLE:
#     a hitscan ray stops on the first body it finds there, damageable or not
#
# @tool so the rectangle you drag out in the editor is the rectangle the game
# runs with. Size drives the collider AND the drawn box from one number, so the
# art and the collision can never drift apart the way they do when you resize a
# sprite and forget the shape underneath it.

# Below this a collider is degenerate and quietly stops colliding, which looks
# exactly like a bug in whatever walked through it.
const MIN_EXTENT: float = 1.0

@export var size: Vector2 = Vector2(128.0, 32.0):
	set(value):
		size = Vector2(maxf(value.x, MIN_EXTENT), maxf(value.y, MIN_EXTENT))
		_rebuild()

@export var color: Color = Color(0.24, 0.25, 0.29):
	set(value):
		color = value
		queue_redraw()

@export var edge_color: Color = Color(0.42, 0.44, 0.5):
	set(value):
		edge_color = value
		queue_redraw()

# The collider is a real node in wall.tscn, not something built at runtime, so
# you can see and select the collision box in the editor and there is no window
# during startup where the wall is drawn but not yet solid.
@onready var _collider: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	if Engine.is_editor_hint():
		# Only so the warning triangle below can appear the moment a handle is
		# dragged. The running game has no use for the callback.
		set_notify_local_transform(true)

	_bake_transform()
	_rebuild()

# Godot's 2D physics cannot collide against a shape whose transform has been
# skewed or scaled unevenly -- the transform stops being decomposable, the
# contact normals come out wrong, and anything that touches the wall gets
# ejected to a corner of it instead of being stopped by the face it walked into.
# Dragging the editor's resize handles is the easy way to end up there, because
# they write `scale` and `skew` on the node rather than changing `size`.
#
# So whatever the transform says, we fold it into `size` here and hand the
# physics server a clean, unscaled rectangle. Rotation is decomposable and
# collides fine, so it is left alone.
func _bake_transform() -> void:
	if scale.is_equal_approx(Vector2.ONE) and is_zero_approx(skew):
		return

	# The rectangle is centred on its own origin and therefore symmetric, so a
	# mirrored (negative) scale covers exactly the same ground as its absolute
	# value. Only the sign of the basis changes, and that sign is the part
	# physics chokes on.
	size = size * scale.abs()
	scale = Vector2.ONE
	# Nothing to fold a shear into: a skewed rectangle is a parallelogram, and
	# neither RectangleShape2D nor the box we draw can be one. Dropping it is
	# the only representable answer.
	skew = 0.0

func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
		update_configuration_warnings()

# Flags the window between dragging a handle and the next time the scene loads,
# which is the only time a wall can be sat in a state physics can't collide.
func _get_configuration_warnings() -> PackedStringArray:
	if scale.is_equal_approx(Vector2.ONE) and is_zero_approx(skew):
		return PackedStringArray()

	return PackedStringArray([
		"This wall has been scaled or skewed by dragging its resize handles. "
		+ "Godot's 2D physics can't collide a shape with that transform -- "
		+ "bodies that touch it get thrown to a corner. Resize with the Size "
		+ "property instead. The transform is folded into Size when the scene "
		+ "next loads, so reopening the scene also clears this.",
	])

func _draw() -> void:
	var rect := Rect2(-size * 0.5, size)
	draw_rect(rect, color)
	# A lighter outline so two walls flush against each other still read as two.
	draw_rect(rect, edge_color, false, 1.0)

func _rebuild() -> void:
	queue_redraw()

	# The setters above fire while the scene is still loading, before @onready
	# has run. The _ready call catches us up once the collider exists.
	if _collider == null:
		return

	# The shape in wall.tscn is marked resource_local_to_scene, so every placed
	# wall gets its own copy and resizing one doesn't resize the whole level.
	# If it somehow isn't a rectangle, replace it rather than fail silently.
	var shape := _collider.shape as RectangleShape2D
	if shape == null:
		shape = RectangleShape2D.new()
		_collider.shape = shape

	shape.size = size
