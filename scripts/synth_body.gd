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
const SynthRoutines := preload("res://mods/xenu.synth_rift/scripts/synth_routines.gd")
const WorldView := preload("res://mods/xenu.synth_rift/scripts/world_view.gd")
const AudioBytes := preload("res://mods/xenu.synth_rift/scripts/audio_bytes.gd")
const VoiceRecorder := preload("res://mods/xenu.synth_rift/scripts/voice_recorder.gd")

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
## The clip playing as a layer over the base one ("" for none): a game played with the hands, whatever the legs do.
var _overlay_state := ""
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
## What she sees in front of her right now (the summoner knows the room): an Array of placed entities.
var sight: Callable = Callable()
## A picture from her eyes at a point, when pictures are on: a coroutine, {ok, jpeg_b64} (see take_picture).
var picture_taker: Callable = Callable()
## What she does on her own once asked (look for, fetch, watch the TV): the model is told the result afterwards.
var routines: Node = null
## Her head going now and then to something that is really there (a probe that measures her gaze switches it off).
var idle_curiosity_on := true
signal routine_done(kind: String, ok: bool, summary: String, data: Dictionary)
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

## The mic was pressed or let go: the chat page shows whether she is listening.
signal voice_changed(recording: bool)
## The player's voice, recorded and ended (a WAV): the Summoner sends it to Synth.
signal voice_clip(wav: PackedByteArray)

const MAX_CHAT := 60
var _chat: Array = []
var _recorder := VoiceRecorder.new()


func _ready() -> void:
	routines = SynthRoutines.new()
	routines.name = "Routines"
	routines.body = self
	routines.done.connect(func(kind: String, ok: bool, summary: String, data: Dictionary) -> void: routine_done.emit(kind, ok, summary, data))
	add_child(routines)
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
	if _recorder.is_recording() and _recorder.seconds() >= VoiceRecorder.MAX_SECONDS:
		print("[Rift] voice: %.0f s is the longest a clip goes; sending what was said" % VoiceRecorder.MAX_SECONDS)
		toggle_voice()


func _physics_process(delta: float) -> void:
	_update_gaze(delta)
	_carry(delta)
	if idle_curiosity_on:
		routines.idle_curiosity(delta, is_speaking())
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


## Where her eyes are above the floor.
func eye_height() -> float:
	return float(_puppet.get("height")) * 0.93 if _puppet != null else 1.45


func has_puppet() -> bool:
	return _puppet != null


## Her avatar's own states, as Karada tells them (the server owns "what she is doing"): the clip of that
## name if her skin has it, else standing. A state that is not one of her clips changes nothing.
func set_karada_state(state: String) -> void:
	var before := _karada_state
	_karada_state = state if not state.is_empty() else "idle"
	# Out of a crouch she stands up (the skin's own clip for it), then does what the state says.
	if before == "crouch" and _karada_state != "crouch" and _one_shot == "" and _goal == null and _puppet != null \
			and bool(_puppet.call("has_clip", "crouch_post")):
		play_once("crouch_post")
		return
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


## The clip that moves her whole body: the rest clip, unless that one only moves the upper body (a layer, below).
func _base_anim() -> String:
	var rest := _rest_anim()
	return "idle" if _is_layer(rest) else rest


## A state whose clip is a layer over the body (`mask: upper_body`) is not what she stands or sits in: it is what
## her hands do. It goes on while she walks, and on whatever she is doing with her legs. It does not go on
## while she greets, arrives or leaves: those are the whole body's.
func _wanted_layer() -> String:
	if _puppet != null and _held != null and _one_shot == "" and not _ethereal and _presence != "summon" \
			and bool(_puppet.call("has_clip", "gaming")):
		return "gaming"  # her hands together in front of her: she holds something in both
	if _puppet == null or _one_shot != "" or _ethereal or _presence == "summon" or _karada_state == "idle":
		return ""
	if not bool(_puppet.call("has_clip", _karada_state)) or not _is_layer(_karada_state):
		return ""
	return _karada_state


func _is_layer(clip_name: String) -> bool:
	return _puppet != null and bool(_puppet.call("has_clip", clip_name)) \
		and str(_puppet.call("clip_mask", clip_name)) == "upper_body"


## Put the clips back to what she should be doing now, unless a walk or a one-shot has her legs.
func _refresh_anim() -> void:
	if _puppet == null:
		return
	_set_layer(_wanted_layer())
	if _goal != null or _one_shot != "":
		return
	_set_anim(_base_anim())


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


