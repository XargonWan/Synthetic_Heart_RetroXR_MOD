## RiftSummoner -- the Synthetic Heart Rift Summoner: a teleportation pod a person fits in.
##
## A pickable the player moves about and sets down. A little screen by its opening, at
## chest height, is red while the capsule is idle. Put a hand over it (in VR; on a desktop, click it) and:
##
##   CHARGING  the screen turns Synth cyan, the capsule hums up to a climax and the
##             rift is opened to the Synthetic Heart server in the meantime. The
##             teleport sound lasts for as long as the loading does, and never less
##             than `charge_seconds`.
##   ARRIVING  when the server has welcomed us AND the charge is done: a flash, the
##             body materialises inside the capsule, steps out to its front and turns
##             to the player.
##   OPEN      Synth is told she was summoned and what she sees in front of her, the
##             player included (a player model does not exist: their head is the
##             camera). Touching the screen again, or the menu button, sends her back.
##   LEAVING   she steps back in, dissolves, the rift closes, the screen goes red.
##
## It is handled like an arcade cabinet, because it is as big and as awkward to move:
## taken by HOLDING the grab on it for a second (a ring fills; a stray squeeze or click
## never carries a 2 m pod off), see-through while it is in a hand, never thrown, stood
## upright again if it is dropped leaning, and set down by aiming at the floor, where a
## yellow rectangle shows its base (GroundPlacement). Its menu opens beside it.
##
## It is IDLE whenever a room loads: an open rift is a live connection to somebody's
## server, and that is not something to restore silently.
extends XRToolsPickable

const Protocol := preload("res://mods/xenu.synth_rift/scripts/rift_protocol.gd")
const RiftLink := preload("res://mods/xenu.synth_rift/scripts/rift_link.gd")
const SynthBody := preload("res://mods/xenu.synth_rift/scripts/synth_body.gd")
const RiftSettings := preload("res://mods/xenu.synth_rift/scripts/rift_settings.gd")
const RiftOptionsPanel := preload("res://mods/xenu.synth_rift/scripts/rift_options_panel.gd")
const SummonerModel := preload("res://mods/xenu.synth_rift/scripts/summoner_model.gd")
const SummonerSounds := preload("res://mods/xenu.synth_rift/scripts/summoner_sounds.gd")
const SummonerView := preload("res://mods/xenu.synth_rift/scripts/summoner_view.gd")
const AssetFetcher := preload("res://mods/xenu.synth_rift/scripts/asset_fetcher.gd")
const KaradaPuppet := preload("res://mods/xenu.synth_rift/scripts/karada_puppet.gd")
const RiftDispatch := preload("res://mods/xenu.synth_rift/scripts/rift_dispatch.gd")

## What Synth calls the player: they have no profile in a room.
const PLAYER_NAME := "player"
const MOD_VERSION := "0.6.0"
const STATE_INTERVAL := 1.0
## How far the body may be from this, and how far it looks for things to tell Synth about.
const SENSE_RADIUS := 6.0
const MAX_ENTITIES := 20
## The player this close for the first time is worth telling Synth.
const GREET_DISTANCE := 2.0
const GREET_REARM_SECONDS := 60.0
## How far in front of the capsule she steps out to.
const STEP_OUT := 1.3
## A touch on the screen sends her back only this long after she arrived: a hand that
## is still over the screen from summoning her must not dismiss her.
const DISMISS_GRACE := 2.5

## How see-through it is while carried: 0 solid, 1 invisible (the cabinets' number).
const HELD_TRANSPARENCY := 0.65
## It is still a ghost this long after it stops moving, so a pod dropped or pushed does not
## flash solid in front of the face on its way down.
const GHOST_SETTLE := 0.6
const GHOST_SPEED := 0.15
## The base on the floor, for the yellow rectangle: the feet reach about 0.75 m from the middle.
const FOOTPRINT := Vector2(1.3, 1.3)
## Standing it upright again: the fraction of the tilt corrected each second, and the most it
## turns at, radians a second (an arcade cabinet's numbers). Under UPRIGHT_EPS it rests.
const RIGHT_RATE := 5.0
const RIGHT_MAX := 3.0
const UPRIGHT_EPS := 0.0035
const CENTER_OF_MASS_Y := 0.35

