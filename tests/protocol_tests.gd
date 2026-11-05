## The rift protocol: pure, so it runs with no room, no headset and no server.
##
##   godot --headless --path RetroXR --script res://mods/xenu.synth_rift/tests/protocol_tests.gd
##
## Each case is a way the wire could go wrong: a server address spelled four ways,
## a verb that must never reach the body, a frame that is not a frame.
extends SceneTree

const Protocol := preload("res://mods/xenu.synth_rift/scripts/rift_protocol.gd")
const View := preload("res://mods/xenu.synth_rift/scripts/summoner_view.gd")
const ChatStore := preload("res://mods/xenu.synth_rift/scripts/chat_store.gd")
const RiftSettings := preload("res://mods/xenu.synth_rift/scripts/rift_settings.gd")

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
	_resume()
	_chat_memory()
	_synth_name()
	_screen()
	print("[rift-tests] %d cases, %d failed" % [_count, _failed])
	# A suite that ran nothing (a script that did not compile) is not a pass.
	quit(1 if _failed > 0 or _count == 0 else 0)


## The chat labels them with what the server calls them, and falls back to SyntH when none was offered.
func _synth_name() -> void:
	var before := RiftSettings.synth_name()
	RiftSettings.set_synth_name("")
	_check(RiftSettings.synth_name() == "SyntH", "no name offered: SyntH")
	RiftSettings.set_synth_name("  Rei ")
	_check(RiftSettings.synth_name() == "Rei", "the offered name, trimmed")
	RiftSettings.set_synth_name("")
	_check(RiftSettings.synth_name() == "SyntH", "a server that stops offering one brings the default back")
	RiftSettings.set_synth_name("" if before == "SyntH" else before)


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
	_eq(Protocol.persona_urls({"skin": "Rei", "persona": {"url": "/skins/Rei/persona.json"}}, "/avatars/model_x.vrm"),
		["/skins/Rei/persona.json", "/avatars/persona.json"], "the persona the server names first, no repeats")
	_eq(Protocol.persona_urls({"skin": "Rei"}, "/avatars/model_x.vrm"), ["/avatars/persona.json", "/skins/Rei/persona.json"],
		"a model in /avatars/ still finds the skin's persona")
	_eq(Protocol.persona_urls({}, ""), [], "nothing known, nothing to try")
	var clip := Protocol.audio(7, PackedByteArray([1, 2, 3, 250]), "player")
	_eq(clip, {"type": "audio", "id": 7, "format": "wav", "data": "AQID+g==", "actor": "player"}, "a voice clip frame")
	_eq(Marshalls.base64_to_raw(String(clip["data"])), PackedByteArray([1, 2, 3, 250]), "and its bytes come back whole")
	# A token with characters that would break a query string is escaped.
	_eq(Protocol.socket_url("h:1", "a b&c=d"), "ws://h:1/api/vessel/retroxr/ws?token=a%20b%26c%3Dd", "token escaped")


