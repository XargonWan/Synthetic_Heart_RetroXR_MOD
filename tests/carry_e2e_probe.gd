## "Follow me" as the player sees it: Synth is out, the player walks into another room, and Synth is THERE, at the spawn,
## at once, with no sound and no waiting -- the same link and body carried across, nothing closed and reopened.
##
##   PROBE=carry python tests/rift_harness.py
## The room change is RetroXR's own sequence (SceneManager.scene_changed with the old room still up, then the old room
## taken out of the tree and freed, a new one added, scene_content_ready), played by hand. Lines are [probe].
extends Node

const SCENE := "res://mods/xenu.synth_rift/scenes/rift_summoner.tscn"

var _failed := 0
var _room: Node3D = null
var _pod: Node3D = null
var _camera: Camera3D = null
var _t := 0.0
var _stage := 0
var _body: Node3D = null
var _sm: Node = null


func _ready() -> void:
	_sm = get_node_or_null("/root/SceneManager")
	_check(_sm != null, "SceneManager is there to play the room change on")
	_room = _make_room("RoomA", Vector3(0.0, 0.0, 0.0))
	add_child(_room)
	# The player is not part of a room: RetroXR carries its rig across.
	_camera = Camera3D.new()
	_camera.position = Vector3(0.5, 1.5, 3.0)
	add_child(_camera)
	_camera.current = true
	_camera.look_at(Vector3(0, 1.0, 0))
	_pod = (load(SCENE) as PackedScene).instantiate()
	_room.add_child(_pod)
	await get_tree().physics_frame
	_pod.set_on(true)
	print("[probe] the pod is summoning Synth in room A")


func _make_room(room_name: String, at: Vector3) -> Node3D:
	var room := Node3D.new()
	room.name = room_name
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = at + Vector3(0, -0.5, 0)
	room.add_child(floor_body)
	return room


func _process(delta: float) -> void:
	_t += delta
	if _stage == 0 and _pod.phase() == 3:
		_stage = 1
		_body = _pod.get("_body")
		_check(_body != null and _body.visible, "Synth is out in room A")
		_cross()
	elif _t > 100.0 and _stage < 9:
		_check(false, "timeout (stage %d, phase %d, status '%s')" % [_stage, _pod.phase(), _pod.status_text()])
		_finish()


func _cross() -> void:
	var link: Node = _pod.get("_link")
	var link_before := link.get_instance_id()
	var body_before := _body.get_instance_id()
	var started := Time.get_ticks_usec()
	# What SceneManager does: say so (old room up, saved), then take the room out and free it, build the next, say it is up.
	_sm.emit_signal("scene_changed", "tardis")
	_check(_pod.get("_in_transit") == true, "they are parked for the crossing")
	_check(_pod.get_parent() == get_tree().root and _body.get_parent() == get_tree().root, "the pod and their body are on the root, out of the room's way")
	remove_child(_room)
	_room.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(is_instance_valid(_body) and is_instance_valid(_pod), "the old room is gone and THEY are not")
	_check(link.is_open(), "the link is still open: nothing was closed")
	var room_b := _make_room("RoomB", Vector3.ZERO)
	add_child(room_b)
	# The new room's own pod, as its save brings it back: idle.
	var pod_b: Node3D = (load(SCENE) as PackedScene).instantiate()
	pod_b.position = Vector3(6.0, 0.5, 6.0)
	room_b.add_child(pod_b)
	_camera.position = Vector3(-2.0, 1.5, -1.0)   # a new spawn point
	_sm.emit_signal("scene_content_ready", "tardis")
	await get_tree().process_frame
	await get_tree().process_frame
	var took := (Time.get_ticks_usec() - started) / 1000.0
	_check(_pod.get("_in_transit") == false, "the crossing is over")
	_check(_pod.get("_link").get_instance_id() == link_before and _pod.get("_body").get_instance_id() == body_before, "the same link and the same body (nothing was made again)")
	_check(_body.visible and not _body.is_ethereal() and _body.collision_layer == 1, "they are there, visible and solid, with no fade")
	var player := Vector2(_camera.global_position.x, _camera.global_position.z)
	var d := Vector2(_body.global_position.x, _body.global_position.z).distance_to(player)
	_check(d > 0.5 and d < 1.3, "at the player's side where they spawned (%.2f m)" % d)
	var facing: Vector3 = -_body.global_basis.z
	var to_p := Vector3(player.x - _body.global_position.x, 0.0, player.y - _body.global_position.z).normalized()
	_check(facing.dot(to_p) > 0.9, "turned to the player")
	var sfx: AudioStreamPlayer3D = _pod.get("_sfx")
	_check(not sfx.playing, "and not a sound (nothing is playing)")
	_check(_pod.phase() == 3, "still OPEN")
	await get_tree().create_timer(0.6).timeout
	_check(pod_b.is_on() and pod_b.get("_mirroring") == true and pod_b.phase() == 3, "the room's own capsule is ON while Synth is out (it was Off)")
	_check(pod_b.get("_screen_label").text.contains("ONLINE") and pod_b.get("_light_mat").albedo_color.g > 0.9 and pod_b.get("_beam").visible, "its screen says ONLINE, its lamp is Synth cyan and its beam is up")
	_check(pod_b.status_ok() and pod_b.status_text().begins_with("Open"), "and its menu says Open (%s)" % pod_b.status_text())
	print("[probe] the crossing took %.0f ms of frames, none of it reconnecting" % took)
	# Once more, to a room with nothing in it: the host that carries them is not tied to any room.
	_stage = 9
	_sm.emit_signal("scene_changed", "arcade")
	remove_child(room_b)
	room_b.queue_free()
	await get_tree().process_frame
	var room_c := _make_room("RoomC", Vector3.ZERO)
	add_child(room_c)
	var pod_c: Node3D = (load(SCENE) as PackedScene).instantiate()
	pod_c.position = Vector3(6.0, 0.5, -6.0)
	room_c.add_child(pod_c)
	_camera.position = Vector3(1.0, 1.5, 1.0)
	_sm.emit_signal("scene_content_ready", "arcade")
	await get_tree().process_frame
	await get_tree().process_frame
	var d2 := Vector2(_body.global_position.x, _body.global_position.z).distance_to(Vector2(1.0, 1.0))
	_check(_body.visible and d2 > 0.5 and d2 < 1.3 and link.is_open(), "and again into a third room (%.2f m, link open)" % d2)
	_check(_pod.get("_link").get_instance_id() == link_before, "still the one link")
	await get_tree().create_timer(0.6).timeout
	_check(pod_c.is_on() and pod_c.get("_mirroring") == true, "the third room's capsule is on too")
	# Touching the lit capsule (its menu's button, its screen) sends them back: the host's rift ends and the capsule goes dark.
	pod_c.set_on(false)
	await get_tree().create_timer(2.5).timeout
	_check(not is_instance_valid(_pod) or _pod.is_queued_for_deletion(), "sent back from the capsule: the carrier is gone with them")
	_check(not pod_c.is_on() and pod_c.get("_screen_label").text.contains("STANDBY") and pod_c.status_text() == "Off", "and the capsule is dark again (%s)" % pod_c.get("_screen_label").text.replace("\n", " / "))
	_finish()


func _finish() -> void:
	print("[probe] %s" % ("all ok" if _failed == 0 else "%d FAILED" % _failed))
	get_tree().quit(_failed)


func _check(ok: bool, what: String) -> void:
	print("[probe] %s: %s" % ["ok" if ok else "FAIL", what])
	if not ok:
		_failed += 1
