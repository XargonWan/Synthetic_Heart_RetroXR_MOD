## `operate`: they walk up to a machine and work it, put a cartridge in, take one out, and never play. Stand-ins with a RetroXR
## machine's method names (SynthUse asks by method) in a real body, real physics and the real routines: the walk, the
## hands and the words they report are the room's, only the machines are fake.
##
## The scene of the TODO: switch the TV on and change its volume; "play Tetris on the Game Boy" is refused WITHOUT walking
## anywhere; fetch the cartridge, put it in the Game Boy, take the Game Boy in their hands, switch it on, look at its
## screen; a cartridge that sits in a console is taken out of it before it is carried.
##
##   godot --headless --path RetroXR res://mods/xenu.synth_rift/tests/operate_probe.tscn
extends Node

const SynthBody := preload("res://mods/xenu.synth_rift/scripts/synth_body.gd")

var _count := 0
var _failed := 0
var _body: CharacterBody3D
var _done: Array = []
var _nodes: Array = []


class FakeTV extends StaticBody3D:
	var on := false
	var vol := 0.5
	func is_on() -> bool: return on
	func set_power(v: bool) -> void: on = v
	func volume() -> float: return vol
	func remote_volume_up() -> void: vol = minf(1.0, vol + 0.1)
	func remote_volume_down() -> void: vol = maxf(0.0, vol - 0.1)
	func remote_mute_toggle() -> void: pass


class FakeVCR extends RigidBody3D:
	var tape: Node3D = null
	var pressed: Array = []
	func has_media() -> bool: return tape != null
	func remote_play() -> void: pressed.append("play")
	func remote_rewind() -> void: pressed.append("rewind")
	func remote_eject() -> void: tape = null
	func get_snapped_tape() -> Node3D: return tape
	func restore_media(t: Node3D, _y: float = 0.0) -> void: tape = t


class FakeConsole extends RigidBody3D:
	var is_powered_on := false
	var cart: Node3D = null
	func set_power(v: bool) -> void: is_powered_on = v
	func accepts_media(m: Node3D) -> bool: return str(m.get_meta("systemid", "")) == "gb"
	func restore_cartridge(c: Node3D, _y: float = 0.0) -> void:
		cart = c
		c.global_position = global_position
	func get_snapped_cartridge() -> Node3D: return cart
	func net_release_cartridge() -> void: cart = null


