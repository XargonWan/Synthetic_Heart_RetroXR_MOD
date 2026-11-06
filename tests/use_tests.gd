## What Synth may do to a machine and how it is asked for: the words (`parse`) and the doing (`apply`, `insert`, `eject`),
## against stand-ins that have the same methods as a RetroXR TV, VCR and console (SynthUse asks by method name, so no room
## is needed).
##
##   godot --headless --path RetroXR --script res://mods/xenu.synth_rift/tests/use_tests.gd
##
## The line these cases hold: they switch things on, turn volumes, rewind, take media in and out, and they NEVER play: any
## request for a game is refused with the reason.
extends SceneTree

const U := preload("res://mods/xenu.synth_rift/scripts/synth_use.gd")

var _failed := 0
var _count := 0


## A TV's surface: power by `set_power`/`is_on`, volume in steps, mute, channels.
class FakeTV extends Node3D:
	var on := false
	var vol := 0.5
	var muted := false
	var rf := true
	func is_on() -> bool: return on
	func set_power(v: bool) -> void: on = v
	func volume() -> float: return vol
	func remote_volume_up() -> void: vol = minf(1.0, vol + 0.1)
	func remote_volume_down() -> void: vol = maxf(0.0, vol - 0.1)
	func is_muted() -> bool: return muted
	func remote_mute_toggle() -> void: muted = not muted
	func can_change_channel() -> bool: return rf
	func remote_channel_up() -> void: pass
	func remote_channel_down() -> void: pass


## A VCR: transport keys and a slot (`restore_media`, `get_snapped_tape`).
class FakeVCR extends Node3D:
	var tape: Node3D = null
	var pressed: Array = []
	func has_media() -> bool: return tape != null
	func remote_play() -> void: pressed.append("play")
	func remote_pause() -> void: pressed.append("pause")
	func remote_stop() -> void: pressed.append("stop")
	func remote_ff() -> void: pressed.append("ff")
	func remote_rewind() -> void: pressed.append("rewind")
	func remote_eject() -> void:
		pressed.append("eject")
		tape = null
	func get_snapped_tape() -> Node3D: return tape
	func restore_media(t: Node3D, _yaw: float = 0.0) -> void: tape = t


## A console: `is_powered_on` is a PROPERTY (as RetroSystem's is), a cartridge slot that filters by `accepts_media`.
class FakeConsole extends Node3D:
	var is_powered_on := false
	var cart: Node3D = null
	var takes := "gb"
	func toggle_power() -> void: is_powered_on = not is_powered_on
	func set_power(v: bool) -> void:
		if v != is_powered_on:
			toggle_power()
	func accepts_media(m: Node3D) -> bool: return str(m.get_meta("systemid", "")) == takes
	func restore_cartridge(c: Node3D, _yaw: float = 0.0) -> void: cart = c
	func get_snapped_cartridge() -> Node3D: return cart
	func net_release_cartridge() -> void: cart = null


func _init() -> void:
	_words()
	_games_are_refused()
	_tv()
	_vcr()
	_console()
	_media()
	print("[rift-tests] %d cases, %d failed" % [_count, _failed])
	quit(1 if _failed > 0 or _count == 0 else 0)


func _check(ok: bool, what: String) -> void:
	_count += 1
	if not ok:
		_failed += 1
		print("[rift-tests] FAIL: %s" % what)


