class_name PilotCreator
extends PanelContainer
## The pilot look creator (DESIGN.md "Customization"): a big portrait, the list of parts down
## the side with a lock pin each, a grid of options for the selected part, primary and
## secondary colors from the part's palette, saved color presets, the pilot's expressions,
## and a Token tab with the on-foot model. Randomize all keeps locked parts.
## Works on the v2 portrait format (PortraitSpec); the result goes in pilot["portrait"].
##
##   var pc := PilotCreator.new()
##   add_child(pc)
##   pc.open(pilot.get("portrait", {}))
##   pc.confirmed.connect(func(p: Dictionary) -> void: pilot["portrait"] = p)
##   pc.cancelled.connect(pc.queue_free)

signal confirmed(portrait: Dictionary)
signal cancelled

const SAVED_LOOKS := "user://pilot_looks.json"
const SAVED_COLORS := "user://portrait_colors.json"
const TEXT := Color(0.86, 0.9, 0.94)
const MUTED := Color(0.55, 0.62, 0.7)
const ACCENT := Color(0.95, 0.72, 0.3)

var portrait: Dictionary = {}
var locks: Dictionary = {}
var part_id := "hair"
var color_slot := "primary"
var expression := "neutral"
var tab := "portrait"

var _start: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _big: PortraitArt
var _token_view: SubViewportContainer
var _token_root: Node3D
var _token: PilotToken
var _part_rows: VBoxContainer
var _options: GridContainer
var _option_title: Label
var _slot_row: HBoxContainer
var _palette: GridContainer
var _saved_colors: HFlowContainer
var _expr_row: HBoxContainer
var _looks: OptionButton
var _tab_buttons: Dictionary = {}


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.035, 0.042, 0.055)
	sb.set_content_margin_all(18)
	add_theme_stylebox_override("panel", sb)
	_rng.randomize()
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	add_child(root)
	root.add_child(_header())
	var main := HBoxContainer.new()
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main.add_theme_constant_override("separation", 16)
	root.add_child(main)
	main.add_child(_parts_column())
	main.add_child(_center_column())
	main.add_child(_options_column())
	root.add_child(_footer())


## Starts editing a look (empty = a random one).
func open(p: Dictionary = {}) -> void:
	portrait = PortraitSpec.normalize(p) if not p.is_empty() else PortraitSpec.randomize(_rng)
	portrait = portrait.duplicate(true)
	_start = portrait.duplicate(true)
	locks.clear()
	_refresh_all()


func get_portrait() -> Dictionary:
	return portrait.duplicate(true)


func select_part(id: String) -> void:
	part_id = id
	color_slot = "primary"
	_refresh_all()


func set_option(option: String) -> void:
	_entry(part_id)["option"] = option
	_refresh_all()


func set_color(c: Color) -> void:
	_entry(part_id)[color_slot] = "#" + c.to_html(false)
	# Face and body share the skin tone.
	if part_id in ["face", "body"]:
		_entry("face")["primary"] = _entry(part_id)["primary"]
		_entry("body")["primary"] = _entry(part_id)["primary"]
	_refresh_all()


func randomize_all() -> void:
	portrait = PortraitSpec.randomize(_rng, portrait, locks)
	_refresh_all()


func toggle_lock(id: String) -> void:
	if locks.has(id):
		locks.erase(id)
	else:
		locks[id] = true
	_refresh_parts()


func set_expression(e: String) -> void:
	expression = e
	_big.set_look(portrait, expression)
	_refresh_expressions()


func set_tab(t: String) -> void:
	tab = t
	_big.visible = t == "portrait"
	_token_view.visible = t == "token"
	for k: String in _tab_buttons:
		(_tab_buttons[k] as Button).button_pressed = k == t
	if t == "token":
		_rebuild_token()


func _entry(id: String) -> Dictionary:
	var parts: Dictionary = portrait["parts"]
	if not parts.has(id):
		parts[id] = {"option": "none"}
	return parts[id]


func _part_def(id: String) -> Dictionary:
	for p: Dictionary in PortraitSpec.parts():
		if String(p["id"]) == id:
			return p
	return {}


static func nice(id: String) -> String:
	return id.replace("_", " ").capitalize()


# --- layout --------------------------------------------------------------------------------

