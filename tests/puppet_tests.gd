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
	print("[rift-tests] %d cases, %d failed" % [_count, _failed])
	quit(1 if _failed > 0 or _count == 0 else 0)


func _check(ok: bool, what: String) -> void:
	_count += 1
	if not ok:
		_failed += 1
		print("[rift-tests] FAIL: %s" % what)