func _words() -> void:
	for pair: Array in [
		["turn on", U.POWER_ON], ["Turn it ON!", U.POWER_ON], ["switch on", U.POWER_ON], ["power up", U.POWER_ON], ["turn the TV on", U.POWER_ON],
		["turn on the Game Boy", U.POWER_ON], ["turn off", U.POWER_OFF], ["switch it off", U.POWER_OFF], ["shut down", U.POWER_OFF],
		["power off", U.POWER_OFF], ["toggle", U.POWER_TOGGLE], ["power", U.POWER_TOGGLE],
		["volume up", U.VOLUME_UP], ["louder", U.VOLUME_UP], ["turn up the volume", U.VOLUME_UP], ["raise the volume", U.VOLUME_UP],
		["volume down", U.VOLUME_DOWN], ["turn down the volume", U.VOLUME_DOWN], ["quieter", U.VOLUME_DOWN], ["lower the volume", U.VOLUME_DOWN],
		["mute", U.MUTE], ["unmute", U.UNMUTE], ["channel up", U.CHANNEL_UP], ["next channel", U.CHANNEL_UP], ["channel down", U.CHANNEL_DOWN],
		["play", U.PLAY], ["pause", U.PAUSE], ["stop", U.STOP], ["rewind", U.REWIND], ["rewind the tape", U.REWIND],
		["fast forward", U.FAST_FORWARD], ["fast-forward", U.FAST_FORWARD], ["eject", U.EJECT], ["take it out", U.EJECT], ["remove the tape", U.EJECT],
		["insert", U.INSERT], ["put it in", U.INSERT], ["put the cartridge into the console", U.INSERT], ["load the cartridge", U.INSERT],
		["dance", ""], ["", ""], ["   ", ""],
	]:
		_check(U.parse(str(pair[0])) == str(pair[1]), "\"%s\" means '%s' (got '%s')" % [pair[0], pair[1], U.parse(str(pair[0]))])


func _games_are_refused() -> void:
	for text: String in ["play tetris", "play a game", "press A", "press the start button", "start the game", "use the d-pad", "play the game"]:
		_check(U.parse(text) == U.GAME, "\"%s\" is asking to play a game" % text)
	_check(U.parse("turn on the Game Boy") != U.GAME, "the Game Boy is a name, not a game")
	var tv := FakeTV.new()
	var res := U.apply(tv, U.GAME)
	_check(not bool(res["ok"]) and str(res["detail"]).contains("cannot play") and str(res["detail"]).contains("switch it on"),
		"a request for a game is refused, and says what they can do instead")
	var gb := FakeConsole.new()
	_check(U.is_game_machine(gb) and not U.is_game_machine(tv), "a console is a games machine and a TV is not")
	_check(not U.can(gb, U.PLAY), "a console has no PLAY key for them to press")
	tv.free()
	gb.free()


func _tv() -> void:
	var tv := FakeTV.new()
	_check(U.power_state(tv) == false, "an off TV says it is off")
	var r := U.apply(tv, U.POWER_ON)
	_check(bool(r["ok"]) and tv.on and U.power_state(tv) == true, "turn on: the TV is on")
	r = U.apply(tv, U.POWER_ON)
	_check(bool(r["ok"]) and str(r["detail"]).contains("already") and tv.on, "turn on again: told it already was, not toggled off")
	var before := tv.vol
	r = U.apply(tv, U.VOLUME_UP, 3)
	_check(bool(r["ok"]) and tv.vol > before + 0.25, "volume up three presses (%.2f -> %.2f)" % [before, tv.vol])
	r = U.apply(tv, U.VOLUME_DOWN, 2)
	_check(bool(r["ok"]) and str(r["detail"]).contains("down"), "volume down is told")
	tv.vol = 1.0
	r = U.apply(tv, U.VOLUME_UP)
	_check(not bool(r["ok"]) and str(r["detail"]).contains("100%"), "volume already at its top: refused with where it is (%s)" % r["detail"])
	r = U.apply(tv, U.MUTE)
	_check(bool(r["ok"]) and tv.muted, "mute")
	r = U.apply(tv, U.MUTE)
	_check(bool(r["ok"]) and tv.muted and str(r["detail"]).contains("already"), "mute twice does not unmute")
	r = U.apply(tv, U.UNMUTE)
	_check(bool(r["ok"]) and not tv.muted, "unmute")
	tv.rf = false
	r = U.apply(tv, U.CHANNEL_UP)
	_check(not bool(r["ok"]) and str(r["detail"]).contains("aerial"), "channels off the aerial input: told why not")
	r = U.apply(tv, U.REWIND)
	_check(not bool(r["ok"]) and str(r["detail"]).contains("turn it on"), "a TV does not rewind: told what it can do (%s)" % r["detail"])
	r = U.apply(tv, U.POWER_OFF)
	_check(bool(r["ok"]) and not tv.on, "turn off")
	_check(U.presses("volume up a lot") == 5 and U.presses("volume up 4") == 4 and U.presses("volume up") == U.VOLUME_PRESSES and U.presses("volume up 99") == U.MAX_PRESSES,
		"how many presses is asked for")
	tv.free()


