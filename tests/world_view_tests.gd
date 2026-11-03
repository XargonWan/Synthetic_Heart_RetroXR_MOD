## What a thing in the room is called when Synth is told about it, and who can see what: pure, so no room is needed.
##
##   godot --headless --path RetroXR --script res://mods/xenu.synth_rift/tests/world_view_tests.gd
##
## The log of a real session had her told "Cable / Node3D", "@RigidBody3D@4173" and, once, nothing at all ("The  has
## appeared"), and asking for the "Game Boy" failed because the only thing she knew was `System`.
extends SceneTree

const W := preload("res://mods/xenu.synth_rift/scripts/world_view.gd")

var _failed := 0
var _count := 0


func _init() -> void:
	_names()
	_unique()
	_view()
	_match()
	print("[rift-tests] %d cases, %d failed" % [_count, _failed])
	quit(1 if _failed > 0 or _count == 0 else 0)


func _check(ok: bool, what: String) -> void:
	_count += 1
	if not ok:
		_failed += 1
		print("[rift-tests] FAIL: %s" % what)


func _entity(raw: Dictionary, id_num: int = 1) -> Dictionary:
	return {"id": str(raw.get("node", "x")), "id_num": id_num, "raw": raw, "type": W.kind_of(str(raw.get("type", "")))}


func _names() -> void:
	_check(W.clean_name("@RigidBody3D@4173") == "", "an engine-made name is not a name")
	_check(W.clean_name("  ") == "" and W.clean_name("") == "", "an empty one is not either")
	_check(W.clean_name("Crate") == "Crate", "a real one stays")
	_check(W.label_of({"node": "System", "type": "RetroSystem", "machine": "Game Boy Color"}) == "Game Boy Color", "a console is called what it is")
	_check(W.label_of({"node": "Cartridge", "type": "RetroCartridge", "title": "Pokemon Gold"}) == "Pokemon Gold (game cartridge)", "a cartridge by its game")
	_check(W.label_of({"node": "Cartridge", "type": "RetroCartridge"}) == "game cartridge", "an unlabelled one by its kind (never the node's own name)")
	_check(W.label_of({"node": "@RigidBody3D@4173", "type": "VCRTape"}) == "VHS tape", "an engine name falls back to what it is: %s" % W.label_of({"node": "@RigidBody3D@4173", "type": "VCRTape"}))
	_check(W.label_of({"node": "TV", "type": "RetroTV"}) == "TV", "the TV")
	_check(W.label_of({"node": "Cable", "type": "Node3D"}) == "Cable", "a plain node keeps a name a person could say")
	_check(W.label_of({"node": "@Node3D@2", "type": "Node3D"}) == W.UNKNOWN, "nothing says what it is: %s" % W.label_of({"node": "@Node3D@2", "type": "Node3D"}))
	_check(W.label_of({"node": "", "type": ""}) == "unknown item", "nothing at all: `unknown item`, never an empty line")
	_check(W.label_of({"node": "Thing", "type": "Thing", "display": "Lamp"}) == "Lamp", "a name the game gives it wins")
	_check(W.kind_of("RetroGameGear") == "game gear", "an unknown class turned into words (%s)" % W.kind_of("RetroGameGear"))
	_check(W.kind_of("RigidBody3D") == "", "an engine class says nothing")


func _unique() -> void:
	var list: Array = [_entity({"node": "@RigidBody3D@4173", "type": "VCRTape"}, 30), _entity({"node": "VCRTape", "type": "VCRTape"}, 10),
		_entity({"node": "@RigidBody3D@9", "type": "Node3D"}, 20), _entity({"node": "TV", "type": "RetroTV"}, 5)]
	W.name_all(list)
	_check(list[1]["name"] == "VHS tape 1" and list[0]["name"] == "VHS tape 2", "two of a kind are numbered, in a stable order (%s, %s)" % [list[1]["name"], list[0]["name"]])
	_check(list[2]["name"] == "unknown item", "an unnamed thing is `unknown item` (%s)" % list[2]["name"])
	_check(list[3]["name"] == "TV", "one of a kind is not numbered")
	for e: Dictionary in list:
		_check(not str(e["name"]).strip_edges().is_empty() and not str(e["name"]).contains("@"), "no name is empty or engine-made (%s)" % e["name"])


func _view() -> void:
	var o := Vector3.ZERO
	var fwd := Vector3(0, 0, -1)
	_check(W.in_view(o, fwd, Vector3(0, 0, -3)), "straight ahead is seen")
	_check(W.in_view(o, fwd, Vector3(3, 0, -0.2)), "almost to her right is seen (within 90 degrees)")
	_check(not W.in_view(o, fwd, Vector3(1, 0, 2)), "behind her is not")
	_check(not W.in_view(o, fwd, Vector3(0, 0, 3)), "right behind her is not")
	_check(W.in_view(o, fwd, Vector3(-2, 0, -2)), "ahead and to the left is")
	_check(not W.in_view(o, fwd, Vector3(2, 0, 0.5), 120.0), "a narrower view leaves the side out")
	_check(W.in_view(o, Vector3(1, 0, 0), Vector3(5, 0, 0.1)), "it follows where she faces")


func _match() -> void:
	var gb := {"name": "Game Boy Color", "id": "System", "type": "game console"}
	var tape := {"name": "VHS tape 2", "id": "VCRTape", "type": "VHS tape"}
	_check(W.matches(gb, "Game Boy") == 1, "\"Game Boy\" finds the Game Boy Color")
	_check(W.matches(gb, "gameboy") == 1, "spaces do not matter")
	_check(W.matches(gb, "Game Boy Color") == 2, "the whole name is an exact match")
	_check(W.matches(gb, "game console") == 1, "its kind finds it")
	_check(W.matches(gb, "System") == 2, "and the node's own name still does")
	_check(W.matches(tape, "vhs") == 1 and W.matches(tape, "tv") == 0, "a part of a name, not of another")
	_check(W.matches(gb, "") == 0, "nothing asked, nothing found")
