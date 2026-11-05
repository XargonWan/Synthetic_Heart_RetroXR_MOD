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
const ChatStore := preload("res://mods/xenu.synth_rift/scripts/chat_store.gd")
const SynthNav := preload("res://mods/xenu.synth_rift/scripts/synth_nav.gd")
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
## The one-off clip they are playing (a greeting, an emote); while it plays Karada's states wait.
var _one_shot := ""
## What Synth's Karada says they are doing (idle, think, write, talk, touch): their body follows it,
## except while they walk, and again when they stop.
var _karada_state := "idle"
## Karada's presence: "summon" while a vessel is introducing them into this room (a rift opening), "" otherwise.
var _presence := ""
var _fetcher: Node = null
var _voice: AudioStreamPlayer3D = null
var _voice_queue: Array = []
var _voice_heard := 0
## Their voice has a bus of its own, with a capture on it: how loud they are right now opens their mouth.
const VOICE_BUS := "SynthVoice"
var _capture: AudioEffectCapture = null
## Set by the Summoner: (query: String) -> Dictionary of the nearest thing in the room called that
## ({name, label, type, systemid, powered, position}), or {}. "player" is handled here.
var world_lookup: Callable = Callable()
## What they see in front of their right now (the summoner knows the room): an Array of placed entities.
var sight: Callable = Callable()
## A picture from their eyes at a point, when pictures are on: a coroutine, {ok, jpeg_b64} (see take_picture).
var picture_taker: Callable = Callable()
## What they do on their own once asked (look for, fetch, watch the TV): the model is told the result afterwards.
var routines: Node = null
## Their head going now and then to something that is really there (a probe that measures their gaze switches it off).
var idle_curiosity_on := true
signal routine_done(kind: String, ok: bool, summary: String, data: Dictionary)
## Where they are looking: at the player ("player"), at a point they chose ("point"), or nowhere.
## A glance is short: the player moving or clicking earns ONE (GLANCE_SECONDS), and then they
## ignores them for GLANCE_COOLDOWN, or they would stare like a security camera. They look at the player
## for as long as they speak, and when they arrive; at a thing for as long as they study it.
const GLANCE_SECONDS := 2.2
const GLANCE_COOLDOWN := 10.0
const ARRIVAL_LOOK_SECONDS := 6.0
const STUDY_SECONDS := 5.0
## How many verbs they have been given (the probes wait for the server to finish asking).
var acts_seen := 0
var _look_kind := ""
var _look_point := Vector3.ZERO
var _look_left := 0.0
var _glance_cool := 0.0
var _noticed := false
## While they have just chosen where to look, the reflex leaves it alone until then (ticks, ms).
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
## The way round things to `_goal` (SynthNav): points to steer through, the last being the goal itself when a way
## was found; `_path_complete` false means it stops short, and arriving at its end is a walk that failed.
var _path := PackedVector3Array()
var _path_i := 0
var _path_complete := true
var _replans := 0
var _avoid: Array[Vector3] = []
const WAYPOINT_REACHED := 0.25
const MAX_REPLANS := 2
## A walk with no leash (an exploration leg, `move` with `free`): it keeps to floor (SynthNav.check_ground), keeps clear of
## the player and of anything rolling, looks a couple of metres ahead every `AHEAD_EVERY` seconds and plans round what it
## finds there, which is a good deal more than a leashed walk to a place in a room they know.
var _free_walk := false
const MAX_REPLANS_FREE := 5
const AHEAD_EVERY := 0.4
const AHEAD_METRES := 2.0
## The player is kept this far off (shrunk when they already stand nearer, or they could never step away).
const PLAYER_SPACE := 0.9
const ROLLING_SPEED := 0.4
const ROLLING_SPACE := 0.7
var _ahead_clock := 0.0
var _plan_cell := SynthNav.CELL
## A survey asks this many physics questions a frame and settles at most this many cells, in at most this many questions.
const SURVEY_QUERIES_PER_FRAME := 150
const SURVEY_MAX_CELLS := 1400
const SURVEY_MAX_QUERIES := 9000
const SURVEY_BUCKET := 1.5
const SURVEY_MIN_COST := 1.0
const SURVEY_SIGHT_RANGE := 9.0
const SURVEY_RAYS_PER_FRAME := 120
## Set by the Summoner: Callable(from, to, node, own_rid) -> bool, can `from` see `to`; and the room's name.
var line_of_sight: Callable = Callable()
var room_name := ""
var _stuck_for := 0.0
## Turning on the spot with one of the skin's turn clips (`turn_left` / `turn_right`): a body that swivels to a new
## heading without a step looks like a turret. `_turn_gained` is what the clip turns them by the time it is cut off
## (radians, + = left), added to the heading when it ends, because the clip shows the turn through the hips only.
const TURN_MIN_DEG := 40.0
var _turning := false
var _turn_left := 0.0
var _turn_clip := ""
var _turn_seconds := 0.0
var _turn_gained := 0.0
## The heading they are turning to (rotation.y), or NAN: what the standing body eases toward once a clip has done the bulk.
var _face_goal := NAN
## Set when a walk starts from standing: the first thing they do is turn to where they are going.
var _turn_first := false
var _stuck_sample := 0.0
var _last_pos := Vector3.ZERO
var _walk_elapsed := 0.0
var _walk_result: Dictionary = {}
signal _walk_finished
## Something was said, by the player or by them: the chat page redraws.
signal chat_changed
## The player wrote this to them: the Summoner sends it to Synth.
signal chat_sent(text: String)

