class_name ModelRig
extends Rig

# An enemy body from the Colony Security models (assets/enemies/colony-security,
# made outside this repo; see its README). Each model has its own skeleton and
# three clips -- Idle, Walk, Stagger -- with the gun modelled in the right hand,
# pointing at the ground.
#
# The clips are played here by hand (the AnimationPlayer is advanced in
# animate()), and then the bones are bent on top of them: both arms come up to
# the shoulder when the unit is alert and follow its aim pitch, the legs fold
# when it ducks. That keeps the guns pointed at what they are shooting at, which
# the clips alone never do.
#
# Same interface as Rig, so Enemy does not care which one it has. View only.

const ROOT: String = "res://assets/enemies/colony-security/"
const HEIGHT: float = 1.85          # every model is scaled to this before the unit's own scale
const WALK_SPEED: float = 1.5       # ground speed (m/s) the Walk clip was made for
# Which model wears which of the game's enemy types.
const MODELS: Dictionary = {
	"trooper": "patrol", "rusher": "shade", "bulwark": "bastion", "marksman": "longshot",
	"lobber": "sapper", "overseer": "marshal", "breacher": "breacher", "crawler": "crawler",
}

var _model: Node3D
var _skeleton: Skeleton3D
var _player: AnimationPlayer
var _bones: Dictionary = {}          # name -> index
var _mesh_list: Array[MeshInstance3D] = []
var _lens: Array = []                # [mesh, surface] of each lit lens, put out on death
var _gun_length: float = 0.7         # from the hand to the muzzle, in model metres
var _gun_tilt: float = 0.0           # how far the gun in the hand points below the forearm
const FOREARM: float = 0.28          # elbow to hand, in model metres
var _stagger_left: float = 0.0
var _clip: String = ""

static func has_model(type_id: String) -> bool:
	return MODELS.has(type_id) and ResourceLoader.exists(ROOT + str(MODELS[type_id]) + ".glb")

func setup(type_id: String, weapon_length: float) -> void:
	var name_id: String = MODELS[type_id]
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "catalog.json"))
	var tall: float = catalog.get(name_id, {}).get("height_m", HEIGHT)
	_model = (load(ROOT + name_id + ".glb") as PackedScene).instantiate()
	# The models face +Z; the game's units face -Z.
	_model.rotation.y = PI
	_model.scale = Vector3.ONE * (HEIGHT / tall)
	add_child(_model)
	_skeleton = _model.find_children("*", "Skeleton3D", true, false)[0]
	_player = _model.find_children("*", "AnimationPlayer", true, false)[0]
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for clip: String in ["Idle", "Walk"]:
		_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	for i in _skeleton.get_bone_count():
		_bones[_skeleton.get_bone_name(i)] = i
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		_mesh_list.append(mesh)
		for s in mesh.mesh.get_surface_count():
			var material := mesh.mesh.surface_get_material(s)
			if material != null and material.resource_name.begins_with("HQ_Lens"):
				_lens.append([mesh, s])
	_play("Idle", 0.0)
	_player.advance(0.0)
	# At rest the gun hangs straight down while the forearm angles forward; the
	# difference is how the gun sits in the hand.
	if _bones.has("forearmR"):
		var hang := _skeleton.get_bone_global_pose(_bones["forearmR"]).basis.y.normalized()
		_gun_tilt = acos(clampf(hang.dot(Vector3.DOWN), -1.0, 1.0))
	_gun_length = 0.05 + weapon_length * 0.5
	# Stagger the idle so a squad standing together does not breathe in step.
	_player.seek(randf() * 1.4, true)

func animate(delta: float, speed: float, raised: bool, pitch: float, crouched: bool = false) -> void:
	if _dead or _player == null:
		return
	_crouch = move_toward(_crouch, 1.0 if crouched else 0.0, delta * 5.0)
	_raise = move_toward(_raise, 1.0 if raised else 0.0, delta * 4.0)
	_flinch = move_toward(_flinch, 0.0, delta * 4.0)
	_stagger_left = maxf(_stagger_left - delta, 0.0)
	if _stagger_left <= 0.0:
		if speed > 0.35:
			_play("Walk", 0.2)
			_player.speed_scale = clampf(speed / WALK_SPEED, 0.6, 2.4)
		else:
			_play("Idle", 0.3)
			_player.speed_scale = 1.0
	# Back to rest first: the clips do not key every bone every frame, and the
	# bends below would otherwise pile up frame on frame.
	_skeleton.reset_bone_poses()
	_player.advance(delta)
	_pose(pitch)

