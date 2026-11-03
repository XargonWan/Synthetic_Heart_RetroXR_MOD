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
const VrmBudget := preload("res://mods/xenu.synth_rift/scripts/vrm_budget.gd")
const BodyCache := preload("res://mods/xenu.synth_rift/scripts/body_cache.gd")

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
## Each clip's descriptor from the skin (`.fbx.json`): its intro / loop / outro frames and its `mask`.
var _descriptors: Dictionary = {}
## The window of the playing clip that repeats: {start, end} in seconds, or empty (the whole clip loops).
var _window: Dictionary = {}

## A clip that moves only the upper body (a descriptor with `"mask": "upper_body"`: a game played seated, shown
## standing, walking or sitting) plays on a second copy of the animation's skeleton, and only the bones from the
## hips up read it; the legs go on reading the base clip.
var _over_root: Node3D = null
var _over_skel: Skeleton3D = null
var _over_player: AnimationPlayer = null
var _over_clip := ""
var _over_window: Dictionary = {}

## Seconds one clip takes to melt into the next (0 = a cut). The pose she was in is kept and the new one is blended
## in from it, bone by bone, so it holds for a change of clip, of window or of layer alike.
var xfade_seconds := 0.3
var _last_local: Dictionary = {}
var _last_rise := 0.0
var _from_local: Dictionary = {}
var _from_rise := 0.0
var _xf_left := 0.0
## A clip that does not loop has played to its end.
signal clip_finished(clip_name: String)

## What the body cost and how it was brought inside its budget (VrmBudget): tier, triangles, ... and the time.
var budget: Dictionary = {}

## Her face (blink, emotion, mouth): null until a model is loaded.
var face: RefCounted = null


## The model, from the bytes of a .vrm. True when it loaded with a skeleton.
## The model, from the bytes of a .vrm, brought inside the tier's budget (VrmBudget) and kept (BodyCache): the
## second time the same file is asked for, the finished body is read back and nothing is parsed. True when it
## loaded with a skeleton. `use_cache` false makes it fresh and does not keep it (the tests).
func load_model(vrm: PackedByteArray, use_cache: bool = true) -> bool:
	var t0 := Time.get_ticks_msec()
	var tier_name := VrmBudget.tier_name()
	var key := BodyCache.key_for(vrm, tier_name) if use_cache else ""
	var root: Node3D = null
	var from_cache := false
	var stats := {}
	if use_cache:
		var cached := BodyCache.load_body(key)
		if not cached.is_empty():
			root = cached["root"]
			stats = cached["stats"]
			face = VrmFace.new()
			face.call("from_data", cached["face"], root)
			from_cache = true
	if root == null:
		# The document is made INSIDE the image step: it takes the registered extensions when it is created.
		var made: Array = []
		var err: int = VrmBudget.with_image_budget(VrmBudget.tier(), func() -> int:
			var doc := GLTFDocument.new()
			var state := GLTFState.new()
			made.append(doc)
			made.append(state)
			return doc.append_from_buffer(vrm, "", state))
		if err != OK:
			print("[Rift] VRM did not load: %s" % error_string(err))
			return false
		var doc: GLTFDocument = made[0]
		var state: GLTFState = made[1]
		root = doc.generate_scene(state) as Node3D
		if root == null:
			return false
		_build_face(state, root)
		var images := VrmBudget.last_image_stats()
		print("[Rift] image step: %s" % str(images))
		var reduced := VrmBudget.reduce_meshes(root, face, VrmBudget.tier())
		var packed := VrmBudget.compress_textures(root, VrmBudget.tier())
		stats = {"images": images, "reduced": reduced, "textures": packed}
	var skels := root.find_children("*", "Skeleton3D", true, false)
	if skels.is_empty():
		print("[Rift] VRM has no skeleton")
		root.queue_free()
		return false
	if use_cache and not from_cache:
		BodyCache.store(key, root, face.call("to_data", root), stats)
	if model != null:
		model.queue_free()
	model = root
	skeleton = skels[0] as Skeleton3D
	model.name = "Model"
	add_child(model)
	height = _measure_height()
	var measured := VrmBudget.measure(model)
	budget = {"tier": tier_name, "from_cache": from_cache, "tris": measured["tris"], "verts": measured["verts"],
		"surfaces": measured["surfaces"], "blend_shapes": measured["blend_shapes"], "texture_bytes": measured["texture_bytes"],
		"texture_max": measured["texture_max"], "ms": Time.get_ticks_msec() - t0,
		"stats": stats}
	print("[Rift] VRM loaded (%s%s): %d bones, %.2f m, %d tris, %d verts, %d surfaces, %d blend shapes, textures %s (%.0f MB in the materials, largest %d px), %d ms" % [
		tier_name, ", from the cache" if from_cache else "", skeleton.get_bone_count(), height, measured["tris"],
		measured["verts"], measured["surfaces"], measured["blend_shapes"], _images_text(stats),
		float(measured["texture_bytes"]) / 1048576.0, measured["texture_max"], budget["ms"]])
	_bind()
	return true


