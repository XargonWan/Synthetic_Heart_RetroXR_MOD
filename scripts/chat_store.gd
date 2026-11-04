## ChatStore -- the chat with Synth, kept between summons.
##
## What was said is Synth's memory too (the server keeps it per house, see `remembers_chat` in the connector); this is
## the mod's copy, the log the chat page shows. One file for the mod, like the settings. The pod's menu clears both
## (`forget`): the server's through a frame, this one here.
extends RefCounted

const MOD_ID := "xenu.synth_rift"
const FILE := "user://mods/xenu.synth_rift/chat.json"
const KEEP := 60


## The saved lines ({who, text}), oldest first; [] when nothing was kept.
static func load_lines() -> Array:
	var raw: Variant = JsonStore.read_dict(FILE, MOD_ID).get("lines", [])
	var out: Array = []
	if raw is Array:
		for l: Variant in raw:
			if l is Dictionary and str((l as Dictionary).get("who", "")) in ["you", "synth"]:
				out.append({"who": str(l["who"]), "text": str((l as Dictionary).get("text", ""))})
	return out.slice(maxi(0, out.size() - KEEP))


## Keep `lines` (only what was said: the page's own notes are not part of the conversation).
static func save_lines(lines: Array) -> bool:
	var keep: Array = []
	for l: Variant in lines:
		if l is Dictionary and str((l as Dictionary).get("who", "")) in ["you", "synth"]:
			keep.append({"who": l["who"], "text": l["text"]})
	DirAccess.make_dir_recursive_absolute(FILE.get_base_dir())
	return JsonStore.write_dict(FILE, {"lines": keep.slice(maxi(0, keep.size() - KEEP))}, MOD_ID)


static func clear() -> bool:
	print("[Rift] the saved chat is cleared")
	return save_lines([])