## The mic was pressed or let go: the chat page shows whether they are listening.
signal voice_changed(recording: bool)
## The player's voice, recorded and ended (a WAV): the Summoner sends it to Synth.
signal voice_clip(wav: PackedByteArray)

const MAX_CHAT := 60
var _chat: Array = []
## Keep the log between summons (ChatStore). Off for a probe: a suite must not write the player's chat.
var persist_chat := false
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

	# Point at them and press Tab (the left thumbstick) to write to them: this is what the ray finds.
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

	# Their voice comes from their head.
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

	if _turning:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		_turn_left -= delta
		if _turn_left <= 0.0:
			_end_turn()
		return

	if _goal == null:
		velocity.x = 0.0
		velocity.z = 0.0
		move_and_slide()
		_ease_facing(delta)
		_follow_the_player(delta)
		return

	var goal: Vector3 = _goal
	var to_goal := Vector3(goal.x - global_position.x, 0.0, goal.z - global_position.z)
	_walk_elapsed += delta
	if to_goal.length() <= ARRIVE_DISTANCE:
		_end_walk(true, "arrived")
		return
	if _walk_elapsed > MOVE_TIMEOUT:
		_end_walk(false, "timeout")
		return
	# Steer through the path's points, not straight at the goal (a wall or a console in between).
	var aim := to_goal
	if not _path.is_empty():
		while _path_i < _path.size() - 1 and _flat_to(_path[_path_i]).length() < WAYPOINT_REACHED:
			_path_i += 1
		aim = _flat_to(_path[_path_i])
		if _path_i == _path.size() - 1 and aim.length() < WAYPOINT_REACHED and not _path_complete:
			_end_walk(false, "no_way_round: got as near as %.1f m to it" % to_goal.length())
			return
	var dir := aim.normalized()
	# From standing, the first thing is to turn to where they are going (a quarter turn or more takes a clip).
	if _turn_first:
		_turn_first = false
		if begin_turn(atan2(-dir.x, -dir.z)):
			return
	_set_anim("walk")
	velocity.x = dir.x * WALK_SPEED
	velocity.z = dir.z * WALK_SPEED
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), minf(1.0, 8.0 * delta))
	move_and_slide()

	if _free_walk:
		_ahead_clock += delta
		if _ahead_clock >= AHEAD_EVERY:
			_ahead_clock = 0.0
			if not _way_ahead_clear() and _replans < MAX_REPLANS_FREE:
				# Something came onto the way (the player stepped in, a thing rolled): plan round it BEFORE walking into it.
				_replans += 1
				print("[Rift] walk: something is on the way ahead, planning round it (try %d)" % _replans)
				if _plan_path(goal) and not _path.is_empty():
					return

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
		# Something the plan did not know of (it was put there, or is the player): once or twice, another way.
		if _replans < (MAX_REPLANS_FREE if _free_walk else MAX_REPLANS):
			_replans += 1
			_avoid.append(global_position + dir * 0.45)
			_stuck_for = 0.0
			print("[Rift] walk: stuck at %s, looking for another way (try %d)" % [str(global_position), _replans])
			if _plan_path(goal) and not _path.is_empty():
				return
		_end_walk(false, "blocked")


func _input(event: InputEvent) -> void:
	# A click is the player doing something: they may notice (the WebUI avatar's eyes do the same).
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		_noticed = true


## Look at the player for `seconds` (never shortens a look they are already in).
func attend_player(seconds: float) -> void:
	if _look_kind == "point" and _look_left > 0.0:
		return
	_look_kind = "player"
	_look_left = maxf(_look_left, seconds)


## Look at a point in the world they chose, for `seconds`.
func study_point(point: Vector3, seconds: float = STUDY_SECONDS) -> void:
	_look_kind = "point"
	_look_point = point
	_look_left = seconds


## The reflex: when the player moves or clicks and they are doing nothing else, they glance at the player for a
## moment, then relaxes, and does not look again for a while however much they move. Never while they
## walks (they look where they go), never right after they chose where to look; and they look at the player
## for as long as they are speaking.
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
	# Speaking to someone, they look at the player.
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


## What they are looking at right now: "player", "point" or "" (the tests read it).
func gaze_kind() -> String:
	return _look_kind if _look_left > 0.0 and is_gazing() else ""


## While they were asked to follow: keep to FOLLOW_DISTANCE of the player (inside their leash).
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
	_begin_walk(dest)


## Start walking to `dest`: the goal, and the way round things to it. False when there is no way at all.
func _begin_walk(dest: Vector3, free: bool = false) -> bool:
	_free_walk = free
	_ahead_clock = 0.0
	_turn_first = _goal == null and not _turning
	_face_goal = NAN
	_goal = dest
	collision_mask = _body_mask()
	_walk_elapsed = 0.0
	_stuck_for = 0.0
	_stuck_sample = 0.0
	_last_pos = global_position
	_replans = 0
	_avoid.clear()
	return _plan_path(dest)


