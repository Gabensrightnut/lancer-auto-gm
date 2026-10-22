class_name TurnOrderBar
extends Control
## Turn order across the top (DESIGN "Play feel"): a portrait for every unit, grouped by
## side, showing who has acted this round, whose turn it is, and which side picks next.
## Lancer has sides alternate and the players choose among themselves, so each ready ally
## shows an "I'll go" button when it's the players' pick.
## Data: {"round", "picking_side", "local_side", "units": [{"id", "name", "side",
## "acted", "active", "hp": [cur, max] (optional), "frame": frame id}]}.

signal i_will_go(unit_id: String)

const SIDE_COLORS := {"players": Color(0.3, 0.75, 1.0), "enemies": Color(1.0, 0.32, 0.27)}

var data: Dictionary = {}
var portraits: Dictionary = {}  # unit id -> Texture2D
var _box: HBoxContainer
var _banner: Label
var _zone: Control


func _init() -> void:
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = HBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	add_child(_box)
	# Nameplates fade under the portraits, buttons and banner (LabelDeclutter).
	_zone = Control.new()
	_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zone.add_to_group(LabelDeclutter.GROUP_KEEPOUT)
	add_child(_zone)
	_banner = Label.new()
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_constant_override("outline_size", 6)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	add_child(_banner)


func set_data(d: Dictionary) -> void:
	data = d
	_rebuild()


func _rebuild() -> void:
	for c in _box.get_children():
		c.queue_free()
	var vp := get_viewport_rect().size if is_inside_tree() else Vector2(1920, 1080)
	var px := clampf(vp.y * 0.065, 48, 110)
	var units: Array = data.get("units", [])
	var picking := String(data.get("picking_side", ""))
	var local := String(data.get("local_side", "players"))
	for side: String in ["players", "enemies"]:
		var any := false
		for u: Dictionary in units:
			if u.get("side") != side:
				continue
			any = true
			_box.add_child(_portrait(u, px, picking == side and side == local))
		if any and side == "players":
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(px * 0.6, 0)
			_box.add_child(gap)
	_center_box.call_deferred()
	var col: Color = SIDE_COLORS.get(picking, Color.WHITE)
	_banner.text = "ROUND %d  ·  %s PICK NEXT" % [int(data.get("round", 1)), "PLAYERS" if picking == "players" else "ENEMIES"]
	if data.get("active_name", "") != "":
		_banner.text = "ROUND %d  ·  %s's TURN" % [int(data.get("round", 1)), String(data["active_name"]).to_upper()]
	_banner.add_theme_color_override("font_color", col.lightened(0.3))
	_banner.add_theme_font_size_override("font_size", int(px * 0.24))
	# Below the "I'll go" buttons, sized to its text so nameplates only fade right under it.
	_banner.size = Vector2.ZERO
	_banner.reset_size()
	_banner.position = Vector2((vp.x - _banner.size.x) * 0.5, 8 + px * 1.62 + px * 0.42)


func _center_box() -> void:
	var vp := get_viewport_rect().size
	_box.reset_size()
	_box.position = Vector2((vp.x - _box.size.x) / 2.0, 8)
	var r := Rect2(_box.position, _box.size).merge(Rect2(_banner.position, _banner.size))
	_zone.position = r.position
	_zone.size = r.size


func _portrait(u: Dictionary, px: float, can_pick: bool) -> Control:
	var col: Color = SIDE_COLORS.get(u.get("side", ""), Color.WHITE)
	var acted := bool(u.get("acted", false))
	var active := bool(u.get("active", false))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var frame := Panel.new()
	frame.custom_minimum_size = Vector2(px, px * 1.15)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.92)
	sb.border_color = col if not acted else col.darkened(0.6)
	sb.set_border_width_all(4 if active else 2)
	if active:
		sb.border_color = Color(1.0, 0.85, 0.35)
	sb.set_corner_radius_all(4)
	frame.add_theme_stylebox_override("panel", sb)
	frame.tooltip_text = String(u.get("name", ""))
	var tex: Texture2D = portraits.get(u.get("id", ""))
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.position = Vector2(3, 3)
		tr.size = Vector2(px - 6, px * 1.15 - 6)
		tr.modulate = Color(0.45, 0.45, 0.5) if acted else Color.WHITE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(tr)
	var hp: Array = u.get("hp", [])
	if hp.size() == 2:
		var bar := ColorRect.new()
		bar.color = Color(0.35, 0.9, 0.55) if not acted else Color(0.25, 0.45, 0.3)
		bar.position = Vector2(4, px * 1.15 - 8)
		bar.size = Vector2((px - 8) * clampf(float(hp[0]) / maxf(1.0, float(hp[1])), 0.0, 1.0), 4)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(bar)
	if acted:
		var done := Label.new()
		done.text = "✓"
		done.add_theme_font_size_override("font_size", int(px * 0.3))
		done.add_theme_color_override("font_color", Color(0.75, 0.8, 0.85))
		done.position = Vector2(px - px * 0.32, 0)
		frame.add_child(done)
	box.add_child(frame)
	var name := Label.new()
	name.text = String(u.get("name", ""))
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.custom_minimum_size = Vector2(px, 0)
	name.clip_text = true
	name.add_theme_font_size_override("font_size", int(px * 0.16))
	name.add_theme_color_override("font_color", col.lightened(0.35) if not acted else Color(0.5, 0.5, 0.55))
	name.add_theme_constant_override("outline_size", 4)
	name.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	box.add_child(name)
	if can_pick and not acted and not active:
		var b := Button.new()
		b.text = "I'll go"
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", int(px * 0.17))
		b.pressed.connect(func() -> void: i_will_go.emit(String(u.get("id", ""))))
		box.add_child(b)
	return box


## Renders a head-and-shoulders portrait of a model into a texture (once). Keeps the
## SubViewport alive as a child of `host`.
static func render_portrait(host: Node, model: Node3D, height: float) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(160, 184)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	host.add_child(vp)
	var root := Node3D.new()
	vp.add_child(root)
	root.add_child(model)
	model.rotation_degrees.y = 200
	var cam := Camera3D.new()
	cam.fov = 30
	root.add_child(cam)
	cam.position = Vector3(0, height * 0.72, -height * 1.6)
	cam.look_at(Vector3(0, height * 0.62, 0))
	cam.current = true
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 160, 0)
	key.light_energy = 2.6
	root.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, -20, 0)
	rim.light_energy = 1.2
	rim.light_color = Color(0.5, 0.75, 1.0)
	root.add_child(rim)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.63, 0.7)
	e.ambient_light_energy = 1.4
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = e
	root.add_child(env)
	return vp.get_texture()
