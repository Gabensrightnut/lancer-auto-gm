class_name ActionBar
extends Control
## Every available action as a button: cost icons (Quick, Full, Free, Reaction, Protocol,
## Move, plus heat / charges / Overcharge badges with numbers), name and a short description.
## Unusable actions are greyed with the reason. Hovering shows the full rule text and rule
## reference, and previews the cost on a ResourceHUD. Format in src/render/FORMATS.md.

signal action_pressed(action: Dictionary)
signal action_hovered(action: Dictionary)

const BTN := Vector2(189, 78)

var resources: ResourceHUD
var actions: Array = []

var _flow: HFlowContainer
var _detail: PanelContainer
var _detail_text: RichTextLabel
var _buttons: Dictionary = {}  # id -> Button


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	_flow = HFlowContainer.new()
	_flow.add_theme_constant_override("h_separation", 6)
	_flow.add_theme_constant_override("v_separation", 6)
	add_child(_flow)
	_detail = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.07, 0.94)
	sb.border_color = Color(0.4, 0.65, 0.85, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(10)
	_detail.add_theme_stylebox_override("panel", sb)
	_detail.visible = false
	_detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_text = RichTextLabel.new()
	_detail_text.bbcode_enabled = true
	_detail_text.fit_content = true
	_detail_text.custom_minimum_size = Vector2(520, 0)
	_detail_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_detail_text.add_theme_font_size_override("normal_font_size", 14)
	_detail_text.add_theme_font_size_override("bold_font_size", 16)
	_detail.add_child(_detail_text)
	add_child(_detail)


func set_actions(list: Array) -> void:
	actions = list
	for c in _flow.get_children():
		c.queue_free()
	_buttons.clear()
	for a: Dictionary in list:
		var b := _make_button(a)
		_flow.add_child(b)
		_buttons[a.get("id", "")] = b
	_layout()


func _layout() -> void:
	_flow.size = Vector2(size.x, 0)
	_flow.position = Vector2.ZERO


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _flow:
		_layout()


func _make_button(a: Dictionary) -> Button:
	var enabled := bool(a.get("enabled", true))
	var b := Button.new()
	b.custom_minimum_size = BTN
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = not enabled
	b.tooltip_text = ""
	for state: String in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.07, 0.09, 0.12, 0.92) if enabled else Color(0.06, 0.06, 0.07, 0.85)
		if state == "hover":
			sb.bg_color = Color(0.1, 0.16, 0.22, 0.96)
		if state == "pressed":
			sb.bg_color = Color(0.15, 0.25, 0.32, 0.96)
		var cost_col: Color = CostIcon.COLORS.get(a.get("cost", "quick"), Color.WHITE)
		sb.border_color = cost_col.darkened(0.2) if enabled else Color(0.25, 0.25, 0.28)
		sb.border_width_left = 4
		sb.set_border_width(SIDE_TOP, 1)
		sb.set_border_width(SIDE_RIGHT, 1)
		sb.set_border_width(SIDE_BOTTOM, 1)
		sb.set_corner_radius_all(3)
		b.add_theme_stylebox_override(state, sb)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 1)
	box.position = Vector2(10, 5)
	box.size = BTN - Vector2(16, 8)
	b.add_child(box)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 4)
	box.add_child(top)
	var icon := CostIcon.new(String(a.get("cost", "quick")), "", 22.0)
	icon.dimmed = not enabled
	top.add_child(icon)
	var name := Label.new()
	name.text = String(a.get("name", "?"))
	name.add_theme_font_size_override("font_size", 16)
	name.add_theme_color_override("font_color", Color.WHITE if enabled else Color(0.5, 0.5, 0.55))
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.clip_text = true
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(name)
	for x: Dictionary in a.get("extras", []):
		var ei := CostIcon.new(String(x.get("kind", "heat")), str(x.get("value", "")), 18.0)
		ei.dimmed = not enabled
		top.add_child(ei)
	var desc := Label.new()
	desc.text = String(a.get("desc", "")) if enabled else "✕ " + String(a.get("reason", "Unavailable"))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(BTN.x - 18, 0)
	desc.max_lines_visible = 2
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.72, 0.78, 0.85) if enabled else Color(1.0, 0.45, 0.4))
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(desc)
	b.mouse_entered.connect(_hover.bind(a, true))
	b.mouse_exited.connect(_hover.bind(a, false))
	b.pressed.connect(func() -> void: action_pressed.emit(a))
	return b


## Shows the detail panel and cost preview for an action (also used by screenshots/tutorial).
func hover(id: String) -> void:
	for a: Dictionary in actions:
		if a.get("id") == id:
			_hover(a, true)


func _hover(a: Dictionary, on: bool) -> void:
	if not on:
		_detail.visible = false
		if resources:
			resources.set_preview({})
		return
	var cost := String(a.get("cost", "quick"))
	var lines := "[b]%s[/b]   [color=#%s]%s[/color]" % [a.get("name", ""), (CostIcon.COLORS.get(cost, Color.WHITE) as Color).to_html(false), CostIcon.NAMES.get(cost, cost)]
	for x: Dictionary in a.get("extras", []):
		lines += "  ·  %s %s" % [CostIcon.NAMES.get(x.get("kind", ""), ""), x.get("value", "")]
	lines += "\n" + String(a.get("text", a.get("desc", "")))
	if not bool(a.get("enabled", true)):
		lines += "\n[color=#ff7766]Can't use: %s[/color]" % a.get("reason", "")
	if a.has("rule_ref"):
		lines += "\n[color=#8aa]Rule: %s[/color]" % a["rule_ref"]
	_detail_text.text = lines
	_detail.visible = true
	_detail.reset_size()
	var b: Button = _buttons.get(a.get("id", ""))
	var x := 0.0 if b == null else clampf(b.position.x, 0.0, maxf(0.0, size.x - _detail.size.x))
	_detail.position = Vector2(x, -_detail.size.y - 8)
	if resources:
		resources.set_preview(a.get("preview", {}) if bool(a.get("enabled", true)) else {})
	action_hovered.emit(a)
