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

signal done(kind: String, ok: bool, summary: String, data: Dictionary)

const SCAN_STEPS := 8                # a full turn, in steps of 45 degrees
const SCAN_STEP_SECONDS := 0.55
const WAYPOINTS := 4                 # places they walk to look from, at most
const SEARCH_SECONDS := 50.0
const WATCH_SECONDS := 10.0
const WATCH_MAX := 30.0
const WATCH_DISTANCE := 1.7
const REACH := 0.75                  # how close they stand to take something
const HOLD_OUT_SECONDS := 8.0        # how long they hold a thing out to the player

## The SynthBody (untyped: it is a script of the mod and this one is loaded first).
@warning_ignore("untyped_declaration")
var body = null
var running := ""

var _token := 0
var _idle_clock := 20.0


func is_busy() -> bool:
	return running != ""


## Start `kind` (search, explore, watch, pick_up, hand_over, bring, put_down). Answers at once; `done` says how it went.
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


func _started_text(kind: String, payload: Dictionary) -> String:
	var target := str(payload.get("target", payload.get("name", ""))).strip_edges()
	match kind:
		"search":
			return "looking for %s: you will be told what you find" % target
		"explore":
			return "looking around the room: you will be told what you see"
		"watch":
			return "going to watch %s: you will be told what you saw" % (target if target != "" else "the TV")
		"pick_up":
			return "going to pick up %s" % target
		"hand_over":
			return "going to hand it to the player"
		"bring":
			return "going to bring you %s: you will be told how it went" % target
	return kind


func _cancelled(mine: int) -> bool:
	return mine != _token or body == null or not is_instance_valid(body)


func _finish(mine: int, kind: String, ok: bool, summary: String, data: Dictionary = {}) -> void:
	if mine != _token:
		return
	running = ""
	print("[Rift] routine %s done: %s (%s)" % [kind, "ok" if ok else "no", summary])
	done.emit(kind, ok, summary, data)


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
		"pick_up":
			await _pick_up(target, mine, true)
		"hand_over":
			await _hand_over(mine, true)
		"bring":
			await _bring(target, mine)
		"put_down":
			_put_down(mine)
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


func _watch(query: String, seconds: float, mine: int) -> void:
	seconds = clampf(seconds, 3.0, WATCH_MAX)
	var hit := await _acquire(query, mine, true, "watch")
	if hit.is_empty():
		return
	# Stand a little way off on the side they came from, facing it.
	var p: Vector3 = hit["position"]
	var back := Vector3(body.global_position.x - p.x, 0.0, body.global_position.z - p.z)
	if back.length() > 0.01:
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
	var back := Vector3(body.global_position.x - p.x, 0.0, body.global_position.z - p.z)
	if back.length() > REACH + 0.2:
		if not await _walk(p + back.normalized() * REACH, mine):
			if _cancelled(mine):
				return false
	await _face(hit, mine)
	if _cancelled(mine):
		return false
	if not body.hold(node, str(hit["name"])):
		if report:
			_finish(mine, kind, false, "You could not take %s." % str(hit["name"]))
		return false
	if report and report_success:
		_finish(mine, "pick_up", true, "You are holding %s." % str(hit["name"]), {"holding": hit["name"]})
	return true


## Take what they hold to the player and hold it out until they take it, or put it down in front of them.
func _hand_over(mine: int, report: bool) -> bool:
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
	body.attend_player(HOLD_OUT_SECONDS)
	var took := false
	var waited := 0.0
	while waited < HOLD_OUT_SECONDS:
		if not await _wait(0.2, mine):
			return false
		waited += 0.2
		if not body.is_holding_still():
			took = true
			break
	if took:
		_finish(mine, "hand_over" if report else "bring", true, "The player took %s from your hands." % held, {"handed": held})
	else:
		body.put_down()
		_finish(mine, "hand_over" if report else "bring", true, "The player did not take %s, so you put it down in front of them." % held, {"put_down": held})
	return true


func _bring(query: String, mine: int) -> void:
	var held: String = body.holding()
	# Already carrying what was asked for: hand it over. Carrying something ELSE: say so, do not give that away instead.
	if held != "" and WorldView.matches({"name": held, "id": held, "type": ""}, query) == 0:
		_finish(mine, "bring", false, "Your hands are full: you are holding %s, so you cannot fetch %s. Put it down or hand it over first." % [held, query])
		return
	if held == "":
		if not await _pick_up(query, mine, true, "bring", false):
			return
	await _hand_over(mine, false)


func _put_down(mine: int) -> void:
	var held: String = body.holding()
	if held == "":
		_finish(mine, "put_down", false, "You are not holding anything.")
		return
	body.put_down()
	_finish(mine, "put_down", true, "You put %s down." % held, {"put_down": held})


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
