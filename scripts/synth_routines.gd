## SynthRoutines -- what they do ON THEIR OWN once they have been asked: look for something, look around, watch the TV,
## fetch an object.
##
## The model chooses the behaviour and is told the result AFTER, as an event (a turn of its own); in between it is not
## asked anything, the way a Minecraft body goes on mining while it thinks. Each routine is real: they find a thing by
## SEEING it (what a person in front of their would see, `SynthBody.sight`), never by looking it up, so "bring me the
## Game Boy" can end in "I looked everywhere and it is not here". A new routine, a `stop` or a `move` replaces the one
## running.
extends Node

const Protocol := preload("res://mods/xenu.synth_rift/scripts/rift_protocol.gd")
const WorldView := preload("res://mods/xenu.synth_rift/scripts/world_view.gd")
const Use := preload("res://mods/xenu.synth_rift/scripts/synth_use.gd")

signal done(kind: String, ok: bool, summary: String, data: Dictionary)

const SCAN_STEPS := 8                # a full turn, in steps of 45 degrees
const SCAN_STEP_SECONDS := 0.55
const WAYPOINTS := 4                 # places they walk to look from, at most
const SEARCH_SECONDS := 50.0
const WATCH_SECONDS := 10.0
const WATCH_MAX := 30.0
const WATCH_DISTANCE := 1.7
## The grab: a loose object within GRAB_REACH (flat distance from their feet) is taken from where they stand, and flies to their
## hands. It used to need them 0.5 m from the object's middle, which a table made impossible (a VCR in the middle of one: "you
## could not get up to it", for ever). GRAB_STAND is where the walk aims (inside the reach, so stopping a bit short still counts).
const GRAB_REACH := 2.0
const GRAB_STAND := 1.4
## Looking closely at a thing that stays where it is: they walk to INSPECT_DISTANCE and are content with INSPECT_REACH.
const INSPECT_REACH := 2.5
const INSPECT_DISTANCE := 1.2        # how close they stand to a thing too big to lift, to look at it closely
const INSPECT_SECONDS := 3.5         # how long they study it
## Working a machine: they walk to USE_DISTANCE from it and are content with USE_REACH (a machine on a table).
const USE_DISTANCE := 1.2
const USE_REACH := 2.0
## How long they hold a thing out to the player. The model chooses (`seconds`) within HOLD_OUT_MAX; HOLD_OUT_SECONDS is
## what it is when it chose nothing (or something that is not a number).
const HOLD_OUT_SECONDS := 30.0
const HOLD_OUT_MIN := 3.0
const HOLD_OUT_MAX := 60.0
## Where on a surface a thing is set down: this far in from its edge, so that it does not sit on the rim.
const SURFACE_MARGIN := 0.12

## The SynthBody (untyped: it is a script of the mod and this one is loaded first).
@warning_ignore("untyped_declaration")
var body = null
var running := ""
## True while they hold a thing out to the player (the body shows the "give" pose for as long as it is).
var offering := false

var _token := 0
var _idle_clock := 20.0


func is_busy() -> bool:
	return running != ""


## Start `kind` (search, explore, watch, pick_up, hand_over, bring, put_down, operate). Answers at once; `done` says how it went.
func start(kind: String, payload: Dictionary) -> Dictionary:
	if body == null:
		return {"ok": false, "detail": "no_body"}
	if running != "":
		cancel("replaced by %s" % kind)
	_token += 1
	running = kind
	_run(kind, payload, _token)  # a coroutine: it runs on, the caller does not wait
	return {"ok": true, "detail": _started_text(kind, payload), "data": {"routine": kind}}


## Stop what they are doing. NOTHING is told to Synth: it is the model that asked for the replacement (or the stop), and a
## "you stopped" event is a turn of its own -- the model answered the player's last message AGAIN each time, which read as
## the same reply twice (an `explore` replaced by an `explore` gave three turns for one request).
func cancel(why: String = "stopped") -> void:
	if running == "":
		return
	print("[Rift] routine %s cancelled: %s (Synth is not told: no turn)" % [running, why])
	_token += 1
	running = ""
	_set_offering(false)


func _started_text(kind: String, payload: Dictionary) -> String:
	var target := str(payload.get("target", payload.get("name", ""))).strip_edges()
	match kind:
		"search":
			return "looking for %s: you will be told what you find" % target
		"explore":
			return "looking around the room: you will be told what you see"
		"watch":
			return "going to watch %s: you will be told what you saw" % (target if target != "" else "the TV")
		"inspect":
			return "going over to %s to look at it closely: you will be told what you find" % target
		"pick_up":
			return "going to pick up %s" % target
		"hand_over":
			return "going to hand it to the player"
		"put_down":
			return "putting it down%s" % ((" on %s" % target) if target != "" else "")
		"combine":
			return "going to put %s in %s: you will be told how it went" % [str(payload.get("item", payload.get("with", "it"))), target if target != "" else "it"]
		"bring":
			return "going to bring you %s: you will be told how it went" % target
		"operate":
			return "going to do that to %s: you will be told how it went" % (target if target != "" else "it")
	return kind


