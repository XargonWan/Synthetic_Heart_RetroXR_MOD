## The Summoner OBJECT, in a scene with the project's autoloads (not --script).
##
##   XENU_SYNTH_URL=127.0.0.1:8765 godot --headless --path RetroXR res://mods/xenu.synth_rift/tests/summoner_probe.tscn
##
## Spawns the registered scene, switches it on against a real Synth rift socket
## (tests/rift_harness.py), and checks what a player would see: the lamp goes amber
## then green, a body appears beside it, `state` frames carry the room, and when
## Synth leaves the body goes and the lamp is red. Lines are [probe].
extends Node

const SCENE := "res://mods/xenu.synth_rift/scenes/rift_summoner.tscn"

var _summoner: Node = null
var _t := 0.0
var _saw_body := false
var _saw_green := false
var _was_on := false
var _failed := 0


func _ready() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)

	# Something to sense: an object the room would have saved.
	var prop := Node3D.new()
	prop.name = "Crate"
	prop.position = Vector3(1.5, 0.2, 0.5)
	prop.add_to_group("spawned")
	add_child(prop)

	var packed: PackedScene = load(SCENE)
	_check(packed != null, "the scene loads")
	if packed == null:
		get_tree().quit(1)
		return
	_summoner = packed.instantiate()
	_check(_summoner != null, "the scene instantiates")
	add_child(_summoner)
	_summoner.position = Vector3(0, 0.3, 0)
	_summoner.freeze = true
	print("[probe] summoner in the room; is_on=%s" % str(_summoner.is_on()))
	_check(not _summoner.is_on(), "a Summoner starts OFF")
	_summoner.set_on(true)
	_check(_summoner.is_on(), "set_on(true) turns it on")
	_was_on = true


func _process(delta: float) -> void:
	_t += delta
	var host := _summoner.get_parent() if _summoner != null else null
	var body := host.get_node_or_null("SynthBody") if host != null else null
	if body != null and not _saw_body:
		_saw_body = true
		print("[probe] body appeared at %s" % str(body.global_position))
		_check(body.global_position.distance_to(_summoner.global_position) < 1.5, "the body appears beside the Summoner")
	var lamp := _summoner.get_node_or_null("Lamp") as MeshInstance3D if _summoner != null else null
	if lamp != null and lamp.material_override is StandardMaterial3D:
		var c := (lamp.material_override as StandardMaterial3D).albedo_color
		if c.g > 0.9 and c.r < 0.4 and not _saw_green:
			_saw_green = true
			print("[probe] lamp is green")
	# Synth left: everything must be put away.
	if _was_on and _saw_body and not _summoner.is_on():
		_check(host.get_node_or_null("SynthBody") == null or host.get_node("SynthBody").is_queued_for_deletion(),
			"the body goes when the rift closes")
		var lamp2 := _summoner.get_node("Lamp") as MeshInstance3D
		var c2 := (lamp2.material_override as StandardMaterial3D).albedo_color
		_check(c2.r > 0.8 and c2.g < 0.3, "the lamp is red again")
		_check(_saw_green, "the lamp was green while open")
		print("[probe] done, %d failed" % _failed)
		get_tree().quit(1 if _failed > 0 else 0)
	if _t > 60.0:
		print("[probe] timeout")
		get_tree().quit(2)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		print("[probe] FAIL: %s" % what)