## Work out the way to `dest` from here. With no way found at all the walk goes straight (as it always did) and the
## stuck check ends it; a partial way is walked to its end and then reported as a failed walk.
func _plan_path(dest: Vector3) -> bool:
	var nav := _make_nav(_free_walk)
	_plan_cell = nav.cell_size
	var t0 := Time.get_ticks_usec()
	var res := nav.plan(global_position, dest)
	if _free_walk and not bool(res["complete"]):
		# The coarse grid can lose a narrow gap (a door only just wider than they are): once more on the fine one.
		var fine := _make_nav(true, false)
		var res2 := fine.plan(global_position, dest)
		print("[Rift] walk: no full way on the coarse grid (%d questions); the fine one: %s (%d questions)" % [
			int(res["queries"]), "a way" if bool(res2["complete"]) else "none either", int(res2["queries"])])
		if bool(res2["complete"]):
			res = res2
			_plan_cell = fine.cell_size
	_path = res["path"]
	_path_i = 0
	_path_complete = bool(res["complete"])
	print("[Rift] walk: %s to %s, %d point(s), %d physics queries, %.1f ms%s" % [
		"a way" if _path_complete else "NO full way", str(dest), _path.size(), int(res["queries"]),
		float(Time.get_ticks_usec() - t0) / 1000.0, " (search capped)" if bool(res.get("capped", false)) else ""])
	return _path_complete


## A SynthNav for what stands round them now. `free`: no leash; floor under every cell; keep clear of the player and of
## things rolling about. A fresh one each time (what it caches is what the room was like when it was made).
func _make_nav(free: bool, coarse: bool = true) -> SynthNav:
	var nav := SynthNav.new()
	nav.space = get_world_3d().direct_space_state
	nav.mask = _body_mask()
	nav.exclude = [get_rid()]
	nav.floor_y = global_position.y
	nav.anchor = anchor
	nav.leash = INF if free else LEASH
	nav.avoid = _avoid
	if free:
		nav.check_ground = true
		nav.discs = _hazard_discs()
		if coarse:
			nav.cell_size = SynthNav.SURVEY_CELL
			nav.max_queries = SynthNav.FREE_MAX_QUERIES
	return nav


## How much room the player is given when they stand `distance` away: their whole space, less when they already stand
## closer (or there would be no cell they could step to).
static func player_space(distance: float) -> float:
	return minf(PLAYER_SPACE, maxf(0.3, distance - 0.1))


## Who and what to keep clear of, as {"pos", "r"}: the player (their space shrinks to what is left when they already stand
## close), and every loose body that is moving.
func _hazard_discs() -> Array:
	var out: Array = []
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		var p := Vector3(cam.global_position.x, global_position.y, cam.global_position.z)
		var d := Vector2(p.x - global_position.x, p.z - global_position.z).length()
		out.append({"pos": p, "r": player_space(d), "kind": "obstacle"})
	if is_inside_tree():
		for n: Node in get_tree().get_nodes_in_group("spawned"):
			if n is RigidBody3D and (n as RigidBody3D).linear_velocity.length() > ROLLING_SPEED:
				var rp := (n as RigidBody3D).global_position
				out.append({"pos": Vector3(rp.x, global_position.y, rp.z), "r": ROLLING_SPACE, "kind": "obstacle"})
	return out


## Is the way clear for the next `AHEAD_METRES` of the path, as the room is NOW?
func _way_ahead_clear() -> bool:
	if _path.is_empty():
		return true
	var nav := _make_nav(true, _plan_cell > SynthNav.CELL + 0.01)   # the grid the path was planned on
	nav.mark_free(global_position)
	var here := global_position
	var left := AHEAD_METRES
	var i := _path_i
	while i < _path.size() and left > 0.0:
		var to := _path[i]
		if not nav.clear_line(here, to):
			return false
		left -= Vector2(to.x - here.x, to.z - here.z).length()
		here = to
		i += 1
	return true


func _flat_to(p: Vector3) -> Vector3:
	return Vector3(p.x - global_position.x, 0.0, p.z - global_position.z)


## What their body collides with: only the world while they are still a ghost in the pod (the pod is a pickable and
## would hold them in), the world and every loose thing after. They are BLOCKED by them: with the mask on the world alone
## they walked through a console and its collider shot it across the room.
func _body_mask() -> int:
	return 1 if _ethereal else SynthNav.MASK


func _end_walk(ok: bool, detail: String) -> void:
	_goal = null
	_free_walk = false
	_path = PackedVector3Array()
	_path_i = 0
	_path_complete = true
	_anim_state = ""
	_refresh_anim()
	_stuck_for = 0.0
	_stuck_sample = 0.0
	velocity = Vector3.ZERO
	_walk_result = {"ok": ok, "detail": detail, "data": {"position": Protocol.vec(global_position)}}
	print("[Rift] walk ended: %s at %s" % [detail, str(global_position)])
	_walk_finished.emit()


## They come into view. Their own body (loaded and warmed beforehand, see KaradaPuppet.warm) fades in as ONE
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


## The reverse: their body fades out as one thing; the capsule shrinks into the floor.
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
## it, which is how a first summon sent the capsule sliding away) and see-through. They are
## like this from the moment they arrive until they are actually outside, and again on their way back in.
const ETHEREAL_FADE := 0.55
var _ethereal := false


func set_ethereal(on: bool) -> void:
	_ethereal = on
	collision_layer = 0 if on else 1
	collision_mask = _body_mask()
	_set_fade(ETHEREAL_FADE if on else 0.0)
	_refresh_anim()


func is_ethereal() -> bool:
	return _ethereal


