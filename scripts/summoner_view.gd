## SummonerView -- what Synth sees when she steps out, in words.
##
## Pure maths and text, so a test can read it. The body faces `forward`; everything
## in the room is placed by its bearing from there (0 straight ahead, positive to the
## right) and its distance. Synth gets the front of the room first -- who is in front
## of her, the player above all -- and a line for what is behind.
extends RefCounted

## What counts as "in front": within this many degrees of straight ahead.
const FRONT_HALF_DEG := 80.0
const SEE_RADIUS := 5.0
const MAX_LISTED := 8


## Degrees from straight ahead to `target`, seen from `origin` facing `forward`
## (both flattened to the floor): 0 ahead, +90 to the right, +-180 behind.
static func bearing_deg(origin: Vector3, forward: Vector3, target: Vector3) -> float:
	var f := Vector2(forward.x, forward.z)
	var d := Vector2(target.x - origin.x, target.z - origin.z)
	if f.length() < 0.0001 or d.length() < 0.0001:
		return 0.0
	f = f.normalized()
	d = d.normalized()
	# Signed angle from f to d; +ve is clockwise seen from above, i.e. to the right.
	return rad_to_deg(atan2(f.x * d.y - f.y * d.x, f.dot(d)))


static func side_words(bearing: float) -> String:
	var a := absf(bearing)
	if a < 15.0:
		return "straight ahead"
	var side := "right" if bearing > 0.0 else "left"
	if a < 50.0:
		return "ahead and to the %s" % side
	if a < 110.0:
		return "to your %s" % side
	if a < 150.0:
		return "behind you on the %s" % side
	return "right behind you"


## Place every entity ({name, type, position: Vector3, ...}) relative to the body and
## sort them nearest first. Adds bearing, distance and side.
static func place(entities: Array, origin: Vector3, forward: Vector3) -> Array:
	var out: Array = []
	for e: Dictionary in entities:
		var pos: Vector3 = e["position"]
		var flat := Vector3(pos.x - origin.x, 0.0, pos.z - origin.z)
		var d := flat.length()
		if d > SEE_RADIUS:
			continue
		var placed: Dictionary = e.duplicate()
		var b := bearing_deg(origin, forward, pos)
		placed["bearing"] = snappedf(b, 1.0)
		placed["distance"] = snappedf(d, 0.01)
		placed["side"] = side_words(b)
		placed["front"] = absf(b) <= FRONT_HALF_DEG
		out.append(placed)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance"] < b["distance"])
	return out


## The message Synth reads when she has just been summoned.
static func summoned_text(room: String, placed: Array) -> String:
	var front: Array = placed.filter(func(e: Dictionary) -> bool: return e["front"])
	var behind: Array = placed.filter(func(e: Dictionary) -> bool: return not e["front"])
	var text := "You have just been summoned into the RetroXR room '%s' through the Synthetic Heart Rift Summoner, and you have stepped out of its capsule. " % room
	# The player first: they are who called her.
	var player: Dictionary = {}
	for e: Dictionary in front:
		if str(e.get("type", "")) == "player":
			player = e
			break
	if not player.is_empty():
		text += "The player is %s, %.1f m away. " % [str(player["side"]), float(player["distance"])]
	elif not placed.filter(func(e: Dictionary) -> bool: return str(e.get("type", "")) == "player").is_empty():
		text += "The player is out of your sight. "
	else:
		text += "You cannot see the player. "
	var others: Array = front.filter(func(e: Dictionary) -> bool: return str(e.get("type", "")) != "player")
	if others.is_empty():
		text += "There is nothing else in front of you. "
	else:
		var bits: PackedStringArray = []
		for e: Dictionary in others.slice(0, MAX_LISTED):
			bits.append("%s, %s, %.1f m" % [_label(e), str(e["side"]), float(e["distance"])])
		text += "In front of you: %s. " % "; ".join(bits)
	var behind_others: Array = behind.filter(func(e: Dictionary) -> bool: return str(e.get("type", "")) != "player")
	if not behind_others.is_empty():
		text += "Behind you there are %d more things. " % behind_others.size()
	return text.strip_edges()


static func _label(e: Dictionary) -> String:
	var label := str(e.get("label", e.get("name", "something")))
	var sid := str(e.get("systemid", ""))
	return "%s (%s)" % [label, sid] if not sid.is_empty() else label


## What changed in the room since the last look, in words: something new in view, something gone, a machine switched
## on or off. `memory` ({name: {label, powered}}) is what she saw last time and is brought up to date; the first
## call only remembers (nothing is "new" to someone who has just arrived). The player is not part of it.
static func room_changes(memory: Dictionary, placed: Array, first_look: bool = false) -> Array:
	var said: Array = []
	var now: Dictionary = {}
	for e: Dictionary in placed:
		if str(e.get("type", "")) == "player":
			continue
		var key := str(e.get("name", ""))
		now[key] = e
		var label := str(e.get("label", key))
		if not memory.has(key):
			if not first_look:
				said.append("%s has appeared %s, %.1f m away." % [_with_article(label), str(e.get("side", "nearby")), float(e.get("distance", 0.0))])
		elif e.has("powered") and memory[key].has("powered") and bool(e["powered"]) != bool(memory[key]["powered"]):
			said.append("The %s was switched %s." % [label, "on" if bool(e["powered"]) else "off"])
	for key: String in memory.keys():
		if not now.has(key) and not first_look:
			said.append("The %s is no longer there." % str(memory[key].get("label", key)))
	memory.clear()
	for key: String in now:
		var e: Dictionary = now[key]
		memory[key] = {"label": str(e.get("label", key)), "powered": e.get("powered", null)}
		if not e.has("powered"):
			memory[key].erase("powered")
	return said


static func _with_article(label: String) -> String:
	return "The %s" % label
