class_name MapEditor
extends Node3D
## The map editor (scenes/editor/map_editor.tscn): paint height and terrain, pick the world's
## look and weather, lay out deployment zones and sitrep objectives, watch the fairness
## checker, save and load maps (user://maps/). Works before a mission (start_prep) and live as
## the human GM during one (start_live): every change is a GM action (MapEditorModel), so live
## edits reach every seat in its filtered view. Live, the host forwards `edited` events.
##
## Mouse: left-drag paints with the current tool; right-drag / Q E rotate; wheel zooms; WASD pans.
## Keys: 1-8 pick tools, [ ] brush size, M mirror painting, Ctrl+S save.

signal edited(events: Array)
signal play_requested(doc: MapDoc)

## Map sizes offered (width x height): from small skirmishes to the biggest generated maps.
const SIZES := [[24, 22], [30, 30], [36, 40], [44, 48], [50, 56], [60, 60]]

var model := MapEditorModel.new()
var view: BattleView
var tool := "preset"
var radius := 0
var _ui: CanvasLayer
var _panel: PanelContainer
var _status: Label
var _fair: RichTextLabel
var _tool_buttons := {}
var _preset_pick: OptionButton
var _zone_pick: OptionButton
var _level_spin: SpinBox
var _radius_spin: SpinBox
var _mirror: CheckBox
var _land_pick: OptionButton
var _culture_pick: OptionButton
var _weather_pick: OptionButton
var _sitrep_pick: OptionButton
var _name_edit: LineEdit
var _load_pick: OptionButton
var _size_pick: OptionButton
var _shape_pick: OptionButton
var _seed_spin: SpinBox
var _hover: MeshInstance3D
var _stroke: Array[Vector2i] = []
var _painting := false
var _db: ContentDB


func _ready() -> void:
	view = BattleView.new()
	add_child(view)
	_hover = MeshInstance3D.new()
	_hover.material_override = MeshKit.overlay_material(Color(1.0, 0.9, 0.3, 0.45), true)
	_hover.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_hover)
	_build_ui()
	model.changed.connect(_on_changed)
	if model.doc == null:
		start_prep(MapDoc.generated(1, 36, 40, GridLayout.Shape.HEX, "sitrep_control", "grassy_hills", ""))


## Editing a map before a mission.
func start_prep(doc: MapDoc) -> void:
	model.start_prep(doc)
	_after_load()


## Editing live during a mission as the human GM (host): the mission's engine and state.
func start_live(engine: RulesEngine, state: GameState, kit: String = "grassy_hills") -> void:
	var doc := MapDoc.new()
	var parts := kit.get_slice("+", 0).split("/")
	doc.landscape = parts[0]
	doc.culture = parts[1] if parts.size() > 1 else ""
	doc.weather = kit.get_slice("+", 1) if "+" in kit else ""
	model.start_live(engine, state, doc)
	_after_load()


func _after_load() -> void:
	if view == null:
		return
	view.set_map(model.doc.map, model.doc.kit())
	_show_objectives()
	_hover.mesh = null
	_sync_controls()
	_update_fairness()
	_status_text("Live edit: changes go to every player." if model.live else "Editing %s." % model.doc.name)


func _show_objectives() -> void:
	view.terrain.show_objectives(model.doc.zones, model.doc.deployment, true)


func _on_changed(events: Array) -> void:
	edited.emit(events)
	var terrain := false
	for e: Dictionary in events:
		if str(e.get("type", "")) == "terrain_edited":
			terrain = true
	if terrain:
		view.refresh_map(model.state.map)
	_show_objectives()
	_update_fairness()


# --- Painting -----------------------------------------------------------------------------

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			_painting = true
			_stroke.clear()
			_add_to_stroke((ev as InputEventMouseButton).position)
		elif _painting:
			_painting = false
			_finish_stroke()
		get_viewport().set_input_as_handled()
	elif ev is InputEventMouseMotion:
		var cells := _cells_at((ev as InputEventMouseMotion).position)
		_draw_hover(cells)
		if _painting:
			_add_to_stroke((ev as InputEventMouseMotion).position)
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		var k := (ev as InputEventKey).keycode
		if k >= KEY_1 and k <= KEY_8:
			_set_tool(MapEditorModel.TOOLS[k - KEY_1])
		elif k == KEY_BRACKETLEFT:
			_radius_spin.value -= 1
		elif k == KEY_BRACKETRIGHT:
			_radius_spin.value += 1
		elif k == KEY_M:
			_mirror.button_pressed = not _mirror.button_pressed
		elif k == KEY_S and (ev as InputEventKey).ctrl_pressed:
			_save()


