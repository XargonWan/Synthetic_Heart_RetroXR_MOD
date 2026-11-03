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
var _saw_synth_line := false
var _chat_done := false
var _pod_at := Vector3.ZERO
var _saw_think := false
var _game_boy: RigidBody3D = null
var _tv: StaticBody3D = null
var _saw_holding := false
var _held_for := 0.0
var _saw_carried_to_player := false
var _saw_layer := false
var _saw_crouch := false
var _saw_stand_up := false
var _saw_sit := false
var _saw_voice := false
var _saw_idle_again := false
var _gaze_checked := false
var _was_ethereal := false
var _done := false
var _said := {}
var _shots_dir := ""
var _shot_n := 0
var _shot_tick := 0
var _first_puppet := 0
var _saw_mouth := false
var _saw_summon := false
var _summon_ended := false
var _saw_status_label := false
var _saw_joy := false
var _saw_swap := false
var _blinks := 0
var _was_blinking := false
var _arrival_gaze := false


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
	prop.position = Vector3(0.8, 0.2, 2.8)
	prop.add_to_group("spawned")
	add_child(prop)

	# A Game Boy Color on the floor BEHIND the pod (its back is -Z): she cannot see it from where she steps out, so
	# "bring me the Game Boy" means looking for it. A loose object she can lift, named the way the room names one.
	_game_boy = _make_game_boy()
	add_child(_game_boy)
	_game_boy.position = Vector3(-2.2, 0.12, -2.4)
	_game_boy.add_to_group("spawned")

	# A TV that is on, in front and to the right: a lit screen she can watch and take a picture of.
	_tv = _make_tv()
	add_child(_tv)
	_tv.position = Vector3(2.0, 0.9, 2.4)
	_tv.add_to_group("spawned")

	# The player: their head is the camera, 3.4 m in front of the pod (its front is +Z), looking at it.
	_camera = Camera3D.new()
	_camera.position = Vector3(-0.5, 1.5, 3.4)
	add_child(_camera)
	_camera.look_at(Vector3(0, 0.3, 0))
	_camera.current = true

	# SHOTS=<folder> (windowed): a picture every few frames of the whole summon, the way the player sees it.
	_shots_dir = OS.get_environment("SHOTS")
	if not _shots_dir.is_empty():
		for o in LoadingOverlay.owners():
			LoadingOverlay.end(o)
		LoadingOverlay.suspend()
		DirAccess.make_dir_recursive_absolute(_shots_dir)
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.1, 0.1, 0.16)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.5, 0.5, 0.6)
		var env := WorldEnvironment.new()
		env.environment = e
		add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, 30, 0)
		sun.light_energy = 0.7
		add_child(sun)
		var ground := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(12, 12)
		ground.mesh = plane
		add_child(ground)
	var packed: PackedScene = load(SCENE)
	_check(packed != null, "the scene loads")
	if packed == null:
		get_tree().quit(1)
		return
	_summoner = packed.instantiate()
	add_child(_summoner)
	_summoner.position = Vector3(0, 0, 0)   # its origin is on the floor, like a cabinet's
	_summoner.freeze = true
	_summoner.charge_seconds = float(OS.get_environment("CHARGE")) if not OS.get_environment("CHARGE").is_empty() else 0.4
	_summoner.phase_changed.connect(func(p: int) -> void: _phases.append(p))
	print("[probe] summoner in the room; expect='%s'" % _expect)
	_check(not _summoner.is_on(), "a Summoner starts OFF")
	_check(_summoner.status_text() == "Off", "it says Off")
	_check(_screen_is_red(), "the screen is red while idle")
	_check(_summoner._screen_label.text == "SUMMON", "the screen says SUMMON")
	_check_screen_size_and_height()
	await _check_handling()
	_menu_then_open()