func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(30, 1, 30)
	fs.shape = fb
	floor_body.add_child(fs)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)
	_body = SynthBody.new()
	add_child(_body)
	_body.anchor = Vector3.ZERO
	_body.routine_done.connect(func(kind: String, ok: bool, summary: String, d: Dictionary) -> void:
		_done.append({"kind": kind, "ok": ok, "summary": summary, "data": d}))
	_body.sight = func() -> Array:
		var out: Array = []
		for n: Node3D in _nodes:
			out.append(_entity(n))
		return out
	_body.world_lookup = func(q: String) -> Dictionary:
		for n: Node3D in _nodes:
			if n.name.to_lower() == q.to_lower():
				return _entity(n)
		return {}
	await get_tree().physics_frame

	var tv := FakeTV.new()
	_add(tv, "TV", "TV", Vector3(-3.0, 0.5, -3.0), Vector3(0.6, 0.6, 0.5), false)
	var vcr := FakeVCR.new()
	_add(vcr, "VCR", "VCR", Vector3(-3.0, 0.1, -2.0), Vector3(0.4, 0.1, 0.3), true)
	var gb := FakeConsole.new()
	_add(gb, "Game Boy", "game console", Vector3(3.0, 0.05, -2.0), Vector3(0.1, 0.1, 0.15), true)
	var mario := RigidBody3D.new()
	mario.set_meta("systemid", "gb")
	_add(mario, "Mario", "game cartridge", Vector3(0.0, 0.05, -3.0), Vector3(0.06, 0.08, 0.02), true)
	var zelda := RigidBody3D.new()
	zelda.set_meta("systemid", "snes")
	_add(zelda, "Zelda", "game cartridge", Vector3(1.0, 0.05, -3.0), Vector3(0.06, 0.08, 0.02), true)
	var tetris := RigidBody3D.new()
	tetris.set_meta("systemid", "gb")
	_add(tetris, "Tetris", "game cartridge", Vector3(2.0, 0.05, -3.0), Vector3(0.06, 0.08, 0.02), true)
	await get_tree().physics_frame

	# ── the TV, from across the room ──
	var start := _body.global_position
	var r: Variant = await _run("operate", {"interaction": "turn on", "target": "TV"})
	_check(r != null and r["ok"] and tv.on, "turn on the TV: it is on (%s)" % _text(r))
	_check(_body.global_position.distance_to(start) > 2.0, "they walked to it first (%.1f m)" % _body.global_position.distance_to(start))
	_check(r != null and str(r["summary"]).contains("switched on"), "and are told what the room shows")
	var v0 := tv.vol
	r = await _run("operate", {"interaction": "volume up", "target": "TV"})
	_check(r != null and r["ok"] and tv.vol > v0 + 0.15, "volume up (%.2f -> %.2f)" % [v0, tv.vol])
	r = await _run("operate", {"interaction": "turn down the volume", "target": "TV"})
	_check(r != null and r["ok"] and tv.vol < v0 + 0.15, "volume down (%.2f)" % tv.vol)
	r = await _run("operate", {"interaction": "turn off", "target": "TV"})
	_check(r != null and r["ok"] and not tv.on, "turn off")
	r = await _run("operate", {"interaction": "rewind", "target": "TV"})
	_check(r != null and not r["ok"] and str(r["summary"]).contains("You can"), "a TV does not rewind, and they are told what it does (%s)" % _text(r))

	# ── the VCR ──
	vcr.tape = RigidBody3D.new()
	add_child(vcr.tape)
	r = await _run("operate", {"interaction": "rewind", "target": "VCR"})
	_check(r != null and r["ok"] and vcr.pressed == ["rewind"], "rewind the tape")
	r = await _run("operate", {"interaction": "eject", "target": "VCR"})
	_check(r != null and r["ok"] and vcr.tape == null, "eject")

	# ── a game: refused where they stand ──
	_body.global_position = Vector3(0.0, 0.01, 0.0)
	await get_tree().physics_frame
	start = _body.global_position
	r = await _run("operate", {"interaction": "play tetris", "target": "Game Boy"})
	_check(r != null and not r["ok"] and str(r["summary"]).contains("cannot play"), "play Tetris on the Game Boy: refused (%s)" % _text(r))
	_check(_body.global_position.distance_to(start) < 0.2, "without walking anywhere")
	_check(r != null and str(r["summary"]).contains("put it in the console"), "and told what they can do: cartridge in, switch on, look at the screen")
	r = await _run("operate", {"interaction": "play", "target": "Game Boy"})
	_check(r != null and not r["ok"] and str(r["summary"]).contains("cannot play"), "a bare 'play' on a console is a game too")
	r = await _run("operate", {"interaction": "dance", "target": "Game Boy"})
	_check(r != null and not r["ok"] and str(r["summary"]).contains("volume"), "something they cannot do lists what they can")

	# ── the whole Game Boy scene ──
	r = await _run("operate", {"interaction": "insert", "target": "Game Boy"})
	_check(r != null and not r["ok"] and str(r["summary"]).contains("nothing to put"), "insert with empty hands says to pick one up (%s)" % _text(r))
	r = await _run("pick_up", {"target": "Mario"})
	_check(r != null and r["ok"] and _body.holding() == "Mario", "pick up the cartridge (holding %s)" % _body.holding())
	r = await _run("operate", {"interaction": "insert", "target": "Zelda"})
	_check(r != null and not r["ok"], "the wrong cartridge into a thing with no slot is refused (%s)" % _text(r))
	r = await _run("operate", {"interaction": "insert", "target": "Game Boy"})
	_check(r != null and r["ok"] and gb.cart == mario and _body.holding() == "", "put it in the Game Boy: seated, hands free (%s)" % _text(r))
	_check(r != null and str(r["summary"]).contains("switched off"), "and told the console is off")
	r = await _run("pick_up", {"target": "Game Boy"})
	_check(r != null and r["ok"] and _body.holding() == "Game Boy", "take the Game Boy in their hands")
	r = await _run("operate", {"interaction": "turn on"})
	_check(r != null and r["ok"] and gb.is_powered_on, "turn it on with no name: it is the thing in their hands (%s)" % _text(r))
	var here := _body.global_position
	r = await _run("watch", {"target": "Game Boy", "seconds": 3.0})
	_check(r != null and r["kind"] == "watch" and _body.global_position.distance_to(here) < 0.5, "look at its screen without backing away from it (%.2f m)" % _body.global_position.distance_to(here))
	_check(_body.holding() == "Game Boy", "still holding it")
	r = await _run("operate", {"interaction": "insert", "target": "Game Boy", "with": "Zelda"})
	_check(r != null and not r["ok"] and str(r["summary"]).contains("already has"), "a console with a cartridge in it takes no second one (%s)" % _text(r))
	gb.cart = null   # (taken out by hand)
	# ONE thing at a time, except putting two together: with the console in their hands the cartridge is a second thing,
	# held only for as long as it takes, and it goes in; the console stays in their hands.
	r = await _run("operate", {"interaction": "insert", "target": "Game Boy", "with": "Tetris"}, 60.0)
	_check(r != null and r["ok"] and gb.cart == tetris, "the console in their hands and the cartridge fetched as a second thing: it goes in (%s)" % _text(r))
	_check(_body.holding() == "Game Boy" and _body.extra_holding() == "", "and they hold the console and nothing else (holding '%s', second '%s')" % [_body.holding(), _body.extra_holding()])
	# anything else in their hands must be set down first
	gb.cart = null
	_body.put_down()
	await get_tree().physics_frame
	var held_other: bool = _body.hold(zelda, "Zelda")
	_check(held_other, "(control) they hold the Zelda cartridge")
	r = await _run("operate", {"interaction": "insert", "target": "Game Boy", "with": "Tetris"})
	_check(r != null and not r["ok"] and str(r["summary"]).contains("hands are full") and _body.extra_holding() == "", "holding something unrelated: told to put it down first, no second thing taken (%s)" % _text(r))
	_check(not _body.hold_extra(tetris, "Tetris") or _body.holding() == "Zelda", "(control) a second thing is only taken in a combination, never on its own")
	_body.release_extra()
	_body.put_down()
	gb.cart = mario
	await get_tree().physics_frame

	# ── a cartridge that is in a console is taken out before it is carried ──
	_check(gb.cart == mario, "(the cartridge is in the console)")
	r = await _run("pick_up", {"target": "Mario"})
	_check(r != null and r["ok"] and gb.cart == null and _body.holding() == "Mario", "bring me Mario: taken out of the Game Boy first (%s)" % _text(r))
	# `combine` is the same hands with the world's own words: one thing into another, reported as its own result.
	r = await _run("combine", {"target": "Game Boy", "how": "set it on fire"})
	_check(r != null and r["kind"] == "combine" and not r["ok"] and str(r["summary"]).contains("cannot combine") and _body.holding() == "Mario", "combine in a way that is not possible: told what is (%s)" % _text(r))
	r = await _run("combine", {"target": "Game Boy"})
	_check(r != null and r["kind"] == "combine" and r["ok"] and gb.cart == mario and _body.holding() == "", "combine the cartridge in their hands with the Game Boy: seated, hands free (%s)" % _text(r))
	_body.put_down()

	print("[probe] %d cases, %d failed" % [_count, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _text(r: Variant) -> String:
	return str(r["summary"]) if r != null else "no result"


func _add(n: Node3D, label: String, kind: String, at: Vector3, size: Vector3, loose: bool) -> void:
	n.name = label
	n.set_meta("kind", kind)
	var s := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	s.shape = b
	n.add_child(s)
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	m.mesh = bm
	n.add_child(m)
	add_child(n)
	n.position = at
	if n is RigidBody3D:
		(n as RigidBody3D).freeze = true
	n.add_to_group("spawned")
	_nodes.append(n)


func _entity(n: Node3D) -> Dictionary:
	var d := _body.global_position.distance_to(n.global_position)
	return {"id": n.name, "name": n.name, "label": n.name, "type": str(n.get_meta("kind", "Node3D")), "node": n, "position": n.global_position,
		"distance": d, "side": "ahead", "front": true, "bearing": 0.0}


func _run(verb: String, payload: Dictionary, seconds: float = 40.0) -> Variant:
	_done.clear()
	_body.act(verb, payload)
	for i in int(seconds * 10.0):
		await get_tree().create_timer(0.1).timeout
		if not _done.is_empty():
			return _done[_done.size() - 1]
	return null


func _check(ok: bool, what: String) -> void:
	_count += 1
	if not ok:
		_failed += 1
	print("[probe] %s: %s" % ["ok" if ok else "FAIL", what])
