## Her voice, from bytes to a stream: the WAV a Vox engine writes, and what is not playable.
##
##   godot --headless --path RetroXR --script res://mods/xenu.synth_rift/tests/audio_tests.gd
extends SceneTree

const AudioBytes := preload("res://mods/xenu.synth_rift/scripts/audio_bytes.gd")

var _failed := 0
var _count := 0


func _init() -> void:
	var pcm16 := PackedByteArray()
	pcm16.resize(2000)
	for i in 1000:
		pcm16.encode_s16(i * 2, int(8000.0 * sin(float(i) * 0.1)))
	var mono := AudioBytes.stream_from(_wav(pcm16, 1, 22050, 16)) as AudioStreamWAV
	_check(mono != null, "a 16-bit mono WAV is a stream")
	if mono != null:
		_check(mono.format == AudioStreamWAV.FORMAT_16_BITS and not mono.stereo and mono.mix_rate == 22050, "with its own format")
		_check(mono.data == pcm16, "and its own samples")
		_check(absf(mono.get_length() - 1000.0 / 22050.0) < 0.001, "and its length (%.3f s)" % mono.get_length())
	var stereo := AudioBytes.stream_from(_wav(pcm16, 2, 44100, 16)) as AudioStreamWAV
	_check(stereo != null and stereo.stereo and stereo.mix_rate == 44100, "stereo at 44.1 kHz")

	# 8-bit WAV is unsigned: silence is 128, which is 0 in Godot's signed bytes.
	var pcm8 := PackedByteArray([128, 255, 0, 128])
	var eight := AudioBytes.stream_from(_wav(pcm8, 1, 8000, 8)) as AudioStreamWAV
	_check(eight != null and eight.format == AudioStreamWAV.FORMAT_8_BITS, "an 8-bit WAV")
	if eight != null:
		_check(eight.data.decode_s8(0) == 0 and eight.data.decode_s8(1) == 127 and eight.data.decode_s8(2) == -128,
			"unsigned bytes become signed (%d %d %d)" % [eight.data.decode_s8(0), eight.data.decode_s8(1), eight.data.decode_s8(2)])

	# A chunk before 'data' that is not 'fmt ' (a LIST tag) must be skipped.
	var tagged := _wav(pcm16, 1, 22050, 16, true)
	_check(AudioBytes.stream_from(tagged) != null, "a WAV with a LIST chunk before its data")

	# What is not playable is null, never a crash.
	_check(AudioBytes.stream_from(PackedByteArray()) == null, "nothing is null")
	_check(AudioBytes.stream_from("this is not audio at all, just text".to_utf8_buffer()) == null, "text is null")
	_check(AudioBytes.stream_from(_wav(pcm16, 1, 22050, 24)) == null, "24-bit is not played, and says so by being null")
	_check(AudioBytes.stream_from(_wav(pcm16, 6, 22050, 16)) == null, "six channels are not played")
	var no_data := _wav(pcm16, 1, 22050, 16)
	_check(AudioBytes.stream_from(no_data.slice(0, 40)) == null, "a WAV cut off before its samples")
	print("[rift-tests] %d cases, %d failed" % [_count, _failed])
	quit(1 if _failed > 0 or _count == 0 else 0)


## A WAV file around `pcm`.
func _wav(pcm: PackedByteArray, channels: int, rate: int, bits: int, with_list: bool = false) -> PackedByteArray:
	var out := PackedByteArray()
	var fmt := PackedByteArray()
	fmt.resize(16)
	fmt.encode_u16(0, 1)
	fmt.encode_u16(2, channels)
	fmt.encode_u32(4, rate)
	fmt.encode_u32(8, rate * channels * bits / 8)
	fmt.encode_u16(12, channels * bits / 8)
	fmt.encode_u16(14, bits)
	var body := PackedByteArray()
	body.append_array("WAVE".to_ascii_buffer())
	body.append_array(_chunk("fmt ", fmt))
	if with_list:
		body.append_array(_chunk("LIST", "INFOISFT".to_ascii_buffer()))
	body.append_array(_chunk("data", pcm))
	out.append_array("RIFF".to_ascii_buffer())
	var n := PackedByteArray()
	n.resize(4)
	n.encode_u32(0, body.size())
	out.append_array(n)
	out.append_array(body)
	return out


func _chunk(id: String, data: PackedByteArray) -> PackedByteArray:
	var c := PackedByteArray()
	c.append_array(id.to_ascii_buffer())
	var n := PackedByteArray()
	n.resize(4)
	n.encode_u32(0, data.size())
	c.append_array(n)
	c.append_array(data)
	if data.size() & 1:
		c.append(0)
	return c


func _check(ok: bool, what: String) -> void:
	_count += 1
	if not ok:
		_failed += 1
		print("[rift-tests] FAIL: %s" % what)
