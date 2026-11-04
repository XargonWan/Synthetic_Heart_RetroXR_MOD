## The teleport sounds and Synth's view of the room: pure, so they run with no room.
##
##   godot --headless --path RetroXR --script res://mods/xenu.synth_rift/tests/sound_tests.gd
##
## Nobody can listen to a test, so each case is a measurable fact about the sound that
## would be wrong if the sound were: a climb that does not climb, a loop with a seam, a
## chime with no attack, a sample past full scale. `write` dumps the wav files to listen to:
##   ... sound_tests.gd -- --write=/some/folder
extends SceneTree

const Sounds := preload("res://mods/xenu.synth_rift/scripts/summoner_sounds.gd")
const View := preload("res://mods/xenu.synth_rift/scripts/summoner_view.gd")

var _failed := 0
var _count := 0


func _init() -> void:
	_sounds()
	_view()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--write="):
			_write(arg.substr(8))
	print("[rift-tests] %d cases, %d failed" % [_count, _failed])
	# A suite that ran nothing (a script that did not compile) is not a pass.
	quit(1 if _failed > 0 or _count == 0 else 0)


func _check(ok: bool, what: String) -> void:
	_count += 1
	if not ok:
		_failed += 1
		print("[rift-tests] FAIL: %s" % what)


## Zero crossings per second over [from, to) seconds: a pitch you can count.
func _zcr(s: PackedFloat32Array, from: float, to: float) -> float:
	var a := int(from * Sounds.RATE)
	var b := mini(int(to * Sounds.RATE), s.size())
	var n := 0
	for i in range(a + 1, b):
		if (s[i - 1] < 0.0) != (s[i] < 0.0):
			n += 1
	return float(n) / (to - from)


## Energy at one frequency over [from, to) seconds (Goertzel): how much of `hz` is in there.
func _energy_at(s: PackedFloat32Array, from: float, to: float, hz: float) -> float:
	var a := int(from * Sounds.RATE)
	var b := mini(int(to * Sounds.RATE), s.size())
	var w := TAU * hz / Sounds.RATE
	var coeff := 2.0 * cos(w)
	var s1 := 0.0
	var s2 := 0.0
	for i in range(a, b):
		var cur := s[i] + coeff * s1 - s2
		s2 = s1
		s1 = cur
	return (s1 * s1 + s2 * s2 - coeff * s1 * s2) / float(b - a)


func _rms(s: PackedFloat32Array, from: float, to: float) -> float:
	var a := int(from * Sounds.RATE)
	var b := mini(int(to * Sounds.RATE), s.size())
	var acc := 0.0
	for i in range(a, b):
		acc += s[i] * s[i]
	return sqrt(acc / maxf(float(b - a), 1.0))


func _peak(s: PackedFloat32Array) -> float:
	var p := 0.0
	for v in s:
		p = maxf(p, absf(v))
	return p


func _sounds() -> void:
	var rise := Sounds.samples_rise()
	_check(absf(float(rise.size()) / Sounds.RATE - 3.0) < 0.01, "rise is 3 s")
	_check(_peak(rise) <= 0.801 and _peak(rise) > 0.5, "rise is loud enough and never past full scale")
	# The tone is at f(t) = 180 (1 + 7 (t/3)^2): 215 Hz at 0.5 s, 1054 Hz at 2.5 s. Measure the
	# pitch, not the crossings: the noise thickening as it climbs raises those on its own.
	var f_early := 180.0 * (1.0 + 7.0 * pow(0.5 / 3.0, 2.0))
	var f_late := 180.0 * (1.0 + 7.0 * pow(2.5 / 3.0, 2.0))
	_check(_energy_at(rise, 0.4, 0.6, f_early) > _energy_at(rise, 0.4, 0.6, f_late) * 3.0,
		"early in the rise the pitch is low (%.0f Hz)" % f_early)
	_check(_energy_at(rise, 2.4, 2.6, f_late) > _energy_at(rise, 2.4, 2.6, f_early) * 3.0,
		"late in the rise the pitch is high (%.0f Hz)" % f_late)
	_check(_rms(rise, 2.4, 2.9) > _rms(rise, 0.0, 0.5) * 0.9, "rise does not fade as it climbs")

	var hum := Sounds.samples_hum()
	_check(hum.size() == Sounds.RATE, "hum is exactly one second")
	_check(absf(hum[0]) < 0.02 and absf(hum[hum.size() - 1]) < 0.15, "hum starts at silence-ish and ends where it began")
	var stream := Sounds.stream("hum")
	_check(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_end == hum.size(), "the hum stream loops over its whole length")
	# The step across the seam must be no bigger than the step between two neighbours inside.
	var worst := 0.0
	for i in range(1000, 2000):
		worst = maxf(worst, absf(hum[i] - hum[i - 1]))
	_check(absf(hum[0] - hum[hum.size() - 1]) <= worst * 1.5, "no seam in the hum loop")

	var arrive := Sounds.samples_arrive()
	_check(_rms(arrive, 0.0, 0.3) > _rms(arrive, 1.1, 1.4) * 4.0, "arrive starts with a bang and rings out")
	_check(_peak(arrive) <= 0.801, "arrive never past full scale")
	_check(_zcr(arrive, 0.0, 0.1) > _zcr(arrive, 0.18, 0.28), "the arrive zap falls in pitch")

	var leave := Sounds.samples_leave()
	_check(_zcr(leave, 0.3, 0.45) > _zcr(leave, 0.0, 0.15) * 2.0, "leave climbs into the flash")
	var fizzle := Sounds.samples_fizzle()
	_check(_zcr(fizzle, 0.0, 0.15) > _zcr(fizzle, 0.4, 0.55), "fizzle falls away")
	_check(_rms(fizzle, 0.0, 0.1) > _rms(fizzle, 0.5, 0.6) * 5.0, "fizzle dies")

	for name_: String in ["rise", "hum", "arrive", "leave", "fizzle"]:
		var wav := Sounds.stream(name_)
		_check(wav != null and wav.data.size() > 1000 and wav.mix_rate == Sounds.RATE, "%s makes a stream" % name_)
	_check(Sounds.stream("rise") == Sounds.stream("rise"), "a stream is built once")
	_check(Sounds.stream("nope") == null, "an unknown sound is null")


