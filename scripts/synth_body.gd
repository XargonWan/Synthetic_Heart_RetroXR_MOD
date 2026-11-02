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
const SummonerView := preload("res://mods/xenu.synth_rift/scripts/summoner_view.gd")
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
## The one-off clip she is playing (a greeting, an emote); while it plays Karada's states wait.
var _one_shot := ""
## What Synth's Karada says she is doing (idle, think, write, talk, touch): her body follows it,
## except while she walks, and again when she stops.
var _karada_state := "idle"
## Karada's presence: "summon" while a vessel is introducing her into this room (a rift opening), "" otherwise.
var _presence := ""
var _fetcher: Node = null
var _voice: AudioStreamPlayer3D = null
var _voice_queue: Array = []
var _voice_heard := 0
## Her voice has a bus of its own, with a capture on it: how loud she is right now opens her mouth.
const VOICE_BUS := "SynthVoice"
var _capture: AudioEffectCapture = null
## Set by the Summoner: (query: String) -> Dictionary of the nearest thing in the room called that
## ({name, label, type, systemid, powered, position}), or {}. "player" is handled here.
var world_lookup: Callable = Callable()
## Where she is looking: at the player ("player"), at a point she chose ("point"), or nowhere.
## A glance is short: the player moving or clicking earns ONE (GLANCE_SECONDS), and then she
## ignores them for GLANCE_COOLDOWN, or she would stare like a security camera. She looks at them
## for as long as she speaks, and when she arrives; at a thing for as long as she studies it.
const GLANCE_SECONDS := 2.2
const GLANCE_COOLDOWN := 10.0
const ARRIVAL_LOOK_SECONDS := 6.0
const STUDY_SECONDS := 5.0
## How many verbs she has been given (the probes wait for the server to finish asking).
var acts_seen := 0
var _look_kind := ""
var _look_point := Vector3.ZERO
var _look_left := 0.0
var _glance_cool := 0.0
var _noticed := false
## While she has just chosen where to look, the reflex leaves it alone until then (ticks, ms).
var _deliberate_until := 0
var _gaze_clock := 0.0
var _gaze_cam_pos := Vector3.ZERO
var _gaze_cam_fwd := Vector3.ZERO
const GAZE_MOVE_M := 0.06
const GAZE_TURN_DEG := 5.0
const DELIBERATE_MS := 6000
var _follow := false
var _follow_clock := 0.0
const FOLLOW_DISTANCE := 1.4
const STOP_SHORT := 0.9
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
	_capture = _voice_capture()
	if _capture != null:
		_voice.bus = VOICE_BUS
	add_child(_voice)
	_voice.finished.connect(_next_voice)


func _process(_delta: float) -> void:
	_lip_sync()


func _physics_process(delta: float) -> void:
	_update_gaze(delta)
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
		_follow_the_player(delta)
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


func _input(event: InputEvent) -> void:
	# A click is the player doing something: she may notice (the WebUI avatar's eyes do the same).
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_noticed = true


## Look at the player for `seconds` (never shortens a look she is already in).
func attend_player(seconds: float) -> void:
	if _look_kind == "point" and _look_left > 0.0:
		return
	_look_kind = "player"
	_look_left = maxf(_look_left, seconds)


## Look at a point in the world she chose, for `seconds`.
func study_point(point: Vector3, seconds: float = STUDY_SECONDS) -> void:
	_look_kind = "point"
	_look_point = point
	_look_left = seconds


