## The Summoner OBJECT, in a scene with the project's autoloads (not --script).
##
##   (started by tests/rift_harness.py, which plays Synth's side)
##   PROBE_SERVER=127.0.0.1:8765 godot --headless --path RetroXR res://mods/xenu.synth_rift/tests/summoner_probe.tscn
##
## What a player does: opens the object's menu, types the server and password, touches
## the screen. What must happen: the screen goes from red to Synth cyan, the teleport
## sound plays while it loads, Synth steps out of the capsule and is told she was
## summoned and what she sees (the player, whose head is the camera, included); a
## second touch sends her back. PROBE_EXPECT picks the case:
##   (none)     summon by touching the screen, Synth leaves (the server hangs up)
##   dismiss    summon from the menu's button, then send her back by touching the screen
##   refused    the server wants another password
## Lines are [probe].
extends Node

const SCENE := "res://mods/xenu.synth_rift/scenes/rift_summoner.tscn"
const Sounds := preload("res://mods/xenu.synth_rift/scripts/summoner_sounds.gd")

var _summoner: Node = null
var _camera: Camera3D = null
var _t := 0.0
var _failed := 0
var _menu_ui: Control = null
var _expect := ""
var _phases: Array[int] = []
var _saw_body := false
var _saw_cyan := false
var _saw_open_text := false
var _checked_charging := false
var _checked_arriving := false
var _dismissing := false
var _early_touch_done := false
var _done := false


func _ready() -> void:
	_expect = OS.get_environment("PROBE_EXPECT")
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.5, 0)
	add_child(floor_body)

	# Something to see: an object the room would have saved, in front of the pod.
	var prop := Node3D.new()
	prop.name = "Crate"
	prop.position = Vector3(0.8, 0.2, -2.8)
	prop.add_to_group("spawned")
	add_child(prop)

	# The player: their head is the camera, 3.4 m in front of the pod, looking at it.
	_camera = Camera3D.new()
	_camera.position = Vector3(-0.5, 1.5, -3.4)
	add_child(_camera)
	_camera.look_at(Vector3(0, 0.3, 0))
	_camera.current = true

	var packed: PackedScene = load(SCENE)
	_check(packed != null, "the scene loads")
	if packed == null:
		get_tree().quit(1)
		return
	_summoner = packed.instantiate()
	add_child(_summoner)
	_summoner.position = Vector3(0, 1.105, 0)   # the pod is 2.21 m: its feet on the floor at y = 0
	_summoner.freeze = true
	_summoner.charge_seconds = 0.4
	_summoner.phase_changed.connect(func(p: int) -> void: _phases.append(p))
	print("[probe] summoner in the room; expect='%s'" % _expect)
	_check(not _summoner.is_on(), "a Summoner starts OFF")
	_check(_summoner.status_text() == "Off", "it says Off")
	_check(_screen_is_red(), "the screen is red while idle")
	_check(_summoner._screen_label.text == "SUMMON", "the screen says SUMMON")
	_check_screen_size_and_height()
	_menu_then_open()


## The screen is small and at about chest height (1.1 - 1.4 m above the floor), on the pod's front.
func _check_screen_size_and_height() -> void:
	var cap: MeshInstance3D = _summoner._button.get_node("ButtonMesh")
	var size: Vector3 = cap.mesh.get_aabb().size
	var width := maxf(size.x, size.z)
	var depth := minf(size.x, size.z)
	_check(width <= 0.14 and depth <= 0.08, "the screen is small (%.0f x %.0f cm)" % [width * 100.0, depth * 100.0])
	var floor_y: float = _summoner.global_position.y - 1.105
	var h: float = _summoner._button.global_position.y - floor_y
	_check(h > 1.1 and h < 1.4, "the screen is at chest height (%.2f m above the floor)" % h)
	# On the front half of the pod (towards -Z), outside the shell.
	var rel: Vector3 = _summoner._button.global_position - _summoner.global_position
	_check(rel.z < 0.0 and Vector2(rel.x, rel.z).length() > 0.45, "and on the pod's front, outside the shell")


func _flat_distance(a: Node3D, b: Node3D) -> float:
	return Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()


func _screen_is_red() -> bool:
	var c: Color = _summoner._screen_mat.albedo_color
	return c.r > 0.8 and c.g < 0.3 and c.b < 0.3


func _screen_is_cyan() -> bool:
	var c: Color = _summoner._screen_mat.albedo_color
	return c.r < 0.6 and c.g > 0.9 and c.b > 0.9


