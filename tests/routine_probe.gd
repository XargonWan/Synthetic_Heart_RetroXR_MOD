## A routine that cannot do what it was asked says so. `bring` used to end with NO result when the pick-up failed (a thing
## too big, one not there): the model heard nothing and asked again, for ever (three `bring`s in one real session).
## Each case below is a way that ended silently; the control is a small box, which they do pick up.
##
##   godot --headless --path RetroXR res://mods/xenu.synth_rift/tests/routine_probe.tscn
extends Node

const SynthBody := preload("res://mods/xenu.synth_rift/scripts/synth_body.gd")

var _count := 0
var _failed := 0
var _body: CharacterBody3D
var _done: Array = []


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
	_body.routine_done.connect(func(kind: String, ok: bool, summary: String, _d: Dictionary) -> void:
		_done.append({"kind": kind, "ok": ok, "summary": summary}))
	# The room is asked afresh every time, as the real one is: a thing they carried and set down is no longer where it was.
	var nodes: Array = []
	_body.sight = func() -> Array:
		var out: Array = []
		for n: Node3D in nodes:
			out.append(_entity(n))
		return out
	_body.world_lookup = func(q: String) -> Dictionary:
		for n: Node3D in nodes:
			if n.name.to_lower() == q.to_lower():
				return _entity(n)
		return {}
	await get_tree().physics_frame

	var small := _thing("Crate", Vector3(0.2, 0.2, 0.2), Vector3(0.0, 0.1, -1.2), true)
	var big := _thing("Wardrobe", Vector3(0.7, 1.8, 0.5), Vector3(1.2, 0.9, -1.0), true)
	var fixed := _thing("Statue", Vector3(0.2, 0.3, 0.2), Vector3(-1.2, 0.15, -1.0), false)
	var hidden_big := _thing("Phone", Vector3(0.1, 0.02, 0.2), Vector3(0.0, 0.05, 1.5), true)
	# a huge mesh that is NOT drawn (a helper): it must not make the phone "too big"
	var ghost := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(3, 3, 3)
	ghost.mesh = gm
	ghost.visible = false
	hidden_big.add_child(ghost)
	nodes.append_array([small, big, fixed, hidden_big])
	await get_tree().physics_frame

	# 1. too big
	var r: Variant = await _run("bring", {"name": "Wardrobe"})
	_check(r != null and not r["ok"] and r["kind"] == "bring", "bring of a thing too big ends with a result (not silence)")
	_check(r != null and str(r["summary"]).contains("too big"), "and says why: %s" % (str(r["summary"]) if r != null else "none"))
	_check(not _body.routines.is_busy(), "and the routine is over (not 'running' for ever)")
	# 2. fixed in place
	r = await _run("bring", {"name": "Statue"})
	_check(r != null and not r["ok"] and str(r["summary"]).contains("fixed in place"), "a thing that is not loose: %s" % (str(r["summary"]) if r != null else "none"))
	# 3. nothing of that name
	r = await _run("bring", {"name": "Spaceship"}, 90.0)   # it looks round the room first: up to a minute
	_check(r != null and not r["ok"] and r["kind"] == "bring", "a thing that is not there ends with a result for the bring, not a search")
	# 4. the same through pick_up (it always reported)
	r = await _run("pick_up", {"name": "Wardrobe"})
	_check(r != null and not r["ok"] and r["kind"] == "pick_up" and str(r["summary"]).contains("too big"), "pick_up says the same")
	# 5. a hidden helper mesh does not make a small thing big
	_check(_body.lift_size(hidden_big) < 0.3, "an undrawn mesh is not counted (%.2f m)" % _body.lift_size(hidden_big))
	_check(_body.lift_size(big) > 1.5, "(control) a drawn tall thing is measured (%.2f m)" % _body.lift_size(big))
	# 6. control: a small box is picked up
	r = await _run("pick_up", {"name": "Crate"})
	_check(r != null and r["ok"] and _body.holding() != "", "(control) a small crate is picked up (%s)" % (str(r["summary"]) if r != null else "none"))
	# 7. hands full: bring says so
	r = await _run("bring", {"name": "Phone"})
	_check(r != null and not r["ok"] and r["kind"] == "bring" and str(r["summary"]).contains("hands are full"), "with hands full a bring says so")
	await _inspect_cases(small, big, fixed, hidden_big)
	await _flight_cases(small)
	print("[probe] %d cases, %d failed" % [_count, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


## `inspect` goes over to the thing and takes it in their hands when it can be lifted. It used to turn the head and read out
## a distance. CONTROLS: a thing too big is walked up to and left alone; a name that is not there is refused at once.
func _inspect_cases(small: Node3D, big: Node3D, fixed: Node3D, phone: Node3D) -> void:
	_body.put_down()
	_body.global_position = Vector3(3.0, 0.01, 3.0)
	await get_tree().physics_frame
	var start := _body.global_position
	var crate_at := small.global_position
	var immediate: Dictionary = _body.act("inspect", {"target": "Crate"})
	_check(bool(immediate.get("ok", false)) and str(immediate.get("detail", "")).contains("going over to"), "inspect answers at once that they are going over: %s" % str(immediate.get("detail", "")))
	_check(_body.routines.is_busy(), "and the walk goes on after the answer")
	var r: Variant = await _wait_done()
	var near := Vector2(_body.global_position.x - crate_at.x, _body.global_position.z - crate_at.z).length()
	_check(r != null and r["kind"] == "inspect" and r["ok"], "the result comes afterwards, as an event (%s)" % (str(r["summary"]) if r != null else "none"))
	_check(_body.global_position.distance_to(start) > 2.0 and near < 0.9, "they WALKED to it (%.1f m moved, %.2f m from the crate)" % [_body.global_position.distance_to(start), near])
	_check(_body.holding() == "Crate", "and took it in their hands (holding %s)" % _body.holding())
	_check(r != null and str(r["summary"]).contains("You are holding it now"), "and say so")
	# a second thing too big to lift: they keep the crate in their hands while they look at it
	var wardrobe_at := big.global_position
	_body.act("inspect", {"target": "Wardrobe"})
	r = await _wait_done()
	_check(r != null and r["ok"] and str(r["summary"]).contains("too big"), "a wardrobe is walked up to and left where it is: %s" % (str(r["summary"]) if r != null else "none"))
	_check(_body.holding() == "Crate", "and the crate is still in their hands (holding '%s')" % _body.holding())
	_check(big.global_position.distance_to(wardrobe_at) < 0.05, "(control) the wardrobe has not moved")
	_check(Vector2(_body.global_position.x - wardrobe_at.x, _body.global_position.z - wardrobe_at.z).length() < 1.8, "they stand in front of it")
	_body.act("inspect", {"target": "Statue"})
	r = await _wait_done()
	_check(r != null and r["ok"] and str(r["summary"]).contains("fixed in place") and _body.holding() == "Crate", "a fixed thing too: looked at, not taken (%s)" % (str(r["summary"]) if r != null else "none"))
	_check(fixed.global_position.distance_to(Vector3(-1.2, 0.15, -1.0)) < 0.05, "(control) and not moved")
	# a second thing they CAN lift: the crate is set down where they stand, and the phone is in their hands
	var crate_down := small.global_position
	_body.act("inspect", {"target": "Phone"})
	r = await _wait_done()
	_check(r != null and r["ok"] and _body.holding() == "Phone", "a second liftable thing: the phone is in their hands (holding '%s')" % _body.holding())
	_check(small.global_position.distance_to(crate_down) < 1.5 and small.global_position.distance_to(phone.global_position) > 0.2, "and the crate they held was set down, not carried along")
	_check(str(r["summary"]).contains("You are holding it now"), "and they say so")
	var nope: Dictionary = _body.act("inspect", {"target": "Spaceship"})
	_check(not bool(nope.get("ok", true)) and str(nope.get("detail", "")).contains("nothing called"), "(control) a name that is not there is refused at once: %s" % str(nope.get("detail", "")))
	_check(not _body.routines.is_busy(), "and starts nothing")


func _wait_done(seconds: float = 40.0) -> Variant:
	_done.clear()
	for i in int(seconds * 10.0):
		await get_tree().create_timer(0.1).timeout
		if not _done.is_empty():
			return _done[_done.size() - 1]
	return null


## A thing in the room; `loose` = a RigidBody3D, else a static one.
func _thing(label: String, size: Vector3, at: Vector3, loose: bool) -> Node3D:
	var n: Node3D = RigidBody3D.new() if loose else StaticBody3D.new()
	n.name = label
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
	return n


func _entity(n: Node3D) -> Dictionary:
	var d := _body.global_position.distance_to(n.global_position)
	return {"id": n.name, "name": n.name, "label": n.name, "type": "Node3D", "node": n, "position": n.global_position,
		"distance": d, "side": "ahead", "front": true, "bearing": 0.0}


## Start a routine and wait for its result event (null on a timeout: the silence this probe is about).
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


## What they take travels to their hands (about half a second, an arc) instead of snapping there. CONTROL: a second later it IS
## in their hands, and it does not stay where it was.
func _flight_cases(thing: Node3D) -> void:
	_body.put_down()
	_body.global_position = Vector3(-6.0, 0.01, 6.0)
	await get_tree().physics_frame
	thing.global_position = _body.global_position + Vector3(0.0, 0.8, -1.4)   # on a table, a metre and a half off
	var from := thing.global_position
	var took: bool = _body.hold(thing, "Crate")
	_check(took, "(control) the thing is taken")
	var hands: Vector3 = _body.hand_point()
	await get_tree().create_timer(0.1).timeout
	var early := thing.global_position.distance_to(hands)
	var started := from.distance_to(hands)
	_check(early > started * 0.6, "a tenth of a second in it has barely left the table (%.2f of %.2f m still to go)" % [early, started])
	await get_tree().create_timer(0.25).timeout
	var mid := thing.global_position.distance_to(hands)
	_check(mid > 0.15 and mid < early, "and is on its way half way (%.2f m to go)" % mid)
	await get_tree().create_timer(0.6).timeout
	_check(thing.global_position.distance_to(_body.hand_point()) < 0.06, "and in their hands by the end (%.3f m off)" % thing.global_position.distance_to(_body.hand_point()))
	_body.put_down()