## Her mouth follows how loud she is: the RMS of what her voice just played, as the WebUI measures it. Where the
## voice bus gives no signal (a device whose audio path bypasses it: nothing is measured while she is plainly
## speaking) the mouth moves by a speech-like pattern instead, which is better than a face that does not speak.
const SILENT_CAPTURE_SECONDS := 0.25
var _silent_for := 0.0
var _speech_clock := 0.0
var _fallback_logged := false
## For the tests: she is speaking though no clip plays.
var _force_speaking := false


func _lip_sync() -> void:
	var face := face_of()
	if face == null:
		return
	var speaking := (_voice != null and _voice.playing) or _force_speaking
	var level := 0.0
	if _capture != null:
		var frames := _capture.get_frames_available()
		if frames > 0:
			var buffer := _capture.get_buffer(frames)
			var sum := 0.0
			for f in buffer:
				sum += (f.x * f.x + f.y * f.y) * 0.5
			level = sqrt(sum / float(buffer.size()))
	var delta := get_process_delta_time()
	if speaking and level < 0.002:
		_silent_for += delta
	else:
		_silent_for = 0.0
	if speaking and _silent_for > SILENT_CAPTURE_SECONDS:
		if not _fallback_logged:
			_fallback_logged = true
			print("[Rift] lip sync: the voice bus measured nothing while she speaks: her mouth moves by a speech-like pattern")
		_speech_clock += delta
		level = speech_pattern(_speech_clock)
	face.call("speak_level", level if speaking else 0.0)


## A mouth that opens and closes like speech: two beats a little apart, 0.02-0.3 (what a measured voice gives).
static func speech_pattern(t: float) -> float:
	return clampf(0.14 + 0.09 * sin(t * 17.0) + 0.07 * sin(t * 10.7 + 1.3), 0.02, 0.3)


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


## The layer clip over her body: `clip_name` from the hips up, or none with "".
func _set_layer(clip_name: String) -> void:
	if _puppet == null or clip_name == _overlay_state:
		return
	_overlay_state = clip_name
	if clip_name == "":
		_puppet.call("stop_over")
	elif not bool(_puppet.call("play_over", clip_name)):
		_overlay_state = ""


func layer() -> String:
	return _overlay_state


## A one-off animation from her skin, then standing again (or the state she is in, when she is not busy any more).
## False when her skin has not got it.
func play_once(clip_name: String) -> bool:
	if _puppet == null or not bool(_puppet.call("has_clip", clip_name)):
		return false
	_one_shot = clip_name
	_anim_state = ""
	_set_layer("")
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


func voice_recording() -> bool:
	return _recorder.is_recording()


## The mic of the chat page: first press starts listening, the next ends it and sends what was said.
func toggle_voice() -> void:
	if _recorder.is_recording():
		var wav := _recorder.stop()
		voice_changed.emit(false)
		if wav.is_empty():
			_log_chat("note", "I heard nothing. Is the microphone switched on in the options?")
			return
		voice_clip.emit(wav)
		return
	_recorder.head_source = func() -> Vector3:
		var cam := get_viewport().get_camera_3d()
		return cam.global_position if cam != null else global_position
	if _recorder.start(get_tree()):
		voice_changed.emit(true)
	else:
		_log_chat("note", "There is no microphone to listen with.")


## What Synth made of the clip: her ears' answer. The words go into the log as the player's own; a failure is a note.
func heard(ok: bool, text: String, reason: String) -> void:
	if ok and not text.is_empty():
		_log_chat("you", text)
		return
	var why := {
		"no_stt": "Synth has no speech recognition set up.",
		"nothing_heard": "I could not make out any words.",
		"too_long": "That was too long to send.",
		"stt_failed": "The speech recognition failed.",
		"bad_clip": "That recording could not be read.",
	}
	_log_chat("note", str(why.get(reason, "I could not hear that (%s)." % reason)))


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
	# What she was doing for the model ends when the model says something else to do with her legs.
	if action in ["move", "follow"] and routines != null and routines.is_busy():
		routines.cancel("you were told to %s" % action)
	match action:
		"search", "explore", "watch", "pick_up", "hand_over", "bring", "put_down":
			return routines.start(action, payload)
		"stop":
			routines.cancel("you were told to stop")
			return {"ok": true, "detail": "stopped"}
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


# ── what she holds ───────────────────────────────────────────────────────────
#
# A thing she picks up is carried by moving it (never by changing who owns it in the room): the object is frozen and
# eased to her hands every frame, and put back as it was when she lets go. While she carries, `release_mode` is
# UNFROZEN, so that a player who takes it from her hands is not left holding something that will stay frozen in
# the air when they let go (the pickable would otherwise remember "frozen" as what to go back to).

const NOT_LIFTED := ["RetroTV", "Seat", "Table", "SpeakerPair"]
const LIFT_MAX_SIZE := 0.6

