## Opens the rift socket of a REAL Synth and closes it before saying anything (no hello, so no
## session is begun): does the TLS handshake get through?
##
##   XENU_SYNTH_URL=https://localhost:8000/ [VERIFY=1] godot --headless --path RetroXR \
##       --script res://mods/xenu.synth_rift/tests/tls_probe.gd
##
## VERIFY=1 is the old behaviour (a certificate nobody vouches for is refused): the control.
extends SceneTree

const Protocol := preload("res://mods/xenu.synth_rift/scripts/rift_protocol.gd")

var _peer := WebSocketPeer.new()
var _t := 0.0
var _done := false


func _initialize() -> void:
	var url: String = Protocol.socket_url(OS.get_environment("XENU_SYNTH_URL"))
	var verify := OS.get_environment("VERIFY") == "1"
	var tls: TLSOptions = null
	if not verify and Protocol.trusts_unverified_tls(url):
		tls = TLSOptions.client_unsafe()
	print("[probe] %s (%s)" % [url, "certificate verified" if tls == null else "self-signed accepted"])
	var err := _peer.connect_to_url(url, tls)
	if err != OK:
		print("[probe] RESULT connect_to_url failed: %s" % error_string(err))
		quit(1)


func _process(delta: float) -> bool:
	if _done:
		return false
	_t += delta
	_peer.poll()
	var st := _peer.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		_done = true
		print("[probe] RESULT OPEN: the handshake got through")
		_peer.close()
		quit(0)
	elif st == WebSocketPeer.STATE_CLOSED:
		_done = true
		print("[probe] RESULT CLOSED before opening (code %d): the handshake was refused" % _peer.get_close_code())
		quit(2)
	elif _t > 10.0:
		_done = true
		print("[probe] RESULT timeout")
		quit(3)
	return false
