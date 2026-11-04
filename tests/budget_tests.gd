## What a body costs, and the cache that keeps it. Every skin on the server's disk is brought inside the Quest
## budget (RETROXR_TIER=quest) and measured; a synthetic mesh proves the morph pruning keeps the RIGHT shape.
##
##   SKINS=$HOME/gits/Synthetic_Heart/skins godot --headless --path RetroXR \
##       --script res://mods/xenu.synth_rift/tests/budget_tests.gd
##
## Headless draws nothing, but the meshes, the textures' data and the files are all real, so the numbers are real.
## A headset is what settles the budget's own figures.
extends SceneTree

const Puppet := preload("res://mods/xenu.synth_rift/scripts/karada_puppet.gd")
const VrmBudget := preload("res://mods/xenu.synth_rift/scripts/vrm_budget.gd")
const VrmFace := preload("res://mods/xenu.synth_rift/scripts/vrm_face.gd")
const BodyCache := preload("res://mods/xenu.synth_rift/scripts/body_cache.gd")

var _failed := 0
var _count := 0


func _initialize() -> void:
	var skins := OS.get_environment("SKINS")
	if skins.is_empty():
		print("[rift-tests] no SKINS set")
		quit(1)
		return
	BodyCache.dir = "user://synth_rift_test"
	BodyCache.clear()
	_morph_pruning_keeps_the_right_shape()
	OS.set_environment("RETROXR_TIER", "quest")
	var names: Array = []
	for d in DirAccess.get_directories_at(skins):
		if FileAccess.file_exists("%s/%s/model.vrm" % [skins, d]) and FileAccess.open("%s/%s/model.vrm" % [skins, d], FileAccess.READ).get_length() > 1000:
			names.append(d)
	_check(names.size() >= 2, "there are skins to measure (%d)" % names.size())
	var quest: Dictionary = VrmBudget.TIERS["quest"]
	print("[rift-tests] %-6s %9s %9s %7s %7s %12s %8s" % ["skin", "tris", "verts", "blend", "tex px", "tex MB", "ms"])
	for skin: String in names:
		var vrm := FileAccess.get_file_as_bytes("%s/%s/model.vrm" % [skins, skin])
		var puppet: Node3D = Puppet.new()
		root.add_child(puppet)
		_check(puppet.load_model(vrm, false), "%s loads under the Quest budget" % skin)
		var b: Dictionary = puppet.budget
		var tex: Dictionary = (b["stats"] as Dictionary).get("textures", {})
		var before: int = int(((b["stats"] as Dictionary).get("reduced", {}) as Dictionary).get("tris_before", 0))
		print("[rift-tests] %-6s %4d>%-4d %9d %7d %7d %5.0f>%-5.0f %8d" % [skin, before / 1000, b["tris"] / 1000, b["verts"], b["blend_shapes"],
			b["texture_max"], float(tex.get("bytes_before", 0)) / 1048576.0, float(tex.get("bytes_after", 0)) / 1048576.0, b["ms"]])
		_check(int(b["tris"]) <= int(quest["max_tris"]), "%s: %d triangles are within the %d cap" % [skin, b["tris"], quest["max_tris"]])
		_check(int(b["texture_max"]) <= int(quest["tex_cap"]), "%s: the largest texture is %d px (cap %d)" % [skin, b["texture_max"], quest["tex_cap"]])
		_check(int(tex.get("textures", 0)) > 5 and int(tex.get("errors", 1)) == 0, "%s: its textures were compressed (%s)" % [skin, str(tex)])
		_check(float(tex.get("bytes_after", 1)) < float(tex.get("bytes_before", 0)) * 0.35, "%s: to a third or less of their size" % skin)
		_check(int(b["blend_shapes"]) < 120, "%s: morph targets were pruned (%d left)" % [skin, b["blend_shapes"]])
		_check(int(b["surfaces"]) >= 8, "%s: no surface was lost (%d)" % [skin, b["surfaces"]])
		var face: RefCounted = puppet.face
		for n: Array in [["blink"], ["joy", "happy"], ["a", "aa"]]:
			_check(face.has_expression(n[0]) or face.has_expression(n[-1]), "%s: '%s' still moves their face" % [skin, n[0]])
		_check(_blink_closes_the_lids(face), "%s: and blinking really sets a blend shape that exists" % skin)
		puppet.queue_free()

	# Rei again under the desktop budget: nothing is reduced that does not have to be.
	OS.set_environment("RETROXR_TIER", "desktop")
	var rei := FileAccess.get_file_as_bytes("%s/Rei/model.vrm" % skins)
	var desk: Node3D = Puppet.new()
	root.add_child(desk)
	desk.load_model(rei, false)
	_check(int(desk.budget["tris"]) > 40000, "desktop: the triangles are as the file made them (%d)" % desk.budget["tris"])
	desk.queue_free()

	# The cache.
	OS.set_environment("RETROXR_TIER", "quest")
	BodyCache.clear()
	BodyCache.hits = 0
	BodyCache.stores = 0
	var first: Node3D = Puppet.new()
	root.add_child(first)
	first.load_model(rei)
	var key := BodyCache.key_for(rei, "quest")
	_check(BodyCache.stores == 1 and BodyCache.has(key), "the first load makes the body and keeps it")
	var second: Node3D = Puppet.new()
	root.add_child(second)
	second.load_model(rei)
	_check(BodyCache.hits == 1 and BodyCache.stores == 1, "the second one reads it back (hits %d, stores %d)" % [BodyCache.hits, BodyCache.stores])
	_check(bool(second.budget["from_cache"]) and not bool(first.budget["from_cache"]), "and says so")
	print("[rift-tests] first load %d ms, from the cache %d ms" % [first.budget["ms"], second.budget["ms"]])
	_check(int(second.budget["ms"]) * 2 < int(first.budget["ms"]), "which is much faster")
	for field: String in ["tris", "verts", "surfaces", "blend_shapes"]:
		_check(first.budget[field] == second.budget[field], "the cached body has the same %s (%s)" % [field, str(second.budget[field])])
	_check(absf(float(first.budget["texture_bytes"]) - float(second.budget["texture_bytes"])) < float(first.budget["texture_bytes"]) * 0.05,
		"and about the same texture bytes (%d against %d)" % [first.budget["texture_bytes"], second.budget["texture_bytes"]])
	_check(second.face.expression_names().size() == first.face.expression_names().size() and _blink_closes_the_lids(second.face),
		"and the same face: blinking works on it")
	_check(second.skeleton.get_bone_count() == first.skeleton.get_bone_count(), "and the same skeleton")
	# Another tier, another file; another skin (other bytes), another file.
	_check(BodyCache.key_for(rei, "desktop") != key, "the desktop's body is another file")
	var other := rei.duplicate()
	other[100] = (other[100] + 1) % 256
	_check(BodyCache.key_for(other, "quest") != key, "another .vrm is another file")
	# A file cut short is made again, not an error.
	var path := BodyCache.path_of(key)
	var data := FileAccess.get_file_as_bytes(path)
	var cut := FileAccess.open(path, FileAccess.WRITE)
	cut.store_buffer(data.slice(0, data.size() / 3))
	cut.close()
	var third: Node3D = Puppet.new()
	root.add_child(third)
	_check(third.load_model(rei), "a truncated cache file does not stop their loading")
	_check(not bool(third.budget["from_cache"]) and BodyCache.stores == 2 and int(third.budget["tris"]) == int(first.budget["tris"]),
		"it is made again and kept again (stores %d)" % BodyCache.stores)
	# The cache holds the last three only.
	for i in 4:
		var dummy := Node3D.new()
		BodyCache.store("filler_%d" % i, dummy, {}, {})
		dummy.free()
		OS.delay_msec(1100)
	_check(DirAccess.get_files_at(BodyCache.dir).size() <= BodyCache.KEEP, "only the last %d bodies are kept (%d)" % [BodyCache.KEEP, DirAccess.get_files_at(BodyCache.dir).size()])
	BodyCache.clear()
	print("[rift-tests] %d cases, %d failed" % [_count, _failed])
	quit(1 if _failed > 0 or _count == 0 else 0)