var _held: Node3D = null
var _held_name := ""
var _held_saved: Dictionary = {}


func holding() -> String:
	return _held_name if _held != null and is_instance_valid(_held) else ""


## True while she still has it: false once the player took it from her hands.
func is_holding_still() -> bool:
	return _held != null and is_instance_valid(_held)


func is_walking() -> bool:
	return _goal != null


## Can she lift it? A loose object (a RigidBody3D) no larger than a person carries in two hands, and not furniture.
func can_hold(node: Node3D) -> bool:
	if not (node is RigidBody3D):
		return false
	var script: Script = node.get_script()
	if script != null and str(script.get_global_name()) in NOT_LIFTED:
		return false
	var top := -INF
	var big := 0.0
	for m: Node in node.find_children("*", "GeometryInstance3D", true, false):
		var box := (m as GeometryInstance3D).get_aabb().size * (m as Node3D).global_transform.basis.get_scale()
		big = maxf(big, maxf(box.x, maxf(box.y, box.z)))
	return big <= LIFT_MAX_SIZE and not (node.has_method("is_picked_up") and bool(node.call("is_picked_up")))


func hold(node: Node3D, label: String) -> bool:
	if _held != null or not can_hold(node):
		return false
	var rb := node as RigidBody3D
	_held_saved = {"freeze": rb.freeze, "layer": rb.collision_layer, "mask": rb.collision_mask}
	if "release_mode" in rb:
		_held_saved["release_mode"] = rb.get("release_mode")
		rb.set("release_mode", 0)  # XRToolsPickable.ReleaseMode.UNFROZEN
	rb.freeze = true
	rb.collision_layer = 0
	rb.collision_mask = 0
	_held = rb
	_held_name = label
	print("[Rift] she picks up %s" % label)
	_refresh_anim()
	return true


## Where her hands are, in the world: the middle of the two, or in front of her chest when she has no body to ask.
func hand_point() -> Vector3:
	if _puppet != null and _puppet.has_method("hand_point"):
		return _puppet.call("hand_point") as Vector3
	return global_position + Vector3(0.0, 1.0, 0.0) - global_basis.z * 0.35


func _carry(delta: float) -> void:
	if _held == null:
		return
	if not is_instance_valid(_held):
		_held = null
		_held_name = ""
		_refresh_anim()
		return
	if _held.has_method("is_picked_up") and bool(_held.call("is_picked_up")):
		# The player has it. Its own bookkeeping is theirs now; only give back what we changed that they do not.
		print("[Rift] the player took %s from her hands" % _held_name)
		if _held_saved.has("release_mode") and "release_mode" in _held:
			_held.set("release_mode", _held_saved["release_mode"])
		_held = null
		_held_name = ""
		_refresh_anim()
		return
	var want := hand_point()
	_held.global_position = _held.global_position.lerp(want, minf(1.0, 12.0 * delta))


## Let go of it, on the surface under her hands in front of her (a table, the floor), as it was before she took it.
func put_down() -> void:
	if _held == null:
		return
	var node := _held
	if is_instance_valid(node):
		var from := hand_point() - global_basis.z * 0.25
		var query := PhysicsRayQueryParameters3D.create(from + Vector3(0, 0.1, 0), from + Vector3(0, -2.0, 0))
		query.collision_mask = 0xFFFFFFFF & ~(1 << 20)
		query.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		node.global_position = ((hit["position"] as Vector3) + Vector3(0, 0.08, 0)) if hit.has("position") else from
		var rb := node as RigidBody3D
		rb.collision_layer = int(_held_saved.get("layer", rb.collision_layer))
		rb.collision_mask = int(_held_saved.get("mask", rb.collision_mask))
		rb.freeze = bool(_held_saved.get("freeze", false))
		if _held_saved.has("release_mode") and "release_mode" in rb:
			rb.set("release_mode", _held_saved["release_mode"])
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		rb.sleeping = false
	print("[Rift] she puts down %s" % _held_name)
	_held = null
	_held_name = ""
	_refresh_anim()


## Walk to a point; the result of the walk ({ok, detail}). The routines use this, so that they do not cancel themselves.
func walk_to(point: Vector3) -> Dictionary:
	return await _move({"x": point.x, "y": point.y, "z": point.z})


## A picture from her eyes toward `point` (see the summoner's `_take_picture`): {ok, jpeg_b64}; {ok: false} when
## pictures are not wired (no window, a headless run) or switched off.
func take_picture(point: Vector3) -> Dictionary:
	if not picture_taker.is_valid():
		return {"ok": false, "detail": "no_camera"}
	return await picture_taker.call(point)


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