## The reflex: when the player moves or clicks and she is doing nothing else, she glances at them for a
## moment, then relaxes, and does not look again for a while however much they move. Never while she
## walks (she looks where she goes), never right after she chose where to look; and she looks at them
## for as long as she is speaking.
func _update_gaze(delta: float) -> void:
	if _puppet == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	_glance_cool = maxf(_glance_cool - delta, 0.0)
	_gaze_clock += delta
	if _gaze_clock >= 0.2:
		var moved := cam.global_position.distance_to(_gaze_cam_pos) > GAZE_MOVE_M
		var turned := rad_to_deg(_gaze_cam_fwd.angle_to(-cam.global_basis.z)) > GAZE_TURN_DEG if _gaze_cam_fwd != Vector3.ZERO else false
		if (moved or turned) and _gaze_cam_pos != Vector3.ZERO:
			_noticed = true
		_gaze_cam_pos = cam.global_position
		_gaze_cam_fwd = -cam.global_basis.z
		_gaze_clock = 0.0
	var busy := _goal != null or Time.get_ticks_msec() < _deliberate_until
	if _noticed:
		_noticed = false
		if not busy and _look_left <= 0.0 and _glance_cool <= 0.0:
			attend_player(GLANCE_SECONDS)
			_glance_cool = GLANCE_COOLDOWN
	# Speaking to someone, she looks at them.
	if (_voice != null and _voice.playing) or _bubble_left > 0.0:
		attend_player(0.5)
	_look_left = maxf(_look_left - delta, 0.0)
	var target: Variant = null
	if _look_left > 0.0:
		if _look_kind == "point":
			target = _look_point
		elif _goal == null:
			target = cam.global_position + Vector3(0, -0.05, 0)
	_puppet.call("set_gaze", target)


func is_gazing() -> bool:
	return _puppet != null and float(_puppet.call("gaze_weight")) > 0.5


## What she is looking at right now: "player", "point" or "" (the tests read it).
func gaze_kind() -> String:
	return _look_kind if _look_left > 0.0 and is_gazing() else ""


## While she was asked to follow: keep to FOLLOW_DISTANCE of the player (inside her leash).
func _follow_the_player(delta: float) -> void:
	if not _follow:
		return
	_follow_clock += delta
	if _follow_clock < 0.5:
		return
	_follow_clock = 0.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var to_player := Vector3(cam.global_position.x - global_position.x, 0.0, cam.global_position.z - global_position.z)
	if to_player.length() <= FOLLOW_DISTANCE + 0.4:
		return
	var dest := cam.global_position - to_player.normalized() * FOLLOW_DISTANCE
	dest.y = global_position.y
	var from_anchor := Vector3(dest.x - anchor.x, 0.0, dest.z - anchor.z)
	if from_anchor.length() > LEASH:
		var edge := anchor + from_anchor.normalized() * LEASH
		dest = Vector3(edge.x, global_position.y, edge.z)
	_goal = dest
	_walk_elapsed = 0.0
	_stuck_for = 0.0
	_stuck_sample = 0.0
	_last_pos = global_position


func _end_walk(ok: bool, detail: String) -> void:
	_goal = null
	_anim_state = ""
	_refresh_anim()
	_stuck_for = 0.0
	_stuck_sample = 0.0
	velocity = Vector3.ZERO
	_walk_result = {"ok": ok, "detail": detail, "data": {"position": Protocol.vec(global_position)}}
	print("[Rift] walk ended: %s at %s" % [detail, str(global_position)])
	_walk_finished.emit()


## She comes into view. Her own body (loaded and warmed beforehand, see KaradaPuppet.warm) fades in as ONE
## thing, every part at the same value, with nothing growing and nothing arriving after the rest; the
## capsule that stands in for a body without a skin grows out of a point on the floor, fast then slow.
## The collider is not scaled (physics bodies do not like it), only the picture.
func appear(seconds: float) -> void:
	if _puppet != null:
		_visual.scale = Vector3.ONE
		_set_fade(1.0)
		_visual.visible = true
		var fade := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		fade.tween_method(_set_fade, 1.0, ETHEREAL_FADE, seconds)
		await fade.finished
		return
	_visual.scale = Vector3(0.05, 0.02, 0.05)
	_visual.visible = true
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_visual, "scale", Vector3.ONE, seconds)
	var mat := _capsule.mesh.material as StandardMaterial3D
	mat.emission_energy_multiplier = 3.0
	tw.tween_property(mat, "emission_energy_multiplier", 0.4, seconds * 1.4)
	await tw.finished