const LIGHT_OFF := Color(0.9, 0.15, 0.1)
## Synth's own colour, from its banner.
const LIGHT_CYAN := Color(0.43, 1.0, 1.0)

enum Phase { IDLE, CHARGING, ARRIVING, OPEN, LEAVING }

## The shortest the charge sounds and looks. The probes shorten it.
var charge_seconds := 2.8

var _phase: Phase = Phase.IDLE
var _link: Node = null
var _body: CharacterBody3D = null
var _light_mat: StandardMaterial3D = null
var _lamp_nodes: Array = []
var _beam: MeshInstance3D = null
var _beam_mat: StandardMaterial3D = null
var _button: Area3D = null
var _screen_mat: StandardMaterial3D = null
var _screen_label: Label3D = null
var _sfx: AudioStreamPlayer3D = null
var _hum: AudioStreamPlayer3D = null
var _charge_t := 0.0
var _open_t := 0.0
var _link_ready := false
var _pulse := 0.0
var _state_clock := 0.0
var _player_near := false
var _greet_cooldown := 0.0
var _status := "Off"
var _status_ok := false
var _ghost_nodes: Array = []
var _ghost_mats: Array = []
var _ghost_on := false
var _ghost_settle := 0.0
var _signal_held := false
## Her real body, fetched from the server while the pod charges: "" not yet, "loading", "ready", "failed".
var _assets_state := ""
var _fetcher: Node = null
var _karada_state := "idle"
var _puppet: Node3D = null

## The state line or the lamp changed: the options menu redraws.
signal status_changed
## The phase changed (the probes wait on it).
signal phase_changed(phase: int)


## The capsule's parts. In _enter_tree so they exist before PickableHighlight (a child)
## readies and looks for its parent's meshes.
func _enter_tree() -> void:
	if not _lamp_nodes.is_empty():
		return
	var parts: Dictionary = SummonerModel.build(self)
	_lamp_nodes = parts["lamp"]
	_beam = parts["beam"]
	_beam_mat = parts["beam_mat"]
	_button = parts["button"]
	_screen_mat = parts["screen_mat"]
	_screen_label = parts["screen_label"]


func _ready() -> void:
	super._ready()
	_light_mat = _build_light()
	_sfx = _player("Sfx")
	_hum = _player("Hum")
	_link = RiftLink.new()
	_link.name = "RiftLink"
	add_child(_link)
	_link.opened.connect(_on_opened)
	_link.closed.connect(_on_closed)
	_link.action_received.connect(_on_action)
	_link.karada_received.connect(_on_karada)
	_button.button_pressed.connect(_on_screen_touched)
	action_pressed.connect(func(_p: Variant) -> void: toggle())
	# Set it down by aiming at the floor: a yellow rectangle shows where it will stand.
	var placer := GroundPlacement.new()
	placer.name = "GroundPlacement"
	placer.host = self
	placer.set_footprint(FOOTPRINT)
	add_child(placer)
	# See-through while carried, like a cabinet.
	_collect_ghost_parts()
	grabbed.connect(func(_p: Variant = null, _by: Variant = null) -> void:
		_signal_held = true
		_set_ghost(true))
	dropped.connect(func(_p: Variant = null) -> void:
		_signal_held = false
		_ghost_settle = GHOST_SETTLE)
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, CENTER_OF_MASS_Y, 0.0)
	angular_damp = maxf(angular_damp, 2.0)
	_show_idle()


func _player(player_name: String) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = player_name
	p.unit_size = 2.5
	p.max_distance = 15.0
	p.volume_db = -3.0
	add_child(p)
	return p


# ── how it is handled ────────────────────────────────────────────────────────

## Taken by holding the grab on it for this long (HoldToGrab asks every pickable).
func grab_hold_seconds() -> float:
	return HoldToGrab.DEFAULT_SECONDS


## A 2 m pod is set down where the hand let go of it, never thrown across the room.
func throw_scale() -> float:
	return 0.0


