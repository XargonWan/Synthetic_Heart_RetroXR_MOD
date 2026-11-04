## Photographs the real body: their VRM, then their Mixamo idle and greeting, retargeted.
## WINDOWED (never --headless): the dummy renderer returns a correctly sized blank picture.
##
##   SKIN=$HOME/gits/Synthetic_Heart/skins/Rei OUT=/some/folder godot --path RetroXR \
##       --resolution 640x480 --position 20,20 res://mods/xenu.synth_rift/tests/puppet_probe.tscn
extends Node

const Puppet := preload("res://mods/xenu.synth_rift/scripts/karada_puppet.gd")

var _cam: Camera3D


func _ready() -> void:
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	LoadingOverlay.suspend()
	var out := OS.get_environment("OUT")
	var skin := OS.get_environment("SKIN")
	DirAccess.make_dir_recursive_absolute(out)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(10, 10)
	ground.mesh = plane
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.30, 0.28)
	ground.material_override = gm
	add_child(ground)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.12, 0.12, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.78)
	e.ambient_light_energy = 0.9
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = 40
	add_child(_cam)
	_cam.current = true

	var puppet: Node3D = Puppet.new()
	add_child(puppet)
	var t0 := Time.get_ticks_msec()
	_check(puppet.load_model(FileAccess.get_file_as_bytes(skin + "/model.vrm")), "the model loads")
	print("[probe] model in %d ms" % (Time.get_ticks_msec() - t0))
	var side := OS.get_environment("VIEW") == "side"
	# They face -Z; "side" looks at them from their left (+X... their right is -X), full length.
	_cam.position = Vector3(3.2, puppet.height * 0.5, 0) if side else Vector3(0, puppet.height * 0.55, -3.2)
	_cam.look_at(Vector3(0, puppet.height * 0.5, 0))
	await _shoot(out, "1_vrm_rest_pose")

	var idle_file := OS.get_environment("IDLE") if not OS.get_environment("IDLE").is_empty() else "idle/Idle.fbx"
	var clips := {"idle": idle_file, "greet": "greet/Standing Greeting.fbx"}
	for clip: String in clips:
		t0 = Time.get_ticks_msec()
		_check(puppet.add_clip(clip, FileAccess.get_file_as_bytes(skin + "/animations/" + clips[clip])), "%s loads" % clip)
		print("[probe] %s in %d ms (%.1f s long)" % [clip, Time.get_ticks_msec() - t0, puppet.clip_length(clip)])
	print("[probe] %d bones mapped" % puppet.mapped_bones())
	_check(puppet.mapped_bones() > 40, "most of the skeleton maps (%d)" % puppet.mapped_bones())

	puppet.play("greet")
	for t: float in [0.0, 1.5, 3.0]:
		puppet.seek(t)
		await _shoot(out, "2_greet_%03d" % int(t * 10))
	puppet.play("idle")
	for t: float in [0.0, 4.0, 8.0]:
		puppet.seek(t)
		await _shoot(out, "3_idle_%02ds" % int(t))
	get_tree().quit(0)


func _shoot(out: String, shot: String) -> void:
	for i in 4:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, shot])
	print("[probe] %s" % shot)


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("[probe] FAIL: %s" % what)