func _cells_at(screen: Vector2) -> Array[Vector2i]:
	var c: Variant = pick_cell(screen)
	if c == null:
		return []
	model.symmetric = _mirror.button_pressed
	return model.brush(c, radius)


## The board cell under a screen point: march along the camera ray until it meets a column.
func pick_cell(screen: Vector2) -> Variant:
	var cam := get_viewport().get_camera_3d()
	if cam == null or model.state == null:
		return null
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	var map := model.state.map
	var t := 0.0
	while t < 300.0:
		var p := from + dir * t
		var c := map.grid.from_world(p)
		if map.has_cell(c) and p.y <= map.ground_height(c) * GridLayout.LEVEL_HEIGHT + 0.01:
			return c
		if p.y < -1.0:
			break
		t += 0.05
	return null


func _add_to_stroke(screen: Vector2) -> void:
	for c in _cells_at(screen):
		if not _stroke.has(c):
			_stroke.append(c)
	_draw_hover(_stroke)


func _finish_stroke() -> void:
	if _stroke.is_empty():
		return
	var events := model.paint(_stroke, tool)
	if events.is_empty() and model.last_error != "":
		_status_text("Refused: " + model.last_error)
	else:
		_status_text("%s on %d space%s." % [tool.capitalize(), _stroke.size(), "" if _stroke.size() == 1 else "s"])
	_stroke.clear()


func _draw_hover(cells: Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color.WHITE)
	for c: Vector2i in cells:
		view.terrain.add_cell_fill(st, c, view.terrain.top_y(c) + 0.04, 0.08)
	_hover.mesh = st.commit() if not cells.is_empty() else null


