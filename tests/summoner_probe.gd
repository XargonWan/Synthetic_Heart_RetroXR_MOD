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
var _menu_ui: Control = null
var _saw_open_text := false


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
	_check(_summoner.status_text() == "Off", "it says Off")
	_menu_then_open()


## The player's way in: point at the object, open ITS menu, type the server and the
## password there, press the button there. Nothing is set from outside.
func _menu_then_open() -> void:
	_summoner.toggle_options_ui(null)
	for i in 6:
		await get_tree().process_frame
	var panel := _summoner.get_node_or_null("RiftOptionsPanel")
	_check(panel != null, "the object has its own menu")
	if panel == null:
		get_tree().quit(1)
		return
	_check(panel.visible, "the menu is showing")
	var ui: Control = panel._get_ui()
	_check(ui != null, "the menu's UI loaded in its viewport")
	if ui == null:
		get_tree().quit(1)
		return
	# Fields start empty (no settings yet in this fresh data dir).
	_check(ui._server_edit.text == "" and ui._token_edit.text == "", "no server saved yet")
	_check(ui._token_edit.secret, "the password is hidden")
	var server := OS.get_environment("PROBE_SERVER")
	ui._server_edit.text = server
	ui._server_edit.text_submitted.emit(server)
	ui._token_edit.text = "s3cret"
	ui._token_edit.text_submitted.emit("s3cret")
	var saved: Dictionary = JsonStore.read_dict("user://mods/xenu.synth_rift/settings.json", "xenu.synth_rift")
	_check(saved.get("server") == server and saved.get("token") == "s3cret", "typing in the menu saves the settings")
	_check(not ("s3cret" in FileAccess.get_file_as_string("user://mods/xenu.synth_rift/settings.json").replace('"token": "s3cret"', "")),
		"the password is written once, to the mod's file")
	# Open the rift with the menu's own button.
	ui._power.pressed.emit()
	_check(_summoner.is_on(), "the menu's button turns it on")
	await get_tree().process_frame
	_check(ui._status.text.begins_with("Connecting"), "the menu says it is connecting")
	_was_on = true
	_menu_ui = ui


func _process(delta: float) -> void:
	_t += delta
	# Wrong password: Synth refuses the handshake and the menu must say so.
	if OS.get_environment("PROBE_EXPECT") == "refused" and _menu_ui != null:
		if not _summoner.is_on() and _menu_ui._status.text.begins_with("Refused"):
			_check("password" in _menu_ui._status.text, "the menu names the password (got '%s')" % _menu_ui._status.text)
			_check(_summoner.get_parent().get_node_or_null("SynthBody") == null, "no body for a refused rift")
			print("[probe] refused as expected: %s, %d failed" % [_menu_ui._status.text, _failed])
			get_tree().quit(1 if _failed > 0 else 0)
		elif _t > 30.0:
			print("[probe] FAIL: never refused (status '%s')" % _menu_ui._status.text)
			get_tree().quit(2)
		return
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
	if _menu_ui != null and not _saw_open_text and _menu_ui._status.text.begins_with("Open"):
		_saw_open_text = true
		_check(_menu_ui._power.text == "Close the rift", "the button offers to close it")
	# Synth left: everything must be put away.
	if _was_on and _saw_body and not _summoner.is_on() and _menu_ui != null:
		_check(host.get_node_or_null("SynthBody") == null or host.get_node("SynthBody").is_queued_for_deletion(),
			"the body goes when the rift closes")
		var lamp2 := _summoner.get_node("Lamp") as MeshInstance3D
		var c2 := (lamp2.material_override as StandardMaterial3D).albedo_color
		_check(c2.r > 0.8 and c2.g < 0.3, "the lamp is red again")
		_check(_saw_green, "the lamp was green while open")
		_check(_saw_open_text, "the menu said Open while it was")
		_check(_menu_ui._status.text == "Synth left the room", "the menu says why it closed (got '%s')" % _menu_ui._status.text)
		print("[probe] done, %d failed" % _failed)
		get_tree().quit(1 if _failed > 0 else 0)
	if _t > 60.0:
		print("[probe] timeout")
		get_tree().quit(2)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		print("[probe] FAIL: %s" % what)
