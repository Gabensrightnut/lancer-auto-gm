class_name MechPreview
extends VBoxContainer
## The equipped mech in a small 3D studio, with the paint customizer under it.
## Drag to turn the mech, mouse wheel to zoom. The model is always the real loadout; paint is
## cosmetic (MechPaint format).
##
## Plugging it in (e.g. the builder's preview_area):
##   var pv := MechPreview.new()
##   pv.show_paint_controls = true          # false: just the turntable
##   preview_area.add_child(pv)
##   pv.set_mech(db, mech["frame"], mech["loadout"], mech.get("paint", {}))
##   pv.paint_changed.connect(func(p: Dictionary) -> void: mech["paint"] = p)
## Call set_mech again whenever the frame or loadout changes (paint is kept). In battle,
## MechView applies unit["paint"] the same way.

signal paint_changed(paint: Dictionary)

const PRESETS_FILE := "res://data/game/paint_presets.json"
const USER_PRESETS := "user://paint_presets.json"
const SWATCHES := ["primary", "secondary", "glow", "markings"]
const SWATCH_NAMES := {"primary": "Primary", "secondary": "Secondary", "glow": "Glow", "markings": "Markings"}

var show_paint_controls := true:
	set(v):
		show_paint_controls = v
		if _controls:
			_controls.visible = v
## Current paint (only keys that differ from the factory scheme are needed).
var paint: Dictionary = {}

var _db: ContentDB
var _frame: Dictionary = {}
var _loadout: Dictionary = {}
var _vp: SubViewport
var _vpc: SubViewportContainer
var _cam: Camera3D
var _turntable: Node3D
var _model: MechModel
var _yaw := -30.0
var _pitch := -10.0
var _zoom := 1.0
var _dragging := false
var _idle := 0.0
var _slot := "primary"
var _controls: VBoxContainer
var _swatch_buttons: Dictionary = {}
var _presets: OptionButton
var _decal_pickers: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	_vpc = SubViewportContainer.new()
	_vpc.stretch = true
	_vpc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vpc.custom_minimum_size = Vector2(240, 260)
	_vpc.gui_input.connect(_on_view_input)
	add_child(_vpc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = false
	_vp.msaa_3d = Viewport.MSAA_4X
	_vpc.add_child(_vp)
	_build_studio()
	_controls = _build_controls()
	add_child(_controls)


## Shows a frame with a loadout ({"mounts": [{"weapons": [ids]}]}, as the builder stores it).
func set_mech(db: ContentDB, frame_id: String, loadout: Dictionary, mech_paint: Dictionary = {}) -> void:
	_db = db
	_frame = db.frame(frame_id) if db else {}
	if _frame.is_empty():
		_frame = {"id": frame_id, "source": "GMS", "mechtype": ["Balanced"], "stats": {"size": 1}}
	_loadout = loadout
	paint = mech_paint.duplicate(true)
	_rebuild()
	_sync_controls()


func set_paint(p: Dictionary) -> void:
	paint = p.duplicate(true)
	_repaint()
	_sync_controls()


func get_paint() -> Dictionary:
	return paint.duplicate(true)


func reset_paint() -> void:
	set_paint({})
	paint_changed.emit(get_paint())


func randomize_paint(rng: RandomNumberGenerator = null) -> void:
	set_paint(MechPaint.random_paint(rng if rng else _rng))
	paint_changed.emit(get_paint())


## The model on the turntable (for screenshots and tests).
func model() -> MechModel:
	return _model


func _ready() -> void:
	_repaint()  # decals need the model in the tree
	_place_camera()


# --- 3D ------------------------------------------------------------------------------------

func _build_studio() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.035, 0.04, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, -35, 0)
	key.light_energy = 1.6
	key.shadow_enabled = true
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_energy = 1.1
	rim.light_color = Color(0.6, 0.75, 1.0)
	_vp.add_child(rim)
	var floor := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.6
	cyl.bottom_radius = 1.7
	cyl.height = 0.06
	cyl.radial_segments = 48
	floor.mesh = cyl
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.07, 0.075, 0.085)
	fm.metallic = 0.0
	fm.roughness = 0.85
	floor.material_override = fm
	floor.position.y = -0.03
	_vp.add_child(floor)
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 1.58
	tor.outer_radius = 1.62
	tor.rings = 64
	ring.mesh = tor
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.albedo_color = Color(0.35, 0.6, 0.85)
	ring.material_override = rm
	_vp.add_child(ring)
	_turntable = Node3D.new()
	_vp.add_child(_turntable)
	_cam = Camera3D.new()
	_cam.fov = 32.0
	_vp.add_child(_cam)


