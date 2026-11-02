## Numbers for a posture: how each part of the spine and the legs leans, in the side view, in the
## animation's own skeleton and in hers, at rest and posed. Answers "why is she arched?".
##
##   SKIN=$HOME/gits/Synthetic_Heart-retroxr/skins/Rei CLIP="idle/Idle.fbx" godot --headless --path RetroXR \
##       --script res://mods/xenu.synth_rift/tests/posture_probe.gd
extends SceneTree

const Puppet := preload("res://mods/xenu.synth_rift/scripts/karada_puppet.gd")


func _initialize() -> void:
	var skin := OS.get_environment("SKIN")
	var clip := OS.get_environment("CLIP")
	var puppet: Node3D = Puppet.new()
	root.add_child(puppet)
	puppet.load_model(FileAccess.get_file_as_bytes(skin + "/model.vrm"))
	puppet.add_clip("c", FileAccess.get_file_as_bytes(skin + "/animations/" + clip))
	var tgt: Skeleton3D = puppet.skeleton
	var src: Skeleton3D = puppet._src_skel
	# Segments of the spine and head, hips to head top; angle from vertical in the side plane,
	# + leaning BACK (the way an arch goes), seen with the body facing its own front.
	var chains := {
		"src": [src, ["mixamorig_Hips", "mixamorig_Spine", "mixamorig_Spine1", "mixamorig_Spine2", "mixamorig_Neck", "mixamorig_Head", "mixamorig_HeadTop_End"], -1.0],
		"her": [tgt, ["J_Bip_C_Hips", "J_Bip_C_Spine", "J_Bip_C_Chest", "J_Bip_C_UpperChest", "J_Bip_C_Neck", "J_Bip_C_Head", "J_Adj_C_FaceEye"], 1.0],
	}
	# The whole torso as one line, hips to neck, against the vertical: positive leans FORWARD.
	var hips_s := src.find_bone("mixamorig_Hips")
	var neck_s := src.find_bone("mixamorig_Neck")
	var head_s := src.find_bone("mixamorig_Head")
	var spine2_s := src.find_bone("mixamorig_Spine2")
	puppet.play("c", true)
	var lean_sum := 0.0
	var worst := 0.0
	var n := 0
	for k in 24:
		var tt: float = puppet.clip_length("c") * float(k) / 24.0
		puppet.seek(tt)
		await process_frame
		puppet.seek(tt)
		var d := src.get_bone_global_pose(neck_s).origin - src.get_bone_global_pose(hips_s).origin
		var lean := rad_to_deg(atan2(d.z, d.y))
		var dh := src.get_bone_global_pose(head_s).origin - src.get_bone_global_pose(neck_s).origin
		var head_lean := rad_to_deg(atan2(dh.z, dh.y))
		lean_sum += lean
		worst = minf(worst, lean)
		n += 1
	print("[probe] %s: torso (hips->neck) mean lean %+.1f deg (negative = arched BACK), most back %+.1f, over %d samples" % [clip, lean_sum / n, worst, n])
	for t: float in [0.0, 4.0, 8.0]:
		puppet.seek(t)
		await process_frame
		puppet.seek(t)
		for who: String in chains:
			var sk: Skeleton3D = chains[who][0]
			var names: Array = chains[who][1]
			var facing: float = chains[who][2]
			var line := PackedStringArray()
			var total := 0.0
			for i in names.size() - 1:
				var a := sk.find_bone(names[i])
				var b := sk.find_bone(names[i + 1])
				if a < 0 or b < 0:
					line.append("?")
					continue
				var d := sk.get_bone_global_pose(b).origin - sk.get_bone_global_pose(a).origin
				# The body's front is +Z for the animation and -Z for her: lean-back is toward -front.
				var lean := rad_to_deg(atan2(-d.z * facing, d.y))
				total += lean
				line.append("%+.1f" % lean)
			print("[probe] t=%.0f %s segment lean back (deg): %s" % [t, who, " ".join(line)])
	# Rest, for her.
	puppet.play("c", false)
	var rest := PackedStringArray()
	var names2: Array = chains["her"][1]
	for i in names2.size() - 1:
		var a := tgt.find_bone(names2[i])
		var b := tgt.find_bone(names2[i + 1])
		var d := tgt.get_bone_global_rest(b).origin - tgt.get_bone_global_rest(a).origin
		rest.append("%+.1f" % rad_to_deg(atan2(-d.z, d.y)))
	print("[probe] her REST segment lean back (deg): %s" % " ".join(rest))
	var rest_src := PackedStringArray()
	var names3: Array = chains["src"][1]
	for i in names3.size() - 1:
		var a := src.find_bone(names3[i])
		var b := src.find_bone(names3[i + 1])
		var d := src.get_bone_global_rest(b).origin - src.get_bone_global_rest(a).origin
		rest_src.append("%+.1f" % rad_to_deg(atan2(d.z, d.y)))
	print("[probe] src REST segment lean back (deg): %s" % " ".join(rest_src))
	quit(0)
