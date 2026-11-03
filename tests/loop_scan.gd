## Where a clip can repeat: for a Mixamo .fbx, its speed profile (a held pose is where it nearly stands still), how far
## its last frame is from its first, and the windows whose two ends are closest, by mean angle per bone over all
## the rotation tracks, and by the WORST bone (what the eye catches: a held pose drifts, and a window whose mean is
## 0.7 degrees can still turn a head by 4). It is how a descriptor's `loop` window is chosen: by measuring, not by eye.
## When no window closes well enough, the descriptor asks the client to make the repeat (`loop.blend_frames`).
##
##   godot --headless --path RetroXR --script res://mods/xenu.synth_rift/tests/loop_scan.gd -- <clip.fbx> [min frames]
##
## `min frames` (default 24) is the shortest window offered. Add `--within=A,B` to look only between frames A and B
## (the centre of a clip: its intro walks into the pose and its outro out of it).
extends SceneTree

const FPS := 30.0


func _init() -> void:
	var path := ""
	var min_len := 24
	var lo_frame := 0
	var hi_frame := 1 << 30
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--within="):
			var ab := arg.trim_prefix("--within=").split(",")
			lo_frame = int(ab[0])
			hi_frame = int(ab[1])
		elif path.is_empty():
			path = arg
		else:
			min_len = int(arg)
	if path.is_empty():
		print("[scan] usage: -- <clip.fbx> [min frames] [--within=A,B]")
		quit(2)
		return
	var doc := FBXDocument.new()
	var state := FBXState.new()
	if doc.append_from_buffer(FileAccess.get_file_as_bytes(path), "", state) != OK:
		print("[scan] %s did not load" % path)
		quit(1)
		return
	var scene := doc.generate_scene(state) as Node3D
	var players: Array = scene.find_children("*", "AnimationPlayer", true, false)
	var anim: Animation = (players[0] as AnimationPlayer).get_animation((players[0] as AnimationPlayer).get_animation_list()[0])
	var frames := int(round(anim.length * FPS)) + 1
	var tracks: Array = []
	for t in anim.get_track_count():
		if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			tracks.append(t)
	var q: Array = []
	for f in frames:
		var row: Array = []
		for t: int in tracks:
			row.append(anim.rotation_track_interpolate(t, minf(f / FPS, anim.length)))
		q.append(row)
	print("[scan] %s: %.2f s, %d frames, %d rotation tracks" % [path.get_file(), anim.length, frames, tracks.size()])
	var speed := ""
	for f in range(0, frames - 1, 4):
		speed += "%d:%.2f " % [f, _dist(q, f, f + 1)]
	print("[scan] speed, deg/bone/frame: %s" % speed)
	print("[scan] first frame vs last: %.2f deg/bone (a cycle when near 0)" % _dist(q, 0, frames - 1))
	var windows: Array = []
	for a in range(maxi(lo_frame, 0), frames):
		for b in range(a + min_len, mini(frames, hi_frame + 1)):
			windows.append([_worst(q, a, b), a, b, _dist(q, a, b)])
	windows.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	for i in mini(8, windows.size()):
		print("[scan] window %d..%d (%.2f s): worst bone %.2f deg apart (mean %.2f)" % [windows[i][1], windows[i][2], (windows[i][2] - windows[i][1]) / FPS, windows[i][0], windows[i][3]])
	quit(0)


## Mean angle between two frames, in degrees per bone.
func _dist(q: Array, a: int, b: int) -> float:
	var sum := 0.0
	for i in (q[a] as Array).size():
		sum += rad_to_deg((q[a][i] as Quaternion).angle_to(q[b][i]))
	return sum / maxi((q[a] as Array).size(), 1)


## The biggest angle between two frames over the bones, in degrees.
func _worst(q: Array, a: int, b: int) -> float:
	var worst := 0.0
	for i in (q[a] as Array).size():
		worst = maxf(worst, rad_to_deg((q[a][i] as Quaternion).angle_to(q[b][i])))
	return worst
