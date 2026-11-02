## SynthBody -- Synth's body in the room.
##
## Phase 0: a capsule that walks in a straight line (no navigation yet: no room
## has a navmesh, and what to do about that is exactly what this spike measures),
## says things in a bubble over its head and reports where it is. The VRM and its
## animations replace the capsule later without changing this interface.
##
## `act()` answers a verb asked by Synth with {ok, detail, data}; a verb that takes
## time (move) answers when it is done, which is why it is a coroutine.
extends CharacterBody3D

const Protocol := preload("res://mods/xenu.synth_rift/scripts/rift_protocol.gd")
const ChatPanel := preload("res://mods/xenu.synth_rift/scripts/chat_panel.gd")
const AudioBytes := preload("res://mods/xenu.synth_rift/scripts/audio_bytes.gd")

const WALK_SPEED := 1.1
const ARRIVE_DISTANCE := 0.35
## Never further from the Summoner than this: Synth lives in the room it was called to.
const LEASH := 6.0
const GRAVITY := 9.8
const STUCK_SECONDS := 1.5
const STUCK_SAMPLE := 0.5
## Less than this in one sample while asked to walk is not walking.
const STUCK_DISTANCE := 0.1
const MOVE_TIMEOUT := 40.0
const BUBBLE_SECONDS_PER_CHAR := 0.07

## Where the Summoner stands; the leash is measured from here.
var anchor: Vector3 = Vector3.ZERO

var _bubble: Label3D = null
var _visual: Node3D = null
var _capsule: MeshInstance3D = null
var _puppet: Node3D = null
var _anim_state := ""
## What Synth's Karada says she is doing (idle, think, write, talk, touch): her body follows it,
## except while she walks, and again when she stops.
var _karada_state := "idle"
var _fetcher: Node = null
var _voice: AudioStreamPlayer3D = null
var _voice_queue: Array = []
var _voice_heard := 0
var _bubble_left := 0.0
var _goal: Variant = null  # Vector3 while walking
var _stuck_for := 0.0
var _stuck_sample := 0.0
var _last_pos := Vector3.ZERO
var _walk_elapsed := 0.0
var _walk_result: Dictionary = {}
signal _walk_finished
## Something was said, by the player or by her: the chat page redraws.
signal chat_changed
## The player wrote this to her: the Summoner sends it to Synth.
signal chat_sent(text: String)

const MAX_CHAT := 60
var _chat: Array = []


func _ready() -> void:
	var capsule := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.22
	mesh.height = 1.55
	capsule.mesh = mesh
	capsule.position.y = 0.775
	capsule.name = "Visual"
	_visual = capsule
	_capsule = capsule
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.78, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.4, 0.9)
	mat.emission_energy_multiplier = 0.4
	mesh.material = mat
	add_child(capsule)

	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.22
	cap.height = 1.55
	shape.shape = cap
	shape.position.y = 0.775
	add_child(shape)

	_bubble = Label3D.new()
	_bubble.position = Vector3(0, 1.85, 0)
	_bubble.pixel_size = 0.0016
	_bubble.font_size = 44
	_bubble.outline_size = 10
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.no_depth_test = true
	_bubble.visible = false
	_bubble.width = 700
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_bubble)
	_last_pos = global_position

	# Point at her and press Tab (the left thumbstick) to write to her: this is what the ray finds.
	var pointer := StaticBody3D.new()
	pointer.name = "PointerArea"
	pointer.collision_layer = 1 << 20
	pointer.collision_mask = 0
	var pshape := CollisionShape3D.new()
	var pcyl := CylinderShape3D.new()
	pcyl.radius = 0.38
	pcyl.height = 1.75
	pshape.shape = pcyl
	pshape.position.y = 0.875
	pointer.add_child(pshape)
	add_child(pointer)

	# Her voice comes from her head.
	_voice = AudioStreamPlayer3D.new()
	_voice.name = "Voice"
	_voice.unit_size = 3.0
	_voice.max_distance = 20.0
	_voice.position = Vector3(0, 1.55, 0)
	add_child(_voice)
	_voice.finished.connect(_next_voice)


