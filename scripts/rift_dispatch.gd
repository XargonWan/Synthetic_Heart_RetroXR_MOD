## RiftDispatch -- one verb from Synth, from the socket to the body and back.
##
## Static and free of the Summoner so a probe drives exactly what the room runs.
## The rule it enforces: a verb that is not on the list never reaches the body.
## The body does not play, and nothing here writes input to a console.
extends RefCounted

const Protocol := preload("res://mods/xenu.synth_rift/scripts/rift_protocol.gd")


static func handle(body: Node, link: Node, id: int, action: String, payload: Dictionary) -> void:
	if not Protocol.is_known_verb(action):
		print("[Rift] refused unknown verb %s" % action)
		link.send_frame(Protocol.result(id, false, "unknown_verb: " + action))
		return
	if body == null or not is_instance_valid(body):
		link.send_frame(Protocol.result(id, false, "no_body"))
		return
	var res: Dictionary = await body.act(action, payload)
	if not link.is_open():
		return
	link.send_frame(Protocol.result(id, bool(res.get("ok", false)), str(res.get("detail", "")),
		res.get("data", {}) if res.get("data") is Dictionary else {}))
