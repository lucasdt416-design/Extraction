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
	_rebuild()

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