## The reverse: her body fades out as one thing; the capsule shrinks into the floor.
func disappear(seconds: float) -> void:
	if _puppet != null:
		var fade := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		fade.tween_method(_set_fade, ETHEREAL_FADE, 1.0, seconds)
		await fade.finished
		_visual.visible = false
		return
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_visual, "scale", Vector3(0.05, 0.02, 0.05), seconds)
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
	_refresh_anim()


func is_ethereal() -> bool:
	return _ethereal


## She becomes solid and opaque, over `seconds`: the moment she is really in the room.
func materialise(seconds: float) -> void:
	_ethereal = false
	# She has just stepped out and there is someone in front of her: she looks at them.
	attend_player(ARRIVAL_LOOK_SECONDS)
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_fade, ETHEREAL_FADE, 0.0, seconds)
	await tw.finished
	collision_layer = 1
	_refresh_anim()


## How see-through she is: 0 solid, 1 gone (dithered per instance; a renderer that ignores it, the
## Quest's, shows her solid, which is no worse than before).
func _set_fade(amount: float) -> void:
	if _puppet != null:
		_puppet.call("set_fade", amount)
		return
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
	if puppet.has_signal("clip_finished") and not puppet.is_connected("clip_finished", _on_clip_finished):
		puppet.connect("clip_finished", _on_clip_finished)
	_capsule.visible = false
	_bubble.position.y = float(puppet.get("height")) + 0.25
	_one_shot = ""
	_anim_state = ""
	_refresh_anim()
	if _ethereal:
		_set_fade(ETHEREAL_FADE)
	print("[Rift] Synth's own body is on (%.2f m)" % float(puppet.get("height")))


## Another skin: the new body takes her place where she stands, in what she was doing.
func swap_puppet(puppet: Node3D) -> void:
	var old := _puppet
	_puppet = null
	_anim_state = ""
	if puppet.get_parent() != null:
		puppet.reparent(self, false)
	else:
		add_child(puppet)
	puppet.position = Vector3.ZERO
	puppet.rotation = Vector3.ZERO
	puppet.visible = true
	if old != null and is_instance_valid(old):
		old.queue_free()
	attach_puppet(puppet)


func has_puppet() -> bool:
	return _puppet != null


## Her avatar's own states, as Karada tells them (the server owns "what she is doing"): the clip of that
## name if her skin has it, else standing. A state that is not one of her clips changes nothing.
func set_karada_state(state: String) -> void:
	_karada_state = state if not state.is_empty() else "idle"
	_refresh_anim()


func karada_state() -> String:
	return _karada_state


## Karada's presence (`summon` while she is being introduced), as the server says it.
func set_presence(presence: String) -> void:
	_presence = "" if presence in ["", "idle"] else presence
	_refresh_anim()


func presence() -> String:
	return _presence


## Karada's states are what her avatar is doing in her HEAD (think, write, touch): on the WebUI that is all she does,
## so they are always shown. Here she also has a body that does things, and a person can walk and think at once:
## she shows a state's clip only when she is not busy, and the activity wins otherwise (the state is remembered, so
## she goes back to it when the activity ends). `summon` is the state of being introduced into a rift: it is not a
## pose of its own (a skin may ship `animations/summon/`), it is the vessel saying "she is arriving".
func is_busy() -> bool:
	return _goal != null or _one_shot != "" or _ethereal or _presence == "summon"


## The clip she rests in. Standing while busy; the state's clip (if her skin has it) when she is not.
func _rest_anim() -> String:
	if _puppet == null:
		return "idle"
	if _presence == "summon":
		return "summon" if bool(_puppet.call("has_clip", "summon")) else "idle"
	if is_busy() or _karada_state == "idle":
		return "idle"
	return _karada_state if bool(_puppet.call("has_clip", _karada_state)) else "idle"


## Put the clip back to what she should be doing now, unless a walk or a one-shot has her.
func _refresh_anim() -> void:
	if _puppet == null or _goal != null or _one_shot != "":
		return
	_set_anim(_rest_anim())