## Blinking sets a blend shape that is there, to 1, on the mesh itself.
func _blink_closes_the_lids(face: RefCounted) -> bool:
	face.set_face_values({})
	face.auto_blink = false
	face.set_face_values({"blink": 1.0})
	face.update(0.016)
	var ok := false
	if face.has_expression("blink"):
		for b: Dictionary in face._binds[face._resolve("blink")]:
			var mi: MeshInstance3D = b["mi"]
			ok = int(b["idx"]) >= 0 and int(b["idx"]) < mi.get_blend_shape_count() and absf(mi.get_blend_shape_value(int(b["idx"])) - float(b["w"])) < 0.01
	face.set_face_values({})
	face.update(0.016)
	face.auto_blink = true
	return ok


## Keeping shape 2 of three leaves a mesh whose only shape IS the old shape 2, and the expression that
## moved shape 2 moves it.
func _morph_pruning_keeps_the_right_shape() -> void:
	var base := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)])
	var mesh := ArrayMesh.new()
	for i in 3:
		mesh.add_blend_shape("shape%d" % i)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = base
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 2, 1, 3])
	var shapes: Array = []
	for i in 3:
		var shifted := PackedVector3Array()
		for v in base:
			shifted.append(v + Vector3(0, 0, float(i + 1)))
		var shape := []
		shape.resize(Mesh.ARRAY_MAX)
		shape[Mesh.ARRAY_VERTEX] = shifted
		shapes.append(shape)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes)
	var holder := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Face"
	mi.mesh = mesh
	holder.add_child(mi)
	var face: RefCounted = VrmFace.new()
	face.set("_binds", {"blink": [{"mi": mi, "idx": 2, "w": 1.0}]})
	var report := VrmBudget.reduce_meshes(holder, face, {"max_tris": 1000000, "lods": false})
	var pruned := mi.mesh as ArrayMesh
	_check(pruned.get_blend_shape_count() == 1 and report["morph_dropped"] == 2, "of three blend shapes one is kept")
	_check(pruned.get_blend_shape_name(0) == "shape2", "the one the expression moves (%s)" % pruned.get_blend_shape_name(0))
	var kept: Array = pruned.surface_get_blend_shape_arrays(0)[0]
	_check((kept[Mesh.ARRAY_VERTEX] as PackedVector3Array)[0].is_equal_approx(Vector3(0, 0, 3)), "with the deltas it had (%s)" % str((kept[Mesh.ARRAY_VERTEX] as PackedVector3Array)[0]))
	_check(int(face._binds["blink"][0]["idx"]) == 0, "and the expression now points at it (%d)" % int(face._binds["blink"][0]["idx"]))
	holder.free()


func _check(ok: bool, what: String) -> void:
	_count += 1
	if not ok:
		_failed += 1
		print("[rift-tests] FAIL: %s" % what)
