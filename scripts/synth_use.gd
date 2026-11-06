## SynthUse -- what Synth may DO to a thing in the room with their hands, and the words that ask for it.
##
## `operate` is the verb: a TV switched on or off, its volume, a VCR's rewind or eject, a cartridge put into a console, a
## console switched on. It is what a person does at a shelf of machines, and it is as far as a person who is not playing
## goes: **nothing here presses a controller button**, and anything that asks for a game (play, press, A, start) is refused
## with the reason, so the model knows it cannot play and says so instead of trying again. They can still take the
## components and set them up (cartridge in, machine on, look at the screen); playing is the player's.
##
## Pure words (`parse`, `plays_a_game`) and duck-typed things (`apply`, `insert`, `eject`: they ask a node what it can do by
## method name, never by class, so the suite drives a stand-in for a TV and the room drives the real one). Nothing here moves
## the body: that is the routine's (`SynthRoutines._operate`), which walks up to the thing first.
extends RefCounted

## What is asked for, as the words of `parse` give it.
const POWER_ON := "power_on"
const POWER_OFF := "power_off"
const POWER_TOGGLE := "power_toggle"
const VOLUME_UP := "volume_up"
const VOLUME_DOWN := "volume_down"
const MUTE := "mute"
const UNMUTE := "unmute"
const CHANNEL_UP := "channel_up"
const CHANNEL_DOWN := "channel_down"
const PLAY := "play"
const PAUSE := "pause"
const STOP := "stop"
const REWIND := "rewind"
const FAST_FORWARD := "fast_forward"
const EJECT := "eject"
const INSERT := "insert"
## Asking to play a game (press a button, start it): refused, never done.
const GAME := "game"

## One press of the volume key moves it by about this much; "louder" is a couple of presses.
const VOLUME_PRESSES := 2
const MAX_PRESSES := 10

## Which media each kind of player takes, by the media's class (a machine that can say so itself is asked: `accepts_media`).
const HOST_TAKES := {
	"VCRPlayer": ["VCRTape"], "DVDPlayer": ["DVDDisc"], "CassettePlayer": ["AudioCassette", "CompactCassette"],
	"CDPlayer": ["AudioDisc"],
}
## The method each kind of machine names what it holds by, in the order they are asked.
const HELD_BY := ["get_snapped_cartridge", "get_snapped_tape", "get_snapped_disc", "get_snapped_media"]

## What the model is told when it asks for what cannot be: everything they can do, so it does not guess again.
const VOCABULARY := "turn on / turn off (a TV, a console), volume up / volume down, mute / unmute, channel up / channel down, " \
	+ "play / pause / stop / rewind / fast forward / eject (a VCR or other player), insert (a cartridge or tape into a machine)"
## Why the answer to "play Tetris" is no, with what they can do instead.
const NO_GAMES := "You cannot play games: you have no way to press a controller's buttons. That is for the player. What you CAN " \
	+ "do is set the machine up: pick up the cartridge, put it in the console (operate insert), pick the console up, switch it " \
	+ "on, and look at its screen."


# ── the words ────────────────────────────────────────────────────────────────

