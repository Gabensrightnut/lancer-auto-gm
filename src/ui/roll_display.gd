class_name RollDisplay
extends Control
## Shows a roll step by step (DESIGN.md "Roll visuals"): the d20 lands, Accuracy (blue +d6)
## and Difficulty (red -d6) sources appear with their labels, matching blue/red pairs fade
## out together, the leftover d6s roll and only the highest counts, flat bonuses are added,
## then the total vs the target and HIT / MISS / CRIT. Speed follows Fx.speed (0 = instant).
## Input: the `check` record from Dice.check(), extended as described in src/render/FORMATS.md.

const BLUE := Color(0.32, 0.62, 1.0)
const RED := Color(1.0, 0.32, 0.28)
const GOLD := Color(1.0, 0.82, 0.3)
const HIT := Color(0.35, 1.0, 0.6)
const MISS := Color(0.7, 0.7, 0.74)

## Keep the last roll on screen (for screenshots and the tutorial).
var hold_result := false

var _panel: PanelContainer
var _box: VBoxContainer
var _busy := false


## A die face: a hexagon for the d20, a rounded square for d6s.
class Die extends Control:
	var sides := 20
	var value := 1
	var color := Color.WHITE
	var dimmed := false

	func _init(s: int, c: Color) -> void:
		sides = s
		color = c
		custom_minimum_size = Vector2(64, 64) if s == 20 else Vector2(40, 40)
		pivot_offset = custom_minimum_size / 2.0

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0 - 2.0
		var pts := PackedVector2Array()
		var n := 6 if sides == 20 else 4
		var rot := -PI / 2.0 if sides == 20 else PI / 4.0
		for i in range(n):
			var a := rot + TAU * i / n
			pts.append(c + Vector2(cos(a), sin(a)) * r * (1.0 if sides == 20 else 1.3))
		var fill := color.darkened(0.55) if not dimmed else Color(0.15, 0.15, 0.17)
		draw_colored_polygon(pts, fill)
		pts.append(pts[0])
		draw_polyline(pts, color if not dimmed else Color(0.4, 0.4, 0.45), 3.0, true)
		var font := get_theme_default_font()
		var fs := 30 if sides == 20 else 22
		var text := str(value)
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(font, c + Vector2(-ts.x / 2.0, ts.y * 0.32), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE if not dimmed else Color(0.5, 0.5, 0.55))