## Whether anything holds it: a hand, or the laser (a ray grab is held without a GrabDriver, so
## is_picked_up() stays false and no signal fires: the layer it was moved to is the tell).
func _is_held() -> bool:
	if _signal_held or is_picked_up():
		return true
	return collision_layer == picked_up_layer and collision_layer != original_collision_layer


func _physics_process(delta: float) -> void:
	var held := _is_held()
	var moving := not freeze and linear_velocity.length() > GHOST_SPEED
	if held or moving:
		_ghost_settle = GHOST_SETTLE
	else:
		_ghost_settle = maxf(0.0, _ghost_settle - delta)
	var want := held or _ghost_settle > 0.0
	if want != _ghost_on:
		_set_ghost(want)
	# While nobody holds it, it tends to STAND: dropped leaning, it turns back upright about the
	# horizontal. Its heading is left alone, the player's to choose.
	if held or freeze:
		return
	var axis := global_basis.y.cross(Vector3.UP)
	var tilt := asin(clampf(axis.length(), 0.0, 1.0))
	if tilt < UPRIGHT_EPS:
		return
	var turn := minf(tilt * RIGHT_RATE, RIGHT_MAX)
	var yaw_part := Vector3.UP * angular_velocity.dot(Vector3.UP)
	angular_velocity = yaw_part + axis.normalized() * turn


## Everything that draws, as a list to fade, and the materials the mobile renderer fades instead.
func _collect_ghost_parts() -> void:
	_ghost_nodes = find_children("*", "GeometryInstance3D", true, false)
	var seen := {}
	for n: Variant in _ghost_nodes:
		var mi := n as MeshInstance3D
		if mi != null and mi.material_override is StandardMaterial3D and not seen.has(mi.material_override):
			var m := mi.material_override as StandardMaterial3D
			seen[m] = true
			_ghost_mats.append({"mat": m, "alpha": m.albedo_color.a, "mode": m.transparency})


## Whether this renderer honours GeometryInstance3D.transparency. Forward+ does; the Quest's mobile
## renderer and the Compatibility one do not (the cabinet's carried-solid report, 2026-10-21).
func _per_instance_fade() -> bool:
	return RenderingServer.get_current_rendering_method() not in ["mobile", "gl_compatibility"]


func _set_ghost(on: bool) -> void:
	_ghost_on = on
	var amount := HELD_TRANSPARENCY if on else 0.0
	if _per_instance_fade():
		for n: Variant in _ghost_nodes:
			if is_instance_valid(n):
				(n as GeometryInstance3D).transparency = amount
		return
	# Without it: the same look from the materials, which are this pod's own.
	for entry: Dictionary in _ghost_mats:
		var m: StandardMaterial3D = entry["mat"]
		var c := m.albedo_color
		c.a = float(entry["alpha"]) * (1.0 - amount)
		m.albedo_color = c
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if on else int(entry["mode"])


## For the tests: how see-through it is now.
func ghost_transparency() -> float:
	for n: Variant in _ghost_nodes:
		return (n as GeometryInstance3D).transparency
	return 0.0


# ── what the player does ─────────────────────────────────────────────────────

## The menu every object has: point at it and press the left thumbstick (Tab on a
## desktop). The server and password are edited here, on the object.
func toggle_options_ui(camera: Node3D) -> void:
	RiftOptionsPanel.toggle_for(self, camera)


## A hand over the screen (VR), or a click on it (desktop).
func _on_screen_touched() -> void:
	match _phase:
		Phase.IDLE:
			set_on(true)
		Phase.CHARGING:
			# Changed their mind: only once the charge has plainly started, so the
			# hand that began it does not cancel it.
			if _charge_t > 1.0:
				set_on(false)
		Phase.OPEN:
			if _open_t >= DISMISS_GRACE:
				set_on(false)


func toggle() -> void:
	set_on(_phase == Phase.IDLE)


## True from the touch until she has left again.
func is_on() -> bool:
	return _phase != Phase.IDLE


func phase() -> int:
	return _phase


