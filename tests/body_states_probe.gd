## What their body shows of Karada's states, with no server: think / write only when they are idle, walking and a
## greeting win over them, and they go back to the state afterwards; `summon` (presence) holds them back too.
##
##   SKIN=$HOME/gits/Synthetic_Heart/skins/Rei godot --headless --path RetroXR \
##       res://mods/xenu.synth_rift/tests/body_states_probe.tscn
extends Node

var _failed := 0
var _count := 0
var _walk_done := false


func _ready() -> void:
	var skin := OS.get_environment("SKIN")
	if skin.is_empty():
		print("[probe] no SKIN set")
		get_tree().quit(1)
		return
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)
	var body: CharacterBody3D = preload("res://mods/xenu.synth_rift/scripts/synth_body.gd").new()
	add_child(body)
	var puppet: Node3D = preload("res://mods/xenu.synth_rift/scripts/karada_puppet.gd").new()
	add_child(puppet)
	puppet.load_model(FileAccess.get_file_as_bytes(skin + "/model.vrm"))
	for pair: Array in [["idle", "idle/Idle2.fbx"], ["greet", "greet/Standing Greeting.fbx"],
			["think", "think/Thinking.fbx"], ["write", "write/Texting While Standing.fbx"], ["walk", "walk/walk/Walking.fbx"],
			["turn_left", "walk/turn_left/Left Turn.fbx"], ["turn_right", "walk/turn_right/Right Turn.fbx"]]:
		puppet.add_clip(pair[0], FileAccess.get_file_as_bytes(skin + "/animations/" + pair[1]))
	body.attach_puppet(puppet)
	await get_tree().process_frame

	_check(puppet.playing() == "idle", "they stand to begin with (%s)" % puppet.playing())
	body.set_karada_state("think")
	_check(puppet.playing() == "think", "idle and Karada says think: they are seen thinking (%s)" % puppet.playing())
	body.set_karada_state("write")
	_check(puppet.playing() == "write", "and writing (%s)" % puppet.playing())
	body.set_karada_state("idle")
	_check(puppet.playing() == "idle", "and standing again (%s)" % puppet.playing())

	# Walking wins; the state is waiting for them when they stop.
	body.set_karada_state("think")
	_walk_done = false
	_walk(body)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# The goal is on their right, a quarter turn: the first thing is that turn (below), then the walking clip.
	while body.is_turning():
		await get_tree().physics_frame
	await get_tree().physics_frame
	_check(body.is_busy() and puppet.playing() == "walk", "they walk: the walking clip plays, not thinking (%s)" % puppet.playing())
	body.set_karada_state("write")
	await get_tree().physics_frame
	_check(puppet.playing() == "walk", "a new state while they walk does not stop the walk (%s)" % puppet.playing())
	while not _walk_done:
		await get_tree().physics_frame
	await get_tree().process_frame
	_check(not body.is_busy() and puppet.playing() == "write", "they have arrived and are writing, the state they were in (%s)" % puppet.playing())

	# A greeting is not interrupted by a state; it goes back to it afterwards.
	body.set_karada_state("think")
	_check(body.play_once("greet") and puppet.playing() == "greet", "a greeting plays (%s)" % puppet.playing())
	body.set_karada_state("write")
	await get_tree().process_frame
	_check(puppet.playing() == "greet", "Karada changing state does not cut the greeting (%s)" % puppet.playing())
	puppet.clip_finished.emit("greet")
	_check(puppet.playing() == "write" and not body.is_busy(), "afterwards they are in the state Karada is in now (%s)" % puppet.playing())

	# Presence: while a vessel introduces them, no state pose.
	body.set_karada_state("idle")
	body.set_presence("summon")
	body.set_karada_state("think")
	_check(body.is_busy() and puppet.playing() == "idle", "being summoned: thinking stays in the background (%s)" % puppet.playing())
	body.set_presence("idle")
	_check(puppet.playing() == "think", "the presence ends: they think, as Karada says (%s)" % puppet.playing())

	# Arriving (see-through, on their way out of the pod) holds it back too.
	body.set_ethereal(true)
	_check(puppet.playing() == "idle", "stepping out of the pod: standing (%s)" % puppet.playing())
	body.set_ethereal(false)
	_check(puppet.playing() == "think", "out and solid: thinking again (%s)" % puppet.playing())

	# The mouth: when the voice bus measures nothing while they speak, it moves anyway; and it closes when they stop.
	var face: RefCounted = body.face_of()
	body._capture = null
	body._force_speaking = true
	var opened := 0.0
	for i in 40:
		await get_tree().process_frame
		opened = maxf(opened, float(face.mouth_open()))
	_check(opened > 0.05, "their mouth moves while they speak even when nothing is measured (%.2f)" % opened)
	body._force_speaking = false
	for i in 40:
		await get_tree().process_frame
	_check(face.mouth_open() < 0.02, "and closes when they stop (%.2f)" % face.mouth_open())
	_check(body.speech_pattern(0.0) >= 0.02 and body.speech_pattern(3.3) <= 0.3, "the pattern stays between a whisper and a normal voice")

	# A turn is a clip, not a swivel: walking off behind them starts with the turn that side's, and the body ends up facing
	# where it went. (Control: with no turn clips, rotation at once, which is what the capsule does.)
	body.set_karada_state("idle")
	await get_tree().physics_frame
	body.global_position = Vector3.ZERO
	body.rotation.y = 0.0   # facing -Z
	_walk_done = false
	body.act("move", {"x": -1.5, "y": 0.0, "z": 0.0})   # to their left side (-X is left of a body facing -Z)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(body.is_turning() and puppet.playing() == "turn_left", "a goal to the left: they turn left first (%s)" % puppet.playing())
	var x_during := body.global_position.x
	var turned_for := 0
	while body.is_turning() and turned_for < 400:
		await get_tree().physics_frame
		turned_for += 1
	_check(absf(body.global_position.x - x_during) < 0.05, "and do not walk while they turn (moved %.2f m)" % absf(body.global_position.x - x_during))
	_check(absf(wrapf(body.rotation.y - deg_to_rad(90.0), -PI, PI)) < deg_to_rad(25.0), "the turn leaves the body facing its way (rotation %.0f deg)" % rad_to_deg(body.rotation.y))
	await get_tree().physics_frame
	_check(puppet.playing() == "walk", "then the walking clip plays (%s)" % puppet.playing())
	await get_tree().create_timer(0.3).timeout
	_check(body.global_position.x < x_during - 0.1, "and they walk to the left (x %.2f)" % body.global_position.x)
	body._end_walk(false, "the probe ends it")
	await get_tree().physics_frame
	body.global_position = Vector3(0, 0, 0)
	body.rotation.y = 0.0
	body.face_yaw(deg_to_rad(-100.0))
	await get_tree().physics_frame
	_check(body.is_turning() and puppet.playing() == "turn_right", "a face turned away to the right plays the right turn (%s)" % puppet.playing())
	while body.is_turning():
		await get_tree().physics_frame
	for i in 40:
		await get_tree().physics_frame
	_check(absf(wrapf(body.rotation.y + deg_to_rad(100.0), -PI, PI)) < deg_to_rad(2.0), "and settles exactly on the heading asked (%.1f deg)" % rad_to_deg(body.rotation.y))
	_check(body.heading().dot(Vector3(-sin(deg_to_rad(-100.0)), 0, -cos(deg_to_rad(-100.0)))) > 0.999, "heading() says it")
	# Seamless: the hips show the turn through the clip and the body takes it over when the clip is cut; the picture of the
	# hips must not jump across that handover (without shed_yaw the crossfade starts a whole turn away).
	body.global_position = Vector3(0, 0, 0)
	body.rotation.y = 0.0
	body.face_yaw(deg_to_rad(-90.0 - 5.0))
	await get_tree().physics_frame
	var hips_bone: int = puppet.skeleton.find_bone("J_Bip_C_Hips")
	var last_yaw := NAN
	var guard := 0
	while body.is_turning() and guard < 400:
		await get_tree().process_frame
		if body.is_turning():   # a frame in which the body has not yet taken the turn over
			last_yaw = _hips_yaw(body, puppet, hips_bone)
		guard += 1
	await get_tree().physics_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var jump := absf(wrapf(_hips_yaw(body, puppet, hips_bone) - last_yaw, -180.0, 180.0))
	_check(jump < 25.0, "the picture of the hips does not jump when the body takes the turn over (%.0f deg)" % jump)

	body.face_yaw(deg_to_rad(-90.0))
	await get_tree().physics_frame
	_check(not body.is_turning(), "a turn under the threshold is eased, not a clip (%.0f deg)" % rad_to_deg(wrapf(deg_to_rad(-90.0) - body.rotation.y, -PI, PI)))

	# A small turn is a clip too (it used to be a swivel under 40 degrees).
	body.global_position = Vector3.ZERO
	body.rotation.y = 0.0
	body.face_yaw(deg_to_rad(25.0))
	await get_tree().physics_frame
	_check(body.is_turning() and puppet.playing() == "turn_left", "a 25 degree turn plays the turn clip (%s)" % puppet.playing())
	while body.is_turning():
		await get_tree().physics_frame
	for i in 40:
		await get_tree().physics_frame
	_check(absf(wrapf(body.rotation.y - deg_to_rad(25.0), -PI, PI)) < deg_to_rad(3.0), "and ends facing it (%.0f deg)" % rad_to_deg(body.rotation.y))

	# A turn asked while a clip plays waits for it; the body does not swivel under the clip.
	body.rotation.y = 0.0
	body.set_karada_state("idle")
	_check(body.play_once("greet"), "a greeting plays")
	body.face_yaw(deg_to_rad(90.0))
	for i in 10:
		await get_tree().physics_frame
	_check(absf(body.rotation.y) < deg_to_rad(1.0) and not body.is_turning(), "a turn asked during it waits (rotation %.0f deg)" % rad_to_deg(body.rotation.y))
	var waited := 0
	while puppet.playing() == "greet" and waited < 1200:
		await get_tree().physics_frame
		waited += 1
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(body.is_turning() and puppet.playing() == "turn_left", "and plays the turn once the clip is over (%s)" % puppet.playing())
	while body.is_turning():
		await get_tree().physics_frame
	for i in 40:
		await get_tree().physics_frame

	# A corner in the way of a walk is a turn on the spot, not a swivel with the walk playing.
	body.global_position = Vector3.ZERO
	body.rotation.y = 0.0
	body._turn_first = false
	body._goal = Vector3(0.0, 0.0, 3.0)   # straight behind: 180 degrees from where they face, no turn_first
	body._path = PackedVector3Array([Vector3(0.0, 0.0, 3.0)])
	body._path_i = 0
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(body.is_turning(), "a way that goes straight back starts with a turn, not a swivel (%s)" % puppet.playing())
	body._end_walk(false, "the probe ends it")
	while body.is_turning():
		await get_tree().physics_frame

	# Seated: a standing person's turn clip would be wrong; it is eased.
	body.set_karada_state("sit")
	body.rotation.y = 0.0
	body.face_yaw(deg_to_rad(90.0))
	await get_tree().physics_frame
	_check(not body.is_turning(), "seated, a turn is eased and not a standing clip")
	body.set_karada_state("idle")

	print("[probe] done, %d cases, %d failed" % [_count, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


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


## Which way the hips face in the world, in degrees about UP.
func _hips_yaw(body: Node3D, puppet: Node3D, bone: int) -> float:
	var basis: Basis = body.global_basis * puppet.skeleton.get_bone_global_pose(bone).basis
	var forward := basis * Vector3(0, 0, 1)
	return rad_to_deg(atan2(forward.x, forward.z))
