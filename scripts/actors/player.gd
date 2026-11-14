class_name Player
extends CharacterBody3D

# First-person player. Consumes one InputFrame per physics tick (rule 1) and is
# the one place player health, shield, ammo and ability state change (rule 2).
# The view model, camera feel and sounds are visuals layered on top in
# _process; they read this state and never change it.

signal died(killer: Node)
signal damaged(from_position: Vector3, amount: float, shield_only: bool)
# 1 = hit, 2 = headshot, 3 = kill. For the HUD's hit marker.
signal hit_confirmed(result: int)
signal notice(text: String)

const WALK_SPEED: float = 5.0
const SPRINT_SPEED: float = 7.3
const CROUCH_SPEED: float = 2.7
const AIM_SPEED: float = 3.4
const JUMP_SPEED: float = 6.6
const GRAVITY: float = 19.0
const STAND_HEIGHT: float = 1.8
const CROUCH_HEIGHT: float = 1.15
const EYE_OFFSET: float = 0.16       # eye sits this far below the top of the collider
const SHIELD_REGEN: float = 22.0
const INTERACT_REACH: float = 3.2
const SWAP_TIME: float = 0.32
const BASE_FOV: float = 82.0

var input_source: PlayerInputSource
var build_stats: Dictionary = {}
var frame_def: Dictionary = {}

var max_health: float = 100.0
var max_shield: float = 40.0
var health: float = 100.0
var shield: float = 40.0
var is_dead: bool = false

var guns: Array[Gun] = []
var gun_index: int = 0

# Ability state. Cooldowns count down to zero; *_left are active durations.
var tactical_cooldown: float = 0.0
var prime_cooldown: float = 0.0
var cloak_left: float = 0.0
var pulse_left: float = 0.0
var overcharge_left: float = 0.0
var fortify_left: float = 0.0
var heal_left: float = 0.0        # channel time remaining on a medkit or stim
var heal_is_medkit: bool = false

# Read by the HUD.
var interact_label: String = ""
var interact_progress: float = 0.0
var is_aiming: bool = false
var is_crouched: bool = false
var is_sprinting: bool = false
var bloom: float = 0.0

var _rng := RandomNumberGenerator.new()
var _yaw: float = 0.0
var _pitch: float = 0.0
var _height: float = STAND_HEIGHT
var _since_damage: float = 99.0
var _swap_left: float = 0.0
var _dash_left: float = 0.0
var _dash_dir: Vector3 = Vector3.ZERO
var _heal_rate: float = 0.0
var _interact_latched: bool = false
var _step_distance: float = 0.0
var _was_on_floor: bool = true
var _tactical_latched: bool = false
var _prime_latched: bool = false

# View state (cosmetic).
var _head: Node3D
var _camera: Camera3D
var _view: Node3D
var _view_models: Array[Node3D] = []
var _flash: MeshInstance3D
var _collider: CollisionShape3D
var _kick: float = 0.0
var _kick_target: float = 0.0
var _view_kick: float = 0.0
var _sway: Vector2 = Vector2.ZERO
var _bob: float = 0.0
var _land_dip: float = 0.0
var _aim_blend: float = 0.0
var _shake: float = 0.0

func _ready() -> void:
	add_to_group("player")
	collision_layer = Layers.PLAYER
	collision_mask = Layers.WORLD | Layers.ENEMY
	floor_snap_length = 0.3

	build_stats = GameManager.player_stats()
	frame_def = Catalog.FRAMES[GameManager.frame_id]
	max_health = build_stats["health"]
	max_shield = build_stats["shield"]
	health = max_health
	shield = max_shield
	_rng.seed = GameManager.rng.randi()

	var shape := CapsuleShape3D.new()
	shape.radius = 0.36
	shape.height = STAND_HEIGHT
	_collider = CollisionShape3D.new()
	_collider.shape = shape
	_collider.position.y = STAND_HEIGHT * 0.5
	add_child(_collider)

	_head = Node3D.new()
	_head.position.y = STAND_HEIGHT - EYE_OFFSET
	add_child(_head)
	_camera = Camera3D.new()
	_camera.fov = BASE_FOV
	_camera.near = 0.03
	_camera.far = 600.0
	_head.add_child(_camera)
	_camera.make_current()

	input_source = PlayerInputSource.new()
	add_child(input_source)

	for id in GameManager.raid_weapons():
		var gun := Gun.new(id)
		gun.reload_mult = build_stats["reload"]
		gun.infinite_reserve = id == "sidearm"
		guns.append(gun)
	_build_view_models()
	_yaw = rotation.y

