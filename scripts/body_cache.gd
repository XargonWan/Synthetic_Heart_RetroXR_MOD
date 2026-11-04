## BodyCache -- their body, brought inside its budget once and kept.
##
## Making a body costs seconds (parse a 20 MB .vrm, decode and compress its textures, rebuild its meshes). The
## result is the same every time for the same file and tier, so it is saved as a scene under user:// and read
## back at every later summon (and every later launch): `<sha256 of the .vrm>_<tier>_v<BUDGET_VERSION>.scn`. A
## changed skin, another tier or a new budget version is a different name, so none of them can be served a body
## that was made for another.
##
## It never gets in their way: a file that is missing, truncated, from another version or that will not load is
## logged and the body is made again; a cache that cannot be written (a full disk) is logged and skipped.
## Only the three most recent bodies are kept.
extends RefCounted

const VrmBudget := preload("res://mods/xenu.synth_rift/scripts/vrm_budget.gd")

const DIR := "user://synth_rift/bodies"
## Where bodies are kept (the tests point it at a folder of their own).
static var dir := DIR
const KEEP := 3
const META := "synth_rift_body"

## For the tests: how many bodies were read from here and how many were written.
static var hits := 0
static var stores := 0


static func key_for(vrm: PackedByteArray, tier_name: String) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(vrm)
	return "%s_%s_v%d" % [hash.finish().hex_encode().left(20), tier_name, VrmBudget.BUDGET_VERSION]


static func path_of(key: String) -> String:
	return "%s/%s.scn" % [dir, key]


static func has(key: String) -> bool:
	return FileAccess.file_exists(path_of(key))


## {root: Node3D, face: Dictionary, stats: Dictionary} or {} (a miss, or a file that cannot be used: it is deleted).
static func load_body(key: String) -> Dictionary:
	var path := path_of(key)
	if not FileAccess.file_exists(path):
		return {}
	var t0 := Time.get_ticks_msec()
	var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var root := packed.instantiate() as Node3D if packed != null else null
	var meta: Variant = root.get_meta(META, null) if root != null else null
	if root == null or not (meta is Dictionary) or int((meta as Dictionary).get("version", -1)) != VrmBudget.BUDGET_VERSION:
		print("[Rift] body cache: %s would not load (or is from another version): made again" % key)
		if root != null:
			root.free()
		DirAccess.remove_absolute(path)
		return {}
	hits += 1
	print("[Rift] body cache hit: %s in %d ms" % [key, Time.get_ticks_msec() - t0])
	return {"root": root, "face": (meta as Dictionary).get("face", {}), "stats": (meta as Dictionary).get("stats", {})}


## Save `root` (a body inside its budget, not yet in the tree) with its expressions and the budget's own numbers.
static func store(key: String, root: Node3D, face_data: Dictionary, stats: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(dir)
	root.set_meta(META, {"version": VrmBudget.BUDGET_VERSION, "face": face_data, "stats": stats})
	_own(root, root)
	var packed := PackedScene.new()
	if packed.pack(root) != OK:
		print("[Rift] body cache: could not pack %s" % key)
		return false
	# Written beside its name and moved into place, so a write cut short never leaves a file that looks whole.
	var tmp := "%s/%s.tmp.scn" % [dir, key]
	var err := ResourceSaver.save(packed, tmp)
	if err != OK:
		print("[Rift] body cache: could not save %s (%s)" % [key, error_string(err)])
		DirAccess.remove_absolute(tmp)
		return false
	DirAccess.rename_absolute(tmp, path_of(key))
	stores += 1
	print("[Rift] body cache: saved %s (%.1f MB)" % [key, float(FileAccess.open(path_of(key), FileAccess.READ).get_length()) / 1048576.0])
	trim()
	return true


static func _own(node: Node, owner: Node) -> void:
	for child in node.get_children():
		child.owner = owner
		_own(child, owner)


## Keep the KEEP most recently written bodies, delete the rest.
static func trim() -> void:
	var entries: Array = []
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".scn") and not file.ends_with(".tmp.scn"):
			entries.append({"file": file, "time": FileAccess.get_modified_time("%s/%s" % [dir, file])})
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["time"] > b["time"])
	for i in range(KEEP, entries.size()):
		DirAccess.remove_absolute("%s/%s" % [dir, entries[i]["file"]])
		print("[Rift] body cache: dropped %s" % entries[i]["file"])


## Delete every cached body; how many.
static func clear() -> int:
	var n := 0
	if DirAccess.dir_exists_absolute(dir):
		for file in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute("%s/%s" % [dir, file])
			n += 1
	print("[Rift] body cache: cleared %d" % n)
	return n