func _verbs() -> void:
	for verb: String in ["say", "move", "look", "use", "follow", "unfollow", "status",
			"look_at", "touch", "pick_up", "put_down", "hand_over", "sit", "emote", "inspect",
			"search", "explore", "watch", "bring", "stop", "survey", "look_around"]:
		_check(Protocol.is_known_verb(verb), "%s is a verb" % verb)
	# the two the core sends to build a walk are accepted, declared, and kept out of what the model is offered
	for verb: String in Protocol.INTERNAL_VERBS:
		_check(Protocol.IMPLEMENTED_VERBS.has(verb), "%s is declared in the hello" % verb)
		_check(not Protocol.CORE_VERBS.has(verb) and not Protocol.WORLD_VERBS.has(verb), "%s is neither a core nor a world verb" % verb)
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

	# Turning their head is not the room changing: a thing that left their view but still exists is out of SIGHT, said
	# nothing about, and when it comes back into view it is not "new" either.
	var mem2 := {}
	var tv2 := {"id": "TV1", "name": "TV", "label": "CRT television", "type": "TV", "side": "ahead", "distance": 2.0}
	var vase := {"id": "Vase1", "name": "Vase", "label": "vase", "type": "Node3D", "side": "ahead", "distance": 1.0}
	View.room_changes(mem2, [tv2, vase], true, ["TV1", "Vase1"])
	_check(View.room_changes(mem2, [], false, ["TV1", "Vase1"]).is_empty(), "turned away: nothing is 'no longer there' (it still exists)")
	_check(mem2.has("TV") and mem2.has("Vase"), "and they remember them as they were")
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

	# A thing that stops existing is told as gone only if it stays gone: it may have been moved.
	var m5 := {}
	var crate := {"id": "Crate1", "name": "Crate", "label": "crate", "type": "Node3D", "side": "ahead", "distance": 1.0}
	View.room_changes(m5, [tv2, crate], true, ["TV1", "Crate1"], 0.0, 20.0)
	_check(View.room_changes(m5, [tv2], false, ["TV1"], 1.0, 20.0).is_empty(), "gone: not told yet")
	_check(m5.has("Crate") and m5["Crate"].has("missing_since"), "it is remembered as missing, since when")
	_check(View.room_changes(m5, [tv2], false, ["TV1"], 10.0, 20.0).is_empty(), "still waiting at 10 s")
	said = View.room_changes(m5, [tv2], false, ["TV1"], 21.5, 20.0)
	_check(said.size() == 1 and str(said[0]).contains("crate") and str(said[0]).contains("no longer there"), "told once it stayed gone (%s)" % str(said))
	_check(not m5.has("Crate"), "and then forgotten")
	# Back before the delay: nothing to tell.
	var m6 := {}
	View.room_changes(m6, [tv2, crate], true, ["TV1", "Crate1"], 0.0, 20.0)
	View.room_changes(m6, [tv2], false, ["TV1"], 1.0, 20.0)
	_check(View.room_changes(m6, [tv2, crate], false, ["TV1", "Crate1"], 5.0, 20.0).is_empty(), "it came back: neither gone nor new")
	_check(not m6["Crate"].has("missing_since"), "and it is no longer waiting")
	# A copy of the same kind turns up elsewhere meanwhile: it was moved.
	var m7 := {}
	var crate2 := {"id": "Crate2", "name": "Crate2", "label": "crate", "type": "Node3D", "side": "to your left", "distance": 2.0}
	View.room_changes(m7, [tv2, crate], true, ["TV1", "Crate1"], 0.0, 20.0)
	View.room_changes(m7, [tv2], false, ["TV1"], 1.0, 20.0)
	said = View.room_changes(m7, [tv2, crate2], false, ["TV1", "Crate2"], 4.0, 20.0)
	_check(said.size() == 1 and str(said[0]).contains("was moved") and str(said[0]).contains("to your left") and not str(said[0]).contains("appeared"), "moved, not gone and appeared (%s)" % str(said))
	_check(View.room_changes(m7, [tv2, crate2], false, ["TV1", "Crate2"], 40.0, 20.0).is_empty(), "and the old one is never told as gone afterwards")