func _label(t: String, px: int, col: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	return l


func _button(t: String, cb: Callable, min_w: float = 120.0) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(min_w, 34)
	b.add_theme_font_size_override("font_size", 15)
	b.pressed.connect(cb)
	return b


func _header() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(_label("PILOT CREATOR", 26, ACCENT))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(30, 0)
	h.add_child(gap)
	for t: Array in [["portrait", "Portrait"], ["token", "Token"]]:
		var b := _button(t[1], func() -> void: set_tab(t[0]), 110)
		b.toggle_mode = true
		_tab_buttons[t[0]] = b
		h.add_child(b)
	var hint := _label("Pick a part on the left, then a style and colors on the right. Pins keep a part when you randomize.", 14, MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(hint)
	return h


func _parts_column() -> Control:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(300, 0)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_part_rows = VBoxContainer.new()
	_part_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_part_rows.add_theme_constant_override("separation", 3)
	sc.add_child(_part_rows)
	return sc


func _center_column() -> Control:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	var stage := Control.new()
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.custom_minimum_size = Vector2(480, 520)
	v.add_child(stage)
	var frame := AspectRatioContainer.new()
	frame.ratio = 0.86
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(frame)
	_big = PortraitArt.new()
	frame.add_child(_big)
	_token_view = _build_token_view()
	_token_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_token_view.visible = false
	stage.add_child(_token_view)
	v.add_child(_label("Expressions (dialogue picks these automatically)", 14, MUTED))
	_expr_row = HBoxContainer.new()
	_expr_row.add_theme_constant_override("separation", 6)
	v.add_child(_expr_row)
	return v


func _options_column() -> Control:
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(560, 0)
	v.add_theme_constant_override("separation", 8)
	_option_title = _label("", 20, ACCENT)
	v.add_child(_option_title)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 430)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_options = GridContainer.new()
	_options.columns = 4
	_options.add_theme_constant_override("h_separation", 8)
	_options.add_theme_constant_override("v_separation", 8)
	sc.add_child(_options)
	v.add_child(sc)
	_slot_row = HBoxContainer.new()
	_slot_row.add_theme_constant_override("separation", 8)
	v.add_child(_slot_row)
	_palette = GridContainer.new()
	_palette.columns = 12
	_palette.add_theme_constant_override("h_separation", 4)
	_palette.add_theme_constant_override("v_separation", 4)
	v.add_child(_palette)
	v.add_child(_label("Saved colors", 14, MUTED))
	_saved_colors = HFlowContainer.new()
	_saved_colors.add_theme_constant_override("h_separation", 4)
	v.add_child(_saved_colors)
	return v


func _footer() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	h.add_child(_button("Randomize all", randomize_all, 150))
	h.add_child(_button("Save look", _save_look))
	_looks = OptionButton.new()
	_looks.focus_mode = Control.FOCUS_NONE
	_looks.custom_minimum_size = Vector2(190, 34)
	_looks.item_selected.connect(_load_look)
	h.add_child(_looks)
	h.add_child(_button("Reset to default", func() -> void:
		portrait = _start.duplicate(true)
		_refresh_all(), 150))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(gap)
	h.add_child(_button("Cancel", func() -> void: cancelled.emit()))
	var ok := _button("Confirm", func() -> void: confirmed.emit(get_portrait()), 150)
	ok.add_theme_color_override("font_color", ACCENT)
	h.add_child(ok)
	return h


# --- refresh -------------------------------------------------------------------------------

func _refresh_all() -> void:
	if portrait.is_empty():
		return
	_big.set_look(portrait, expression)
	_refresh_parts()
	_refresh_options()
	_refresh_colors()
	_refresh_expressions()
	_refresh_looks()
	if tab == "token":
		_rebuild_token()
	set_tab(tab)


func _refresh_parts() -> void:
	for c in _part_rows.get_children():
		c.queue_free()
	for p: Dictionary in PortraitSpec.parts():
		var id := String(p["id"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var pin := LockPin.new()
		pin.locked = locks.has(id)
		pin.tooltip_text = "Keep this part when randomizing"
		pin.toggled_lock.connect(func() -> void: toggle_lock(id))
		row.add_child(pin)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_pressed = id == part_id
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 30)
		b.text = "%s   ·  %s" % [p.get("name", nice(id)), nice(String(_entry(id).get("option", "none")))]
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(func() -> void: select_part(id))
		row.add_child(b)
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(16, 16)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sw.color = Color(String(_entry(id).get("primary", "#00000000"))) if (p.get("colors", []) as Array).size() > 0 else Color(0, 0, 0, 0)
		row.add_child(sw)
		_part_rows.add_child(row)


func _refresh_options() -> void:
	var def := _part_def(part_id)
	_option_title.text = String(def.get("name", nice(part_id))).to_upper()
	for c in _options.get_children():
		c.queue_free()
	var cur := String(_entry(part_id).get("option", ""))
	for opt: String in def.get("options", []):
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(128, 148)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.07, 0.09)
		sb.set_border_width_all(3 if opt == cur else 1)
		sb.border_color = ACCENT if opt == cur else Color(0.2, 0.24, 0.3)
		sb.set_corner_radius_all(4)
		for st: String in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, sb)
		var look := portrait.duplicate(true)
		(look["parts"] as Dictionary)[part_id] = (_entry(part_id).duplicate() as Dictionary).merged({"option": opt}, true)
		var thumb := PortraitArt.new()
		thumb.card = false
		thumb.custom_minimum_size = Vector2.ZERO
		thumb.set_anchors_preset(Control.PRESET_FULL_RECT)
		thumb.offset_left = 3
		thumb.offset_top = 3
		thumb.offset_right = -3
		thumb.offset_bottom = -3
		thumb.set_look(look, expression)
		b.add_child(thumb)
		b.pressed.connect(func() -> void: set_option(opt))
		cell.add_child(b)
		var l := _label(nice(opt), 13, TEXT if opt == cur else MUTED)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(l)
		_options.add_child(cell)


