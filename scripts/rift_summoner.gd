## RiftSummoner -- the Synthetic Heart Rift Summoner.
##
## A pickable the player carries and puts down. Press its action (trigger while
## held in VR, Shift + click on a desktop) and the rift opens: this connects to the
## Synthetic Heart server, and when Synth says welcome her body appears beside it.
## Press again, or lose the server, and the rift closes and the body goes.
##
## It is OFF whenever a room loads: an open rift is a live connection to somebody's
## server, and that is not something to restore silently.
extends XRToolsPickable

const Protocol := preload("res://mods/xenu.synth_rift/scripts/rift_protocol.gd")
const RiftLink := preload("res://mods/xenu.synth_rift/scripts/rift_link.gd")
const SynthBody := preload("res://mods/xenu.synth_rift/scripts/synth_body.gd")
const RiftDispatch := preload("res://mods/xenu.synth_rift/scripts/rift_dispatch.gd")

const MOD_ID := "xenu.synth_rift"
const MOD_VERSION := "0.1.0"
const SETTINGS_FILE := "user://mods/xenu.synth_rift/settings.json"
const DEFAULT_SERVER := "127.0.0.1:8080"
const STATE_INTERVAL := 1.0
## How far the body may be from this, and how far it looks for things to tell Synth about.
const SENSE_RADIUS := 6.0
const MAX_ENTITIES := 20
## The player this close for the first time is worth telling Synth.
const GREET_DISTANCE := 2.0
const GREET_REARM_SECONDS := 60.0

const LIGHT_OFF := Color(0.9, 0.15, 0.1)
const LIGHT_WAIT := Color(1.0, 0.7, 0.1)
const LIGHT_ON := Color(0.2, 1.0, 0.45)

var _link: Node = null
var _body: CharacterBody3D = null
var _light_mat: StandardMaterial3D = null
var _state_clock := 0.0
var _player_near := false
var _greet_cooldown := 0.0
var _on := false


func _ready() -> void:
	super._ready()
	_light_mat = _build_light()
	_set_light(LIGHT_OFF)
	_link = RiftLink.new()
	_link.name = "RiftLink"
	add_child(_link)
	_link.opened.connect(_on_opened)
	_link.closed.connect(_on_closed)
	_link.action_received.connect(_on_action)
	action_pressed.connect(func(_p: Variant) -> void: toggle())


func toggle() -> void:
	set_on(not _on)


func is_on() -> bool:
	return _on


func set_on(on: bool) -> void:
	if on == _on:
		return
	if on:
		var settings := _settings()
		var url: String = Protocol.socket_url(str(settings.get("server", DEFAULT_SERVER)),
			str(settings.get("token", "")))
		var hello: Dictionary = Protocol.hello(_room_id(), ["motion", "speech"],
			Protocol.WANTED_ANIMATIONS, MOD_VERSION)
		_on = true
		_set_light(LIGHT_WAIT)
		print("[Rift] summoner on (room=%s)" % _room_id())
		if not _link.open_rift(url, hello):
			_on = false
			_set_light(LIGHT_OFF)
	else:
		print("[Rift] summoner off")
		_on = false
		_link.close_rift("switched_off")
		_remove_body()
		_set_light(LIGHT_OFF)


func _process(delta: float) -> void:
	if _body == null or not _link.is_open():
		return
	if _greet_cooldown > 0.0:
		_greet_cooldown -= delta
	_state_clock += delta
	if _state_clock >= STATE_INTERVAL:
		_state_clock = 0.0
		_link.send_frame(Protocol.state(_body.global_position, "", {"entities": _sense()}))
		_check_player()


func _on_opened(welcome: Dictionary) -> void:
	_set_light(LIGHT_ON)
	_spawn_body()
	var assets: Dictionary = welcome.get("assets", {}) if welcome.get("assets") is Dictionary else {}
	print("[Rift] welcomed; skin=%s, animations offered=%s" % [
		str(assets.get("skin", "?")), str((assets.get("animations", {}) as Dictionary).keys())])


func _on_closed(reason: String) -> void:
	print("[Rift] rift closed: %s" % reason)
	_on = false
	_remove_body()
	_set_light(LIGHT_OFF)


func _on_action(id: int, action: String, payload: Dictionary) -> void:
	await RiftDispatch.handle(_body, _link, id, action, payload)


func _spawn_body() -> void:
	_remove_body()
	_body = SynthBody.new()
	_body.name = "SynthBody"
	_body.anchor = global_position
	var host: Node = get_parent()
	if host == null:
		print("[Rift] summoner has no parent to put the body in")
		return
	host.add_child(_body)
	var spot := global_position + (-global_basis.z * 0.6)
	_body.global_position = _floor_below(spot)
	print("[Rift] body at %s" % str(_body.global_position))


func _remove_body() -> void:
	if _body != null and is_instance_valid(_body):
		_body.queue_free()
	_body = null


## The floor under `point` (the first collider straight down), or `point` if none.
func _floor_below(point: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.5, point + Vector3.DOWN * 3.0)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	return (hit["position"] as Vector3) if hit.has("position") else point


## What Synth's body can see: the spawned objects near it, nearest first.
func _sense() -> Array:
	var found: Array = []
	for node: Node in get_tree().get_nodes_in_group("spawned"):
		var n3 := node as Node3D
		if n3 == null or n3 == self or n3 == _body:
			continue
		var d := n3.global_position.distance_to(_body.global_position)
		if d > SENSE_RADIUS:
			continue
		var entry: Dictionary = {"name": str(n3.name), "type": n3.get_class(), "distance": snappedf(d, 0.01)}
		var script: Script = n3.get_script()
		if script != null and not script.get_global_name().is_empty():
			entry["type"] = str(script.get_global_name())
		var sid: Variant = n3.get("systemid")
		if sid is String and not String(sid).is_empty():
			entry["systemid"] = sid
		found.append(entry)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance"] < b["distance"])
	return found.slice(0, MAX_ENTITIES)


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


## Settings come from the mod's own store; the environment overrides for probes.
func _settings() -> Dictionary:
	var s: Dictionary = JsonStore.read_dict(SETTINGS_FILE, MOD_ID)
	var server := OS.get_environment("XENU_SYNTH_URL")
	if not server.is_empty():
		s["server"] = server
	var token := OS.get_environment("XENU_SYNTH_TOKEN")
	if not token.is_empty():
		s["token"] = token
	return s


func _build_light() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 2.0
	var lamp := get_node_or_null("Lamp") as MeshInstance3D
	if lamp != null:
		lamp.material_override = mat
	return mat


func _set_light(color: Color) -> void:
	_light_mat.albedo_color = color
	_light_mat.emission = color