## It is handled like an arcade cabinet: held on for a second, see-through in a hand, never thrown,
## stood upright when dropped leaning, set down on a yellow rectangle by aiming at the floor.
func _check_handling() -> void:
	_check(HoldToGrab.seconds_for(_summoner) == HoldToGrab.DEFAULT_SECONDS, "it is taken by holding the grab on it (%.1f s)" % HoldToGrab.seconds_for(_summoner))
	_check(_summoner.throw_scale() == 0.0, "it is never thrown")

	# See-through while carried, solid again once it has settled.
	_check(_summoner.ghost_transparency() == 0.0, "solid at rest")
	_summoner.grabbed.emit(_summoner, null)
	await get_tree().physics_frame
	_check(absf(_summoner.ghost_transparency() - 0.65) < 0.001, "see-through while carried (%.2f)" % _summoner.ghost_transparency())
	_summoner.dropped.emit(_summoner)
	for i in 60:
		await get_tree().physics_frame
	_check(_summoner.ghost_transparency() == 0.0, "solid again once set down (%.2f)" % _summoner.ghost_transparency())

	# The yellow rectangle, the size of its base, with its front toward +Z; and what a release does.
	var placer: Node = _summoner.get_node_or_null("GroundPlacement")
	_check(placer != null, "it has a ground placement")
	if placer != null:
		_check(placer.footprint.is_equal_approx(_summoner.FOOTPRINT), "the rectangle is the size of its base")
		placer.preview({"position": Vector3(3, 0, -2), "yaw": 0.0})
		var marker := get_tree().current_scene.get_node_or_null("GroundPlacementMarker") as Node3D
		_check(marker != null and marker.visible, "a yellow rectangle shows where it will stand")
		placer.preview({})
		placer.apply({"position": Vector3(2, 0, -1), "yaw": 0.7})
		_check(_summoner.global_position.distance_to(Vector3(2, 0, -1)) < 0.01, "letting go stands it on the rectangle")
		_check(absf(_summoner.global_rotation.y - 0.7) < 0.01 and _summoner.global_basis.y.dot(Vector3.UP) > 0.999, "upright, turned as the rectangle was")
		placer.apply({"position": Vector3(0, 0, 0), "yaw": 0.0})

	# Dropped leaning, it stands up again. 1.2 rad (69 degrees) is past where it would topple by
	# itself (its base is 0.58 m in radius, its weight 0.35 m up: it tips at 59), so only the
	# controller that stands it up can bring it back.
	_summoner.freeze = false
	_summoner.global_basis = Basis(Vector3.RIGHT, 1.2)
	for i in 240:
		await get_tree().physics_frame
	var upright: float = _summoner.global_basis.y.dot(Vector3.UP)
	_check(upright > 0.995, "dropped leaning it turns back upright (up dot = %.4f)" % upright)
	_summoner.freeze = true
	_summoner.global_transform = Transform3D(Basis(), Vector3.ZERO)


## The screen is small and at about chest height (1.1 - 1.4 m above the floor), on the pod's front.
func _check_screen_size_and_height() -> void:
	var cap: MeshInstance3D = _summoner._button.get_node("ButtonMesh")
	var size: Vector3 = cap.mesh.get_aabb().size
	var width := maxf(size.x, size.z)
	var depth := minf(size.x, size.z)
	_check(width <= 0.14 and depth <= 0.08, "the screen is small (%.0f x %.0f cm)" % [width * 100.0, depth * 100.0])
	var floor_y: float = _summoner.global_position.y
	var h: float = _summoner._button.global_position.y - floor_y
	_check(h > 1.1 and h < 1.4, "the screen is at chest height (%.2f m above the floor)" % h)
	# On the front half of the pod (towards +Z), on the right of someone standing in front, outside the shell.
	var rel: Vector3 = _summoner._button.global_position - _summoner.global_position
	_check(rel.z > 0.0 and Vector2(rel.x, rel.z).length() > 0.45, "and on the pod's front, outside the shell")
	_check(rel.x > 0.2, "on the right hand of a player standing in front of it (x=%.2f)" % rel.x)