## What the texture step did, as text: "24 textures, 136 MB -> 24 MB".
func _images_text(stats: Dictionary) -> String:
	var t: Dictionary = stats.get("textures", {}) if stats.get("textures") is Dictionary else {}
	if t.is_empty() or int(t.get("textures", 0)) == 0:
		return "as they were"
	return "%d compressed, %.0f MB -> %.0f MB%s" % [int(t.get("textures", 0)), float(t.get("bytes_before", 0)) / 1048576.0,
		float(t.get("bytes_after", 0)) / 1048576.0, (", %d would not compress" % int(t["errors"])) if int(t.get("errors", 0)) > 0 else ""]


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


# ── fading her in and out ────────────────────────────────────────────────────
#
# GeometryInstance3D.transparency is a dither, and on this model it is not one fade: a cut-out material (her
# clothes) is discarded as soon as it is a little see-through while the skin only thins, so at 30% she is
# NAKED and at 55% nothing is drawn at all. So she fades through her MATERIALS: each one is copied once into
# an alpha-blended twin (with a depth pre-pass, so her own arm does not show through her own body) and every
# twin has the same alpha. At zero the originals are put back, exactly as the file made them.

## [{mi, surface, original: Material (the override that was there, or null), twin: BaseMaterial3D}]
var _fade_slots: Array = []
var _fade_prepared := false
var _fade_amount := 0.0


func _prepare_fade() -> void:
	if _fade_prepared or model == null:
		return
	_fade_prepared = true
	var twins := {}
	for n: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		for surface in mi.mesh.get_surface_count():
			var source := mi.get_active_material(surface)
			if not (source is BaseMaterial3D):
				continue
			if not twins.has(source):
				var twin := source.duplicate() as BaseMaterial3D
				twin.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
				twins[source] = twin
			_fade_slots.append({"mi": mi, "surface": surface, "original": mi.get_surface_override_material(surface),
				"twin": twins[source], "source": source})


## 0 = as the file made her, 1 = gone; one number for every part. The twins are only worn while it is above 0.
func set_fade(amount: float) -> void:
	_prepare_fade()
	if _fade_slots.is_empty():
		for part: Node in find_children("*", "GeometryInstance3D", true, false):
			(part as GeometryInstance3D).transparency = amount
		return
	var was := _fade_amount
	_fade_amount = clampf(amount, 0.0, 1.0)
	if _fade_amount <= 0.0:
		if was > 0.0:
			for slot: Dictionary in _fade_slots:
				(slot["mi"] as MeshInstance3D).set_surface_override_material(int(slot["surface"]), slot["original"])
		return
	var alpha := 1.0 - _fade_amount
	if was <= 0.0:
		for slot: Dictionary in _fade_slots:
			(slot["mi"] as MeshInstance3D).set_surface_override_material(int(slot["surface"]), slot["twin"])
	var seen := {}
	for slot: Dictionary in _fade_slots:
		var twin: BaseMaterial3D = slot["twin"]
		if not seen.has(twin):
			seen[twin] = true
			var c := twin.albedo_color
			c.a = alpha * (slot["source"] as BaseMaterial3D).albedo_color.a
			twin.albedo_color = c


func fade_amount() -> float:
	return _fade_amount


## Every part's current fade, for the tests: material alphas while fading.
func fade_alphas() -> Array:
	var out: Array = []
	for slot: Dictionary in _fade_slots:
		var m := (slot["mi"] as MeshInstance3D).get_active_material(int(slot["surface"]))
		if m is BaseMaterial3D:
			out.append(snappedf((m as BaseMaterial3D).albedo_color.a / maxf((slot["source"] as BaseMaterial3D).albedo_color.a, 0.0001), 0.001))
	return out


## True once every part has been drawn (see warm()).
var warmed := false