# --- Simulation --------------------------------------------------------------

func _physics_process(delta: float) -> void:
	var frame := InputFrame.new() if is_dead else input_source.poll()
	_tick_timers(delta)
	_look(frame)
	_move(frame, delta)
	if is_dead:
		return
	_abilities(frame)
	_weapons(frame, delta)
	_healing(frame, delta)
	_interact(frame, delta)

func _tick_timers(delta: float) -> void:
	tactical_cooldown = maxf(tactical_cooldown - delta, 0.0)
	prime_cooldown = maxf(prime_cooldown - delta, 0.0)
	cloak_left = maxf(cloak_left - delta, 0.0)
	pulse_left = maxf(pulse_left - delta, 0.0)
	fortify_left = maxf(fortify_left - delta, 0.0)
	_dash_left = maxf(_dash_left - delta, 0.0)
	_swap_left = maxf(_swap_left - delta, 0.0)
	if overcharge_left > 0.0:
		overcharge_left = maxf(overcharge_left - delta, 0.0)
		if overcharge_left <= 0.0:
			for gun in guns:
				gun.rate_mult = 1.0
	bloom = maxf(bloom - delta * 7.0, 0.0)
	_since_damage += delta
	if not is_dead and _since_damage >= float(build_stats["regen_delay"]) and shield < max_shield:
		shield = minf(shield + SHIELD_REGEN * delta, max_shield)

func _look(frame: InputFrame) -> void:
	_yaw -= frame.look.x
	_pitch = clampf(_pitch - frame.look.y, -1.5, 1.5)
	rotation.y = _yaw

func _move(frame: InputFrame, delta: float) -> void:
	is_crouched = frame.crouch or (is_crouched and not _can_stand())
	is_aiming = frame.aim and not is_dead and _swap_left <= 0.0 and not gun().is_reloading()
	is_sprinting = frame.sprint and frame.move.y > 0.1 and not is_crouched and not is_aiming and heal_left <= 0.0

	var target_height := CROUCH_HEIGHT if is_crouched else STAND_HEIGHT
	_height = move_toward(_height, target_height, delta * 4.5)
	(_collider.shape as CapsuleShape3D).height = _height
	_collider.position.y = _height * 0.5

	var speed := WALK_SPEED
	if is_crouched:
		speed = CROUCH_SPEED
	elif is_sprinting:
		speed = SPRINT_SPEED
	elif is_aiming or heal_left > 0.0:
		speed = AIM_SPEED
	speed *= float(build_stats["speed"])

	var wish := (global_transform.basis * Vector3(frame.move.x, 0.0, -frame.move.y))
	wish.y = 0.0
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var grounded := is_on_floor()
	flat = flat.move_toward(wish * speed, (60.0 if grounded else 14.0) * delta)
	if _dash_left > 0.0:
		flat = _dash_dir * 17.0

	velocity.x = flat.x
	velocity.z = flat.z
	if grounded:
		if frame.jump and not is_crouched and not is_dead:
			velocity.y = JUMP_SPEED
			Sfx.play("step", -8.0, 0.8)
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

	if is_on_floor() and not _was_on_floor:
		_land_dip = 0.12
		Sfx.play("step", -4.0, 0.7)
		_make_noise(9.0)
	_was_on_floor = is_on_floor()

	# Footsteps: both the sound and the noise enemies hear come off distance
	# travelled. Crouch-walking is silent to them.
	if is_on_floor():
		_step_distance += Vector2(velocity.x, velocity.z).length() * delta
		var stride := 2.3 if is_sprinting else 1.9
		if _step_distance >= stride:
			_step_distance = 0.0
			Sfx.play("step", -14.0 if is_crouched else (-6.0 if is_sprinting else -10.0), 1.1)
			if not is_crouched:
				_make_noise(13.0 if is_sprinting else 5.0)

