## WorldView -- what a thing in the room is CALLED when Synth is told about it, and who can see what.
##
## Pure text and maths, so a test can read it. The generic prompt Synth is given (`Nearby entities: ...`) prints an
## entity's `name`, falling back to its `type`, and nothing else: a node called "System" or "@RigidBody3D@4173"
## reaches her as exactly that, and an empty one as an empty line. So `name` here is the thing's NAME FOR A PERSON
## ("Game Boy Color", "VHS tape 2", "unknown item"), unique in the room, and the node's own is kept as `id`.
##
## What a person sees is what is in front of them (about 180 degrees) and not hidden: that is all she is told, and
## she can turn, walk and look to be told more.
extends RefCounted

## The field of view of a person, in degrees, centred straight ahead.
const FOV_DEG := 180.0
## Past this a thing is not told about (a room is not much bigger).
const SEE_RADIUS := 6.0
## What a thing is called when nothing about it says. Never leave a name empty.
const UNKNOWN := "unknown item"

## RetroXR's class (the script's global name) -> what a person calls it.
const KINDS := {
	"RetroSystem": "game console", "RetroCartridge": "game cartridge", "RetroTV": "TV", "RetroDisc": "disc",
	"VCRPlayer": "VCR", "VCRTape": "VHS tape", "DVDPlayer": "DVD player", "BatteryCell": "battery",
	"TVRemote": "TV remote", "Seat": "seat", "Table": "table", "PortCover": "port cover",
	"CompositeCable": "cable", "LinkCable": "link cable", "PowerCord": "power cord", "PowerStrip": "power strip",
	"PowerBrick": "power adapter", "PDFBook": "book", "Poster": "poster", "SpeakerPair": "speaker",
	"RetroKeyboard": "keyboard", "RetroMouse": "mouse", "Antenna": "antenna", "Wiimote": "Wii remote",
	"Nunchuk": "Nunchuk", "SensorBar": "sensor bar", "MemoryCard": "memory card",
}
## What Godot calls a node that has no script of its own: it says nothing about the thing.
const GENERIC := ["Node", "Node3D", "RigidBody3D", "StaticBody3D", "CharacterBody3D", "Area3D", "MeshInstance3D", "Object", ""]


## A node name a person could say: engine-made ones ("@RigidBody3D@4173") and empty ones are not names.
static func clean_name(raw: String) -> String:
	var name := raw.strip_edges()
	if name.is_empty() or name.begins_with("@") or name.contains("@"):
		return ""
	return name


## A class turned into words when it is not in KINDS: "RetroGameGear" -> "game gear". "" when it is only an engine
## class (it would say nothing).
static func kind_of(type_name: String) -> String:
	if KINDS.has(type_name):
		return str(KINDS[type_name])
	if type_name in GENERIC:
		return ""
	var stem := type_name.trim_prefix("Retro")
	var words := ""
	for i in stem.length():
		var c := stem[i]
		if i > 0 and c == c.to_upper() and c != c.to_lower() and stem[i - 1] != stem[i - 1].to_upper():
			words += " "
		words += c.to_lower()
	return words.strip_edges()


## The name for a person of one thing. `raw` = {node: the node's own name, type: its class, display: a name the game
## gives it, title: the game or medium in it, machine: what a console is called, systemid}.
static func label_of(raw: Dictionary) -> String:
	var type_name := str(raw.get("type", ""))
	var kind := kind_of(type_name)
	var machine := str(raw.get("machine", "")).strip_edges()
	var title := str(raw.get("title", "")).strip_edges()
	var display := clean_name(str(raw.get("display", "")))
	if type_name == "player":
		return "the player"
	if not machine.is_empty():
		return machine
	if not title.is_empty() and not kind.is_empty():
		return "%s (%s)" % [title, kind]
	if not display.is_empty():
		return display
	var node := clean_name(str(raw.get("node", "")))
	# A node named after its own class says nothing more than the kind does.
	if not node.is_empty() and node.to_lower() != type_name.trim_prefix("Retro").to_lower() and node != type_name \
			and node.to_lower() != kind.replace(" ", ""):
		return node
	if not kind.is_empty():
		return kind
	return UNKNOWN


## Give every entity its `name`/`label`: the label of `label_of`, numbered when several share one ("VHS tape 1",
## "VHS tape 2"), in a stable order (by `id`, never by distance: she moves). `entities` entries carry `raw`.
static func name_all(entities: Array) -> void:
	var by_label: Dictionary = {}
	for e: Dictionary in entities:
		var label := label_of(e.get("raw", {}) as Dictionary)
		e["label"] = label
		if not by_label.has(label):
			by_label[label] = []
		(by_label[label] as Array).append(e)
	for label: String in by_label:
		var group: Array = by_label[label]
		group.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("id_num", 0)) < int(b.get("id_num", 0)))
		for i in group.size():
			var shown := label if group.size() == 1 else "%s %d" % [label, i + 1]
			(group[i] as Dictionary)["name"] = shown
			(group[i] as Dictionary)["label"] = shown


## Is `target` inside a person's field of view from `origin` facing `forward`? (Flat, around the up axis.)
static func in_view(origin: Vector3, forward: Vector3, target: Vector3, fov_deg: float = FOV_DEG) -> bool:
	var f := Vector2(forward.x, forward.z)
	var d := Vector2(target.x - origin.x, target.z - origin.z)
	if d.length() < 0.05:
		return true  # on top of her
	if f.length() < 0.0001:
		return false
	return absf(rad_to_deg(f.normalized().angle_to(d.normalized()))) <= fov_deg * 0.5


## Does what she asked for match this entity's name? Exact (case-folded) first, then a part of it ("vhs" ~ "VHS tape 2").
static func matches(entity: Dictionary, query: String) -> int:
	var q := query.strip_edges().to_lower()
	if q.is_empty():
		return 0
	var name_l := str(entity.get("name", "")).to_lower()
	var id_l := str(entity.get("id", "")).to_lower()
	var kind_l := str(entity.get("type", "")).to_lower()
	if q == name_l or q == id_l:
		return 2
	if name_l.contains(q) or kind_l == q or (q.length() > 2 and kind_l.contains(q)):
		return 1
	# "gameboy" / "game boy": spaces do not matter to a person.
	if name_l.replace(" ", "").contains(q.replace(" ", "")):
		return 1
	return 0
