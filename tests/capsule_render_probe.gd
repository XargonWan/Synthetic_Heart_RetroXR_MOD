## Photographs the capsule: idle (red), charging (cyan) and online. WINDOWED, never
## --headless (the dummy renderer returns a correctly sized blank picture).
##
##   OUT=/some/folder godot --path RetroXR --resolution 640x480 --position 20,20 \
##       res://mods/xenu.synth_rift/tests/capsule_render_probe.tscn
extends Node

const SCENE := "res://mods/xenu.synth_rift/scenes/rift_summoner.tscn"

var _summoner: Node = null
var _cam: Camera3D = null


func _ready() -> void:
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	LoadingOverlay.suspend()
	var out := OS.get_environment("OUT")
	if out.is_empty():
		out = "user://capsule"
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
	e.ambient_light_color = Color(0.55, 0.57, 0.65)
	e.ambient_light_energy = 0.8
	e.glow_enabled = true
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.1
	add_child(sun)

	_summoner = (load(SCENE) as PackedScene).instantiate()
	add_child(_summoner)
	_summoner.position = Vector3(0, 0, 0)
	_summoner.freeze = true

	_cam = Camera3D.new()
	_cam.fov = 50
	add_child(_cam)
	_cam.current = true

	var mid := Vector3(0, 1.0, 0)
	# The pod's front is +Z, so the player stands on that side.
	await _shoot(out, "1_idle_front", Vector3(1.8, 1.6, 4.2), mid)
	# The flanks wear the logo, the back the ribs.
	await _shoot(out, "1b_right_flank", Vector3(3.0, 1.6, 0.4), Vector3(0, 1.4, 0))
	await _shoot(out, "1c_left_flank", Vector3(-3.0, 1.6, 0.4), Vector3(0, 1.4, 0))
	await _shoot(out, "1d_back", Vector3(1.2, 1.6, -3.5), Vector3(0, 1.2, 0))
	# Carried: see-through, with the yellow rectangle where it would be set down.
	_summoner._signal_held = true   # as if in a hand: the pod's own tick keeps it a ghost
	var placer: Node = _summoner.get_node("GroundPlacement")
	placer.preview({"position": Vector3(2.0, 0, 2.4), "yaw": 0.0})
	await _shoot(out, "2_carried_ghost_and_placement", Vector3(3.8, 1.9, 6.4), Vector3(1.0, 0.8, 1.2))
	placer.preview({})
	_summoner._signal_held = false
	_summoner._ghost_settle = 0.0
	await get_tree().physics_frame
	# The menu, beside it.
	_summoner.toggle_options_ui(_cam)
	await get_tree().process_frame
	await _shoot(out, "3_menu_beside", Vector3(1.2, 1.6, 4.6), Vector3(0.9, 1.1, 0.4))
	_summoner.toggle_options_ui(_cam)
	_summoner._show_charging()
	_summoner._beam_mat.albedo_color.a = 0.4
	_summoner._screen_text("ONLINE")
	var screen: Vector3 = _summoner._button.global_position
	await _shoot(out, "4_screen_from_the_player", screen + Vector3(-0.2, 0.2, 0.75), screen)
	await _with_synth(out)
	get_tree().quit(0)


func _shoot(out: String, shot: String, from: Vector3, at: Vector3) -> void:
	_cam.position = from
	_cam.look_at(at)
	for i in 5:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [out, shot]
	img.save_png(path)
	print("[probe] %s %s (%dx%d)" % [shot, path, img.get_width(), img.get_height()])


## Rei out of the pod with her chat page beside her. Needs SKIN (a Karada skin folder).
func _with_synth(out: String) -> void:
	var skin := OS.get_environment("SKIN")
	if skin.is_empty():
		return
	_summoner._show_charging()
	_summoner._screen_text("ONLINE")
	var body: CharacterBody3D = preload("res://mods/xenu.synth_rift/scripts/synth_body.gd").new()
	add_child(body)
	body.global_position = Vector3(0, 0, 1.5)
	body.rotation.y = PI   # facing the player, who is on the +Z side
	var puppet: Node3D = preload("res://mods/xenu.synth_rift/scripts/karada_puppet.gd").new()
	add_child(puppet)
	puppet.load_model(FileAccess.get_file_as_bytes(skin + "/model.vrm"))
	puppet.add_clip("idle", FileAccess.get_file_as_bytes(skin + "/animations/idle/Idle.fbx"))
	puppet.add_clip("greet", FileAccess.get_file_as_bytes(skin + "/animations/greet/Standing Greeting.fbx"))
	body.attach_puppet(puppet)
	puppet.seek(4.0)
	body.act("say", {"text": "Ciao! Sono appena arrivata. Che bella stanza."})
	body.send_chat("Ciao Rei, mi senti?")
	body.act("say", {"text": "Ti sento benissimo!"})
	body.toggle_options_ui(_cam)
	await get_tree().process_frame
	await _shoot(out, "5_synth_out_of_the_pod", Vector3(1.6, 1.5, 4.6), Vector3(0.4, 1.0, 1.2))
	await _shoot(out, "6_chat_beside_her", Vector3(1.1, 1.5, 3.4), Vector3(0.7, 1.2, 1.4))