func _can_stand() -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.5, global_position + Vector3.UP * (STAND_HEIGHT + 0.05), Layers.WORLD)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _abilities(frame: InputFrame) -> void:
	if frame.tactical and not _tactical_latched and tactical_cooldown <= 0.0:
		_use_ability(frame_def["tactical"], frame, true)
	_tactical_latched = frame.tactical
	if frame.prime and not _prime_latched and prime_cooldown <= 0.0:
		_use_ability(frame_def["prime"], frame, false)
	_prime_latched = frame.prime

func _use_ability(ability: Dictionary, frame: InputFrame, is_tactical: bool) -> void:
	var duration: float = ability.get("duration", 0.0)
	match ability["id"]:
		"dash":
			var local := Vector3(frame.move.x, 0.0, -frame.move.y)
			if local.length() < 0.1:
				local = Vector3.FORWARD
			_dash_dir = (global_transform.basis * local.normalized())
			_dash_left = 0.2
		"overcharge":
			overcharge_left = duration
			shield = max_shield
			for gun in guns:
				gun.rate_mult = 1.25
		"cloak":
			cloak_left = duration
		"pulse":
			pulse_left = duration
			Fx.burst(self, global_position + Vector3.UP, 45.0, Color(0.4, 0.75, 1.0), 0.9)
		"stim":
			if health >= max_health:
				notice.emit("Health is already full")
				return
			heal_left = duration
			heal_is_medkit = false
			_heal_rate = 40.0 / duration
		"fortify":
			fortify_left = duration
	if is_tactical:
		tactical_cooldown = ability["cooldown"]
	else:
		prime_cooldown = ability["cooldown"]
	Sfx.play("ability", -4.0, 1.0 if is_tactical else 0.75)

func _weapons(frame: InputFrame, delta: float) -> void:
	for g in guns:
		g.tick(delta)
	var current := gun()

	var want := gun_index
	if frame.weapon_slot >= 0 and frame.weapon_slot < guns.size():
		want = frame.weapon_slot
	elif frame.weapon_next and guns.size() > 1:
		want = (gun_index + 1) % guns.size()
	if want != gun_index:
		current.cancel_reload()
		gun_index = want
		_swap_left = SWAP_TIME
		Sfx.play("reload", -12.0, 1.4)
		return
	if _swap_left > 0.0:
		return

	if frame.reload and current.start_reload(overcharge_left > 0.0):
		Sfx.play("reload", -6.0)
	var trigger := frame.shoot if current.def["auto"] else frame.shoot_pressed
	if not trigger:
		return
	if heal_left > 0.0 and heal_is_medkit:
		heal_left = 0.0   # pulling the trigger abandons the medkit
	if current.mag <= 0 and not current.is_reloading():
		if current.start_reload(overcharge_left > 0.0):
			Sfx.play("reload", -6.0)
		elif frame.shoot_pressed:
			Sfx.play("empty")
		return
	if not current.can_fire():
		return

	var def := current.def
	var moving := Vector2(velocity.x, velocity.z).length() / WALK_SPEED
	var spread: float = def["spread"] * (float(def["ads"]) if is_aiming else 1.0)
	spread *= (1.0 + moving * 0.7) * (0.8 if is_crouched else 1.0) * (1.0 if is_on_floor() else 2.2)
	spread += bloom
	var origin := _camera.global_position
	var direction := -_camera.global_transform.basis.z
	var hits := current.fire(self, origin, direction, _muzzle_position(), spread, _rng)

	var best := 0
	for hit in hits:
		best = maxi(best, int(hit["result"]))
	if best > 0:
		hit_confirmed.emit(best)
		Sfx.play("kill" if best == 3 else ("headshot" if best == 2 else "hit"), -5.0)

	bloom = minf(bloom + float(def["recoil"]) * 0.28, 3.0)
	_kick_target += deg_to_rad(float(def["recoil"])) * (0.6 if is_aiming else 1.0)
	_yaw += deg_to_rad(_rng.randf_range(-0.35, 0.35) * float(def["recoil"])) * 0.5
	_view_kick = 1.0
	_shake = maxf(_shake, float(def["recoil"]) * 0.05)
	cloak_left = 0.0
	Sfx.play("shot_" + current.id, -3.0)
	_flash.visible = true
	Fx.flash(self, _muzzle_position(), Color(1.0, 0.8, 0.5), 2.2, 0.05, 6.0)
	_make_noise(float(def["noise"]))