## What Tab does on a desktop (SpawnMenuController._raycast_options_host): a ray from
## the camera against layer 21, then up the parents to something with an options menu.
## Without a PointerArea on that layer the object has no menu on Tab, and without
## layer 3 the hand cannot pick it up either (the first build had neither).
func _tab_finds_it() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_summoner.collision_layer == 4, "it is on the pickable layer (3)")
	_check(_summoner.is_in_group("spawned"), "it is in the spawned group, so a room saves it")
	var from: Vector3 = _summoner.global_position + Vector3(0, 0, 1.0)
	var to: Vector3 = _summoner.global_position + Vector3(0, 0, -1.0)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 1 << 20
	q.collide_with_areas = true
	q.collide_with_bodies = true
	var hit: Dictionary = _summoner.get_world_3d().direct_space_state.intersect_ray(q)
	_check(not hit.is_empty(), "the Tab raycast (layer 21) hits the object")
	var node: Node = hit.get("collider") as Node
	var host: Node = null
	while node != null:
		if node.has_method("toggle_options_ui") or node is XRToolsPickable:
			host = node
			break
		node = node.get_parent()
	_check(host == _summoner, "and the options host it resolves to is the Summoner")


## The player's way in: point at the object, open ITS menu, type the server and the
## password there, then touch the screen. Nothing is set from outside.
func _menu_then_open() -> void:
	await _tab_finds_it()
	_summoner.toggle_options_ui(null)
	for i in 6:
		await get_tree().process_frame
	var panel := _summoner.get_node_or_null("RiftOptionsPanel")
	_check(panel != null, "the object has its own menu")
	if panel == null:
		get_tree().quit(1)
		return
	var ui: Control = panel._get_ui()
	_check(ui != null, "the menu's UI loaded in its viewport")
	if ui == null:
		get_tree().quit(1)
		return
	_menu_ui = ui
	_check(ui._server_edit.text == "" and ui._token_edit.text == "", "no server saved yet")
	_check(ui._token_edit.secret, "the password is hidden")
	var server := OS.get_environment("PROBE_SERVER")
	ui._server_edit.text = server
	ui._server_edit.text_submitted.emit(server)
	ui._token_edit.text = "s3cret"
	ui._token_edit.text_submitted.emit("s3cret")
	var saved: Dictionary = JsonStore.read_dict("user://mods/xenu.synth_rift/settings.json", "xenu.synth_rift")
	_check(saved.get("server") == server and saved.get("token") == "s3cret", "typing in the menu saves the settings")

	if _expect == "dismiss":
		# Summon with the menu's own button this time.
		ui._power.pressed.emit()
	else:
		# A hand over the screen. VRButton emits this for a fingertip and for a click.
		_summoner._button.button_pressed.emit()
	_check(_summoner.is_on(), "touching the screen / pressing the menu button starts it")
	_check(_summoner.phase() == 1, "it is CHARGING")
	await get_tree().process_frame
	_check(_screen_is_cyan(), "the screen turns Synth cyan")
	_check(_summoner._screen_label.text == "LINKING", "and says LINKING")
	_check(_summoner._beam.visible, "the beam is up")
	_check(_summoner._sfx.stream == Sounds.stream("rise") and _summoner._sfx.playing, "the charge sound is playing")
	_check(ui._status.text.begins_with("Connecting"), "the menu says it is connecting")
	_checked_charging = true
	# A second touch during the first second must not cancel it.
	_summoner._button.button_pressed.emit()
	_check(_summoner.phase() == 1, "a touch right after starting does not cancel it")


