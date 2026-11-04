## Photographs the postures: standing, the game clip as a layer over standing and over sitting, sitting, crouching,
## thinking in its loop and mid-stride. WINDOWED (never --headless): the dummy renderer returns a blank picture.
## A small box stands where a seat would, to judge where the hips land (its height is a guess).
##
##   SKIN=$HOME/gits/Synthetic_Heart/skins/Rei OUT=/some/folder godot --path RetroXR \
##       --resolution 480x640 --position 20,20 res://mods/xenu.synth_rift/tests/posture_render_probe.tscn
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
	var seat := MeshInstance3D.new()
	var seat_mesh := BoxMesh.new()
	seat_mesh.size = Vector3(0.5, 0.45, 0.45)
	seat.mesh = seat_mesh
	seat.position = Vector3(0, 0.225, 0.22)
	seat.visible = false
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.25, 0.35, 0.55)
	seat.material_override = sm
	add_child(seat)
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
	puppet.load_model(FileAccess.get_file_as_bytes(skin + "/model.vrm"))
	for pair: Array in [["idle", "idle/Idle2.fbx"], ["walk", "walk/Walking.fbx"], ["sit", "sit/Sitting Idle.fbx"],
			["gaming", "gaming/Gaming-sitting.fbx"], ["crouch", "crouch/Crouching Idle.fbx"], ["think", "think/Thinking.fbx"]]:
		puppet.add_clip(pair[0], FileAccess.get_file_as_bytes(skin + "/animations/" + pair[1]))
		var d := FileAccess.get_file_as_string(skin + "/animations/" + pair[1] + ".json")
		if not d.is_empty():
			puppet.set_clip_descriptor(pair[0], JSON.parse_string(d))
	puppet.xfade_seconds = 0.0
	var h: float = puppet.height
	# From their front-left, a little above their middle.
	_cam.position = Vector3(-1.5, h * 0.62, -2.9)
	_cam.look_at(Vector3(0, h * 0.5, 0))

	# [shot, base, layer, seat visible, seconds to let it run]
	for s: Array in [["1_stand", "idle", "", false, 1.0], ["2_stand_gaming", "idle", "gaming", false, 1.5],
			["3_sit", "sit", "", true, 1.0], ["4_sit_gaming", "sit", "gaming", true, 1.5],
			["5_crouch", "crouch", "", false, 1.0], ["6_think_loop", "think", "", false, 2.2], ["7_walk", "walk", "", false, 0.4],
			["8_walk_gaming", "walk", "gaming", false, 0.4]]:
		puppet.stop_over()
		puppet.play(s[1])
		if s[2] != "":
			puppet.play_over(s[2])
		seat.visible = s[3]
		await get_tree().create_timer(s[4]).timeout
		await _shoot(out, s[0])
	get_tree().quit(0)


func _shoot(out: String, shot: String) -> void:
	for i in 4:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, shot])
	print("[probe] %s" % shot)