func _healing(frame: InputFrame, delta: float) -> void:
	if heal_left > 0.0:
		var step := minf(delta, heal_left)
		health = minf(health + _heal_rate * step, max_health)
		heal_left -= step
		return
	if not frame.heal:
		return
	if health >= max_health:
		return
	if not GameManager.take_from_backpack("medkit"):
		if Engine.get_physics_frames() % 60 == 0:
			notice.emit("No medkits")
		return
	var time := 2.0 / float(build_stats["med_speed"])
	heal_left = time
	heal_is_medkit = true
	_heal_rate = float(Catalog.item("medkit")["heal"]) / time
	Sfx.play("open", -6.0, 1.3)

func _interact(frame: InputFrame, delta: float) -> void:
	var target := _find_interactable()
	if target == null:
		interact_label = ""
		interact_progress = 0.0
		if not frame.interact:
			_interact_latched = false
		return
	interact_label = target.interact_label()
	if not frame.interact:
		_interact_latched = false
		interact_progress = 0.0
		return
	if _interact_latched:
		return
	var needed: float = target.interact_time()
	interact_progress += delta / maxf(needed, 0.01)
	if interact_progress >= 1.0:
		interact_progress = 0.0
		_interact_latched = true
		target.interact(self)

func _find_interactable() -> Node:
	var from := _camera.global_position
	var query := PhysicsRayQueryParameters3D.create(from, from - _camera.global_transform.basis.z * INTERACT_REACH, Layers.INTERACT | Layers.WORLD)
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var node: Node = hit["collider"]
	if node != null and node.has_method("interact") and node.can_interact():
		return node
	return null

# The one place player health changes (rule 2). Returns 1 so shooters that
# care get a hit confirmation; 3 on death.
func take_damage(amount: float, from: Node = null, _position: Vector3 = Vector3.ZERO, _direction: Vector3 = Vector3.ZERO) -> int:
	if is_dead:
		return 0
	if fortify_left > 0.0:
		amount *= 0.5
	_since_damage = 0.0
	var had_shield := shield > 0.0
	var to_shield := minf(shield, amount)
	shield -= to_shield
	health -= amount - to_shield
	var source := (from as Node3D).global_position if from is Node3D else global_position
	damaged.emit(source, amount, amount - to_shield <= 0.0)
	_shake = maxf(_shake, 0.25)
	if had_shield and shield <= 0.0:
		Sfx.play("shield_break", -3.0)
	else:
		Sfx.play("hurt", -6.0, 1.5 if shield > 0.0 else 1.0)
	if heal_left > 0.0 and heal_is_medkit:
		heal_left = 0.0
	if health <= 0.0:
		health = 0.0
		is_dead = true
		died.emit(from)
		return 3
	return 1

func add_ammo(mags: int) -> void:
	for g in guns:
		g.reserve += int(g.def["mag"]) * mags

func gun() -> Gun:
	return guns[gun_index]

# --- What the AI is allowed to know ------------------------------------------

func eye_position() -> Vector3:
	return _head.global_position

