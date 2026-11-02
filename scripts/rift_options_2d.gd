## RiftOptions2D -- the Summoner's menu: where Synth lives, and the rift's state.
## Loaded into RiftOptionsPanel's SubViewport via XRToolsViewport2DIn3D.
##
## Emits:
##   settings_changed(server, token)  -- a field was committed (Enter, or focus left it)
##   power_pressed                    -- the Open/Close button
##   close_requested                  -- the X
extends Control

signal close_requested
signal settings_changed(server: String, token: String)
signal power_pressed

const BodyCache := preload("res://mods/xenu.synth_rift/scripts/body_cache.gd")

const COLOR_BG := Color(0.08, 0.08, 0.16, 0.96)
const COLOR_ROW := Color(0.65, 0.65, 0.80)
const COLOR_OK := Color(0.45, 1.0, 0.65)
const COLOR_WARN := Color(1.0, 0.80, 0.35)

var _server_edit: LineEdit = null
var _token_edit: LineEdit = null
var _show_btn: Button = null
var _status: Label = null
var _power: Button = null
var _last_server := ""
var _last_token := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _build_ui() -> void:
	var margin := MenuStyle.panel_root(self, COLOR_BG, 10, 12)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	MenuStyle.close_button(MenuStyle.title_row(root, "Synthetic Heart Rift"),
		func() -> void: close_requested.emit())
	root.add_child(HSeparator.new())

	_status = Label.new()
	_status.text = "Off"
	_status.add_theme_font_size_override("font_size", 18)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status)

	_server_edit = _field_row(root, "Server", "192.168.1.10:8080")
	_token_edit = _field_row(root, "Password", "none (only if Synth asks for one)")
	_token_edit.secret = true

	_show_btn = Button.new()
	_show_btn.toggle_mode = true
	_show_btn.text = "Show password"
	_show_btn.custom_minimum_size = Vector2(0, 36)
	_show_btn.toggled.connect(func(on: bool) -> void:
		_token_edit.secret = not on
		_show_btn.text = "Hide password" if on else "Show password")
	root.add_child(_show_btn)

	_power = Button.new()
	_power.text = "Open the rift"
	_power.custom_minimum_size = Vector2(0, 46)
	_power.add_theme_font_size_override("font_size", 20)
	_power.pressed.connect(func() -> void:
		_commit()
		power_pressed.emit())
	root.add_child(_power)

	# Her body is made once per skin and kept (see BodyCache); this lets the player throw it away, e.g. to free the space.
	var cache_btn := Button.new()
	cache_btn.text = "Forget Synth's saved body"
	cache_btn.custom_minimum_size = Vector2(0, 34)
	cache_btn.pressed.connect(func() -> void:
		var n := BodyCache.clear()
		cache_btn.text = "Forgotten (%d)" % n)
	root.add_child(cache_btn)


func _field_row(parent: Container, caption: String, placeholder: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = caption
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", COLOR_ROW)
	lbl.custom_minimum_size = Vector2(100, 0)
	row.add_child(lbl)
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.custom_minimum_size = Vector2(0, 38)
	edit.add_theme_font_size_override("font_size", 18)
	edit.text_submitted.connect(func(_t: String) -> void: _commit())
	edit.focus_exited.connect(_commit)
	row.add_child(edit)
	return edit


## Fill the fields and the state line. Safe to call every time the menu opens.
func populate(server: String, token: String, is_on: bool, status: String, ok: bool) -> void:
	if _server_edit == null:
		return
	if not _server_edit.has_focus():
		_server_edit.text = server
	if not _token_edit.has_focus():
		_token_edit.text = token
	_last_server = server
	_last_token = token
	set_status(status, ok, is_on)


func set_status(status: String, ok: bool, is_on: bool) -> void:
	if _status == null:
		return
	_status.text = status
	_status.add_theme_color_override("font_color", COLOR_OK if ok else COLOR_WARN)
	_power.text = "Close the rift" if is_on else "Open the rift"


func _commit() -> void:
	var server := _server_edit.text.strip_edges()
	var token := _token_edit.text
	if server == _last_server and token == _last_token:
		return
	_last_server = server
	_last_token = token
	settings_changed.emit(server, token)
