## The retarget, in numbers: where her hands, feet and head end up against where the animation
## puts its own, relative to the hips. A Mixamo rig faces +Z and a VRoid one -Z, so the answer
## is the animation's offset turned half a circle (x and z flipped) and scaled to her legs.
##
##   SKIN=$HOME/gits/Synthetic_Heart/skins/Rei godot --headless --path RetroXR \
##       --script res://mods/xenu.synth_rift/tests/puppet_tests.gd
##
## No SKIN: nothing to test, which is a failure (a suite that ran nothing is not a pass).
extends SceneTree

const Puppet := preload("res://mods/xenu.synth_rift/scripts/karada_puppet.gd")
## Her proportions are not Mixamo's: arms and legs differ by a few centimetres.
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
	_check(puppet.height > 1.5 and puppet.height < 1.8, "she is a person's height (%.2f m)" % puppet.height)

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
	# Two idles: the one that arches her back is not the one she stands in.
	_check(puppet.add_clip("idle__0", FileAccess.get_file_as_bytes(skin + "/animations/idle/Idle.fbx")), "Idle loads")
	_check(puppet.add_clip("idle__1", FileAccess.get_file_as_bytes(skin + "/animations/idle/Idle2.fbx")), "Idle2 loads")
	var lean0: float = await puppet.torso_lean("idle__0")
	var lean1: float = await puppet.torso_lean("idle__1")
	_check(lean0 < -8.0, "Idle arches the torso back (%+.1f deg)" % lean0)
	_check(lean1 > lean0 + 3.0, "Idle2 stands straighter (%+.1f deg)" % lean1)
	var best: String = await puppet.choose_most_upright("idle", ["idle__0", "idle__1"])
	_check(best == "idle__1", "the straighter one is chosen (%s)" % best)
	_check(puppet._clips["idle"] == puppet._clips["idle__1"], "and it is what 'idle' plays")
	# Her gaze: the head turns the rest of the way to a point, within what a neck can do, and lets go.
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
	_check(before > 20.0, "without it her head is well off the point (%.0f deg)" % before)
	_check(after < 8.0, "with it her head points at it (%.0f deg)" % after)
	_check(puppet.gaze_weight() > 0.99, "fully eased in")
	# A point behind her: the neck stops where a neck stops, it does not wring.
	puppet.set_gaze(Vector3(0.0, head_at.y, 3.0))
	for i in 6:
		puppet._retarget()
		puppet._apply_gaze(0.2)
	var f: Vector3 = puppet.head_forward()
	var yaw := rad_to_deg(absf(atan2(f.x, -f.z)))
	_check(yaw < 80.0, "a point behind her turns her head %.0f deg, not 180" % yaw)
	# Let go: she eases back to what the clip does.
	puppet.set_gaze(null)
	for i in 30:
		puppet._retarget()
		puppet._apply_gaze(0.1)
	_check(puppet.gaze_weight() < 0.01, "and it lets go (%.3f)" % puppet.gaze_weight())
	print("[rift-tests] %d cases, %d failed" % [_count, _failed])
	quit(1 if _failed > 0 or _count == 0 else 0)


func _check(ok: bool, what: String) -> void:
	_count += 1
	if not ok:
		_failed += 1
		print("[rift-tests] FAIL: %s" % what)