func set_on(on: bool) -> void:
	if on:
		if _phase == Phase.IDLE:
			_begin_summon()
	else:
		match _phase:
			Phase.CHARGING:
				_abort("switched_off", false)
			Phase.ARRIVING, Phase.OPEN:
				_dismiss()


# ── the sequence ─────────────────────────────────────────────────────────────

func _begin_summon() -> void:
	var settings: Dictionary = RiftSettings.load_settings()
	var server := RiftSettings.server_of(settings)
	var url: String = Protocol.socket_url(server, str(settings.get("token", "")))
	var hello: Dictionary = Protocol.hello(_room_id(), ["motion", "speech"],
		Protocol.WANTED_ANIMATIONS, MOD_VERSION)
	print("[Rift] summoning (room=%s)" % _room_id())
	_charge_t = 0.0
	_link_ready = false
	_assets_state = ""
	_free_puppet()
	_free_fetcher()
	_fetcher = AssetFetcher.new()
	_fetcher.name = "AssetFetcher"
	add_child(_fetcher)
	_fetcher.call("setup", server, str(settings.get("token", "")))
	_karada_state = "idle"
	_set_phase(Phase.CHARGING)
	_set_status("Connecting to %s ..." % server, false)
	_show_charging()
	_play(_sfx, "rise")
	if not _sfx.finished.is_connected(_on_rise_finished):
		_sfx.finished.connect(_on_rise_finished)
	if not _link.open_rift(url, hello):
		# open_rift has already said why, through closed(); nothing more to do.
		pass


## The climb is over but the server has not answered: keep the hum going until it does.
func _on_rise_finished() -> void:
	if _phase == Phase.CHARGING:
		_play(_hum, "hum")


func _on_opened(welcome: Dictionary) -> void:
	_link_ready = true
	var assets: Dictionary = welcome.get("assets", {}) if welcome.get("assets") is Dictionary else {}
	print("[Rift] welcomed; skin=%s, animations offered=%s" % [
		str(assets.get("skin", "?")), str((assets.get("animations", {}) as Dictionary).keys())])
	_set_status("Rift open: charging ...", false)
	_load_body(assets)


func _process(delta: float) -> void:
	match _phase:
		Phase.CHARGING:
			_charge_t += delta
			_animate_charge()
			if _link_ready and _charge_t >= charge_seconds and _assets_state != "loading":
				_arrive()
		Phase.OPEN:
			_open_t += delta
			_pulse += delta
			_beam_mat.albedo_color.a = 0.28 + 0.1 * sin(_pulse * 2.4)
	if _body == null or _phase != Phase.OPEN or not _link.is_open():
		return
	if _greet_cooldown > 0.0:
		_greet_cooldown -= delta
	_state_clock += delta
	if _state_clock >= STATE_INTERVAL:
		_state_clock = 0.0
		_link.send_frame(_state_frame())
		_check_player()


func _animate_charge() -> void:
	var k := clampf(_charge_t / charge_seconds, 0.0, 1.0)
	# The beam fattens and the lamp flickers faster as it climbs.
	_beam.scale = Vector3(0.3 + 0.7 * k, 1.0, 0.3 + 0.7 * k)
	var flicker := 0.5 + 0.5 * sin(_charge_t * (10.0 + 40.0 * k))
	_beam_mat.albedo_color.a = 0.12 + 0.3 * k * (0.6 + 0.4 * flicker)
	_light_mat.emission_energy_multiplier = 0.8 + 2.4 * k * (0.7 + 0.3 * flicker)