func _cancelled(mine: int) -> bool:
	return mine != _token or body == null or not is_instance_valid(body)


func _finish(mine: int, kind: String, ok: bool, summary: String, data: Dictionary = {}) -> void:
	if mine != _token:
		return
	running = ""
	_set_offering(false)
	print("[Rift] routine %s done: %s (%s)" % [kind, "ok" if ok else "no", summary])
	done.emit(kind, ok, summary, data)


## The hands are held out (or not): the body is told, so that it shows the pose.
func _set_offering(value: bool) -> void:
	if offering == value:
		return
	offering = value
	if body != null and is_instance_valid(body) and body.has_method("refresh_pose"):
		body.call("refresh_pose")


## Wait, but give up the moment this routine is replaced. False then.
func _wait(seconds: float, mine: int) -> bool:
	var left := seconds
	while left > 0.0:
		if _cancelled(mine):
			return false
		await get_tree().create_timer(minf(0.1, left)).timeout
		left -= 0.1
	return not _cancelled(mine)


func _run(kind: String, payload: Dictionary, mine: int) -> void:
	var target := str(payload.get("target", payload.get("name", ""))).strip_edges()
	match kind:
		"search":
			await _search(target, mine)
		"explore":
			await _explore(mine)
		"watch":
			await _watch(target if target != "" else "TV", float(payload.get("seconds", WATCH_SECONDS)), mine)
		"inspect":
			await _inspect(target, mine)
		"pick_up":
			await _pick_up(target, mine, true)
		"hand_over":
			await _hand_over(mine, true, _hold_out_seconds(payload))
		"bring":
			await _bring(target, mine, _hold_out_seconds(payload))
		"put_down":
			await _put_down(target, mine)
		"operate":
			await _operate(payload, mine)
		"combine":
			await _combine(payload, mine)
	# A routine that ended without saying how is a routine the model waits on for ever: say so.
	if mine == _token and running == kind:
		print("[Rift] routine %s ended with no result: reporting it as a failure" % kind)
		_finish(mine, kind, false, "The %s ended without a result: it did not work out." % kind.replace("_", " "))


# ── seeing ───────────────────────────────────────────────────────────────────

## What they see right now, or [].
func _sight() -> Array:
	return body.sight.call() if body.sight.is_valid() else []


## The best of what they see that `query` names (exact over partial, then nearest), or {}.
func _find_in(seen: Array, query: String) -> Dictionary:
	var best: Dictionary = {}
	var best_score := 0
	var best_d := INF
	for e: Dictionary in seen:
		if str(e.get("type", "")) == "player":
			continue
		var score := WorldView.matches(e, query)
		if score == 0:
			continue
		var d := float(e.get("distance", INF))
		if score > best_score or (score == best_score and d < best_d):
			best = e
			best_score = score
			best_d = d
	return best


## Turn on the spot to `yaw` (radians), over a short time, so it is a turn and not a jump.
func _turn_to(yaw: float, mine: int, seconds: float = 0.45) -> bool:
	# A quarter turn or more is the skin's turn clip, as long as it takes; what is left (or a small turn) is the ease below.
	while body.begin_turn(yaw):
		while body.is_turning():
			if _cancelled(mine):
				return false
			await get_tree().process_frame
	var t := 0.0
	var from: float = body.rotation.y
	while t < seconds:
		if _cancelled(mine):
			return false
		await get_tree().process_frame
		t += get_process_delta_time()
		body.rotation.y = lerp_angle(from, yaw, clampf(t / seconds, 0.0, 1.0))
	body.rotation.y = yaw
	return true


## Turn all the way round, looking. Returns what `query` names if it comes into view (the body stops facing it), else {}.
## With `collect` it also notes the names of everything that comes into view.
func _scan(query: String, collect: Dictionary, mine: int) -> Dictionary:
	var yaw: float = body.rotation.y
	for step in SCAN_STEPS:
		var seen := _sight()
		for e: Dictionary in seen:
			if str(e.get("type", "")) != "player":
				collect[str(e.get("name", ""))] = e
		if query != "":
			var hit := _find_in(seen, query)
			if not hit.is_empty():
				return hit
		yaw -= TAU / SCAN_STEPS
		if not await _turn_to(yaw, mine) or not await _wait(SCAN_STEP_SECONDS, mine):
			return {}
	return {}


## A place to look from they have not looked from: far from where they have been, inside their leash.
func _next_waypoint(visited: Array) -> Variant:
	var best: Variant = null
	var best_gap := 0.0
	for ring: float in [2.2, 4.0]:
		for k in 10:
			var a := TAU * k / 10.0
			var p: Vector3 = body.anchor + Vector3(cos(a) * ring, 0.0, sin(a) * ring)
			p.y = body.global_position.y
			var gap := INF
			for v: Vector3 in visited:
				gap = minf(gap, p.distance_to(v))
			if gap > best_gap:
				best_gap = gap
				best = p
	return best if best_gap > 1.6 else null


