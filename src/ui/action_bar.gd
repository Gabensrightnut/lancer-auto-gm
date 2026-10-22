class_name ActionBar
extends Control
## BG3-style action bar at the bottom center: everything that isn't a basic move (weapons,
## Quick/Full actions, Boost, tech, systems, reactions, protocols, core power) as icon
## buttons with cost badges, grouped by tabs, with number-key shortcuts, hover cards, a
## compact resource cluster beside it and an End Turn button. Buttons can be rearranged by
## dragging; the order is saved per pilot. Height = 9% of the screen x `bar_scale` (a
## settings slider). Format in src/render/FORMATS.md.

signal action_pressed(action: Dictionary)
signal action_hovered(action: Dictionary, on: bool)
signal end_turn_pressed

const GROUPS := ["weapons", "quick", "full", "tech", "systems", "reactions", "core"]
const GROUP_NAMES := {"all": "All", "weapons": "Weapons", "quick": "Quick", "full": "Full", "tech": "Tech",
	"systems": "Systems", "reactions": "Reactions", "core": "Core"}
## Bar height as a fraction of the screen height (DESIGN: ~9% at 1080p).
const BASE_HEIGHT := 0.09
const LAYOUT_DIR := "user://action_layouts/"

## Settings slider: 0.7 .. 1.5.
var bar_scale := 1.0:
	set(v):
		bar_scale = clampf(v, 0.6, 1.6)
		_layout()
var pilot_id := ""
var actions: Array = []
var tab := "all"
var resources: ResourceCluster
var card: HoverCard
## Back-compat: the full ResourceHUD can also receive previews.
var resource_hud: ResourceHUD

var _panel: Panel
var _tabs: HBoxContainer
var _row: HBoxContainer
var _end_turn: Button
var _buttons: Dictionary = {}  # id -> ActionButton
var _order: Array = []


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel = Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.055, 0.88)
	sb.border_color = Color(0.35, 0.55, 0.75, 0.6)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)
	_panel.add_to_group(LabelDeclutter.GROUP_KEEPOUT)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 2)
	_panel.add_child(_tabs)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 4)
	_panel.add_child(_row)
	resources = ResourceCluster.new()
	add_child(resources)
	resources.add_to_group(LabelDeclutter.GROUP_KEEPOUT)
	_end_turn = Button.new()
	_end_turn.text = "END TURN"
	_end_turn.focus_mode = Control.FOCUS_NONE
	_end_turn.pressed.connect(func() -> void: end_turn_pressed.emit())
	var eb := StyleBoxFlat.new()
	eb.bg_color = Color(0.35, 0.12, 0.08, 0.95)
	eb.border_color = Color(1.0, 0.55, 0.3)
	eb.set_border_width_all(2)
	eb.set_corner_radius_all(4)
	_end_turn.add_theme_stylebox_override("normal", eb)
	var ebh := eb.duplicate() as StyleBoxFlat
	ebh.bg_color = Color(0.55, 0.2, 0.1, 0.98)
	_end_turn.add_theme_stylebox_override("hover", ebh)
	_end_turn.add_theme_stylebox_override("pressed", ebh)
	add_child(_end_turn)
	card = HoverCard.new()
	add_child(card)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func set_actions(list: Array, pilot: String = "") -> void:
	actions = list
	if pilot != "":
		pilot_id = pilot
	_load_order()
	_rebuild()


## Updates actions in place (e.g. after a turn passes) so lockout sweeps animate.
func update_actions(list: Array) -> void:
	actions = list
	for a: Dictionary in list:
		var b: ActionButton = _buttons.get(a.get("id", ""))
		if b:
			b.set_action(a)


func set_tab(t: String) -> void:
	tab = t
	_rebuild()


func _visible_actions() -> Array:
	var by_id := {}
	for a: Dictionary in actions:
		by_id[a.get("id", "")] = a
	var out: Array = []
	for id: String in _order:
		if by_id.has(id):
			var a: Dictionary = by_id[id]
			if tab == "all" or String(a.get("group", "quick")) == tab:
				out.append(a)
	return out


func _rebuild() -> void:
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	_buttons.clear()
	var present := {"all": true}
	for a: Dictionary in actions:
		present[String(a.get("group", "quick"))] = true
	for g: String in ["all"] + GROUPS:
		if not present.has(g):
			continue
		var b := Button.new()
		b.text = GROUP_NAMES[g]
		b.toggle_mode = true
		b.button_pressed = g == tab
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(set_tab.bind(g))
		_tabs.add_child(b)
	var vis := _visible_actions()
	var last_group := ""
	for i in range(vis.size()):
		var a: Dictionary = vis[i]
		var g := String(a.get("group", "quick"))
		if tab == "all" and g != last_group and last_group != "":
			var sep := ColorRect.new()
			sep.color = Color(0.35, 0.55, 0.75, 0.35)
			sep.custom_minimum_size = Vector2(2, 0)
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_row.add_child(sep)
		last_group = g
		var b := ActionButton.new(a)
		b.hotkey = str((i + 1) % 10) if i < 10 else ""
		b.pressed.connect(func(x: Dictionary) -> void: action_pressed.emit(x))
		b.hovered.connect(_hover)
		b.swap_requested.connect(_swap)
		_row.add_child(b)
		_buttons[a.get("id", "")] = b
	_layout()