func _arrive() -> void:
	_set_phase(Phase.ARRIVING)
	_stop(_hum)
	_play(_sfx, "arrive")
	_set_status("Synth is arriving ...", false)
	_screen_text("ARRIVING")
	_flash()
	if not _spawn_body():
		_abort("no_body", true)
		return
	_body.world_lookup = Callable(self, "_lookup_entity")
	_body.set_fetcher(_fetcher)
	if _puppet != null and _assets_state == "ready":
		_body.set_karada_state(_karada_state)
		_body.attach_puppet(_puppet)
		_puppet = null
	elif _assets_state == "failed":
		print("[Rift] her own body could not be loaded: she arrives as a capsule")
	# Intangible and half there until she is actually out of the pod.
	_body.set_ethereal(true)
	_body.hide_until_summoned()
	await _body.appear(0.7)
	if not _still_arriving():
		return
	# Step out of the capsule, to its front, and turn to the player.
	var out := _floor_below(global_position + (global_basis.z * STEP_OUT))
	await _body.act("move", {"x": out.x, "y": out.y, "z": out.z})
	if not _still_arriving():
		return
	# Out of the pod: only now does she become solid.
	_flash()
	await _body.materialise(0.5)
	if not _still_arriving():
		return
	await _body.act("look", {"target": "player"})
	if not _still_arriving():
		return
	_body.play_once("greet")
	_open_t = 0.0
	_pulse = 0.0
	_beam.scale = Vector3.ONE
	_set_phase(Phase.OPEN)
	_set_status("Open: Synth is in the room. Point at her and press Tab to talk.", true)
	_screen_text("ONLINE")
	_tell_synth_she_was_summoned()


## Synth's Karada: what her avatar is doing, and what she says aloud.
func _on_karada(kind: String, payload: Dictionary) -> void:
	if kind == "animation":
		_karada_state = str(payload.get("state", "idle"))
	if _body != null and is_instance_valid(_body):
		_body.on_karada(kind, payload)


## The player wrote to her through the chat page.
func _on_player_wrote(text: String) -> void:
	if _link == null or not _link.is_open():
		return
	_link.send_frame(Protocol.event("chat", "%s: %s" % [PLAYER_NAME, text], PLAYER_NAME, 1.0,
		{"message": text, "addressed": true}))
	print("[Rift] the player wrote: %s" % text)


func _still_arriving() -> bool:
	return _phase == Phase.ARRIVING and _body != null and is_instance_valid(_body) and _link.is_open()


## What Synth reads: that she was summoned, and what is in front of her. The state frame
## goes first so the world state her turn is built from already has the room in it.
func _tell_synth_she_was_summoned() -> void:
	var placed := _placed_entities()
	_link.send_frame(Protocol.state(_body.global_position, "", {"entities": _json_entities(placed)}))
	var text := SummonerView.summoned_text(_room_id(), placed)
	print("[Rift] telling Synth: %s" % text)
	_link.send_frame(Protocol.event("summoned", text, "", 1.0,
		{"room": _room_id(), "seen": _json_entities(placed)}))


## Send her back: she steps into the capsule and dissolves, the rift closes.
func _dismiss() -> void:
	if _phase == Phase.LEAVING:
		return
	_set_phase(Phase.LEAVING)
	_set_status("Sending Synth back ...", false)
	_screen_text("LEAVING")
	_play(_sfx, "leave")
	if _body != null and is_instance_valid(_body):
		_body.set_ethereal(true)   # into the pod: it is not shoved aside on the way in
		var home := _floor_below(global_position)
		await _body.act("move", {"x": home.x, "y": home.y, "z": home.z})
		if _body != null and is_instance_valid(_body):
			await _body.disappear(0.5)
	_flash()
	_close("switched_off")


## Shut the rift and put everything away.
func _close(reason: String) -> void:
	_link.close_rift(reason)
	_remove_body()
	_free_fetcher()
	_stop(_hum)
	_set_phase(Phase.IDLE)
	_set_status("Off" if reason == "switched_off" else _reason_text(reason), false)
	_show_idle()


## The rift failed, or was called off, before or during the arrival.
func _abort(reason: String, with_sound: bool) -> void:
	print("[Rift] summon ended: %s" % reason)
	_link.close_rift(reason)
	_remove_body()
	_free_fetcher()
	_stop(_hum)
	_stop(_sfx)
	if with_sound:
		_play(_sfx, "fizzle")
	_set_phase(Phase.IDLE)
	_set_status("Off" if reason == "switched_off" else _reason_text(reason), false)
	_show_idle()
	if reason != "switched_off":
		_screen_text("FAILED")