func _walk(point: Vector3, mine: int) -> bool:
	var result: Dictionary = await body.walk_to(point)
	return not _cancelled(mine) and bool(result.get("ok", false))


## How far `p` is from their feet, on the floor plane.
func _flat_gap(p: Vector3) -> float:
	return Vector2(p.x - body.global_position.x, p.z - body.global_position.z).length()


## Get within `reach` of the point `p`: no walk at all when they already are. Otherwise walk to `stand` from it; a walk
## that ends SHORT (a table in the way: the path stops at the nearest cell it could reach) is still enough when they ended
## within `reach`. Returns "" when they are within reach, "cancelled" when the routine was replaced meanwhile, else WHY NOT in
## words for the model (how near they got, and what is in the way), so it does not ask for the same thing again.
func _approach(p: Vector3, stand: float, reach: float, mine: int, target: Node3D = null) -> String:
	if _flat_gap(p) <= reach:
		return ""
	var back := Vector3(body.global_position.x - p.x, 0.0, body.global_position.z - p.z)
	var aim := p + (back.normalized() * stand if back.length() > 0.01 else Vector3.ZERO)
	await _walk(aim, mine)
	if _cancelled(mine):
		return "cancelled"
	var gap := _flat_gap(p)
	if gap <= reach:
		return ""
	var blocker := _blocker_near(p, target)
	return "the closest you got was %.1f m%s" % [gap, (", %s is in the way" % blocker) if blocker != "" else ", there is no way to get closer"]


## The name of the biggest thing standing next to `p` that is not the target: what a thing is resting on or behind ("the
## table"). "" when nothing they can see is close to it.
func _blocker_near(p: Vector3, target: Node3D) -> String:
	var best := ""
	var best_d := 1.0
	for e: Dictionary in _sight():
		if str(e.get("type", "")) == "player" or (target != null and e.get("node") == target):
			continue
		if not (str(e.get("type", "")) in ["table", "seat", "TV", "speaker"]):
			continue
		var q: Vector3 = e["position"]
		var d := Vector2(q.x - p.x, q.z - p.z).length()
		if d < best_d:
			best_d = d
			best = "the %s" % str(e.get("name", e.get("type", "furniture")))
	return best


# ── the routines ─────────────────────────────────────────────────────────────

## Find what `query` names: in front of their already, else by turning round and walking to somewhere else and again.
## Returns the entity they SAW, or {} (the routine has then been finished as a failure when `report`).
func _acquire(query: String, mine: int, report: bool, kind: String) -> Dictionary:
	var collect: Dictionary = {}
	var hit := _find_in(_sight(), query)
	if not hit.is_empty():
		return hit
	var visited: Array = [body.global_position]
	var started := Time.get_ticks_msec()
	var spots := 0
	while true:
		hit = await _scan(query, collect, mine)
		if _cancelled(mine):
			return {}
		if not hit.is_empty():
			return hit
		if spots >= WAYPOINTS or (Time.get_ticks_msec() - started) / 1000.0 > SEARCH_SECONDS:
			break
		var next: Variant = _next_waypoint(visited)
		if next == null:
			break
		spots += 1
		if not await _walk(next as Vector3, mine):
			if _cancelled(mine):
				return {}
		visited.append(body.global_position)
	if report:
		var names := ", ".join(collect.keys()) if not collect.is_empty() else "nothing else"
		_finish(mine, kind, false, "You looked for %s: you turned all the way round from %d places in the room and did not see it. What you did see: %s. It is not here, or it is hidden (in a drawer, behind something, in someone's hands)." % [
			query, spots + 1, names], {"query": query, "found": false, "places_looked": spots + 1, "saw": collect.keys()})
	return {}


func _search(query: String, mine: int) -> void:
	if query == "":
		_finish(mine, "search", false, "You were not told what to look for.")
		return
	var hit := await _acquire(query, mine, true, "search")
	if hit.is_empty():
		return
	await _face(hit, mine)
	_finish(mine, "search", true, "You found %s: %s, %.1f m away." % [str(hit["name"]), str(hit.get("side", "ahead")), float(hit.get("distance", 0.0))],
		{"query": query, "found": true, "name": hit["name"], "distance": hit.get("distance", 0.0), "position": Protocol.vec(hit["position"])})


func _face(hit: Dictionary, mine: int) -> void:
	var p: Vector3 = hit["position"]
	var flat := Vector3(p.x - body.global_position.x, 0.0, p.z - body.global_position.z)
	if flat.length() > 0.01:
		await _turn_to(atan2(-flat.x, -flat.z), mine, 0.35)
	body.study_point(p, 3.0)


