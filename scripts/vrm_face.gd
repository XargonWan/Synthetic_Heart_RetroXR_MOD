## VrmFace -- the face of Synth's body: blink, emotion, the mouth.
##
## The WebUI avatar's FacialDriver (frontend/src/composables/vrm/face.ts), ported: the same layers
## in the same order, so the body in the room has the face the avatar on the screen has.
##
##   1. face values  -- the server's emotion state (Karada `face` frames)
##   2. descriptor   -- frame-windowed expressions of the animation that is playing (think closes their eyes)
##   3. overlay      -- `vrm_expression_set` targets (one active source)
##   4. visemes      -- the mouth, last, so it wins over an emotion's mouth
##
## Logical names (eyes_closed, mouth_smile ...) go through the skin's persona `blendshape_map` to a VRM
## expression name (blink, happy ...); a name that already is one passes through. An automatic blink
## runs unless something else is driving the blink expression.
##
## An expression is a set of binds {mesh instance, blend shape, weight}, read from the model's own
## file: VRM 0.x `blendShapeMaster.blendShapeGroups` (weights 0-100) or VRM 1.0 `VRMC_vrm.expressions`.
## Godot's glTF import turns a mesh's morph targets into blend shapes in the file's order, so a bind's
## index is the blend shape's index.
extends RefCounted

const BLINK_MIN_INTERVAL := 2.5
const BLINK_MAX_INTERVAL := 6.0
const BLINK_CLOSE := 0.08
const BLINK_HOLD := 0.04
const BLINK_OPEN := 0.1
## The mouth opens no wider than this while they speak (the WebUI's own cap).
const MOUTH_OPEN_CAP := 0.7
const MOUTH_SMOOTHING := 0.35

## VRM 1.0 names (what the blendshape_map uses) -> the VRM 0.x preset that is the same thing.
const VRM0_NAMES := {
	"happy": "joy", "sad": "sorrow", "relaxed": "fun", "aa": "a", "ih": "i", "ou": "u", "ee": "e",
	"oh": "o", "blinkleft": "blink_l", "blinkright": "blink_r",
}

## expression name (lower case, VRM 1.0 spelling) -> [{mi: MeshInstance3D, idx: int, w: float 0..1}]
var _binds: Dictionary = {}
var _aliases: Dictionary = {}
## The skin's persona blendshape_map: logical name -> expression name; "visemes" -> {A: {name: scale}}.
var blendshape_map: Dictionary = {}
## The persona's `emotions`: an emotion name the server sends in a `face` frame -> the LOGICAL targets it is
## (happy -> {mouth_smile: 0.25, eyes_smile: 0.2}), scaled by the value. A name that is not here is taken as a
## VRM expression, as before.
var emotions: Dictionary = {}

var _face_values: Dictionary = {}
var _overlay: Variant = null
var _descriptor: Dictionary = {}
var _descriptor_started := 0.0
var _visemes: Dictionary = {}
var _mouth := 0.0

var _blink_timer := 0.0
var _next_blink := 0.0
var _blink_phase := "idle"
var _blink_phase_time := 0.0
var _blink_weight := 0.0
var auto_blink := true

var _driven: Dictionary = {}
## What was last written, by expression name: the tests read it.
var applied: Dictionary = {}


func _init() -> void:
	_next_blink = _random_interval()


## Read the expressions out of the model's glTF. `scene_node` is Callable(node_index) -> Node (GLTFState.get_scene_node).
## Returns how many expressions it found.
func load_from(gltf_json: Dictionary, scene_node: Callable, mesh_nodes: Callable) -> int:
	_binds.clear()
	_aliases.clear()
	var ext: Dictionary = gltf_json.get("extensions", {}) if gltf_json.get("extensions") is Dictionary else {}
	if ext.has("VRM"):
		_load_vrm0(ext["VRM"] as Dictionary, mesh_nodes)
	if ext.has("VRMC_vrm"):
		_load_vrm1(ext["VRMC_vrm"] as Dictionary, scene_node)
	print("[Rift] face: %d expressions (%s)" % [_binds.size(), ", ".join(PackedStringArray(_binds.keys()))])
	return _binds.size()