func _process(delta: float) -> void:
	_t += delta
	if _done or _summoner == null:
		return
	if _expect == "refused" and _menu_ui != null:
		if not _summoner.is_on() and _menu_ui._status.text.begins_with("Refused"):
			_check("password" in _menu_ui._status.text, "the menu names the password (got '%s')" % _menu_ui._status.text)
			_check(_summoner.get_parent().get_node_or_null("SynthBody") == null, "no body for a refused rift")
			_check(_screen_is_red(), "the screen is red again")
			_check(_summoner._screen_label.text == "FAILED", "and says FAILED")
			_check(_summoner._sfx.stream == Sounds.stream("fizzle"), "the rift fizzles")
			_finish("refused as expected: %s" % _menu_ui._status.text)
		elif _t > 30.0:
			_check(false, "never refused (status '%s')" % _menu_ui._status.text)
			_finish("timeout")
		return

	var host := _summoner.get_parent()
	var body := host.get_node_or_null("SynthBody")
	if body != null and not _saw_body:
		_saw_body = true
		print("[probe] body appeared at %s" % str(body.global_position))
		_check(_flat_distance(body, _summoner) < 0.3, "the body appears inside the capsule")
		# The floor is at y = 0 and the capsule's centre at 0.3: she stands on the floor, not on the capsule.
		_check(absf(body.global_position.y) < 0.05, "she stands on the floor (y=%.2f), not on top of the capsule" % body.global_position.y)
	if _summoner.phase() == 2 and not _checked_arriving:
		_checked_arriving = true
		_check(_summoner._sfx.stream == Sounds.stream("arrive"), "the arrival sound plays")
		_check(_summoner._screen_label.text == "ARRIVING", "the screen says ARRIVING")
	if _summoner._lamp_nodes.size() > 0:
		if _screen_is_cyan() and (_summoner._light_mat.albedo_color.g > 0.9):
			_saw_cyan = true
	if _menu_ui != null and not _saw_open_text and _menu_ui._status.text.begins_with("Open"):
		_saw_open_text = true
		_check(_menu_ui._power.text == "Close the rift", "the button offers to close it")
		_check(_summoner._screen_label.text == "ONLINE", "the screen says ONLINE")
		_check(body != null and _flat_distance(body, _summoner) > 0.9,
			"she has stepped out of the capsule (%.2f m)" % _flat_distance(body, _summoner))
		_check(_summoner.phase() == 3, "it is OPEN")
		# She faces the player: the camera is at -X/-Z of her.
		var fwd: Vector3 = -body.global_basis.z
		var to_cam: Vector3 = (_camera.global_position - body.global_position)
		to_cam.y = 0.0
		_check(fwd.dot(to_cam.normalized()) > 0.9, "she turned to face the player")

	if _expect == "dismiss":
		if _summoner.phase() == 3 and not _dismissing:
			if not _early_touch_done:
				# Touching right away must not dismiss her (the hand is still over the screen).
				_early_touch_done = true
				_summoner._button.button_pressed.emit()
				_check(_summoner.phase() == 3, "a touch straight after she arrives does not send her back")
			elif _summoner._open_t >= _summoner.DISMISS_GRACE:
				_dismissing = true
				_summoner._button.button_pressed.emit()
				_check(_summoner.phase() == 4, "a touch later sends her back (LEAVING)")
				_check(_summoner._sfx.stream == Sounds.stream("leave"), "the leaving sound plays")
		if _dismissing and _summoner.phase() == 0:
			_check(_summoner.get_parent().get_node_or_null("SynthBody") == null or
				_summoner.get_parent().get_node("SynthBody").is_queued_for_deletion(), "the body is gone")
			_check(_screen_is_red(), "the screen is red again")
			_check(_summoner._screen_label.text == "SUMMON", "and says SUMMON")
			_check(_summoner.status_text() == "Off", "the menu says Off")
			_check(_saw_cyan and _saw_open_text, "it was cyan and open on the way")
			_finish("dismissed")
		elif _t > 40.0:
			_check(false, "never dismissed (phase %d)" % _summoner.phase())
			_finish("timeout")
		return

	# Default case: Synth hangs up (the harness disconnects her).
	if _saw_open_text and not _summoner.is_on():
		_check(_summoner.get_parent().get_node_or_null("SynthBody") == null or
			_summoner.get_parent().get_node("SynthBody").is_queued_for_deletion(), "the body goes when the rift closes")
		_check(_screen_is_red(), "the screen is red again")
		_check(_saw_cyan, "the screen was cyan while open")
		_check(_menu_ui._status.text == "Synth left the room", "the menu says why it closed (got '%s')" % _menu_ui._status.text)
		_check(_phases.slice(0, 5) == [1, 2, 3, 0], "the phases went CHARGING, ARRIVING, OPEN, IDLE (%s)" % str(_phases))
		_finish("closed by Synth")
	elif _t > 60.0:
		_check(false, "timeout (phase %d, status '%s')" % [_summoner.phase(), _summoner.status_text()])
		_finish("timeout")


func _finish(what: String) -> void:
	_done = true
	print("[probe] done (%s), %d failed" % [what, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
		print("[probe] FAIL: %s" % what)