func _explore(mine: int) -> void:
	var collect: Dictionary = {}
	var visited: Array = [body.global_position]
	var spots := 0
	while spots <= 2:
		await _scan("", collect, mine)
		if _cancelled(mine):
			return
		var next: Variant = _next_waypoint(visited)
		if next == null or spots >= 2:
			break
		spots += 1
		await _walk(next as Vector3, mine)
		visited.append(body.global_position)
	var names: Array = collect.keys()
	_finish(mine, "explore", true, "You looked around the room from %d places. You saw: %s." % [spots + 1, ", ".join(names) if not names.is_empty() else "nothing but the room"],
		{"saw": names})


## Turn on the spot for about `seconds`, naming what comes into view. Not a routine the model asked for: the core's walk
## (plugins/rift_vessel/exploration.py) asks it at every stop, and uses the names. They are marked busy meanwhile, so the
## idle glances keep out and a `stop` or a new walk ends it. {ok, data: {saw: [{name, area}]}}.
func look_around(seconds: float) -> Dictionary:
	if body == null:
		return {"ok": false, "detail": "no_body"}
	if running != "" and running != "look_around":
		cancel("replaced by looking around")
	_token += 1
	var mine := _token
	running = "look_around"
	var collect: Dictionary = {}
	seconds = clampf(seconds, 1.0, 10.0)
	var steps := clampi(int(seconds / SCAN_STEP_SECONDS), 2, SCAN_STEPS)
	var per := seconds / float(steps)
	var yaw: float = body.rotation.y
	var ok := true
	for i in steps:
		for e: Dictionary in _sight():
			if str(e.get("type", "")) != "player":
				collect[str(e.get("name", ""))] = true
		yaw -= TAU / float(steps)
		if not await _turn_to(yaw, mine, minf(per * 0.6, 0.45)) or not await _wait(per * 0.4, mine):
			ok = false
			break
	if mine == _token:
		running = ""
	var saw: Array = []
	for n: String in collect.keys():
		if not n.is_empty():
			saw.append({"name": n, "area": str(body.room_name)})
	return {"ok": ok, "detail": "looked around" if ok else "stopped", "data": {"saw": saw}}


func _watch(query: String, seconds: float, mine: int) -> void:
	seconds = clampf(seconds, 3.0, WATCH_MAX)
	var hit := await _acquire(query, mine, true, "watch")
	if hit.is_empty():
		return
	# Stand a little way off on the side they came from, facing it.
	var p: Vector3 = hit["position"]
	var back := Vector3(body.global_position.x - p.x, 0.0, body.global_position.z - p.z)
	# A thing in their hands (the Game Boy they are looking at the screen of) or already within WATCH_DISTANCE is not walked
	# away from: they used to back off to 1.7 m from what they held.
	if back.length() > 0.01 and back.length() > WATCH_DISTANCE + 0.3:
		if not await _walk(p + back.normalized() * WATCH_DISTANCE, mine):
			if _cancelled(mine):
				return
	await _face(hit, mine)
	if not await _wait(seconds, mine):
		return
	var live := _find_in(_sight(), query)
	var text := "You watched %s for %.0f seconds." % [str(hit["name"]), seconds]
	var data := {"name": hit["name"], "seconds": seconds}
	if not live.is_empty() and live.has("powered"):
		text += " It is switched %s." % ("on" if bool(live["powered"]) else "off")
		data["powered"] = bool(live["powered"])
	# What their eyes took (a picture, when pictures are on): the picture is how they can say what is on it.
	var shot: Dictionary = await body.take_picture(p)
	if bool(shot.get("ok", false)):
		data["image_jpeg_b64"] = shot["jpeg_b64"]
		text += " A picture of what they were looking at is attached."
	_finish(mine, "watch", true, text, data)


