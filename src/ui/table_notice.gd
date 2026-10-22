class_name TableNotice
extends PanelContainer
## A pop-up for effects the game doesn't apply itself (manual_effect events): which system,
## its rule text, and what the table should do. Stays until clicked or for a while; several
## stack as a queue. Also keeps nameplates out from under it (LabelDeclutter keep-out).

const SHOW_FOR := 9.0

var _text: RichTextLabel
var _queue: Array = []
var _left := 0.0


func _init() -> void:
	add_to_group(LabelDeclutter.GROUP_KEEPOUT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.05, 0.03, 0.95)
	sb.border_color = Color(0.88, 0.69, 0.31, 0.95)
	sb.set_border_width_all(1)
	sb.border_width_left = 4
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(12)
	add_theme_stylebox_override("panel", sb)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.custom_minimum_size = Vector2(420, 0)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.add_theme_font_size_override("normal_font_size", 15)
	_text.add_theme_font_size_override("bold_font_size", 17)
	add_child(_text)
	visible = false


func show_note(source: String, rule_text: String, guidance: String) -> void:
	_queue.append([source, rule_text, guidance])
	if not visible:
		_next()


func _next() -> void:
	if _queue.is_empty():
		visible = false
		return
	var n: Array = _queue.pop_front()
	var body := RegEx.create_from_string("<[^>]+>").sub(String(n[1]).replace("<br>", "\n"), "", true).strip_edges()
	if body.length() > 420:
		body = body.left(420) + "…"
	_text.clear()
	_text.append_text("[color=#e0b050][b]FOR THE TABLE: %s[/b][/color]\n" % n[0])
	if body != "":
		_text.append_text("[color=#c8ccd2]%s[/color]\n" % body)
	_text.append_text("[color=#f0d79a]%s[/color]\n[color=#8a8070][i]Click to close[/i][/color]" % n[2])
	visible = true
	reset_size()
	var vp := get_viewport_rect().size if is_inside_tree() else Vector2(1920, 1080)
	position = Vector2(vp.x - size.x - 24, vp.y * 0.22)
	_left = SHOW_FOR


func _process(delta: float) -> void:
	if visible:
		_left -= delta
		if _left <= 0.0:
			_next()


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
		_next()
