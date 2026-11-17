## "Follow me" through the REAL link: the player left a room with Synth out, and the pod of the room they enter opens the
## rift by itself and Synth appears BESIDE THE PLAYER (not out of the capsule), whether or not the server kept the session.
##
##   PROBE=follow python tests/rift_harness.py            # the server began a NEW session (its own idle timeout)
##   PROBE=follow PROBE_EXPECT=resumed python tests/rift_harness.py   # the server kept it
## The room: a floor, a pod at the origin (its front is +Z) and a player 6 m away at the far side of it, so beside the
## player and out of the pod's front are told apart by where they stand. Lines are [probe]; exit code = failures.
extends Node

const SCENE := "res://mods/xenu.synth_rift/scenes/rift_summoner.tscn"

var _failed := 0
var _pod: Node3D = null
var _camera: Camera3D = null
var _t := 0.0
var _done := false
var _expect := ""
var _ghost := false
const RiftFollow := preload("res://mods/xenu.synth_rift/scripts/rift_follow.gd")


func _ready() -> void:
	_expect = OS.get_environment("PROBE_EXPECT")
	_ghost = OS.get_environment("PROBE_GHOST") == "1"
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)
	_camera = Camera3D.new()
	_camera.position = Vector3(4.0, 1.5, 4.0)
	add_child(_camera)
	_camera.current = true
	_camera.look_at(Vector3(0, 1.0, 0))

	# What the last room left behind: a session to pick up, from ANOTHER scene node (its name need not differ), just now.
	var sample: Node = (load(SCENE) as PackedScene).instantiate()
	var klass: GDScript = sample.get_script()
	sample.free()
	klass.set("_resume_session", "harness-1" if _expect == "resumed" else "an-old-session-the-server-forgot")
	klass.set("_resume_room", "arcade")
	klass.set("_resume_scene", 1)
	RiftFollow.set_since(Time.get_ticks_msec())
	if _ghost:
		# No pod in this room: RetroXR's room hook brings one of its own, invisible.
		RiftFollow.on_room_ready("tardis")
		await get_tree().process_frame
		for pod in get_tree().get_nodes_in_group("rift_summoner"):
			_pod = pod
	else:
		_pod = (load(SCENE) as PackedScene).instantiate()
		add_child(_pod)
	print("[probe] %s in a new room; expect='%s'" % ["no pod, an invisible one" if _ghost else "a pod", _expect])


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if _pod == null:
		return
	if _pod.phase() == 3:   # OPEN
		_done = true
		_check_arrival()
		return
	if _t > float(OS.get_environment("PROBE_TIMEOUT") if OS.get_environment("PROBE_TIMEOUT") != "" else "100"):
		_check(false, "timeout (phase %d, status '%s')" % [_pod.phase(), _pod.status_text()])
		_finish()


func _check_arrival() -> void:
	var body: Node3D = _pod.get("_body")
	_check(_pod.get("_followed") == true, "it came because they followed (not a touch on the screen)")
	if _ghost:
		_check(_pod.get("host_only") == true and not _pod.visible and not _pod.is_in_group("spawned"), "the pod is an invisible host, and not one the room would save")
		_check(_pod.collision_layer == 0, "nothing can grab or hit it")
	_check(_pod.get("_resumed") == (_expect == "resumed"), "the server %s the session (resumed=%s)" % ["kept" if _expect == "resumed" else "began a new", str(_pod.get("_resumed"))])
	_check(_pod.get("_beside") == true, "they appeared beside the player")
	_check(body != null, "there is a body")
	if body != null:
		var player := Vector3(_camera.global_position.x, 0.0, _camera.global_position.z)
		var from_player := Vector2(body.global_position.x - player.x, body.global_position.z - player.z).length()
		var from_pod := Vector2(body.global_position.x - _pod.global_position.x, body.global_position.z - _pod.global_position.z).length()
		_check(from_player > 0.5 and from_player < 1.3, "an arm's length from the player (%.2f m)" % from_player)
		if not _ghost:
			_check(from_pod > 4.0, "and nowhere near the pod (%.2f m)" % from_pod)
		var facing: Vector3 = -body.global_basis.z
		var to_player := (player - body.global_position)
		to_player.y = 0.0
		_check(facing.dot(to_player.normalized()) > 0.9, "turned to the player (dot %.2f)" % facing.dot(to_player.normalized()))
	_finish()


func _finish() -> void:
	print("[probe] %s" % ("all ok" if _failed == 0 else "%d FAILED" % _failed))
	get_tree().quit(_failed)


func _check(ok: bool, what: String) -> void:
	print("[probe] %s: %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_failed += 1