func _layout() -> void:
	if _panel == null:
		return
	var vp := get_viewport_rect().size if is_inside_tree() else Vector2(1920, 1080)
	var h := vp.y * BASE_HEIGHT * bar_scale
	# Shrink to fit the screen width if the slider (or many buttons) would overflow it.
	var buttons := 0
	var seps := 0
	for c in _row.get_children():
		if c is ActionButton:
			buttons += 1
		else:
			seps += 1
	var need := h * 3.1 + 8 + maxf((h * 0.76 - 10.0 + 4) * buttons + 6 * seps + 12.0, h * 4.0) + 8 + h * 1.05
	if need > vp.x - 16.0:
		h *= (vp.x - 16.0) / need
	var tab_h := h * 0.24
	var btn := h - tab_h - 10.0
	var n := _row.get_child_count()
	var row_w := 0.0
	for c in _row.get_children():
		if c is ActionButton:
			c.custom_minimum_size = Vector2(btn, btn)
			row_w += btn + 4
		else:
			row_w += 6
	var w := maxf(row_w + 12.0, h * 4.0)
	var cluster_w := h * 3.1
	var end_w := h * 1.05
	var total := cluster_w + 8 + w + 8 + end_w
	var x0 := (vp.x - total) / 2.0
	var y0 := vp.y - h - 10.0
	resources.position = Vector2(x0, y0)
	resources.size = Vector2(cluster_w, h)
	_panel.position = Vector2(x0 + cluster_w + 8, y0)
	_panel.size = Vector2(w, h)
	_tabs.position = Vector2(6, 3)
	for b in _tabs.get_children():
		(b as Button).add_theme_font_size_override("font_size", int(tab_h * 0.55))
		(b as Button).custom_minimum_size = Vector2(0, tab_h - 4)
	_row.position = Vector2(6, tab_h + 4)
	_row.size = Vector2(w - 12, btn)
	_end_turn.position = Vector2(_panel.position.x + w + 8, y0)
	_end_turn.size = Vector2(end_w, h)
	_end_turn.add_theme_font_size_override("font_size", int(h * 0.16))
	if n == 0:
		_row.size = Vector2.ZERO


func _hover(a: Dictionary, on: bool) -> void:
	if not on:
		card.visible = false
		resources.set_preview({})
		if resource_hud:
			resource_hud.set_preview({})
		action_hovered.emit(a, false)
		return
	var vp := get_viewport_rect().size
	card.show_action(a, clampf(vp.y / 1080.0, 0.75, 1.5))
	var b: ActionButton = _buttons.get(a.get("id", ""))
	var x := _panel.position.x + (b.position.x if b else 0.0)
	card.position = Vector2(clampf(x, 8, vp.x - card.size.x - 8), _panel.position.y - card.size.y - 8)
	var p: Dictionary = a.get("preview", {}) if not ActionButton.locked(a) else {}
	resources.set_preview(p)
	if resource_hud:
		resource_hud.set_preview(p)
	action_hovered.emit(a, true)


## Shows the hover card and preview for an action without the mouse (tutorial, screenshots).
func hover(id: String) -> void:
	for a: Dictionary in actions:
		if a.get("id") == id:
			_hover(a, true)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or not visible:
		return
	if k.keycode >= KEY_0 and k.keycode <= KEY_9 and not k.shift_pressed and not k.ctrl_pressed:
		var idx := (k.keycode - KEY_1 + 10) % 10
		var vis := _visible_actions()
		if idx < vis.size() and not ActionButton.locked(vis[idx]):
			action_pressed.emit(vis[idx])
			get_viewport().set_input_as_handled()


# --- per-pilot layout ------------------------------------------------------------------

func _swap(from_id: String, to_id: String) -> void:
	var i := _order.find(from_id)
	var j := _order.find(to_id)
	if i < 0 or j < 0:
		return
	_order[i] = to_id
	_order[j] = from_id
	_save_order()
	_rebuild()


func _layout_path() -> String:
	return LAYOUT_DIR + (pilot_id if pilot_id != "" else "default") + ".json"


func _load_order() -> void:
	var saved: Array = []
	if FileAccess.file_exists(_layout_path()):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(_layout_path()))
		if d is Dictionary:
			saved = d.get("order", [])
	# Default order: by group, then as given. Saved order wins for known ids.
	var ids: Array = []
	for g: String in GROUPS:
		for a: Dictionary in actions:
			if String(a.get("group", "quick")) == g:
				ids.append(a.get("id", ""))
	for a: Dictionary in actions:
		if not ids.has(a.get("id", "")):
			ids.append(a.get("id", ""))
	_order = []
	for id: Variant in saved:
		if ids.has(id):
			_order.append(id)
	for id: Variant in ids:
		if not _order.has(id):
			_order.append(id)


func _save_order() -> void:
	DirAccess.make_dir_recursive_absolute(LAYOUT_DIR)
	var f := FileAccess.open(_layout_path(), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"order": _order}))