func _physics_process(delta: float) -> void:
	if _bubble_left > 0.0:
		_bubble_left -= delta
		if _bubble_left <= 0.0:
			_bubble.visible = false

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = 0.0

	if _goal == null:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		return

	_set_anim("walk")
	var goal: Vector3 = _goal
	var to_goal := Vector3(goal.x - global_position.x, 0.0, goal.z - global_position.z)
	_walk_elapsed += delta
	if to_goal.length() <= ARRIVE_DISTANCE:
		_end_walk(true, "arrived")
		return
	if _walk_elapsed > MOVE_TIMEOUT:
		_end_walk(false, "timeout")
		return
	var dir := to_goal.normalized()
	velocity.x = dir.x * WALK_SPEED
	velocity.z = dir.z * WALK_SPEED
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), minf(1.0, 8.0 * delta))
	move_and_slide()

	# Blocked: asked to move, and the body is not getting anywhere.
	_stuck_sample += delta
	if _stuck_sample >= STUCK_SAMPLE:
		if global_position.distance_to(_last_pos) < STUCK_DISTANCE:
			_stuck_for += _stuck_sample
		else:
			_stuck_for = 0.0
		_last_pos = global_position
		_stuck_sample = 0.0
	if _stuck_for > STUCK_SECONDS:
		_end_walk(false, "blocked")


func _end_walk(ok: bool, detail: String) -> void:
	_goal = null
	_set_anim(_rest_anim())
	_stuck_for = 0.0
	_stuck_sample = 0.0
	velocity = Vector3.ZERO
	_walk_result = {"ok": ok, "detail": detail, "data": {"position": Protocol.vec(global_position)}}
	print("[Rift] walk ended: %s at %s" % [detail, str(global_position)])
	_walk_finished.emit()


## Materialise: the body grows out of a point on the floor, fast then slow, brightest at
## the start. The collider is not scaled (physics bodies do not like it), only the picture.
func appear(seconds: float) -> void:
	_visual.scale = Vector3(0.05, 0.02, 0.05)
	_visual.visible = true
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_visual, "scale", Vector3.ONE, seconds)
	if _puppet == null:
		var mat := _capsule.mesh.material as StandardMaterial3D
		mat.emission_energy_multiplier = 3.0
		tw.tween_property(mat, "emission_energy_multiplier", 0.4, seconds * 1.4)
	await tw.finished


## The reverse: it shrinks into the floor and is gone.
func disappear(seconds: float) -> void:
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_visual, "scale", Vector3(0.05, 0.02, 0.05), seconds)
	if _puppet == null:
		var mat := _capsule.mesh.material as StandardMaterial3D
		tw.tween_property(mat, "emission_energy_multiplier", 3.0, seconds)
	await tw.finished
	_visual.visible = false


## Intangible and half there: no collision (the pod, a rigid body, is pushed by a body that overlaps
## it, which is how a first summon sent the capsule sliding away) and see-through. She is
## like this from the moment she arrives until she is actually outside, and again on her way back in.
const ETHEREAL_FADE := 0.55
var _ethereal := false


func set_ethereal(on: bool) -> void:
	_ethereal = on
	collision_layer = 0 if on else 1
	_set_fade(ETHEREAL_FADE if on else 0.0)


func is_ethereal() -> bool:
	return _ethereal


## She becomes solid and opaque, over `seconds`: the moment she is really in the room.
func materialise(seconds: float) -> void:
	_ethereal = false
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_fade, ETHEREAL_FADE, 0.0, seconds)
	await tw.finished
	collision_layer = 1


## How see-through she is: 0 solid, 1 gone (dithered per instance; a renderer that ignores it, the
## Quest's, shows her solid, which is no worse than before).
func _set_fade(amount: float) -> void:
	for n: Node in _visual_parts():
		(n as GeometryInstance3D).transparency = amount


