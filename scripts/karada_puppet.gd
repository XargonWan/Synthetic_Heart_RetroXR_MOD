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

const VrmFace := preload("res://mods/xenu.synth_rift/scripts/vrm_face.gd")

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
## Her face (blink, emotion, mouth): null until a model is loaded.
var face: RefCounted = null


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
	_build_face(state, root)
	# Keep it from drawing a frame in the pose the file ships in until it has one.
	print("[Rift] VRM loaded: %d bones, %.2f m" % [skeleton.get_bone_count(), height])
	_bind()
	return true


## Her expressions, from the model file (see VrmFace). Godot hands no scene node back for a skinned mesh
## (GLTFState.get_scene_node is null for it), so a glTF node is found again by its NAME under the model.
func _build_face(state: GLTFState, root: Node3D) -> void:
	face = VrmFace.new()
	var json_nodes: Array = state.json.get("nodes", []) if state.json.get("nodes") is Array else []
	var mesh_instance_of := func(node_index: int) -> Node:
		if node_index < 0 or node_index >= json_nodes.size():
			return null
		var found := root.find_child(str((json_nodes[node_index] as Dictionary).get("name", "")), true, false)
		return found if found is MeshInstance3D else null
	var mesh_nodes := func(mesh_index: int) -> Array:
		var out: Array = []
		for i in json_nodes.size():
			if int((json_nodes[i] as Dictionary).get("mesh", -1)) == mesh_index:
				var n: Node = mesh_instance_of.call(i)
				if n != null:
					out.append(n)
		return out
	face.call("load_from", state.json, mesh_instance_of, mesh_nodes)


## The skin's persona.json (its blendshape_map says which expression each logical face name is).
func set_persona(persona: Dictionary) -> void:
	if face != null and persona.get("blendshape_map") is Dictionary:
		face.set("blendshape_map", persona["blendshape_map"])
		print("[Rift] her face map: %d names" % (persona["blendshape_map"] as Dictionary).size())


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


## How far the animation leans the torso, in degrees, averaged over its length: hips to neck against the
## vertical in the source rig, positive forward, NEGATIVE = arched back. Measured on the Mixamo skeleton
## itself, so it says what the clip does and not what the retarget made of it. Async: the player
## applies a pose on a frame.
func torso_lean(clip_name: String) -> float:
	if _src_skel == null or _player == null or not _clips.has(clip_name):
		return 0.0
	var hips := _src_skel.find_bone(_mx("Hips"))
	var neck := _src_skel.find_bone(_mx("Neck"))
	if hips < 0 or neck < 0:
		return 0.0
	var anim: Animation = _clips[clip_name]
	var before := _playing
	_player.play(clip_name)
	var samples := 12
	var sum := 0.0
	for k in samples:
		var t := anim.length * float(k) / float(samples)
		_player.seek(t, true)
		await get_tree().process_frame
		_player.seek(t, true)
		var d := _src_skel.get_bone_global_pose(neck).origin - _src_skel.get_bone_global_pose(hips).origin
		sum += rad_to_deg(atan2(d.z, d.y))
	if before != "":
		_player.play(before)
	else:
		_player.stop()
	return sum / float(samples)


## Of several clips for one state (a skin can ship an idle that stands badly), keep the one that
## stands most upright as `state`. Returns its name. The others stay under their own names.
func choose_most_upright(state: String, candidates: Array) -> String:
	var best := ""
	var best_lean := -INF
	for c: Variant in candidates:
		var lean: float = await torso_lean(str(c))
		print("[Rift] %s: torso leans %+.1f deg (negative = arched back)" % [str(c), lean])
		if lean > best_lean:
			best_lean = lean
			best = str(c)
	if best != "":
		alias_clip(state, best)
	return best


## `state` plays what `source` is.
func alias_clip(state: String, source: String) -> void:
	if not _clips.has(source):
		return
	if _lib.has_animation(state):
		_lib.remove_animation(state)
	_lib.add_animation(state, _clips[source])
	_clips[state] = _clips[source]


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


