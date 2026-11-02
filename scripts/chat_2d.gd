## Chat2D -- the page you write to Synth on, and read her answers on.
## Loaded into ChatPanel's SubViewport via XRToolsViewport2DIn3D.
##
##   message_sent(text)   Enter in the field, or the Send button
##   close_requested      the X
extends Control

signal message_sent(text: String)
signal close_requested

const COLOR_BG := Color(0.08, 0.08, 0.16, 0.96)
const COLOR_YOU := "#9fb3ff"
const COLOR_SYNTH := "#6effff"
const MAX_LINES := 60

var _log: RichTextLabel = null
var _edit: LineEdit = null
var _lines: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MenuStyle.panel_root(self, COLOR_BG, 10, 12)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)
	MenuStyle.close_button(MenuStyle.title_row(root, "Talk to Synth"), func() -> void: close_requested.emit())
	root.add_child(HSeparator.new())

	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size = Vector2(0, 230)
	_log.add_theme_font_size_override("normal_font_size", 18)
	_log.add_theme_font_size_override("bold_font_size", 18)
	root.add_child(_log)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)
	_edit = LineEdit.new()
	_edit.placeholder_text = "Write to Synth and press Enter"
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_edit.custom_minimum_size = Vector2(0, 42)
	_edit.add_theme_font_size_override("font_size", 18)
	_edit.text_submitted.connect(func(_t: String) -> void: _send())
	row.add_child(_edit)
	var send := Button.new()
	send.text = "Send"
	send.custom_minimum_size = Vector2(84, 42)
	send.add_theme_font_size_override("font_size", 18)
	send.pressed.connect(_send)
	row.add_child(send)
	_redraw()


## Replace what the page shows with `lines` ([{who, text}], oldest first).
func show_lines(lines: Array) -> void:
	_lines = lines.slice(maxi(lines.size() - MAX_LINES, 0))
	_redraw()


func _redraw() -> void:
	if _log == null:
		return
	_log.clear()
	if _lines.is_empty():
		_log.append_text("[color=#8a8aa8]Nothing said yet. Write below.[/color]")
		return
	for line: Dictionary in _lines:
		var mine := str(line.get("who", "")) == "you"
		_log.append_text("[color=%s][b]%s[/b][/color]  %s\n" % [
			COLOR_YOU if mine else COLOR_SYNTH, "You" if mine else "Synth",
			str(line.get("text", "")).replace("[", "[lb]")])


func focus_field() -> void:
	if _edit != null:
		_edit.grab_focus()


func _send() -> void:
	var text := _edit.text.strip_edges()
	if text.is_empty():
		return
	_edit.clear()
	message_sent.emit(text)
