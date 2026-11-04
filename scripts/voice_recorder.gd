## VoiceRecorder -- the player's voice, for Synth to hear.
##
## RetroXR has exactly ONE reader of the host microphone (the `Microphone` autoload: AudioServer keeps a single
## read cursor, so a second reader would starve the machines). This does not read the device either: while
## recording it makes itself one more consumer in the autoload's list, the way a running console is, and is handed
## the same frames. It honours the player's own switch (Options > microphone): with that off no frame ever arrives
## and `stop()` says so, instead of sending silence.
##
## Everything the autoload asks of a consumer is answered here (`microphone_position`, `audio_max_distance`,
## `get_libretro_node().PushMicrophoneFrames`, `hears_microphone_level`, `push_microphone_level`).
extends RefCounted

const AudioBytes := preload("res://mods/xenu.synth_rift/scripts/audio_bytes.gd")

const MAX_SECONDS := 30.0

var _frames := PackedVector2Array()
var _rate := 0.0
var _recording := false
var _started_ms := 0
var _mic: Node = null
var _previous_source: Callable = Callable()
var _our_source: Callable = Callable()
## () -> Vector3: where the "microphone" is, so the gain is full. Set by the owner (the player's head).
var head_source: Callable = Callable()


func is_recording() -> bool:
	return _recording


func seconds() -> float:
	return float(Time.get_ticks_msec() - _started_ms) / 1000.0 if _recording else 0.0


## False when there is nothing to record with (no `Microphone` autoload): the reason is logged.
func start(tree: SceneTree) -> bool:
	if _recording:
		return true
	_mic = tree.root.get_node_or_null("Microphone") if tree != null else null
	if _mic == null or not ("consumer_source" in _mic):
		print("[Rift] voice: this build has no Microphone service; nothing to record with")
		return false
	_frames = PackedVector2Array()
	_rate = 0.0
	_previous_source = _mic.consumer_source
	_our_source = func() -> Array:
		var machines: Array = _previous_source.call()
		var out := machines.duplicate()
		out.append(self)
		return out
	_mic.consumer_source = _our_source
	_recording = true
	_started_ms = Time.get_ticks_msec()
	print("[Rift] voice: recording")
	return true


## Ends the recording: the WAV, or an empty array when nothing was heard (with the reason logged).
func stop() -> PackedByteArray:
	if not _recording:
		return PackedByteArray()
	_recording = false
	# Only give back the list if it is still ours: someone else may have wrapped it since.
	if _mic != null and is_instance_valid(_mic) and _mic.consumer_source == _our_source:
		_mic.consumer_source = _previous_source
	var heard := _frames.size()
	var rate := _rate
	var frames := _frames
	_frames = PackedVector2Array()
	if heard == 0 or rate <= 0.0:
		print("[Rift] voice: no sound arrived (is the microphone switched on in the options?)")
		return PackedByteArray()
	print("[Rift] voice: %.1f s heard" % (float(heard) / rate))
	return AudioBytes.wav_from_frames(frames, rate)


# -- what the Microphone service asks of a consumer -------------------------------------------------

var audio_max_distance := 10.0


func microphone_position() -> Vector3:
	return head_source.call() if head_source.is_valid() else Vector3.ZERO


func get_libretro_node() -> Object:
	return self


func hears_microphone_level() -> bool:
	return false


func push_microphone_level(_level: Vector2) -> void:
	pass


# Named like the extension's method on purpose: this object stands in for a machine's Libretro node.
func PushMicrophoneFrames(frames: PackedVector2Array, rate: float, gain: float) -> void:
	if not _recording:
		return
	_rate = rate
	if gain == 1.0:
		_frames.append_array(frames)
	else:
		for f in frames:
			_frames.append(f * gain)