## They become solid and opaque, over `seconds`: the moment they are really in the room.
func materialise(seconds: float) -> void:
	_ethereal = false
	# They have just stepped out and there is someone in front of them: they look at the player.
	attend_player(ARRIVAL_LOOK_SECONDS)
	var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(_set_fade, ETHEREAL_FADE, 0.0, seconds)
	await tw.finished
	collision_layer = 1
	collision_mask = _body_mask()
	_refresh_anim()


## How see-through they are: 0 solid, 1 gone (dithered per instance; a renderer that ignores it, the
## Quest's, shows their solid, which is no worse than before).
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


## Hidden until they are called out of the capsule.
func hide_until_summoned() -> void:
	_visual.visible = false


## Their real body (a KaradaPuppet, loaded from their skin) in place of the capsule. It stands on the
## floor, faces -Z like this body does, and the speech bubble moves up to their head.
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
	_replay_face()
	_bubble.position.y = float(puppet.get("height")) + 0.25
	_one_shot = ""
	_turning = false
	_face_goal = NAN
	_anim_state = ""
	_refresh_anim()
	if _ethereal:
		_set_fade(ETHEREAL_FADE)
	print("[Rift] Synth's own body is on (%.2f m)" % float(puppet.get("height")))


## Another skin: the new body takes their place where they stand, in what they were doing.
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


## Where their eyes are above the floor.
func eye_height() -> float:
	return float(_puppet.get("height")) * 0.93 if _puppet != null else 1.45


func has_puppet() -> bool:
	return _puppet != null


## Their avatar's own states, as Karada tells them (the server owns "what they are doing"): the clip of that
## name if their skin has it, else standing. A state that is not one of their clips changes nothing.
func set_karada_state(state: String) -> void:
	var before := _karada_state
	_karada_state = state if not state.is_empty() else "idle"
	# Out of a crouch they stand up (the skin's own clip for it), then do what the state says.
	if before == "crouch" and _karada_state != "crouch" and _one_shot == "" and _goal == null and _puppet != null \
			and bool(_puppet.call("has_clip", "crouch_post")):
		play_once("crouch_post")
		return
	_refresh_anim()


func karada_state() -> String:
	return _karada_state


## Karada's presence (`summon` while they are being introduced), as the server says it.
func set_presence(presence: String) -> void:
	_presence = "" if presence in ["", "idle"] else presence
	_refresh_anim()


func presence() -> String:
	return _presence


## Karada's states are what their avatar is doing in their HEAD (think, write, touch): on the WebUI that is all they do,
## so they are always shown. Here they also have a body that does things, and a person can walk and think at once:
## they show a state's clip only when they are not busy, and the activity wins otherwise (the state is remembered, so
## they go back to it when the activity ends). `summon` is the state of being introduced into a rift: it is not a
## pose of its own (a skin may ship `animations/summon/`), it is the vessel saying "they are arriving".
func is_busy() -> bool:
	return _goal != null or _one_shot != "" or _turning or _ethereal or _presence == "summon"


## The clip they rest in. Standing while busy; the state's clip (if their skin has it) when they are not.
func _rest_anim() -> String:
	if _puppet == null:
		return "idle"
	if _presence == "summon":
		return "summon" if bool(_puppet.call("has_clip", "summon")) else "idle"
	if is_busy() or _karada_state == "idle":
		return "idle"
	return _karada_state if bool(_puppet.call("has_clip", _karada_state)) else "idle"


## The clip that moves their whole body: the rest clip, unless that one only moves the upper body (a layer, below).
func _base_anim() -> String:
	var rest := _rest_anim()
	return "idle" if _is_layer(rest) else rest


## A state whose clip is a layer over the body (`mask: upper_body`) is not what they stand or sit in: it is what
## their hands do. It goes on while they walk, and on whatever they are doing with their legs. It does not go on
## while they greet, arrive or leave: those are the whole body's.
func _wanted_layer() -> String:
	if _puppet != null and _held != null and _one_shot == "" and not _ethereal and _presence != "summon" \
			and bool(_puppet.call("has_clip", "gaming")):
		return "gaming"  # their hands together in front of them: they hold something in both
	if _puppet == null or _one_shot != "" or _ethereal or _presence == "summon" or _karada_state == "idle":
		return ""
	if not bool(_puppet.call("has_clip", _karada_state)) or not _is_layer(_karada_state):
		return ""
	return _karada_state


func _is_layer(clip_name: String) -> bool:
	return _puppet != null and bool(_puppet.call("has_clip", clip_name)) \
		and str(_puppet.call("clip_mask", clip_name)) == "upper_body"


## Put the clips back to what they should be doing now, unless a walk or a one-shot has their legs.
func _refresh_anim() -> void:
	if _puppet == null:
		return
	_set_layer(_wanted_layer())
	if _goal != null or _one_shot != "" or _turning:
		return
	_set_anim(_base_anim())


