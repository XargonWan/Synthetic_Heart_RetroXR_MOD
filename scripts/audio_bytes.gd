## AudioBytes -- the bytes of a clip Synth made, as an AudioStream Godot can play.
##
## Her voice is a file on the server (Vox writes a .wav; other engines an .mp3 or .ogg) and the
## mod has the bytes, not a path. Godot has no one call for that: an MP3 and an Ogg take their
## bytes directly, a WAV has to be read (RIFF chunks: the format, then the samples) and handed
## to an AudioStreamWAV. 8- and 16-bit PCM, mono or stereo. Anything else is null, never a crash.
extends RefCounted


## The stream, or null when the bytes are nothing playable.
static func stream_from(bytes: PackedByteArray) -> AudioStream:
	if bytes.size() < 16:
		return null
	if bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WAVE":
		return _wav(bytes)
	if bytes.slice(0, 4).get_string_from_ascii() == "OggS":
		return AudioStreamOggVorbis.load_from_buffer(bytes)
	if bytes.slice(0, 3).get_string_from_ascii() == "ID3" or (bytes[0] == 0xFF and (bytes[1] & 0xE0) == 0xE0):
		var mp3 := AudioStreamMP3.new()
		mp3.data = bytes
		return mp3
	return null


static func _wav(bytes: PackedByteArray) -> AudioStreamWAV:
	var pos := 12
	var channels := 0
	var rate := 0
	var bits := 0
	var tag := 0
	var data := PackedByteArray()
	while pos + 8 <= bytes.size():
		var id := bytes.slice(pos, pos + 4).get_string_from_ascii()
		var size := bytes.decode_u32(pos + 4)
		var body := pos + 8
		if id == "fmt " and body + 16 <= bytes.size():
			tag = bytes.decode_u16(body)
			channels = bytes.decode_u16(body + 2)
			rate = bytes.decode_u32(body + 4)
			bits = bytes.decode_u16(body + 14)
		elif id == "data":
			# A streamed file may say 0 or too much for its length: take what is there.
			var end := mini(body + size, bytes.size()) if size > 0 else bytes.size()
			data = bytes.slice(body, end)
			break
		pos = body + size + (size & 1)
	# 1 = PCM, 0xFFFE = extensible (PCM, in every file this has met).
	if (tag != 1 and tag != 0xFFFE) or channels < 1 or channels > 2 or rate <= 0 or data.is_empty():
		return null
	var wav := AudioStreamWAV.new()
	wav.mix_rate = rate
	wav.stereo = channels == 2
	if bits == 16:
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.data = data
	elif bits == 8:
		# WAV's 8 bits are unsigned; Godot's are signed.
		wav.format = AudioStreamWAV.FORMAT_8_BITS
		var signed := PackedByteArray()
		signed.resize(data.size())
		for i in data.size():
			signed.encode_s8(i, int(data[i]) - 128)
		wav.data = signed
	else:
		return null
	return wav


## Seconds in a stream, when it knows (a WAV does by counting).
static func seconds_of(stream: AudioStream) -> float:
	return stream.get_length() if stream != null else 0.0


## What the player said, as a WAV Synth can read: `frames` are the microphone's (stereo float pairs at `rate`),
## mixed to mono and averaged down to `target_rate` (speech needs 16 kHz, not 48), 16-bit PCM with a 44-byte header.
## Empty frames (or a rate of nothing) are an empty result, never a malformed file.
static func wav_from_frames(frames: PackedVector2Array, rate: float, target_rate: int = 16000) -> PackedByteArray:
	if frames.is_empty() or rate <= 0.0 or target_rate <= 0:
		return PackedByteArray()
	var step := rate / float(target_rate)
	var count := maxi(int(floor(float(frames.size()) / maxf(step, 1.0))), 1) if step >= 1.0 else frames.size()
	var pcm := PackedByteArray()
	pcm.resize(count * 2)
	for i in count:
		var from := int(floor(float(i) * step))
		var to := mini(maxi(int(floor(float(i + 1) * step)), from + 1), frames.size())
		var sum := 0.0
		for j in range(from, to):
			sum += (frames[j].x + frames[j].y) * 0.5
		var v := clampf(sum / float(to - from), -1.0, 1.0)
		pcm.encode_s16(i * 2, int(round(v * 32767.0)))
	var out := PackedByteArray()
	out.resize(44)
	out.encode_u32(0, 0x46464952)  # "RIFF"
	out.encode_u32(4, 36 + pcm.size())
	out.encode_u32(8, 0x45564157)  # "WAVE"
	out.encode_u32(12, 0x20746d66)  # "fmt "
	out.encode_u32(16, 16)
	out.encode_u16(20, 1)  # PCM
	out.encode_u16(22, 1)  # mono
	out.encode_u32(24, target_rate)
	out.encode_u32(28, target_rate * 2)
	out.encode_u16(32, 2)
	out.encode_u16(34, 16)
	out.encode_u32(36, 0x61746164)  # "data"
	out.encode_u32(40, pcm.size())
	out.append_array(pcm)
	return out
