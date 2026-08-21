class_name Bullet
extends Area2D

# Placeholder art: a white streak travelling in a straight line. Damage goes to
# anything it touches that answers take_damage(); anything else solid still
# stops it, so walls will block shots once there are walls.

@export var speed: float = 900.0
@export var max_range: float = 900.0
@export var length: float = 14.0
@export var damage: int = 1
@export var hit_radius: float = 2.0
@export var color: Color = Color.WHITE

# Whoever fired us. Bullets ignore their own shooter, so a muzzle that sits
# inside the shooter's own collider can't self-inflict.
var shooter: Node = null

# Bodies in this group are ignored entirely -- the shot passes through them
# rather than stopping. Empty means hit everything solid.
var ignore_group: StringName = &""

var _direction: Vector2 = Vector2.RIGHT
var _travelled: float = 0.0

func _ready() -> void:
	_build_collider()
	body_entered.connect(_on_body_entered)
	# Nothing here wants mouse picking; skip the per-bullet hit testing.
	input_pickable = false

func launch(from: Vector2, direction: Vector2) -> void:
	global_position = from
	_direction = direction.normalized()
	# Local +X now points along the flight path, which keeps _draw trivial.
	rotation = _direction.angle()

func _physics_process(delta: float) -> void:
	var step := speed * delta
	global_position += _direction * step
	_travelled += step

	if _travelled >= max_range:
		queue_free()

func _draw() -> void:
	# Trails back from the tip along -X. Width 1 and no antialiasing, so it
	# renders as a crisp line of white pixels.
	draw_line(Vector2.ZERO, Vector2(-length, 0.0), color, 1.0)

func _on_body_entered(body: Node2D) -> void:
	# Our shooter can be freed while we're still in the air -- a dying enemy's
	# last shot. queue_free() doesn't clear references to it, and passing a
	# freed Object into a parameter typed Node fails the type check at the call
	# site, so drop the stale reference before it can travel any further.
	if not is_instance_valid(shooter):
		shooter = null

	if body == shooter:
		return
	if ignore_group != &"" and body.is_in_group(ignore_group):
		return

	if body.has_method("take_damage"):
		body.take_damage(damage, shooter)

	# Solid things stop the shot whether or not they could be hurt by it.
	queue_free()

# Built here rather than in a .tscn because bullets are spawned from code, and
# because the length depends on `speed`, which the shooter sets before we enter
# the tree.
func _build_collider() -> void:
	var shape := CapsuleShape2D.new()
	shape.radius = hit_radius

	# Cover a whole tick of travel, not just the drawn streak. At 900 px/s a
	# bullet moves 15 px between physics frames, which is enough to skip clean
	# past a target if the collider is only as long as the sprite.
	var step := speed / float(Engine.physics_ticks_per_second)
	shape.height = maxf(length, step + hit_radius * 2.0)

	var collider := CollisionShape2D.new()
	collider.shape = shape
	# A capsule runs along its own Y, so rotate it onto our X and push it back
	# to trail from the tip exactly like the drawn line does.
	collider.rotation = PI / 2.0
	collider.position = Vector2(-shape.height / 2.0, 0.0)
	add_child(collider)