## Pay the first draw where nobody looks. A model that is first drawn on the frame it appears compiles its
## pipelines and uploads its textures there, and arrives in pieces (the clothes after the skin); so every
## part is drawn once, off screen, in the two states it will be seen in (see-through and solid), before she is
## shown. The same trick ModelWarmer plays for the machines. A headless run draws nothing, so there is
## nothing to warm (and a SubViewport that updates always hangs one).
func warm() -> void:
	if warmed or model == null:
		warmed = true
		return
	if DisplayServer.get_name() == "headless":
		warmed = true
		return
	var t0 := Time.get_ticks_msec()
	var home := get_parent()
	var viewport := SubViewport.new()
	viewport.name = "BodyWarmViewport"
	viewport.size = Vector2i(256, 256)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	home.add_child(viewport)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, height * 0.55, height * 2.0)
	viewport.add_child(camera)
	camera.look_at_from_position(camera.position, Vector3(0.0, height * 0.5, 0.0))
	camera.current = true
	viewport.add_child(DirectionalLight3D.new())
	var was_visible := visible
	reparent(viewport, false)
	visible = true
	if _player != null and _clips.has("idle"):
		play("idle", true)
		_retarget()
	var parts: Array = find_children("*", "GeometryInstance3D", true, false)
	for amount: float in [0.7, 0.4, 0.0]:
		set_fade(amount)
		for i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
	visible = was_visible
	reparent(home, false)
	position = Vector3.ZERO
	viewport.queue_free()
	warmed = true
	print("[Rift] her body is warmed: %d parts drawn in %d ms" % [parts.size(), Time.get_ticks_msec() - t0])


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
	if _descriptors.has(source):
		_descriptors[state] = _descriptors[source]
	else:
		_descriptors.erase(state)


func has_clip(clip_name: String) -> bool:
	return _clips.has(clip_name)


## Play a clip (looping). Unknown names are ignored, the model keeps what it was doing. A clip whose descriptor
## has a `loop` window plays its intro once (when it has one) and then repeats the window; one without plays
## whole and repeats whole. The change from what was playing is a crossfade.
func play(clip_name: String, loop: bool = true) -> bool:
	if _player == null or not _clips.has(clip_name):
		return false
	var anim: Animation = _clips[clip_name]
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	if _playing != clip_name or not _player.is_playing():
		_begin_crossfade()
		_player.play(clip_name)
		_window = _loop_window(clip_name) if loop else {}
		_enter_window(_player, _window)
	_playing = clip_name
	_after = ""
	return true


## The part of `clip_name` that repeats, from its descriptor: {clip, from (where it starts playing), start, end} in
## seconds, or empty. The intro runs from its start to the loop's; with no intro it starts at the loop. With
## `loop.blend_frames` the window is made seamless (`_seamless_loop`) and `baked` names the clip that repeats.
func _loop_window(clip_name: String) -> Dictionary:
	var d: Dictionary = _descriptors.get(clip_name, {})
	if not (d.get("loop") is Dictionary):
		return {}
	var fps := float(d.get("fps", 30.0))
	var lp: Dictionary = d["loop"]
	var start := float(lp.get("start_frame", 0)) / fps
	var end := float(lp.get("end_frame", 0)) / fps
	var length := (_clips[clip_name] as Animation).length
	end = minf(end, length)
	if end - start < 0.2:
		return {}
	var from := start
	if d.get("intro") is Dictionary:
		from = float((d["intro"] as Dictionary).get("start_frame", 0)) / fps
	var window := {"clip": clip_name, "from": from, "start": start, "end": end}
	var blend := float(lp.get("blend_frames", 0)) / fps
	if blend > 0.0:
		var baked := _seamless_loop(clip_name, start, end, blend)
		if baked != "":
			window["baked"] = baked
	return window


