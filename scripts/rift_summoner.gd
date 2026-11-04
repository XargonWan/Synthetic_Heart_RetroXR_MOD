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
##   OPEN      Synth is told they were summoned and what they see in front of them, the
##             player included (a player model does not exist: their head is the
##             camera). Touching the screen again, or the menu button, sends them back.
##   LEAVING   they step back in, dissolves, the rift closes, the screen goes red.
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
const WorldView := preload("res://mods/xenu.synth_rift/scripts/world_view.gd")
const AssetFetcher := preload("res://mods/xenu.synth_rift/scripts/asset_fetcher.gd")
const KaradaPuppet := preload("res://mods/xenu.synth_rift/scripts/karada_puppet.gd")
const RiftDispatch := preload("res://mods/xenu.synth_rift/scripts/rift_dispatch.gd")
const ChatStore := preload("res://mods/xenu.synth_rift/scripts/chat_store.gd")

## What Synth calls the player: they have no profile in a room.
const PLAYER_NAME := "player"
const MOD_VERSION := "0.13.0"
const STATE_INTERVAL := 1.0
## At most this many changes in the room are told per look, and how much they matter to them.
## A thing that stops existing is told as gone only after this long: it may only have been moved.
const GONE_DELAY_SECONDS := 20.0
const MAX_SIGHTINGS := 3
const SIGHTING_SALIENCE := 0.45
## How far the body may be from this, and how far it looks for things to tell Synth about.
const SENSE_RADIUS := 6.0
const MAX_ENTITIES := 20
## How much a finished routine matters to the model: it asked for it, so it wants to know.
const ROUTINE_SALIENCE := 0.9
const PICTURE_W := 640
const PICTURE_H := 480
## The player this close for the first time is worth telling Synth.
const GREET_DISTANCE := 2.0
const GREET_REARM_SECONDS := 60.0
## How far in front of the capsule they step out to.
const STEP_OUT := 1.3
## A touch on the screen sends them back only this long after they arrived: a hand that
## is still over the screen from summoning them must not dismiss them.
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
## The session Synth welcomed this process with, kept ACROSS rooms (a Summoner is freed with its room): the next one's
## hello names it, and Synth, which kept the session through its disconnect grace, carries on the same conversation.
## "" after a goodbye (the player sent them back), which ends the session for good.
static var _resume_session := ""
static var _resume_room := ""
## This summon picked a session up, and the room it was in before.
var _resumed := false
var _resumed_from := ""
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
## Their real body, fetched from the server while the pod charges: "" not yet, "loading", "ready", "failed".
var _assets_state := ""
var _fetcher: Node = null
var _karada_state := "idle"
var _skin_loading := false
## Karada's presence as last told ("summon" while the vessel introduces them), kept for a body that is not there yet.
var _presence := ""
## The ids of what they have SEEN since they stepped out: what they can name (see _lookup_entity).
var _seen_ids: Dictionary = {}
var _room_memory: Dictionary = {}
var _room_seen := false
var _skin_again: Dictionary = {}
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
	_link.transcript_received.connect(_on_transcript)
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


## True from the touch until they have left again.
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
		Protocol.WANTED_ANIMATIONS, MOD_VERSION, _resume_session)
	print("[Rift] summoning (room=%s%s)" % [_room_id(), ", asking to resume session %s" % _resume_session if _resume_session != "" else ""])
	_charge_t = 0.0
	_link_ready = false
	_assets_state = ""
	_free_puppet()
	_free_fetcher()
	_fetcher = AssetFetcher.new()
	_fetcher.name = "AssetFetcher"
	add_child(_fetcher)
	_fetcher.call("setup", server, str(settings.get("token", "")))
	_fetcher.connect("progress", _on_download_progress)
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