func _rebuild() -> void:
	if _model:
		_model.queue_free()
		_model = null
	_model = MechBuilder.build(_frame, _loadout, _db)
	_turntable.add_child(_model)
	_repaint()
	_place_camera()


func _repaint() -> void:
	if _model:
		MechPaint.apply(_model, paint)


func _place_camera() -> void:
	if _model == null:
		return
	# Fit the whole model (weapons and antennas included) in view, from the front quarter.
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in _model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh and mi.is_inside_tree():
			var b := mi.global_transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
	if first:
		box = AABB(Vector3(-0.5, 0, -0.5), Vector3(1, _model.height, 1))
	var radius := box.size.length() * 0.5
	var target := box.get_center()
	var aspect := clampf(_vp.size.x / maxf(1.0, float(_vp.size.y)), 0.6, 1.0)
	var dist := radius / sin(deg_to_rad(_cam.fov) * 0.5) / aspect * 0.95 * _zoom
	var rot := Basis.from_euler(Vector3(deg_to_rad(_pitch), deg_to_rad(_yaw + 180.0), 0))
	_cam.transform = Transform3D(rot, target + rot * Vector3(0, 0, dist))


func _process(delta: float) -> void:
	_idle += delta
	if not _dragging and _idle > 3.0:
		_yaw += delta * 12.0  # slow turn when left alone
		_place_camera()


func _on_view_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = clampf(_zoom * 0.9, 0.45, 1.6)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = clampf(_zoom * 1.1, 0.45, 1.6)
		_idle = 0.0
		_place_camera()
	elif e is InputEventMouseMotion and _dragging:
		var mm := e as InputEventMouseMotion
		_yaw -= mm.relative.x * 0.4
		_pitch = clampf(_pitch - mm.relative.y * 0.3, -60.0, 15.0)
		_idle = 0.0
		_place_camera()


# --- paint controls --------------------------------------------------------------------------