func _vcr() -> void:
	var vcr := FakeVCR.new()
	var r := U.apply(vcr, U.REWIND)
	_check(not bool(r["ok"]) and str(r["detail"]).contains("nothing in it"), "rewind with no tape: told there is none")
	var tape := Node3D.new()
	var fit := U.fit_refusal(vcr, tape, "the VCR", "VHS tape 1")
	_check(fit == "" or fit.contains("does not go in"), "a tape is checked against what a VCR takes (%s)" % fit)
	vcr.restore_media(tape)
	r = U.apply(vcr, U.REWIND)
	_check(bool(r["ok"]) and vcr.pressed == ["rewind"], "rewind with a tape presses rewind")
	r = U.apply(vcr, U.PLAY)
	_check(bool(r["ok"]) and vcr.pressed.back() == "play", "play")
	r = U.apply(vcr, U.POWER_ON)
	_check(not bool(r["ok"]) and str(r["detail"]).contains("play"), "a VCR has no power key for them: told what it has (%s)" % r["detail"])
	r = U.apply(vcr, U.EJECT)
	_check(bool(r["ok"]) and vcr.tape == null, "eject takes the tape out")
	r = U.apply(vcr, U.EJECT)
	_check(not bool(r["ok"]), "eject on an empty VCR is refused")
	vcr.free()
	tape.free()


func _console() -> void:
	var gb := FakeConsole.new()
	_check(U.power_state(gb) == false, "a console says it is off by its property")
	var r := U.apply(gb, U.POWER_ON)
	_check(bool(r["ok"]) and gb.is_powered_on and U.power_state(gb) == true, "turn on switches the console on")
	r = U.apply(gb, U.POWER_ON)
	_check(gb.is_powered_on and str(r["detail"]).contains("already"), "turn on a console that is on does not switch it off")
	r = U.apply(gb, U.POWER_TOGGLE)
	_check(bool(r["ok"]) and not gb.is_powered_on, "toggle")
	r = U.apply(gb, U.POWER_OFF)
	_check(str(r["detail"]).contains("already") and not gb.is_powered_on, "turn off an off console: already")
	gb.free()


func _media() -> void:
	var gb := FakeConsole.new()
	var mario := Node3D.new()
	mario.set_meta("systemid", "gb")
	var snes := Node3D.new()
	snes.set_meta("systemid", "snes")
	_check(U.fit_refusal(gb, mario, "the Game Boy", "Mario") == "", "a Game Boy cartridge fits the Game Boy")
	var why := U.fit_refusal(gb, snes, "the Game Boy", "Zelda")
	_check(why.contains("does not fit"), "another machine's cartridge does not (%s)" % why)
	var r := U.insert(gb, mario)
	_check(bool(r["ok"]) and gb.cart == mario and U.held_by(gb) == mario, "insert seats it")
	_check(U.fit_refusal(gb, snes, "the Game Boy", "Zelda").contains("already has"), "a full slot says so")
	_check(U.host_of(mario, [Node3D.new(), gb]) == gb, "what a cartridge sits in is found")
	_check(U.host_of(snes, [gb]) == null, "a loose one is in nothing")
	r = U.eject(gb)
	_check(bool(r["ok"]) and gb.cart == null, "eject takes it out of the slot")
	_check(not bool(U.eject(gb)["ok"]), "and an empty slot has nothing to take out")
	_check(U.options_of(Node3D.new()).contains("no switch"), "a thing with no controls says so")
	gb.free()
	mario.free()
	snes.free()
