class_name ResourceHUD
extends Control
## Always-visible resources for the active unit (DESIGN.md "Resource HUD and action buttons"):
## HP, Overshield, Heat with the Danger Zone mark, Structure, Stress, Repairs, Burn, core
## power, and the turn's action economy. Hovering an action previews its cost here.
## Draws only the values it's given (format in src/render/FORMATS.md); "??" when unknown.

const W := 380.0
const BAR_X := 110.0
const BAR_W := 190.0
const ROW_H := 26.0
const HP_COL := Color(0.35, 0.9, 0.55)
const OS_COL := Color(0.45, 0.85, 1.0)
const HEAT_COL := Color(1.0, 0.5, 0.15)
const DZ_COL := Color(1.0, 0.25, 0.2)

var data: Dictionary = {}
## The hovered action's cost: {"heat": 2 or [1, 3], "quick": 1, "full": 1, "reaction": 1,
## "move": n, "repairs": 1, "core_power": 1, "overshield": n, "hp": -n}
var preview: Dictionary = {}

var _economy: HBoxContainer
var _pulse := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W, 330)
	_economy = HBoxContainer.new()
	_economy.add_theme_constant_override("separation", 10)
	add_child(_economy)


func set_data(d: Dictionary) -> void:
	data = d
	_rebuild_economy()
	queue_redraw()


func set_preview(p: Dictionary) -> void:
	preview = p
	_rebuild_economy()
	queue_redraw()


func _process(delta: float) -> void:
	if not preview.is_empty():
		_pulse += delta
		queue_redraw()


func _pair(key: String) -> Array:
	var v: Variant = data.get(key)
	if v is Array and (v as Array).size() >= 2:
		return [int(v[0]), int(v[1])]
	return []


func _rows() -> Array:
	var rows: Array = ["hp"]
	if int(data.get("overshield", 0)) > 0 or preview.has("overshield"):
		rows.append("overshield")
	rows.append_array(["heat", "structure", "stress", "repairs"])
	if int(data.get("burn", 0)) > 0:
		rows.append("burn")
	rows.append("core_power")
	return rows