func _refresh_colors() -> void:
	var def := _part_def(part_id)
	var slots: Array = def.get("colors", [])
	for c in _slot_row.get_children():
		c.queue_free()
	for c in _palette.get_children():
		c.queue_free()
	for c in _saved_colors.get_children():
		c.queue_free()
	if slots.is_empty():
		_slot_row.add_child(_label("This part has no colors.", 14, MUTED))
		return
	if not slots.has(color_slot):
		color_slot = String(slots[0])
	for slot: String in slots:
		var b := _button(nice(slot), func() -> void:
			color_slot = slot
			_refresh_colors(), 120)
		b.toggle_mode = true
		b.button_pressed = slot == color_slot
		var col := Color(String(_entry(part_id).get(slot, "#808080")))
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(4)
		sb.set_border_width_all(3 if slot == color_slot else 1)
		sb.border_color = Color.WHITE if slot == color_slot else Color(0, 0, 0, 0.6)
		for st: String in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, sb)
		for k: String in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(k, Color.BLACK if col.get_luminance() > 0.5 else Color.WHITE)
		_slot_row.add_child(b)
	var pal: Array = (PortraitSpec.data().get("palettes", {}) as Dictionary).get(String(def.get("palette", "")), [])
	for h: String in pal:
		_palette.add_child(_swatch(Color(h), func() -> void: set_color(Color(h))))
	# Saved color pairs for this palette.
	for pair: Dictionary in _saved_color_list():
		if String(pair.get("palette", "")) != String(def.get("palette", "")):
			continue
		var b := _swatch(Color(String(pair["primary"])), func() -> void:
			for k: String in ["primary", "secondary"]:
				if pair.has(k) and slots.has(k):
					_entry(part_id)[k] = pair[k]
			_refresh_all(), Color(String(pair.get("secondary", pair["primary"]))))
		_saved_colors.add_child(b)
	_saved_colors.add_child(_button("+ Save these colors", _save_colors, 160))


func _swatch(c: Color, cb: Callable, second: Color = Color(0, 0, 0, 0)) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(34, 30)
	b.tooltip_text = "#" + c.to_html(false)
	for st: String in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(4)
		sb.set_border_width_all(2 if st == "hover" else 1)
		sb.border_color = Color.WHITE if st == "hover" else Color(0, 0, 0, 0.6)
		if second.a > 0.0:
			sb.border_width_bottom = 8
			sb.border_color = second
		b.add_theme_stylebox_override(st, sb)
	b.pressed.connect(cb)
	return b