func _process(delta: float) -> void:
	if _playing != "":
		_retarget()
	_apply_gaze(delta)
	if face != null:
		face.call("update", delta)


# ── where she looks ──────────────────────────────────────────────────────────
#
# Her head follows a point in the world: the animation moves it, then this turns neck and head the
# rest of the way, clamped to what a neck can do and eased in and out so it never snaps. It is a
# reflex layer on top of the clip, like the WebUI avatar's eyes following the pointer: whether she
# looks is decided by the body (SynthBody), how is decided here.

const GAZE_YAW_LIMIT := deg_to_rad(70.0)
const GAZE_PITCH_UP := deg_to_rad(30.0)
const GAZE_PITCH_DOWN := deg_to_rad(25.0)
## How much of the turn the neck takes; the head takes the rest.
const GAZE_NECK_SHARE := 0.4
## Seconds the look takes to come in and to go out (a time constant).
const GAZE_EASE := 0.3

var _gaze_target: Variant = null
var _gaze_weight := 0.0


## Look at a world point, or at nothing (null): she eases back to the clip's own head.
func set_gaze(world_point: Variant) -> void:
	_gaze_target = world_point


func gaze_weight() -> float:
	return _gaze_weight


## Where her head points, in the model's space (-Z is her front): the head's turn from its rest
## applied to the front. For the tests, and for the turn below.
func head_forward() -> Vector3:
	var head := skeleton.find_bone(_vrm("Head")) if skeleton != null else -1
	if head < 0:
		return Vector3(0, 0, -1)
	var turn := skeleton.get_bone_global_pose(head).basis.get_rotation_quaternion() \
		* skeleton.get_bone_global_rest(head).basis.get_rotation_quaternion().inverse()
	return turn * Vector3(0, 0, -1)


func _apply_gaze(delta: float) -> void:
	if skeleton == null:
		return
	var want := 1.0 if _gaze_target != null else 0.0
	_gaze_weight = move_toward(_gaze_weight, want, delta / GAZE_EASE)
	if _gaze_weight < 0.001:
		return
	var neck := skeleton.find_bone(_vrm("Neck"))
	var head := skeleton.find_bone(_vrm("Head"))
	if neck < 0 or head < 0:
		return
	# While it eases out there is no target any more: hold the last one.
	if _gaze_target != null:
		_last_gaze = _gaze_target
	if _last_gaze == null:
		return
	var skel_inv := skeleton.global_transform.affine_inverse()
	var to_target: Vector3 = skel_inv * (_last_gaze as Vector3) - skeleton.get_bone_global_pose(head).origin
	if to_target.length() < 0.05:
		return
	var dir := to_target.normalized()
	# Against her front (-Z): yaw about UP, pitch above the horizon, both clamped.
	var yaw := clampf(atan2(dir.x, -dir.z), -GAZE_YAW_LIMIT, GAZE_YAW_LIMIT)
	var pitch := clampf(asin(clampf(dir.y, -1.0, 1.0)), -GAZE_PITCH_DOWN, GAZE_PITCH_UP)
	var goal := Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var current := head_forward()
	var arc := Quaternion(current, goal) if current.dot(goal) < 0.9999 else Quaternion.IDENTITY
	var turn := Quaternion.IDENTITY.slerp(arc, _gaze_weight)
	_turn_bone(neck, Quaternion.IDENTITY.slerp(turn, GAZE_NECK_SHARE))
	_turn_bone(head, Quaternion.IDENTITY.slerp(turn, 1.0 - GAZE_NECK_SHARE))


var _last_gaze: Variant = null


## Turn a bone by `q` in model space (its children follow).
func _turn_bone(bone: int, q: Quaternion) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_rot := Quaternion.IDENTITY
	if parent >= 0:
		parent_rot = skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion()
	var now := skeleton.get_bone_global_pose(bone).basis.get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(bone, (parent_rot.inverse() * q * now).normalized())


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
