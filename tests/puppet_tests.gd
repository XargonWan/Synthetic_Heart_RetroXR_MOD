## The retarget, in numbers: where their hands, feet and head end up against where the animation
## puts its own, relative to the hips. A Mixamo rig faces +Z and a VRoid one -Z, so the answer
## is the animation's offset turned half a circle (x and z flipped) and scaled to their legs.
##
##   SKIN=$HOME/gits/Synthetic_Heart/skins/Rei godot --headless --path RetroXR \
##       --script res://mods/xenu.synth_rift/tests/puppet_tests.gd
##
## No SKIN: nothing to test, which is a failure (a suite that ran nothing is not a pass).
extends SceneTree

const Puppet := preload("res://mods/xenu.synth_rift/scripts/karada_puppet.gd")
## Their proportions are not Mixamo's: arms and legs differ by a few centimetres.
const TOLERANCE := 0.16

var _failed := 0
var _count := 0


func _initialize() -> void:
	var skin := OS.get_environment("SKIN")
	if skin.is_empty():
		print("[rift-tests] no SKIN set")
		quit(1)
		return
	var puppet: Node3D = Puppet.new()
	root.add_child(puppet)
	_check(puppet.load_model(FileAccess.get_file_as_bytes(skin + "/model.vrm")), "the model loads")
	for clip: String in ["idle/Idle.fbx", "greet/Standing Greeting.fbx", "write/Texting While Standing.fbx"]:
		_check(puppet.add_clip(clip.get_file().get_basename(), FileAccess.get_file_as_bytes(skin + "/animations/" + clip)),
			"%s loads" % clip)
	_check(puppet.mapped_bones() >= 50, "52 bones map (%d)" % puppet.mapped_bones())
	_check(puppet.height > 1.5 and puppet.height < 1.8, "they are a person's height (%.2f m)" % puppet.height)

	var tgt: Skeleton3D = puppet.skeleton
	var src: Skeleton3D = puppet._src_skel
	var scale: float = puppet._scale
	var pairs := {
		"left hand": ["J_Bip_L_Hand", "mixamorig_LeftHand"], "right hand": ["J_Bip_R_Hand", "mixamorig_RightHand"],
		"left foot": ["J_Bip_L_Foot", "mixamorig_LeftFoot"], "right foot": ["J_Bip_R_Foot", "mixamorig_RightFoot"],
		"head": ["J_Bip_C_Head", "mixamorig_Head"],
	}
	for clip: String in ["Standing Greeting", "Texting While Standing", "Idle"]:
		puppet.play(clip, true)
		for t: float in [0.4, 1.5, 3.0]:
			puppet.seek(t)
			# The animation has to have MOVED the source, or every number below is rest against rest.
			await process_frame
			puppet.seek(t)
			var th := tgt.get_bone_global_pose(tgt.find_bone("J_Bip_C_Hips")).origin
			var sh := src.get_bone_global_pose(src.find_bone("mixamorig_Hips")).origin
			for part: String in pairs:
				var tp := tgt.get_bone_global_pose(tgt.find_bone(pairs[part][0])).origin - th
				var sp := src.get_bone_global_pose(src.find_bone(pairs[part][1])).origin - sh
				# The animation's offset turned half a circle about UP, then scaled.
				var want := Vector3(-sp.x, sp.y, -sp.z) * scale
				var off := tp.distance_to(want)
				_check(off < TOLERANCE, "%s / %s at %.1f s: %.2f m from where the animation puts it" % [clip, part, t, off])
	# The check that the checks can fail: the greeting really raises a hand away from its rest.
	puppet.play("Standing Greeting", true)
	puppet.seek(1.5)
	await process_frame
	puppet.seek(1.5)
	var travelled := 0.0
	for hand: String in ["mixamorig_LeftHand", "mixamorig_RightHand"]:
		var i := src.find_bone(hand)
		travelled = maxf(travelled, (src.get_bone_global_pose(i).origin - src.get_bone_global_rest(i).origin).length())
	_check(travelled > 0.25, "the greeting moves a hand %.2f m from rest (else these numbers are rest against rest)" % travelled)
	# The skin's turn clips turn them through the hips; the body has to add that much to its heading, so the numbers
	# are what the animation itself does: a left turn is about half a circle to the left, a right one a quarter to the right.
	_check(puppet.add_clip("turn_left", FileAccess.get_file_as_bytes(skin + "/animations/walk/turn_left/Left Turn.fbx")), "Left Turn loads")
	_check(puppet.add_clip("turn_right", FileAccess.get_file_as_bytes(skin + "/animations/walk/turn_right/Right Turn.fbx")), "Right Turn loads")
	var left_end: float = puppet.clip_yaw("turn_left", puppet.clip_length("turn_left"))
	var right_end: float = puppet.clip_yaw("turn_right", puppet.clip_length("turn_right"))
	_check(left_end > 150.0 and left_end < 200.0, "Left Turn turns them to the left, by about half a circle (%.0f deg)" % left_end)
	_check(right_end < -75.0 and right_end > -105.0, "Right Turn turns them to the right, by about a quarter (%.0f deg)" % right_end)
	_check(absf(puppet.clip_yaw("turn_left", 0.0)) < 1.0, "and neither has turned at its first frame")
	var t90: float = puppet.clip_time_for_yaw("turn_left", 90.0)
	_check(t90 > 0.3 and t90 < puppet.clip_length("turn_left") - 0.2 and absf(puppet.clip_yaw("turn_left", t90) - 90.0) < 3.0,
		"a quarter turn to the left is cut off part of the way through its clip (%.2f s of %.2f, %.0f deg)" % [t90, puppet.clip_length("turn_left"), puppet.clip_yaw("turn_left", t90)])
	_check(puppet.clip_time_for_yaw("turn_right", 170.0) == puppet.clip_length("turn_right"), "a turn the clip cannot make runs the whole clip")
	_check(puppet.add_clip("walk", FileAccess.get_file_as_bytes(skin + "/animations/walk/walk/Walking.fbx")), "Walking loads")
	# The hips sway a few degrees through a step; a walk ends facing the way it began.
	_check(absf(puppet.clip_yaw("walk", puppet.clip_length("walk"))) < 5.0, "walking turns nobody (%.1f deg at its end)" % puppet.clip_yaw("walk", puppet.clip_length("walk")))
	_check(puppet.clip_yaw("nothing_of_the_kind", 1.0) == 0.0, "a clip that is not there turns nobody")
	# Two idles: the one that arches them back is not the one they stand in.
	_check(puppet.add_clip("idle__0", FileAccess.get_file_as_bytes(skin + "/animations/idle/Idle.fbx")), "Idle loads")
	_check(puppet.add_clip("idle__1", FileAccess.get_file_as_bytes(skin + "/animations/idle/Idle2.fbx")), "Idle2 loads")
	var lean0: float = await puppet.torso_lean("idle__0")
	var lean1: float = await puppet.torso_lean("idle__1")
	_check(lean0 < -8.0, "Idle arches the torso back (%+.1f deg)" % lean0)
	_check(lean1 > lean0 + 3.0, "Idle2 stands straighter (%+.1f deg)" % lean1)
	var best: String = await puppet.choose_most_upright("idle", ["idle__0", "idle__1"])
	_check(best == "idle__1", "the straighter one is chosen (%s)" % best)
	_check(puppet._clips["idle"] == puppet._clips["idle__1"], "and it is what 'idle' plays")
	# Their gaze: the head turns the rest of the way to a point, within what a neck can do, and lets go.
	puppet.play("idle", true)
	puppet.seek(2.0)
	await process_frame
	puppet.seek(2.0)
	var head: int = tgt.find_bone("J_Bip_C_Head")
	var head_at: Vector3 = tgt.get_bone_global_pose(head).origin
	var target := Vector3(2.0, head_at.y, -2.0)   # forward and to the +X side, 45 degrees
	var to_target := (target - head_at).normalized()
	var before := rad_to_deg(puppet.head_forward().angle_to(to_target))
	puppet.set_gaze(target)
	for i in 6:
		puppet._retarget()
		puppet._apply_gaze(0.2)
	var after := rad_to_deg(puppet.head_forward().angle_to(to_target))
	_check(before > 20.0, "without it their head is well off the point (%.0f deg)" % before)
	_check(after < 8.0, "with it their head points at it (%.0f deg)" % after)
	_check(puppet.gaze_weight() > 0.99, "fully eased in")
	# A point behind them: the neck stops where a neck stops, it does not wring.
	puppet.set_gaze(Vector3(0.0, head_at.y, 3.0))
	for i in 6:
		puppet._retarget()
		puppet._apply_gaze(0.2)
	var f: Vector3 = puppet.head_forward()
	var yaw := rad_to_deg(absf(atan2(f.x, -f.z)))
	_check(yaw < 80.0, "a point behind their turns their head %.0f deg, not 180" % yaw)
	# Let go: they ease back to what the clip does.
	puppet.set_gaze(null)
	for i in 30:
		puppet._retarget()
		puppet._apply_gaze(0.1)
	_check(puppet.gaze_weight() < 0.01, "and it lets go (%.3f)" % puppet.gaze_weight())
	_face_cases(puppet, skin)
	print("[rift-tests] %d cases, %d failed" % [_count, _failed])
	quit(1 if _failed > 0 or _count == 0 else 0)