func _on_closed(reason: String) -> void:
	print("[Rift] rift closed: %s" % reason)
	# Our own close_rift also lands here; by then we are IDLE and have said everything.
	if _phase == Phase.IDLE:
		return
	_remove_body()
	_free_fetcher()
	_stop(_hum)
	_stop(_sfx)
	_play(_sfx, "fizzle")
	_set_phase(Phase.IDLE)
	_set_status(_reason_text(reason), false)
	_show_idle()
	_screen_text("FAILED")


## What the player is told when the rift shuts, in words rather than codes.
static func _reason_text(reason: String) -> String:
	if reason == "switched_off":
		return "Off"
	if reason.begins_with("refused:"):
		var code := reason.substr(8)
		match code:
			"busy": return "Refused: a rift is already open"
			"connect_failed": return "Refused: is the RetroXR Vessel plugin on in Synth?"
			"protocol": return "Refused: Synth speaks another protocol version"
		return "Refused by Synth (%s)" % code
	match reason:
		"refused": return "Could not reach Synth: is it running at that address and port? (a password is only needed if its WebUI has one)"
		"connect_timeout": return "No answer from the server"
		"welcome_timeout": return "The server did not welcome us"
		"server_closed": return "Synth left the room"
		"no_server": return "Set a server address in this menu"
		"connect_failed": return "Could not connect"
		"no_body": return "Could not place Synth in the room"
	return "Closed (%s)" % reason


func _on_action(id: int, action: String, payload: Dictionary) -> void:
	await RiftDispatch.handle(_body, _link, id, action, payload)


# ── her real body ────────────────────────────────────────────────────────────

## Fetch her skin from the server (the model, then every animation the server named) while the
## pod charges, and build the puppet. The capsule stays her body if any of it fails.
func _load_body(assets: Dictionary) -> void:
	_assets_state = "loading"
	var model: Dictionary = assets.get("model", {}) if assets.get("model") is Dictionary else {}
	var model_url := str(model.get("url", ""))
	if model_url.is_empty() or _fetcher == null:
		print("[Rift] the server named no model for her: capsule")
		_assets_state = "failed"
		return
	var fetcher := _fetcher
	_set_status("Rift open: loading Synth's body ...", false)
	var vrm: PackedByteArray = await fetcher.call("get_bytes", model_url)
	if not _loading_still_wanted(fetcher):
		return
	var puppet: Node3D = KaradaPuppet.new()
	puppet.visible = false
	add_child(puppet)
	if vrm.is_empty() or not bool(puppet.call("load_model", vrm)):
		puppet.queue_free()
		_assets_state = "failed"
		return
	var anims: Dictionary = assets.get("animations", {}) if assets.get("animations") is Dictionary else {}
	for clip_name: String in anims:
		var entry: Variant = anims[clip_name]
		var clips: Array = (entry as Dictionary).get("clips", []) if entry is Dictionary else []
		var urls := _own_clips(clip_name, clips)
		var names: Array = []
		for i in urls.size():
			var bytes: PackedByteArray = await fetcher.call("get_bytes", urls[i])
			if not _loading_still_wanted(fetcher, puppet):
				return
			var variant := "%s__%d" % [clip_name, i]
			if not bytes.is_empty() and bool(puppet.call("add_clip", variant, bytes)):
				names.append(variant)
		if names.is_empty():
			continue
		if names.size() > 1 and clip_name == "idle":
			# A skin can ship a standing clip that stands badly (Rei's Idle arches her back): of the
			# standing ones keep the most upright. Not for the others: how upright a gesture or a
			# typing pose is says nothing about it.
			await puppet.call("choose_most_upright", clip_name, names)
		else:
			puppet.call("alias_clip", clip_name, names[0])
	_puppet = puppet
	_assets_state = "ready"
	print("[Rift] her body is ready: %d bones mapped, clips: %s" % [int(puppet.call("mapped_bones")), str(anims.keys())])
	_set_status("Rift open: charging ...", false)


