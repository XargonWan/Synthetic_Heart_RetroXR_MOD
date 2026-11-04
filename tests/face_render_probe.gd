## Photographs their face for a list of Karada `face` payloads, close up. WINDOWED (the dummy renderer is blank).
##
##   SKIN=$HOME/gits/Synthetic_Heart/skins/Rei OUT=/some/folder godot --path RetroXR --resolution 480x480 \
##       --position 20,20 res://mods/xenu.synth_rift/tests/face_render_probe.tscn
extends Node

const Puppet := preload("res://mods/xenu.synth_rift/scripts/karada_puppet.gd")

const CASES := [
	["0_none", {}],
	["1_session", {"happy": 0.65, "relaxed": 0.5, "love": 0.011, "neutral": 0.3, "devotion": 0.2786, "fear": 0.01, "arousal": 0.01, "angry": 0.01}],
	["2_happy_only", {"happy": 0.65}],
	["3_relaxed_only", {"relaxed": 0.5}],
	["4_neutral_only", {"neutral": 0.3}],
	["5_later", {"happy": 0.3, "relaxed": 0.5, "neutral": 0.5, "angry": 0.01, "disgust": 0.01}],
]

var _cam: Camera3D


func _ready() -> void:
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	LoadingOverlay.suspend()
	var out := OS.get_environment("OUT")
	var skin := OS.get_environment("SKIN")
	DirAccess.make_dir_recursive_absolute(out)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.2, 0.22)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.8, 0.8, 0.85)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-20, 160, 0)
	add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = 18
	add_child(_cam)
	_cam.current = true
	var puppet: Node3D = Puppet.new()
	add_child(puppet)
	puppet.load_model(FileAccess.get_file_as_bytes(skin + "/model.vrm"))
	var persona: Variant = JSON.parse_string(FileAccess.get_file_as_string(skin + "/persona.json"))
	if persona is Dictionary:
		puppet.set_persona(persona)
	var face: RefCounted = puppet.face
	face.set("auto_blink", false)
	var h: float = puppet.height
	_cam.position = Vector3(0, h * 0.93, -1.1)
	_cam.look_at(Vector3(0, h * 0.93, 0))
	for c: Array in CASES:
		face.call("set_face_values", c[1])
		await get_tree().create_timer(0.4).timeout
		print("[probe] %s applied=%s" % [c[0], str(face.get("applied"))])
		await _shoot(out, c[0])
	get_tree().quit(0)


func _shoot(out: String, shot: String) -> void:
	for i in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, shot])