## Look at a thing closely, the way a person would: go over to it, take it in their hands if it can be lifted (a cartridge, a
## console, a tape) and study it, or stand in front of it if it cannot (a TV, a wardrobe, a statue). They are told what it is
## afterwards. What they picked up STAYS in their hands (the room shows them holding it; `put_down` / `hand_over` are theirs to
## ask for). Going on to a second thing: if that one can be lifted too, the first is set down where they stand to take it; if
## it cannot, they keep the first in their hands while they look at it.
## It used to turn their head and read out a distance, which a model asked for over and over without anything ever happening.
func _inspect(query: String, mine: int) -> void:
	if query == "":
		_finish(mine, "inspect", false, "You were not told what to look at.")
		return
	var hit: Dictionary = body.call("_resolve", {"target": query})
	if hit.is_empty():
		_finish(mine, "inspect", false, "There is nothing called '%s' that you can see. If you want to find it, search for it." % query)
		return
	var label := str(hit.get("label", hit.get("name", query)))
	var p: Vector3 = hit["position"]
	if str(hit.get("type", "")) == "player":
		await _face(hit, mine)
		_finish(mine, "inspect", true, "That is the player, %.1f m away." % Vector2(p.x - body.global_position.x, p.z - body.global_position.z).length())
		return
	var node: Node3D = hit.get("node") as Node3D
	var refusal := "" if (node != null and is_instance_valid(node)) else "it is gone"
	if refusal == "":
		refusal = str(body.lift_refusal(node))
	var already: bool = body.holding() != "" and body.holding() == str(hit.get("name", ""))
	var liftable := refusal == "" and not already
	if liftable and body.holding() != "":
		var set_down: String = body.holding()
		body.put_down()
		print("[Rift] inspect: set %s down to take %s" % [set_down, label])
	# Go over to it: within grabbing reach to take it, or a little way off when it stays where it is. Already within reach
	# (a VCR on a table they cannot walk up to) = no walk at all.
	var why := await _approach(p, GRAB_STAND if liftable else INSPECT_DISTANCE, GRAB_REACH if liftable else INSPECT_REACH, mine, node)
	if why == "cancelled":
		return
	if why != "":
		_finish(mine, "inspect", false, "You could not get within reach of %s: %s." % [label, why])
		return
	await _face(hit, mine)
	if _cancelled(mine):
		return
	var taken := false
	if liftable:
		taken = body.hold(node, str(hit.get("name", label)))
	if not await _wait(INSPECT_SECONDS, mine):
		return
	var bits: PackedStringArray = [str(hit.get("type", "something"))]
	if str(hit.get("systemid", "")) != "":
		bits.append("a %s machine" % str(hit["systemid"]))
	if hit.has("powered"):
		bits.append("switched on" if bool(hit["powered"]) else "switched off")
	if str(hit.get("title", "")) != "":
		bits.append("%s is on it" % str(hit["title"]))
	var text := "You went over to %s and looked at it closely: %s." % [label, ", ".join(bits)]
	if taken or already:
		text += " You are holding it now (put it down or hand it over whenever you like)."
	elif refusal != "":
		text += " You left it where it is: %s." % refusal
	_finish(mine, "inspect", true, text, {"name": hit.get("name", label), "label": label, "type": hit.get("type", ""),
		"powered": hit.get("powered", null), "title": hit.get("title", ""), "holding": taken or already, "refusal": refusal})


## Walk up to a thing and take it. A FAILURE is always reported as the routine `kind`'s result: `bring` used to call this
## with report=false, so a thing that could not be lifted (or found, or reached) ended it with NO result at all: the model
## heard nothing, the routine stayed "running" for ever and the model asked for it again, three times in one real session.
## `report_success`: a pick_up ends with the result; a bring goes on to hand the thing over.
func _pick_up(query: String, mine: int, report: bool, kind: String = "pick_up", report_success: bool = true) -> bool:
	if body.holding() != "":
		if report:
			_finish(mine, kind, false, "Your hands are full: you are holding %s." % body.holding())
		return false
	var hit := await _acquire(query, mine, report, kind)
	if hit.is_empty():
		return false
	var node: Node3D = hit.get("node") as Node3D
	var why: String = "it is gone" if (node == null or not is_instance_valid(node)) else str(body.lift_refusal(node))
	if why != "":
		if report:
			_finish(mine, kind, false, "You cannot pick up %s: %s." % [str(hit["name"]), why])
		return false
	if node.has_method("is_picked_up") and bool(node.call("is_picked_up")):
		if report:
			_finish(mine, kind, false, "The player is holding %s." % str(hit["name"]))
		return false
	var p: Vector3 = node.global_position
	var far := await _approach(p, GRAB_STAND, GRAB_REACH, mine, node)
	if far == "cancelled":
		return false
	if far != "":
		if report:
			_finish(mine, kind, false, "You could not get within reach of %s: %s." % [str(hit["name"]), far])
		return false
	await _face(hit, mine)
	if _cancelled(mine):
		return false
	# A cartridge in a console, a tape in a VCR: taken out first, or the machine goes on believing it holds it.
	var host := Use.host_of(node, get_tree().get_nodes_in_group("spawned"))
	if host != null:
		var out := Use.eject(host)
		if not bool(out.get("ok", false)):
			if report:
				_finish(mine, kind, false, "%s is inside %s and you could not take it out: %s." % [str(hit["name"]), str(host.name), str(out.get("detail", ""))])
			return false
		if not await _wait(1.2, mine):
			return false
	if not body.hold(node, str(hit["name"])):
		if report:
			_finish(mine, kind, false, "You could not take %s." % str(hit["name"]))
		return false
	if report and report_success:
		_finish(mine, "pick_up", true, "You are holding %s." % str(hit["name"]), {"holding": hit["name"]})
	return true


## How long to hold a thing out: what the model chose, within limits, else the fallback.
func _hold_out_seconds(payload: Dictionary) -> float:
	var raw: Variant = payload.get("seconds", null)
	if (raw is float or raw is int) and float(raw) > 0.0:
		return clampf(float(raw), HOLD_OUT_MIN, HOLD_OUT_MAX)
	if raw is String and str(raw).is_valid_float() and float(str(raw)) > 0.0:
		return clampf(float(str(raw)), HOLD_OUT_MIN, HOLD_OUT_MAX)
	return HOLD_OUT_SECONDS