## Picking a session up again after a room change: the hello names it, and the text Synth reads says it is the same
## conversation (and never has them introduce themselves again).
func _resume() -> void:
	var fresh := Protocol.hello("root", [], [], "0.14.0")
	_check(not fresh.has("resume"), "a first hello names no session")
	_check(not Protocol.hello("root", [], [], "0.14.0", "").has("resume"), "an empty token is no token")
	_eq(Protocol.hello("bedroom", [], [], "0.13.0", "abc123")["resume"], "abc123", "a hello after a room change names the session")
	_eq(Protocol.hello("bedroom", [], [], "0.13.0", "abc123")["type"], "hello", "and is still a hello")
	var placed: Array = [{"id": "TV1", "name": "TV1", "label": "TV", "type": "RetroTV", "side": "straight ahead", "distance": 2.0, "front": true}]
	var first := View.summoned_text("root", placed)
	_check(first.contains("being summoned") and first.contains("inside its capsule") and not first.contains("same conversation"), "a new session is told it is being summoned, from inside the capsule")
	_check(first.contains("Say hello") and first.contains("only `say` works") and first.contains("held"), "the FIRST PROMPT asks for the greeting and says it is held until they are out (%s)" % first)
	var moved := View.summoned_text("bedroom", placed, {"from_room": "root"})
	_check(moved.contains("from the RetroXR room 'root' to the room 'bedroom'") and moved.contains("do not introduce yourself again"), "after a room change: where from, where to, no new introduction (%s)" % moved)
	var blip := View.summoned_text("root", placed, {"from_room": "root"})
	_check(blip.contains("cut for a moment") and blip.contains("do not introduce yourself again") and not blip.contains("being summoned"), "the same room: a blip, not a summoning (%s)" % blip)
	_check(not moved.contains("Say hello") and not blip.contains("Say hello"), "a conversation that goes on is not asked to say hello")
	_check(moved.contains("TV") and blip.contains("TV"), "and still says what is in front of them")


## The chat is kept between summons and cleared by the player. The real file is put back at the end.
func _chat_memory() -> void:
	var kept := FileAccess.get_file_as_bytes(ChatStore.FILE) if FileAccess.file_exists(ChatStore.FILE) else PackedByteArray()
	var had := FileAccess.file_exists(ChatStore.FILE)
	var pending_before := RiftSettings.forget_pending()
	ChatStore.clear()
	_eq(ChatStore.load_lines().size(), 0, "a cleared chat is empty")
	var lines: Array = [{"who": "you", "text": "ciao"}, {"who": "note", "text": "I heard nothing"}, {"who": "synth", "text": "ciao Jay"}]
	_check(ChatStore.save_lines(lines), "the chat is saved")
	var back := ChatStore.load_lines()
	_eq(back.size(), 2, "what was said comes back, the page's own notes do not")
	_check(back[0]["text"] == "ciao" and back[1]["who"] == "synth", "in order, with who said it")
	var many: Array = []
	for i in 100:
		many.append({"who": "you", "text": "n%d" % i})
	ChatStore.save_lines(many)
	var kept_n := ChatStore.load_lines()
	_check(kept_n.size() == ChatStore.KEEP and kept_n[kept_n.size() - 1]["text"] == "n99", "only the last %d are kept (%d)" % [ChatStore.KEEP, kept_n.size()])
	ChatStore.clear()
	_eq(ChatStore.load_lines().size(), 0, "forgetting empties it (control: the line above had %d)" % kept_n.size())
	# A forget asked while the rift is shut waits for the next open.
	RiftSettings.set_forget_pending(true)
	_check(RiftSettings.forget_pending(), "a forget asked with the rift shut is remembered")
	RiftSettings.set_forget_pending(false)
	_check(not RiftSettings.forget_pending(), "and stops being owed once told")
	RiftSettings.set_forget_pending(pending_before)
	if had:
		var f := FileAccess.open(ChatStore.FILE, FileAccess.WRITE)
		f.store_buffer(kept)
		f.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ChatStore.FILE))


func _screen() -> void:
	_check("turn_left" in Protocol.WANTED_ANIMATIONS and "turn_right" in Protocol.WANTED_ANIMATIONS, "the hello asks for both turns")
	_eq(View.body_screen(0), "BODY MATERIALIZATION\n[------------] 0%", "the body bar at nothing")
	_eq(View.body_screen(50), "BODY MATERIALIZATION\n[######------] 50%", "at half")
	_eq(View.body_screen(100), "BODY MATERIALIZATION\n[############] 100%", "and full")
	_eq(View.body_screen(250), View.body_screen(100), "a percentage past a hundred is a hundred")
	for pct in [0, 5, 40, 100]:
		for line in View.body_screen(pct).split("\n"):
			_check(line.length() <= 20, "no line of the screen is wider than the glass (%d chars at %d%%)" % [line.length(), pct])
