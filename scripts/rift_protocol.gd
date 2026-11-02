## RiftProtocol — the frames spoken with Synthetic Heart over the rift socket.
##
## Pure: no nodes, no network, so the tests can read it. The same protocol is
## documented from Synth's side in plugins/rift_vessel/retroxr/guide.md.
##
##   mod -> synth   hello / event / state / action_result / request_assets
##   synth -> mod   welcome / action / assets / error
extends RefCounted

const PROTOCOL := 1
const SOCKET_PATH := "/api/vessel/retroxr/ws"

## Verbs Synth may ask for. Anything else is answered "unknown_verb": the body
## never plays, and nothing here writes input to a console.
const CORE_VERBS: Array[String] = ["say", "move", "look", "use", "follow", "unfollow", "status"]
const WORLD_VERBS: Array[String] = [
	"look_at", "touch", "pick_up", "put_down", "hand_over", "sit", "emote", "inspect",
]
## Animations RetroXR will ask the skin for (the body is idle until it has them).
const WANTED_ANIMATIONS: Array[String] = ["idle", "walk", "talk", "think", "greet"]


static func is_known_verb(verb: String) -> bool:
	return CORE_VERBS.has(verb) or WORLD_VERBS.has(verb)


## "http://host:8080", "https://host", "ws://host:8080/" or a bare "host:8080"
## all name the same server. Returns the full socket URL, token included.
static func socket_url(server: String, token: String = "") -> String:
	var s := server.strip_edges()
	if s.is_empty():
		return ""
	var secure := false
	if s.begins_with("https://") or s.begins_with("wss://"):
		secure = true
		s = s.substr(s.find("://") + 3)
	elif s.contains("://"):
		s = s.substr(s.find("://") + 3)
	s = s.rstrip("/")
	if s.contains("/"):
		s = s.substr(0, s.find("/"))
	if s.is_empty():
		return ""
	var url := ("wss://" if secure else "ws://") + s + SOCKET_PATH
	if not token.is_empty():
		url += "?token=" + token.uri_encode()
	return url


## The host part of a socket URL ("wss://synth.local:8000/x?t=1" -> "synth.local").
static func host_of(url: String) -> String:
	var s := url
	if s.contains("://"):
		s = s.substr(s.find("://") + 3)
	for stop: String in ["/", "?", "#"]:
		if s.contains(stop):
			s = s.substr(0, s.find(stop))
	if s.begins_with("["):  # [::1]:8000
		return s.substr(1, maxi(s.find("]") - 1, 0))
	if s.contains(":"):
		s = s.substr(0, s.find(":"))
	return s


## A machine on this one or this network: loopback, a private range, a link-local address,
## `.local`, or a bare name with no dot. No public authority signs a certificate for any of
## these, so a Synth there serves a self-signed one.
static func is_private_host(host: String) -> bool:
	var h := host.to_lower()
	if h.is_empty():
		return false
	if h == "localhost" or h == "::1" or h.ends_with(".local") or h.ends_with(".lan") or h.ends_with(".home.arpa"):
		return true
	if not h.contains(".") and not h.contains(":"):
		return true
	var parts := h.split(".")
	var numeric := parts.size() == 4
	for part: String in parts:
		numeric = numeric and part.is_valid_int()
	if numeric:
		var a := int(parts[0])
		var b := int(parts[1])
		return a == 127 or a == 10 or (a == 192 and b == 168) or (a == 172 and b >= 16 and b <= 31) \
			or (a == 169 and b == 254)
	return h.begins_with("fe80:") or h.begins_with("fc") or h.begins_with("fd")


## Whether to accept a certificate nobody vouches for: a wss:// socket to a local or private
## address. A public host is verified like any other, so a password never goes to a stranger.
static func trusts_unverified_tls(url: String) -> bool:
	return url.begins_with("wss://") and is_private_host(host_of(url))


static func hello(room: String, capabilities: Array, animations: Array, mod_version: String) -> Dictionary:
	return {
		"type": "hello",
		"protocol": PROTOCOL,
		"room": room,
		"mod_version": mod_version,
		"capabilities": capabilities,
		"animations": animations,
	}


static func event(event_type: String, summary: String, actor: String = "",
		salience: float = -1.0, data: Dictionary = {}) -> Dictionary:
	var frame: Dictionary = {"type": "event", "event_type": event_type, "summary": summary, "data": data}
	if not actor.is_empty():
		frame["actor"] = actor
	if salience >= 0.0:
		frame["salience"] = salience
	return frame


static func state(position: Vector3, holding: String, extra: Dictionary) -> Dictionary:
	return {
		"type": "state",
		"state": {"position": vec(position), "holding": holding, "extra": extra},
	}


static func result(id: int, ok: bool, detail: String = "", data: Dictionary = {}) -> Dictionary:
	return {"type": "action_result", "id": id, "ok": ok, "detail": detail, "data": data}


static func request_assets(animations: Array) -> Dictionary:
	return {"type": "request_assets", "animations": animations}


static func vec(v: Vector3) -> Dictionary:
	return {"x": snappedf(v.x, 0.01), "y": snappedf(v.y, 0.01), "z": snappedf(v.z, 0.01)}


## A frame from the wire, or {} when it is not one (not JSON, not an object, no type).
static func parse(text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	var frame: Dictionary = parsed
	if not (frame.get("type") is String) or String(frame["type"]).is_empty():
		return {}
	return frame


## A point Synth named in a payload: {x,y,z} (or "x,y,z") -> Vector3, otherwise null.
static func point_of(payload: Dictionary) -> Variant:
	var src: Variant = payload.get("position", payload)
	if src is Dictionary:
		var d: Dictionary = src
		if d.has("x") and d.has("z"):
			return Vector3(float(d["x"]), float(d.get("y", 0.0)), float(d["z"]))
	var target: Variant = payload.get("target")
	if target is String:
		var parts := String(target).split(",")
		if parts.size() == 3 and String(parts[0]).is_valid_float() and String(parts[2]).is_valid_float():
			return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))
	return null
