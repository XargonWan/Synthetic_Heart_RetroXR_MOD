## Their way round things (SynthNav) and their body being STOPPED by loose objects instead of shooting them across the room.
## Runs in the real physics world (a scene, headless is fine):
##
##   godot --headless --path RetroXR res://mods/xenu.synth_rift/tests/nav_probe.tscn
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


# ── the search, on a map drawn here ──────────────────────────────────────────

func _pure() -> void:
	# A wall along z = 1.0 from x = -3 to x = 3; the way round is at x > 3.
	var wall := func(p: Vector3) -> bool: return absf(p.z - 1.0) < 0.35 and p.x > -3.0 and p.x < 3.0
	var nav := SynthNav.new()
	nav.blocked_fn = wall
	nav.leash = 8.0
	var r := nav.plan(Vector3(0, 0, 0), Vector3(0, 0, 2.5))
	var path: PackedVector3Array = r["path"]
	_check(bool(r["complete"]) and path.size() >= 2, "a wall between: a way is found with %d turning points" % path.size())
	var crosses := false
	var prev := Vector3.ZERO
	for p in path:
		if (prev.z - 1.0) * (p.z - 1.0) < 0.0 and absf(lerpf(prev.x, p.x, (1.0 - prev.z) / (p.z - prev.z))) < 3.0:
			crosses = true
		prev = p
	_check(not crosses, "and no leg of it goes through the wall")
	_check(absf((path[path.size() - 1] as Vector3).x) < 0.01 and absf((path[path.size() - 1] as Vector3).z - 2.5) < 0.01, "it ends exactly on the goal")
	var longest := 0.0
	for p in path:
		longest = maxf(longest, (p as Vector3).x)
	_check(longest >= 2.99, "it goes round the end of the wall (x reaches %.1f)" % longest)
	_check(nav.queries < 1500, "and asks few questions (%d)" % nav.queries)
	# Control: the straight line IS blocked, so the test above can fail.
	_check(not nav.clear_line(Vector3(0, 0, 0), Vector3(0, 0, 2.5)), "(control) the straight line through the wall is blocked")

	var open := SynthNav.new()
	open.blocked_fn = func(_p: Vector3) -> bool: return false
	var o := open.plan(Vector3(0, 0, 0), Vector3(4.0, 0, 3.0))
	_check(bool(o["complete"]) and (o["path"] as PackedVector3Array).size() == 1, "an empty room: one straight leg")

	# A goal in a sealed ring: no way, and the answer is the nearest they got, with complete=false.
	var ring := func(p: Vector3) -> bool:
		var d := Vector2(p.x - 3.0, p.z).length()
		return d > 0.8 and d < 1.3
	var sealed := SynthNav.new()
	sealed.blocked_fn = ring
	sealed.leash = 8.0
	var s := sealed.plan(Vector3(0, 0, 0), Vector3(3.0, 0, 0))
	_check(not bool(s["complete"]), "a goal inside a sealed ring is reported as unreachable")
	var end: Vector3 = (s["path"] as PackedVector3Array)[(s["path"] as PackedVector3Array).size() - 1] if not (s["path"] as PackedVector3Array).is_empty() else Vector3.ZERO
	_check(Vector2(end.x - 3.0, end.z).length() > 1.0, "and the path stops outside the ring (%.1f m from its middle)" % Vector2(end.x - 3.0, end.z).length())

	# A goal inside a solid thing (a console's middle) is reached when they are next to it.
	var block := SynthNav.new()
	block.blocked_fn = func(p: Vector3) -> bool: return Vector2(p.x - 2.0, p.z).length() < 0.4
	var b := block.plan(Vector3(0, 0, 0), Vector3(2.0, 0, 0))
	var bend: Vector3 = (b["path"] as PackedVector3Array)[(b["path"] as PackedVector3Array).size() - 1]
	_check(bool(b["complete"]) and Vector2(bend.x - 2.0, bend.z).length() < 0.9, "a goal inside a thing: they get next to it (%.2f m)" % Vector2(bend.x - 2.0, bend.z).length())

	var leashed := SynthNav.new()
	leashed.blocked_fn = func(p: Vector3) -> bool: return absf(p.x - 3.0) < 0.35 and absf(p.z) < 20.0
	leashed.leash = 2.0
	leashed.anchor = Vector3.ZERO
	var l := leashed.plan(Vector3(0, 0, 0), Vector3(5.0, 0, 0))
	_check(not bool(l["complete"]), "a way that would leave their leash is not taken")

	var avoiding := SynthNav.new()
	avoiding.blocked_fn = func(_p: Vector3) -> bool: return false
	avoiding.avoid = [Vector3(2.0, 0, 0)]
	var a := avoiding.plan(Vector3(0, 0, 0), Vector3(4.0, 0, 0))
	var through := false
	for p in a["path"]:
		through = through or Vector2((p as Vector3).x - 2.0, (p as Vector3).z).length() < 0.4
	_check(not avoiding.clear_line(Vector3.ZERO, Vector3(4, 0, 0)) and not through, "a place they were stuck at is walked round the second time")


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