func aim_point() -> Vector3:
	return global_position + Vector3.UP * (_height * 0.62)

# How easy we are to spot, as a multiplier on how fast an enemy's awareness
# fills. Zero means unseen.
func visibility(distance: float) -> float:
	if cloak_left > 0.0:
		return 1.0 if distance < 3.5 else 0.0
	var factor := 1.0
	if is_crouched:
		factor *= 0.55 * float(build_stats["stealth"])
	if is_sprinting:
		factor *= 1.5
	return factor

# Reloading, healing or swapping: the moments a squad should push.
func is_vulnerable() -> bool:
	return gun().is_reloading() or (heal_left > 0.0 and heal_is_medkit) or health < max_health * 0.3

func _make_noise(radius: float) -> void:
	get_tree().call_group("enemy", "hear", global_position, radius * float(build_stats["noise"]), self)

# --- View (cosmetic) ---------------------------------------------------------

func _process(delta: float) -> void:
	# Recoil: the view kicks to a target that itself relaxes back to zero.
	_kick_target = move_toward(_kick_target, 0.0, delta * 0.35 + _kick_target * delta * 5.0)
	_kick = lerpf(_kick, _kick_target, minf(delta * 28.0, 1.0))
	_shake = move_toward(_shake, 0.0, delta * 1.6)
	_land_dip = move_toward(_land_dip, 0.0, delta * 0.6)
	_view_kick = move_toward(_view_kick, 0.0, delta * 9.0)
	_aim_blend = move_toward(_aim_blend, 1.0 if is_aiming else 0.0, delta * 9.0)

	var eye := _height - EYE_OFFSET - _land_dip
	if is_dead:
		eye = lerpf(_head.position.y, 0.35, minf(delta * 3.0, 1.0))
		_head.rotation.z = lerpf(_head.rotation.z, 0.9, minf(delta * 3.0, 1.0))
	_head.position.y = eye
	_head.rotation.x = _pitch + _kick
	_camera.h_offset = randf_range(-1.0, 1.0) * _shake * 0.05
	_camera.v_offset = randf_range(-1.0, 1.0) * _shake * 0.05

	var def := gun().def
	var target_fov: float = lerpf(BASE_FOV + (5.0 if is_sprinting else 0.0), float(def["ads_fov"]), _aim_blend)
	_camera.fov = lerpf(_camera.fov, target_fov, minf(delta * 14.0, 1.0))

	# View model: bob with stride, lag behind the look, kick back on a shot,
	# drop out of frame while swapping, tilt down while reloading or healing.
	var speed := Vector2(velocity.x, velocity.z).length()
	_bob += delta * speed * 1.9
	var bob := Vector3(sin(_bob) * 0.012, absf(cos(_bob)) * -0.014, 0.0) * clampf(speed / WALK_SPEED, 0.0, 1.4) * (1.0 - _aim_blend * 0.85)
	_sway = _sway.lerp(Vector2.ZERO, minf(delta * 9.0, 1.0))
	var hip := Vector3(0.19, -0.16, -0.4)
	var ads := Vector3(0.0, -0.118, -0.3)
	var lower := 0.0
	if _swap_left > 0.0:
		lower = sin(_swap_left / SWAP_TIME * PI)
	elif gun().is_reloading():
		lower = sin(gun().reload_progress() * PI) * 0.7
	elif heal_left > 0.0:
		lower = 1.0
	elif is_sprinting:
		lower = 0.25
	_view.position = hip.lerp(ads, _aim_blend) + bob + Vector3(_sway.x, _sway.y - lower * 0.22, _view_kick * 0.045 * (0.5 if is_aiming else 1.0))
	_view.rotation = Vector3(_view_kick * 0.06 - lower * 0.8 + _sway.y * 1.5, _sway.x * -2.0 + (0.5 if is_sprinting and lower < 0.3 else 0.0) * (1.0 - _aim_blend), _sway.x * -1.5)
	var showing := gun_index if _swap_left < SWAP_TIME * 0.5 else -1
	for i in _view_models.size():
		_view_models[i].visible = i == showing or (showing == -1 and i != gun_index and _view_models.size() > 1)
	if _flash.visible and _view_kick < 0.75:
		_flash.visible = false
	var length: float = def["length"]
	_flash.position = Vector3(0.0, 0.0, -0.1 - length)

