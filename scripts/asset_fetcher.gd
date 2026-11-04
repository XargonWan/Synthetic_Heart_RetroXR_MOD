## AssetFetcher -- downloads Synth's body from the server that is hosting the rift.
##
## The model and the animations are Karada skin files (`/skins/<skin>/model.vrm`,
## `/skins/<skin>/animations/...`), served over the same host and port as the socket. They are
## kept in `user://mods/xenu.synth_rift/cache/`, named by the sha256 the server's asset manifest
## gives them (`/api/karada/assets/manifest`), so a skin that changes is fetched again and one
## that did not is read from disk (the VRM is 19 MB). With no manifest the name is the path's
## and a cached file is trusted.
##
## The password, if there is one, goes as a bearer token; and a self-signed certificate is
## accepted for a local or private address only, like the socket's.
extends Node

const Protocol := preload("res://mods/xenu.synth_rift/scripts/rift_protocol.gd")
const CACHE_DIR := "user://mods/xenu.synth_rift/cache"
## A download is given up on when NO byte has arrived for this long (not when it has taken long: their model is 25 MB, and a
## home server over wifi gave 85-250 KB/s, which a fixed 60 s total cut off every time and left them a blue capsule).
const STALL_SEC := 20.0
## Whatever happens, one request is over after this long.
const MAX_SEC := 900.0
const POLL_SEC := 0.25
## A request that fails on the network is tried once more (an HTTP answer, 404 and the like, is not).
const ATTEMPTS := 2

## How far a download got: `got` bytes of `total` (-1 when the server did not say).
signal progress(url_path: String, got: int, total: int)

var base := ""
var token := ""
var _manifest: Dictionary = {}
var _manifest_tried := false
## Settable so a probe can watch the watchdog without waiting 20 s.
var stall_sec := STALL_SEC


func setup(server: String, password: String) -> void:
	base = Protocol.http_base(server)
	token = password


## The bytes of `url_path` (like "/skins/Rei/model.vrm"), from the cache or the server; empty on failure.
func get_bytes(url_path: String) -> PackedByteArray:
	if base.is_empty() or url_path.is_empty():
		return PackedByteArray()
	await _load_manifest()
	var cached := _cache_path(url_path)
	if FileAccess.file_exists(cached):
		var bytes := FileAccess.get_file_as_bytes(cached)
		if bytes.size() > 0:
			print("[Rift] cache hit: %s (%d bytes)" % [url_path, bytes.size()])
			return bytes
	var got := await _fetch(base + Protocol.encode_path(url_path))
	if got.is_empty():
		print("[Rift] could not download %s" % url_path)
		return got
	DirAccess.make_dir_recursive_absolute(CACHE_DIR)
	var f := FileAccess.open(cached, FileAccess.WRITE)
	if f != null:
		f.store_buffer(got)
		f.close()
	print("[Rift] downloaded %s (%d bytes)" % [url_path, got.size()])
	return got


## The bytes of `url_path` straight from the server, never cached: their voice is a new clip every time.
func get_fresh(url_path: String) -> PackedByteArray:
	if base.is_empty() or url_path.is_empty():
		return PackedByteArray()
	return await _fetch(base + Protocol.encode_path(url_path))


func _cache_path(url_path: String) -> String:
	var entry: Variant = _manifest.get(url_path)
	var stamp := str(url_path.md5_text()).substr(0, 10)
	if entry is Dictionary:
		stamp += "_" + str((entry as Dictionary).get("hash", "")).trim_prefix("sha256:").substr(0, 12)
	return "%s/%s_%s" % [CACHE_DIR, stamp, url_path.get_file().validate_filename()]


func _load_manifest() -> void:
	if _manifest_tried:
		return
	_manifest_tried = true
	var raw := await _fetch(base + "/api/karada/assets/manifest")
	if raw.is_empty():
		print("[Rift] no asset manifest: cached files are trusted")
		return
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if parsed is Dictionary and (parsed as Dictionary).get("assets") is Dictionary:
		_manifest = (parsed as Dictionary)["assets"]
		print("[Rift] asset manifest: %d files" % _manifest.size())


func _fetch(url: String) -> PackedByteArray:
	for attempt in ATTEMPTS:
		var out := await _fetch_once(url)
		if bool(out["done"]):
			return out["bytes"] as PackedByteArray
		print("[Rift] attempt %d of %d failed: %s" % [attempt + 1, ATTEMPTS, url])
	return PackedByteArray()


## One request, watched: {done: false} means "worth another try" (network trouble or a stall), done with no bytes is
## the server's answer (not found, refused) and final.
func _fetch_once(url: String) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 0.0
	req.accept_gzip = true
	add_child(req)
	if Protocol.trusts_unverified_tls(url.replace("https://", "wss://")):
		req.set_tls_options(TLSOptions.client_unsafe())
	var headers := PackedStringArray()
	if not token.is_empty():
		headers.append("Authorization: Bearer " + token)
	var answer: Array = []
	req.request_completed.connect(func(r: int, c: int, h: PackedStringArray, b: PackedByteArray) -> void:
		answer.assign([r, c, h, b]))
	var err := req.request(url, headers)
	if err != OK:
		print("[Rift] request failed (%s): %s" % [error_string(err), url])
		req.queue_free()
		return {"done": true, "bytes": PackedByteArray()}
	var last := 0
	var idle := 0.0
	var elapsed := 0.0
	# A timer of our own (a child): if the fetcher is freed mid-download it is freed with it and this simply never
	# resumes, instead of resuming on an object that is gone.
	var tick := Timer.new()
	tick.wait_time = POLL_SEC
	add_child(tick)
	tick.start()
	while answer.is_empty():
		await tick.timeout
		elapsed += POLL_SEC
		var got := req.get_downloaded_bytes()
		if got > last:
			last = got
			idle = 0.0
			progress.emit(url.trim_prefix(base), got, req.get_body_size())
		else:
			idle += POLL_SEC
		if idle >= stall_sec or elapsed >= MAX_SEC:
			print("[Rift] GET %s gave up: %s after %d bytes (%.0f s)" % [url, "nothing arrived for %.0f s" % idle if idle >= stall_sec else "too long", last, elapsed])
			req.cancel_request()
			req.queue_free()
			tick.queue_free()
			return {"done": false, "bytes": PackedByteArray()}
	tick.queue_free()
	req.queue_free()
	var result: int = int(answer[0])
	var code: int = int(answer[1])
	if result != HTTPRequest.RESULT_SUCCESS:
		print("[Rift] GET %s -> result %d, HTTP %d" % [url, result, code])
		return {"done": false, "bytes": PackedByteArray()}
	if code != 200:
		print("[Rift] GET %s -> result %d, HTTP %d" % [url, result, code])
		return {"done": true, "bytes": PackedByteArray()}
	return {"done": true, "bytes": answer[3] as PackedByteArray}