func _load_vrm0(vrm: Dictionary, mesh_nodes: Callable) -> void:
	var master: Dictionary = vrm.get("blendShapeMaster", {}) if vrm.get("blendShapeMaster") is Dictionary else {}
	var groups: Array = master.get("blendShapeGroups", []) if master.get("blendShapeGroups") is Array else []
	for g: Variant in groups:
		if not (g is Dictionary):
			continue
		var group: Dictionary = g
		var binds: Array = []
		for b: Variant in group.get("binds", []):
			if not (b is Dictionary):
				continue
			# A bind names a glTF MESH; the node that draws it is what moves.
			var targets: Array = mesh_nodes.call(int((b as Dictionary).get("mesh", -1)))
			for mi: Variant in targets:
				if mi is MeshInstance3D:
					binds.append({"mi": mi, "idx": int((b as Dictionary).get("index", -1)),
						"w": float((b as Dictionary).get("weight", 100.0)) / 100.0})
		if binds.is_empty():
			continue
		var preset := str(group.get("presetName", "")).to_lower()
		var named := str(group.get("name", "")).to_lower()
		var key := named if preset in ["", "unknown"] else preset
		_binds[key] = binds
		if not named.is_empty():
			_aliases[named] = key
	# A VRM 1.0 name resolves to its 0.x preset.
	for v1: String in VRM0_NAMES:
		if _binds.has(VRM0_NAMES[v1]):
			_aliases[v1] = VRM0_NAMES[v1]


func _load_vrm1(vrm: Dictionary, scene_node: Callable) -> void:
	var ex: Dictionary = vrm.get("expressions", {}) if vrm.get("expressions") is Dictionary else {}
	for section: String in ["preset", "custom"]:
		var entries: Dictionary = ex.get(section, {}) if ex.get(section) is Dictionary else {}
		for name: String in entries:
			var binds: Array = []
			var e: Variant = entries[name]
			if not (e is Dictionary):
				continue
			for b: Variant in (e as Dictionary).get("morphTargetBinds", []):
				if not (b is Dictionary):
					continue
				var node: Variant = scene_node.call(int((b as Dictionary).get("node", -1)))
				if node is MeshInstance3D:
					binds.append({"mi": node, "idx": int((b as Dictionary).get("index", -1)),
						"w": float((b as Dictionary).get("weight", 1.0))})
			if not binds.is_empty():
				_binds[name.to_lower()] = binds
	# A 0.x name (joy, a) resolves to its 1.0 preset (happy, aa), so either spelling finds the expression.
	for v1: String in VRM0_NAMES:
		if _binds.has(v1) and not _binds.has(VRM0_NAMES[v1]):
			_aliases[VRM0_NAMES[v1]] = v1


## Which blend shapes of `mi` an expression moves (so the others can be dropped): a sorted list of indices.
func blend_shapes_used(mi: MeshInstance3D) -> Array:
	var used := {}
	for key: String in _binds:
		for b: Dictionary in _binds[key]:
			if b["mi"] == mi and int(b["idx"]) >= 0:
				used[int(b["idx"])] = true
	var out: Array = used.keys()
	out.sort()
	return out


## The blend shapes of `mi` were rebuilt without some: `map` is {old index: new index}. A bind to one that is
## gone is dropped.
func remap_blend_shapes(mi: MeshInstance3D, map: Dictionary) -> void:
	for key: String in _binds.keys():
		var kept: Array = []
		for b: Dictionary in _binds[key]:
			if b["mi"] != mi:
				kept.append(b)
			elif map.has(int(b["idx"])):
				b["idx"] = int(map[int(b["idx"])])
				kept.append(b)
		if kept.is_empty():
			_binds.erase(key)
		else:
			_binds[key] = kept


