## RiftOptionsPanel -- the Summoner's floating menu.
##
## Opened the way every object's menu is: point at the Summoner and press the left
## thumbstick (Tab on a desktop); the controller calls the Summoner's
## toggle_options_ui, which builds this on demand as its child. The server and
## password live HERE, on the object, and not in the global menu.
extends FloatingObjectPanel3D

const PANEL_SCENE := preload("res://mods/xenu.synth_rift/scenes/rift_options_panel.tscn")
const RiftSettings := preload("res://mods/xenu.synth_rift/scripts/rift_settings.gd")
const NODE_NAME := "RiftOptionsPanel"
## The menu hangs BESIDE a pod this big, on the side of the player's right hand, at chest height,
## where it can be read (a cabinet's does the same), not over a hood two metres up.
const SIDE_DISTANCE := 1.45
const CHEST_HEIGHT := 1.3
const TOWARD_PLAYER := 0.2

var _summoner: Node3D = null

@onready var _viewport_node: XRToolsViewport2DIn3D = $RiftOptionsViewport


static func toggle_for(summoner: Node3D, camera: Node3D) -> void:
	if not is_instance_valid(summoner):
		return
	var panel := summoner.get_node_or_null(NODE_NAME)
	if panel == null:
		panel = PANEL_SCENE.instantiate()
		panel.name = NODE_NAME
		summoner.add_child(panel)
	if panel.visible:
		panel.hide_panel()
	else:
		panel.show_for(summoner, camera)


func show_for(summoner: Node3D, camera: Node3D) -> void:
	_summoner = summoner
	_camera = camera
	global_position = _anchor()
	visible = true
	_ensure_ui_connected()
	_populate()


func _get_ui() -> Control:
	var vp := _viewport_node.get_node_or_null("Viewport") as SubViewport
	if vp == null or vp.get_child_count() == 0:
		return null
	return vp.get_child(0) as Control


func _ensure_ui_connected() -> void:
	if _ui_connected:
		return
	var ui := _get_ui()
	if ui == null:
		call_deferred("_ensure_ui_connected")
		return
	ui.close_requested.connect(hide_panel)
	ui.settings_changed.connect(_on_settings_changed)
	ui.power_pressed.connect(_on_power_pressed)
	ui.forget_chat_pressed.connect(_on_forget_chat)
	if _summoner.has_signal("status_changed"):
		_summoner.status_changed.connect(_refresh)
	_ui_connected = true


func _populate() -> void:
	if _get_ui() == null:
		call_deferred("_populate")
		return
	_refresh()


func _refresh() -> void:
	var ui := _get_ui()
	if ui == null or not is_instance_valid(_summoner):
		return
	var s: Dictionary = RiftSettings.load_settings()
	ui.populate(str(s.get("server", "")), str(s.get("token", "")),
		_summoner.is_on(), _summoner.status_text(), _summoner.status_ok())


func _on_settings_changed(server: String, token: String) -> void:
	RiftSettings.save(server, token)


func _on_forget_chat() -> void:
	if not is_instance_valid(_summoner) or not _summoner.has_method("forget_chat"):
		return
	var told := bool(_summoner.call("forget_chat"))
	var ui := _get_ui()
	if ui != null:
		ui.chat_forgotten(told)


func _on_power_pressed() -> void:
	if is_instance_valid(_summoner):
		_summoner.toggle()


func _target_node() -> Node3D:
	return _summoner


func _float_height() -> float:
	return CHEST_HEIGHT


## Beside the pod: to the right of someone looking at it, at chest height, a little toward them.
func _anchor() -> Vector3:
	if not is_instance_valid(_summoner):
		return global_position
	var pod := _summoner.global_position
	var cam := _camera if is_instance_valid(_camera) else get_viewport().get_camera_3d()
	var to_cam := Vector3(0, 0, 1)
	if cam != null:
		to_cam = Vector3(cam.global_position.x - pod.x, 0.0, cam.global_position.z - pod.z)
	if to_cam.length() < 0.01:
		to_cam = Vector3(0, 0, 1)
	to_cam = to_cam.normalized()
	var right := (-to_cam).cross(Vector3.UP).normalized()
	return pod + right * SIDE_DISTANCE + to_cam * TOWARD_PLAYER + Vector3(0, CHEST_HEIGHT, 0)
