## RiftSettings -- which Synth server the Summoner opens the rift to.
##
## One file for the mod, not one per object and NEVER the room's save slot: the
## token is a password, and a slot is a file people share. The Summoner's own menu
## edits it; the environment overrides it for probes (XENU_SYNTH_URL / _TOKEN).
extends RefCounted

const MOD_ID := "xenu.synth_rift"
const FILE := "user://mods/xenu.synth_rift/settings.json"
const DEFAULT_SERVER := "127.0.0.1:8080"


static func load_settings() -> Dictionary:
	var s: Dictionary = JsonStore.read_dict(FILE, MOD_ID)
	var server := OS.get_environment("XENU_SYNTH_URL")
	if not server.is_empty():
		s["server"] = server
	var token := OS.get_environment("XENU_SYNTH_TOKEN")
	if not token.is_empty():
		s["token"] = token
	return s


static func server_of(s: Dictionary) -> String:
	var server := str(s.get("server", "")).strip_edges()
	return server if not server.is_empty() else DEFAULT_SERVER


## Write what the player typed. The environment overrides are never written back.
static func save(server: String, token: String) -> bool:
	DirAccess.make_dir_recursive_absolute(FILE.get_base_dir())
	var ok := JsonStore.write_dict(FILE, {"server": server.strip_edges(), "token": token}, MOD_ID)
	print("[Rift] settings %s (server=%s, token %s)" % [
		"saved" if ok else "NOT saved", server.strip_edges(), "set" if not token.is_empty() else "empty"])
	return ok