## A pose that is held DRIFTS: Thinking's head is 4 degrees and its arm 3 away from where they were a second ago, in a
## clip with no cycle in it, so repeating frames 43..73 steps by that much every second (the mean over the bones said 0.7
## and hid it; no window of the clip does better than 2). The repeat is made in the data instead: a new clip, the
## window's length, whose last `blend` seconds are the window's own blended toward the frames BEFORE its start (the
## clip at t - length), so its end is exactly its start. It loops by itself. Made once per clip; returns its name.
func _seamless_loop(clip_name: String, start: float, end: float, blend: float) -> String:
	var key := "%s~loop_%.3f_%.3f_%.3f" % [clip_name, start, end, blend]
	if _lib.has_animation(key):
		return key
	var src: Animation = _clips[clip_name]
	var span := end - start
	blend = minf(blend, minf(span, start))  # the frames before the start must exist
	if blend <= 0.0:
		return ""
	var fps := float((_descriptors.get(clip_name, {}) as Dictionary).get("fps", 30.0))
	var steps := int(round(span * fps))
	var loop := Animation.new()
	loop.length = steps / fps
	loop.loop_mode = Animation.LOOP_LINEAR
	for t in src.get_track_count():
		var kind := src.track_get_type(t)
		if kind != Animation.TYPE_ROTATION_3D and kind != Animation.TYPE_POSITION_3D and kind != Animation.TYPE_SCALE_3D:
			continue
		var track := loop.add_track(kind)
		loop.track_set_path(track, src.track_get_path(t))
		loop.track_set_interpolation_type(track, Animation.INTERPOLATION_LINEAR)
		for k in steps:  # the key at `steps` is the key at 0: the loop wraps onto it
			var at := start + k / fps
			var weight := clampf((at - (end - blend)) / blend, 0.0, 1.0)
			weight = weight * weight * (3.0 - 2.0 * weight)
			var time := k / fps
			match kind:
				Animation.TYPE_ROTATION_3D:
					var a: Quaternion = src.rotation_track_interpolate(t, at)
					loop.rotation_track_insert_key(track, time, a.slerp(src.rotation_track_interpolate(t, at - span), weight) if weight > 0.0 else a)
				Animation.TYPE_POSITION_3D:
					var a: Vector3 = src.position_track_interpolate(t, at)
					loop.position_track_insert_key(track, time, a.lerp(src.position_track_interpolate(t, at - span), weight))
				_:
					var a: Vector3 = src.scale_track_interpolate(t, at)
					loop.scale_track_insert_key(track, time, a.lerp(src.scale_track_interpolate(t, at - span), weight))
	_lib.add_animation(key, loop)
	print("[Rift] %s: frames %.0f..%.0f made into a seamless loop (blended over the last %.0f frames)" % [clip_name, start * fps, end * fps, blend * fps])
	return key


## Keep the pose she is in so the next clip can be blended in from it.
func _begin_crossfade() -> void:
	if xfade_seconds <= 0.0 or _last_local.is_empty():
		return
	_from_local = _last_local.duplicate()
	_from_rise = _last_rise
	_xf_left = xfade_seconds


## The skin's descriptor of a clip (what Karada sent beside the file), as the server wrote it.
func set_clip_descriptor(clip_name: String, descriptor: Dictionary) -> void:
	if descriptor.is_empty():
		_descriptors.erase(clip_name)
	else:
		_descriptors[clip_name] = descriptor


func clip_descriptor(clip_name: String) -> Dictionary:
	return _descriptors.get(clip_name, {})


## `upper_body` for a clip that moves only the body above the hips, else "".
func clip_mask(clip_name: String) -> String:
	return str(clip_descriptor(clip_name).get("mask", ""))


## Play `clip_name` as a layer over the base clip: from the hips up it is the one that moves her; the hips and
## legs stay with the base. A crossfade in. False when she has no such clip or no rig to put it on.
func play_over(clip_name: String) -> bool:
	if _player == null or not _clips.has(clip_name) or not _ensure_overlay():
		return false
	if _over_clip == clip_name and _over_player.is_playing():
		return true
	_begin_crossfade()
	(_clips[clip_name] as Animation).loop_mode = Animation.LOOP_LINEAR
	_over_player.play(clip_name)
	_over_window = _loop_window(clip_name)
	_enter_window(_over_player, _over_window)
	_over_clip = clip_name
	return true


## Take the layer off: the base clip is the whole body again, melted in.
func stop_over() -> void:
	if _over_clip == "":
		return
	_begin_crossfade()
	_over_player.stop()
	_over_clip = ""
	_over_window = {}


func overlay() -> String:
	return _over_clip


## The second copy of the animation rig, made the first time a layer is wanted.
func _ensure_overlay() -> bool:
	if _over_skel != null:
		return true
	if _src_root == null:
		return false
	_over_root = _src_root.duplicate() as Node3D
	_over_root.name = "AnimationOverlay"
	add_child(_over_root)
	var skels: Array = _over_root.find_children("*", "Skeleton3D", true, false)
	var players: Array = _over_root.find_children("*", "AnimationPlayer", true, false)
	if skels.is_empty() or players.is_empty():
		_over_root.queue_free()
		_over_root = null
		return false
	_over_skel = skels[0] as Skeleton3D
	_over_player = players[0] as AnimationPlayer
	if _over_player.has_animation_library(""):
		_over_player.remove_animation_library("")
	_over_player.add_animation_library("", _lib)
	return true


