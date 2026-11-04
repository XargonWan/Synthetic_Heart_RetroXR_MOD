## How they come into view: ONE fade of the whole body, and nothing left to do on the frame they appear.
## WINDOWED (never --headless: the dummy renderer draws nothing).
##
##   SKIN=$HOME/gits/Synthetic_Heart/skins/Rei OUT=/some/folder godot --path RetroXR --resolution 640x480 \
##       --position 20,20 res://mods/xenu.synth_rift/tests/arrival_probe.tscn [-- --nowarm]
##
## Per frame while they fade in it checks that every part of them has the SAME transparency (nothing arrives
## after the rest) and it measures the frame times: a first draw that compiles pipelines and uploads textures
## is a hitch of tens of milliseconds, which is what "arriving in pieces" is. --nowarm is the control: without
## the warm-up the hitch must show, or the number says nothing.
extends Node

const Puppet := preload("res://mods/xenu.synth_rift/scripts/karada_puppet.gd")
const Body := preload("res://mods/xenu.synth_rift/scripts/synth_body.gd")

var _failed := 0
var _frames: Array[float] = []
var _uneven := 0
var _body: CharacterBody3D = null
var _recording := false
var _shots := 0
var _out := ""


func _ready() -> void:
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	LoadingOverlay.suspend()
	var skin := OS.get_environment("SKIN")
	_out = OS.get_environment("OUT")
	var nowarm := "--nowarm" in OS.get_cmdline_user_args()
	if _out.is_empty():
		_out = "user://arrival"
	DirAccess.make_dir_recursive_absolute(_out)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.1, 0.1, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.7)
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	ground.mesh = plane
	add_child(ground)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(8, 1, 8)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.3, 3.0)
	add_child(cam)
	cam.current = true
	cam.look_at(Vector3(0, 0.9, 0))

	_body = Body.new()
	add_child(_body)
	var puppet: Node3D = Puppet.new()
	add_child(puppet)
	var t0 := Time.get_ticks_msec()
	puppet.load_model(FileAccess.get_file_as_bytes(skin + "/model.vrm"))
	for pair: Array in [["idle", "idle/Idle2.fbx"]]:
		puppet.add_clip(pair[0], FileAccess.get_file_as_bytes(skin + "/animations/" + pair[1]))
	print("[probe] body loaded in %d ms" % (Time.get_ticks_msec() - t0))
	if not nowarm:
		await puppet.warm()
	_check(puppet.warmed == (not nowarm), "warmed: %s" % str(puppet.warmed))
	_body.attach_puppet(puppet)
	_body.set_ethereal(true)
	_body.hide_until_summoned()
	# Let the loading settle so the measurement is of the appearance and not of what came before it.
	for i in 20:
		await get_tree().process_frame
	_frames.clear()
	_recording = true
	_body.appear(0.6)
	for i in 60:
		await get_tree().process_frame
		await _shoot_if_needed(i)
	_recording = false
	print("[probe] fade at the end of the appearance: %s" % str(_body._puppet.fade_amount()))

	for amount: float in [0.9, 0.7, 0.55, 0.3, 0.0]:
		_body._set_fade(amount)
		for i in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/fade_%d.png" % [_out, int(amount * 100)])
	var worst := 0.0
	for f in _frames:
		worst = maxf(worst, f)
	print("[probe] frames=%d worst frame %.1f ms, uneven fades %d" % [_frames.size(), worst * 1000.0, _uneven])
	_check(_uneven == 0, "every part has the same transparency in every frame (%d uneven)" % _uneven)
	print("[probe] done (%s), %d failed, worst=%.1f" % ["nowarm" if nowarm else "warmed", _failed, worst * 1000.0])
	get_tree().quit(1 if _failed > 0 else 0)


func _process(delta: float) -> void:
	if not _recording or _body == null:
		return
	_frames.append(delta)
	var values := {}
	for a: Variant in _body._puppet.fade_alphas():
		values[a] = true
	if values.size() > 1:
		_uneven += 1


func _shoot_if_needed(i: int) -> void:
	if i % 3 != 0 or i > 45:
		return
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/arrive_%02d.png" % [_out, _shots])
	_shots += 1


func _check(ok: bool, what: String) -> void:
	if ok:
		print("[probe] ok: %s" % what)
	else:
		_failed += 1
		print("[probe] FAIL: %s" % what)
