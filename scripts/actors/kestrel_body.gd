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

func build(height: float, mode: Mode = Mode.FULL) -> void:
	var model := SCENE.instantiate() as Node3D
	# The model faces +Z; everything in this game faces -Z.
	model.rotation.y = PI
	model.scale = Vector3.ONE * (height / MODEL_HEIGHT)
	add_child(model)
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

func _process(_delta: float) -> void:
	# Collapsing a bone to nothing hides everything skinned to it and its
	# children. Re-applied every frame, after the clip has posed the skeleton.
	for bone in _hidden_bones:
		if bone >= 0:
			_skeleton.set_bone_pose_scale(bone, Vector3.ONE * 0.0001)
