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
	print("[Rift] verb #%d %s %s" % [id, action, _short(payload)])
	var res: Dictionary = await body.act(action, payload)
	print("[Rift] verb #%d %s -> %s %s" % [id, action, "ok" if bool(res.get("ok", false)) else "FAILED", str(res.get("detail", "")).left(120)])
	if not link.is_open():
		return
	link.send_frame(Protocol.result(id, bool(res.get("ok", false)), str(res.get("detail", "")),
		res.get("data", {}) if res.get("data") is Dictionary else {}))


## A payload for a log line: the text of a `say` shortened, a picture never printed.
static func _short(payload: Dictionary) -> String:
	var out := {}
	for k: Variant in payload:
		var v: Variant = payload[k]
		out[k] = (str(v).left(60) + "...") if v is String and str(v).length() > 60 else v
	return str(out)