## Take what they hold to the player and hold it out, hands forward, until they take it or the time is up. Not taken is a
## FACT they are told, not a reason to put it down: what to do with it (keep it, set it on the table, try again) is theirs to
## choose, as a turn of their own.
func _hand_over(mine: int, report: bool, seconds: float = HOLD_OUT_SECONDS) -> bool:
	var held: String = body.holding()
	if held == "":
		if report:
			_finish(mine, "hand_over", false, "You are not holding anything.")
		return false
	var cam: Camera3D = body.get_viewport().get_camera_3d()
	if cam == null:
		if report:
			_finish(mine, "hand_over", false, "You cannot find the player.")
		return false
	var there := cam.global_position
	var away := Vector3(body.global_position.x - there.x, 0.0, body.global_position.z - there.z)
	if away.length() > 1.2:
		if not await _walk(there + away.normalized() * 0.9, mine):
			if _cancelled(mine):
				return false
	var player := {"position": there}
	await _face(player, mine)
	_set_offering(true)
	body.attend_player(seconds)
	var took := false
	var waited := 0.0
	while waited < seconds:
		if not await _wait(0.2, mine):
			return false
		waited += 0.2
		if not body.is_holding_still():
			took = true
			break
	var kind := "hand_over" if report else "bring"
	if took:
		_finish(mine, kind, true, "The player took %s from your hands." % held, {"handed": held, "taken": true})
	else:
		_finish(mine, kind, true, "You held %s out to the player for %.0f seconds and they did not take it. You are still holding it." % [held, seconds],
			{"offered": held, "taken": false, "holding": held, "seconds": seconds})
	return true


func _bring(query: String, mine: int, seconds: float = HOLD_OUT_SECONDS) -> void:
	var held: String = body.holding()
	# Already carrying what was asked for: hand it over. Carrying something ELSE: say so, do not give that away instead.
	if held != "" and WorldView.matches({"name": held, "id": held, "type": ""}, query) == 0:
		_finish(mine, "bring", false, "Your hands are full: you are holding %s, so you cannot fetch %s. Put it down or hand it over first." % [held, query])
		return
	if held == "":
		if not await _pick_up(query, mine, true, "bring", false):
			return
	await _hand_over(mine, false, seconds)


## Let go of what they hold: where they stand (on what is under their hands) or, with a `target`, on that thing: they walk up
## to it, and set it on its top. The answer says WHERE it ended up.
func _put_down(query: String, mine: int) -> void:
	var held: String = body.holding()
	if held == "":
		_finish(mine, "put_down", false, "You are not holding anything.")
		return
	if query == "":
		var here: Dictionary = body.put_down()
		_finish(mine, "put_down", true, "You put %s down %s." % [held, str(here.get("where", "in front of you"))], {"put_down": held, "where": here.get("where", "")})
		return
	var hit := _operate_target(query, body.held_node())
	if hit.is_empty() or (hit.get("node") != null and hit.get("node") == body.held_node()):
		hit = await _acquire(query, mine, false, "put_down")
	if hit.is_empty():
		if not _cancelled(mine):
			_finish(mine, "put_down", false, "There is nothing called '%s' that you can see. You are still holding %s. If you want to find it, search for it." % [query, held])
		return
	var node: Node3D = hit.get("node") as Node3D
	var label := str(hit.get("label", hit.get("name", query)))
	if node == null or not is_instance_valid(node):
		_finish(mine, "put_down", false, "%s is gone. You are still holding %s." % [label, held])
		return
	if node == body.held_node():
		_finish(mine, "put_down", false, "%s is what you are holding. You are still holding it." % label)
		return
	var top: Dictionary = body.surface_top(node, SURFACE_MARGIN)
	if not bool(top.get("ok", false)):
		_finish(mine, "put_down", false, "There is no flat top on %s to set %s on. You are still holding it." % [label, held])
		return
	if not await _reach_for_use(hit, node, label, body.held_node(), mine, "put_down"):
		return
	# Each spot is only where to aim: it counts when there is a flat surface under it (the near side first, then the middle).
	for spot: Vector3 in top["points"]:
		var done_at: Dictionary = body.put_down(spot)
		if bool(done_at.get("ok", false)):
			_finish(mine, "put_down", true, "You put %s down %s." % [held, str(done_at.get("where", "on " + label))], {"put_down": held, "where": done_at.get("where", ""), "on": label})
			return
	_finish(mine, "put_down", false, "You could not find a flat place on %s to set %s. You are still holding it." % [label, held])


# ── working a machine ────────────────────────────────────────────────────────