func _draw() -> void:
	var font := get_theme_default_font()
	var rows := _rows()
	var h := 44.0 + rows.size() * ROW_H + 74.0
	custom_minimum_size.y = h
	draw_rect(Rect2(0, 0, W, h), Color(0.04, 0.05, 0.07, 0.85))
	draw_rect(Rect2(0, 0, W, h), Color(0.35, 0.55, 0.75, 0.6), false, 1.5)
	draw_rect(Rect2(0, 0, 4, h), Color(0.3, 0.75, 1.0))
	draw_string(font, Vector2(14, 26), String(data.get("name", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	draw_string(font, Vector2(14 + 10 + font.get_string_size(String(data.get("name", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x, 26), String(data.get("frame", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.7, 0.8))
	var y := 44.0
	for key: String in rows:
		_row(font, key, y)
		y += ROW_H
	_economy.position = Vector2(12, y + 8)
	# Warnings from the hovered action.
	var warn := _warning()
	if warn != "":
		var a := 0.65 + 0.35 * sin(_pulse * 8.0)
		draw_string(font, Vector2(14, h - 12), warn, HORIZONTAL_ALIGNMENT_LEFT, W, 16, Color(DZ_COL.r, DZ_COL.g, DZ_COL.b, a))


func _row(font: Font, key: String, y: float) -> void:
	var label := {"hp": "HP", "overshield": "OVERSHIELD", "heat": "HEAT", "structure": "STRUCTURE",
		"stress": "STRESS", "repairs": "REPAIRS", "burn": "BURN", "core_power": "CORE POWER"}[key] as String
	draw_string(font, Vector2(14, y + 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.65, 0.8, 0.92))
	match key:
		"hp":
			_bar(font, y, _pair("hp"), HP_COL, int(_preview_num("hp")))
		"overshield":
			var os := int(data.get("overshield", 0))
			_bar(font, y, [os, maxi(os + int(_preview_num("overshield")), 1)], OS_COL, int(_preview_num("overshield")))
		"heat":
			var p := _pair("heat")
			_bar(font, y, p, HEAT_COL, 0, _heat_preview())
			if not p.is_empty() and data.has("danger_zone"):
				var dz := int(data["danger_zone"])
				var x := BAR_X + BAR_W * float(dz) / maxf(1.0, float(p[1]))
				draw_line(Vector2(x, y + 2), Vector2(x, y + 22), DZ_COL, 2.0)
				draw_string(font, Vector2(x + 3, y + 8), "DZ", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, DZ_COL)
		"structure", "stress", "repairs":
			var p := _pair(key)
			var col := {"structure": Color(0.92, 0.92, 0.95), "stress": Color(1.0, 0.55, 0.3), "repairs": Color(0.6, 0.9, 1.0)}[key] as Color
			_pips(font, y, p, col, int(_preview_num(key)))
		"burn":
			var b := int(data.get("burn", 0))
			draw_string(font, Vector2(BAR_X, y + 17), "%d  (burn check at end of turn)" % b, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 0.45, 0.15))
		"core_power":
			var state := String(data.get("core_power", "??"))
			var spending := preview.has("core_power") and state == "available"
			var col := Color(0.4, 1.0, 0.6) if state == "available" else Color(0.5, 0.5, 0.55)
			if spending:
				col = Color(1.0, 0.85, 0.3, 0.5 + 0.5 * sin(_pulse * 8.0))
			draw_string(font, Vector2(BAR_X, y + 17), ("WILL BE USED" if spending else state.to_upper()), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)


func _preview_num(key: String) -> float:
	var v: Variant = preview.get(key, 0)
	if v is Array:
		return float(v[1])
	return float(v)


## [min, max] heat the hovered action would add, or [] for none.
func _heat_preview() -> Array:
	if not preview.has("heat"):
		return []
	var v: Variant = preview["heat"]
	return [int(v[0]), int(v[1])] if v is Array else [int(v), int(v)]


## Segmented bar. `delta` < 0 previews loss; `heat_add` [min, max] previews a gain.
func _bar(font: Font, y: float, p: Array, col: Color, delta: int = 0, heat_add: Array = []) -> void:
	var rect := Rect2(BAR_X, y + 5, BAR_W, 14)
	draw_rect(rect, Color(0.08, 0.1, 0.12))
	if p.is_empty():
		draw_string(font, Vector2(BAR_X + BAR_W + 10, y + 17), "??", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.7, 0.7, 0.75))
		return
	var cur := float(p[0])
	var mx := maxf(1.0, float(p[1]))
	var fill := clampf(cur / mx, 0.0, 1.0)
	draw_rect(Rect2(rect.position, Vector2(BAR_W * fill, rect.size.y)), col)
	var a := 0.55 + 0.45 * sin(_pulse * 8.0)
	if delta < 0:
		var lost := clampf(-delta / mx, 0.0, fill)
		draw_rect(Rect2(rect.position + Vector2(BAR_W * (fill - lost), 0), Vector2(BAR_W * lost, rect.size.y)), Color(0.1, 0.1, 0.1, a))
	if not heat_add.is_empty():
		var lo := clampf((cur + float(heat_add[0])) / mx, 0.0, 1.0)
		var hi: float = (cur + float(heat_add[1])) / mx
		draw_rect(Rect2(rect.position + Vector2(BAR_W * fill, 0), Vector2(BAR_W * (lo - fill), rect.size.y)), Color(1.0, 0.8, 0.4, a))
		if hi > lo:
			draw_rect(Rect2(rect.position + Vector2(BAR_W * lo, 0), Vector2(BAR_W * (minf(hi, 1.0) - lo), rect.size.y)), Color(1.0, 0.8, 0.4, a * 0.4))
		if hi > 1.0:
			draw_rect(Rect2(rect.position + Vector2(BAR_W, -2), Vector2(8, rect.size.y + 4)), Color(DZ_COL.r, DZ_COL.g, DZ_COL.b, a))
	# Segment ticks for small pools.
	if mx <= 30.0:
		for i in range(1, int(mx)):
			var x := BAR_X + BAR_W * i / mx
			draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color(0, 0, 0, 0.55), 1.0)
	draw_rect(rect, Color(0.5, 0.7, 0.8, 0.5), false, 1.0)
	var txt := "%d/%d" % [int(cur), int(mx)]
	if not heat_add.is_empty():
		txt += "  +%s" % (str(heat_add[0]) if heat_add[0] == heat_add[1] else "%d–%d" % heat_add)
	elif delta < 0:
		txt += "  %d" % delta
	draw_string(font, Vector2(BAR_X + BAR_W + 10, y + 17), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)


func _pips(font: Font, y: float, p: Array, col: Color, delta: int) -> void:
	if p.is_empty():
		draw_string(font, Vector2(BAR_X, y + 17), "??", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.7, 0.7, 0.75))
		return
	var a := 0.4 + 0.4 * sin(_pulse * 8.0)
	for i in range(int(p[1])):
		var x := BAR_X + i * 22.0
		var c := Vector2(x + 8, y + 12)
		var pts := PackedVector2Array([c + Vector2(0, -8), c + Vector2(8, 0), c + Vector2(0, 8), c + Vector2(-8, 0)])
		var filled := i < int(p[0])
		var spent := filled and i >= int(p[0]) + delta and delta < 0
		if filled:
			draw_colored_polygon(pts, Color(col.r, col.g, col.b, a) if spent else col)
		pts.append(pts[0])
		draw_polyline(pts, col.darkened(0.3), 1.5, true)
	draw_string(font, Vector2(BAR_X + BAR_W + 10, y + 17), "%d/%d" % p, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)


func _warning() -> String:
	var hp := _heat_preview()
	var p := _pair("heat")
	if hp.is_empty() or p.is_empty():
		return ""
	var after_max := int(p[0]) + int(hp[1])
	if after_max > int(p[1]):
		return "⚠ May OVERHEAT: heat over cap means a reactor stress check"
	if data.has("danger_zone") and after_max >= int(data["danger_zone"]) and int(p[0]) < int(data["danger_zone"]):
		return "⚠ Enters the DANGER ZONE"
	return ""


func _rebuild_economy() -> void:
	for c in _economy.get_children():
		c.queue_free()
	var e: Dictionary = data.get("economy", {})
	var add := func(kind: String, text: String, spend: bool) -> void:
		var icon := CostIcon.new(kind, text, 24.0)
		icon.dimmed = text.begins_with("0/")
		if spend:
			icon.modulate = Color(1, 1, 1, 0.45)
		icon.tooltip_text = CostIcon.NAMES.get(kind, kind)
		_economy.add_child(icon)
	for key: String in ["quick", "full", "move", "reaction"]:
		if e.has(key):
			var v: Array = e[key]
			add.call(key, "%d/%d" % [int(v[0]), int(v[1])], preview.has(key))
	if e.has("overcharge_next"):
		add.call("overcharge", "next " + String(e["overcharge_next"]), preview.has("overcharge"))
