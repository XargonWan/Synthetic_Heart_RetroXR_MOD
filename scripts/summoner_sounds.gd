## SummonerSounds -- the teleport sounds, synthesised (no recordings, nothing to credit).
##
## Four sounds and a loop, all mono 22.05 kHz, made from sines and filtered noise:
##
##   rise()       3 s   the charge: a pitch that climbs while a tremolo quickens and noise
##                      thickens. Plays from the touch until the rift is ready.
##   hum()        1 s   a seamless loop at the top of the climb, for when the link is slow.
##   arrive()     1.4 s the materialising: a fast downward zap, a noise burst, a low thump,
##                      then a two-note chime.
##   leave()      1.2 s the reverse: a climb into a flash and a soft falling chime.
##   fizzle()     0.6 s the rift failing: a sweep falling away.
##
## `samples_*()` return floats in -1..1 (what the tests read); `stream(name)` is the
## AudioStreamWAV the Summoner plays, built once and kept. Noise is seeded, so the same
## sound comes out every time.
extends RefCounted

const RATE := 22050
const PEAK := 0.8

static var _cache: Dictionary = {}


static func stream(sound: String) -> AudioStreamWAV:
	if _cache.has(sound):
		return _cache[sound]
	var samples: PackedFloat32Array
	match sound:
		"rise": samples = samples_rise()
		"hum": samples = samples_hum()
		"arrive": samples = samples_arrive()
		"leave": samples = samples_leave()
		"fizzle": samples = samples_fizzle()
		_:
			push_error("[Rift] no sound called '%s'" % sound)
			return null
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	wav.data = data
	if sound == "hum":
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	_cache[sound] = wav
	return wav


## The climb. Frequency f(t) = 180 Hz * (1 + 7 (t/T)^2), so 180 -> 1440 Hz, the phase
## integrated so there is no click; the tremolo goes from 6 to 16 Hz.
static func samples_rise() -> PackedFloat32Array:
	var seconds := 3.0
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var phase := 0.0
	var trem_phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / seconds
		var f := 180.0 * (1.0 + 7.0 * k * k)
		phase += TAU * f / RATE
		trem_phase += TAU * (6.0 + 10.0 * k) / RATE
		var tone := sin(phase) + 0.5 * sin(phase * 2.003) + 0.28 * sin(phase * 0.5)
		var trem := 1.0 - 0.45 * k * (0.5 + 0.5 * sin(trem_phase))
		# A one-pole low-passed noise that opens up as the pitch climbs.
		lp += (rng.randf_range(-1.0, 1.0) - lp) * (0.03 + 0.4 * k)
		var env := minf(t / 0.15, 1.0) * (0.55 + 0.45 * k)
		out[i] = (tone * 0.4 * trem + lp * 0.9 * k * k) * env
	return _normalise(out)


## A loop at 440, 660 and 880 Hz with an 8 Hz tremolo. Every frequency is a whole number
## of Hz, so a second holds a whole number of cycles of each and the loop has no seam.
static func samples_hum() -> PackedFloat32Array:
	var n := RATE
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		var tone := sin(TAU * 440.0 * t) + 0.6 * sin(TAU * 660.0 * t) + 0.4 * sin(TAU * 880.0 * t)
		var trem := 0.78 + 0.22 * sin(TAU * 8.0 * t)
		out[i] = tone * trem * 0.35
	return _normalise(out, 0.6)


static func samples_arrive() -> PackedFloat32Array:
	var seconds := 1.4
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var zap_phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		# The zap: 2400 -> 300 Hz in a quarter of a second.
		if t < 0.25:
			var zk := t / 0.25
			zap_phase += TAU * lerpf(2400.0, 300.0, zk * zk) / RATE
			s += sin(zap_phase) * (1.0 - zk) * 0.8
		# The burst of noise, fast to die.
		lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.25
		s += lp * exp(-t * 9.0) * 0.9
		# The thump underneath.
		s += sin(TAU * 70.0 * t) * exp(-t * 7.0) * 0.8
		# The chime: two notes, the second a fifth up, a little after the first.
		if t > 0.1:
			var ct := t - 0.1
			s += sin(TAU * 880.0 * ct) * exp(-ct * 3.2) * 0.45
		if t > 0.22:
			var ct2 := t - 0.22
			s += sin(TAU * 1320.0 * ct2) * exp(-ct2 * 3.6) * 0.35
		out[i] = s
	return _normalise(out)


static func samples_leave() -> PackedFloat32Array:
	var seconds := 1.2
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		# The climb into the flash: 300 -> 2400 Hz over 0.45 s.
		if t < 0.45:
			var k := t / 0.45
			phase += TAU * lerpf(300.0, 2400.0, k * k) / RATE
			s += sin(phase) * (0.3 + 0.7 * k) * 0.7
			lp += (rng.randf_range(-1.0, 1.0) - lp) * 0.2
			s += lp * k * 0.5
		# Then a soft falling chime.
		if t > 0.4:
			var ct := t - 0.4
			s += sin(TAU * lerpf(1320.0, 660.0, minf(ct / 0.7, 1.0)) * ct) * exp(-ct * 4.0) * 0.5
		out[i] = s
	return _normalise(out)


static func samples_fizzle() -> PackedFloat32Array:
	var seconds := 0.6
	var n := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var k := t / seconds
		phase += TAU * lerpf(600.0, 90.0, k) / RATE
		out[i] = (sin(phase) + 0.4 * sin(phase * 2.0)) * exp(-t * 5.0)
	return _normalise(out)


## Scale so the loudest sample is `peak`.
static func _normalise(samples: PackedFloat32Array, peak: float = PEAK) -> PackedFloat32Array:
	var top := 0.0001
	for s in samples:
		top = maxf(top, absf(s))
	var scale := peak / top
	for i in samples.size():
		samples[i] *= scale
	return samples
