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
var _mags: Array[Node3D] = []
var _flash: MeshInstance3D
var _body: KestrelBody
var _shadow_body: KestrelBody
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

	# Kestrel's body: one copy you see when you look down, one that only casts
	# the shadow (so your shadow keeps its head and arms).
	_body = KestrelBody.new()
	_body.position.z = 0.2
	add_child(_body)
	_body.build(STAND_HEIGHT, KestrelBody.Mode.FIRST_PERSON)
	_shadow_body = KestrelBody.new()
	add_child(_shadow_body)
	_shadow_body.build(STAND_HEIGHT, KestrelBody.Mode.SHADOW)

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

	var ground_speed := Vector2(velocity.x, velocity.z).length() if is_on_floor() else 0.0
	for body: KestrelBody in [_body, _shadow_body]:
		body.animate(ground_speed)
		body.scale.y = _height / STAND_HEIGHT

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
	# Lines the optic (or the pistol's irons) up with the centre of the screen.
	var ads := Vector3(0.0, -0.0723 if gun().id != "sidearm" else -0.045, -0.24)
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
	# Reloading drops the magazine out and brings a fresh one up.
	var reload := gun().reload_progress()
	_mags[gun_index].position.y = -0.3 * clampf(sin(clampf((reload - 0.12) / 0.6, 0.0, 1.0) * PI) * 1.6, 0.0, 1.0)
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
	var dark := Mats.surface(Color(0.085, 0.09, 0.1), "plain", 0.42, 0.75)
	var steel := Mats.surface(Color(0.2, 0.21, 0.23), "plain", 0.3, 0.9)
	var pale := Mats.surface(Color(0.74, 0.73, 0.69), "plain", 0.55, 0.1)
	var rubber := Mats.surface(Color(0.05, 0.05, 0.055), "plain", 0.85, 0.0)
	# Kestrel's forearms: chalk ceramic, carbon gloves, an acid-yellow cuff.
	var sleeve := Mats.surface(Color(0.90, 0.91, 0.89), "plain", 0.32, 0.2)
	var cuff := Mats.surface(Color(0.62, 0.66, 0.07), "plain", 0.45, 0.1)
	var accent: Color = frame_def["accent"]
	var lit := Mats.glow(accent, 3.0)
	for g in guns:
		var model := Node3D.new()
		_view.add_child(model)
		_view_models.append(model)
		var length: float = g.def["length"]
		var long := g.id != "sidearm"
		var body := 0.3 if long else length          # receiver length
		var reach := length - body                    # how far the barrel runs past it
		var wide := 0.056 if g.id == "shotgun" else 0.046

		if long:
			# Receiver, with a pale side plate and an ejection port.
			_solid(model, Vector3(0.0, 0.0, -body * 0.5), Vector3(wide, 0.078, body), dark, 0.012)
			_solid(model, Vector3(0.0, -0.004, -body * 0.42), Vector3(wide + 0.006, 0.04, body * 0.5), pale, 0.006)
			_solid(model, Vector3(wide * 0.5 + 0.001, 0.016, -body * 0.55), Vector3(0.003, 0.02, 0.07), steel, 0.001)
			# Stock, with a rubber butt pad.
			_solid(model, Vector3(0.0, -0.012, 0.115), Vector3(wide - 0.008, 0.07, 0.2), dark, 0.014)
			_solid(model, Vector3(0.0, -0.02, 0.222), Vector3(wide - 0.004, 0.1, 0.022), rubber, 0.008)
			# Handguard with vent slots, then the barrel and muzzle.
			var guard := reach * 0.62
			_solid(model, Vector3(0.0, 0.002, -body - guard * 0.5), Vector3(wide - 0.004, 0.058, guard), pale if g.id != "shotgun" else dark, 0.012)
			for slot in 4:
				_solid(model, Vector3(0.0, 0.004, -body - guard * (0.2 + slot * 0.2)), Vector3(wide - 0.002, 0.016, guard * 0.09), dark, 0.002)
			var bore := 0.019 if g.id == "shotgun" else 0.011
			_tube(model, Vector3(0.0, 0.008, -body - reach * 0.5 - 0.03), bore, reach + 0.06, steel)
			_tube(model, Vector3(0.0, 0.008, -length - 0.06), bore + 0.007, 0.07, dark)
			if g.id == "shotgun":
				_tube(model, Vector3(0.0, -0.032, -body - reach * 0.45), 0.016, reach * 0.9, steel)
				_solid(model, Vector3(0.0, -0.03, -body - reach * 0.4), Vector3(0.062, 0.05, 0.13), pale, 0.014)
			# Top rail and the optic.
			_solid(model, Vector3(0.0, 0.045, -body * 0.5 - guard * 0.3), Vector3(0.02, 0.012, body + guard * 0.6), steel, 0.003)
			if g.id == "dmr":
				_tube(model, Vector3(0.0, 0.085, -body * 0.45), 0.021, 0.2, dark)
				_tube(model, Vector3(0.0, 0.085, -body * 0.45 - 0.115), 0.027, 0.05, dark)
				_tube(model, Vector3(0.0, 0.085, -body * 0.45 + 0.105), 0.024, 0.03, dark)
				for ring: float in [-0.05, 0.05]:
					_solid(model, Vector3(0.0, 0.066, -body * 0.45 + ring), Vector3(0.03, 0.04, 0.018), steel, 0.004)
			else:
				# Reflex sight: a housing, a tinted pane, and the dot.
				_solid(model, Vector3(0.0, 0.058, -body * 0.4), Vector3(0.036, 0.016, 0.05), dark, 0.004)
				for side: float in [-1.0, 1.0]:
					_solid(model, Vector3(side * 0.017, 0.082, -body * 0.4 - 0.014), Vector3(0.004, 0.04, 0.012), dark, 0.0015)
				_solid(model, Vector3(0.0, 0.103, -body * 0.4 - 0.014), Vector3(0.038, 0.004, 0.012), dark, 0.0015)
				var pane := _part(model, Vector3(0.0, 0.083, -body * 0.4 - 0.014), Vector3(0.03, 0.036, 0.001), Mats.glass(accent))
				pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_part(model, Vector3(0.0, 0.085, -body * 0.4 - 0.0135), Vector3(0.003, 0.003, 0.001), Mats.glow(Color(1.0, 0.2, 0.15), 6.0))
			_solid(model, Vector3(0.0, 0.058, -body - guard * 0.55), Vector3(0.006, 0.02, 0.008), steel, 0.002)
		else:
			# Pistol: slide over a frame, a short barrel, iron sights.
			_solid(model, Vector3(0.0, 0.018, -length * 0.5), Vector3(0.034, 0.042, length), dark, 0.008)
			_solid(model, Vector3(0.0, -0.014, -length * 0.42), Vector3(0.03, 0.03, length * 0.8), pale, 0.007)
			for cut in 5:
				_solid(model, Vector3(0.0, 0.018, -0.02 - cut * 0.012), Vector3(0.036, 0.03, 0.004), steel, 0.001)
			_tube(model, Vector3(0.0, 0.016, -length - 0.008), 0.0085, 0.03, steel)
			_solid(model, Vector3(0.0, 0.046, -0.014), Vector3(0.02, 0.012, 0.01), dark, 0.002)
			_solid(model, Vector3(0.0, 0.046, -length + 0.02), Vector3(0.005, 0.012, 0.008), dark, 0.002)
			_part(model, Vector3(0.0, 0.05, -length + 0.024), Vector3(0.003, 0.004, 0.001), lit)
			_solid(model, Vector3(0.0, -0.036, -length * 0.5), Vector3(0.012, 0.02, 0.07), dark, 0.004)

		# Grip, trigger guard, magazine (kept as its own node so reloads can drop it).
		var grip := _solid(model, Vector3(0.0, -0.085, 0.006 if long else -0.012), Vector3(0.034, 0.115, 0.046), rubber, 0.012)
		grip.rotation.x = 0.28
		_solid(model, Vector3(0.0, -0.058, -0.06), Vector3(0.008, 0.008, 0.075), dark, 0.002)
		var mag := Node3D.new()
		model.add_child(mag)
		_mags.append(mag)
		if long and g.id != "shotgun":
			var mag_height := 0.2 if g.id == "smg" else (0.1 if g.id == "dmr" else 0.16)
			var block := _solid(mag, Vector3(0.0, -0.04 - mag_height * 0.5, -body * 0.42), Vector3(0.028, mag_height, 0.056), steel, 0.007)
			block.rotation.x = 0.0 if g.id == "smg" else -0.2
		elif not long:
			_solid(mag, Vector3(0.0, -0.148, 0.004), Vector3(0.03, 0.012, 0.046), steel, 0.004).rotation.x = 0.28
		# Accent line down the receiver.
		_part(model, Vector3((wide if long else 0.034) * 0.5 + 0.0015, 0.024, -body * 0.5), Vector3(0.0015, 0.006, body * 0.7), lit)

		# Hands and forearms: trigger hand on the grip, support hand forward.
		var hold := Vector3(0.0, -0.085, 0.01 if long else -0.01)
		_arm(model, hold + Vector3(0.012, -0.012, 0.0), Vector3(0.1, -0.2, 0.34), rubber, sleeve, cuff)
		var support := Vector3(0.0, -0.045, -body - reach * 0.3) if long else Vector3(-0.012, -0.11, -0.012)
		_arm(model, support + Vector3(-0.012, -0.012, 0.0), Vector3(-0.2, -0.22, 0.2 if long else 0.3), rubber, sleeve, cuff)

	_flash = MeshInstance3D.new()
	var burst := SphereMesh.new()
	burst.radius = 0.035
	burst.height = 0.15
	_flash.mesh = burst
	_flash.rotation.x = PI * 0.5
	_flash.material_override = Mats.beam(Color(1.0, 0.8, 0.5), 3.0, 0.9)
	_flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flash.visible = false
	_view.add_child(_flash)

