## KaradaPuppet -- Synth's real body: her VRM skin, moved by her Mixamo animations.
##
## Both come from the Karada skins on the Synth server (`skins/<name>/model.vrm` and
## `animations/<state>/*.fbx`). Godot loads both at run time (GLTFDocument and FBXDocument),
## but the animations are for a Mixamo skeleton and the model is a VRoid one: the bones are
## named differently and their local axes do not agree, so an animation cannot just be
## played on it. This retargets by hand, every frame, in MODEL space:
##
##   delta   = source pose rotation * inverse(source rest rotation)     (how far it turned from rest)
##   desired = delta * target rest rotation                              (the same turn on her rest)
##   local   = inverse(parent's pose rotation) * desired
##
## which is right when the two rests face the same way (both are T-poses facing +Z). The hips
## also carry the height of the source's hips over its rest, scaled to her leg length;
## sideways and forward travel is dropped, the body walks by itself (SynthBody).
##
## Only a Mixamo/VRoid pair is mapped (`BONES`). Anything else loads as a still model.
extends Node3D

## [VRM bone, Mixamo bone] with {s} for the side: "L"/"Left" and "R"/"Right".
const BODY_BONES := [
	["Hips", "Hips"], ["Spine", "Spine"], ["Chest", "Spine1"], ["UpperChest", "Spine2"],
	["Neck", "Neck"], ["Head", "Head"],
	["{S}_Shoulder", "{Side}Shoulder"], ["{S}_UpperArm", "{Side}Arm"], ["{S}_LowerArm", "{Side}ForeArm"],
	["{S}_Hand", "{Side}Hand"],
	["{S}_UpperLeg", "{Side}UpLeg"], ["{S}_LowerLeg", "{Side}Leg"], ["{S}_Foot", "{Side}Foot"],
	["{S}_ToeBase", "{Side}ToeBase"],
]
const FINGERS := [["Thumb", "Thumb"], ["Index", "Index"], ["Middle", "Middle"], ["Ring", "Ring"], ["Little", "Pinky"]]

var model: Node3D = null
var skeleton: Skeleton3D = null
var height := 1.6

var _src_root: Node3D = null
var _src_skel: Skeleton3D = null
var _player: AnimationPlayer = null
## [{t: target bone, s: source bone, depth: int}], parents first.
var _pairs: Array = []
var _hips: Dictionary = {}
var _scale := 1.0
## Half a circle about UP when the animation's rig and hers face opposite ways, else identity.
var _yaw := Quaternion.IDENTITY
var _playing := ""
var _after := ""
var _lib := AnimationLibrary.new()
var _clips: Dictionary = {}


## The model, from the bytes of a .vrm. True when it loaded with a skeleton.
func load_model(vrm: PackedByteArray) -> bool:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_buffer(vrm, "", state)
	if err != OK:
		print("[Rift] VRM did not load: %s" % error_string(err))
		return false
	var root := doc.generate_scene(state) as Node3D
	if root == null:
		return false
	var skels := root.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		print("[Rift] VRM has no skeleton")
		root.queue_free()
		return false
	if model != null:
		model.queue_free()
	model = root
	skeleton = skels[0] as Skeleton3D
	model.name = "Model"
	add_child(model)
	height = _measure_height()
	# Keep it from drawing a frame in the pose the file ships in until it has one.
	print("[Rift] VRM loaded: %d bones, %.2f m" % [skeleton.get_bone_count(), height])
	_bind()
	return true


## One animation, from the bytes of a Mixamo .fbx, under `clip_name`. The first one loaded
## brings the source skeleton; the others share it (the same rig, the same track paths).
func add_clip(clip_name: String, fbx: PackedByteArray) -> bool:
	var doc := FBXDocument.new()
	var state := FBXState.new()
	if doc.append_from_buffer(fbx, "", state) != OK:
		print("[Rift] FBX '%s' did not load" % clip_name)
		return false
	var scene := doc.generate_scene(state) as Node3D
	if scene == null:
		return false
	var ap: AnimationPlayer = null
	for n: Node in scene.find_children("*", "AnimationPlayer", true, false):
		ap = n as AnimationPlayer
		break
	if ap == null or ap.get_animation_list().is_empty():
		scene.queue_free()
		return false
	var anim: Animation = ap.get_animation(ap.get_animation_list()[0]).duplicate()
	if _src_root == null:
		_src_root = scene
		_src_root.name = "AnimationSource"
		_src_root.visible = false
		add_child(_src_root)
		_src_skel = _src_root.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		_player = ap
		for old: String in _player.get_animation_list():
			_lib.add_animation(old, _player.get_animation(old))
		_player.remove_animation_library("")
		_player.add_animation_library("", _lib)
		_player.animation_finished.connect(_on_clip_finished)
		_bind()
	else:
		scene.queue_free()
	_lib.add_animation(clip_name, anim)
	_clips[clip_name] = anim
	return true


func has_clip(clip_name: String) -> bool:
	return _clips.has(clip_name)


## Play a clip (looping). Unknown names are ignored, the model keeps what it was doing.
func play(clip_name: String, loop: bool = true) -> bool:
	if _player == null or not _clips.has(clip_name):
		return false
	var anim: Animation = _clips[clip_name]
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	if _playing != clip_name or not _player.is_playing():
		_player.play(clip_name)
	_playing = clip_name
	_after = ""
	return true