## The words of a request as a lower-case list of what is between the punctuation ("Turn the TV ON!" -> turn, the, tv, on).
static func words(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var word := ""
	for i in text.length():
		var c := text[i].to_lower()
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			word += c
		else:
			if word != "":
				out.append(word)
			word = ""
	if word != "":
		out.append(word)
	return out


static func _has(w: PackedStringArray, list: Array) -> bool:
	for x: Variant in list:
		if w.has(str(x)):
			return true
	return false


## What a request means: one of the constants above, or "" when it is not something they can do. Forgiving about how it is
## said ("turn it on", "switch on", "power up", "louder", "take it out") and strict about what it is.
static func parse(text: String) -> String:
	var w := words(text)
	if w.is_empty():
		return ""
	# A game first: "press A", "play tetris", "start the game" ask for what they cannot do, whatever else is said. "Game" alone
	# is not it ("turn on the Game Boy" is a name), and a bare "play" is a tape's: the routine turns it into a game when the
	# thing it is asked of is a games machine.
	if _has(w, ["press", "button", "buttons", "dpad", "pad", "joystick", "controller", "gamepad", "tetris"]) \
			and not _has(w, ["insert", "eject", "volume", "channel", "rewind"]):
		return GAME
	if _has(w, ["game", "games"]) and _has(w, ["play", "playing", "start", "begin", "run", "launch"]) and not w.has("boy"):
		return GAME
	if _has(w, ["insert", "load", "plug", "slot", "inside"]) or (_has(w, ["put", "place", "push", "stick"]) and _has(w, ["in", "into", "inside"])):
		return INSERT
	if _has(w, ["eject", "unload", "remove"]) or (_has(w, ["take", "pull", "get"]) and _has(w, ["out"])):
		return EJECT
	if _has(w, ["rewind", "rew", "rewinding"]) or (w.has("back") and _has(w, ["tape", "start", "beginning"])):
		return REWIND
	if w.has("fast") or _has(w, ["ff", "forward", "fastforward"]):
		return FAST_FORWARD
	if _has(w, ["unmute"]):
		return UNMUTE
	if _has(w, ["mute", "silence"]):
		return MUTE
	if w.has("volume") or _has(w, ["louder", "quieter", "softer", "lower", "raise"]):
		if _has(w, ["down", "quieter", "softer", "lower", "decrease", "reduce", "less", "quiet"]):
			return VOLUME_DOWN
		return VOLUME_UP
	if w.has("channel") or w.has("ch"):
		return CHANNEL_DOWN if _has(w, ["down", "previous", "prev", "back", "last"]) else CHANNEL_UP
	if _has(w, ["off", "shutdown"]) or (w.has("shut") and w.has("down")) or (_has(w, ["turn", "switch", "power"]) and _has(w, ["off"])):
		return POWER_OFF
	if _has(w, ["on", "boot", "start", "startup"]) or (w.has("power") and w.has("up")) or w.has("wake"):
		return POWER_ON
	if _has(w, ["toggle", "power", "switch", "flip"]):
		return POWER_TOGGLE
	if _has(w, ["pause", "hold"]):
		return PAUSE
	if _has(w, ["stop", "halt"]):
		return STOP
	if _has(w, ["play", "watch", "run"]):
		return PLAY
	return ""


## How many presses of a key a request asks for ("volume up a lot" is more than "a bit"), within MAX_PRESSES.
static func presses(text: String, fallback: int = VOLUME_PRESSES) -> int:
	var w := words(text)
	for x in w:
		if x.is_valid_int():
			return clampi(int(x), 1, MAX_PRESSES)
	if _has(w, ["lot", "much", "max", "full", "far"]):
		return 5
	if _has(w, ["bit", "little", "slightly", "touch", "notch", "one"]):
		return 1
	return fallback


# ── what a thing is and can do ───────────────────────────────────────────────

static func class_of(node: Object) -> String:
	if node == null:
		return ""
	var script: Script = node.get_script()
	return str(script.get_global_name()) if script != null else node.get_class()


## Is it switched on? true / false, or null when it says nothing (a cartridge, a table). A machine says so by a method
## (`is_powered_on()`, `is_on()`) or, as a console does, by a property of that name.
static func power_state(node: Object) -> Variant:
	if node == null:
		return null
	if node.has_method("is_powered_on"):
		return bool(node.call("is_powered_on"))
	if node.has_method("is_on"):
		return bool(node.call("is_on"))
	if "is_powered_on" in node:
		return bool(node.get("is_powered_on"))
	return null


static func has_power_switch(node: Object) -> bool:
	return node != null and (node.has_method("set_power") or node.has_method("toggle_power") or node.has_method("remote_power_toggle"))


## Whether a thing can be asked for `intent` at all (not whether it will work now).
static func can(node: Object, intent: String) -> bool:
	if node == null:
		return false
	match intent:
		POWER_ON, POWER_OFF, POWER_TOGGLE:
			return has_power_switch(node)
		VOLUME_UP:
			return node.has_method("remote_volume_up")
		VOLUME_DOWN:
			return node.has_method("remote_volume_down")
		MUTE, UNMUTE:
			return node.has_method("remote_mute_toggle")
		CHANNEL_UP:
			return node.has_method("remote_channel_up")
		CHANNEL_DOWN:
			return node.has_method("remote_channel_down")
		PLAY:
			return node.has_method("remote_play")
		PAUSE:
			return node.has_method("remote_pause")
		STOP:
			return node.has_method("remote_stop")
		REWIND:
			return node.has_method("remote_rewind")
		FAST_FORWARD:
			return node.has_method("remote_ff")
		EJECT:
			return node.has_method("remote_eject") or node.has_method("net_release_cartridge") or node.has_method("press_eject")
		INSERT:
			return node.has_method("restore_cartridge") or node.has_method("restore_media")
	return false


## What they could do with it, in words, for the model when what it asked for does not apply.
static func options_of(node: Object) -> String:
	var bits := PackedStringArray()
	for pair: Array in [[POWER_ON, "turn it on or off"], [VOLUME_UP, "change the volume"], [MUTE, "mute it"],
			[CHANNEL_UP, "change the channel"], [PLAY, "play, pause, stop"], [REWIND, "rewind or fast forward"],
			[EJECT, "eject what is in it"], [INSERT, "put a cartridge or tape in it"]]:
		if can(node, str(pair[0])):
			bits.append(str(pair[1]))
	return ", ".join(bits) if not bits.is_empty() else "nothing: it has no switch or button they can use"


## Is this a games machine (a console or handheld: something that runs a game)? Asked by what it can take, not by a name.
static func is_game_machine(node: Object) -> bool:
	return node != null and node.has_method("accepts_media") and node.has_method("restore_cartridge")


# ── doing it ─────────────────────────────────────────────────────────────────

## Do `intent` to `node` and say what came of it, as {ok, detail, data}. `count` is the number of presses of a key. It reads the
## thing before and after, so the words are what the room shows and not what was asked. A machine that takes a moment to
## answer (a console booting) is read again by the caller, which waits first.
static func apply(node: Object, intent: String, count: int = VOLUME_PRESSES) -> Dictionary:
	if node == null:
		return _no("it is gone")
	if intent == GAME:
		return _no(NO_GAMES)
	if not can(node, intent):
		return _no("it cannot do that: with it you can %s" % options_of(node))
	match intent:
		POWER_ON, POWER_OFF:
			return _power(node, intent == POWER_ON)
		POWER_TOGGLE:
			var on: Variant = power_state(node)
			return _power(node, true if on == null else not bool(on))
		VOLUME_UP, VOLUME_DOWN:
			var before := _volume(node)
			for i in clampi(count, 1, MAX_PRESSES):
				node.call("remote_volume_up" if intent == VOLUME_UP else "remote_volume_down")
			var after := _volume(node)
			var word := "up" if intent == VOLUME_UP else "down"
			if before >= 0.0 and absf(after - before) < 0.001:
				return _no("the volume would not go any %s: it is at %d%%" % ["higher" if intent == VOLUME_UP else "lower", roundi(after * 100.0)],
					{"volume": after})
			return _yes("You turned the volume %s%s." % [word, (" to %d%%" % roundi(after * 100.0)) if after >= 0.0 else ""], {"volume": after})
		MUTE, UNMUTE:
			var muted: bool = node.has_method("is_muted") and bool(node.call("is_muted"))
			if node.has_method("is_muted") and muted == (intent == MUTE):
				return _yes("It was already %s." % ("muted" if muted else "not muted"), {"muted": muted})
			node.call("remote_mute_toggle")
			var now: bool = node.has_method("is_muted") and bool(node.call("is_muted"))
			return _yes("You %s it." % ("muted" if now else "unmuted"), {"muted": now})
		CHANNEL_UP, CHANNEL_DOWN:
			if node.has_method("can_change_channel") and not bool(node.call("can_change_channel")):
				return _no("it has no channels to change: it is not on the aerial input")
			node.call("remote_channel_up" if intent == CHANNEL_UP else "remote_channel_down")
			return _yes("You changed the channel %s." % ("up" if intent == CHANNEL_UP else "down"))
		PLAY, PAUSE, STOP, REWIND, FAST_FORWARD:
			if node.has_method("has_media") and not bool(node.call("has_media")):
				return _no("there is nothing in it: no tape or disc. Put one in first (operate insert)")
			var method := {PLAY: "remote_play", PAUSE: "remote_pause", STOP: "remote_stop", REWIND: "remote_rewind",
				FAST_FORWARD: "remote_ff"}[intent] as String
			node.call(method)
			var said := {PLAY: "pressed play", PAUSE: "pressed pause", STOP: "pressed stop", REWIND: "pressed rewind",
				FAST_FORWARD: "pressed fast forward"}[intent] as String
			return _yes("You %s." % said)
		EJECT:
			return eject(node)
	return _no("that is not something you can do")


static func _power(node: Object, on: bool) -> Dictionary:
	var before: Variant = power_state(node)
	if before != null and bool(before) == on:
		return _yes("It was already switched %s." % ("on" if on else "off"), {"powered": on, "changed": false})
	if node.has_method("set_power"):
		node.call("set_power", on)
	elif node.has_method("toggle_power"):
		node.call("toggle_power")
	else:
		node.call("remote_power_toggle")
	var after: Variant = power_state(node)
	var data := {"powered": after, "changed": true}
	return _yes("You pressed its power button to switch it %s." % ("on" if on else "off"), data)


static func _volume(node: Object) -> float:
	return float(node.call("volume")) if node.has_method("volume") else -1.0


## What is in a machine, or null: whatever of `HELD_BY` it answers with.
static func held_by(host: Object) -> Node3D:
	if host == null:
		return null
	for method: String in HELD_BY:
		if host.has_method(method):
			var got: Variant = host.call(method)
			if got is Node3D and is_instance_valid(got as Node3D):
				return got as Node3D
	return null


## The machine (among `candidates`) a thing is sitting in, or null: a cartridge in a console, a tape in a VCR. It is what must
## be ejected before the thing can be taken, or the machine goes on believing it holds something that has left.
static func host_of(media: Object, candidates: Array) -> Node3D:
	for c: Variant in candidates:
		if c is Node3D and c != media and held_by(c as Object) == media:
			return c as Node3D
	return null


## Why `media` does not go in `host`, or "" when it does.
static func fit_refusal(host: Object, media: Object, host_name: String, media_name: String) -> String:
	if host == null or media == null:
		return "it is gone"
	if not can(host, INSERT):
		return "%s has no slot you can put anything in" % host_name
	if held_by(host) != null:
		return "%s already has %s in it: eject it first" % [host_name, "something" if held_by(host) == media else "another one"]
	if host.has_method("accepts_media"):
		if not bool(host.call("accepts_media", media)):
			return "%s does not fit in %s: it is for another machine" % [media_name, host_name]
		return ""
	var takes: Variant = HOST_TAKES.get(class_of(host), null)
	if takes is Array and not (takes as Array).has(class_of(media)):
		return "%s does not go in %s" % [media_name, host_name]
	return ""


## Put `media` into `host`. The caller has let go of it (it is no longer in their hands) and checked `fit_refusal`.
static func insert(host: Object, media: Object) -> Dictionary:
	if host.has_method("restore_cartridge"):
		host.call("restore_cartridge", media)
	else:
		host.call("restore_media", media)
	var inside := held_by(host)
	if inside != media:
		return _no("it would not go in")
	return _yes("You put it in.", {"inserted": true, "powered": power_state(host)})


## Take what is in `host` out and leave it just in front of it, loose, where a hand can take it.
static func eject(host: Object) -> Dictionary:
	var inside := held_by(host)
	if host.has_method("remote_eject"):
		if inside == null and host.has_method("has_media") and not bool(host.call("has_media")):
			return _no("there is nothing in it")
		host.call("remote_eject")
		return _yes("You pressed eject: what was in it comes out at the front.", {"ejected": true})
	if inside == null:
		return _no("there is nothing in it")
	if host.has_method("net_release_cartridge"):
		host.call("net_release_cartridge")
	elif host.has_method("press_eject"):
		host.call("press_eject")
	else:
		return _no("it has no way to take it out")
	var out := inside as Node3D
	if out != null and is_instance_valid(out) and out.is_inside_tree() and host is Node3D and (host as Node3D).is_inside_tree():
		# Where the slot let it go is inside the machine: it is set just above it and falls to what the machine stands on.
		out.global_position = (host as Node3D).global_position + Vector3(0.0, 0.12, 0.0)
	return _yes("You took it out.", {"ejected": true})


static func _yes(detail: String, data: Dictionary = {}) -> Dictionary:
	return {"ok": true, "detail": detail, "data": data}


static func _no(detail: String, data: Dictionary = {}) -> Dictionary:
	return {"ok": false, "detail": detail, "data": data}