## One frame from Karada.
func on_karada(kind: String, payload: Dictionary) -> void:
	match kind:
		"animation":
			set_karada_state(str(payload.get("state", "idle")))
			# The clip's own expressions (think shuts their eyes from a frame on).
			var descriptor: Variant = payload.get("descriptor", {})
			_face_state["descriptor"] = descriptor if descriptor is Dictionary else {}
			_face_call("set_descriptor", _face_state["descriptor"])
		"audio":
			_hear(payload)
		"presence":
			set_presence(str(payload.get("state", "")))
		"face":
			var values: Dictionary = payload.get("values", {}) if payload.get("values") is Dictionary else {}
			# The server repeats the same state every second or so: say it when it CHANGES, not 350 times a session.
			if values != _face_state["values"]:
				print("[Rift] Karada face: %s%s" % [str(values), "" if _puppet != null else " (no body yet: kept for it)"])
			_face_state["values"] = values
			_face_call("set_face_values", values)
		"expression":
			if str(payload.get("type", "")) == "vrm_expression_clear":
				_face_state["overlay"] = null
			else:
				print("[Rift] Karada expression: %s" % str(payload))
				_face_state["overlay"] = payload.get("targets", null)
			_face_call("set_overlay", _face_state["overlay"])
		_:
			pass  # the model is the Summoner's: it fetches the new body


## What Karada last said about their face. A frame that comes while they have no body (the pod is still charging, or a
## new skin is being built) used to be dropped, and the face stayed neutral until the server's NEXT change, which for
## an emotion is minutes away. It is kept and handed to every body they get.
var _face_state := {"values": {}, "overlay": null, "descriptor": {}}


func _replay_face() -> void:
	_face_call("set_face_values", _face_state["values"])
	_face_call("set_overlay", _face_state["overlay"])
	if not (_face_state["descriptor"] as Dictionary).is_empty():
		_face_call("set_descriptor", _face_state["descriptor"])
	print("[Rift] their face: what Karada last said is on them (%d emotion values)" % (_face_state["values"] as Dictionary).size())


## Call something on their face, if they have one.
func _face_call(method: String, arg: Variant) -> void:
	if _puppet != null and _puppet.get("face") != null:
		(_puppet.get("face") as RefCounted).call(method, arg)


## The persona's blendshape map and the rest of their face come with the model: hand them over.
func face_of() -> RefCounted:
	return _puppet.get("face") if _puppet != null else null


## The bus their voice plays on, with a capture to measure it by; made once, kept for the session.
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


## Their mouth follows how loud they are: the RMS of what their voice just played, as the WebUI measures it. Where the
## voice bus gives no signal (a device whose audio path bypasses it: nothing is measured while they are plainly
## speaking) the mouth moves by a speech-like pattern instead, which is better than a face that does not speak.
const SILENT_CAPTURE_SECONDS := 0.25
var _silent_for := 0.0
var _speech_clock := 0.0
var _fallback_logged := false
## For the tests: they are speaking though no clip plays.
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
			print("[Rift] lip sync: the voice bus measured nothing while they speak: their mouth moves by a speech-like pattern")
		_speech_clock += delta
		level = speech_pattern(_speech_clock)
	face.call("speak_level", level if speaking else 0.0)


## A mouth that opens and closes like speech: two beats a little apart, 0.02-0.3 (what a measured voice gives).
static func speech_pattern(t: float) -> float:
	return clampf(0.14 + 0.09 * sin(t * 17.0) + 0.07 * sin(t * 10.7 + 1.3), 0.02, 0.3)


func set_fetcher(fetcher: Node) -> void:
	_fetcher = fetcher


## Their voice: fetch the clip from the server and play it from their head, in order.
## A reply now comes as one clip per SENTENCE, each fetched on its own: whichever download ends first must not play
## first, so each clip takes a ticket and waits its turn to join the queue.
## Their voice is queued but not played while this is on (they are still in the capsule: the first prompt goes out at the
## welcome, so a greeting can be ready long before they are out). `release_speech()` lets it play.
var hold_speech := false
var _clip_ticket := 0
var _clip_turn := 0


func _hear(payload: Dictionary) -> void:
	var url := str(payload.get("url", ""))
	if url.is_empty() or _fetcher == null:
		return
	var mine := _clip_ticket
	_clip_ticket += 1
	var bytes: PackedByteArray = await _fetcher.call("get_fresh", url)
	while mine != _clip_turn and is_inside_tree():
		await get_tree().process_frame
	_clip_turn += 1
	if not is_inside_tree():
		return
	var stream := AudioBytes.stream_from(bytes)
	if stream == null:
		print("[Rift] their voice could not be played (%d bytes from %s)" % [bytes.size(), url])
		return
	_voice_queue.append(stream)
	print("[Rift] their voice: %.1f s, \"%s\"" % [AudioBytes.seconds_of(stream), str(payload.get("text", "")).left(60)])
	if not _voice.playing and not hold_speech:
		_next_voice()


## They are out of the capsule: what is queued is said now.
func release_speech() -> void:
	hold_speech = false
	if _voice != null and not _voice.playing:
		_next_voice()


func _next_voice() -> void:
	if _voice_queue.is_empty():
		return
	_voice.stream = _voice_queue.pop_front()
	_voice.play()
	_voice_heard += 1


func is_speaking() -> bool:
	return _voice != null and _voice.playing


## How many clips of their voice have played (the probes count them).
func voices_played() -> int:
	return _voice_heard


## What they are doing, as an animation: standing, walking. Names their skin has not got fall back
## to standing (their body then slides, which is still better than a stiff pose).
func _set_anim(state: String) -> void:
	if _puppet == null or state == _anim_state:
		return
	_anim_state = state
	if _puppet.has_method("has_clip") and bool(_puppet.call("has_clip", state)):
		_puppet.call("play", state, true)
	elif state != "idle" and bool(_puppet.call("has_clip", "idle")):
		_puppet.call("play", "idle", true)