## One frame from Karada.
func on_karada(kind: String, payload: Dictionary) -> void:
	match kind:
		"animation":
			set_karada_state(str(payload.get("state", "idle")))
			# The clip's own expressions (think shuts her eyes from a frame on).
			var descriptor: Variant = payload.get("descriptor", {})
			_face_call("set_descriptor", descriptor if descriptor is Dictionary else {})
		"audio":
			_hear(payload)
		"presence":
			set_presence(str(payload.get("state", "")))
		"face":
			if not (payload.get("values", {}) as Dictionary).is_empty():
				print("[Rift] Karada face: %s" % str(payload.get("values", {})))
			_face_call("set_face_values", payload.get("values", {}) if payload.get("values") is Dictionary else {})
		"expression":
			if str(payload.get("type", "")) != "vrm_expression_clear":
				print("[Rift] Karada expression: %s" % str(payload))
			if str(payload.get("type", "")) == "vrm_expression_clear":
				_face_call("set_overlay", null)
			else:
				_face_call("set_overlay", payload.get("targets", null))
		_:
			pass  # the model is the Summoner's: it fetches the new body


## Call something on her face, if she has one.
func _face_call(method: String, arg: Variant) -> void:
	if _puppet != null and _puppet.get("face") != null:
		(_puppet.get("face") as RefCounted).call(method, arg)


## The persona's blendshape map and the rest of her face come with the model: hand them over.
func face_of() -> RefCounted:
	return _puppet.get("face") if _puppet != null else null


## The bus her voice plays on, with a capture to measure it by; made once, kept for the session.
func _voice_capture() -> AudioEffectCapture:
	var bus := AudioServer.get_bus_index(VOICE_BUS)
	if bus < 0:
		AudioServer.add_bus()
		bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, VOICE_BUS)
		AudioServer.set_bus_send(bus, "Master")
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectCapture:
			return AudioServer.get_bus_effect(bus, i) as AudioEffectCapture
	var capture := AudioEffectCapture.new()
	capture.buffer_length = 0.25
	AudioServer.add_bus_effect(bus, capture)
	return capture


## Her mouth follows how loud she is: the RMS of what her voice just played, as the WebUI measures it.
func _lip_sync() -> void:
	var face := face_of()
	if face == null:
		return
	var level := 0.0
	if _capture != null:
		var frames := _capture.get_frames_available()
		if frames > 0:
			var buffer := _capture.get_buffer(frames)
			var sum := 0.0
			for f in buffer:
				sum += (f.x * f.x + f.y * f.y) * 0.5
			level = sqrt(sum / float(buffer.size()))
	face.call("speak_level", level if _voice != null and _voice.playing else 0.0)


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


## A one-off animation from her skin, then standing again (or the state she is in, when she is not busy any more).
## False when her skin has not got it.
func play_once(clip_name: String) -> bool:
	if _puppet == null or not bool(_puppet.call("has_clip", clip_name)):
		return false
	_one_shot = clip_name
	_anim_state = ""
	if not bool(_puppet.call("play", clip_name, false)):
		_one_shot = ""
		return false
	return true


func _on_clip_finished(clip_name: String) -> void:
	if _one_shot != "" and clip_name == _one_shot:
		_one_shot = ""
		_anim_state = ""
		_refresh_anim()


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
	acts_seen += 1
	if action in ["look", "look_at", "inspect", "emote", "move"]:
		# She chose where to look or what to do: the reflex stays out of it for a while.
		_deliberate_until = Time.get_ticks_msec() + DELIBERATE_MS
		_look_left = 0.0
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
		"look_at":
			return _look_at(payload)
		"inspect":
			return _inspect(payload)
		"follow":
			_follow = true
			_follow_clock = 0.0
			return {"ok": true, "detail": "following the player"}
		"unfollow":
			_follow = false
			return {"ok": true, "detail": "not following"}
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


