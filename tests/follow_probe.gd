## Where Synth would appear beside the player ("follow me"), asked of REAL physics: a floor, a player's head for a camera,
## and things set round them. FollowSpot's order is the suite's (follow_tests); this is whether the Summoner's questions
## to the physics world (floor under a spot, room for a body, a wall between) come out as it means them.
##
##   godot --headless --path RetroXR res://mods/xenu.synth_rift/tests/follow_probe.tscn
## Lines are [probe]; the exit code is the number of failures.
extends Node

const SCENE := "res://mods/xenu.synth_rift/scenes/rift_summoner.tscn"
const RiftFollow := preload("res://mods/xenu.synth_rift/scripts/rift_follow.gd")

var _failed := 0
var _summoner: Node3D = null
var _camera: Camera3D = null


func _ready() -> void:
	_solid(Vector3(0, -0.5, 0), Vector3(30, 1, 30))
	# The player at the origin, their head 1.6 m up, facing -Z. The pod is far off, so its own box is nowhere near.
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 1.6, 0)
	add_child(_camera)
	_camera.current = true
	_summoner = (load(SCENE) as PackedScene).instantiate()
	_summoner.position = Vector3(8, 0.5, 8)
	add_child(_summoner)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_run()


func _solid(at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = at
	add_child(body)
	return body


func _spot() -> Dictionary:
	await get_tree().physics_frame
	await get_tree().physics_frame
	return _summoner.call("_follow_spot")


func _run() -> void:
	var r := await _spot()
	_check(r["ok"] and (r["pos"] as Vector3).distance_to(Vector3(0.8, 0, 0)) < 0.05, "an empty room: at their right hand (%s)" % str(r.get("pos")))
	_check(is_zero_approx((r["pos"] as Vector3).y), "on the floor, not at their eyes (y=%.2f)" % (r["pos"] as Vector3).y)

	# A crate on their right, tall enough to stop a body: their left.
	var crate := _solid(Vector3(0.8, 0.5, 0), Vector3(0.5, 1.0, 0.5))
	r = await _spot()
	_check(r["ok"] and (r["pos"] as Vector3).distance_to(Vector3(-0.8, 0, 0)) < 0.05, "a crate on the right: the left (%s)" % str(r.get("pos")))

	# A low thing is left to their foot (a cartridge): it does not take the spot.
	crate.queue_free()
	var cart := _solid(Vector3(0.8, 0.03, 0), Vector3(0.3, 0.06, 0.3))
	r = await _spot()
	_check(r["ok"] and (r["pos"] as Vector3).distance_to(Vector3(0.8, 0, 0)) < 0.05, "a cartridge on the floor does not take it (%s)" % str(r.get("pos")))
	cart.queue_free()

	# A table over the spot: its top is not a floor to stand on.
	var table := _solid(Vector3(0.8, 0.8, 0), Vector3(0.7, 0.05, 0.7))
	r = await _spot()
	_check(r["ok"] and (r["pos"] as Vector3).distance_to(Vector3(0.8, 0, 0)) > 0.3, "the spot under a table is not their floor (%s)" % str(r.get("pos")))
	table.queue_free()

	# A wall a hand from them on both sides: the spot is wherever there is room, not past it.
	var wall_r := _solid(Vector3(0.5, 1.5, 0), Vector3(0.1, 3.0, 6.0))
	var wall_l := _solid(Vector3(-0.5, 1.5, 0), Vector3(0.1, 3.0, 6.0))
	r = await _spot()
	var p: Vector3 = r.get("pos", Vector3.ZERO)
	_check(r["ok"] and absf(p.x) < 0.5, "walls on both sides: behind or ahead of them, never through a wall (%s)" % str(p))
	_check(r["ok"] and (r["facing"] as Vector3).dot(Vector3(-p.x, 0, -p.z).normalized()) > 0.99, "and they face the player")
	wall_r.queue_free()
	wall_l.queue_free()

	# Over the edge of the world: no floor, no spot.
	for child in get_children():
		if child is StaticBody3D:
			child.queue_free()
	await get_tree().physics_frame
	r = await _spot()
	_check(not r["ok"], "with no floor anywhere they are not put in the air (%s)" % str(r))

	await _room_change()
	print("[probe] %s" % ("all ok" if _failed == 0 else "%d FAILED" % _failed))
	get_tree().quit(_failed)


## The player left a room with Synth out: the pod of the next room opens the rift by itself, once, and only when the option
## is on and the call is fresh. No server answers (a refused address), so what is seen is the pod starting to charge.
func _room_change() -> void:
	OS.set_environment("XENU_SYNTH_URL", "127.0.0.1:1")
	var klass: GDScript = _summoner.get_script()
	var spawn := func() -> Node3D:
		var pod: Node3D = (load(SCENE) as PackedScene).instantiate()
		pod.position = Vector3(8, 0.5, -8)
		add_child(pod)
		return pod
	var started := func(pod: Node3D) -> bool:
		var seen := [false]
		pod.connect("phase_changed", func(ph: int) -> void: seen[0] = seen[0] or ph == 1)
		await get_tree().create_timer(2.5).timeout
		return seen[0]
	var set_call := func(age_msec: int) -> void:
		klass.set("_resume_session", "abc")
		# The SAME room name as here, on purpose: RetroXR's rooms are all a node called "Root", and a name is not a room.
		klass.set("_resume_room", _summoner.call("_room_id"))
		klass.set("_resume_scene", 1)   # not this scene: another room (whose root is called "Root" too)
		RiftFollow.set_since(Time.get_ticks_msec() - age_msec)

	OS.set_environment("XENU_SYNTH_FOLLOW", "1")
	set_call.call(0)
	var pod1: Node3D = spawn.call()
	var did: bool = await started.call(pod1)
	_check(did, "follow on, a fresh call: the next room's pod opens the rift by itself")
	_check(bool(pod1.get("_followed")), "and knows it came by following")
	var pod2: Node3D = spawn.call()
	_check(not (await started.call(pod2)), "the call is used up by the first pod: a second pod stays off")

	OS.set_environment("XENU_SYNTH_FOLLOW", "0")
	set_call.call(0)
	_check(not (await started.call(spawn.call())), "follow off: no pod opens by itself")

	OS.set_environment("XENU_SYNTH_FOLLOW", "1")
	set_call.call(RiftFollow.WINDOW_MSEC + 5000)
	_check(not (await started.call(spawn.call())), "a call that went stale (the room never came) is not answered")

	# The same scene node as the one they were welcomed in: the pod was only deleted and put again, not a room change.
	set_call.call(0)
	klass.set("_resume_scene", get_tree().current_scene.get_instance_id() if get_tree().current_scene != null else 0)
	_check(not (await started.call(spawn.call())), "the room they were in (same scene node): no")

	RiftFollow.set_since(-1)
	_check(not (await started.call(spawn.call())), "no call: a pod is a pod, off until touched")

	# A room with no pod (the Tardis): RetroXR's room hook brings an invisible one. A room whose pod answered needs none.
	var hosts := func() -> Array:
		return get_tree().get_nodes_in_group("rift_summoner").filter(func(n: Node) -> bool: return n.get("host_only") == true)
	set_call.call(0)
	var pod_that_answers: Node3D = spawn.call()
	await get_tree().process_frame
	RiftFollow.on_room_ready("bedroom")
	_check(hosts.call().is_empty(), "a room whose pod took the call gets no invisible one")
	pod_that_answers.queue_free()
	set_call.call(0)
	RiftFollow.on_room_ready("tardis")
	await get_tree().process_frame
	var made: Array = hosts.call()
	_check(made.size() == 1, "a room with no pod gets one invisible Summoner (%d)" % made.size())
	if made.size() == 1:
		var host: Node3D = made[0]
		_check(not host.visible and not host.is_in_group("spawned") and host.collision_layer == 0, "invisible, not saved with the room, not touchable")
		_check(host.get("host_only") == true, "and says it is a host")
	RiftFollow.on_room_ready("tardis")
	await get_tree().process_frame
	_check(hosts.call().size() == made.size(), "the call is answered once: a second room-ready makes no second host")
	set_call.call(RiftFollow.WINDOW_MSEC + 5000)
	for h: Node in hosts.call():
		h.queue_free()
	await get_tree().process_frame
	RiftFollow.on_room_ready("tardis")
	await get_tree().process_frame
	_check(hosts.call().is_empty(), "a stale call brings no host: it does not linger into a room they come back to later")


func _check(ok: bool, what: String) -> void:
	print("[probe] %s: %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_failed += 1