# --- UI -------------------------------------------------------------------------------------

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	add_child(_ui)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.1, 0.92)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.position = Vector2(10, 10)
	_panel.custom_minimum_size = Vector2(330, 0)
	_ui.add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(330, 860)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(310, 0)
	box.add_theme_constant_override("separation", 4)
	scroll.add_child(box)

	_header(box, "MAP EDITOR")
	_status = _label(box, "", 12, Color(0.75, 0.85, 0.95))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_header(box, "Paint")
	var grid := GridContainer.new()
	grid.columns = 4
	box.add_child(grid)
	var names := {"raise": "Raise", "lower": "Lower", "level": "Level", "preset": "Terrain", "destructible": "Breakable",
		"sturdy": "Sturdy", "zone": "Zone", "unzone": "Unzone"}
	for i in range(MapEditorModel.TOOLS.size()):
		var t: String = MapEditorModel.TOOLS[i]
		var b := Button.new()
		b.text = "%d %s" % [i + 1, names[t]]
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(_set_tool.bind(t))
		grid.add_child(b)
		_tool_buttons[t] = b
	_preset_pick = _option(box, "Terrain", MapEditorModel.PRESETS.keys(), func(i: int) -> void:
		model.preset = MapEditorModel.PRESETS.keys()[i]
		_set_tool("preset"))
	_level_spin = _spin(box, "Level to", 0, GmMapActions.MAX_GROUND, 1, func(v: float) -> void: model.level_to = int(v))
	_zone_pick = _option(box, "Zone", [], func(i: int) -> void:
		model.zone = _zone_pick.get_item_text(i)
		_set_tool("zone"))
	_radius_spin = _spin(box, "Brush size", 0, 3, 0, func(v: float) -> void: radius = int(v))
	_mirror = CheckBox.new()
	_mirror.text = "Mirror through the center (keeps it fair)"
	_mirror.add_theme_font_size_override("font_size", 12)
	box.add_child(_mirror)

	_header(box, "Fairness")
	_fair = RichTextLabel.new()
	_fair.bbcode_enabled = true
	_fair.fit_content = true
	_fair.custom_minimum_size = Vector2(300, 0)
	_fair.add_theme_font_size_override("normal_font_size", 12)
	box.add_child(_fair)

	_header(box, "World")
	_land_pick = _option(box, "Landscape", WorldStyle.landscapes(), func(_i: int) -> void: _apply_look())
	_culture_pick = _option(box, "Culture", ["(none)"] + WorldStyle.cultures(), func(_i: int) -> void: _apply_look())
	_weather_pick = _option(box, "Weather", WorldStyle.weathers(), func(_i: int) -> void: _apply_look())
	var sitreps: Array = []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/lancer-data/sitreps.json"))
	for s: Dictionary in (parsed if parsed is Array else []):
		sitreps.append(str(s["id"]))
	_sitrep_pick = _option(box, "Sitrep", sitreps, func(_i: int) -> void: pass)
	_button(box, "Lay out zones for this sitrep", func() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = int(_seed_spin.value)
		model.relayout(_sitrep_pick.get_item_text(_sitrep_pick.selected), rng)
		_sync_controls())

	_header(box, "Map")
	_size_pick = _option(box, "Size", SIZES.map(func(n: Array) -> String: return "%d x %d" % [n[0], n[1]]), func(_i: int) -> void: pass)
	_shape_pick = _option(box, "Grid", ["hex", "square"], func(_i: int) -> void: pass)
	_seed_spin = _spin(box, "Seed", 1, 99999, 1, func(_v: float) -> void: pass)
	var row := HBoxContainer.new()
	box.add_child(row)
	_button(row, "New blank", func() -> void: _new_map(false))
	_button(row, "Generate", func() -> void: _new_map(true))
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "map name"
	box.add_child(_name_edit)
	var row2 := HBoxContainer.new()
	box.add_child(row2)
	_button(row2, "Save", _save)
	_load_pick = OptionButton.new()
	_load_pick.custom_minimum_size = Vector2(140, 0)
	row2.add_child(_load_pick)
	_button(row2, "Load", _load)
	_button(box, "Play this map", func() -> void: play_requested.emit(model.doc))
	_label(box, "Left-drag paints. Right-drag / Q E rotate, wheel zooms, WASD pans. 1-8 tools, [ ] brush, M mirror, Ctrl+S save.", 11, Color(0.6, 0.66, 0.72)).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_set_tool("preset")
	_refresh_saved()


func _header(parent: Control, text: String) -> void:
	var l := _label(parent, text, 14, Color(1.0, 0.78, 0.35))
	l.add_theme_constant_override("outline_size", 0)