## `operate {interaction, target, with}`: do what a person does to a machine, with their hands: switch a TV or a console on or
## off, its volume, a VCR's rewind or eject, a cartridge or tape put into a machine. They walk up to it first, face it, do it
## and are told what came of it (read back from the thing, not assumed). `insert` also takes what goes in: the thing in their
## hands, or (`with`) a loose one in the room, which they fetch first. Asked to play a game, they are told why not and what
## they can do instead, without walking anywhere (SynthUse.NO_GAMES).
func _operate(payload: Dictionary, mine: int, kind: String = "operate") -> void:
	var interaction := str(payload.get("interaction", payload.get("action", ""))).strip_edges()
	var query := str(payload.get("target", payload.get("name", ""))).strip_edges()
	var with_name := str(payload.get("with", payload.get("into", payload.get("media", "")))).strip_edges()
	var intent := Use.parse(interaction)
	if intent == "":
		_finish(mine, kind, false, "You were asked to '%s' and you do not know how to do that to a machine. What you can do: %s." % [
			interaction, Use.VOCABULARY])
		return
	if intent == Use.GAME:
		_finish(mine, kind, false, Use.NO_GAMES, {"game": true})
		return
	var held: Node3D = body.held_node()
	# "Turn it on" with a thing in their hands and no name: it is the thing they hold.
	if query == "" and held != null and intent != Use.INSERT:
		query = body.holding()
	if query == "" and intent != Use.INSERT:
		_finish(mine, kind, false, "You were not told what to do it to.")
		return
	if intent == Use.INSERT:
		await _operate_insert(query, with_name, held, mine, kind)
		return
	var hit := _operate_target(query, held)
	if hit.is_empty():
		_finish(mine, kind, false, "There is nothing called '%s' that you can see. If you want to find it, search for it." % query)
		return
	var node: Node3D = hit.get("node") as Node3D
	var label := str(hit.get("label", hit.get("name", query)))
	if node == null or not is_instance_valid(node):
		_finish(mine, kind, false, "%s is gone." % label)
		return
	# A bare "play" on a machine that runs games is asking to play one.
	if intent == Use.PLAY and Use.is_game_machine(node):
		_finish(mine, kind, false, Use.NO_GAMES, {"game": true})
		return
	if not Use.can(node, intent):
		_finish(mine, kind, false, "You cannot do that to %s. With it you can: %s." % [label, Use.options_of(node)])
		return
	if not await _reach_for_use(hit, node, label, held, mine, kind):
		return
	var result := Use.apply(node, intent, Use.presses(interaction))
	# A console boots and a TV takes a moment: read what the room shows after, not what was just pressed.
	if bool(result.get("ok", false)):
		if not await _wait(1.0, mine):
			return
	var text := str(result.get("detail", ""))
	var data: Dictionary = (result.get("data", {}) as Dictionary).duplicate()
	var powered: Variant = Use.power_state(node)
	if powered != null:
		data["powered"] = bool(powered)
		text += " %s is %s." % [label, "switched on" if bool(powered) else "switched off"]
		if intent == Use.POWER_ON and not bool(powered) and bool(result.get("ok", false)):
			text += " It did not come on: it may have no power (is its cord plugged in?)."
	data["name"] = label
	_finish(mine, kind, bool(result.get("ok", false)), "%s%s" % [("" if bool(result.get("ok", false)) else "You could not: "), text], data)


## `combine {target, item?, how?}`: put one thing into or onto another. Here that is what a person does with a cartridge or a
## tape and a machine with a slot (the same hands as `operate`'s insert): `item` is what goes in (default: what they hold),
## `target` what it goes into, `how` free words for it. Anything else cannot be combined here, and they are told what can.
func _combine(payload: Dictionary, mine: int) -> void:
	var how := str(payload.get("how", "")).strip_edges()
	var intent := Use.parse(how) if how != "" else Use.INSERT
	if intent != Use.INSERT:
		_finish(mine, "combine", false, "You cannot combine things that way here. What you can combine: a cartridge or a tape put into a machine that has a slot for it.")
		return
	var translated := {
		"interaction": "insert",
		"target": str(payload.get("target", payload.get("name", ""))),
		"with": str(payload.get("item", payload.get("with", ""))),
	}
	await _operate(translated, mine, "combine")


## What `query` names for `operate`: the thing in their hands when it is that (it may not be among what they SEE), else
## what they have seen.
func _operate_target(query: String, held: Node3D) -> Dictionary:
	if held != null and query != "":
		var as_held := {"name": body.holding(), "id": body.holding(), "type": ""}
		if WorldView.matches(as_held, query) > 0:
			return {"name": body.holding(), "label": body.holding(), "node": held, "position": held.global_position}
	return body.call("_resolve", {"target": query})


## Be within reach of a thing to work it, facing it. Their own hands' load is no distance at all.
func _reach_for_use(hit: Dictionary, node: Node3D, label: String, held: Node3D, mine: int, kind: String = "operate") -> bool:
	if node == held:
		return true
	var p: Vector3 = node.global_position
	var back := Vector3(body.global_position.x - p.x, 0.0, body.global_position.z - p.z)
	# Already within reach (a machine on a table they cannot walk up to) = no walk at all.
	if back.length() > USE_REACH:
		if not await _walk(p + back.normalized() * USE_DISTANCE, mine):
			if _cancelled(mine):
				return false
			var gap := Vector2(p.x - body.global_position.x, p.z - body.global_position.z).length()
			if gap > USE_REACH:
				_finish(mine, kind, false, "You could not get within reach of %s: the closest you got was %.1f m." % [label, gap])
				return false
	await _face(hit, mine)
	return not _cancelled(mine)


