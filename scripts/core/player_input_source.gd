class_name PlayerInputSource
extends Node

# The only place in the project that reads Input or the mouse (rule 1).
# Mouse motion arrives as events between ticks, so it is accumulated here and
# handed over, then cleared, each time the player polls.

var sensitivity: float = 0.0022
var _look: Vector2 = Vector2.ZERO
var _shoot_pressed: bool = false
var _weapon_next: bool = false
var _slot: int = -1

func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		_look += (event as InputEventMouseMotion).relative * sensitivity * float(GameManager.settings["sensitivity"])
	elif event.is_action_pressed("shoot"):
		_shoot_pressed = true
	elif event.is_action_pressed("weapon_next"):
		_weapon_next = true
	elif event.is_action_pressed("weapon_1"):
		_slot = 0
	elif event.is_action_pressed("weapon_2"):
		_slot = 1

func poll() -> InputFrame:
	var frame := InputFrame.new()
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_look = Vector2.ZERO
		return frame
	frame.move = Vector2(
		Input.get_axis("move_left", "move_right"), Input.get_axis("move_back", "move_forward")
	).limit_length(1.0)
	frame.look = _look
	frame.jump = Input.is_action_pressed("jump")
	frame.sprint = Input.is_action_pressed("sprint")
	frame.crouch = Input.is_action_pressed("crouch")
	frame.shoot = Input.is_action_pressed("shoot")
	frame.shoot_pressed = _shoot_pressed
	frame.aim = Input.is_action_pressed("aim")
	frame.reload = Input.is_action_pressed("reload")
	frame.interact = Input.is_action_pressed("interact")
	frame.tactical = Input.is_action_pressed("tactical")
	frame.prime = Input.is_action_pressed("prime")
	frame.heal = Input.is_action_pressed("heal")
	frame.weapon_slot = _slot
	frame.weapon_next = _weapon_next
	_look = Vector2.ZERO
	_shoot_pressed = false
	_weapon_next = false
	_slot = -1
	return frame