## A big file (their model) is on its way: say how far, on the menu and on the pod's screen.
func _on_download_progress(url_path: String, got: int, total: int) -> void:
	if total < 1_000_000 or _phase != Phase.CHARGING:
		return
	var pct := int(100.0 * float(got) / float(total))
	_set_status("Rift open: loading Synth's body ... %d%% (%.0f of %.0f MB)" % [pct, got / 1048576.0, total / 1048576.0], false)
	if pct % 5 == 0:
		_screen_text("BODY %d%%" % pct)


func _on_opened(welcome: Dictionary) -> void:
	_link_ready = true
	_resumed = bool(welcome.get("resumed", false))
	_resumed_from = _resume_room if _resumed else ""
	var sid := str(welcome.get("session", ""))
	if sid != "":
		_resume_session = sid
		_resume_room = _room_id()
	print("[Rift] session %s%s" % [sid, (" RESUMED (from room '%s'): the conversation goes on" % _resumed_from) if _resumed else " (new)"])
	if RiftSettings.forget_pending():
		_link.send_frame({"type": "forget"})
		RiftSettings.set_forget_pending(false)
		print("[Rift] the chat was forgotten while the rift was shut: Synth is told now")
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
		_watch_room()


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
	_body.sight = Callable(self, "_placed_entities")
	_body.picture_taker = Callable(self, "_take_picture")
	_body.routine_done.connect(_on_routine_done)
	_body.set_fetcher(_fetcher)
	_body.set_karada_state(_karada_state)
	_body.set_presence(_presence)
	if _puppet != null and _assets_state == "ready":
		_body.attach_puppet(_puppet)
		_puppet = null
	elif _assets_state == "failed":
		print("[Rift] their own body could not be loaded: they arrive as a capsule")
	# Intangible and half there until they are actually out of the pod.
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
	# Out of the pod: only now does they become solid.
	_flash()
	await _body.materialise(0.5)
	if not _still_arriving():
		return
	await _body.act("look", {"target": "player"})
	if not _still_arriving():
		return
	if not _resumed:
		_body.play_once("greet")   # the same conversation going on is not greeted again
	_open_t = 0.0
	_pulse = 0.0
	_beam.scale = Vector3.ONE
	_set_phase(Phase.OPEN)
	_set_status("Open: Synth is in the room. Point at them and press Tab to talk.", true)
	_screen_text("ONLINE")
	_tell_synth_she_was_summoned()


## Synth's Karada: what their avatar is doing, and what they say aloud.
func _on_karada(kind: String, payload: Dictionary) -> void:
	if kind == "animation":
		_karada_state = str(payload.get("state", "idle"))
	if kind == "presence":
		_presence = str(payload.get("state", ""))
	if kind == "model":
		_change_skin(payload)
		return
	if _body != null and is_instance_valid(_body):
		_body.on_karada(kind, payload)


## The player changed their skin (the WebUI's model picker): fetch the new body and put them in it.
## The server's description of the body is asked for again, so their clips come from the new skin too.
func _change_skin(payload: Dictionary) -> void:
	if _phase != Phase.OPEN or _body == null or not is_instance_valid(_body) or _fetcher == null:
		print("[Rift] the skin changed (%s) while they are not out: it is fetched at the next summon" % str(payload.get("name", "")))
		return
	if _skin_loading:
		_skin_again = payload
		return
	_skin_loading = true
	print("[Rift] their skin changed to %s: fetching it" % str(payload.get("name", payload.get("url", ""))))
	_link.send_frame(Protocol.request_assets(Protocol.WANTED_ANIMATIONS))
	var assets: Dictionary = await _link.assets_received
	var fetcher := _fetcher
	var puppet: Node3D = await _build_puppet(assets, fetcher, func() -> bool:
		return _phase == Phase.OPEN and _body != null and is_instance_valid(_body))
	_skin_loading = false
	if puppet != null and _phase == Phase.OPEN and _body != null and is_instance_valid(_body):
		_body.swap_puppet(puppet)
		print("[Rift] they wear their new skin")
	elif puppet != null:
		puppet.queue_free()
	if not _skin_again.is_empty():
		var next := _skin_again
		_skin_again = {}
		_change_skin(next)