func _check(ok: bool, what: String) -> void:
	_count += 1
	if not ok:
		_failed += 1
		print("[rift-tests] FAIL: %s" % what)


## Their face is what the WebUI avatar's is: the model's own expressions, layered, with a blink of their own.
func _face_cases(puppet: Node3D, skin: String) -> void:
	var face: RefCounted = puppet.face
	_check(face != null and face.expression_names().size() >= 10, "the model's expressions were read (%d)" % (face.expression_names().size() if face != null else 0))
	for n: String in ["blink", "joy", "a", "sorrow"]:
		_check(face.has_expression(n), "VRM 0.x preset '%s' is there" % n)
	# The VRM 1.0 names the persona map uses reach the 0.x presets.
	for pair: Array in [["happy", "joy"], ["aa", "a"], ["sad", "sorrow"], ["blink", "blink"]]:
		_check(face.has_expression(pair[0]), "'%s' is understood" % pair[0])
	var persona: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(skin + "/persona.json"))
	puppet.set_persona(persona)
	_check(not (face.blendshape_map as Dictionary).is_empty(), "their persona's blendshape map is in")

	face.auto_blink = true
	face.set_face_values({})
	face.update(0.016)
	_check(_blend(face, "blink") < 0.01, "eyes open to begin with (%.2f)" % _blend(face, "blink"))
	face.blink_now()
	var peak := 0.0
	for i in 30:
		face.update(0.016)
		peak = maxf(peak, _blend(face, "blink"))
	_check(peak > 0.99, "they blink: the lids close on the mesh itself (%.2f)" % peak)
	for i in 30:
		face.update(0.016)
	_check(_blend(face, "blink") < 0.01, "and open again (%.2f)" % _blend(face, "blink"))

	# A logical name goes through the map: mouth_smile -> happy -> joy.
	face.set_face_values({"mouth_smile": 0.8})
	face.update(0.016)
	_check(absf(_blend(face, "joy") - 0.8) < 0.01, "an emotion from Karada reaches the face (%.2f)" % _blend(face, "joy"))
	face.set_face_values({})
	face.update(0.016)
	_check(_blend(face, "joy") < 0.01, "and lets go when it is dropped")
	# Something else driving the blink: the automatic one stays out of it.
	# Karada's face frame is an EMOTION state: `happy 0.65` is the persona's soft smile, not the whole joy face at 65%
	# (eyes shut, mouth wide open: the dopey grin of the first sessions). Control: a name the persona does not know
	# is still taken as a VRM expression, so the two readings are told apart.
	face.set_face_values({"happy": 0.65, "relaxed": 0.5, "love": 0.01, "neutral": 0.3, "devotion": 0.28})
	face.update(0.016)
	_check(_blend(face, "joy") > 0.05 and _blend(face, "joy") < 0.25, "happy 0.65 is a gentle smile (joy %.2f), not 0.65" % _blend(face, "joy"))
	_check(_blend(face, "fun") < 0.01, "relaxed is not the model's `fun` face (%.2f)" % _blend(face, "fun"))
	face.set_face_values({"joy": 0.65})
	face.update(0.016)
	_check(absf(_blend(face, "joy") - 0.65) < 0.01, "a name the persona has no emotion for still reaches the model as it is (%.2f)" % _blend(face, "joy"))
	face.set_face_values({})
	face.update(0.016)

	face.set_face_values({"eyes_closed": 1.0})
	face.blink_now()
	face.update(0.016)
	_check(absf(_blend(face, "blink") - 1.0) < 0.01, "their eyes stay shut while the animation closes them")
	face.set_face_values({})
	# The overlay replaces; clear lets go.
	face.set_overlay({"mouth_frown": 0.5})
	face.update(0.016)
	_check(absf(_blend(face, "sorrow") - 0.5) < 0.01, "an expression overlay is drawn")
	face.set_overlay(null)
	face.update(0.016)
	_check(_blend(face, "sorrow") < 0.01, "and cleared")
	# The mouth follows how loud they are, capped like the WebUI's.
	for i in 40:
		face.speak_level(0.5)
		face.update(0.016)
	_check(_blend(face, "a") > 0.3 and _blend(face, "a") <= 0.7001, "their mouth opens as they speak (%.2f)" % _blend(face, "a"))
	for i in 60:
		face.speak_level(0.0)
		face.update(0.016)
	_check(_blend(face, "a") < 0.01, "and closes when they stop (%.2f)" % _blend(face, "a"))
	# A descriptor's frame window: think closes the eyes from a frame on.
	face.set_descriptor({"fps": 30, "expressions": [{"start_frame": 0, "end_frame": 1000, "targets": {"mouth_smile": 0.6}}]})
	face.update(0.016)
	_check(absf(_blend(face, "joy") - 0.6) < 0.01, "a descriptor's expression is drawn inside its window")
	face.set_descriptor({"fps": 30, "expressions": [{"start_frame": 5000, "targets": {"mouth_smile": 0.6}}]})
	face.update(0.016)
	_check(_blend(face, "joy") < 0.01, "and not before it")
	face.set_descriptor({})


## What the mesh itself has for this expression's first bind (the picture, not the bookkeeping).
func _blend(face: RefCounted, expression: String) -> float:
	var key: String = face._resolve(expression)
	if key == "":
		return -1.0
	var bind: Dictionary = (face._binds[key] as Array)[0]
	var mi: MeshInstance3D = bind["mi"]
	return mi.get_blend_shape_value(int(bind["idx"])) / float(bind["w"])