func _init() -> void:
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.88)
	sb.border_color = Color(0.35, 0.55, 0.75, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.visible = false
	add_child(_panel)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	_panel.add_child(_box)


func _center() -> void:
	_panel.reset_size()
	var vp := get_viewport_rect().size
	_panel.position = Vector2((vp.x - _panel.size.x) / 2.0 - position.x, vp.y * 0.17)


func _clear() -> void:
	for c in _box.get_children():
		c.queue_free()
	_panel.visible = true
	_panel.modulate.a = 1.0


func _row() -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_child(h)
	return h


func _text(parent: Control, text: String, color: Color = Color.WHITE, size: int = 20) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


func _chip(parent: Control, text: String, color: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = color.darkened(0.6)
	sb.border_color = color
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	p.add_theme_stylebox_override("panel", sb)
	_text(p, text, color.lightened(0.4), 18)
	parent.add_child(p)
	return p


func _pop(c: Control) -> void:
	c.modulate.a = 0.0
	c.pivot_offset = c.size / 2.0
	if Fx.speed <= 0.0:
		c.modulate.a = 1.0
		return
	var tw := c.create_tween()
	tw.tween_property(c, "modulate:a", 1.0, Fx.t(0.15))
	c.scale = Vector2(1.4, 1.4)
	tw.parallel().tween_property(c, "scale", Vector2.ONE, Fx.t(0.18)).set_ease(Tween.EASE_OUT)


func _wait(seconds: float) -> void:
	await Fx.wait(self, seconds)


func _roll_die(d: Die, final: int) -> void:
	if Fx.speed > 0.0:
		for i in range(8):
			d.value = (final + i * 7) % d.sides + 1  # tumbling faces; the real value comes from the event
			d.queue_redraw()
			await _wait(0.05)
	d.value = final
	d.queue_redraw()
	_pop(d)


## Expands sources into one entry per point: [{label, type}] for "accuracy"/"difficulty".
static func expand_sources(check: Dictionary) -> Dictionary:
	var acc: Array = []
	var diff: Array = []
	for s: Variant in check.get("sources", []):
		var e: Dictionary = s if s is Dictionary else {"label": str(s), "type": "accuracy"}
		var n := int(e.get("value", 1))
		for i in range(absi(n)):
			if String(e.get("kind", e.get("type", "accuracy"))) == "difficulty":
				diff.append(e.get("label", "Difficulty"))
			else:
				acc.append(e.get("label", "Accuracy"))
	var ar: Dictionary = check.get("accuracy_roll", {})
	while acc.size() < int(ar.get("accuracy", 0)):
		acc.append("Accuracy")
	while diff.size() < int(ar.get("difficulty", 0)):
		diff.append("Difficulty")
	return {"accuracy": acc, "difficulty": diff}


## The one-line summary in the design's format, e.g. "6 +4 +2 Grit = 12 vs Evasion 8: HIT".
static func formula_bbcode(check: Dictionary, result: String) -> String:
	var ar: Dictionary = check.get("accuracy_roll", {})
	var out := "%d" % int(check.get("d20", 0))
	var v := int(ar.get("value", 0))
	if v > 0:
		out += " [color=#%s][b]+%d[/b][/color]" % [BLUE.to_html(false), v]
	elif v < 0:
		out += " [color=#%s][b]−%d[/b][/color]" % [RED.to_html(false), -v]
	for b: Dictionary in _bonuses(check):
		var n := int(b["value"])
		out += " %s%d %s" % ["+" if n >= 0 else "−", absi(n), b["label"]]
	out += " = %d" % int(check.get("total", 0))
	if check.has("target"):
		out += " vs %s %d" % [check.get("target_label", "Evasion"), int(check["target"])]
	if result != "":
		out += ": [b]%s[/b]" % result.to_upper()
	return out


static func _bonuses(check: Dictionary) -> Array:
	if check.has("bonuses"):
		return check["bonuses"]
	if check.has("bonus_sources"):
		return check["bonus_sources"]
	var b := int(check.get("bonus", 0))
	return [] if b == 0 else [{"label": "Bonus", "value": b}]


## Plays an attack/check roll. `result` is "hit", "miss" or "crit" (or "success"/"fail").
func play_check(check: Dictionary, result: String, title: String = "") -> void:
	while _busy:
		await get_tree().process_frame
	_busy = true
	_clear()
	if title != "":
		_text(_row(), title, Color(0.8, 0.88, 1.0), 20)
	var r1 := _row()
	var d20 := Die.new(20, Color(0.85, 0.88, 0.95))
	r1.add_child(d20)
	_center()
	await _roll_die(d20, int(check.get("d20", 1)))
	await _wait(0.25)
	# Accuracy and Difficulty sources, one chip per point.
	var src := expand_sources(check)
	var blue_chips: Array = []
	var red_chips: Array = []
	if not (src["accuracy"].is_empty() and src["difficulty"].is_empty()):
		var r2 := _row()
		for label: String in src["accuracy"]:
			var c := _chip(r2, "+1 " + label, BLUE)
			blue_chips.append(c)
		for label: String in src["difficulty"]:
			var c := _chip(r2, "−1 " + label, RED)
			red_chips.append(c)
		_center()
		await get_tree().process_frame
		for c: Control in blue_chips + red_chips:
			_pop(c)
			await _wait(0.12)
		await _wait(0.3)
		# Cancel one for one: matching pairs fade out together.
		var pairs := mini(blue_chips.size(), red_chips.size())
		for i in range(pairs):
			for c: Control in [blue_chips[i], red_chips[i]]:
				if Fx.speed <= 0.0:
					c.modulate.a = 0.2
				else:
					c.create_tween().tween_property(c, "modulate:a", 0.2, Fx.t(0.35))
			await _wait(0.2)
		if pairs > 0:
			await _wait(0.25)
	# Leftover d6s: roll them, keep the highest.
	var ar: Dictionary = check.get("accuracy_roll", {})
	var dice: Array = ar.get("dice", [])
	var tally := _row()
	if not dice.is_empty():
		var color := BLUE if String(ar.get("color", "")) == "blue" else RED
		var dice_nodes: Array = []
		for v: int in dice:
			var d := Die.new(6, color)
			tally.add_child(d)
			dice_nodes.append(d)
		_center()
		for i in range(dice.size()):
			await _roll_die(dice_nodes[i], int(dice[i]))
		var kept := int(ar.get("kept", 0))
		var kept_marked := false
		for i in range(dice.size()):
			if int(dice[i]) == kept and not kept_marked:
				kept_marked = true
			else:
				(dice_nodes[i] as Die).dimmed = true
				(dice_nodes[i] as Die).queue_redraw()
		var sign_text := "+%d" % kept if color == BLUE else "−%d" % kept
		var l := _text(tally, sign_text, color.lightened(0.2), 30)
		_pop(l)
		await _wait(0.35)
	# Flat bonuses.
	for b: Dictionary in _bonuses(check):
		var n := int(b["value"])
		var l := _text(tally, "%s%d %s" % ["+" if n >= 0 else "−", absi(n), b["label"]], Color(0.92, 0.92, 0.95), 24)
		_center()
		_pop(l)
		await _wait(0.25)
	# Total vs target, then the verdict.
	var res_row := _row()
	var total_text := "= %d" % int(check.get("total", 0))
	if check.has("target"):
		total_text += "   vs %s %d" % [String(check.get("target_label", "Evasion")).to_upper(), int(check["target"])]
	var tl := _text(res_row, total_text, Color.WHITE, 28)
	_center()
	_pop(tl)
	await _wait(0.3)
	var verdict := result.to_upper()
	var vcol := HIT
	match result:
		"crit":
			vcol = GOLD
		"miss", "fail", "failure":
			vcol = MISS
	if verdict != "":
		var vl := _text(res_row, "  " + verdict + ("!" if result == "crit" else ""), vcol, 40)
		_center()
		_pop(vl)
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.autowrap_mode = TextServer.AUTOWRAP_OFF
	line.text = "[center]" + formula_bbcode(check, result) + "[/center]"
	line.add_theme_font_size_override("normal_font_size", 16)
	line.add_theme_font_size_override("bold_font_size", 16)
	line.modulate = Color(1, 1, 1, 0.75)
	_box.add_child(line)
	_center()
	await _wait(0.9)
	await _finish()


## Damage roll: dice, bonus, armor, resistance, final damage.
## Accepts a `damage_dealt` event (see FORMATS.md).
func play_damage(e: Dictionary) -> void:
	while _busy:
		await get_tree().process_frame
	_busy = true
	_clear()
	var dtype := String(e.get("damage_type", "Kinetic"))
	_text(_row(), "DAMAGE  ·  " + dtype.to_upper(), damage_color(dtype), 20)
	var row := _row()
	var roll: Dictionary = e.get("roll", {})
	_center()
	for r: Dictionary in roll.get("rolls", []):
		var d := Die.new(int(r.get("sides", 6)), damage_color(dtype))
		row.add_child(d)
		_center()
		await _roll_die(d, absi(int(r.get("value", 0))))
	if int(roll.get("bonus", 0)) != 0:
		_pop(_text(row, "+%d" % int(roll["bonus"]), Color.WHITE, 24))
		await _wait(0.2)
	if int(e.get("armor_reduced", 0)) > 0:
		_pop(_text(row, "−%d Armor" % int(e["armor_reduced"]), RED, 22))
		await _wait(0.2)
	if bool(e.get("resisted", false)):
		_pop(_text(row, "½ Resisted", RED, 22))
		await _wait(0.2)
	var t := _text(row, "= %d" % int(e.get("amount", 0)), Color.WHITE, 30)
	_center()
	_pop(t)
	await _wait(0.7)
	await _finish()


## A titled card for checks with an outcome table (structure, stress, saves).
func show_card(title: String, lines: Array, color: Color) -> void:
	while _busy:
		await get_tree().process_frame
	_busy = true
	_clear()
	_pop(_text(_row(), title, color, 26))
	for l: String in lines:
		var lab := _text(_row(), l, Color(0.9, 0.9, 0.92), 20)
		_center()
		_pop(lab)
		await _wait(0.3)
	_center()
	await _wait(1.0)
	await _finish()


## Hides the panel at once (e.g. when the scene is reset).
func clear_now() -> void:
	_panel.visible = false
	_busy = false


func _finish() -> void:
	if not hold_result:
		if Fx.speed > 0.0:
			var tw := _panel.create_tween()
			tw.tween_property(_panel, "modulate:a", 0.0, Fx.t(0.25))
			await tw.finished
		_panel.visible = false
	_busy = false


static func damage_color(dtype: String) -> Color:
	match dtype:
		"Energy":
			return Color(0.4, 0.85, 1.0)
		"Explosive":
			return Color(1.0, 0.6, 0.2)
		"Burn":
			return Color(1.0, 0.4, 0.15)
		"Heat":
			return Color(1.0, 0.5, 0.1)
	return Color(0.95, 0.92, 0.85)