## The expressions as plain data (a mesh instance by its path under `root`), to be saved with the body and read
## back by from_data(): the cached body has no glTF to read them from.
func to_data(root: Node) -> Dictionary:
	var out := {}
	for key: String in _binds:
		var list: Array = []
		for b: Dictionary in _binds[key]:
			list.append({"path": str(root.get_path_to(b["mi"])), "idx": int(b["idx"]), "w": float(b["w"])})
		out[key] = list
	return {"binds": out, "aliases": _aliases.duplicate()}


func from_data(data: Dictionary, root: Node) -> int:
	_binds.clear()
	_aliases = (data.get("aliases", {}) as Dictionary).duplicate() if data.get("aliases") is Dictionary else {}
	var binds: Dictionary = data.get("binds", {}) if data.get("binds") is Dictionary else {}
	for key: String in binds:
		var list: Array = []
		for b: Variant in binds[key]:
			var mi := root.get_node_or_null(NodePath(str((b as Dictionary).get("path", "")))) as MeshInstance3D
			if mi != null:
				list.append({"mi": mi, "idx": int((b as Dictionary).get("idx", -1)), "w": float((b as Dictionary).get("w", 1.0))})
		if not list.is_empty():
			_binds[key] = list
	return _binds.size()


func has_expression(name: String) -> bool:
	return _resolve(name) != ""


func expression_names() -> Array:
	return _binds.keys()


func _resolve(name: String) -> String:
	var n := name.to_lower()
	if _binds.has(n):
		return n
	var alias: String = _aliases.get(n, "")
	return alias if _binds.has(alias) else ""


# ── what drives it ───────────────────────────────────────────────────────────

func set_face_values(values: Dictionary) -> void:
	_face_values = values


## `vrm_expression_set` targets, or null for `vrm_expression_clear`.
func set_overlay(targets: Variant) -> void:
	_overlay = targets if targets is Dictionary else null


## The animation descriptor's frame-windowed expressions ({fps, expressions: [{start_frame, end_frame, targets}]}),
## counted from now. {} clears it.
func set_descriptor(descriptor: Dictionary) -> void:
	_descriptor = descriptor
	_descriptor_started = Time.get_ticks_msec() / 1000.0


## Viseme weights by letter (A I U E O); the room only has the amplitude, so it drives A.
func set_visemes(weights: Dictionary) -> void:
	_visemes = weights


## How open their mouth is, from how loud they are right now (0..1): smoothed and capped like the WebUI's.
func speak_level(level: float) -> void:
	var target := minf(MOUTH_OPEN_CAP, sqrt(maxf(level, 0.0)) * 1.6)
	_mouth += (target - _mouth) * MOUTH_SMOOTHING
	_visemes = {"A": 0.0 if _mouth < 0.02 else _mouth}


func mouth_open() -> float:
	return _mouth


# ── each frame ───────────────────────────────────────────────────────────────

func update(delta: float) -> void:
	var composed: Dictionary = {}
	for name: String in _face_values:
		_accumulate_emotion(composed, name, float(_face_values[name]))
	for pair: Array in _descriptor_targets():
		_accumulate(composed, str(pair[0]), float(pair[1]))
	if _overlay is Dictionary:
		for name: String in (_overlay as Dictionary):
			_accumulate(composed, name, float((_overlay as Dictionary)[name]))

	# The automatic blink, unless something else is already driving it.
	var blink_driven := composed.has("blink")
	_update_blink(delta, blink_driven)
	if not blink_driven and _blink_weight > 0.0:
		composed["blink"] = _blink_weight

	# The mouth last: it wins over an emotion's mouth.
	var map: Dictionary = blendshape_map.get("visemes", {}) if blendshape_map.get("visemes") is Dictionary else {}
	for letter: String in _visemes:
		var weight := float(_visemes[letter])
		if weight <= 0.0:
			continue
		var targets: Variant = map.get(letter)
		if targets is Dictionary:
			for name: String in (targets as Dictionary):
				composed[name] = weight * float((targets as Dictionary)[name])
		else:
			composed[{"A": "aa", "I": "ih", "U": "ou", "E": "ee", "O": "oh"}.get(letter, "aa")] = weight

	_write(composed)


