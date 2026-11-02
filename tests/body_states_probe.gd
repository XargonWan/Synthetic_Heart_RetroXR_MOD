## What her body shows of Karada's states, with no server: think / write only when she is idle, walking and a
## greeting win over them, and she goes back to the state afterwards; `summon` (presence) holds them back too.
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
			["think", "think/Thinking.fbx"], ["write", "write/Texting While Standing.fbx"], ["walk", "Texting And Walking.fbx"]]:
		puppet.add_clip(pair[0], FileAccess.get_file_as_bytes(skin + "/animations/" + pair[1]))
	body.attach_puppet(puppet)
	await get_tree().process_frame

	_check(puppet.playing() == "idle", "she stands to begin with (%s)" % puppet.playing())
	body.set_karada_state("think")
	_check(puppet.playing() == "think", "idle and Karada says think: she is seen thinking (%s)" % puppet.playing())
	body.set_karada_state("write")
	_check(puppet.playing() == "write", "and writing (%s)" % puppet.playing())
	body.set_karada_state("idle")
	_check(puppet.playing() == "idle", "and standing again (%s)" % puppet.playing())

	# Walking wins; the state is waiting for her when she stops.
	body.set_karada_state("think")
	_walk_done = false
	_walk(body)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(body.is_busy() and puppet.playing() == "walk", "she walks: the walking clip plays, not thinking (%s)" % puppet.playing())
	body.set_karada_state("write")
	await get_tree().physics_frame
	_check(puppet.playing() == "walk", "a new state while she walks does not stop the walk (%s)" % puppet.playing())
	while not _walk_done:
		await get_tree().physics_frame
	await get_tree().process_frame
	_check(not body.is_busy() and puppet.playing() == "write", "she has arrived and is writing, the state she was in (%s)" % puppet.playing())

	# A greeting is not interrupted by a state; it goes back to it afterwards.
	body.set_karada_state("think")
	_check(body.play_once("greet") and puppet.playing() == "greet", "a greeting plays (%s)" % puppet.playing())
	body.set_karada_state("write")
	await get_tree().process_frame
	_check(puppet.playing() == "greet", "Karada changing state does not cut the greeting (%s)" % puppet.playing())
	puppet.clip_finished.emit("greet")
	_check(puppet.playing() == "write" and not body.is_busy(), "afterwards she is in the state Karada is in now (%s)" % puppet.playing())

	# Presence: while a vessel introduces her, no state pose.
	body.set_karada_state("idle")
	body.set_presence("summon")
	body.set_karada_state("think")
	_check(body.is_busy() and puppet.playing() == "idle", "being summoned: thinking stays in the background (%s)" % puppet.playing())
	body.set_presence("idle")
	_check(puppet.playing() == "think", "the presence ends: she thinks, as Karada says (%s)" % puppet.playing())

	# Arriving (see-through, on her way out of the pod) holds it back too.
	body.set_ethereal(true)
	_check(puppet.playing() == "idle", "stepping out of the pod: standing (%s)" % puppet.playing())
	body.set_ethereal(false)
	_check(puppet.playing() == "think", "out and solid: thinking again (%s)" % puppet.playing())

	# The mouth: when the voice bus measures nothing while she speaks, it moves anyway; and it closes when she stops.
	var face: RefCounted = body.face_of()
	body._capture = null
	body._force_speaking = true
	var opened := 0.0
	for i in 40:
		await get_tree().process_frame
		opened = maxf(opened, float(face.mouth_open()))
	_check(opened > 0.05, "her mouth moves while she speaks even when nothing is measured (%.2f)" % opened)
	body._force_speaking = false
	for i in 40:
		await get_tree().process_frame
	_check(face.mouth_open() < 0.02, "and closes when she stops (%.2f)" % face.mouth_open())
	_check(body.speech_pattern(0.0) >= 0.02 and body.speech_pattern(3.3) <= 0.3, "the pattern stays between a whisper and a normal voice")

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
