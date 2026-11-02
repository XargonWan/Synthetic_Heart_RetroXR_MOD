## The rift protocol: pure, so it runs with no room, no headset and no server.
##
##   godot --headless --path RetroXR --script res://mods/xenu.synth_rift/tests/protocol_tests.gd
##
## Each case is a way the wire could go wrong: a server address spelled four ways,
## a verb that must never reach the body, a frame that is not a frame.
extends SceneTree

const Protocol := preload("res://mods/xenu.synth_rift/scripts/rift_protocol.gd")

var _failed := 0
var _count := 0


func _init() -> void:
	_urls()
	_verbs()
	_frames()
	_points()
	print("[rift-tests] %d cases, %d failed" % [_count, _failed])
	quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_count += 1
	if not ok:
		_failed += 1
		print("[rift-tests] FAIL: %s" % what)


func _eq(got: Variant, want: Variant, what: String) -> void:
	_check(got == want, "%s (got %s, wanted %s)" % [what, str(got), str(want)])


func _urls() -> void:
	var want := "ws://192.168.1.5:8080/api/vessel/retroxr/ws"
	for spelling: String in ["192.168.1.5:8080", "http://192.168.1.5:8080", "ws://192.168.1.5:8080/",
			"http://192.168.1.5:8080/some/page", "  192.168.1.5:8080  "]:
		_eq(Protocol.socket_url(spelling), want, "address '%s'" % spelling)
	_eq(Protocol.socket_url("https://synth.example"), "wss://synth.example/api/vessel/retroxr/ws", "https -> wss")
	_eq(Protocol.socket_url("wss://synth.example:9"), "wss://synth.example:9/api/vessel/retroxr/ws", "wss kept")
	_eq(Protocol.socket_url(""), "", "empty address")
	_eq(Protocol.socket_url("http://"), "", "scheme only")
	# A token with characters that would break a query string is escaped.
	_eq(Protocol.socket_url("h:1", "a b&c=d"), "ws://h:1/api/vessel/retroxr/ws?token=a%20b%26c%3Dd", "token escaped")


func _verbs() -> void:
	for verb: String in ["say", "move", "look", "use", "follow", "unfollow", "status",
			"look_at", "touch", "pick_up", "put_down", "hand_over", "sit", "emote", "inspect"]:
		_check(Protocol.is_known_verb(verb), "%s is a verb" % verb)
	# The body never plays: nothing that reaches a console is a verb.
	for verb: String in ["press_button", "play", "set_input", "attack", "respawn", "", "Say", "say "]:
		_check(not Protocol.is_known_verb(verb), "'%s' must not be a verb" % verb)


func _frames() -> void:
	var hello: Dictionary = Protocol.hello("den", ["motion"], ["walk"], "0.1.0")
	_eq(hello["type"], "hello", "hello type")
	_eq(hello["protocol"], 1, "hello protocol")
	_eq(hello["animations"], ["walk"], "hello animations")

	var ev: Dictionary = Protocol.event("touch", "hand", "player", 0.9, {"part": "hand"})
	_eq([ev["actor"], ev["salience"], ev["data"]["part"]], ["player", 0.9, "hand"], "event fields")
	var bare: Dictionary = Protocol.event("spawn", "x")
	_check(not bare.has("actor") and not bare.has("salience"), "no actor/salience unless given")

	var st: Dictionary = Protocol.state(Vector3(1.234, 0, -2.0), "cart", {"entities": []})
	_eq(st["state"]["position"], {"x": 1.23, "y": 0.0, "z": -2.0}, "state position rounds")
	_eq(st["state"]["holding"], "cart", "state holding")

	var res: Dictionary = Protocol.result(7, false, "blocked", {"n": 1})
	_eq([res["id"], res["ok"], res["detail"]], [7, false, "blocked"], "result fields")

	for bad: String in ["", "not json", "[]", "42", "{}", "{\"type\": \"\"}", "{\"type\": 3}", "{\"id\": 1}"]:
		_check(Protocol.parse(bad).is_empty(), "'%s' is not a frame" % bad)
	_eq(Protocol.parse("{\"type\":\"welcome\",\"session\":\"s\"}")["session"], "s", "a frame parses")


func _points() -> void:
	_eq(Protocol.point_of({"x": 1, "y": 0.5, "z": 2}), Vector3(1, 0.5, 2), "xyz payload")
	_eq(Protocol.point_of({"x": 1, "z": 2}), Vector3(1, 0, 2), "y defaults to 0")
	_eq(Protocol.point_of({"position": {"x": 3, "z": 4}}), Vector3(3, 0, 4), "nested position")
	_eq(Protocol.point_of({"target": "1.5,0,-2"}), Vector3(1.5, 0, -2), "'x,y,z' target")
	_check(Protocol.point_of({"target": "player"}) == null, "a name is not a point")
	_check(Protocol.point_of({"target": "a,b,c"}) == null, "garbage is not a point")
	_check(Protocol.point_of({}) == null, "empty payload")