## The clips that ARE `state`: the files directly in its folder (`animations/idle/Idle.fbx`), not the
## variants filed under it (`animations/idle/happy/Happy.fbx` is a mood, not standing). At most four.
func _own_clips(state: String, clips: Array) -> Array:
	var own: Array = []
	var any: Array = []
	for c: Variant in clips:
		if not (c is Dictionary):
			continue
		var url := str((c as Dictionary).get("url", ""))
		if url.is_empty():
			continue
		any.append(url)
		if url.get_base_dir().get_file() == state:
			own.append(url)
	if own.is_empty() and not any.is_empty():
		own = [any[0]]
	return own.slice(0, 4)


## False (and everything put away) when the summon was called off while a download ran.
func _loading_still_wanted(fetcher: Node, puppet: Node = null) -> bool:
	if _phase == Phase.CHARGING or _phase == Phase.ARRIVING:
		return true
	print("[Rift] summon ended while her body was loading: dropped")
	if puppet != null and is_instance_valid(puppet):
		puppet.queue_free()
	_assets_state = ""
	return false


# ── the body ─────────────────────────────────────────────────────────────────

func _spawn_body() -> bool:
	# Not her loaded body: that is what this is about to be put on.
	_remove_body(false)
	var host: Node = get_parent()
	if host == null:
		print("[Rift] summoner has no parent to put the body in")
		return false
	# The floor is measured BEFORE the body exists: a body added at the origin first is
	# a collider the ray stops on (it found her head and stood her at 1.55 m).
	var floor_spot := _floor_below(global_position)
	_body = SynthBody.new()
	_body.name = "SynthBody"
	_body.chat_sent.connect(_on_player_wrote)
	_body.anchor = global_position
	host.add_child(_body)
	# Inside the pod, facing out of its front.
	_body.global_position = floor_spot
	# The pod's front is +Z and a body faces its own -Z.
	_body.global_rotation.y = global_rotation.y + PI
	print("[Rift] body at %s" % str(_body.global_position))
	return true


func _remove_body(and_puppet: bool = true) -> void:
	if _body != null and is_instance_valid(_body):
		_body.queue_free()
	_body = null
	if and_puppet:
		_free_puppet()


func _free_fetcher() -> void:
	if _fetcher != null and is_instance_valid(_fetcher):
		_fetcher.queue_free()
	_fetcher = null


func _free_puppet() -> void:
	if _puppet != null and is_instance_valid(_puppet):
		_puppet.queue_free()
	_puppet = null


## The floor under `point` (the first collider straight down), or `point` if none.
func _floor_below(point: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.5, point + Vector3.DOWN * 3.0)
	query.exclude = [get_rid()]
	# Not the pointer boxes (layer 21): they are stood over every object for the laser, and
	# the first build put the body on top of the capsule's own.
	query.collision_mask = 0xFFFFFFFF & ~(1 << 20)
	var hit := space.intersect_ray(query)
	return (hit["position"] as Vector3) if hit.has("position") else point


# ── what she sees ────────────────────────────────────────────────────────────

## Everything she could be told about, in world space: the room's spawned objects and
## the player. The player has no model, so their head is the camera.
func _entities() -> Array:
	var found: Array = []
	for node: Node in get_tree().get_nodes_in_group("spawned"):
		var n3 := node as Node3D
		if n3 == null or n3 == self or n3 == _body:
			continue
		var entry: Dictionary = {"name": str(n3.name), "type": n3.get_class(), "position": n3.global_position}
		var script: Script = n3.get_script()
		if script != null and not script.get_global_name().is_empty():
			entry["type"] = str(script.get_global_name())
		var label: Variant = n3.get("display_name")
		var shown := str(label) if label is String and not String(label).is_empty() else str(n3.name)
		entry["label"] = shown.substr(0, shown.find("@")) if shown.contains("@") else shown
		if n3.has_method("is_powered_on"):
			entry["powered"] = bool(n3.call("is_powered_on"))
		var sid: Variant = n3.get("systemid")
		if sid is String and not String(sid).is_empty():
			entry["systemid"] = sid
		found.append(entry)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		found.append({"name": "player", "type": "player", "label": "the player", "position": cam.global_position})
	return found