## The menu hangs beside the pod, on the right of the player, at chest height.
func _check_menu_beside(panel: Node3D) -> void:
	var rel: Vector3 = panel.global_position - _summoner.global_position
	var flat := Vector2(rel.x, rel.z).length()
	_check(flat > 1.2 and flat < 1.8, "the menu is beside the pod, not over it (%.2f m)" % flat)
	_check(rel.y > 1.0 and rel.y < 1.7, "at chest height (%.2f m)" % rel.y)
	_check(rel.x > 0.8, "on the right of a player standing in front of it (x=%.2f)" % rel.x)


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
	var from: Vector3 = _summoner.global_position + Vector3(0, 1.1, 1.0)
	var to: Vector3 = _summoner.global_position + Vector3(0, 1.1, -1.0)
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
	for i in 3:
		await get_tree().process_frame
	_check_menu_beside(panel)
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

	# The pod is NOT frozen from here on: a body that overlaps a rigid pod pushes it, and that
	# is the very thing this must not do (it slid away when she stepped out).
	_summoner.freeze = false
	_pod_at = _summoner.global_position
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
	if not _shots_dir.is_empty() and _summoner != null and _summoner.phase() >= 1 and _shot_n < 400:
		_shot_tick += 1
		if _shot_tick % 3 == 0:
			get_viewport().get_texture().get_image().save_png("%s/s_%03d.png" % [_shots_dir, _shot_n])
			_shot_n += 1
	_t += delta
	if _done or _summoner == null:
		return
	if _expect == "refused" and _menu_ui != null:
		if not _summoner.is_on() and _menu_ui._status.text.begins_with("Could not reach"):
			_check("password" in _menu_ui._status.text, "the menu says it could not reach Synth, and that a password is only if it has one (got '%s')" % _menu_ui._status.text)
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
		body.idle_curiosity_on = false  # its random glances would be taken for staring by the gaze checks below (motion_layers_probe tests it)
		print("[probe] body appeared at %s" % str(body.global_position))
		_check(_flat_distance(body, _summoner) < 0.3, "the body appears inside the capsule")
		_put_down_a_vase.call_deferred()
		_check(body.presence() == "summon", "Karada says she is being summoned while she steps out (%s)" % body.presence())
		_saw_summon = true
		# The floor is at y = 0 and the capsule's centre at 0.3: she stands on the floor, not on the capsule.
		_check(absf(body.global_position.y) < 0.05, "she stands on the floor (y=%.2f), not on top of the capsule" % body.global_position.y)
	# Karada drives her: think while the avatar thinks, her voice from her head, idle again after.
	if body != null and body.has_puppet():
		if body.karada_state() == "think" and body._puppet.playing() == "think":
			_saw_think = true
		var puppet: Node3D = body._puppet
		if body.karada_state() == "gaming" and body.layer() == "gaming" and puppet.overlay() == "gaming" and puppet.playing() == "idle":
			_saw_layer = true
		if body.karada_state() == "crouch" and puppet.playing() == "crouch":
			_saw_crouch = true
		if puppet.playing() == "crouch_post":
			_saw_stand_up = true
		if body.karada_state() == "sit" and puppet.playing() == "sit":
			_saw_sit = true
		if body.holding() == "Game Boy Color":
			_saw_holding = true
		# It flies to her hands over a moment (it was 1 m away when she took it); after that it stays there.
		_held_for = _held_for + get_process_delta_time() if body.holding() != "" else 0.0
		if _held_for > 1.0 and _game_boy != null and is_instance_valid(_game_boy) and _game_boy.global_position.distance_to(body.hand_point()) > 0.4:
			_check(false, "what she holds stays in her hands, not left behind (%.2f m)" % _game_boy.global_position.distance_to(body.hand_point()))
		if body.voices_played() >= 1:
			_saw_voice = true
		if _saw_summon and body.presence() == "" and not _summon_ended:
			_summon_ended = true
		if body.get_node_or_null("Status") != null:
			_saw_status_label = true
		if _first_puppet == 0:
			_first_puppet = body._puppet.get_instance_id()
		elif body._puppet.get_instance_id() != _first_puppet:
			_saw_swap = true
		var face: RefCounted = body.face_of()
		if face != null:
			if face.mouth_open() > 0.1:
				_saw_mouth = true
			if float(face.applied.get("joy", 0.0)) > 0.5:
				_saw_joy = true
			var blinking: bool = float(face.applied.get("blink", 0.0)) > 0.5
			if blinking and not _was_blinking:
				_blinks += 1
			_was_blinking = blinking
		if _saw_think and body.karada_state() == "idle" and body._puppet.playing() == "idle":
			_saw_idle_again = true
	# What Synth says lands in the chat log (the harness makes her say a line once she is out).
	if body != null and not _saw_synth_line:
		for line: Dictionary in body.chat_lines():
			if line["who"] == "synth":
				_saw_synth_line = true
	# Intangible while she is inside the pod and walking out of it, solid once she is out.
	if body != null and _summoner.phase() == 2 and body.is_ethereal():
		_was_ethereal = true
		_check(body.collision_layer == 0, "she has no collision while she steps out")
		_check(_summoner.global_position.distance_to(_pod_at) < 0.03, "the pod stays where it stood (%.3f m)" % _summoner.global_position.distance_to(_pod_at))
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
		_check(_was_ethereal, "she was intangible on the way out")
		_check(not body.is_ethereal() and body.collision_layer == 1, "and is solid now she is out")
		_check(body.gaze_kind() == "player" or body._look_kind == "player" and body._look_left > 0.0, "she looks at the player as she arrives")
		_check(_summoner.global_position.distance_to(_pod_at) < 0.05, "the pod never moved (%.3f m)" % _summoner.global_position.distance_to(_pod_at))
		_check(_menu_ui._status.text.contains("Tab"), "the menu says how to talk to her (%s)" % _menu_ui._status.text)
		_chat_roundtrip(body)
		_gaze_roundtrip(body)
		# Her own body, from her skin: the model and the animations were fetched from the server.
		_check(body.has_puppet(), "she wears her own body (Rei's VRM), not the capsule")
		if body.has_puppet():
			var puppet: Node3D = body._puppet
			_check(puppet.mapped_bones() > 40, "her animations are bound to her bones (%d)" % puppet.mapped_bones())
			_check(puppet.has_clip("idle") and puppet.has_clip("greet"), "her idle and greeting arrived")
			_check(puppet.height > 1.4 and puppet.height < 1.9, "she is a person's height (%.2f m)" % puppet.height)
			_check(not body._capsule.visible, "the capsule is hidden")
			_check(puppet.playing() in ["greet", "idle"], "she is playing an animation (%s)" % puppet.playing())
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
		_check(_saw_synth_line, "what Synth said reached the chat log")
		_check(_saw_think, "her body played the think clip when Karada said think")
		_check(_saw_holding, "she picked the Game Boy up (the object was carried in her hands)")
		_check(_game_boy.global_position.distance_to(Vector3(_camera.global_position.x, 0.0, _camera.global_position.z)) < 1.8 or _game_boy.global_position.distance_to(_camera.global_position) < 1.8,
				"and it ended up with the player, who is 3 m from where it was (%.2f m from them)" % _game_boy.global_position.distance_to(_camera.global_position))
		_check(not _game_boy.freeze and _game_boy.collision_layer != 0, "and it is a loose object again, not frozen in the air")
		_check(_saw_layer, "gaming: her hands played over a standing body (a layer from the server's clip and descriptor)")
		_check(_saw_crouch and _saw_stand_up, "crouch: she crouched and then stood up with the clip that ends the state")
		_check(_saw_sit, "sit: she sat")
		_check(_summon_ended, "and the presence ended once she was out (the server heard `summoned`)")
		_check(_saw_voice, "her voice (a WAV from the server) was played from her head")
		_check(_saw_mouth, "her mouth opened while she spoke")
		_check(not _saw_status_label, "nothing is written over her head about what she is doing")
		_check(_saw_joy, "an emotion Karada sent showed on her face")
		_check(_saw_swap, "a change of skin put her in a new body")
		_check(_blinks >= 1, "she blinked by herself (%d)" % _blinks)
		_check(_saw_idle_again, "and she went back to idle when Karada did")
		_check(_menu_ui._status.text == "Synth left the room", "the menu says why it closed (got '%s')" % _menu_ui._status.text)
		_check(_phases.slice(0, 5) == [1, 2, 3, 0], "the phases went CHARGING, ARRIVING, OPEN, IDLE (%s)" % str(_phases))
		_finish("closed by Synth")
	elif _t > (float(OS.get_environment("PROBE_TIMEOUT")) if not OS.get_environment("PROBE_TIMEOUT").is_empty() else 60.0):
		_check(false, "timeout (phase %d, status '%s')" % [_summoner.phase(), _summoner.status_text()])
		_finish("timeout")


