## RiftLink -- the WebSocket to the Synthetic Heart server.
##
## One link per Summoner. It does three things: opens the socket, says hello as
## the first frame, and hands every frame after that to whoever listens. It never
## reconnects by itself: the Summoner being on IS the rift being open, so the
## Summoner decides when to try again.
##
## States: CLOSED -> CONNECTING -> HELLO (socket up, waiting for welcome) -> OPEN.
extends Node

const Protocol := preload("res://mods/xenu.synth_rift/scripts/rift_protocol.gd")

enum State { CLOSED, CONNECTING, HELLO, OPEN }

## Synth said welcome: {session, assets}.
signal opened(welcome: Dictionary)
## The rift is shut, for the reason given (also when we asked).
signal closed(reason: String)
## Synth asks for a verb: its id, the verb and its payload.
signal action_received(id: int, action: String, payload: Dictionary)
## An `assets` answer to request_assets().
signal assets_received(assets: Dictionary)
## What Synth's Karada says their avatar is doing: kind ("animation", "audio", "face", ...) and its payload.
signal karada_received(kind: String, payload: Dictionary)
## What Synth made of a clip the player recorded (ok=false: `reason` says why there is no text).
signal transcript_received(id: int, ok: bool, text: String, reason: String)

## No welcome within this long after the socket opens: give up.
const WELCOME_TIMEOUT_SEC := 15.0
## No socket within this long: give up.
const CONNECT_TIMEOUT_SEC := 10.0

var state: State = State.CLOSED
var _peer: WebSocketPeer = null
var _hello: Dictionary = {}
var _waited := 0.0


func is_open() -> bool:
	return state == State.OPEN


## Open the rift. `hello` is the first frame (Protocol.hello(...)).
func open_rift(url: String, hello: Dictionary) -> bool:
	if state != State.CLOSED:
		print("[Rift] open_rift ignored: link is %s" % State.keys()[state])
		return false
	if url.is_empty():
		print("[Rift] open_rift refused: no server address (set it in the mod's settings)")
		closed.emit("no_server")
		return false
	_peer = WebSocketPeer.new()
	# A Synth on this machine or network serves a self-signed certificate, which Godot refuses
	# unless told otherwise. Only for those: a public host is verified as ever.
	var tls: TLSOptions = null
	if Protocol.trusts_unverified_tls(url):
		tls = TLSOptions.client_unsafe()
		print("[Rift] %s is on this machine or network: accepting its self-signed certificate" % Protocol.host_of(url))
	var err := _peer.connect_to_url(url, tls)
	if err != OK:
		print("[Rift] connect_to_url failed (%s): %s" % [error_string(err), _safe_url(url)])
		_peer = null
		closed.emit("connect_failed")
		return false
	_hello = hello
	_waited = 0.0
	state = State.CONNECTING
	print("[Rift] connecting to %s" % _safe_url(url))
	return true


func close_rift(reason: String = "closed") -> void:
	if _peer != null:
		_peer.close(1000, reason)
	_finish(reason)


func send_frame(frame: Dictionary) -> bool:
	if _peer == null or _peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return false
	return _peer.send_text(JSON.stringify(frame)) == OK


func _process(delta: float) -> void:
	if _peer == null:
		return
	_peer.poll()
	match _peer.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			_waited += delta
			if _waited > CONNECT_TIMEOUT_SEC:
				print("[Rift] no answer from the server in %.0f s" % CONNECT_TIMEOUT_SEC)
				_peer.close()
				_finish("connect_timeout")
		WebSocketPeer.STATE_OPEN:
			if state == State.CONNECTING:
				state = State.HELLO
				_waited = 0.0
				_peer.send_text(JSON.stringify(_hello))
			elif state == State.HELLO:
				_waited += delta
				if _waited > WELCOME_TIMEOUT_SEC:
					print("[Rift] no welcome in %.0f s" % WELCOME_TIMEOUT_SEC)
					_peer.close()
					_finish("welcome_timeout")
					return
			while _peer != null and _peer.get_available_packet_count() > 0:
				_on_frame(_peer.get_packet().get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			var code := _peer.get_close_code()
			var why := _peer.get_close_reason()
			print("[Rift] socket closed (code=%d reason=%s)" % [code, why])
			_finish("server_closed" if state == State.OPEN else "refused")


func _on_frame(text: String) -> void:
	var frame := Protocol.parse(text)
	if frame.is_empty():
		print("[Rift] ignored a frame that is not protocol JSON")
		return
	match String(frame["type"]):
		"welcome":
			state = State.OPEN
			print("[Rift] open (session=%s)" % str(frame.get("session")))
			opened.emit(frame)
		"error":
			print("[Rift] server refused: %s (%s)" % [str(frame.get("code")), str(frame.get("message"))])
			_finish("refused:" + str(frame.get("code")))
		"action":
			action_received.emit(int(frame.get("id", 0)), String(frame.get("action", "")),
				frame.get("payload", {}) if frame.get("payload") is Dictionary else {})
		"karada":
			karada_received.emit(String(frame.get("kind", "")),
				frame.get("payload", {}) if frame.get("payload") is Dictionary else {})
		"transcript":
			transcript_received.emit(int(frame.get("id", 0)), bool(frame.get("ok", false)),
				String(frame.get("text", "")), String(frame.get("reason", "")))
		"assets":
			assets_received.emit(frame.get("assets", {}) if frame.get("assets") is Dictionary else {})
		_:
			print("[Rift] ignored frame type %s" % str(frame["type"]))


func _finish(reason: String) -> void:
	var was := state
	state = State.CLOSED
	_peer = null
	if was != State.CLOSED:
		closed.emit(reason)


## The URL without the token, for the log.
static func _safe_url(url: String) -> String:
	var q := url.find("?")
	return url if q < 0 else url.substr(0, q) + "?token=***"