## What `target` names: the player, or the nearest thing in the room with that name. {} when nothing.
func _resolve(payload: Dictionary) -> Dictionary:
	var query := str(payload.get("target", payload.get("name", ""))).strip_edges()
	if query.is_empty():
		return {}
	if query.to_lower() in ["player", "the player", "you", "user"]:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return {}
		return {"name": "player", "label": "the player", "type": "player", "position": cam.global_position}
	if world_lookup.is_valid():
		return world_lookup.call(query)
	return {}


func _face_point(p: Vector3) -> void:
	var flat := Vector3(p.x - global_position.x, 0.0, p.z - global_position.z)
	if flat.length() > 0.01:
		rotation.y = atan2(-flat.x, -flat.z)


## Her head goes to what she is studying; the player looks at themselves.
func _study(hit: Dictionary) -> void:
	if str(hit.get("type", "")) == "player":
		attend_player(STUDY_SECONDS)
		return
	study_point(hit["position"])


func _look_at(payload: Dictionary) -> Dictionary:
	var hit := _resolve(payload)
	if hit.is_empty():
		return {"ok": false, "detail": "nothing called '%s' that you can see" % str(payload.get("target", ""))}
	_face_point(hit["position"])
	_study(hit)
	return {"ok": true, "detail": "looking at %s" % str(hit.get("label", "it"))}


## Turn to it and say what it is. Nothing about a screen's picture yet: that is not built.
func _inspect(payload: Dictionary) -> Dictionary:
	var hit := _resolve(payload)
	if hit.is_empty():
		return {"ok": false, "detail": "nothing called '%s' that you can see" % str(payload.get("target", ""))}
	var pos: Vector3 = hit["position"]
	_face_point(pos)
	_study(hit)
	var bearing := SummonerView.bearing_deg(global_position, -global_basis.z, pos)
	var dist := Vector2(pos.x - global_position.x, pos.z - global_position.z).length()
	var bits: PackedStringArray = []
	if str(hit.get("type", "")) == "player":
		bits.append("a person")
	else:
		bits.append(str(hit.get("type", "something")))
	if str(hit.get("systemid", "")) != "":
		bits.append("a %s machine" % str(hit["systemid"]))
	if hit.has("powered"):
		bits.append("switched on" if bool(hit["powered"]) else "switched off")
	var text := "%s: %s, %.1f m away, %s." % [str(hit.get("label", "it")), ", ".join(bits), dist,
		SummonerView.side_words(bearing)]
	print("[Rift] inspect: %s" % text)
	return {"ok": true, "detail": text, "data": {"label": hit.get("label", ""), "type": hit.get("type", ""),
		"distance": snappedf(dist, 0.1), "powered": hit.get("powered", null)}}


func _look(payload: Dictionary) -> Dictionary:
	var point: Variant = Protocol.point_of(payload)
	if point is Vector3:
		var p: Vector3 = point
		var flat := Vector3(p.x - global_position.x, 0.0, p.z - global_position.z)
		if flat.length() > 0.01:
			rotation.y = atan2(-flat.x, -flat.z)
			study_point(p)
			return {"ok": true}
	if payload.has("yaw"):
		rotation.y = deg_to_rad(float(payload["yaw"]))
		return {"ok": true}
	if str(payload.get("target", "")) == "player":
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var f := cam.global_position - global_position
			rotation.y = atan2(-f.x, -f.z)
			attend_player(STUDY_SECONDS)
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
		# A thing in the room, by its name: walk up to it, not into it.
		var named := _resolve(payload)
		if not named.is_empty():
			var there: Vector3 = named["position"]
			var back := Vector3(global_position.x - there.x, 0.0, global_position.z - there.z)
			point = there + (back.normalized() * STOP_SHORT if back.length() > 0.01 else Vector3.ZERO)
	if not (point is Vector3):
		return {"ok": false, "detail": "no_target: nothing called '%s'" % str(payload.get("target", ""))}
	_follow = false  # an explicit walk ends following
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