## The server's EMOTION state: `happy 0.65` is the persona's soft smile at 65%, never the model's "happy" expression
## at 65% (that one is the whole joy face: eyes shut, mouth wide open, which on top of `relaxed 0.5` was the dopey
## grin they wore for as long as the server held the emotion). The legacy WebUI reads it the same way (its
## `__synth_emotion_face_presets`). An emotion with several targets on one expression keeps the strongest.
func _accumulate_emotion(composed: Dictionary, name: String, value: float) -> void:
	var preset: Variant = emotions.get(name)
	if not (preset is Dictionary):
		_accumulate(composed, name, value)
		return
	for logical: String in (preset as Dictionary):
		var mapped: Variant = blendshape_map.get(logical)
		var key: String = str(mapped) if mapped is String else logical
		var weight := float((preset as Dictionary)[logical]) * value
		composed[key] = maxf(float(composed.get(key, 0.0)), weight)


func _accumulate(composed: Dictionary, name: String, value: float) -> void:
	var mapped: Variant = blendshape_map.get(name)
	composed[str(mapped) if mapped is String else name] = value


func _descriptor_targets() -> Array:
	var out: Array = []
	var list: Variant = _descriptor.get("expressions")
	if not (list is Array):
		return out
	var fps := float(_descriptor.get("fps", 30.0))
	var frame := (Time.get_ticks_msec() / 1000.0 - _descriptor_started) * (fps if fps > 0.0 else 30.0)
	for e: Variant in list:
		if not (e is Dictionary):
			continue
		var entry: Dictionary = e
		if frame < float(entry.get("start_frame", 0)):
			continue
		if entry.has("end_frame") and frame > float(entry["end_frame"]):
			continue
		if entry.get("targets") is Dictionary:
			for name: String in (entry["targets"] as Dictionary):
				out.append([name, float((entry["targets"] as Dictionary)[name])])
	return out


## Zero what was driven last frame, then drive the new weights (a dropped source lets go).
func _write(composed: Dictionary) -> void:
	for key: String in _driven:
		_set_expression(key, 0.0)
	_driven.clear()
	applied = {}
	for name: String in composed:
		var key := _resolve(name)
		if key == "":
			continue
		var value := clampf(float(composed[name]), 0.0, 1.0)
		_set_expression(key, value)
		_driven[key] = true
		applied[key] = value


func _set_expression(key: String, value: float) -> void:
	for b: Dictionary in _binds.get(key, []):
		var mi: MeshInstance3D = b["mi"]
		if is_instance_valid(mi) and int(b["idx"]) >= 0 and int(b["idx"]) < mi.get_blend_shape_count():
			mi.set_blend_shape_value(int(b["idx"]), value * float(b["w"]))


func _update_blink(delta: float, suppressed: bool) -> void:
	if suppressed or not auto_blink:
		_blink_phase = "idle"
		_blink_weight = 0.0
		return
	match _blink_phase:
		"idle":
			_blink_timer += delta
			if _blink_timer >= _next_blink:
				_blink_phase = "closing"
				_blink_phase_time = 0.0
		"closing":
			_blink_phase_time += delta
			_blink_weight = minf(1.0, _blink_phase_time / BLINK_CLOSE)
			if _blink_phase_time >= BLINK_CLOSE:
				_blink_phase = "hold"
				_blink_phase_time = 0.0
		"hold":
			_blink_phase_time += delta
			_blink_weight = 1.0
			if _blink_phase_time >= BLINK_HOLD:
				_blink_phase = "opening"
				_blink_phase_time = 0.0
		"opening":
			_blink_phase_time += delta
			_blink_weight = maxf(0.0, 1.0 - _blink_phase_time / BLINK_OPEN)
			if _blink_phase_time >= BLINK_OPEN:
				_blink_phase = "idle"
				_blink_weight = 0.0
				_blink_timer = 0.0
				_next_blink = _random_interval()


func _random_interval() -> float:
	return BLINK_MIN_INTERVAL + randf() * (BLINK_MAX_INTERVAL - BLINK_MIN_INTERVAL)


## For the tests: a blink starts now.
func blink_now() -> void:
	_blink_timer = _next_blink
