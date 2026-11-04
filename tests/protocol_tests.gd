## The rift protocol: pure, so it runs with no room, no headset and no server.
##
##   godot --headless --path RetroXR --script res://mods/xenu.synth_rift/tests/protocol_tests.gd
##
## Each case is a way the wire could go wrong: a server address spelled four ways,
## a verb that must never reach the body, a frame that is not a frame.
extends SceneTree

const Protocol := preload("res://mods/xenu.synth_rift/scripts/rift_protocol.gd")
const View := preload("res://mods/xenu.synth_rift/scripts/summoner_view.gd")

var _failed := 0
var _count := 0


func _init() -> void:
	_urls()
	_verbs()
	_frames()
	_points()
	_tls()
	_http()
	_room()
	print("[rift-tests] %d cases, %d failed" % [_count, _failed])
	# A suite that ran nothing (a script that did not compile) is not a pass.
	quit(1 if _failed > 0 or _count == 0 else 0)


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
	var clip := Protocol.audio(7, PackedByteArray([1, 2, 3, 250]), "player")
	_eq(clip, {"type": "audio", "id": 7, "format": "wav", "data": "AQID+g==", "actor": "player"}, "a voice clip frame")
	_eq(Marshalls.base64_to_raw(String(clip["data"])), PackedByteArray([1, 2, 3, 250]), "and its bytes come back whole")
	# A token with characters that would break a query string is escaped.
	_eq(Protocol.socket_url("h:1", "a b&c=d"), "ws://h:1/api/vessel/retroxr/ws?token=a%20b%26c%3Dd", "token escaped")


func _verbs() -> void:
	for verb: String in ["say", "move", "look", "use", "follow", "unfollow", "status",
			"look_at", "touch", "pick_up", "put_down", "hand_over", "sit", "emote", "inspect",
			"search", "explore", "watch", "bring", "stop"]:
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


## A Synth at home serves a self-signed certificate. Trust that, and only that: a password
## must never go to a public host that fails verification.
func _tls() -> void:
	_eq(Protocol.host_of("wss://localhost:8000/api/x?token=a"), "localhost", "host of a url")
	_eq(Protocol.host_of("ws://192.168.1.5:8080"), "192.168.1.5", "host with a port")
	_eq(Protocol.host_of("wss://[::1]:8000/x"), "::1", "an ipv6 host")
	_eq(Protocol.host_of("wss://synth.example.com/x"), "synth.example.com", "a host with no port")
	for host: String in ["localhost", "127.0.0.1", "127.1.2.3", "::1", "10.0.0.2", "192.168.1.5", "172.16.0.1",
			"172.31.255.1", "169.254.1.1", "synth.local", "nas.lan", "synthbox", "fe80::1", "fd12::1"]:
		_check(Protocol.is_private_host(host), "%s is local" % host)
	for host: String in ["", "example.com", "synth.example.com", "8.8.8.8", "172.32.0.1", "172.15.0.1",
			"192.169.1.1", "11.0.0.1", "1.2.3", "2001:db8::1"]:
		_check(not Protocol.is_private_host(host), "'%s' is not local" % host)
	_check(Protocol.trusts_unverified_tls("wss://localhost:8000/api/vessel/retroxr/ws"), "wss to localhost is trusted")
	_check(Protocol.trusts_unverified_tls("wss://192.168.1.5:8000/x"), "wss to the LAN is trusted")
	_check(not Protocol.trusts_unverified_tls("wss://synth.example.com/x"), "wss to a public host is verified")
	_check(not Protocol.trusts_unverified_tls("ws://localhost:8000/x"), "plain ws has no certificate to trust")
	# The whole path from what a player types, the way the Summoner builds it.
	_check(Protocol.trusts_unverified_tls(Protocol.socket_url("https://localhost:8000/")), "https://localhost:8000/ ends up trusted")
	_eq(Protocol.socket_url("https://localhost:8000/", ""), "wss://localhost:8000/api/vessel/retroxr/ws", "and an empty password adds no token")


