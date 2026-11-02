## Can Godot load a Karada skin AT RUN TIME? A VRM model, then an FBX animation, and can the
## animation drive the model? Nothing here is the game's; it answers a question.
##
##   VRM=/path/model.vrm FBX=/path/anim.fbx godot --headless --path RetroXR --script res://mods/xenu.synth_rift/tests/vrm_probe.gd
extends SceneTree


func _initialize() -> void:
	var vrm_path := OS.get_environment("VRM")
	var fbx_path := OS.get_environment("FBX")
	print("[probe] classes: GLTFDocument=%s FBXDocument=%s RetargetModifier3D=%s BoneMap=%s SkeletonProfileHumanoid=%s" % [
		ClassDB.class_exists("GLTFDocument"), ClassDB.class_exists("FBXDocument"),
		ClassDB.class_exists("RetargetModifier3D"), ClassDB.class_exists("BoneMap"),
		ClassDB.class_exists("SkeletonProfileHumanoid")])
	var t0 := Time.get_ticks_msec()
	var model := _load(vrm_path, "VRM")
	print("[probe] vrm loaded in %d ms" % (Time.get_ticks_msec() - t0))
	if model != null:
		_describe(model, "vrm")
	if not fbx_path.is_empty():
		t0 = Time.get_ticks_msec()
		var anim_scene := _load(fbx_path, "FBX")
		print("[probe] fbx loaded in %d ms" % (Time.get_ticks_msec() - t0))
		if anim_scene != null:
			_describe(anim_scene, "fbx")
			for ap: Node in anim_scene.find_children("*", "AnimationPlayer", true, false):
				for a: String in (ap as AnimationPlayer).get_animation_list():
					var anim := (ap as AnimationPlayer).get_animation(a)
					print("[probe] fbx animation '%s' %.2f s, %d tracks, first: %s" % [a, anim.length, anim.get_track_count(),
						str(anim.track_get_path(0)) if anim.get_track_count() > 0 else "-"])
	quit(0)


func _load(path: String, kind: String) -> Node:
	if path.is_empty() or not FileAccess.file_exists(path):
		print("[probe] %s: no file '%s'" % [kind, path])
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	var doc: Object = ClassDB.instantiate("FBXDocument" if kind == "FBX" else "GLTFDocument")
	if doc == null:
		print("[probe] %s: no document class" % kind)
		return null
	var state: Object = ClassDB.instantiate("FBXState" if kind == "FBX" else "GLTFState")
	var err: int = doc.call("append_from_buffer", bytes, "", state)
	print("[probe] %s append_from_buffer -> %s (%d bytes)" % [kind, error_string(err), bytes.size()])
	if err != OK and kind == "FBX":
		# FBX is read through ufbx, which wants a file (or a base path to resolve from).
		state = ClassDB.instantiate("FBXState")
		err = doc.call("append_from_file", path, state)
		print("[probe] FBX append_from_file -> %s" % error_string(err))
		if err != OK:
			state = ClassDB.instantiate("FBXState")
			err = doc.call("append_from_buffer", bytes, path.get_base_dir(), state)
			print("[probe] FBX append_from_buffer with a base path -> %s" % error_string(err))
	if err != OK:
		return null
	return doc.call("generate_scene", state) as Node


func _describe(root: Node, label: String) -> void:
	var skeletons := root.find_children("*", "Skeleton3D", true, false)
	var meshes := root.find_children("*", "MeshInstance3D", true, false)
	print("[probe] %s: root=%s, %d skeletons, %d meshes" % [label, root.get_class(), skeletons.size(), meshes.size()])
	for sk: Node in skeletons:
		var skel := sk as Skeleton3D
		var names: PackedStringArray = []
		for i in mini(skel.get_bone_count(), 8):
			names.append(skel.get_bone_name(i))
		print("[probe] %s skeleton: %d bones, first: %s" % [label, skel.get_bone_count(), ", ".join(names)])
	var top := -INF
	var bottom := INF
	for m: Node in meshes:
		var mi := m as MeshInstance3D
		var box := mi.global_transform * mi.get_aabb()
		top = maxf(top, box.end.y)
		bottom = minf(bottom, box.position.y)
	if not meshes.is_empty():
		print("[probe] %s height %.2f m (%.2f .. %.2f)" % [label, top - bottom, bottom, top])