## Talking to her: point at HER (the ray Tab uses finds her, not the pod), open her page, write.
func _chat_roundtrip(body: Node3D) -> void:
	if _chat_done:
		return
	_chat_done = true
	var at: Vector3 = body.global_position + Vector3(0, 1.0, 0)
	var q := PhysicsRayQueryParameters3D.create(at + Vector3(2.0, 0, 0), at + Vector3(-2.0, 0, 0))
	q.collision_mask = 1 << 20
	q.collide_with_bodies = true
	var hit: Dictionary = body.get_world_3d().direct_space_state.intersect_ray(q)
	var node: Node = hit.get("collider") as Node
	var host: Node = null
	while node != null:
		if node.has_method("toggle_options_ui"):
			host = node
			break
		node = node.get_parent()
	_check(host == body, "the Tab ray, aimed at her, finds HER and not the pod")
	body.toggle_options_ui(_camera)
	for i in 6:
		await get_tree().process_frame
	var panel := body.get_node_or_null("ChatPanel")
	_check(panel != null and panel.visible, "her chat page opens")
	if panel == null:
		return
	var rel: Vector3 = panel.global_position - body.global_position
	var toward: Vector3 = (_camera.global_position - body.global_position)
	toward.y = 0.0
	_check(rel.y > 0.3 and rel.y < 0.9, "under her, low, not over her shoulder (%.2f m up)" % rel.y)
	_check(Vector2(rel.x, rel.z).normalized().dot(Vector2(toward.x, toward.z).normalized()) > 0.9 and Vector2(rel.x, rel.z).length() > 0.4,
		"in front of her, toward the player (%.2f m)" % Vector2(rel.x, rel.z).length())
	var ui: Control = panel._get_ui()
	_check(ui != null, "the chat page loaded")
	if ui == null:
		return
	ui._edit.text = "ciao Rei, mi senti?"
	ui._send()
	_check(body.chat_lines().size() >= 1 and body.chat_lines()[-1]["who"] == "you", "what is written is kept in the log")
	await get_tree().process_frame
	_check(ui._log.get_parsed_text().contains("ciao Rei"), "and shown on the page")
	_check(ui._edit.text == "", "the field is emptied")


