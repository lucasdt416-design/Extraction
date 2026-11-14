class_name KestrelBody
extends Node3D

# Kestrel, the player character: the rigged model from
# assets/characters/kestrel, wrapped so the rest of the game only has to say
# how fast it is moving. View only (rule 6) -- it reads speed and plays the
# matching clip; nothing here feeds back into the simulation.

enum Mode {
	FULL,          # the whole character, as others see it (menu, third person)
	FIRST_PERSON,  # head and arms hidden so the camera can sit inside it; no shadow
	SHADOW,        # invisible, but casts the whole character's shadow
}

const SCENE: PackedScene = preload("res://assets/characters/kestrel/kestrel.glb")
const MODEL_HEIGHT: float = 2.047
# Ground speed each clip was authored to look right at, in metres per second.
const WALK_PACE: float = 2.4
const RUN_PACE: float = 6.2

var _anim: AnimationPlayer
var _skeleton: Skeleton3D
var _mesh: MeshInstance3D
var _hidden_bones: Array[int] = []
var _clip: String = ""
var _model: Node3D
var _scale: float = 1.0
# Collapse state: seconds since it began (-1 = standing), and the pose it began from.
var _fall_time: float = -1.0
var _fall_from: Dictionary = {}

func build(height: float, mode: Mode = Mode.FULL) -> void:
	var model := SCENE.instantiate() as Node3D
	# The model faces +Z; everything in this game faces -Z.
	model.rotation.y = PI
	model.scale = Vector3.ONE * (height / MODEL_HEIGHT)
	add_child(model)
	_model = model
	_scale = height / MODEL_HEIGHT
	_anim = model.find_children("*", "AnimationPlayer", true, false)[0]
	_skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	_mesh = model.find_children("*", "MeshInstance3D", true, false)[0]
	for clip in _anim.get_animation_list():
		_anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	match mode:
		Mode.FIRST_PERSON:
			_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			for bone: String in ["neck", "clavicle.L", "clavicle.R"]:
				_hidden_bones.append(_skeleton.find_bone(bone))
		Mode.SHADOW:
			_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	animate(0.0)

func animate(speed: float) -> void:
	var clip := "Idle"
	var rate := 1.0
	if speed > 4.4:
		clip = "Run"
		rate = clampf(speed / RUN_PACE, 0.7, 1.6)
	elif speed > 0.35:
		clip = "Walk"
		rate = clampf(speed / WALK_PACE, 0.5, 2.0)
	if clip != _clip:
		_clip = clip
		_anim.play(clip, 0.22)
	_anim.speed_scale = rate

# Death, with no authored clip to play: the skeleton is posed by hand through
# three overlapping beats -- a jolt backwards, the knees giving way, then the
# whole body pitching forward onto the ground.
func collapse() -> void:
	if _fall_time >= 0.0:
		return
	_anim.pause()
	_fall_time = 0.0
	for i in _skeleton.get_bone_count():
		_fall_from[_skeleton.get_bone_name(i)] = _skeleton.get_bone_pose_rotation(i)

func _bend(bone: String, axis: Vector3, angle: float) -> void:
	var index := _skeleton.find_bone(bone)
	if index >= 0:
		_skeleton.set_bone_pose_rotation(index, (_fall_from[bone] as Quaternion) * Quaternion(axis, angle))

func _pose_collapse() -> void:
	var t := _fall_time
	var jolt := smoothstep(0.0, 0.22, t) * (1.0 - smoothstep(0.35, 0.8, t))
	var buckle := smoothstep(0.18, 0.75, t)
	var pitch := smoothstep(0.55, 1.2, t)
	pitch *= pitch
	var settle := sin(clampf((t - 1.2) / 0.35, 0.0, 1.0) * PI) * 0.035
	for side: String in [".L", ".R"]:
		var sign := 1.0 if side == ".L" else -1.0
		# The legs fold as the knees go, then mostly straighten out once it's down.
		var fold := buckle * (1.0 - pitch * 0.75)
		_bend("thigh" + side, Vector3.RIGHT, -fold * 1.15)
		_bend("shin" + side, Vector3.RIGHT, fold * 1.85 + pitch * sign * 0.25)
		_bend("upper_arm" + side, Vector3.FORWARD, sign * (jolt * 0.9 - pitch * 0.5))
		_bend("forearm" + side, Vector3.RIGHT, -jolt * 0.7 - pitch * 0.6)
	_bend("spine", Vector3.RIGHT, -jolt * 0.3 + buckle * 0.35)
	_bend("chest", Vector3.RIGHT, -jolt * 0.25 + buckle * 0.25)
	_bend("neck", Vector3.RIGHT, -jolt * 0.5 + pitch * 0.4)
	_bend("head", Vector3.RIGHT, -jolt * 0.3 + pitch * 0.3)
	# The model faces +Z in its own space, so pitching forward is +X.
	_model.rotation.x = pitch * 1.5
	# Sinks as the knees go, then comes to rest lying just above the ground.
	_model.position.y = (-buckle * 0.42 * (1.0 - pitch) + pitch * 0.14 + settle) * _scale
	_model.position.z = pitch * 0.55 * _scale

func _process(delta: float) -> void:
	if _fall_time >= 0.0:
		_fall_time += delta
		_pose_collapse()
	# Collapsing a bone to nothing hides everything skinned to it and its
	# children. Re-applied every frame, after the clip has posed the skeleton.
	for bone in _hidden_bones:
		if bone >= 0:
			_skeleton.set_bone_pose_scale(bone, Vector3.ONE * 0.0001)
