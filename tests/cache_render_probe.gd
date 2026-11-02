## The cached body must LOOK like the body it was made from. WINDOWED.
##   SKIN=... [TIER=quest] godot --path RetroXR --resolution 640x480 res://mods/xenu.synth_rift/tests/cache_render_probe.tscn
extends Node

const Puppet := preload("res://mods/xenu.synth_rift/scripts/karada_puppet.gd")
const BodyCache := preload("res://mods/xenu.synth_rift/scripts/body_cache.gd")


func _ready() -> void:
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	LoadingOverlay.suspend()
	if not OS.get_environment("TIER").is_empty():
		OS.set_environment("RETROXR_TIER", OS.get_environment("TIER"))
	BodyCache.dir = "user://synth_rift_test"
	BodyCache.clear()
	var vrm := FileAccess.get_file_as_bytes(OS.get_environment("SKIN") + "/model.vrm")
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.1, 0.1, 0.14)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.8)
	var env := WorldEnvironment.new()
	env.environment = e
	add_child(env)
	add_child(DirectionalLight3D.new())
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.2, -2.6)
	add_child(cam)
	cam.current = true
	cam.look_at(Vector3(0, 0.95, 0))
	var shots: Array[Image] = []
	for leg: String in ["fresh", "cached"]:
		var puppet: Node3D = Puppet.new()
		add_child(puppet)
		puppet.load_model(vrm, leg == "cached" or true)   # the first call makes and keeps it, the second reads it
		print("[probe] %s: from_cache=%s %d tris, %d ms" % [leg, str(puppet.budget["from_cache"]), puppet.budget["tris"], puppet.budget["ms"]])
		for i in 8:
			await get_tree().process_frame
		shots.append(get_viewport().get_texture().get_image())
		shots[-1].save_png("%s/%s.png" % [OS.get_environment("OUT"), leg])
		puppet.queue_free()
		await get_tree().process_frame
	var diff := 0.0
	var n := 0
	for y in range(40, 440):
		for x in range(200, 440):
			var a := shots[0].get_pixel(x, y)
			var b := shots[1].get_pixel(x, y)
			diff += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			n += 3
	print("[probe] mean difference per channel: %.4f" % (diff / n))
	BodyCache.clear()
	get_tree().quit(0)