func _unhandled_input(event: InputEvent) -> void:
	# View lag only: the turn itself is applied from the InputFrame.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var relative := (event as InputEventMouseMotion).relative
		_sway = (_sway + Vector2(-relative.x, relative.y) * 0.00006).limit_length(0.03)

func _muzzle_position() -> Vector3:
	return _view.global_transform * Vector3(0.0, 0.0, -0.1 - float(gun().def["length"]))

func _build_view_models() -> void:
	_view = Node3D.new()
	_view.scale = Vector3.ONE * 0.85
	_camera.add_child(_view)
	var body_mat := Mats.surface(Color(0.24, 0.25, 0.27), "plain", 0.45, 0.5)
	var pale := Mats.surface(Color(0.78, 0.77, 0.74), "plain", 0.5, 0.2)
	var accent: Color = frame_def["accent"]
	for g in guns:
		var model := Node3D.new()
		_view.add_child(model)
		_view_models.append(model)
		var length: float = g.def["length"]
		var girth := 0.05 if g.id != "shotgun" else 0.062
		# Receiver, barrel, top rail with a sight, grip, magazine, accent line.
		_part(model, Vector3(0.0, 0.0, -length * 0.35), Vector3(girth, 0.085, length * 0.7), body_mat)
		_part(model, Vector3(0.0, 0.012, -length * 0.85 - 0.02), Vector3(girth * 0.55, girth * 0.55, length * 0.4), body_mat)
		_part(model, Vector3(0.0, 0.0, -length * 0.5), Vector3(girth + 0.012, 0.05, length * 0.36), pale)
		_part(model, Vector3(0.0, 0.05, -length * 0.3), Vector3(0.02, 0.014, length * 0.5), body_mat)
		_part(model, Vector3(0.0, 0.066, -0.06), Vector3(0.03, 0.022, 0.012), body_mat)
		_part(model, Vector3(0.0, 0.064, -length * 0.55), Vector3(0.008, 0.02, 0.008), Mats.glow(accent, 3.0))
		_part(model, Vector3(0.0, -0.085, 0.01), Vector3(0.04, 0.12, 0.05), body_mat).rotation.x = 0.25
		_part(model, Vector3(0.0, -0.09, -length * 0.3), Vector3(0.03, 0.12 if g.id != "shotgun" else 0.04, 0.05), pale)
		_part(model, Vector3(girth * 0.5 + 0.001, 0.01, -length * 0.4), Vector3(0.002, 0.012, length * 0.5), Mats.glow(accent, 2.5))
		if g.id == "dmr" or g.id == "rifle":
			_part(model, Vector3(0.0, 0.0, 0.1), Vector3(0.045, 0.1, 0.2), body_mat)
		# Hands: a forearm on the grip, another under the barrel.
		var hand := Mats.surface(Color(0.17, 0.18, 0.2), "plain", 0.7, 0.0)
		if g.id != "sidearm":
			_part(model, Vector3(-0.045, -0.085, -length * 0.5 + 0.05), Vector3(0.04, 0.04, 0.16), hand).rotation = Vector3(0.5, 0.6, 0.0)
		_part(model, Vector3(0.0, -0.1, 0.02), Vector3(0.05, 0.05, 0.06), hand)
	_flash = MeshInstance3D.new()
	var quad := SphereMesh.new()
	quad.radius = 0.035
	quad.height = 0.13
	_flash.mesh = quad
	_flash.rotation.x = PI * 0.5
	_flash.material_override = Mats.beam(Color(1.0, 0.8, 0.5), 3.0, 0.9)
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	_view.add_child(_flash)

func _part(parent: Node3D, at: Vector3, size: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance
