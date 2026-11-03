## Crossfade, the descriptor's loop window and the upper-body layer, on the real skin's clips, with no server
## and no frames to wait for: the puppet is stepped by hand.
##
##   SKIN=$HOME/gits/Synthetic_Heart/skins/Rei godot --headless --path RetroXR \
##       res://mods/xenu.synth_rift/tests/motion_layers_probe.tscn
##
## Every check has a control that must fail: the thinking window of the OLD descriptor (49..79) jumps, the same
## change with no crossfade jumps, a clip played as the base moves the legs the layer must not touch.
extends Node

const Puppet := preload("res://mods/xenu.synth_rift/scripts/karada_puppet.gd")
const Body := preload("res://mods/xenu.synth_rift/scripts/synth_body.gd")
const STEP := 1.0 / 60.0

var _failed := 0
var _count := 0
var _skin := ""
var _walk_done := false


func _ready() -> void:
	_skin = OS.get_environment("SKIN")
	if _skin.is_empty():
		print("[probe] no SKIN set")
		get_tree().quit(1)
		return
	_loop_window()
	_crossfade()
	_layer()
	await _body()
	print("[probe] done, %d cases, %d failed" % [_count, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


# ── helpers ──────────────────────────────────────────────────────────────────

func _puppet(clips: Dictionary) -> Node3D:
	var puppet: Node3D = Puppet.new()
	add_child(puppet)
	if not puppet.load_model(FileAccess.get_file_as_bytes(_skin + "/model.vrm"), false):
		print("[probe] the model did not load")
	for name: String in clips:
		_load(puppet, name, clips[name])
	puppet.set_process(false)
	return puppet


func _load(puppet: Node3D, clip_name: String, rel: String) -> void:
	puppet.add_clip(clip_name, FileAccess.get_file_as_bytes(_skin + "/animations/" + rel))
	var d := FileAccess.get_file_as_string(_skin + "/animations/" + rel + ".json")
	if not d.is_empty():
		puppet.set_clip_descriptor(clip_name, JSON.parse_string(d))


## One frame of the puppet: the players move, then it retargets.
func _step(puppet: Node3D, seconds: float = STEP) -> void:
	puppet._player.advance(seconds)
	if puppet._over_player != null and puppet._over_clip != "":
		puppet._over_player.advance(seconds)
	puppet._process(seconds)


func _run(puppet: Node3D, seconds: float) -> void:
	for i in int(seconds / STEP):
		_step(puppet)


func _pose(puppet: Node3D) -> Dictionary:
	var out := {}
	for p: Dictionary in puppet._pairs:
		out[puppet.skeleton.get_bone_name(p["t"])] = puppet.skeleton.get_bone_pose_rotation(p["t"])
	return out


## Mean angle between two poses, in degrees, over the bones whose name contains one of `parts` (all when empty).
func _diff(a: Dictionary, b: Dictionary, parts: Array = []) -> float:
	var sum := 0.0
	var n := 0
	for bone: String in a:
		var keep := parts.is_empty()
		for part: String in parts:
			if bone.contains(part):
				keep = true
		if keep:
			sum += rad_to_deg((a[bone] as Quaternion).angle_to(b[bone]))
			n += 1
	return sum / maxi(n, 1)


# ── the loop window ──────────────────────────────────────────────────────────

## The biggest turn of any one bone between two poses, in degrees: what the eye catches. The mean over the bones
## said 0.7 for a repeat that moved her head 4 (a held pose drifts), so the repeat is judged by this.
func _worst(a: Dictionary, b: Dictionary) -> float:
	var worst := 0.0
	for bone: String in a:
		worst = maxf(worst, rad_to_deg((a[bone] as Quaternion).angle_to(b[bone])))
	return worst


## Run a puppet that has `think` for `seconds` and return the biggest one-frame step of any bone once the intro is
## over (the pose after the intro is where the repeats start) and how many times the loop went round.
func _loop_run(puppet: Node3D, seconds: float) -> Dictionary:
	puppet.xfade_seconds = 0.0
	puppet.play("think")
	var w: Dictionary = puppet._window
	var start: float = w["start"]
	var worst := 0.0
	var wraps := 0
	var armed := false
	var last := _pose(puppet)
	var last_t := 0.0
	for i in int(seconds / STEP):
		_step(puppet)
		var now := _pose(puppet)
		var t: float = puppet._player.current_animation_position
		var name := String(puppet._player.current_animation)
		var in_loop := name.contains("~loop") or t >= start
		if in_loop:
			if armed:
				var step := _worst(last, now)
				if step > 0.5 and OS.get_environment("VERBOSE") != "":
					print("[probe] step %.2f deg at frame %d, %s t=%.3f" % [step, i, name, t])
				worst = maxf(worst, step)
				if t < last_t - 0.1:
					wraps += 1
			armed = true
		last = now
		last_t = t
	return {"worst": worst, "wraps": wraps}


func _loop_window() -> void:
	var puppet := _puppet({"think": "think/Thinking.fbx"})
	puppet.xfade_seconds = 0.0
	puppet.play("think")
	var w: Dictionary = puppet._window
	_check(not w.is_empty() and is_equal_approx(w["start"], 54.0 / 30.0) and is_equal_approx(w["end"], 74.0 / 30.0),
			"thinking repeats frames 54..74 of its clip (%s)" % str(w))
	_check(w.has("baked"), "and the repeat is a clip made for it (the window's own end blended toward what came before its start)")
	var run := _loop_run(puppet, 8.0)
	_check(String(puppet._player.current_animation).contains("~loop"), "after the intro the made loop plays (%s)" % puppet._player.current_animation)
	_check(run["wraps"] >= 6, "8 s is several turns of it (%d)" % run["wraps"])
	_check(run["worst"] < 0.4, "and no bone moves more than %.2f deg in a frame, the wrap included" % run["worst"])
	var span: float = puppet._player.current_animation_length
	_check(absf(span - 20.0 / 30.0) < 0.05, "it is the window's length (%.2f s)" % span)

	# Control: the same window cut, with no blend. Its two ends are a drifted pose apart.
	var cut := _puppet({"think": "think/Thinking.fbx"})
	var d: Dictionary = (cut.clip_descriptor("think") as Dictionary).duplicate(true)
	d["loop"].erase("blend_frames")
	cut.set_clip_descriptor("think", d)
	var cut_run := _loop_run(cut, 8.0)
	_check(cut_run["wraps"] >= 6, "control: the cut loop goes round too (%d)" % cut_run["wraps"])
	_check(cut_run["worst"] > 1.5, "control: with no blend a bone steps %.2f deg at the wrap" % cut_run["worst"])

	# Control: the descriptor this replaced (frames 49..79, ending with the outro under way).
	var old := _puppet({"think": "think/Thinking.fbx"})
	old.set_clip_descriptor("think", {"fps": 30, "intro": {"start_frame": 0, "end_frame": 49},
			"loop": {"start_frame": 49, "end_frame": 79}, "outro": {"start_frame": 79, "end_frame": 126}})
	var old_run := _loop_run(old, 8.0)
	_check(old_run["worst"] > 6.0, "control: the old 49..79 window steps %.2f deg at the wrap" % old_run["worst"])

	# No descriptor, no window: the whole clip repeats.
	var plain := _puppet({"think": "think/Thinking.fbx"})
	plain.set_clip_descriptor("think", {})
	plain.play("think")
	_check(plain._window.is_empty(), "a clip with no loop window repeats whole")
	for p: Node in [puppet, cut, old, plain]:
		p.queue_free()


# ── crossfade ────────────────────────────────────────────────────────────────

func _crossfade() -> void:
	var puppet := _puppet({"idle": "idle/Idle2.fbx", "walk": "walk/Walking.fbx"})
	puppet.play("idle")
	_run(puppet, 0.5)
	var before := _pose(puppet)
	puppet.play("walk")
	_step(puppet)
	var first := _pose(puppet)
	_run(puppet, puppet.xfade_seconds * 0.5)
	var halfway := _pose(puppet)
	_run(puppet, puppet.xfade_seconds)
	var done := _pose(puppet)
	var jump := _diff(before, first)
	var mid_from := _diff(before, halfway)
	var mid_to := _diff(halfway, done)
	_check(jump < 2.0, "idle to walk: the first frame is where she was (%.2f deg/bone away)" % jump)
	_check(mid_from > 3.0 and mid_to > 3.0, "halfway she is between the two (%.1f from idle, %.1f from walk)" % [mid_from, mid_to])
	_check(_diff(before, done) > 8.0, "and then she walks (%.1f deg/bone from the idle)" % _diff(before, done))

	# Control: with no crossfade the same change is a cut.
	var hard := _puppet({"idle": "idle/Idle2.fbx", "walk": "walk/Walking.fbx"})
	hard.xfade_seconds = 0.0
	hard.play("idle")
	_run(hard, 0.5)
	var h_before := _pose(hard)
	hard.play("walk")
	_step(hard)
	var h_jump := _diff(h_before, _pose(hard))
	_check(h_jump > 8.0 and h_jump > jump * 4.0, "control: with no crossfade it is a cut (%.1f deg/bone)" % h_jump)

	# A change in the middle of a crossfade carries on from where she is, not from where she was.
	puppet.play("idle")
	_step(puppet)
	puppet.play("walk")
	_run(puppet, 0.1)
	var b := _pose(puppet)
	puppet.play("idle")
	_step(puppet)
	_check(_diff(b, _pose(puppet)) < 2.0, "turning back mid-fade does not jump (%.2f deg/bone)" % _diff(b, _pose(puppet)))
	puppet.queue_free()
	hard.queue_free()


# ── the upper-body layer ─────────────────────────────────────────────────────

func _layer() -> void:
	var clips := {"idle": "idle/Idle2.fbx", "gaming": "gaming/Gaming-sitting.fbx", "sit": "sit/Sitting Idle.fbx"}
	var puppet := _puppet(clips)
	puppet.xfade_seconds = 0.0
	_check(puppet.clip_mask("gaming") == "upper_body", "her skin says the gaming clip is for the upper body")
	puppet.play("idle")
	_run(puppet, 1.0)
	var idle_pose := _pose(puppet)
	var hips_y: float = puppet.skeleton.get_bone_pose_position(puppet._hips["t"]).y
	_check(puppet.play_over("gaming"), "the gaming clip goes on as a layer")
	_run(puppet, 1.0)
	var layered := _pose(puppet)
	var legs := ["UpperLeg", "LowerLeg", "Foot", "ToeBase", "Hips"]
	_check(puppet.overlay() == "gaming" and puppet.playing() == "idle", "the base is still standing (%s under %s)" % [puppet.playing(), puppet.overlay()])
	var legs_moved := _diff(idle_pose, layered, legs)
	var arms_moved := _diff(idle_pose, layered, ["UpperArm", "LowerArm", "Hand", "Spine", "Chest"])
	_check(arms_moved > 5.0, "the arms and the back do what the game clip says (%.1f deg/bone from standing)" % arms_moved)
	_check(legs_moved < 3.0, "the legs go on doing what standing does (%.2f deg/bone)" % legs_moved)
	_check(absf(puppet.skeleton.get_bone_pose_position(puppet._hips["t"]).y - hips_y) < 0.02, "and she does not sink as she would sitting (hips y unchanged)")

	# Control: the same clip as the BASE is a seated body and the legs go.
	var base := _puppet(clips)
	base.xfade_seconds = 0.0
	base.play("idle")
	_run(base, 1.0)
	var standing := _pose(base)
	base.play("gaming")
	_run(base, 1.0)
	var seated_legs := _diff(standing, _pose(base), legs)
	_check(seated_legs > 20.0, "control: played as the base it bends the legs (%.1f deg/bone)" % seated_legs)

	# The layer comes off: standing again.
	puppet.stop_over()
	_run(puppet, 1.0)
	_check(_diff(idle_pose, _pose(puppet), ["UpperArm", "LowerArm", "Hand"]) < 8.0 and puppet.overlay() == "", "taking the layer off gives the arms back to the base")

	# A layer over another base: sitting, the legs stay seated.
	puppet.play("sit")
	_run(puppet, 1.0)
	var sat := _pose(puppet)
	puppet.play_over("gaming")
	_run(puppet, 1.0)
	_check(_diff(sat, _pose(puppet), legs) < 3.0, "over a seated base the legs stay seated (%.2f)" % _diff(sat, _pose(puppet), legs))
	puppet.queue_free()
	base.queue_free()


# ── what the body does with Karada's states ─────────────────────────────────

func _body() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)
	var body: CharacterBody3D = Body.new()
	add_child(body)
	var puppet: Node3D = Puppet.new()
	add_child(puppet)
	puppet.load_model(FileAccess.get_file_as_bytes(_skin + "/model.vrm"), false)
	for pair: Array in [["idle", "idle/Idle2.fbx"], ["greet", "greet/Standing Greeting.fbx"], ["walk", "walk/Walking.fbx"],
			["sit", "sit/Sitting Idle.fbx"], ["gaming", "gaming/Gaming-sitting.fbx"], ["crouch", "crouch/Crouching Idle.fbx"],
			["crouch_post", "crouch/Crouch To Stand.fbx"], ["think", "think/Thinking.fbx"]]:
		_load(puppet, pair[0], pair[1])
	body.attach_puppet(puppet)
	await get_tree().process_frame

	body.set_karada_state("sit")
	_check(puppet.playing() == "sit" and body.layer() == "", "sit: she sits (%s)" % puppet.playing())
	body.set_karada_state("crouch")
	_check(puppet.playing() == "crouch", "crouch: she crouches (%s)" % puppet.playing())
	body.set_karada_state("idle")
	_check(puppet.playing() == "crouch_post" and body.is_busy(), "out of a crouch she stands up first (%s)" % puppet.playing())
	puppet.clip_finished.emit("crouch_post")
	_check(puppet.playing() == "idle" and not body.is_busy(), "and then stands (%s)" % puppet.playing())

	body.set_karada_state("gaming")
	_check(puppet.playing() == "idle" and body.layer() == "gaming" and puppet.overlay() == "gaming",
			"gaming: she stands and her hands play (%s, layer %s)" % [puppet.playing(), body.layer()])
	_walk_done = false
	_walk(body)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(puppet.playing() == "walk" and body.layer() == "gaming", "she walks and goes on playing (%s, layer %s)" % [puppet.playing(), body.layer()])
	while not _walk_done:
		await get_tree().physics_frame
	await get_tree().process_frame
	_check(puppet.playing() == "idle" and body.layer() == "gaming", "she stops and still plays (%s, layer %s)" % [puppet.playing(), body.layer()])

	_check(body.play_once("greet") and body.layer() == "", "a greeting is the whole body's: the layer comes off (%s)" % body.layer())
	puppet.clip_finished.emit("greet")
	_check(body.layer() == "gaming", "and goes back on afterwards (%s)" % body.layer())

	body.set_presence("summon")
	_check(body.layer() == "", "being summoned she does not play (%s)" % body.layer())
	body.set_presence("idle")
	_check(body.layer() == "gaming", "the summon ends and she plays (%s)" % body.layer())
	body.set_ethereal(true)
	_check(body.layer() == "", "stepping out of the pod she does not play")
	body.set_ethereal(false)
	body.set_karada_state("think")
	_check(body.layer() == "" and puppet.overlay() == "" and puppet.playing() == "think", "another state takes the layer off (%s)" % body.layer())
	body.set_karada_state("gaming")
	body.set_karada_state("sit")
	_check(body.layer() == "" and puppet.playing() == "sit", "from playing to sitting (%s, %s)" % [body.layer(), puppet.playing()])


func _walk(body: CharacterBody3D) -> void:
	await body.act("move", {"x": 1.5, "y": 0.0, "z": 0.0})
	_walk_done = true


func _check(ok: bool, what: String) -> void:
	_count += 1
	if ok:
		print("[probe] ok: %s" % what)
	else:
		_failed += 1
		print("[probe] FAIL: %s" % what)