## The reflex is a GLANCE: the player moves, she looks at them for a moment, then relaxes, and does not
## look again for a while whatever they do; she never drops what she chose to look at.
func _gaze_roundtrip(body: Node3D) -> void:
	if _gaze_checked:
		return
	_gaze_checked = true
	# Let her finish whatever she was asked to do (the server is still sending commands), then be still.
	for i in 600:
		await get_tree().create_timer(0.1).timeout
		if not is_instance_valid(body):
			return
		if body._goal == null and Time.get_ticks_msec() > body._deliberate_until + 500 and body._look_left <= 0.0 and body._bubble_left <= 0.0 and _saw_swap and body.acts_seen >= 10:
			break
	var panel := body.get_node_or_null("ChatPanel") as Node3D
	if panel != null and panel.visible:
		panel.hide_panel()
	body._glance_cool = 0.0
	await get_tree().create_timer(2.5).timeout
	_check(not body.is_gazing(), "she is not staring at a player who is standing still")
	_camera.global_position += Vector3(0.6, 0, 0)       # the player steps sideways
	await get_tree().create_timer(0.9).timeout
	_check(body.gaze_kind() == "player", "the player moved: she glances at them")
	# A glance is short (2.2 s, then it eases out in 0.3).
	await get_tree().create_timer(2.6).timeout
	_check(not body.is_gazing(), "and relaxes by herself, though the player has not stopped moving")
	# ...and a player who keeps moving does not draw another one for a good while.
	_camera.global_position += Vector3(-0.6, 0, 0)
	await get_tree().create_timer(1.0).timeout
	_check(not body.is_gazing(), "a player who keeps moving does not make her stare (the cooldown)")
	# She decides to look at something: the reflex stays out of it, and her head goes to it.
	body._glance_cool = 0.0
	body.act("look_at", {"target": "Crate"})
	_camera.global_position += Vector3(0.6, 0, 0)
	await get_tree().create_timer(0.9).timeout
	_check(body.gaze_kind() == "point", "what she chose to look at gets her head, and the player moving does not pull it away (%s)" % body.gaze_kind())
	# The gaze test is over: the harness may now ask her to look for things (a search turns her body about).
	var flag := OS.get_environment("GAZE_DONE_FILE")
	if not flag.is_empty():
		FileAccess.open(flag, FileAccess.WRITE).store_string("done")


