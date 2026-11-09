## What they know about a screen in front of them (SynthWatching): pure, so no room is needed.
##
##   godot --headless --path RetroXR --script res://mods/xenu.synth_rift/tests/watching_tests.gd
##
## The screen is the Jellyfin Decoder's `now_playing()` dictionary; the point is that Synth is told WHAT is on
## (series, season, episode) and the lines just said, rarely, and never as text in the world.
extends SceneTree

const Watching := preload("res://mods/xenu.synth_rift/scripts/synth_watching.gd")

var _failed := 0
var _count := 0


func _init() -> void:
	_keys()
	_events()
	print("[rift-tests] %d cases, %d failed" % [_count, _failed])
	quit(1 if _failed > 0 or _count == 0 else 0)


func _check(ok: bool, what: String) -> void:
	_count += 1
	if not ok:
		_failed += 1
		print("[rift-tests] FAIL: %s" % what)


func _on(line: String = "", recent: Array = [], paused: bool = false, ep: int = 3) -> Dictionary:
	var d := {"playing": true, "kind": "episode", "series": "Re:Zero", "title": "Re:Union", "season": 2, "episode": ep,
		"paused": paused, "position_s": 754.0, "length_s": 1450.0,
		"text": "Re:Zero, season 2, episode %d 'Re:Union', at 12:34 of 24:10" % ep}
	if line != "":
		d["line"] = line
		d["recent"] = recent if not recent.is_empty() else [line]
	return d


func _screen(info: Dictionary) -> Array:
	return [{"id": "Decoder", "name": "Jellyfin decoder", "info": info}]


func _keys() -> void:
	_check(Watching.key_of({"playing": false}) == "off", "nothing playing is 'off'")
	_check(Watching.key_of(_on()) != Watching.key_of(_on("", [], true)), "pausing changes what is on")
	_check(Watching.key_of(_on()) != Watching.key_of(_on("", [], false, 4)), "another episode changes it")
	var moved := _on()
	moved["position_s"] = 900.0
	_check(Watching.key_of(_on()) == Watching.key_of(moved), "the position moving does not")
	_check(Watching.brief({"playing": false}).is_empty(), "brief of nothing is empty")
	var b := Watching.brief(_on("Emilia: Why?"))
	_check(b["text"].begins_with("Re:Zero, season 2, episode 3") and b["line"] == "Emilia: Why?", "brief carries the sentence and the line")
	_check(not b.has("paused"), "and no pause flag while playing")
	_check(Watching.brief(_on("", [], true))["paused"] == true, "a paused screen says so")
	_check(Watching.clean_line("a\nb") == "a / b", "two rows of a line are joined")
	_check(Watching.clean_line("x".repeat(500)).length() == Watching.MAX_LINE_CHARS, "a long line is cut")
	_check(Watching.lines_text({"recent": ["one", "two", "three", "four"]}) == "\"two\" / \"three\" / \"four\"", "at most the last three lines, quoted")
	_check(Watching.lines_text({}) == "", "no lines, no text")


func _events() -> void:
	var w: RefCounted = Watching.new()
	var ev: Array = w.observe(_screen(_on("Subaru: I will save you.")), 0.0)
	_check(ev.size() == 1, "the first sight of a screen that is playing is told")
	_check(str(ev[0]["summary"]).contains("showing Re:Zero, season 2, episode 3 'Re:Union'"), "it says series, season and episode")
	_check(str(ev[0]["summary"]).contains("Just said: \"Subaru: I will save you.\""), "and what was just said")
	_check(is_equal_approx(ev[0]["salience"], Watching.CHANGE_SALIENCE), "quietly")
	_check(ev[0]["data"]["watching"]["text"] != "", "the data carries it too")
	_check(w.observe(_screen(_on("Subaru: I will save you.")), 5.0).is_empty(), "nothing new five seconds on")
	_check(w.observe(_screen(_on("Subaru: I will save you.")), 25.0).is_empty(), "the same line is not told again")
	ev = w.observe(_screen(_on("Emilia: Why would you say that?", ["Subaru: I will save you.", "Emilia: Why would you say that?"])), 26.0)
	_check(ev.size() == 1 and str(ev[0]["summary"]).contains("they just said: \"Subaru: I will save you.\" / \"Emilia: Why would you say that?\""), "a new line is told with the one before it")
	_check(is_equal_approx(ev[0]["salience"], Watching.LINE_SALIENCE), "at a lower salience still")
	_check(w.observe(_screen(_on("A third line.")), 30.0).is_empty(), "but not more often than every LINE_INTERVAL")
	ev = w.observe(_screen(_on("", [], true)), 31.0)
	_check(ev.size() == 1 and str(ev[0]["summary"]).contains("is paused on"), "pausing is told")
	ev = w.observe(_screen(_on("Back again.")), 32.0)
	_check(ev.size() == 1 and str(ev[0]["summary"]).contains("is showing"), "resuming is told")
	ev = w.observe(_screen({"playing": false}), 33.0)
	_check(ev.size() == 1 and str(ev[0]["summary"]).contains("stopped playing"), "stopping is told")
	_check(w.observe(_screen({"playing": false}), 40.0).is_empty(), "and then silence")
	# out of view and back
	w.observe(_screen(_on("x")), 50.0)
	w.observe([], 51.0)
	_check(w.observe(_screen(_on("x")), 52.0).size() == 1, "a screen that left their view and came back is news again")
	# a screen that shows nothing at first sight tells nothing, and a later start is a change
	var w2: RefCounted = Watching.new()
	_check(w2.observe(_screen({"playing": false}), 0.0).is_empty(), "an idle screen has nothing to tell")
	_check(w2.observe(_screen(_on("Go.")), 1.0).size() == 1, "its start is told")
	# no dialogue yet (no reader's track): the change is told without a line, and no dialogue events follow
	var w3: RefCounted = Watching.new()
	var e3: Array = w3.observe(_screen(_on()), 0.0)
	_check(e3.size() == 1 and not str(e3[0]["summary"]).contains("Just said"), "without a text track it only says what is on")
	_check(w3.observe(_screen(_on()), 60.0).is_empty(), "and tells no lines it does not have")
