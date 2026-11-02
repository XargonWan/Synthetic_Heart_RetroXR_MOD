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
var _visual: MeshInstance3D = null
var _bubble_left := 0.0
var _goal: Variant = null  # Vector3 while walking
var _stuck_for := 0.0
var _stuck_sample := 0.0
var _last_pos := Vector3.ZERO
var _walk_elapsed := 0.0
var _walk_result: Dictionary = {}
signal _walk_finished


func _ready() -> void:
	var capsule := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.22
	mesh.height = 1.55
	capsule.mesh = mesh
	capsule.position.y = 0.775
	capsule.name = "Visual"
	_visual = capsule
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
	_bubble.pixel_size = 0.003
	_bubble.font_size = 48
	_bubble.outline_size = 12
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.no_depth_test = true
	_bubble.visible = false
	_bubble.width = 900
	_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_bubble)
	_last_pos = global_position


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
	var mat := _visual.mesh.material as StandardMaterial3D
	mat.emission_energy_multiplier = 3.0
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_visual, "scale", Vector3.ONE, seconds)
	tw.tween_property(mat, "emission_energy_multiplier", 0.4, seconds * 1.4)
	await tw.finished


## The reverse: it shrinks into the floor and is gone.
func disappear(seconds: float) -> void:
	var mat := _visual.mesh.material as StandardMaterial3D
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(_visual, "scale", Vector3(0.05, 0.02, 0.05), seconds)
	tw.tween_property(mat, "emission_energy_multiplier", 3.0, seconds)
	await tw.finished
	_visual.visible = false


## Hidden until she is called out of the capsule.
func hide_until_summoned() -> void:
	_visual.visible = false


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
			return {"ok": true, "detail": "spoken"}
		"status":
			return {"ok": true, "data": {"position": Protocol.vec(global_position)}}
		"look":
			return _look(payload)
		"move":
			return await _move(payload)
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
