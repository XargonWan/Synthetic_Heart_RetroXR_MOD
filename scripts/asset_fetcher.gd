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
const TIMEOUT_SEC := 60.0

var base := ""
var token := ""
var _manifest: Dictionary = {}
var _manifest_tried := false


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


## The bytes of `url_path` straight from the server, never cached: her voice is a new clip every time.
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
	var req := HTTPRequest.new()
	req.timeout = TIMEOUT_SEC
	req.accept_gzip = true
	add_child(req)
	if Protocol.trusts_unverified_tls(url.replace("https://", "wss://")):
		req.set_tls_options(TLSOptions.client_unsafe())
	var headers := PackedStringArray()
	if not token.is_empty():
		headers.append("Authorization: Bearer " + token)
	var err := req.request(url, headers)
	if err != OK:
		print("[Rift] request failed (%s): %s" % [error_string(err), url])
		req.queue_free()
		return PackedByteArray()
	var result: Array = await req.request_completed
	req.queue_free()
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS or int(result[1]) != 200:
		print("[Rift] GET %s -> result %d, HTTP %d" % [url, int(result[0]), int(result[1])])
		return PackedByteArray()
	return result[3] as PackedByteArray
