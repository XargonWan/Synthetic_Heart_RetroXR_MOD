## ChatPanel -- the chat page, floating beside Synth.
##
## Opened the way every object's menu is: point at THEM and press the left thumbstick (Tab on a
## desktop); the controller calls their body's toggle_options_ui. The page keeps nothing: the body
## keeps the log, this shows it and hands what is written back.
extends FloatingObjectPanel3D

const RiftSettings := preload("res://mods/xenu.synth_rift/scripts/rift_settings.gd")
const PANEL_SCENE := preload("res://mods/xenu.synth_rift/scenes/chat_panel.tscn")
const NODE_NAME := "ChatPanel"
## UNDER them: low in front of their feet, toward the player, where a person looks down to read.
const HEIGHT := 0.55
const TOWARD_PLAYER := 0.65

var _body: Node3D = null

@onready var _viewport_node: XRToolsViewport2DIn3D = $ChatViewport


static func toggle_for(body: Node3D, camera: Node3D) -> void:
	if not is_instance_valid(body):
		return
	var panel := body.get_node_or_null(NODE_NAME)
	if panel == null:
		panel = PANEL_SCENE.instantiate()
		panel.name = NODE_NAME
		body.add_child(panel)
	if panel.visible:
		panel.hide_panel()
	else:
		panel.show_for(body, camera)


func show_for(body: Node3D, camera: Node3D) -> void:
	_body = body
	_camera = camera
	global_position = _anchor()
	visible = true
	_ensure_ui_connected()
	_refresh()


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
	ui.set_synth_name(RiftSettings.synth_name())
	ui.message_sent.connect(func(text: String) -> void:
		if is_instance_valid(_body):
			_body.send_chat(text))
	ui.mic_pressed.connect(func() -> void:
		if is_instance_valid(_body):
			_body.toggle_voice())
	if _body.has_signal("voice_changed"):
		_body.voice_changed.connect(ui.set_recording)
		ui.set_recording(_body.voice_recording())
	if _body.has_signal("chat_changed"):
		_body.chat_changed.connect(_refresh)
	_ui_connected = true


func _refresh() -> void:
	var ui := _get_ui()
	if ui == null:
		call_deferred("_refresh")
		return
	if is_instance_valid(_body):
		ui.set_synth_name(RiftSettings.synth_name())
		ui.show_lines(_body.chat_lines())


## No subject: FloatingObjectPanel3D lifts a panel clear of its subject's box, and this one is
## meant to hang in front of their legs, which is inside it.
func _target_node() -> Node3D:
	return null


func _float_height() -> float:
	return HEIGHT


func _anchor() -> Vector3:
	if not is_instance_valid(_body):
		return global_position
	var pos := _body.global_position
	var cam := _camera if is_instance_valid(_camera) else get_viewport().get_camera_3d()
	var to_cam := Vector3(0, 0, 1)
	if cam != null:
		to_cam = Vector3(cam.global_position.x - pos.x, 0.0, cam.global_position.z - pos.z)
	if to_cam.length() < 0.01:
		to_cam = Vector3(0, 0, 1)
	return pos + to_cam.normalized() * TOWARD_PLAYER + Vector3(0, HEIGHT, 0)