func _visual_parts() -> Array:
	var root: Node = _puppet if _puppet != null else _capsule
	if root == null:
		return []
	var parts: Array = root.find_children("*", "GeometryInstance3D", true, false)
	if root is GeometryInstance3D:
		parts.append(root)
	return parts


## Hidden until she is called out of the capsule.
func hide_until_summoned() -> void:
	_visual.visible = false


## Her real body (a KaradaPuppet, loaded from her skin) in place of the capsule. It stands on the
## floor, faces -Z like this body does, and the speech bubble moves up to her head.
func attach_puppet(puppet: Node3D) -> void:
	if puppet.get_parent() != null:
		puppet.reparent(self, false)
	else:
		add_child(puppet)
	puppet.position = Vector3.ZERO
	puppet.rotation = Vector3.ZERO
	_puppet = puppet
	_visual = puppet
	_capsule.visible = false
	_bubble.position.y = float(puppet.get("height")) + 0.25
	_set_anim(_rest_anim())
	if _ethereal:
		_set_fade(ETHEREAL_FADE)
	print("[Rift] Synth's own body is on (%.2f m)" % float(puppet.get("height")))


func has_puppet() -> bool:
	return _puppet != null


## Her avatar's own states, as Karada tells them (the server owns "what she is doing"): the clip of that
## name if her skin has it, else standing. A state that is not one of her clips changes nothing.
func set_karada_state(state: String) -> void:
	_karada_state = state if not state.is_empty() else "idle"
	# Walking wins while she walks; _end_walk puts the state back.
	if _goal == null and _puppet != null:
		_anim_state = ""
		_set_anim(_rest_anim())


func karada_state() -> String:
	return _karada_state


## The clip she rests in: Karada's state if her skin has it, else standing.
func _rest_anim() -> String:
	if _puppet != null and _karada_state != "idle" and bool(_puppet.call("has_clip", _karada_state)):
		return _karada_state
	return "idle"


## One frame from Karada.
func on_karada(kind: String, payload: Dictionary) -> void:
	match kind:
		"animation":
			set_karada_state(str(payload.get("state", "idle")))
		"audio":
			_hear(payload)
		_:
			pass  # the face, the model and the expressions are not drawn yet


func set_fetcher(fetcher: Node) -> void:
	_fetcher = fetcher


## Her voice: fetch the clip from the server and play it from her head, in order.
func _hear(payload: Dictionary) -> void:
	var url := str(payload.get("url", ""))
	if url.is_empty() or _fetcher == null:
		return
	var bytes: PackedByteArray = await _fetcher.call("get_fresh", url)
	if not is_inside_tree():
		return
	var stream := AudioBytes.stream_from(bytes)
	if stream == null:
		print("[Rift] her voice could not be played (%d bytes from %s)" % [bytes.size(), url])
		return
	_voice_queue.append(stream)
	print("[Rift] her voice: %.1f s, \"%s\"" % [AudioBytes.seconds_of(stream), str(payload.get("text", "")).left(60)])
	if not _voice.playing:
		_next_voice()


func _next_voice() -> void:
	if _voice_queue.is_empty():
		return
	_voice.stream = _voice_queue.pop_front()
	_voice.play()
	_voice_heard += 1


func is_speaking() -> bool:
	return _voice != null and _voice.playing


## How many clips of her voice have played (the probes count them).
func voices_played() -> int:
	return _voice_heard


## What she is doing, as an animation: standing, walking. Names her skin has not got fall back
## to standing (her body then slides, which is still better than a stiff pose).
func _set_anim(state: String) -> void:
	if _puppet == null or state == _anim_state:
		return
	_anim_state = state
	if _puppet.has_method("has_clip") and bool(_puppet.call("has_clip", state)):
		_puppet.call("play", state, true)
	elif state != "idle" and bool(_puppet.call("has_clip", "idle")):
		_puppet.call("play", "idle", true)