func _refresh_expressions() -> void:
	for c in _expr_row.get_children():
		c.queue_free()
	for e: String in PortraitArt.EXPRESSIONS:
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 1)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(76, 86)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.07, 0.09)
		sb.set_border_width_all(2 if e == expression else 1)
		sb.border_color = ACCENT if e == expression else Color(0.2, 0.24, 0.3)
		for st: String in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, sb)
		var t := PortraitArt.new()
		t.card = false
		t.custom_minimum_size = Vector2.ZERO
		t.set_anchors_preset(Control.PRESET_FULL_RECT)
		t.set_look(portrait, e)
		b.add_child(t)
		b.pressed.connect(func() -> void:
			expression = e
			_refresh_expressions()
			_big.set_look(portrait, expression))
		cell.add_child(b)
		var l := _label(nice(e), 11, TEXT if e == expression else MUTED)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(l)
		_expr_row.add_child(cell)


# --- token ---------------------------------------------------------------------------------

func _build_token_view() -> SubViewportContainer:
	var vpc := SubViewportContainer.new()
	vpc.stretch = true
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vpc.add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.06, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.65, 0.75)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -30, 0)
	key.light_energy = 1.5
	key.shadow_enabled = true
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 160, 0)
	rim.light_color = Color(0.6, 0.75, 1.0)
	vp.add_child(rim)
	var floor := MeshInstance3D.new()
	floor.mesh = MeshKit.cylinder(0.9, 0.04, 40)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.1, 0.11, 0.13)
	fm.roughness = 0.9
	floor.material_override = fm
	floor.position.y = -0.02
	vp.add_child(floor)
	_token_root = Node3D.new()
	vp.add_child(_token_root)
	var cam := Camera3D.new()
	cam.fov = 30.0
	var eye := Vector3(0, 1.45, -4.4)
	cam.transform = Transform3D(Basis.looking_at(Vector3(0, 0.95, 0) - eye), eye)
	vp.add_child(cam)
	return vpc


func _rebuild_token() -> void:
	if _token:
		_token.queue_free()
	_token = PilotToken.new().build(portrait)
	_token.rotation_degrees.y = 200.0
	_token_root.add_child(_token)


func _process(delta: float) -> void:
	if tab == "token" and _token:
		_token.rotation_degrees.y += delta * 20.0


# --- saving --------------------------------------------------------------------------------

func _read(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var d: Variant = JSON.parse_string(f.get_as_text())
	return d if d is Array else []


func _write(path: String, list: Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(list, "  "))


func _saved_color_list() -> Array:
	return _read(SAVED_COLORS)


func _save_colors() -> void:
	var def := _part_def(part_id)
	var e := _entry(part_id)
	var pair := {"palette": String(def.get("palette", ""))}
	for k: String in ["primary", "secondary"]:
		if e.has(k):
			pair[k] = e[k]
	var list := _saved_color_list()
	list.append(pair)
	_write(SAVED_COLORS, list)
	_refresh_colors()


func _refresh_looks() -> void:
	_looks.clear()
	_looks.add_item("Load a saved look…")
	for l: Dictionary in _read(SAVED_LOOKS):
		_looks.add_item(String(l.get("name", "Look")))
	_looks.select(0)


func _save_look() -> void:
	var list := _read(SAVED_LOOKS)
	list.append({"name": "Look %d" % (list.size() + 1), "portrait": get_portrait()})
	_write(SAVED_LOOKS, list)
	_refresh_looks()


func _load_look(i: int) -> void:
	var list := _read(SAVED_LOOKS)
	if i <= 0 or i > list.size():
		return
	portrait = PortraitSpec.normalize((list[i - 1] as Dictionary).get("portrait", {})).duplicate(true)
	_refresh_all()


## A small pin button: filled when the part is locked.
class LockPin extends Control:
	signal toggled_lock
	var locked := false

	func _init() -> void:
		custom_minimum_size = Vector2(26, 30)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			locked = not locked
			queue_redraw()
			toggled_lock.emit()

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y * 0.42)
		var col := Color(0.95, 0.72, 0.3) if locked else Color(0.4, 0.45, 0.52)
		draw_line(c, c + Vector2(0, 11), col, 2.0, true)
		if locked:
			draw_circle(c, 6.0, col)
		else:
			draw_arc(c, 6.0, 0, TAU, 20, col, 1.6, true)