## Play a clip once, then `next` (looping): a greeting, then standing again.
func play_then(clip_name: String, next: String) -> bool:
	if not play(clip_name, false):
		return false
	_after = next if _clips.has(next) else ""
	return true


func _on_clip_finished(finished: StringName) -> void:
	if _after != "" and str(finished) == _playing:
		var next := _after
		_after = ""
		play(next, true)


func playing() -> String:
	return _playing


func clip_length(clip_name: String) -> float:
	return (_clips[clip_name] as Animation).length if _clips.has(clip_name) else 0.0


## Seek (a test, or a still frame).
func seek(seconds: float) -> void:
	if _player != null:
		_player.seek(seconds, true)
		_retarget()


## Bone pairs found in both skeletons: for the tests.
func mapped_bones() -> int:
	return _pairs.size()


func _process(_delta: float) -> void:
	if _playing != "":
		_retarget()


# ── the mapping ──────────────────────────────────────────────────────────────

func _bind() -> void:
	_pairs.clear()
	_hips = {}
	if skeleton == null or _src_skel == null:
		return
	var names: Array = []
	for side: Array in [["L", "Left"], ["R", "Right"]]:
		for pair: Array in BODY_BONES:
			if pair[0] == "Hips" or pair[0] in ["Spine", "Chest", "UpperChest", "Neck", "Head"]:
				if side[0] == "R":
					continue
			names.append([_vrm(str(pair[0]).replace("{S}", side[0])), _mx(str(pair[1]).replace("{Side}", side[1]))])
		for finger: Array in FINGERS:
			for i in [1, 2, 3]:
				names.append([_vrm("%s_%s%d" % [side[0], finger[0], i]), _mx("%sHand%s%d" % [side[1], finger[1], i])])
	for pair: Array in names:
		var t := skeleton.find_bone(pair[0])
		var s := _src_skel.find_bone(pair[1])
		if t >= 0 and s >= 0:
			_pairs.append({"t": t, "s": s, "depth": _depth(skeleton, t)})
	_pairs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["depth"] < b["depth"])
	var th := skeleton.find_bone(_vrm("Hips"))
	var sh := _src_skel.find_bone(_mx("Hips"))
	if th >= 0 and sh >= 0:
		_hips = {"t": th, "s": sh}
		var tgt_y := skeleton.get_bone_global_rest(th).origin.y
		var src_y := _src_skel.get_bone_global_rest(sh).origin.y
		_scale = tgt_y / src_y if absf(src_y) > 0.0001 else 1.0
	# Which way each rig faces: a body's LEFT arm is on +X when it faces +Z and on -X when it
	# faces -Z. VRoid models face -Z (VRM 0.x), Mixamo +Z, so a rotation measured in one model
	# space has to be turned half a circle to mean the same in the other.
	var tl := skeleton.find_bone(_vrm("L_UpperArm"))
	var sl := _src_skel.find_bone(_mx("LeftArm"))
	_yaw = Quaternion.IDENTITY
	if tl >= 0 and sl >= 0:
		var tx := skeleton.get_bone_global_rest(tl).origin.x
		var sx := _src_skel.get_bone_global_rest(sl).origin.x
		if signf(tx) != signf(sx):
			_yaw = Quaternion(Vector3.UP, PI)
		print("[Rift] left arm at x=%.3f (her) and %.3f (animation): %s" % [tx, sx, "facing opposite ways, turned" if _yaw != Quaternion.IDENTITY else "facing the same way"])
	print("[Rift] retarget bound: %d bones, hips scale %.3f" % [_pairs.size(), _scale])


static func _vrm(bone: String) -> String:
	return "J_Bip_%s" % (bone if bone.contains("_") else "C_" + bone)


static func _mx(bone: String) -> String:
	return "mixamorig_%s" % bone


static func _depth(sk: Skeleton3D, bone: int) -> int:
	var d := 0
	var b := sk.get_bone_parent(bone)
	while b >= 0:
		d += 1
		b = sk.get_bone_parent(b)
	return d


func _retarget() -> void:
	if _pairs.is_empty() or _src_skel == null:
		return
	for p: Dictionary in _pairs:
		var t: int = p["t"]
		var s: int = p["s"]
		var src_pose := _src_skel.get_bone_global_pose(s).basis.get_rotation_quaternion()
		var src_rest := _src_skel.get_bone_global_rest(s).basis.get_rotation_quaternion()
		var delta := _yaw * (src_pose * src_rest.inverse()) * _yaw.inverse()
		var desired := delta * skeleton.get_bone_global_rest(t).basis.get_rotation_quaternion()
		var parent := skeleton.get_bone_parent(t)
		var parent_pose := Quaternion.IDENTITY
		if parent >= 0:
			parent_pose = skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion()
		skeleton.set_bone_pose_rotation(t, (parent_pose.inverse() * desired).normalized())
	if not _hips.is_empty():
		var t: int = _hips["t"]
		var s: int = _hips["s"]
		var rise := (_src_skel.get_bone_pose(s).origin.y - _src_skel.get_bone_rest(s).origin.y) * _scale
		var rest := skeleton.get_bone_rest(t).origin
		skeleton.set_bone_pose_position(t, rest + Vector3(0, rise, 0))


func _measure_height() -> float:
	var top := -INF
	var bottom := INF
	for m: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		var box := model.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		top = maxf(top, box.end.y)
		bottom = minf(bottom, box.position.y)
	return top - bottom if top > bottom else 1.6