func _finish(what: String) -> void:
	_done = true
	print("[probe] done (%s), %d failed" % [what, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


## Something put down in the room while she is out: she is told (the harness checks the event).
func _make_tv() -> StaticBody3D:
	var script := GDScript.new()
	script.source_code = "extends StaticBody3D\nvar display_name := 'TV'\nfunc is_on() -> bool:\n\treturn true\n"
	script.reload()
	var tv := StaticBody3D.new()
	tv.set_script(script)
	tv.name = "TV"
	var body_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.7, 0.55, 0.5)
	body_mesh.mesh = box
	var casing := StandardMaterial3D.new()
	casing.albedo_color = Color(0.15, 0.15, 0.17)
	body_mesh.material_override = casing
	tv.add_child(body_mesh)
	var screen := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 0.4)
	screen.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.9, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.9, 0.3)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	screen.material_override = mat
	screen.position = Vector3(0, 0, -0.26)
	screen.rotation_degrees = Vector3(0, 180, 0)
	tv.add_child(screen)
	# A picture on a screen: bars, so that a picture of it says something (and the side she sees it from does not matter).
	for k in 6:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.08, 0.6, 0.6)
		bar.mesh = bm
		var bmat := StandardMaterial3D.new()
		bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bmat.albedo_color = Color.from_hsv(k / 6.0, 0.9, 1.0)
		bar.material_override = bmat
		bar.position = Vector3(-0.2 + k * 0.08, 0.34, 0)
		tv.add_child(bar)
	var shape := CollisionShape3D.new()
	var bshape := BoxShape3D.new()
	bshape.size = box.size
	shape.shape = bshape
	tv.add_child(shape)
	tv.rotation_degrees = Vector3(0, 53, 0)  # the screen faces the way she comes from
	return tv


func _make_game_boy() -> RigidBody3D:
	var script := GDScript.new()
	script.source_code = "extends RigidBody3D\nvar display_name := 'Game Boy Color'\nvar systemid := 'gbc'\nfunc is_powered_on() -> bool:\n\treturn false\nfunc is_picked_up() -> bool:\n\treturn false\n"
	script.reload()
	var rb := RigidBody3D.new()
	rb.set_script(script)
	rb.name = "System"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.1, 0.15, 0.03)
	shape.shape = box
	rb.add_child(shape)
	rb.mass = 0.3
	return rb


func _put_down_a_vase() -> void:
	await get_tree().create_timer(3.0).timeout
	var vase := Node3D.new()
	vase.name = "Vase"
	vase.position = Vector3(-0.9, 0.2, 2.2)
	vase.add_to_group("spawned")
	add_child(vase)


func _check(ok: bool, what: String) -> void:
	if ok:
		if not _said.has(what):
			_said[what] = true
			print("[probe] ok: %s" % what)
	else:
		_failed += 1
		print("[probe] FAIL: %s" % what)