## Put a cartridge or tape into a machine. `query` is the machine; the thing is `with_name`, else what they hold. A loose one is
## fetched first. Either may be given as the target (it is the one that has the slot that is the machine).
func _operate_insert(query: String, with_name: String, held: Node3D, mine: int, kind: String = "operate") -> void:
	var host_hit: Dictionary = {}
	var media_hit: Dictionary = {}
	if query != "":
		host_hit = _operate_target(query, held)
		if host_hit.is_empty():
			_finish(mine, kind, false, "There is nothing called '%s' that you can see. If you want to find it, search for it." % query)
			return
	if with_name != "":
		media_hit = _operate_target(with_name, held)
		if media_hit.is_empty():
			_finish(mine, kind, false, "There is nothing called '%s' that you can see. If you want to find it, search for it." % with_name)
			return
	elif held != null:
		media_hit = {"name": body.holding(), "label": body.holding(), "node": held, "position": held.global_position}
	# Whichever of the two has the slot is the machine: "insert Mario into the Game Boy" may come either way round.
	if not host_hit.is_empty() and not media_hit.is_empty() and not Use.can(host_hit.get("node") as Object, Use.INSERT) \
			and Use.can(media_hit.get("node") as Object, Use.INSERT):
		var swap := host_hit
		host_hit = media_hit
		media_hit = swap
	if host_hit.is_empty():
		_finish(mine, kind, false, "You were not told what to put it in.")
		return
	if media_hit.is_empty():
		_finish(mine, kind, false, "You have nothing to put in %s: pick up the cartridge or tape first, or say which one (with)." % str(host_hit.get("label", "it")))
		return
	var host: Node3D = host_hit.get("node") as Node3D
	var media: Node3D = media_hit.get("node") as Node3D
	var host_label := str(host_hit.get("label", host_hit.get("name", "it")))
	var media_label := str(media_hit.get("label", media_hit.get("name", "it")))
	var why := Use.fit_refusal(host, media, host_label, media_label)
	if why != "":
		_finish(mine, kind, false, "You cannot put %s in %s: %s." % [media_label, host_label, why])
		return
	# A loose one is taken first (their hands must be free for it; what they hold is the machine's, then, not the thing's).
	if media != held:
		if held != null and held != host:
			_finish(mine, kind, false, "Your hands are full: you are holding %s. Put it down first." % body.holding())
			return
		if held != null and held == host:
			_finish(mine, kind, false, "Your hands are full with %s, the machine itself: put it down first, then put %s in it." % [host_label, media_label])
			return
		if not await _pick_up(str(media_hit.get("name", media_label)), mine, true, kind, false):
			return
		held = body.held_node()
		if held != media:
			_finish(mine, kind, false, "You could not pick up %s." % media_label)
			return
	if host != held and not await _reach_for_use(host_hit, host, host_label, held, mine, kind):
		return
	body.release_held()
	var result := Use.insert(host, media)
	if not bool(result.get("ok", false)):
		_finish(mine, kind, false, "You could not put %s in %s: %s." % [media_label, host_label, str(result.get("detail", ""))])
		return
	if not await _wait(0.6, mine):
		return
	var powered: Variant = Use.power_state(host)
	var text := "You put %s in %s." % [media_label, host_label]
	if powered != null:
		text += " It is switched %s." % ("on" if bool(powered) else "off: switch it on (operate turn on) to start it")
	_finish(mine, kind, true, text, {"inserted": media_label, "into": host_label, "powered": powered})


# ── life while nobody asks anything ──────────────────────────────────────────

## Now and then their head goes to something that is really there: a machine that is on, the TV, the player. Never told
## to the model (it is not news), never a thing that is not in front of them.
func idle_curiosity(delta: float, speaking: bool) -> void:
	if running != "" or speaking or body == null or body.is_walking():
		_idle_clock = maxf(_idle_clock, 8.0)
		return
	_idle_clock -= delta
	if _idle_clock > 0.0:
		return
	_idle_clock = randf_range(18.0, 40.0)
	var seen := _sight()
	var interesting: Array = []
	for e: Dictionary in seen:
		if str(e.get("type", "")) == "player":
			continue
		if bool(e.get("powered", false)):
			interesting.append(e)
			interesting.append(e)  # what is on is looked at more often
		else:
			interesting.append(e)
	if interesting.is_empty():
		return
	var pick: Dictionary = interesting[randi() % interesting.size()]
	body.study_point(pick["position"], randf_range(2.5, 5.0))
	print("[Rift] idle: they look at %s" % str(pick.get("name", "?")))