## Where the skin's files are fetched from: the same server as the socket.
func _http() -> void:
	_eq(Protocol.http_base("https://localhost:8000/"), "https://localhost:8000", "https keeps its scheme")
	_eq(Protocol.http_base("wss://synth.local:9"), "https://synth.local:9", "wss is https")
	_eq(Protocol.http_base("192.168.1.5:8080"), "http://192.168.1.5:8080", "a bare address is http")
	_eq(Protocol.http_base("ws://h:1/api/x"), "http://h:1", "a path is dropped")
	_eq(Protocol.http_base(""), "", "empty")
	_eq(Protocol.http_base("http://"), "", "a scheme alone")
	_eq(Protocol.encode_path("/skins/Rei/animations/greet/Standing Greeting.fbx"),
		"/skins/Rei/animations/greet/Standing%20Greeting.fbx", "spaces are encoded, slashes are not")
	_eq(Protocol.encode_path("/skins/Rei/model.vrm"), "/skins/Rei/model.vrm", "a plain path is untouched")


func _room() -> void:
	var tv := {"name": "TV", "label": "CRT television", "type": "Node3D", "powered": false, "side": "to your left", "distance": 2.0}
	var mem := {}
	_check(View.room_changes(mem, [tv], true).is_empty(), "the first look only remembers")
	_check(View.room_changes(mem, [tv]).is_empty(), "nothing changed, nothing to tell")
	var tv_on := tv.duplicate()
	tv_on["powered"] = true
	var said := View.room_changes(mem, [tv_on])
	_check(said.size() == 1 and str(said[0]).contains("switched on") and str(said[0]).contains("CRT television"), "a machine switched on is noticed (%s)" % str(said))
	var cart := {"name": "Cart", "label": "Zelda cartridge", "type": "Node3D", "side": "ahead", "distance": 1.2}
	said = View.room_changes(mem, [tv_on, cart])
	_check(said.size() == 1 and str(said[0]).contains("Zelda cartridge") and str(said[0]).contains("appeared") and str(said[0]).contains("1.2 m"), "something put down is noticed, and where (%s)" % str(said))
	said = View.room_changes(mem, [tv_on])
	_check(said.size() == 1 and str(said[0]).contains("no longer there"), "something taken away is noticed (%s)" % str(said))
	var player := {"name": "player", "label": "the player", "type": "player", "side": "ahead", "distance": 2.0}
	_check(View.room_changes(mem, [tv_on, player]).is_empty(), "the player is not an object")
	said = View.room_changes(mem, [tv_on, player])
	_check(said.is_empty(), "and what is unchanged stays quiet")

	# Turning her head is not the room changing: a thing that left her view but still exists is out of SIGHT, said
	# nothing about, and when it comes back into view it is not "new" either.
	var mem2 := {}
	var tv2 := {"id": "TV1", "name": "TV", "label": "CRT television", "type": "TV", "side": "ahead", "distance": 2.0}
	var vase := {"id": "Vase1", "name": "Vase", "label": "vase", "type": "Node3D", "side": "ahead", "distance": 1.0}
	View.room_changes(mem2, [tv2, vase], true, ["TV1", "Vase1"])
	_check(View.room_changes(mem2, [], false, ["TV1", "Vase1"]).is_empty(), "turned away: nothing is 'no longer there' (it still exists)")
	_check(mem2.has("TV") and mem2.has("Vase"), "and she remembers them as they were")
	_check(View.room_changes(mem2, [tv2, vase], false, ["TV1", "Vase1"]).is_empty(), "turned back: they do not 'appear' again")
	said = View.room_changes(mem2, [tv2], false, ["TV1"])
	_check(said.size() == 1 and str(said[0]).contains("vase") and str(said[0]).contains("no longer there"), "a thing that stopped existing IS gone (%s)" % str(said))
	# The old rule still holds when the caller does not say what exists.
	var mem3 := {}
	View.room_changes(mem3, [tv2], true)
	_check(View.room_changes(mem3, []).size() == 1, "without the list of what exists, leaving view is leaving")
	# Cords are never news, whichever way they go.
	var cable := {"id": "Cable1", "name": "Cable", "label": "cable", "type": "cable", "side": "to your left", "distance": 1.5}
	var mem4 := {}
	_check(View.room_changes(mem4, [tv2], true).is_empty(), "first look")
	_check(View.room_changes(mem4, [tv2, cable]).is_empty(), "a cable coming into view is not told")
	_check(View.room_changes(mem4, [tv2]).is_empty() and not mem4.has("Cable"), "nor going, and it is not even remembered")