## The layer clip over their body: `clip_name` from the hips up, or none with "".
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


## A one-off animation from their skin, then standing again (or the state they are in, when they are not busy any more).
## False when their skin has not got it.
func play_once(clip_name: String) -> bool:
	if _puppet == null or not bool(_puppet.call("has_clip", clip_name)):
		return false
	_cancel_turn()
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


## The menu they have, like every object: point at them and press Tab, and write.
func toggle_options_ui(camera: Node3D) -> void:
	ChatPanel.toggle_for(self, camera)


func chat_lines() -> Array:
	return _chat


## The player wrote to them (the page's Send): kept in the log and handed on.
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


## What Synth made of the clip: their ears' answer. The words go into the log as the player's own; a failure is a note.
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
	if persist_chat and who != "note":
		ChatStore.save_lines(_chat)
	chat_changed.emit()


## What was said in the earlier summons comes back with the body (the page shows it, Synth remembers it too).
func load_chat() -> void:
	if not persist_chat:
		return
	_chat = ChatStore.load_lines()
	print("[Rift] the chat with Synth: %d earlier line(s) are back" % _chat.size())
	chat_changed.emit()


## Forget what was said (the pod's menu): the log here, empty on the page at once.
func forget_chat() -> void:
	_chat = []
	chat_changed.emit()


func say_bubble(text: String) -> void:
	_bubble.text = text
	_bubble.visible = true
	_bubble_left = clampf(text.length() * BUBBLE_SECONDS_PER_CHAR, 3.0, 12.0)


## Answer a verb. Always returns {ok, detail, data}; never throws.
func act(action: String, payload: Dictionary) -> Dictionary:
	acts_seen += 1
	if action in ["look", "look_at", "inspect", "emote", "move"]:
		# They chose where to look or what to do: the reflex stays out of it for a while.
		_deliberate_until = Time.get_ticks_msec() + DELIBERATE_MS
		_look_left = 0.0
	# What they were doing for the model ends when the model says something else to do with their legs.
	if action in ["move", "follow"] and routines != null and routines.is_busy():
		routines.cancel("you were told to %s" % action)
	match action:
		"search", "explore", "watch", "pick_up", "hand_over", "bring", "put_down":
			return routines.start(action, payload)
		"stop":
			routines.cancel("you were told to stop")
			_follow = false
			if _goal != null:
				_end_walk(false, "stopped")   # a walk the core sent them on (an exploration leg) ends here too
			return {"ok": true, "detail": "stopped"}
		"survey":
			return await survey(payload)
		"look_around":
			return await routines.look_around(float(payload.get("seconds", 3.0)))
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


# ── a survey: what can be walked to, what is out of sight, what is in the way ───────────────────────────────────
#
# The core (Synth) decides where an exploration goes; it asks the body what it can say about where it is. This answers: the
# places there is a way to (with the length of the way), whether any point they have looked from has a line of sight to
# each, the things in front of them as places to go and study, and what to keep clear of. Read only: nothing moves.

