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
