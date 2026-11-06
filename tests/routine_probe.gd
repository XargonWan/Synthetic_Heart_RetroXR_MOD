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
	await _table_cases(nodes)
	await _give_cases(nodes, small, fixed)
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
	_check(_body.global_position.distance_to(start) > 2.0 and near < 2.0, "they WALKED to it (inside the grab reach) (%.1f m moved, %.2f m from the crate)" % [_body.global_position.distance_to(start), near])
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


## A VCR in the middle of a table: they cannot walk up to it (the table is in the way), so they take it from the table's edge.
## It used to end with "you could not get up to it" for ever. CONTROLS: one too far in for the arm is refused, and the answer
## names the table; the thing has not moved.
func _table_cases(nodes: Array) -> void:
	_body.put_down()
	var table := _thing("Table", Vector3(3.4, 0.8, 4.0), Vector3(4.5, 0.4, -3.0), false)
	table.set_meta("kind", "table")
	var vcr := _thing("VCR", Vector3(0.3, 0.1, 0.3), Vector3(4.5, 0.85, -1.9), true)
	var deep := _thing("Tape", Vector3(0.2, 0.05, 0.2), Vector3(4.5, 0.825, -3.2), true)
	nodes.append_array([table, vcr, deep])
	_body.global_position = Vector3(4.5, 0.01, 1.5)
	await get_tree().physics_frame
	var r: Variant = await _run("inspect", {"target": "VCR"})
	_check(r != null and r["ok"] and _body.holding() == "VCR", "a VCR on a table is taken from its edge (holding '%s': %s)" % [_body.holding(), str(r["summary"]) if r != null else "none"])
	_check(table.global_position.distance_to(Vector3(4.5, 0.4, -3.0)) < 0.05, "(control) the table has not moved")
	_body.put_down()
	r = await _run("pick_up", {"name": "Tape"})
	_check(r != null and not r["ok"] and str(r["summary"]).contains("closest you got") and str(r["summary"]).to_lower().contains("table"), "one too far in is refused and the answer names the table: %s" % (str(r["summary"]) if r != null else "none"))
	_check(_body.holding() == "", "(control) and nothing is held")


## Setting a thing down on something, holding it out, following. `put_down` with a `target` sets the thing on top of it (and
## says where); a thing with no top is refused and stays in their hands. A `hand_over` that is NOT taken is not followed by a
## put-down: they are told, and still hold it (what to do with it is the model's). The offer lasts as long as the model chose
## (within limits, else a fallback). CONTROLS: the clamps of that time; `stop` ends following.
func _give_cases(nodes: Array, crate: Node3D, statue: Node3D) -> void:
	_body.put_down()
	_body.global_position = Vector3(0.0, 0.01, 0.5)
	await get_tree().physics_frame
	_check(_body.hold(crate, "Crate"), "(control) the crate is in their hands")
	var r: Variant = await _run("put_down", {"target": statue.name})
	_check(r != null and not r["ok"] and str(r["summary"]).contains("no flat top") and _body.holding() == "Crate", "a thing with no top is refused and the crate stays in their hands (%s)" % (str(r["summary"]) if r != null else "none"))
	var desk := _thing("Desk", Vector3(1.6, 0.8, 1.0), Vector3(-6.0, 0.4, -6.0), false)
	desk.add_to_group("spawned")
	nodes.append(desk)
	_body.global_position = Vector3(-6.0, 0.01, -3.5)
	await get_tree().physics_frame
	r = await _run("put_down", {"target": "Desk"}, 60.0)
	_check(r != null and r["ok"] and _body.holding() == "" and str(r["summary"]).contains("Desk"), "put it on the desk: set down, and told where (%s)" % (str(r["summary"]) if r != null else "none"))
	_check(absf(crate.global_position.x + 6.0) < 0.9 and absf(crate.global_position.z + 6.0) < 0.6, "and it is over the desk (%.2f, %.2f)" % [crate.global_position.x, crate.global_position.z])
	await get_tree().create_timer(0.5).timeout
	_check(crate.global_position.y > 0.7 and crate.global_position.y < 1.2, "and on its top, not through it (y %.2f)" % crate.global_position.y)

	# holding it out, not taken
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(-6.0, 1.6, -0.5)
	cam.current = true
	await get_tree().physics_frame
	_check(_body.hold(crate, "Crate"), "(control) the crate is taken again")
	_done.clear()
	_body.act("hand_over", {"seconds": 4.0})
	var offered := false
	for _i in 400:
		await get_tree().create_timer(0.1).timeout
		offered = offered or bool(_body.routines.offering)
		if not _done.is_empty():
			break
	r = _done[_done.size() - 1] if not _done.is_empty() else null
	_check(offered, "the hands are held out while they offer it")
	_check(not bool(_body.routines.offering), "and not after")
	_check(r != null and r["ok"] and r["kind"] == "hand_over" and str(r["summary"]).contains("did not take it") and str(r["summary"]).contains("still holding"), "not taken: they are told, and are still holding it (%s)" % (str(r["summary"]) if r != null else "none"))
	_check(_body.holding() == "Crate", "and nothing was put down for them")
	cam.queue_free()
	_check(is_equal_approx(float(_body.routines.call("_hold_out_seconds", {"seconds": 500})), 60.0), "the time they chose is capped")
	_check(is_equal_approx(float(_body.routines.call("_hold_out_seconds", {})), 30.0), "no time chosen: the fallback")
	_check(is_equal_approx(float(_body.routines.call("_hold_out_seconds", {"seconds": "soon"})), 30.0), "a time that is no number: the fallback")
	_check(is_equal_approx(float(_body.routines.call("_hold_out_seconds", {"seconds": 1})), 3.0), "and a very short one is lengthened to a few seconds")

	# following
	var fr: Dictionary = await _body.act("follow", {})
	_check(bool(fr.get("ok", false)) and _body.is_following(), "follow: they follow")
	await _body.act("stop", {})
	_check(not _body.is_following(), "stop ends following")
	await _body.act("follow", {})
	await _body.act("unfollow", {})
	_check(not _body.is_following(), "unfollow too")
	_body.put_down()


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
	return {"id": n.name, "name": n.name, "label": n.name, "type": str(n.get_meta("kind", "Node3D")), "node": n, "position": n.global_position,
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