func _in_physics() -> void:
	_box(Vector3(30, 1, 30), Vector3(0, -0.5, 0), 1)
	# A wall of the room (layer 1) with a gap at the right, and a seat-sized thing on the pickable layer (3).
	_box(Vector3(4.0, 2.0, 0.2), Vector3(-1.0, 1.0, -2.0), 1)
	_box(Vector3(0.6, 0.5, 0.6), Vector3(2.0, 0.25, 0.0), 4)
	_box(Vector3(1.0, 1.0, 0.2), Vector3(-2.0, 0.5, 2.0), 1 << 4)   # layer 5: nothing of theirs
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space := get_viewport().world_3d.direct_space_state
	var nav := SynthNav.new()
	nav.space = space
	nav.leash = 8.0
	var through_wall := nav.plan(Vector3(0, 0, 0), Vector3(0, 0, -4.0))
	var wp: PackedVector3Array = through_wall["path"]
	_check(bool(through_wall["complete"]) and wp.size() >= 2, "the real wall: a way round it (%d points, %d queries)" % [wp.size(), nav.queries])
	_check(not nav.clear_line(Vector3(0, 0, 0), Vector3(0, 0, -4.0)), "(control) straight through the real wall is blocked")
	_check(nav.clear_line(Vector3(0, 0, 0), Vector3(0, 0, 1.0)), "(control) open floor is clear")
	var seat := SynthNav.new()
	seat.space = space
	_check(not seat.clear_line(Vector3(0.5, 0, 0), Vector3(3.5, 0, 0)), "a thing on the pickable layer blocks them")
	_check(seat.clear_line(Vector3(-2.0, 0, 1.0), Vector3(-2.0, 0, 3.0)), "(control) a thing on a layer that is not theirs is walked through")

	await _body_walks(wp)
	await _body_and_a_box()
	await _body_goes_round()


func _body() -> CharacterBody3D:
	var body: CharacterBody3D = SynthBody.new()
	add_child(body)
	body.anchor = Vector3.ZERO
	return body


## They walk to a goal behind the wall and get there.
func _body_walks(_wp: PackedVector3Array) -> void:
	var body := _body()
	body.global_position = Vector3(0, 0.01, 0)
	await get_tree().physics_frame
	var r: Dictionary = await body.walk_to(Vector3(0, 0, -4.0))
	_check(bool(r.get("ok", false)), "they walk to the far side of the wall and get there (%s)" % str(r.get("detail", "")))
	_check(body.global_position.distance_to(Vector3(0, body.global_position.y, -4.0)) < 0.5, "and stands at it (%.2f m)" % body.global_position.distance_to(Vector3(0, body.global_position.y, -4.0)))
	body.queue_free()
	await get_tree().physics_frame


## A loose box in their way: they go round it and the box stays where it was. CONTROL: the same walk by a plain
## character whose mask is the world alone (what they were) drives straight into the box and shoves it.
func _body_and_a_box() -> void:
	var box := RigidBody3D.new()
	box.collision_layer = 4
	box.collision_mask = 1 | 4
	var s := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(0.4, 0.4, 0.4)
	s.shape = sh
	box.add_child(s)
	box.mass = 2.0
	box.position = Vector3(5.0, 0.21, 5.0)
	add_child(box)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var rest := box.global_position

	var old := CharacterBody3D.new()
	old.collision_layer = 1
	old.collision_mask = 1
	var os := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.22
	cap.height = 1.55
	os.shape = cap
	os.position.y = 0.775
	old.add_child(os)
	add_child(old)
	old.global_position = Vector3(3.0, 0.01, 5.0)
	for i in 240:
		old.velocity = Vector3(1.1, -1.0, 0.0)
		old.move_and_slide()
		await get_tree().physics_frame
	var shoved := box.global_position.distance_to(rest)
	_check(shoved > 0.3, "(control) a body on the world layer alone drives through a loose box and shoves it %.2f m" % shoved)
	old.queue_free()
	box.global_position = rest
	box.linear_velocity = Vector3.ZERO
	box.angular_velocity = Vector3.ZERO
	box.rotation = Vector3.ZERO
	await get_tree().physics_frame
	await get_tree().physics_frame

	var body := _body()
	body.anchor = Vector3(5.0, 0.0, 5.0)
	body.global_position = Vector3(3.0, 0.01, 5.0)
	await get_tree().physics_frame
	var r: Dictionary = await body.walk_to(Vector3(7.0, 0, 5.0))
	var moved := box.global_position.distance_to(rest)
	_check(moved < 0.05, "they walk past a loose box and it has not moved (%.3f m)" % moved)
	_check(bool(r.get("ok", false)), "and they arrive (%s)" % str(r.get("detail", "")))
	body.queue_free()
	box.queue_free()
	await get_tree().physics_frame


## The way round a wall with an end, by the body itself: it ends at the goal and no point of its walk is inside the wall.
func _body_goes_round() -> void:
	var body := _body()
	body.global_position = Vector3(-1.0, 0.01, -0.8)
	await get_tree().physics_frame
	var lowest := [99.0]   # an Array: a lambda copies a float
	var tracker := Timer.new()
	tracker.wait_time = 0.05
	tracker.timeout.connect(func() -> void:
		# the wall is 4 m wide at x -3..1, z -2.1..-1.9: how close to its face does they get?
		var p := body.global_position
		if p.x > -3.0 and p.x < 1.0:
			lowest[0] = minf(lowest[0], absf(p.z + 2.0)))
	add_child(tracker)
	tracker.start()
	var r: Dictionary = await body.walk_to(Vector3(-1.0, 0, -3.5))
	tracker.queue_free()
	_check(bool(r.get("ok", false)), "they get to the other side of a wall by going round its end (%s)" % str(r.get("detail", "")))
	_check(lowest[0] < 98.0 and lowest[0] > 0.15, "and never put themself into it (closest %.2f m to its middle line; 99 = never sampled)" % lowest[0])
	body.queue_free()
