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


## May they send pictures of what they see to Synth (a watched TV, a room)? On unless the player switched it off: a
## picture leaves the room for the server, and from there perhaps for a model, so it is theirs to forbid.
static func pictures_on() -> bool:
	var env := OS.get_environment("XENU_SYNTH_PICTURES")
	if not env.is_empty():
		return env != "0"
	return bool(JsonStore.read_dict(FILE, MOD_ID).get("pictures", true))


static func set_pictures(on: bool) -> void:
	var s: Dictionary = JsonStore.read_dict(FILE, MOD_ID)
	s["pictures"] = on
	DirAccess.make_dir_recursive_absolute(FILE.get_base_dir())
	JsonStore.write_dict(FILE, s, MOD_ID)
	print("[Rift] pictures %s" % ("on" if on else "off"))


## The player asked to forget the chat while the rift was shut: Synth is told the moment it opens.
static func forget_pending() -> bool:
	return bool(JsonStore.read_dict(FILE, MOD_ID).get("forget_pending", false))


static func set_forget_pending(on: bool) -> void:
	var s: Dictionary = JsonStore.read_dict(FILE, MOD_ID)
	s["forget_pending"] = on
	DirAccess.make_dir_recursive_absolute(FILE.get_base_dir())
	JsonStore.write_dict(FILE, s, MOD_ID)


## What the server calls them (the welcome's `assets.name`, their persona's name), kept so a chat opened before the next
## welcome still says it. "SyntH" until a server has offered one.
const DEFAULT_SYNTH_NAME := "SyntH"


static func synth_name() -> String:
	var n := str(JsonStore.read_dict(FILE, MOD_ID).get("synth_name", "")).strip_edges()
	return n if not n.is_empty() else DEFAULT_SYNTH_NAME


## Remember the name a welcome offered; an empty one (a server that offers none) forgets the old, so the default returns.
static func set_synth_name(name: String) -> void:
	name = name.strip_edges()
	var s: Dictionary = JsonStore.read_dict(FILE, MOD_ID)
	if str(s.get("synth_name", "")) == name:
		return
	if name.is_empty():
		s.erase("synth_name")
	else:
		s["synth_name"] = name
	DirAccess.make_dir_recursive_absolute(FILE.get_base_dir())
	JsonStore.write_dict(FILE, s, MOD_ID)
	print("[Rift] the server calls them '%s'" % (name if not name.is_empty() else DEFAULT_SYNTH_NAME + " (none offered)"))


## Write what the player typed. The environment overrides are never written back.
static func save(server: String, token: String) -> bool:
	DirAccess.make_dir_recursive_absolute(FILE.get_base_dir())
	var s: Dictionary = JsonStore.read_dict(FILE, MOD_ID)
	s["server"] = server.strip_edges()
	s["token"] = token
	var ok := JsonStore.write_dict(FILE, s, MOD_ID)
	print("[Rift] settings %s (server=%s, token %s)" % [
		"saved" if ok else "NOT saved", server.strip_edges(), "set" if not token.is_empty() else "empty"])
	return ok