func _build_controls() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var hint := _text("Drag to turn  ·  wheel to zoom  ·  paint is cosmetic: the model always shows your real loadout", 12, Color(0.6, 0.66, 0.72))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 200
	box.add_child(hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for s: String in SWATCHES:
		var b := Button.new()
		b.text = SWATCH_NAMES[s]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(96, 30)
		b.pressed.connect(func() -> void: _select_slot(s))
		_swatch_buttons[s] = b
		row.add_child(b)
	box.add_child(row)
	var grid := GridContainer.new()
	grid.columns = 16
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	for c: Color in MechPaint.palette_grid():
		var cb := Button.new()
		cb.custom_minimum_size = Vector2(22, 22)
		cb.focus_mode = Control.FOCUS_NONE
		cb.tooltip_text = "#" + c.to_html(false)
		for st: String in ["normal", "hover", "pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = c
			sb.set_corner_radius_all(3)
			sb.set_border_width_all(2 if st == "hover" else 1)
			sb.border_color = Color.WHITE if st == "hover" else Color(0, 0, 0, 0.6)
			cb.add_theme_stylebox_override(st, sb)
		cb.pressed.connect(func() -> void: _pick_color(c))
		grid.add_child(cb)
	box.add_child(grid)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 6)
	prow.add_child(_text("Preset", 13, Color(0.75, 0.8, 0.85)))
	_presets = OptionButton.new()
	_presets.focus_mode = Control.FOCUS_NONE
	_presets.custom_minimum_size = Vector2(170, 0)
	_presets.item_selected.connect(_on_preset)
	prow.add_child(_presets)
	var save := Button.new()
	save.text = "Save as preset"
	save.focus_mode = Control.FOCUS_NONE
	save.pressed.connect(_save_preset)
	prow.add_child(save)
	box.add_child(prow)
	box.add_child(_text("Markings", 13, Color(0.75, 0.8, 0.85)))
	var dgrid := GridContainer.new()
	dgrid.columns = 4
	dgrid.add_theme_constant_override("h_separation", 6)
	for slot: String in MechPaint.DECAL_SLOTS:
		dgrid.add_child(_text(MechPaint.SLOT_NAMES[slot], 12, Color(0.7, 0.75, 0.8)))
		var ob := OptionButton.new()
		ob.focus_mode = Control.FOCUS_NONE
		for id: String in MechPaint.DECALS:
			ob.add_item(MechPaint.DECAL_NAMES[id])
		ob.item_selected.connect(func(i: int) -> void: _set_decal(slot, MechPaint.DECALS[i]))
		_decal_pickers[slot] = ob
		dgrid.add_child(ob)
	box.add_child(dgrid)
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	for pair: Array in [["Randomize", func() -> void: randomize_paint()], ["Reset to factory", reset_paint]]:
		var b := Button.new()
		b.text = pair[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(130, 30)
		b.pressed.connect(pair[1])
		brow.add_child(b)
	box.add_child(brow)
	_select_slot("primary")
	return box


func _text(t: String, px: int, col: Color) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", col)
	return l


func _select_slot(s: String) -> void:
	_slot = s
	for k: String in _swatch_buttons:
		(_swatch_buttons[k] as Button).button_pressed = k == s


func _pick_color(c: Color) -> void:
	paint[_slot] = "#" + c.to_html(false)
	_repaint()
	_sync_controls()
	paint_changed.emit(get_paint())


func _set_decal(slot: String, id: String) -> void:
	var d: Dictionary = paint.get("decals", {})
	if id == "number":
		id = "number:%02d" % _rng.randi_range(1, 99)
	d[slot] = id
	paint["decals"] = d
	_repaint()
	paint_changed.emit(get_paint())


## Every preset: factory first, then data/game presets, then the player's saved ones.
func presets() -> Array:
	var out: Array = [{"name": "Factory (%s)" % _frame.get("source", "GMS")}]
	var f := FileAccess.open(PRESETS_FILE, FileAccess.READ)
	if f:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			out.append_array((d as Dictionary).get("presets", []))
	var u := FileAccess.open(USER_PRESETS, FileAccess.READ)
	if u:
		var ud: Variant = JSON.parse_string(u.get_as_text())
		if ud is Array:
			out.append_array(ud)
	return out


func _on_preset(i: int) -> void:
	var list := presets()
	if i <= 0 or i >= list.size():
		var keep: Dictionary = paint.get("decals", {})
		set_paint({"decals": keep})
	else:
		var p: Dictionary = (list[i] as Dictionary).duplicate()
		p.erase("name")
		p["decals"] = paint.get("decals", {})
		set_paint(p)
	paint_changed.emit(get_paint())


func _save_preset() -> void:
	var saved: Array = []
	var u := FileAccess.open(USER_PRESETS, FileAccess.READ)
	if u:
		var ud: Variant = JSON.parse_string(u.get_as_text())
		if ud is Array:
			saved = ud
		u.close()
	var p := get_paint()
	p.erase("decals")
	p["name"] = "My scheme %d" % (saved.size() + 1)
	saved.append(p)
	var w := FileAccess.open(USER_PRESETS, FileAccess.WRITE)
	if w:
		w.store_string(JSON.stringify(saved, "  "))
	_sync_controls()


func _sync_controls() -> void:
	if _frame.is_empty():
		return
	var fac := MechPaint.factory(_frame)
	if _model:
		fac.merge(MechPaint.model_colors(_model), true)
	for s: String in SWATCHES:
		var c := Color(String(paint.get(s, fac[s])))
		var b: Button = _swatch_buttons[s]
		for st: String in ["normal", "hover", "pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = c.darkened(0.15)
			sb.set_corner_radius_all(4)
			sb.set_border_width_all(3 if st == "pressed" else 1)
			sb.border_color = Color.WHITE if st == "pressed" else Color(0, 0, 0, 0.7)
			b.add_theme_stylebox_override(st, sb)
		var txt := Color.BLACK if c.get_luminance() > 0.5 else Color.WHITE
		for k: String in ["font_color", "font_hover_color", "font_pressed_color"]:
			b.add_theme_color_override(k, txt)
	var names: Array = []
	for p: Dictionary in presets():
		names.append(String(p.get("name", "?")))
	var sel := _presets.selected
	_presets.clear()
	for n: String in names:
		_presets.add_item(n)
	_presets.select(clampi(sel, 0, names.size() - 1))
	var d: Dictionary = paint.get("decals", {})
	for slot: String in _decal_pickers:
		var id := String(d.get(slot, "")).get_slice(":", 0)
		(_decal_pickers[slot] as OptionButton).select(maxi(0, MechPaint.DECALS.find(id)))
