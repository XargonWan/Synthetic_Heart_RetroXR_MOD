## End-to-end probe: the mod's link, dispatch and body against a REAL Synth rift
## socket (core/vessel_retroxr_api.py). Needs a server, so it is a probe, not a test.
##
##   XENU_SYNTH_URL=127.0.0.1:8765 godot --headless --path RetroXR \
##       --script res://mods/xenu.synth_rift/tests/e2e_probe.gd
##
## The server side (scratchpad harness) drives verbs through the real connector and
## prints what came back; this side prints what the body did. Lines are [probe].
extends SceneTree

const Protocol := preload("res://mods/xenu.synth_rift/scripts/rift_protocol.gd")
const RiftLink := preload("res://mods/xenu.synth_rift/scripts/rift_link.gd")
const SynthBody := preload("res://mods/xenu.synth_rift/scripts/synth_body.gd")
const RiftDispatch := preload("res://mods/xenu.synth_rift/scripts/rift_dispatch.gd")

var _link: Node
var _body: CharacterBody3D
var _t := 0.0


func _initialize() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	root.add_child(floor_body)

	# A wall across the way, for the blocked case.
	var wall := StaticBody3D.new()
	var wshape := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(8, 3, 0.3)
	wshape.shape = wbox
	wall.add_child(wshape)
	wall.position = Vector3(0, 1.5, -3)
	root.add_child(wall)

	_body = SynthBody.new()
	_body.position = Vector3(0, 0.05, 0)
	root.add_child(_body)

	_link = RiftLink.new()
	root.add_child(_link)
	_link.opened.connect(func(w: Dictionary) -> void:
		var a: Dictionary = w.get("assets", {})
		print("[probe] opened session=%s skin=%s model=%s" % [str(w.get("session")), str(a.get("skin")),
			str((a.get("model", {}) as Dictionary).get("url"))]))
	_link.closed.connect(func(reason: String) -> void:
		print("[probe] closed: %s" % reason)
		quit(0))
	_link.action_received.connect(func(id: int, action: String, payload: Dictionary) -> void:
		print("[probe] action %d %s %s" % [id, action, str(payload)])
		await RiftDispatch.handle(_body, _link, id, action, payload))

	var url: String = Protocol.socket_url(OS.get_environment("XENU_SYNTH_URL"), OS.get_environment("XENU_SYNTH_TOKEN"))
	var hello: Dictionary = Protocol.hello("probe_room", ["motion"], ["idle", "walk"], "probe")
	if not _link.open_rift(url, hello):
		print("[probe] could not open")
		quit(1)


func _process(delta: float) -> bool:
	_t += delta
	if _t > 60.0:
		print("[probe] timeout")
		quit(2)
	return false
