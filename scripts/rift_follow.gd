## RiftFollow -- "follow me": Synth comes with the player into ANY other room, pod or no pod.
##
## A Summoner (`_exit_tree`) that is freed with the rift up and the option on calls `leaving()`. The next room to finish
## loading is told by RetroXR (`ModApi.on_scene_content_ready`, registered in mod_main.gd), and by then every pod the room
## saved has been readied and has had its chance to take the call (`take()`); if none did, this puts one invisible pod of
## its own in the room (the HOST: it keeps the link, the body and the state exactly as a pod does, and nothing of it is
## drawn, grabbed or saved). Either way the call is answered ONCE and never kept for a later room: a call that lingered
## brought Synth back every time the player walked into a room they had left (the first version kept it two minutes).
##
## Static and node-free, like the other views, so the headless probes drive what the room runs.
extends RefCounted

const SUMMONER_SCENE := "res://mods/xenu.synth_rift/scenes/rift_summoner.tscn"
const RiftSettings := preload("res://mods/xenu.synth_rift/scripts/rift_settings.gd")
## The longest a call waits for a room to come (a room is a few seconds to load; this is a safety net for a RetroXR with no
## room hook, where only a pod's own `_ready` can answer it).
const WINDOW_MSEC := 60000

static var _since := -1


## The rift was up and the player left the room: the next room brings them.
static func leaving() -> void:
	_since = Time.get_ticks_msec()


## Is there a call to answer that is still fresh? Does not answer it.
static func pending() -> bool:
	return _since >= 0 and Time.get_ticks_msec() - _since <= WINDOW_MSEC


## Answer the call: true when there was a fresh one (and the player still wants it), and there is none afterwards.
static func take() -> bool:
	var fresh := pending()
	_since = -1
	return fresh and RiftSettings.follow_me_on()


## The Summoner that holds the rift for Synth when it is NOT this room's pod: the invisible host that carried them in (see
## `host_only`), or null. A pod of the room shows this one's rift as its own (`RiftSummoner._mirror_tick`).
static func carrier(tree: SceneTree, except: Node = null) -> Node:
	if tree == null:
		return null
	for pod: Node in tree.get_nodes_in_group("rift_summoner"):
		if pod != except and pod.get("host_only") == true and pod.has_method("is_on") and bool(pod.call("is_on")):
			return pod
	return null


## For the probes: the call as it is, set or cleared.
static func set_since(msec: int) -> void:
	_since = msec


## RetroXR says a room is up and its objects are back. A pod of its own has taken the call by now; if nobody did, a host.
static func on_room_ready(_scene_id: String = "") -> void:
	if not pending():
		_since = -1
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return
	if not take():
		return
	var host: Node3D = (load(SUMMONER_SCENE) as PackedScene).instantiate()
	# Before it enters the tree: its _ready reads this.
	host.set("host_only", true)
	var scene := tree.current_scene
	scene.add_child(host)
	var cam := scene.get_viewport().get_camera_3d()
	if cam != null:
		# At the player's feet, its front the way they face: only where it would step out if no spot beside them is free.
		var fwd := -cam.global_basis.z
		host.global_position = cam.global_position - Vector3(0.0, 1.5, 0.0)
		host.global_rotation.y = atan2(fwd.x, fwd.z) if Vector2(fwd.x, fwd.z).length() > 0.05 else 0.0
	print("[Rift] follow me: this room has no Summoner, an invisible one brings them")