func survey(payload: Dictionary) -> Dictionary:
	var vps: Array[Vector3] = []
	for v: Variant in payload.get("viewpoints", []):
		if v is Array and (v as Array).size() >= 3:
			vps.append(Vector3(float(v[0]), float(v[1]), float(v[2])))
	var want := clampi(int(payload.get("max", 24)), 4, 48)
	var nav := _make_nav(true)
	nav.cell_size = SynthNav.SURVEY_CELL
	var t0 := Time.get_ticks_msec()
	var st: SynthNav.ReachState = nav.reach_begin(global_position)
	while true:
		if nav.reach_step(st, SURVEY_QUERIES_PER_FRAME, SURVEY_MAX_CELLS) or nav.queries >= SURVEY_MAX_QUERIES:
			break
		await get_tree().process_frame
		if not is_inside_tree():
			return {"ok": false, "detail": "gone"}
	var cells: Dictionary = nav.reach_cells(st)
	var here := global_position
	# One place per square of SURVEY_BUCKET metres (the nearest to its middle), then an even spread of them.
	var best: Dictionary = {}
	for c: Vector2i in cells.keys():
		var cost: float = cells[c]
		if cost < SURVEY_MIN_COST:
			continue
		var centre := nav.centre_of(c)
		var key := Vector2i(floori(centre.x / SURVEY_BUCKET), floori(centre.z / SURVEY_BUCKET))
		var mid := Vector3((float(key.x) + 0.5) * SURVEY_BUCKET, 0.0, (float(key.y) + 0.5) * SURVEY_BUCKET)
		var off := Vector2(centre.x - mid.x, centre.z - mid.z).length()
		if not best.has(key) or off < float(best[key]["off"]):
			best[key] = {"pos": centre, "cost": cost, "off": off}
	var picks: Array = best.values()
	picks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["cost"]) < float(b["cost"]))
	if picks.size() > want:
		var spread: Array = []
		for k in want:
			spread.append(picks[int(float(k) * float(picks.size()) / float(want))])
		picks = spread
	# Which of them can they already see from where they have looked?
	var eye := eye_height()
	var rays := 0
	var candidates: Array = []
	for p: Dictionary in picks:
		var pos: Vector3 = p["pos"]
		var seen := false
		if line_of_sight.is_valid():
			for vp: Vector3 in vps:
				if Vector2(vp.x - pos.x, vp.z - pos.z).length() > SURVEY_SIGHT_RANGE:
					continue
				rays += 1
				if bool(line_of_sight.call(vp + Vector3(0.0, eye, 0.0), pos + Vector3(0.0, 0.9, 0.0), null, get_rid())):
					seen = true
					break
				if rays % SURVEY_RAYS_PER_FRAME == 0:
					await get_tree().process_frame
		candidates.append({"pos": Protocol.vec(pos), "cost": snappedf(float(p["cost"]), 0.1), "seen": seen})
	# Things in front of them, as places to go up to: a spot 1.2 m short of each that there is a way to.
	var pois: Array = []
	if sight.is_valid():
		for e: Dictionary in sight.call():
			if str(e.get("type", "")) == "player" or bool(e.get("held", false)):
				continue
			var ep: Vector3 = e["position"]
			var back := Vector3(here.x - ep.x, 0.0, here.z - ep.z)
			var approach := ep + (back.normalized() * 1.2 if back.length() > 0.01 else Vector3.ZERO)
			var near_cost := INF
			var near_pos := Vector3.ZERO
			var near_d := 0.8
			for c: Vector2i in cells.keys():
				var cp := nav.centre_of(c)
				var d := Vector2(cp.x - approach.x, cp.z - approach.z).length()
				if d < near_d:
					near_d = d
					near_cost = cells[c]
					near_pos = cp
			if near_cost == INF:
				continue
			pois.append({"name": str(e.get("name", "")), "pos": Protocol.vec(near_pos), "cost": snappedf(near_cost, 0.1),
				"area": room_name, "seen": true})
	var hazards: Array = []
	for d: Dictionary in _hazard_discs():
		hazards.append({"pos": Protocol.vec(d["pos"]), "radius": snappedf(float(d["r"]), 0.1), "kind": str(d.get("kind", "obstacle"))})
	var fwd := heading()
	print("[Rift] survey: %d cells reached, %d candidates (%d seen), %d things, %d hazards, %d questions, %d ms%s" % [
		cells.size(), candidates.size(), candidates.filter(func(c: Dictionary) -> bool: return bool(c["seen"])).size(),
		pois.size(), hazards.size(), nav.queries, Time.get_ticks_msec() - t0, " (capped)" if st.capped else ""])
	return {"ok": true, "detail": "surveyed", "data": {"position": Protocol.vec(global_position), "heading": atan2(fwd.z, fwd.x),
		"candidates": candidates, "pois": pois, "hazards": hazards}}


# ── what they hold ───────────────────────────────────────────────────────────
#
# A thing they pick up is carried by moving it (never by changing who owns it in the room): the object is frozen and
# eased to their hands every frame, and put back as it was when they let go. While they carry, `release_mode` is
# UNFROZEN, so that a player who takes it from their hands is not left holding something that will stay frozen in
# the air when they let go (the pickable would otherwise remember "frozen" as what to go back to).

const NOT_LIFTED := ["RetroTV", "Seat", "Table", "SpeakerPair"]
const LIFT_MAX_SIZE := 0.6

var _held: Node3D = null
var _held_name := ""
var _held_saved: Dictionary = {}


func holding() -> String:
	return _held_name if _held != null and is_instance_valid(_held) else ""


## True while they still have it: false once the player took it from their hands.
func is_holding_still() -> bool:
	return _held != null and is_instance_valid(_held)


func is_walking() -> bool:
	return _goal != null


## Why they cannot lift it, or "" when they can. A loose object (a RigidBody3D) no larger than a person carries in two hands,
## and not furniture. The size is what is DRAWN, as one box in the world: the biggest single mesh was measured before, and a
## hidden or oversized helper mesh (a glow, a pointer plate) could make a Game Boy "not something you can lift".
func lift_refusal(node: Node3D) -> String:
	if not (node is RigidBody3D):
		return "it is fixed in place, not a loose object"
	var script: Script = node.get_script()
	if script != null and str(script.get_global_name()) in NOT_LIFTED:
		return "it is furniture, too big to carry"
	if node.has_method("is_picked_up") and bool(node.call("is_picked_up")):
		return "the player is holding it"
	var size := lift_size(node)
	if size > LIFT_MAX_SIZE:
		return "it is too big to carry (%.2f m across)" % size
	return ""


## The widest side of everything visible that `node` is made of, as one box in the world (0 when nothing is drawn).
func lift_size(node: Node3D) -> float:
	var box := AABB()
	var first := true
	for m: Node in node.find_children("*", "GeometryInstance3D", true, false):
		var g := m as GeometryInstance3D
		if g == null or not g.is_visible_in_tree():
			continue
		var world := g.global_transform * g.get_aabb()
		box = world if first else box.merge(world)
		first = false
	return 0.0 if first else maxf(box.size.x, maxf(box.size.y, box.size.z))


func can_hold(node: Node3D) -> bool:
	return lift_refusal(node) == ""


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
	print("[Rift] they pick up %s" % label)
	_refresh_anim()
	return true


## Where their hands are, in the world: the middle of the two, or in front of their chest when they have no body to ask.
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
		print("[Rift] the player took %s from their hands" % _held_name)
		if _held_saved.has("release_mode") and "release_mode" in _held:
			_held.set("release_mode", _held_saved["release_mode"])
		_held = null
		_held_name = ""
		_refresh_anim()
		return
	var want := hand_point()
	_held.global_position = _held.global_position.lerp(want, minf(1.0, 12.0 * delta))