## The player wrote to them through the chat page.
func _on_player_wrote(text: String) -> void:
	if _link == null or not _link.is_open():
		return
	_link.send_frame(Protocol.event("chat", "%s: %s" % [PLAYER_NAME, text], PLAYER_NAME, 1.0,
		{"message": text, "addressed": true}))
	print("[Rift] the player wrote: %s" % text)


var _clip_ids := 0


## The player spoke to them (the mic of the chat page): the clip goes to Synth, who hears it with their own ears
## (Auris) and answers with the words; they then reach them as a chat line, exactly like typed ones.
func _on_player_spoke(wav: PackedByteArray) -> void:
	if _link == null or not _link.is_open():
		_body.heard(false, "", "stt_failed")
		return
	_clip_ids += 1
	_link.send_frame(Protocol.audio(_clip_ids, wav, PLAYER_NAME))
	print("[Rift] the player spoke: clip %d, %d bytes" % [_clip_ids, wav.size()])


func _on_transcript(id: int, ok: bool, text: String, reason: String) -> void:
	print("[Rift] clip %d heard: ok=%s %s" % [id, str(ok), text if ok else reason])
	if _body != null and is_instance_valid(_body):
		_body.heard(ok, text, reason)


func _still_arriving() -> bool:
	return _phase == Phase.ARRIVING and _body != null and is_instance_valid(_body) and _link.is_open()


## What Synth reads: that they were summoned, and what is in front of them. The state frame
## goes first so the world state their turn is built from already has the room in it.
func _tell_synth_she_was_summoned() -> void:
	var placed := _placed_entities()
	# What they saw on arrival is the baseline: only what changes from here is news.
	_room_memory.clear()
	_seen_ids.clear()
	_room_seen = false
	SummonerView.room_changes(_room_memory, placed, true)
	_room_seen = true
	_link.send_frame(Protocol.state(_body.global_position, "", {"entities": _json_entities(placed)}))
	var text := SummonerView.summoned_text(_room_id(), placed, {"from_room": _resumed_from} if _resumed else {})
	print("[Rift] telling Synth: %s" % text)
	_link.send_frame(Protocol.event("summoned", text, "", 1.0,
		{"room": _room_id(), "seen": _json_entities(placed), "resumed": _resumed}))


## Send them back: they step into the capsule and dissolve, the rift closes.
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


## The room is going away with this pod: the socket drops WITHOUT a goodbye, so Synth keeps the session for its grace
## window and the next Summoner (in the next room) can pick it up with `hello.resume`.
func _exit_tree() -> void:
	if _link != null and is_instance_valid(_link) and _link.is_open():
		print("[Rift] the room is closing with the rift open: leaving without a goodbye (session %s can be resumed)" % _resume_session)
		_link.close_rift("room_change", false)


## The pod's menu: forget the chat. The saved log and the body's go at once; Synth is told now when the rift is open,
## else the moment it next opens. True when it was told at once.
func forget_chat() -> bool:
	ChatStore.clear()
	if _body != null and is_instance_valid(_body):
		_body.forget_chat()
	if _link != null and _link.is_open():
		_link.send_frame({"type": "forget"})
		RiftSettings.set_forget_pending(false)
		print("[Rift] the player asked to forget the chat: Synth is told")
		return true
	RiftSettings.set_forget_pending(true)
	print("[Rift] the player asked to forget the chat while the rift is shut: Synth is told when it opens")
	return false


## Shut the rift and put everything away.
func _close(reason: String) -> void:
	# The player sent them back: a goodbye, so Synth ends the session instead of waiting for it to come back.
	_resume_session = ""
	_link.close_rift(reason, true)
	_remove_body()
	_free_fetcher()
	_stop(_hum)
	_set_phase(Phase.IDLE)
	_set_status("Off" if reason == "switched_off" else _reason_text(reason), false)
	_show_idle()