# A glove at `hand` and a sleeved forearm running back to `elbow`.
func _arm(parent: Node3D, hand: Vector3, elbow: Vector3, glove: Material, cloth: Material, cuff: Material) -> void:
	_solid(parent, hand, Vector3(0.052, 0.05, 0.078), glove, 0.016)
	var along := elbow - hand
	var wrist := hand + along * 0.12
	_limb(parent, wrist, elbow, 0.036, cloth)
	_limb(parent, wrist + along * 0.02, wrist + along * 0.07, 0.04, cuff)

# A capsule between two points.
func _limb(parent: Node3D, from: Vector3, to: Vector3, radius: float, mat: Material) -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = from.distance_to(to) + radius * 2.0
	mesh.radial_segments = 16
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var up := (to - from).normalized()
	var side := up.cross(Vector3.FORWARD).normalized()
	instance.transform = Transform3D(Basis(side, up, side.cross(up)), (from + to) * 0.5)
	parent.add_child(instance)

# A cylinder along the barrel axis.
func _tube(parent: Node3D, at: Vector3, radius: float, length: float, mat: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 20
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mat
	instance.position = at
	instance.rotation.x = PI * 0.5
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)

func _solid(parent: Node3D, at: Vector3, size: Vector3, mat: Material, bevel: float) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = Shapes.rounded_box(size, bevel, 2)
	instance.material_override = mat
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

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