## The nearest thing in the room that `query` names (its node name or the label she is told), or {}.
## Exact names win over partial ones.
func _lookup_entity(query: String) -> Dictionary:
	var q := query.strip_edges().to_lower()
	if q.is_empty() or _body == null or not is_instance_valid(_body):
		return {}
	var exact: Array = []
	var partial: Array = []
	for e: Dictionary in _entities():
		if str(e.get("type", "")) == "player":
			continue
		var name_l := str(e.get("name", "")).to_lower()
		var label_l := str(e.get("label", "")).to_lower()
		if q == name_l or q == label_l:
			exact.append(e)
		elif name_l.contains(q) or label_l.contains(q):
			partial.append(e)
	var pool: Array = exact if not exact.is_empty() else partial
	var best: Dictionary = {}
	var best_d := INF
	for e: Dictionary in pool:
		var d: float = (e["position"] as Vector3).distance_to(_body.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


## `_entities()` seen from the body: bearing, distance and side, nearest first.
func _placed_entities() -> Array:
	if _body == null or not is_instance_valid(_body):
		return []
	return SummonerView.place(_entities(), _body.global_position, -_body.global_basis.z)


## The same, as something a JSON frame can carry.
func _json_entities(placed: Array) -> Array:
	var out: Array = []
	for e: Dictionary in placed.slice(0, MAX_ENTITIES):
		var j: Dictionary = e.duplicate()
		j["position"] = Protocol.vec(e["position"])
		out.append(j)
	return out


func _state_frame() -> Dictionary:
	return Protocol.state(_body.global_position, "", {"entities": _json_entities(_placed_entities())})


func _check_player() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var near := cam.global_position.distance_to(_body.global_position) < GREET_DISTANCE
	if near and not _player_near and _greet_cooldown <= 0.0:
		_greet_cooldown = GREET_REARM_SECONDS
		_link.send_frame(Protocol.event("proximity", "The player walked up to you.", "player", 0.6))
	_player_near = near


func _room_id() -> String:
	var scene := get_tree().current_scene
	return str(scene.name).to_lower() if scene != null else "room"


# ── lamp, screen, sound ──────────────────────────────────────────────────────

func status_text() -> String:
	return _status


func status_ok() -> bool:
	return _status_ok


func _set_status(text: String, ok: bool) -> void:
	_status = text
	_status_ok = ok
	status_changed.emit()


func _set_phase(p: Phase) -> void:
	_phase = p
	phase_changed.emit(int(p))


func _build_light() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 1.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for node: Variant in _lamp_nodes:
		(node as MeshInstance3D).material_override = mat
	return mat


func _set_light(color: Color) -> void:
	_light_mat.albedo_color = color
	_light_mat.emission = color
	_beam_mat.albedo_color = Color(color.r, color.g, color.b, _beam_mat.albedo_color.a)


## Idle: the screen and the inside are red and the beam is off.
func _show_idle() -> void:
	_set_light(LIGHT_OFF)
	_light_mat.emission_energy_multiplier = 1.0
	_screen_mat.albedo_color = LIGHT_OFF
	_screen_text("SUMMON")
	_beam.visible = false
	_beam.scale = Vector3.ONE


func _show_charging() -> void:
	_set_light(LIGHT_CYAN)
	_screen_mat.albedo_color = LIGHT_CYAN
	_screen_text("LINKING")
	_beam.visible = true
	_beam.scale = Vector3(0.3, 1.0, 0.3)
	_beam_mat.albedo_color.a = 0.12


func _screen_text(text: String) -> void:
	_screen_label.text = text


## The burst when she arrives or leaves: the lamp is thrown bright and settles.
func _flash() -> void:
	_light_mat.emission_energy_multiplier = 8.0
	var tw := create_tween()
	tw.tween_property(_light_mat, "emission_energy_multiplier", 1.6, 0.6)


func _play(player: AudioStreamPlayer3D, sound: String) -> void:
	player.stream = SummonerSounds.stream(sound)
	player.play()


func _stop(player: AudioStreamPlayer3D) -> void:
	if player != null:
		player.stop()
