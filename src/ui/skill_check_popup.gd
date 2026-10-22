class_name SkillCheckPopup
extends Control
## BG3-style big skill check: the scene dims, a large d20 tumbles and lands center screen,
## then the skill trigger bonus, blue Accuracy / red Difficulty dice with their sources, the
## target number, and SUCCESS / FAILURE. Input: a `skill_check` event's `check` record
## (Dice.check plus `skill`, `label`, `bonus_sources`, `sources`). Speed follows Fx.speed.

var _d20_value := 20
var _d20_spin := 0.0
var _d20_scale := 1.0
var _show_d20 := false
var _box: VBoxContainer
var _title: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_constant_override("outline_size", 8)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_title.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	add_child(_title)
	_box = VBoxContainer.new()
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_theme_constant_override("separation", 10)
	add_child(_box)


func _vp() -> Vector2:
	return get_viewport_rect().size


func _draw() -> void:
	var vp := _vp()
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.55))
	if not _show_d20:
		return
	var c := Vector2(vp.x / 2.0, vp.y * 0.38)
	var r := vp.y * 0.13 * _d20_scale
	# An icosahedron seen face-on: hexagon outline, inner triangle and spokes.
	var outer := PackedVector2Array()
	for i in range(6):
		var a := _d20_spin + TAU * i / 6.0 - PI / 2.0
		outer.append(c + Vector2(cos(a), sin(a)) * r)
	var inner := PackedVector2Array()
	for i in range(3):
		var a := _d20_spin + TAU * i / 3.0 - PI / 2.0
		inner.append(c + Vector2(cos(a), sin(a)) * r * 0.62)
	draw_colored_polygon(outer, Color(0.1, 0.12, 0.18))
	draw_colored_polygon(inner, Color(0.16, 0.2, 0.3))
	var line := Color(0.75, 0.85, 1.0)
	outer.append(outer[0])
	draw_polyline(outer, line, 3.0, true)
	inner.append(inner[0])
	draw_polyline(inner, line, 2.0, true)
	for i in range(6):
		draw_line(outer[i], inner[i / 2] if i % 2 == 0 else inner[(i / 2 + 1) % 3], Color(line, 0.6), 1.5)
	var font := get_theme_default_font()
	var fs := int(r * 0.55)
	var txt := str(_d20_value)
	draw_string_outline(font, c + Vector2(-r, fs * 0.35), txt, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, 6, Color(0, 0, 0))
	draw_string(font, c + Vector2(-r, fs * 0.35), txt, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, Color.WHITE if _d20_value not in [1, 20] else (Color(1.0, 0.85, 0.3) if _d20_value == 20 else Color(1.0, 0.4, 0.35)))


func _label(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	return l


func _pop(c: Control) -> void:
	if Fx.speed <= 0.0:
		return
	c.modulate.a = 0.0
	c.create_tween().tween_property(c, "modulate:a", 1.0, Fx.t(0.25))


## Plays the check. `hold` keeps it on screen afterwards (screenshots).
func play(check: Dictionary, hold: bool = false) -> void:
	var vp := _vp()
	visible = true
	for c in _box.get_children():
		c.queue_free()
	_title.text = String(check.get("label", check.get("skill", "Skill check"))).to_upper()
	_title.add_theme_font_size_override("font_size", int(vp.y * 0.04))
	_title.position = Vector2(0, vp.y * 0.12)
	_title.size = Vector2(vp.x, vp.y * 0.06)
	_box.position = Vector2(0, vp.y * 0.55)
	_box.size = Vector2(vp.x, vp.y * 0.3)
	_show_d20 = true
	var final := int(check.get("d20", 10))
	if Fx.speed > 0.0:
		for i in range(14):
			_d20_value = (final + i * 7) % 20 + 1
			_d20_spin = i * 0.45
			_d20_scale = 0.8 + 0.25 * sin(i * 0.9)
			queue_redraw()
			await get_tree().create_timer(Fx.t(0.06)).timeout
	_d20_value = final
	_d20_spin = 0.0
	_d20_scale = 1.0
	queue_redraw()
	await Fx.wait(self, 0.4)
	var fs := int(vp.y * 0.03)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	_box.add_child(row)
	for b: Dictionary in check.get("bonus_sources", check.get("bonuses", [])):
		var n := int(b.get("value", 0))
		var l := _label("%s%d %s" % ["+" if n >= 0 else "−", absi(n), b.get("label", "")], Color(0.92, 0.94, 0.97), fs)
		row.add_child(l)
		_pop(l)
		await Fx.wait(self, 0.3)
	var src := RollDisplay.expand_sources(check)
	for lbl: String in src["accuracy"]:
		var l := _label("+1 " + lbl, RollDisplay.BLUE.lightened(0.2), fs)
		row.add_child(l)
		_pop(l)
		await Fx.wait(self, 0.2)
	for lbl: String in src["difficulty"]:
		var l := _label("−1 " + lbl, RollDisplay.RED.lightened(0.2), fs)
		row.add_child(l)
		_pop(l)
		await Fx.wait(self, 0.2)
	var ar: Dictionary = check.get("accuracy_roll", {})
	if int(ar.get("value", 0)) != 0:
		var v := int(ar["value"])
		var l := _label("%s%d (d6)" % ["+" if v > 0 else "−", absi(v)], RollDisplay.BLUE if v > 0 else RollDisplay.RED, int(fs * 1.2))
		row.add_child(l)
		_pop(l)
		await Fx.wait(self, 0.3)
	var total := _label("= %d   vs   %d" % [int(check.get("total", 0)), int(check.get("target", 10))], Color.WHITE, int(fs * 1.4))
	_box.add_child(total)
	_pop(total)
	await Fx.wait(self, 0.4)
	var ok := bool(check.get("success", false))
	var verdict := _label("SUCCESS" if ok else "FAILURE", RollDisplay.HIT if ok else RollDisplay.RED, int(vp.y * 0.07))
	_box.add_child(verdict)
	_pop(verdict)
	if hold:
		return
	await Fx.wait(self, 1.4)
	visible = false