## A one-off animation from her skin, then standing again. False when her skin has not got it.
func play_once(clip_name: String) -> bool:
	if _puppet == null or not bool(_puppet.call("has_clip", clip_name)):
		return false
	_anim_state = ""
	return bool(_puppet.call("play_then", clip_name, _rest_anim()))


## The menu she has, like every object: point at her and press Tab, and write.
func toggle_options_ui(camera: Node3D) -> void:
	ChatPanel.toggle_for(self, camera)


func chat_lines() -> Array:
	return _chat


## The player wrote to her (the page's Send): kept in the log and handed on.
func send_chat(text: String) -> void:
	var t := text.strip_edges()
	if t.is_empty():
		return
	_log_chat("you", t)
	chat_sent.emit(t)


func _log_chat(who: String, text: String) -> void:
	_chat.append({"who": who, "text": text})
	if _chat.size() > MAX_CHAT:
		_chat = _chat.slice(_chat.size() - MAX_CHAT)
	chat_changed.emit()


func say_bubble(text: String) -> void:
	_bubble.text = text
	_bubble.visible = true
	_bubble_left = clampf(text.length() * BUBBLE_SECONDS_PER_CHAR, 3.0, 12.0)


## Answer a verb. Always returns {ok, detail, data}; never throws.
func act(action: String, payload: Dictionary) -> Dictionary:
	match action:
		"say":
			var text := str(payload.get("text", "")).strip_edges()
			if text.is_empty():
				return {"ok": false, "detail": "empty_text"}
			say_bubble(text)
			_log_chat("synth", text)
			return {"ok": true, "detail": "spoken"}
		"status":
			return {"ok": true, "data": {"position": Protocol.vec(global_position)}}
		"look":
			return _look(payload)
		"move":
			return await _move(payload)
		"emote":
			var clip := str(payload.get("name", "")).strip_edges()
			if clip.is_empty():
				return {"ok": false, "detail": "no_name"}
			if play_once(clip):
				return {"ok": true, "detail": "playing " + clip}
			return {"ok": false, "detail": "no_such_animation: " + clip}
		_:
			print("[Rift] verb %s is not built yet" % action)
			return {"ok": false, "detail": "not_implemented_yet: " + action}


func _look(payload: Dictionary) -> Dictionary:
	var point: Variant = Protocol.point_of(payload)
	if point is Vector3:
		var p: Vector3 = point
		var flat := Vector3(p.x - global_position.x, 0.0, p.z - global_position.z)
		if flat.length() > 0.01:
			rotation.y = atan2(-flat.x, -flat.z)
			return {"ok": true}
	if payload.has("yaw"):
		rotation.y = deg_to_rad(float(payload["yaw"]))
		return {"ok": true}
	if str(payload.get("target", "")) == "player":
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var f := cam.global_position - global_position
			rotation.y = atan2(-f.x, -f.z)
			return {"ok": true}
	return {"ok": false, "detail": "no_target"}


func _move(payload: Dictionary) -> Dictionary:
	var point: Variant = Protocol.point_of(payload)
	if not (point is Vector3) and str(payload.get("target", "")) == "player":
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var toward := cam.global_position
			# Stop a little short of the player rather than in their face.
			var away := (global_position - toward)
			away.y = 0.0
			point = toward + (away.normalized() * 0.8 if away.length() > 0.01 else Vector3.ZERO)
	if not (point is Vector3):
		return {"ok": false, "detail": "no_target"}
	var dest: Vector3 = point
	var from_anchor := Vector3(dest.x - anchor.x, 0.0, dest.z - anchor.z)
	if from_anchor.length() > LEASH:
		return {"ok": false, "detail": "too_far_from_the_summoner (limit %.0f m)" % LEASH}
	if _goal != null:
		_end_walk(false, "replaced")
	_goal = dest
	_walk_elapsed = 0.0
	_stuck_for = 0.0
	_stuck_sample = 0.0
	_last_pos = global_position
	await _walk_finished
	return _walk_result