## The rift failed, or was called off, before or during the arrival.
func _abort(reason: String, with_sound: bool) -> void:
	print("[Rift] summon ended: %s" % reason)
	_resume_session = ""
	_link.close_rift(reason, true)
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


# ── their real body ────────────────────────────────────────────────────────────

## Fetch their skin from the server (the model, then every animation the server named) while the
## pod charges, and build the puppet. The capsule stays their body if any of it fails.
func _load_body(assets: Dictionary) -> void:
	_assets_state = "loading"
	_set_status("Rift open: loading Synth's body ...", false)
	var fetcher := _fetcher
	var puppet: Node3D = await _build_puppet(assets, fetcher, func() -> bool: return _loading_still_wanted(fetcher))
	if puppet == null:
		if _assets_state == "loading":
			_assets_state = "failed"
		return
	_puppet = puppet
	_assets_state = "ready"
	print("[Rift] their body is ready: %d bones mapped, clips: %s" % [int(puppet.call("mapped_bones")), str((assets.get("animations", {}) as Dictionary).keys())])
	_set_status("Rift open: charging ...", false)


## Their body from what the server described (`assets`): the model, their persona's face map and every
## clip it named. null when it could not be built or `still_wanted` said to stop.
func _build_puppet(assets: Dictionary, fetcher: Node, still_wanted: Callable) -> Node3D:
	var model: Dictionary = assets.get("model", {}) if assets.get("model") is Dictionary else {}
	var model_url := str(model.get("url", ""))
	if model_url.is_empty() or fetcher == null:
		print("[Rift] the server named no model for them: capsule")
		return null
	var vrm: PackedByteArray = await fetcher.call("get_bytes", model_url)
	if not bool(still_wanted.call()):
		return null
	var puppet: Node3D = KaradaPuppet.new()
	puppet.visible = false
	add_child(puppet)
	if vrm.is_empty() or not bool(puppet.call("load_model", vrm)):
		puppet.queue_free()
		return null
	# Which expression each logical face name is: their skin's persona, next to the model.
	var persona: Variant = null
	for persona_url: String in Protocol.persona_urls(assets, model_url):
		var persona_bytes: PackedByteArray = await fetcher.call("get_fresh", persona_url)
		if not bool(still_wanted.call()):
			puppet.queue_free()
			return null
		persona = JSON.parse_string(persona_bytes.get_string_from_utf8()) if not persona_bytes.is_empty() else null
		if persona is Dictionary:
			print("[Rift] their persona.json: %s" % persona_url)
			break
	if persona is Dictionary:
		puppet.call("set_persona", persona)
	else:
		print("[Rift] their persona.json did not come: their face takes names as they are")
	var anims: Dictionary = assets.get("animations", {}) if assets.get("animations") is Dictionary else {}
	for clip_name: String in anims:
		var entry: Variant = anims[clip_name]
		var clips: Array = (entry as Dictionary).get("clips", []) if entry is Dictionary else []
		var picks := _own_clips(clip_name, clips)
		var loops: Array = []
		var posts: Array = []
		for i in picks.size():
			var bytes: PackedByteArray = await fetcher.call("get_bytes", picks[i]["url"])
			if not bool(still_wanted.call()):
				puppet.queue_free()
				return null
			var variant := "%s__%d" % [clip_name, i]
			if bytes.is_empty() or not bool(puppet.call("add_clip", variant, bytes)):
				continue
			var descriptor: Dictionary = picks[i]["descriptor"]
			puppet.call("set_clip_descriptor", variant, descriptor)
			# A clip that plays once beside others that loop is how the state ENDS (a crouch's "stand up").
			(posts if bool(descriptor.get("play_once", false)) else loops).append(variant)
		if loops.is_empty() and posts.is_empty():
			continue
		if loops.size() > 1 and clip_name == "idle":
			# A skin can ship a standing clip that stands badly (Rei's Idle arches them back): of the
			# standing ones keep the most upright. Not for the others: how upright a gesture or a
			# typing pose is says nothing about it.
			await puppet.call("choose_most_upright", clip_name, loops)
		elif not loops.is_empty():
			puppet.call("alias_clip", clip_name, loops[0])
			if not posts.is_empty():
				puppet.call("alias_clip", clip_name + "_post", posts[0])
		else:
			puppet.call("alias_clip", clip_name, posts[0])
	# Drawn once, off screen, before anybody is shown them: it is what keeps them from arriving in pieces.
	await puppet.call("warm")
	if not bool(still_wanted.call()):
		puppet.queue_free()
		return null
	return puppet


