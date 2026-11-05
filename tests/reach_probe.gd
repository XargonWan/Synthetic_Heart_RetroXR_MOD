## Where there is a way to (SynthNav.reach_*), floor under their feet when nothing leashes them, and the survey the core asks
## for before it sends them walking (SynthBody.survey, a free `move`). Runs in a scene; headless is fine:
##
##   godot --headless --path RetroXR res://mods/xenu.synth_rift/tests/reach_probe.tscn
##
## Every check that could pass for the wrong reason has a CONTROL beside it (the same thing with the thing under test off).
extends Node

const SynthNav := preload("res://mods/xenu.synth_rift/scripts/synth_nav.gd")
const SynthBody := preload("res://mods/xenu.synth_rift/scripts/synth_body.gd")

var _count := 0
var _failed := 0


func _ready() -> void:
	_pure()
	await _in_physics()
	print("[probe] %d cases, %d failed" % [_count, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	_count += 1
	if not ok:
		_failed += 1
	print("[probe] %s: %s" % ["ok" if ok else "FAIL", what])


func _reach(nav: SynthNav, from: Vector3, budget: int = 100000, max_cells: int = 100000) -> Dictionary:
	var st: SynthNav.ReachState = nav.reach_begin(from)
	while not nav.reach_step(st, budget, max_cells):
		pass
	return {"cells": nav.reach_cells(st), "capped": st.capped, "st": st}


# ── on a map drawn here ──────────────────────────────────────────────────────

## Two rooms, 12 x 8 m, a wall at x = 3 with a door at z in [1.0, 2.0].
func _rooms(p: Vector3) -> bool:
	if absf(p.x) > 6.0 or absf(p.z) > 4.0:
		return true
	return absf(p.x - 3.0) < 0.35 and (p.z < 1.0 or p.z > 2.0)


func _pure() -> void:
	var nav := SynthNav.new()
	nav.blocked_fn = _rooms
	nav.leash = INF
	nav.cell_size = SynthNav.SURVEY_CELL
	var r := _reach(nav, Vector3.ZERO)
	var cells: Dictionary = r["cells"]
	var far := Vector2i(roundi(5.0 / 0.4), 0)
	_check(cells.has(far), "(%d cells) the far room is reached" % cells.size())
	_check(float(cells[far]) > 5.5, "and by the DOOR, not through the wall: the way is %.1f m, the straight line 5.0" % float(cells[far]))
	_check(float(cells[Vector2i(roundi(2.0 / 0.4), 0)]) < 2.2, "(control) a place on this side costs about its distance (%.1f m)" % float(cells[Vector2i(5, 0)]))
	_check(not cells.has(Vector2i(roundi(3.0 / 0.4), roundi(-2.0 / 0.4))), "a cell in the wall is not a place")
	_check(not cells.has(Vector2i(roundi(8.0 / 0.4), 0)), "and nothing outside the outer wall")

	var ring := SynthNav.new()
	ring.blocked_fn = func(p: Vector3) -> bool:
		var d := Vector2(p.x - 4.0, p.z).length()
		return d > 1.0 and d < 1.5
	ring.leash = 9.0
	var rr := _reach(ring, Vector3.ZERO, 100000, 3000)
	_check(not (rr["cells"] as Dictionary).has(ring._cell_of(Vector3(4.0, 0, 0))), "inside a sealed ring is not reached")
	_check((rr["cells"] as Dictionary).has(ring._cell_of(Vector3(-4.0, 0, 0))), "(control) outside it is")

	# a few questions at a time reaches exactly the same places as all at once
	var slow := SynthNav.new()
	slow.blocked_fn = _rooms
	slow.leash = INF
	slow.cell_size = SynthNav.SURVEY_CELL
	var rs := _reach(slow, Vector3.ZERO, 25)
	var same := (rs["cells"] as Dictionary).size() == cells.size()
	for c: Vector2i in cells.keys():
		same = same and (rs["cells"] as Dictionary).has(c) and is_equal_approx(float(rs["cells"][c]), float(cells[c]))
	_check(same, "searched 25 questions at a time it finds the same %d places at the same costs" % cells.size())

	var capped := SynthNav.new()
	capped.blocked_fn = _rooms
	capped.leash = INF
	var rc := _reach(capped, Vector3.ZERO, 100000, 60)
	_check(bool(rc["capped"]) and (rc["cells"] as Dictionary).size() <= 60, "the number of cells settled is capped (%d)" % (rc["cells"] as Dictionary).size())

	# floor: the world ends at x = 2
	var edge := SynthNav.new()
	edge.blocked_fn = func(_p: Vector3) -> bool: return false
	edge.leash = INF
	edge.check_ground = true
	edge.ground_fn = func(p: Vector3) -> bool: return p.x < 2.0 and absf(p.z) < 3.0
	var re := _reach(edge, Vector3.ZERO, 100000, 4000)
	var beyond := false
	for c: Vector2i in (re["cells"] as Dictionary).keys():
		beyond = beyond or edge.centre_of(c).x > 2.1
	_check(not beyond and (re["cells"] as Dictionary).size() > 30, "no cell past the edge of the floor (%d cells on it)" % (re["cells"] as Dictionary).size())
	var edgeless := SynthNav.new()
	edgeless.blocked_fn = func(_p: Vector3) -> bool: return false
	edgeless.leash = INF
	edgeless.ground_fn = edge.ground_fn
	var rl := _reach(edgeless, Vector3.ZERO, 100000, 4000)
	var beyond2 := false
	for c: Vector2i in (rl["cells"] as Dictionary).keys():
		beyond2 = beyond2 or edgeless.centre_of(c).x > 2.1
	_check(beyond2, "(control) with the ground check off the same search walks off the edge")

	# a disc: the player
	var disc := SynthNav.new()
	disc.blocked_fn = func(_p: Vector3) -> bool: return false
	disc.leash = 8.0
	disc.discs = [{"pos": Vector3(2.0, 0, 0), "r": 1.0}]
	var p := disc.plan(Vector3.ZERO, Vector3(4.0, 0, 0))
	var into := false
	for q: Vector3 in p["path"]:
		into = into or Vector2(q.x - 2.0, q.z).length() < 1.0
	_check(bool(p["complete"]) and not into and (p["path"] as PackedVector3Array).size() >= 2, "a way round the player's space (%d points)" % (p["path"] as PackedVector3Array).size())
	var nodisc := SynthNav.new()
	nodisc.blocked_fn = func(_p: Vector3) -> bool: return false
	_check(nodisc.plan(Vector3.ZERO, Vector3(4.0, 0, 0))["path"].size() == 1, "(control) without the disc it is one straight leg")
	_check(is_equal_approx(SynthBody.player_space(3.0), 0.9), "the player is given 0.9 m of room")
	_check(SynthBody.player_space(0.6) < 0.9 and SynthBody.player_space(0.6) > 0.3, "less when they already stand nearer (%.2f m at 0.6 m)" % SynthBody.player_space(0.6))
	_check(is_equal_approx(SynthBody.player_space(0.1), 0.3), "and never less than the body's own width")


# ── the real physics world ───────────────────────────────────────────────────

func _box(size: Vector3, at: Vector3, layer: int) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.collision_layer = layer
	var s := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	s.shape = shape
	b.add_child(s)
	b.position = at
	add_child(b)
	return b


func _body() -> CharacterBody3D:
	var body: CharacterBody3D = SynthBody.new()
	add_child(body)
	body.anchor = Vector3.ZERO
	return body


## A floor with a hole in it (x -2..2, z -3..3) and a thin wall (x = -3.4, z -1.5..1.5).
func _in_physics() -> void:
	_box(Vector3(24, 1, 7), Vector3(0, -0.5, -6.5), 1)      # z -10..-3
	_box(Vector3(24, 1, 7), Vector3(0, -0.5, 6.5), 1)       # z 3..10
	_box(Vector3(10, 1, 6), Vector3(-7, -0.5, 0), 1)        # x -12..-2
	_box(Vector3(10, 1, 6), Vector3(7, -0.5, 0), 1)         # x 2..12
	_box(Vector3(0.2, 2.0, 3.0), Vector3(-3.4, 1.0, 0.0), 1)
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := get_viewport().world_3d.direct_space_state
	var ground := SynthNav.new()
	ground.space = space
	ground.leash = INF
	ground.check_ground = true
	var no_ground := SynthNav.new()
	no_ground.space = space
	no_ground.leash = INF
	_check(not ground.clear_line(Vector3(-4.0, 0, 0), Vector3(4.0, 0, 0)), "the real hole: a straight line across it is not walkable")
	_check(no_ground.clear_line(Vector3(-1.5, 0, 0), Vector3(1.5, 0, 0)), "(control) with the ground check off the same line across the hole is 'clear'")
	_check(ground.clear_line(Vector3(-8.0, 0, 0), Vector3(-5.0, 0, 0)), "(control) on the floor it is clear")

	await _survey_checks()
	await _free_walk_checks()
	await _ahead_checks()
	await _player_checks()


func _survey_checks() -> void:
	var body := _body()
	body.global_position = Vector3(-5.0, 0.01, 0.0)
	body.room_name = "den"
	await get_tree().physics_frame
	var space := get_viewport().world_3d.direct_space_state
	body.line_of_sight = func(from: Vector3, to: Vector3, _node: Node, own: RID) -> bool:
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collision_mask = 1
		q.exclude = [own]
		return space.intersect_ray(q).is_empty()
	body.sight = func() -> Array: return [{"name": "TV", "type": "RetroTV", "position": Vector3(-2.6, 0.5, 0.0), "id": "tv"}]
	var roller := RigidBody3D.new()
	roller.gravity_scale = 0.0
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.2
	cs.shape = sh
	roller.add_child(cs)
	roller.collision_layer = 0
	roller.collision_mask = 0
	roller.add_to_group("spawned")
	add_child(roller)
	roller.global_position = Vector3(-8.0, 0.3, -2.0)
	roller.linear_velocity = Vector3(1.0, 0.0, 0.0)

	var res: Dictionary = await body.survey({"viewpoints": [[-5.0, 0.0, 0.0]], "max": 40})
	var d: Dictionary = res.get("data", {})
	var cands: Array = d.get("candidates", [])
	_check(bool(res.get("ok", false)) and cands.size() >= 10 and cands.size() <= 40, "a survey of the floor gives candidates (%d)" % cands.size())
	var in_hole := 0
	var across := 0
	var behind_wall_seen := 0
	var behind_wall := 0
	var in_view := 0
	var in_view_seen := 0
	for c: Dictionary in cands:
		var p: Dictionary = c["pos"]
		if absf(float(p["x"])) < 1.7 and absf(float(p["z"])) < 2.7:
			in_hole += 1
		if float(p["x"]) > 2.3:
			across += 1
			if float(c["cost"]) < Vector2(float(p["x"]) + 5.0, float(p["z"])).length() + 0.5:
				_check(false, "a place across the hole costs no more than the straight line (%.1f)" % float(c["cost"]))
		if float(p["x"]) > -3.3 and float(p["x"]) < -1.9 and absf(float(p["z"])) < 1.5:
			behind_wall += 1
			behind_wall_seen += 1 if bool(c["seen"]) else 0
		if float(p["x"]) < -5.5 and absf(float(p["z"])) < 2.5:
			in_view += 1
			in_view_seen += 1 if bool(c["seen"]) else 0
	_check(in_hole == 0, "no candidate in the hole")
	_check(across > 0, "but there are places across it, reached by going round (%d)" % across)
	_check(in_view > 0 and in_view_seen == in_view, "places in plain view from where they stood are 'seen' (%d of %d)" % [in_view_seen, in_view])
	# every flag must agree with an independent line of sight from where they stood, and some of them must be a "no"
	var wrong := 0
	var hidden := 0
	var from := Vector3(-5.0, 0.0, 0.0) + Vector3(0.0, body.eye_height(), 0.0)
	for c: Dictionary in cands:
		var cp: Dictionary = c["pos"]
		var truth: bool = body.line_of_sight.call(from, Vector3(float(cp["x"]), 0.9, float(cp["z"])), null, body.get_rid())
		if Vector2(float(cp["x"]) + 5.0, float(cp["z"])).length() > body.SURVEY_SIGHT_RANGE:
			truth = false
		if not truth:
			hidden += 1
		if truth != bool(c["seen"]):
			wrong += 1
	_check(hidden > 0 and wrong == 0, "every 'seen' agrees with a line of sight from where they stood, and %d of %d are hidden (%d disagree)" % [hidden, cands.size(), wrong])
	_check(behind_wall_seen == 0, "(what is directly behind the wall: %d candidates, %d marked seen)" % [behind_wall, behind_wall_seen])
	var pois: Array = d.get("pois", [])
	_check(pois.size() == 1 and str(pois[0]["name"]) == "TV" and str(pois[0]["area"]) == "den", "the thing in front of them is a place to go up to, in the room it is in")
	var hz: Array = d.get("hazards", [])
	_check(hz.size() >= 1 and str(hz[0]["kind"]) == "obstacle", "a body rolling about is something to keep clear of (%d)" % hz.size())
	var no_view: Dictionary = await body.survey({"viewpoints": [], "max": 40})
	var unseen_all := true
	for c: Dictionary in no_view["data"]["candidates"]:
		unseen_all = unseen_all and not bool(c["seen"])
	_check(unseen_all, "(control) with nowhere looked from, nothing is 'seen'")
	roller.queue_free()
	body.queue_free()
	await get_tree().physics_frame


func _free_walk_checks() -> void:
	var body := _body()
	body.global_position = Vector3(-8.0, 0.01, 5.0)
	await get_tree().physics_frame
	var far := {"x": 8.0, "y": 0.0, "z": -5.0}
	var leashed: Dictionary = await body.act("move", far)
	_check(not bool(leashed.get("ok", true)) and str(leashed.get("detail", "")).begins_with("too_far_from_the_summoner"),
		"(control) a walk 16 m from the Summoner is refused, as it always was")
	var lowest := [99.0]
	var in_hole := [false]
	var tracker := Timer.new()
	tracker.wait_time = 0.05
	tracker.timeout.connect(func() -> void:
		var p := body.global_position
		lowest[0] = minf(lowest[0], p.y)
		if absf(p.x) < 1.6 and absf(p.z) < 2.6:
			in_hole[0] = true)
	add_child(tracker)
	tracker.start()
	far["free"] = true
	var r: Dictionary = await body.act("move", far)
	tracker.stop()
	_check(bool(r.get("ok", false)), "a free walk of 16 m across the hole's room gets there (%s)" % str(r.get("detail", "")))
	_check(not in_hole[0] and lowest[0] > -0.2, "and never over the hole (lowest %.2f m)" % lowest[0])
	var at: Dictionary = (r.get("data", {}) as Dictionary).get("position", {})
	_check(at.has("x") and absf(float(at["x"]) - 8.0) < 0.6, "the walk says where it ended (x %.1f)" % float(at.get("x", 99.0)))
	# stop ends a walk the core sent them on
	body.global_position = Vector3(-8.0, 0.01, 5.0)
	await get_tree().physics_frame
	var walking: Dictionary = {"x": 8.0, "y": 0.0, "z": 5.0, "free": true}
	var pending: Array = [{}, false]
	_run_move(body, walking, pending)
	await get_tree().create_timer(0.8).timeout
	var stopped: Dictionary = await body.act("stop", {})
	await _until_done(pending)
	_check(bool(stopped.get("ok", false)) and not bool((pending[0] as Dictionary).get("ok", true)) and str((pending[0] as Dictionary).get("detail", "")) == "stopped",
		"`stop` ends the walk at once (%s)" % str((pending[0] as Dictionary).get("detail", "")))
	_check(body.global_position.x < 0.0, "and they are where they were when it came (x %.1f)" % body.global_position.x)
	tracker.queue_free()
	body.queue_free()
	await get_tree().physics_frame


## `out` = [result, done]: GDScript cannot hold on to a void coroutine, so it says when it is over.
func _run_move(body: CharacterBody3D, payload: Dictionary, out: Array) -> void:
	out[0] = await body.act("move", payload)
	out[1] = true


func _until_done(out: Array) -> void:
	var guard := 0
	while not bool(out[1]) and guard < 1200:
		guard += 1
		await get_tree().process_frame


## A thing put onto the way while they walk: they plan round it BEFORE they reach it. CONTROL: the same walk with the free
## options off (what a leashed walk has) stands against it until the stuck check notices.
func _ahead_checks() -> void:
	var stuck_free := await _walk_with_a_box_dropped(true)
	var stuck_old := await _walk_with_a_box_dropped(false)
	_check(stuck_free < 0.6, "a box put on the way is planned round before it is reached (longest standstill %.2f s)" % stuck_free)
	_check(stuck_old >= 1.0, "(control) a leashed walk stands against the same box until the stuck check fires (%.2f s)" % stuck_old)


func _walk_with_a_box_dropped(free: bool) -> float:
	var body := _body()
	body.global_position = Vector3(-10.0, 0.01, 7.0)
	body.anchor = Vector3(-8.0, 0.0, 7.0)
	await get_tree().physics_frame
	var longest := [0.0]
	var tracker := Timer.new()
	tracker.wait_time = 0.05
	tracker.timeout.connect(func() -> void:
		longest[0] = maxf(longest[0], float(body.get("_stuck_for"))))
	add_child(tracker)
	tracker.start()
	var payload := {"x": -4.5, "y": 0.0, "z": 7.0, "free": free}
	var out: Array = [{}, false]
	_run_move(body, payload, out)
	await get_tree().create_timer(0.7).timeout
	# a wall segment 1.6 m wide across the way, ahead of them (x about -8.4 when it appears)
	var wall := _box(Vector3(0.3, 1.8, 1.6), Vector3(-7.6, 0.9, 7.0), 1)
	await _until_done(out)
	tracker.stop()
	tracker.queue_free()
	wall.queue_free()
	body.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	return longest[0]


## The player is in the way (their head is the camera): a free walk passes them at their space, not at arm's length.
## CONTROL: the same walk with nobody there goes straight past the spot.
func _player_checks() -> void:
	var with_player := await _closest_pass(true)
	var alone := await _closest_pass(false)
	_check(with_player >= 0.7, "a walk past the player keeps its distance (%.2f m at the closest)" % with_player)
	_check(alone < 0.4, "(control) with nobody there the same walk goes right by the spot (%.2f m)" % alone)


func _closest_pass(player: bool) -> float:
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_position = Vector3(-7.0, 1.6, 7.0)
	if player:
		cam.make_current()
	else:
		cam.queue_free()
	var body := _body()
	body.global_position = Vector3(-10.0, 0.01, 7.0)
	body.anchor = Vector3(-8.0, 0.0, 7.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var closest := [99.0]
	var tracker := Timer.new()
	tracker.wait_time = 0.05
	tracker.timeout.connect(func() -> void:
		closest[0] = minf(closest[0], Vector2(body.global_position.x + 7.0, body.global_position.z - 7.0).length()))
	add_child(tracker)
	tracker.start()
	var out: Array = [{}, false]
	_run_move(body, {"x": -4.0, "y": 0.0, "z": 7.0, "free": true}, out)
	await _until_done(out)
	tracker.stop()
	tracker.queue_free()
	body.queue_free()
	if player:
		cam.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame
	return closest[0]