## Let go of it, on the surface under their hands in front of them (a table, the floor), as it was before they took it.
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
	print("[Rift] they put down %s" % _held_name)
	_held = null
	_held_name = ""
	_refresh_anim()


## Walk to a point; the result of the walk ({ok, detail}). The routines use this, so that they do not cancel themselves.
func walk_to(point: Vector3) -> Dictionary:
	return await _move({"x": point.x, "y": point.y, "z": point.z})


## A picture from their eyes toward `point` (see the summoner's `_take_picture`): {ok, jpeg_b64}; {ok: false} when
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
		face_yaw(atan2(-flat.x, -flat.z))


## Turn to heading `yaw` (rotation.y). With a body to show it, in a step: a turn clip for a big turn and an ease for the
## rest. Without one (a capsule, a suite) it is at once, as it always was. A walk in progress steers by itself.
func face_yaw(yaw: float) -> void:
	if _goal != null:
		return
	if _puppet == null:
		rotation.y = yaw
		return
	_face_goal = yaw
	if not _turning:
		begin_turn(yaw)


## Where they face, or will once the turn they are in is done.
func heading() -> Vector3:
	var yaw := rotation.y if is_nan(_face_goal) else _face_goal
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


func is_turning() -> bool:
	return _turning


## Start turning on the spot to heading `yaw` with the skin's turn clip, as much of it as the turn needs. False (and
## nothing done) when the turn is small, they are busy, or the skin has no such clip: the caller then eases or snaps.
func begin_turn(yaw: float) -> bool:
	if _puppet == null or _turning or _one_shot != "":
		return false
	var diff := wrapf(yaw - rotation.y, -PI, PI)
	if absf(rad_to_deg(diff)) < TURN_MIN_DEG:
		return false
	var clip := "turn_left" if diff > 0.0 else "turn_right"
	if not bool(_puppet.call("has_clip", clip)):
		return false
	var seconds := float(_puppet.call("clip_time_for_yaw", clip, absf(rad_to_deg(diff))))
	if seconds < 0.2:
		return false
	_turn_gained = deg_to_rad(float(_puppet.call("clip_yaw", clip, seconds)))
	_turn_left = seconds
	_turn_seconds = seconds
	_turn_clip = clip
	_turning = true
	_anim_state = "turn"
	_puppet.call("play", clip, false)
	print("[Rift] turn: %s for %.2f s to turn %.0f of the %.0f deg asked" % [clip, seconds, rad_to_deg(_turn_gained), rad_to_deg(diff)])
	return true


## The clip has turned them as far as it was asked to: the body takes the heading the hips showed and the pose goes on
## from there (the hips give back what the body took, so nothing swings). A turn still owed starts the next clip.
func _end_turn() -> void:
	_turning = false
	rotation.y += _turn_gained
	if _puppet != null:
		_puppet.call("shed_yaw", _turn_gained)
	_turn_gained = 0.0
	_anim_state = ""
	if not is_nan(_face_goal) and _goal == null and begin_turn(_face_goal):
		return
	_refresh_anim()


## Something else wants the body (a greeting): the turn stops where it is, the body keeping the heading the clip had reached.
func _cancel_turn() -> void:
	if not _turning:
		return
	_turn_gained = deg_to_rad(float(_puppet.call("clip_yaw", _turn_clip, _turn_seconds - maxf(_turn_left, 0.0))))
	_turning = false
	rotation.y += _turn_gained
	_puppet.call("shed_yaw", _turn_gained)
	_turn_gained = 0.0
	_anim_state = ""


## Standing: what is left of a turn after the clip, or a small one, is eased (about a third of a second).
func _ease_facing(delta: float) -> void:
	if is_nan(_face_goal):
		return
	rotation.y = lerp_angle(rotation.y, _face_goal, minf(1.0, 8.0 * delta))
	if absf(wrapf(_face_goal - rotation.y, -PI, PI)) < deg_to_rad(0.5):
		rotation.y = _face_goal
		_face_goal = NAN


## Their head goes to what they are studying; the player looks at themselves.
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
	var bearing := SummonerView.bearing_deg(global_position, heading(), pos)
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
			face_yaw(atan2(-flat.x, -flat.z))
			study_point(p)
			return {"ok": true}
	if payload.has("yaw"):
		face_yaw(deg_to_rad(float(payload["yaw"])))
		return {"ok": true}
	if str(payload.get("target", "")) == "player":
		var cam := get_viewport().get_camera_3d()
		if cam != null:
			var f := cam.global_position - global_position
			face_yaw(atan2(-f.x, -f.z))
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
	var free := bool(payload.get("free", false))   # an exploration leg: no leash (the floor under it is checked instead)
	var from_anchor := Vector3(dest.x - anchor.x, 0.0, dest.z - anchor.z)
	if not free and from_anchor.length() > LEASH:
		return {"ok": false, "detail": "too_far_from_the_summoner (limit %.0f m)" % LEASH}
	if _goal != null:
		_end_walk(false, "replaced")
	_begin_walk(dest, free)
	if _path.is_empty() and not _path_complete:
		# Nothing to walk along: boxed in. Say so rather than push at the wall for two seconds.
		_end_walk(false, "no_way_round: nothing leads from here toward it")
		return _walk_result
	await _walk_finished
	return _walk_result