## The clips that ARE `state`: the files directly in its folder (`animations/idle/Idle.fbx`), not the
## variants filed under it (`animations/idle/happy/Happy.fbx` is a mood, not standing; `animations/sit/bed/`
## is for a bed, not a chair). At most four, each as {url, descriptor} (the descriptor is {} when it has none).
func _own_clips(state: String, clips: Array) -> Array:
	var own: Array = []
	var any: Array = []
	for c: Variant in clips:
		if not (c is Dictionary):
			continue
		var url := str((c as Dictionary).get("url", ""))
		if url.is_empty():
			continue
		var descriptor: Variant = (c as Dictionary).get("descriptor", {})
		var entry := {"url": url, "descriptor": descriptor if descriptor is Dictionary else {}}
		any.append(entry)
		if url.get_base_dir().get_file() == state:
			own.append(entry)
	if own.is_empty() and not any.is_empty():
		own = [any[0]]
	return own.slice(0, 4)


## False (and everything put away) when the summon was called off while a download ran.
func _loading_still_wanted(fetcher: Node, puppet: Node = null) -> bool:
	if _phase == Phase.CHARGING or _phase == Phase.ARRIVING:
		return true
	print("[Rift] summon ended while their body was loading: dropped")
	if puppet != null and is_instance_valid(puppet):
		puppet.queue_free()
	_assets_state = ""
	return false


# ── the body ─────────────────────────────────────────────────────────────────

func _spawn_body() -> bool:
	# Not their loaded body: that is what this is about to be put on.
	_remove_body(false)
	var host: Node = get_parent()
	if host == null:
		print("[Rift] summoner has no parent to put the body in")
		return false
	# The floor is measured BEFORE the body exists: a body added at the origin first is
	# a collider the ray stops on (it found their head and stood them at 1.55 m).
	var floor_spot := _floor_below(global_position)
	_body = SynthBody.new()
	_body.name = "SynthBody"
	_body.chat_sent.connect(_on_player_wrote)
	_body.voice_clip.connect(_on_player_spoke)
	_body.anchor = global_position
	_body.persist_chat = true
	host.add_child(_body)
	_body.load_chat()
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


# ── what they see ────────────────────────────────────────────────────────────

