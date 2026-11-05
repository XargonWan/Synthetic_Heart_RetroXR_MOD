## Photographs them picking a thing up off a table: the walk over, the moment of taking it and the carry. WINDOWED (never
## --headless: the dummy renderer returns a blank picture). One frame every FRAME_EVERY seconds from the moment the verb is sent.
##
##   SKIN=$HOME/gits/Synthetic_Heart/skins/Rei OUT=/some/folder godot --path RetroXR --resolution 640x480 --position 20,20 \
##       res://mods/xenu.synth_rift/tests/hold_render_probe.tscn
extends Node

const Puppet := preload("res://mods/xenu.synth_rift/scripts/karada_puppet.gd")
const SynthBody := preload("res://mods/xenu.synth_rift/scripts/synth_body.gd")
const FRAME_EVERY := 0.7
const FRAMES := 12

var _cam: Camera3D
var _body: CharacterBody3D
var _thing: RigidBody3D
var _verb := "pick_up"


func _ready() -> void:
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	LoadingOverlay.suspend()
	var out := OS.get_environment("OUT")
	var skin := OS.get_environment("SKIN")
	if OS.get_environment("VERB") != "":
		_verb = OS.get_environment("VERB")
	DirAccess.make_dir_recursive_absolute(out)

	var floor_body := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(30, 1, 30)
	fs.shape = fb
	floor_body.add_child(fs)
	floor_body.position = Vector3(0, -0.5, 0)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(30, 30)
	floor_mesh.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.30, 0.28)
	floor_mesh.material_override = gm
	floor_mesh.position = Vector3(0, 0.5, 0)
	floor_body.add_child(floor_mesh)
	add_child(floor_body)

	# A table, a little way off in front of them (they face -Z), with a Game Boy-sized thing on it.
	var table := StaticBody3D.new()
	var ts := CollisionShape3D.new()
	var tb := BoxShape3D.new()
	tb.size = Vector3(1.0, 0.75, 0.6)
	ts.shape = tb
	table.add_child(ts)
	var tm := MeshInstance3D.new()
	var tbm := BoxMesh.new()
	tbm.size = tb.size
	tm.mesh = tbm
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.45, 0.3, 0.2)
	tm.material_override = tmat
	table.add_child(tm)
	table.position = Vector3(0.0, 0.375, -2.6)
	add_child(table)

	_thing = RigidBody3D.new()
	_thing.name = "Game Boy"
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.09, 0.03, 0.15)
	cs.shape = bs
	_thing.add_child(cs)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	mesh.mesh = bm
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(0.85, 0.85, 0.1)
	mesh.material_override = mm
	_thing.add_child(mesh)
	add_child(_thing)
	_thing.position = Vector3(0.0, 0.75 + 0.016, -2.6)
	_thing.freeze = true

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
	_cam.fov = 45
	add_child(_cam)
	_cam.current = true

	_body = SynthBody.new()
	add_child(_body)
	_body.anchor = Vector3.ZERO
	_body.global_position = Vector3(0, 0.01, 0)
	var puppet: Node3D = Puppet.new()
	add_child(puppet)
	puppet.load_model(FileAccess.get_file_as_bytes(skin + "/model.vrm"))
	for pair: Array in [["idle", "idle/Idle2.fbx"], ["walk", "walk/Walking.fbx"], ["gaming", "gaming/Gaming-sitting.fbx"]]:
		puppet.add_clip(pair[0], FileAccess.get_file_as_bytes(skin + "/animations/" + pair[1]))
		var d := FileAccess.get_file_as_string(skin + "/animations/" + pair[1] + ".json")
		if not d.is_empty():
			puppet.set_clip_descriptor(pair[0], JSON.parse_string(d))
	_body.attach_puppet(puppet)
	_body.sight = func() -> Array: return [_entity()]
	_body.world_lookup = func(q: String) -> Dictionary: return _entity() if q.to_lower() == "game boy" else {}
	await get_tree().physics_frame
	await get_tree().create_timer(0.8).timeout

	# From their left, level with the table top: the walk over, the reach, the hands.
	_cam.position = Vector3(-2.6, 1.15, -1.3)
	_cam.look_at(Vector3(0.0, 0.95, -1.3))
	var result: Dictionary = await _body.act(_verb, {"target": "Game Boy"})
	print("[probe] %s -> %s" % [_verb, str(result.get("detail", ""))])
	for i in FRAMES:
		await get_tree().create_timer(FRAME_EVERY).timeout
		var img := get_viewport().get_texture().get_image()
		var path := "%s/f%02d.png" % [out, i]
		img.save_png(path)
		print("[probe] frame %d t=%.1fs at (%.2f, %.2f) holding=%s thing_y=%.2f" % [i, float(i + 1) * FRAME_EVERY, _body.global_position.x, _body.global_position.z, _body.holding(), _thing.global_position.y])
	get_tree().quit(0)


func _entity() -> Dictionary:
	return {"id": "gb", "name": "Game Boy", "label": "Game Boy", "type": "Node3D", "node": _thing, "position": _thing.global_position,
		"distance": _body.global_position.distance_to(_thing.global_position), "side": "ahead", "front": true, "bearing": 0.0}
