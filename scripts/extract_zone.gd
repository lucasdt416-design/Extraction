@tool 
class_name ExtractZone
extends Area2D


@export var extract_time = 10.0

@export var radius: float = 100.0:
	set(value):
		radius = maxf(value, 1.0)
		_apply_radius()   # writes _collider.shape.radius
		queue_redraw()

@export var edge_color: Color = Color(0.393, 0.172, 0.196, 1.0):
	set(value):
		edge_color = value
		queue_redraw()

@export var color: Color = Color(0.569, 0.249, 0.289, 1.0):
	set(value):
		color = value
		queue_redraw()
		
@onready var _collider: CollisionShape2D = $CollisionShape2D

var time_in_zone: Dictionary[Player, float] = {}


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	for player in time_in_zone.keys():
		if not is_instance_valid(player) or player.is_dead:
			time_in_zone.erase(player)
		else:
			time_in_zone[player] += delta
			if time_in_zone[player] >= extract_time:
				_extract(player)


func _draw() -> void:
	draw_circle(position, radius, color)
	draw_circle(position, radius, color, false, 1.0)


func _apply_radius() -> void:
	queue_redraw() #happens at the next draw step
	if _collider ==  null:
		return


	var shape := _collider.shape as CircleShape2D
	if shape == null:
		shape = CircleShape2D.new()
		_collider.shape = shape
	
	shape.radius = radius


func _on_body_entered(body) -> void:
	if body.is_in_group("player"):
		time_in_zone[body] = 0.0


func _on_body_exited(body) -> void:
	time_in_zone.erase(body)


func _extract(player: Player) -> void:
	time_in_zone.erase(player)
	GameManager.extract_success(player)