## Play a clip once, then `next` (looping): a greeting, then standing again.
func play_then(clip_name: String, next: String) -> bool:
	if not play(clip_name, false):
		return false
	_after = next if _clips.has(next) else ""
	return true


func _on_clip_finished(finished: StringName) -> void:
	clip_finished.emit(String(finished))
	if _after != "" and str(finished) == _playing:
		var next := _after
		_after = ""
		play(next, true)


func playing() -> String:
	return _playing


func clip_length(clip_name: String) -> float:
	return (_clips[clip_name] as Animation).length if _clips.has(clip_name) else 0.0


## Seek (a test, or a still frame): the pose at that time, now, with no crossfade to it.
func seek(seconds: float) -> void:
	if _player != null:
		_player.seek(seconds, true)
		_xf_left = 0.0
		_retarget()


## Bone pairs found in both skeletons: for the tests.
func mapped_bones() -> int:
	return _pairs.size()


func _process(delta: float) -> void:
	_repeat_window(_player, _window)
	if _over_clip != "":
		_repeat_window(_over_player, _over_window)
	_xf_left = maxf(0.0, _xf_left - delta)
	if _playing != "":
		_retarget()
	_apply_gaze(delta)
	if face != null:
		face.call("update", delta)


## A clip that has just started plays from the window's `from` (its intro's start), or, with nothing before the window,
## straight into the seamless loop.
func _enter_window(player: AnimationPlayer, window: Dictionary) -> void:
	if window.is_empty():
		return
	if window.has("baked") and window["from"] >= window["start"]:
		player.play(window["baked"])
		window.clear()  # the loop repeats itself
	elif window["from"] > 0.0:
		player.seek(window["from"], true)


## The intro done, a seamless loop takes over at the window's start (the same pose, so nothing shows); one without
## goes back to the window's start when it reaches its end.
func _repeat_window(player: AnimationPlayer, window: Dictionary) -> void:
	if window.is_empty() or player == null or not player.is_playing():
		return
	var t := player.current_animation_position
	if window.has("baked"):
		if t >= float(window["start"]):
			player.play(window["baked"])
			window.clear()
		return
	if t >= float(window["end"]):
		player.seek(float(window["start"]) + (t - float(window["end"])), true)


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
			_pairs.append({"t": t, "s": s, "depth": _depth(skeleton, t), "upper": _is_upper_body(str(pair[0]))})
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


## Above the hips (the spine up, the arms, the hands, the fingers): what a `mask: upper_body` clip moves.
static func _is_upper_body(vrm_bone: String) -> bool:
	for lower: String in ["Hips", "Leg", "Foot", "Toe"]:
		if vrm_bone.contains(lower):
			return false
	return true


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
	var blend := 1.0
	if _xf_left > 0.0 and xfade_seconds > 0.0:
		var x := 1.0 - _xf_left / xfade_seconds
		blend = x * x * (3.0 - 2.0 * x)
	var layered := _over_clip != "" and _over_skel != null
	for p: Dictionary in _pairs:
		var t: int = p["t"]
		var s: int = p["s"]
		var src: Skeleton3D = _over_skel if layered and p["upper"] else _src_skel
		var src_pose := src.get_bone_global_pose(s).basis.get_rotation_quaternion()
		var src_rest := src.get_bone_global_rest(s).basis.get_rotation_quaternion()
		var delta := _yaw * (src_pose * src_rest.inverse()) * _yaw.inverse()
		var desired := delta * skeleton.get_bone_global_rest(t).basis.get_rotation_quaternion()
		var parent := skeleton.get_bone_parent(t)
		var parent_pose := Quaternion.IDENTITY
		if parent >= 0:
			parent_pose = skeleton.get_bone_global_pose(parent).basis.get_rotation_quaternion()
		var local := (parent_pose.inverse() * desired).normalized()
		if blend < 1.0 and _from_local.has(t):
			local = (_from_local[t] as Quaternion).slerp(local, blend)
		_last_local[t] = local
		skeleton.set_bone_pose_rotation(t, local)
	if not _hips.is_empty():
		var t: int = _hips["t"]
		var s: int = _hips["s"]
		var rise := (_src_skel.get_bone_pose(s).origin.y - _src_skel.get_bone_rest(s).origin.y) * _scale
		if blend < 1.0:
			rise = lerpf(_from_rise, rise, blend)
		_last_rise = rise
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