## Everything in the room, in world space: the spawned objects and the player (no model: their head is the camera).
## Each has a `name` a person could say (WorldView: "Game Boy Color", "VHS tape 2", "unknown item" -- never the node's
## engine name, never empty), its `type` as a person would put it, and the node's own name as `id`.
func _entities() -> Array:
	var found: Array = []
	for node: Node in get_tree().get_nodes_in_group("spawned"):
		var n3 := node as Node3D
		if n3 == null or n3 == self or n3 == _body:
			continue
		var type_name := n3.get_class()
		var script: Script = n3.get_script()
		if script != null and not script.get_global_name().is_empty():
			type_name = str(script.get_global_name())
		var display: Variant = n3.get("display_name")
		var title: Variant = n3.get("game_label")
		var machine := ""
		var sid: Variant = n3.get("systemid")
		if type_name == "RetroSystem" and n3.has_method("display_name_for_toast"):
			machine = str(n3.call("display_name_for_toast"))
		var entry: Dictionary = {"id": str(n3.name), "id_num": n3.get_instance_id(), "type": WorldView.kind_of(type_name),
			"position": n3.global_position, "node": n3,
			"raw": {"node": str(n3.name), "type": type_name, "display": str(display) if display is String else "",
				"title": str(title) if title is String else "", "machine": machine}}
		if str(entry["type"]).is_empty():
			entry["type"] = WorldView.UNKNOWN
		if n3.has_method("is_powered_on"):
			entry["powered"] = bool(n3.call("is_powered_on"))
		elif n3.has_method("is_on"):
			entry["powered"] = bool(n3.call("is_on"))
		if sid is String and not String(sid).is_empty():
			entry["systemid"] = sid
		if str(title) != "" and title is String:
			entry["title"] = title
		if n3.has_method("is_picked_up") and bool(n3.call("is_picked_up")):
			entry["held"] = true
		found.append(entry)
	WorldView.name_all(found)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		found.append({"id": "player", "id_num": 0, "name": "player", "type": "player", "label": "the player", "position": cam.global_position})
	return found


## The thing the player or Synth means by `query`, among what they have SEEN (so a name they were never told does not
## work: they have to look for it), nearest of the best matches; {} when none. Exact names win over parts of one.
func _lookup_entity(query: String) -> Dictionary:
	if query.strip_edges().is_empty() or _body == null or not is_instance_valid(_body):
		return {}
	_placed_entities()  # what is in front of their right now counts as seen, even before the next state frame
	var best: Dictionary = {}
	var best_score := 0
	var best_d := INF
	for e: Dictionary in _entities():
		if str(e.get("type", "")) == "player" or not _seen_ids.has(str(e.get("id", ""))):
			continue
		var score := WorldView.matches(e, query)
		if score == 0:
			continue
		var d: float = (e["position"] as Vector3).distance_to(_body.global_position)
		if score > best_score or (score == best_score and d < best_d):
			best = e
			best_score = score
			best_d = d
	return best


