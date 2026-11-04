## VoiceRecorder against a stand-in for the `Microphone` autoload: it must join the consumers only while recording,
## hand the list back untouched, and say so (an empty clip) when no sound ever arrived.
##
##   godot --headless --path RetroXR --script res://mods/xenu.synth_rift/tests/voice_tests.gd
extends SceneTree

const VoiceRecorder := preload("res://mods/xenu.synth_rift/scripts/voice_recorder.gd")

var _failed := 0
var _count := 0


## What the real autoload exposes to a consumer: a replaceable `consumer_source`, and a tick that feeds each of them.
class FakeMic extends Node:
	var consumer_source: Callable = func() -> Array: return ["a console"]

	func tick(frames: PackedVector2Array) -> void:
		for c in consumer_source.call():
			if c is String:
				continue
			c.get_libretro_node().PushMicrophoneFrames(frames, 48000.0, 1.0)


func _init() -> void:
	var mic := FakeMic.new()
	mic.name = "Microphone"
	root.add_child(mic)
	var original: Callable = mic.consumer_source
	var rec := VoiceRecorder.new()

	_check(not rec.is_recording(), "not recording at first")
	_check(mic.consumer_source.call() == ["a console"], "the machines are the only consumers")
	_check(rec.start(self), "recording starts")
	_check(rec.is_recording(), "and says so")
	var consumers: Array = mic.consumer_source.call()
	_check(consumers.size() == 2 and consumers[0] == "a console" and consumers[1] == rec, "it is one more consumer beside the console")

	var tone := PackedVector2Array()
	for i in 4800:
		tone.append(Vector2(0.5, 0.5))
	mic.tick(tone)
	mic.tick(tone)
	var wav := rec.stop()
	_check(not rec.is_recording(), "stopped")
	_check(mic.consumer_source == original, "the autoload's list is handed back as it was")
	_check(mic.consumer_source.call() == ["a console"], "and no longer includes the recorder")
	_check(wav.size() == 44 + 3200 * 2, "0.2 s at 16 kHz is %d bytes (%d)" % [44 + 6400, wav.size()])
	mic.tick(tone)
	_check(rec.stop().is_empty(), "a second stop is nothing")

	# Nothing arrives (the player's microphone switch is off): an empty clip, so nothing silent is ever sent.
	_check(rec.start(self), "a second recording starts")
	_check(rec.stop().is_empty(), "no sound arrived: the clip is empty, not silence")

	# Someone else wrapped the list while we were recording: stopping must not undo THEIR wrapper.
	rec.start(self)
	var theirs: Callable = func() -> Array: return ["other"]
	mic.consumer_source = theirs
	rec.stop()
	_check(mic.consumer_source == theirs, "a wrapper put on after ours is left alone")

	# No Microphone service in this build: refuses, and says so by returning false.
	mic.free()
	_check(not VoiceRecorder.new().start(self), "no Microphone service, no recording")

	print("[rift-tests] %d cases, %d failed" % [_count, _failed])
	quit(1 if _failed > 0 or _count == 0 else 0)


func _check(ok: bool, what: String) -> void:
	_count += 1
	if not ok:
		_failed += 1
		print("[rift-tests] FAIL: %s" % what)
