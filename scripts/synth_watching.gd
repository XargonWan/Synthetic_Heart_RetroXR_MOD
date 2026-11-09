## SynthWatching -- what they know about a screen in front of them: WHAT is on it and what was JUST SAID.
##
## Pure. A machine that shows something (the Jellyfin Decoder from the xenu.jellyfin mod, or any other
## object with a `now_playing()` method) answers a dictionary:
##   {playing, kind, title, series, season, episode, year, position_s, length_s, paused, text,
##    line?, recent?, words_from?}
## `text` is the sentence ("Re:Zero, season 2, episode 3 'Re:Union', at 12:34 of 24:10"); `line` / `recent` are
## the dialogue from a text track the machine fetched for a reader (it does that while somebody in the
## group "companion_viewer" is in the room -- the body joins it, and the machine then prefers a track for the
## hard of hearing). None of it is ever drawn into the world: it is what they KNOW, told to the server as
## quiet events and carried in what they see.
##
## The events are rare on purpose (each can cost a turn of the model): one when what is on CHANGES (a new
## episode, a pause, a stop), and one every LINE_INTERVAL seconds with the lines said since, only while it
## plays and only if the last line changed.
extends RefCounted

## At most one dialogue event per screen this often (seconds).
const LINE_INTERVAL := 20.0
const MAX_LINES := 3
const CHANGE_SALIENCE := 0.45
const LINE_SALIENCE := 0.3
## A line this long is cut (a model needs the gist, not a paragraph).
const MAX_LINE_CHARS := 160

## id -> {key, line_t, last_line}
var _mem: Dictionary = {}


func forget() -> void:
	_mem.clear()


## What changes the announcement: the thing itself, not the moving position.
static func key_of(info: Dictionary) -> String:
	if not bool(info.get("playing", false)):
		return "off"
	return "%s|%s|%s|%s|%s|%s" % [info.get("kind", ""), info.get("series", ""), info.get("title", ""),
		info.get("season", -1), info.get("episode", -1), "paused" if bool(info.get("paused", false)) else "playing"]


## The compact form carried in what they see (every state frame): nothing that moves every second but the
## line. Empty dictionary when nothing is on.
static func brief(info: Dictionary) -> Dictionary:
	if not bool(info.get("playing", false)):
		return {}
	var d := {"text": str(info.get("text", ""))}
	var line := clean_line(str(info.get("line", "")))
	if not line.is_empty():
		d["line"] = line
	if bool(info.get("paused", false)):
		d["paused"] = true
	return d


static func clean_line(line: String) -> String:
	var t := line.replace("\n", " / ").strip_edges()
	return t.substr(0, MAX_LINE_CHARS) if t.length() > MAX_LINE_CHARS else t


## The lines said lately as one string, oldest first ("A" / "B"), or "".
static func lines_text(info: Dictionary) -> String:
	var recent: Array = info.get("recent", [])
	var out: PackedStringArray = []
	for l in recent.slice(maxi(recent.size() - MAX_LINES, 0)):
		var c := clean_line(str(l))
		if not c.is_empty():
			out.append("\"%s\"" % c)
	return " / ".join(out)


## `screens`: [{id, name, info}] -- the screens in front of them, as the room reports them. `now_s` a
## clock in seconds. Returns the events to send: [{summary, salience, data}] (maybe none).
func observe(screens: Array, now_s: float) -> Array:
	var events: Array = []
	var present := {}
	for s: Dictionary in screens:
		var id := str(s.get("id", ""))
		present[id] = true
		var info: Dictionary = s.get("info", {})
		var name := str(s.get("name", "a screen"))
		var key := key_of(info)
		var m: Dictionary = _mem.get(id, {})
		var first := m.is_empty()
		if first and key == "off":
			# Something that shows nothing has nothing to tell: remember it so a later start is a change.
			_mem[id] = {"key": key, "line_t": now_s, "last_line": ""}
			continue
		if first or str(m.get("key", "")) != key:
			var summary := ""
			if key == "off":
				summary = "The %s stopped playing." % name
			elif bool(info.get("paused", false)):
				summary = "The %s is paused on %s." % [name, str(info.get("text", ""))]
			else:
				summary = "The %s is showing %s." % [name, str(info.get("text", ""))]
				var words := lines_text(info)
				if not words.is_empty():
					summary += " Just said: %s." % words
			events.append({"summary": summary, "salience": CHANGE_SALIENCE,
				"data": {"screen": name, "watching": brief(info)}})
			_mem[id] = {"key": key, "line_t": now_s, "last_line": clean_line(str(info.get("line", "")))}
			continue
		# Same thing still on: the dialogue, now and then.
		if key.ends_with("|playing") and now_s - float(m.get("line_t", 0.0)) >= LINE_INTERVAL:
			var line := clean_line(str(info.get("line", "")))
			var words := lines_text(info)
			if not words.is_empty() and line != str(m.get("last_line", "")):
				events.append({"summary": "On the %s (%s) they just said: %s." % [name, str(info.get("text", "")), words],
					"salience": LINE_SALIENCE, "data": {"screen": name, "watching": brief(info), "recent": info.get("recent", [])}})
				m["last_line"] = line
				m["line_t"] = now_s
				_mem[id] = m
	# A screen that left their view is forgotten, so coming back is told as news.
	for id: String in _mem.keys().duplicate():
		if not present.has(id):
			_mem.erase(id)
	return events