## Can they SEE this point from their eyes? Nothing solid between (the pointer boxes of the laser do not count, and
## neither does the thing itself or what it rests on within 35 cm of it).
func _line_of_sight(to: Vector3, node: Node = null) -> bool:
	if _body == null or not is_instance_valid(_body):
		return false
	var from := _body.global_position + Vector3(0.0, _body.eye_height(), 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 0xFFFFFFFF & ~(1 << 20)
	var exclude: Array[RID] = [_body.get_rid()]
	if node is CollisionObject3D:
		exclude.append((node as CollisionObject3D).get_rid())
	query.exclude = exclude
	var hit := _body.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or (hit["position"] as Vector3).distance_to(to) < 0.35


## `_entities()` as they see them: in front of them (about 180 degrees), within reach of their eyes, not hidden;
## bearing, distance and side, nearest first. What they see is remembered by id (`_seen_ids`): it is what they can name.
func _placed_entities() -> Array:
	if _body == null or not is_instance_valid(_body):
		return []
	var seen: Array = []
	var forward := -_body.global_basis.z
	for e: Dictionary in _entities():
		var pos: Vector3 = e["position"]
		if not WorldView.in_view(_body.global_position, forward, pos):
			continue
		if str(e.get("type", "")) != "player" and not _line_of_sight(pos + Vector3(0, 0.05, 0), e.get("node") as Node):
			continue
		seen.append(e)
	var placed: Array = SummonerView.place(seen, _body.global_position, forward)
	for e: Dictionary in placed:
		_seen_ids[str(e.get("id", ""))] = true
	return placed


## The same, as something a JSON frame can carry.
func _json_entities(placed: Array) -> Array:
	var out: Array = []
	for e: Dictionary in placed.slice(0, MAX_ENTITIES):
		var j: Dictionary = e.duplicate()
		j.erase("node")
		j.erase("raw")
		j.erase("id_num")
		j["position"] = Protocol.vec(e["position"])
		out.append(j)
	return out


func _state_frame() -> Dictionary:
	return Protocol.state(_body.global_position, _body.holding(), {"entities": _json_entities(_placed_entities())})


## What they did on their own is over: Synth is told how it went, as a turn of its own (a search that found the thing,
## or that looked everywhere and did not). A picture their eyes took rides in `data`.
func _on_routine_done(kind: String, ok: bool, summary: String, data: Dictionary) -> void:
	if _link == null:
		return
	data["ok"] = ok
	# This is a RESULT, not a message: without saying so each one made the model answer the player's last line again
	# ("I'll go and look around" after it had looked around) and start the same routine a second time.
	var told := "%s [This is only the result of what you set off. The player's last message was already answered: tell them how it went in a sentence or two, and do not start it again unless they ask.]" % summary
	_link.send_frame(Protocol.event("%s_done" % kind, told, "", ROUTINE_SALIENCE, data))
	_link.send_frame(_state_frame())


## They notice what changes around them: a thing put down or taken away, a machine switched on or off. Told as
## quiet sightings (they are what they may get curious about, never a reason to interrupt anyone).
func _watch_room() -> void:
	var first := _room_memory.is_empty() and not _room_seen
	_room_seen = true
	var existing: Array = []
	for e: Dictionary in _entities():
		existing.append(str(e.get("id", "")))
	var said: Array = SummonerView.room_changes(_room_memory, _placed_entities(), first, existing,
			float(Time.get_ticks_msec()) / 1000.0, GONE_DELAY_SECONDS)
	for line: Variant in said.slice(0, MAX_SIGHTINGS):
		print("[Rift] sighting: %s" % str(line))
		_link.send_frame(Protocol.event("sighting", str(line), "", SIGHTING_SALIENCE))


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


## The burst when they arrive or leave: the lamp is thrown bright and settles.
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


## A picture from their eyes toward `point`: a JPEG, base64, small. Done in a viewport of its own that shares the room's
## world, with a camera at their eyes (nothing is added to what the player sees; the camera sits just ahead of their face,
## so their own head is behind it). Not in a headless run (no renderer to draw it) and not with the pod's "pictures"
## switch off (the picture leaves the room for the server, so it is the player's to forbid).
func _take_picture(point: Vector3) -> Dictionary:
	if not RiftSettings.pictures_on():
		return {"ok": false, "detail": "pictures_off"}
	if DisplayServer.get_name() == "headless" or _body == null or not is_instance_valid(_body):
		return {"ok": false, "detail": "no_renderer"}
	var from := _body.global_position + Vector3(0.0, _body.eye_height(), 0.0)
	var aim := point - from
	if aim.length() < 0.1:
		return {"ok": false, "detail": "too_close"}
	from += aim.normalized() * 0.18
	var viewport := SubViewport.new()
	viewport.size = Vector2i(PICTURE_W, PICTURE_H)
	viewport.world_3d = get_viewport().world_3d
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	var camera := Camera3D.new()
	camera.fov = 75.0
	camera.near = 0.05
	viewport.add_child(camera)
	camera.global_transform = Transform3D(Basis.looking_at(aim.normalized(), Vector3.UP), from)
	camera.current = true
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	if image == null or image.is_empty():
		return {"ok": false, "detail": "no_image"}
	var jpeg := image.save_jpg_to_buffer(0.8)
	print("[Rift] picture taken: %dx%d, %d KB" % [image.get_width(), image.get_height(), jpeg.size() / 1024])
	if OS.get_environment("RIFT_PICTURE_OUT") != "":
		FileAccess.open(OS.get_environment("RIFT_PICTURE_OUT"), FileAccess.WRITE).store_buffer(jpeg)
	return {"ok": true, "jpeg_b64": Marshalls.raw_to_base64(jpeg)}