func _label(parent: Control, text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.custom_minimum_size = Vector2(300, 0)
	parent.add_child(l)
	return l


func _option(parent: Control, label: String, items: Array, on_pick: Callable) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(90, 0)
	l.add_theme_font_size_override("font_size", 12)
	row.add_child(l)
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(210, 0)
	o.add_theme_font_size_override("font_size", 12)
	for it: Variant in items:
		o.add_item(str(it))
	o.item_selected.connect(on_pick)
	row.add_child(o)
	return o


func _spin(parent: Control, label: String, lo: float, hi: float, value: float, on_change: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(90, 0)
	l.add_theme_font_size_override("font_size", 12)
	row.add_child(l)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = value
	s.value_changed.connect(on_change)
	row.add_child(s)
	return s


func _button(parent: Control, text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(on_press)
	parent.add_child(b)
	return b


func _set_tool(t: String) -> void:
	tool = t
	for k: String in _tool_buttons:
		(_tool_buttons[k] as Button).button_pressed = k == t


func _select(o: OptionButton, text: String) -> void:
	for i in range(o.item_count):
		if o.get_item_text(i) == text:
			o.select(i)
			return


func _sync_controls() -> void:
	var d := model.doc
	_select(_land_pick, d.landscape)
	_select(_culture_pick, d.culture if d.culture != "" else "(none)")
	_select(_weather_pick, d.weather if d.weather != "" else "clear")
	_select(_sitrep_pick, d.sitrep)
	_name_edit.text = d.name if d.name != "untitled" else ""
	_zone_pick.clear()
	for z: String in model.zone_choices():
		_zone_pick.add_item(z)
	_select(_zone_pick, model.zone)
	for n in [_land_pick, _culture_pick, _weather_pick, _size_pick, _shape_pick]:
		(n as OptionButton).disabled = model.live and n != _weather_pick
	_seed_spin.editable = not model.live


func _apply_look() -> void:
	var d := model.doc
	d.landscape = _land_pick.get_item_text(_land_pick.selected)
	var cult := _culture_pick.get_item_text(_culture_pick.selected)
	d.culture = "" if cult == "(none)" else cult
	var w := _weather_pick.get_item_text(_weather_pick.selected)
	d.weather = "" if w == "clear" else w
	view.set_map(model.state.map, d.kit())
	_show_objectives()


func _update_fairness() -> void:
	var lines: Array = []
	for l: Dictionary in model.fairness_lines():
		lines.append("[color=%s]%s[/color] %s" % ["#7ee08a" if l["ok"] else "#ff8a6a", "OK" if l["ok"] else "!!", l["text"]])
	_fair.text = "\n".join(lines)


func _status_text(t: String) -> void:
	_status.text = t


func _new_map(generate: bool) -> void:
	if model.live:
		_status_text("Can't replace the map during a mission.")
		return
	var n: Array = SIZES[_size_pick.selected]
	var shape := GridLayout.Shape.SQUARE if _shape_pick.selected == 1 else GridLayout.Shape.HEX
	var sitrep := _sitrep_pick.get_item_text(_sitrep_pick.selected)
	var doc: MapDoc
	if generate:
		var cult := _culture_pick.get_item_text(_culture_pick.selected)
		doc = MapDoc.generated(int(_seed_spin.value), n[0], n[1], shape, sitrep, _land_pick.get_item_text(_land_pick.selected), "" if cult == "(none)" else cult)
	else:
		doc = MapDoc.blank(n[0], n[1], shape, sitrep)
		doc.landscape = _land_pick.get_item_text(_land_pick.selected)
	start_prep(doc)


func _save() -> void:
	model.doc.name = _name_edit.text if _name_edit.text.strip_edges() != "" else "untitled"
	var err := model.doc.save()
	_status_text("Saved %s." % MapDoc.safe_name(model.doc.name) if err == OK else "Couldn't save (error %d)." % err)
	_refresh_saved()


func _load() -> void:
	if model.live or _load_pick.item_count == 0:
		return
	var d := MapDoc.load_named(_load_pick.get_item_text(_load_pick.selected))
	if d:
		start_prep(d)


func _refresh_saved() -> void:
	_load_pick.clear()
	for n: String in MapDoc.list():
		_load_pick.add_item(n)


# --- Screenshots ------------------------------------------------------------------------------

func screenshot_setup(args: Array) -> Array:
	return args if not args.is_empty() else ["editor"]


func screenshot_stage(tag: String) -> void:
	match tag:
		"paint":
			# A woods line and a raised ridge, mirrored, with the hover brush showing.
			model.symmetric = true
			_mirror.button_pressed = true
			var cells: Array[Vector2i] = []
			for k in range(6):
				cells.append_array(model.brush(SitrepLayout.cell_of(6 + k, 9, model.state.map.grid.shape), 0))
			model.preset = "woods (soft cover, difficult)"
			model.paint(cells, "preset")
			var ridge: Array[Vector2i] = []
			for k in range(4):
				ridge.append_array(model.brush(SitrepLayout.cell_of(14 + k, 11, model.state.map.grid.shape), 0))
			model.paint(ridge, "raise")
			model.paint(ridge, "raise")
			_status_text("Painted woods and a ridge, mirrored.")
			_draw_hover(model.brush(SitrepLayout.cell_of(10, 14, model.state.map.grid.shape), 1))
		"live":
			var g := MissionGenerator.generate(7, {"size": 24, "sitrep": "sitrep_control", "landscape": "city", "culture": "ruins"})
			var engine := RulesEngine.new()
			var state: GameState = g["state"]
			start_live(engine, state, str((g["mission"] as Mission).flavor.get("kit", "city/ruins")))
			for u: Unit in state.units.values():
				view.add_unit(u.to_dict())
			var bad := model.paint([state.units.values()[0].cell], "raise")
			_status_text("Live edit: changes go to every player. Last: %s" % ("refused, " + model.last_error if bad.is_empty() else "ok"))
	view.tactical.pitch = -50
	view.tactical.snap()
	await get_tree().process_frame