func _view() -> void:
	var o := Vector3.ZERO
	var fwd := Vector3(0, 0, -1)
	# +X is to the right of someone facing -Z.
	_check(is_equal_approx(View.bearing_deg(o, fwd, Vector3(0, 0, -3)), 0.0), "straight ahead is 0")
	_check(absf(View.bearing_deg(o, fwd, Vector3(3, 0, 0)) - 90.0) < 0.01, "+X is 90 to the right")
	_check(absf(View.bearing_deg(o, fwd, Vector3(-3, 0, 0)) + 90.0) < 0.01, "-X is 90 to the left")
	_check(absf(absf(View.bearing_deg(o, fwd, Vector3(0, 0, 3))) - 180.0) < 0.01, "behind is 180")
	# Turned to face +X, the same point flips side.
	_check(absf(View.bearing_deg(o, Vector3(1, 0, 0), Vector3(0, 0, 3)) - 90.0) < 0.01, "facing +X, +Z is on the right")
	_check(View.bearing_deg(o, fwd, o) == 0.0, "a point on top of you is 0, not a crash")
	_check(View.side_words(0.0) == "straight ahead" and View.side_words(-30.0) == "ahead and to the left", "side words")
	_check(View.side_words(170.0) == "right behind you" and View.side_words(80.0) == "to your right", "side words behind and right")

	var placed := View.place([
		{"name": "Crate", "type": "Node3D", "position": Vector3(1, 0, -2)},
		{"name": "player", "type": "player", "position": Vector3(-0.5, 1.5, -1.2)},
		{"name": "Tv", "type": "RetroTV", "label": "TV", "systemid": "", "position": Vector3(0, 0, 2.5)},
		{"name": "Far", "type": "Node3D", "position": Vector3(0, 0, -9)},
	], o, fwd)
	_check(placed.size() == 3, "what is past SEE_RADIUS is not seen")
	_check(str(placed[0]["type"]) == "player", "nearest first")
	var text := View.summoned_text("bedroom", placed)
	_check(text.contains("summoned") and text.contains("'bedroom'"), "the text says they were summoned, and where")
	_check(text.contains("The player is ahead and to the left"), "the player is placed (%s)" % text)
	_check(text.contains("Crate") and not text.contains("TV, "), "what is in front is listed, what is behind is not")
	_check(text.contains("Behind you there are 1 more things"), "and a line for what is behind")
	var nobody := View.summoned_text("den", View.place([{"name": "Crate", "type": "Node3D", "position": Vector3(0, 0, -1)}], o, fwd))
	_check(nobody.contains("cannot see the player"), "with no player they are told so")
	var behind_player := View.summoned_text("den", View.place([{"name": "player", "type": "player", "position": Vector3(0, 1.5, 2)}], o, fwd))
	_check(behind_player.contains("out of your sight"), "a player behind them is out of sight, not absent")


func _write(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for name_: String in ["rise", "hum", "arrive", "leave", "fizzle"]:
		var path := "%s/summoner_%s.wav" % [dir, name_]
		var err := Sounds.stream(name_).save_to_wav(path)
		print("[rift-tests] wrote %s (%s)" % [path, error_string(err)])