# Bends bones on top of the clip. Everything is worked out in the world and
# turned into the skeleton's own space, so it does not matter which way the
# modelling tool's axes ran. A positive turn about the unit's right-hand axis
# swings a hanging limb forward.
func _pose(pitch: float) -> void:
	var aim := clampf(pitch, -0.6, 0.6)
	var ahead := -global_transform.basis.z.normalized()
	var right := global_transform.basis.x.normalized()
	# Straight at the target, tilted by the aim pitch.
	var line := ahead.rotated(right, aim)
	_point("upper_armR", "forearmR", line, _raise)
	# The gun is in the right hand, along the forearm: the forearm straightens down the line.
	_point("forearmR", "", line.rotated(right, -_gun_tilt), _raise)
	# The off hand comes up and across, under the barrel.
	var support := (line - right * 0.55).normalized()
	_point("upper_armL", "forearmL", support, _raise * 0.85)
	_point("forearmL", "", (line - right * 0.9).normalized(), _raise * 0.85)
	_turn("torso", right, -_flinch * 0.3 + aim * 0.2 * _raise)
	_turn("head", right, -aim * 0.4)
	for side: String in ["R", "L"]:
		_turn("upper_leg" + side, right, _crouch * 0.9)
		_turn("shin" + side, right, -_crouch * 1.6)
	_model.position.y = -_crouch * 0.3 / scale.y

# Swings a bone about its own root so that it runs from its root toward `toward`
# (a world direction), by `amount` of the way. Where it runs now is measured
# from its root to its child bone's root, or for an end bone along its own axis.
func _point(bone: String, child: String, toward: Vector3, amount: float) -> void:
	if amount < 0.002 or not _bones.has(bone) or (child != "" and not _bones.has(child)):
		return
	var index: int = _bones[bone]
	var pose := _skeleton.get_bone_global_pose(index)
	var reach := pose.basis.y if child == "" else _skeleton.get_bone_global_pose(_bones[child]).origin - pose.origin
	if reach.length() < 0.001:
		return
	var into := _skeleton.global_transform.basis.inverse()
	var want := (into * toward).normalized()
	var swing := Quaternion(reach.normalized(), want)
	var turn := Quaternion.IDENTITY.slerp(swing, clampf(amount, 0.0, 1.0))
	_skeleton.set_bone_global_pose(index, Transform3D(Basis(turn) * pose.basis, pose.origin))

# Turns a bone about a world axis through its own root.
func _turn(bone: String, axis: Vector3, angle: float) -> void:
	if absf(angle) < 0.0005 or not _bones.has(bone):
		return
	var index: int = _bones[bone]
	var pose := _skeleton.get_bone_global_pose(index)
	var local_axis := (_skeleton.global_transform.basis.inverse() * axis).normalized()
	_skeleton.set_bone_global_pose(index, Transform3D(Basis(local_axis, angle) * pose.basis, pose.origin))

func _play(clip: String, blend: float) -> void:
	if _clip == clip:
		return
	_clip = clip
	_player.play(clip, blend)

func flinch() -> void:
	_flinch = 1.0
	if not _dead and _stagger_left <= 0.0:
		_clip = ""
		_play("Stagger", 0.05)
		_player.speed_scale = 1.0
		_stagger_left = _player.get_animation("Stagger").length * 0.9

func muzzle_position() -> Vector3:
	if not _bones.has("forearmR"):
		return global_position + Vector3.UP * 1.3
	var forearm := _skeleton.global_transform * _skeleton.get_bone_global_pose(_bones["forearmR"])
	var along := forearm.basis.y.normalized()
	# Down the forearm to the hand, then along the gun, which sits _gun_tilt above it.
	var gun := along.rotated(global_transform.basis.x.normalized(), _gun_tilt)
	var size := _model.scale.x * scale.x
	return forearm.origin + along * FOREARM * size + gun * _gun_length * size

func head_position() -> Vector3:
	if not _bones.has("head"):
		return global_position + Vector3.UP * 1.7 * scale.y
	var head := _skeleton.global_transform * _skeleton.get_bone_global_pose(_bones["head"])
	return head.origin + Vector3.UP * 0.15 * scale.y

func set_fade(amount: float) -> void:
	for mesh in _mesh_list:
		mesh.transparency = amount

# Lights out, a last stagger, and over it goes, away from whatever killed it.
func die(push: Vector3) -> void:
	_dead = true
	set_fade(0.0)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.05, 0.05, 0.05)
	for spot: Array in _lens:
		(spot[0] as MeshInstance3D).set_surface_override_material(spot[1], dark)
	if _player != null:
		_clip = ""
		_play("Stagger", 0.05)
		_player.speed_scale = 0.7
		_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
	var flat := Vector3(push.x, 0.0, push.z)
	var local := (global_transform.basis.inverse() * flat).normalized() if flat.length() > 0.01 else Vector3.BACK
	var tween := create_tween().set_parallel(true).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "rotation:x", local.z * 1.5, 0.5)
	tween.tween_property(self, "rotation:z", -local.x * 1.5, 0.5)
	tween.tween_property(self, "position:y", -0.72, 0.5)
	tween.chain().tween_callback(func() -> void:
		if _player != null:
			_player.pause())
