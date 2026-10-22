class_name ResourceCluster
extends Control
## The compact resource block beside the action bar: HP and heat bars (Danger Zone marked),
## structure / stress / repair pips, burn, core power, and the turn's actions left, each with
## its official icon. Takes the same data and cost preview as ResourceHUD (FORMATS.md).

const HP_COL := Color(0.35, 0.9, 0.55)
const OS_COL := Color(0.45, 0.85, 1.0)
const HEAT_COL := Color(1.0, 0.5, 0.15)
const DZ_COL := Color(1.0, 0.25, 0.2)

var data: Dictionary = {}
var preview: Dictionary = {}
var _pulse := 0.0
## Logic shared with the full HUD (warnings, previews).
var _logic := ResourceHUD.new()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and is_instance_valid(_logic):
		_logic.free()


func set_data(d: Dictionary) -> void:
	data = d
	_logic.data = d
	queue_redraw()


func set_preview(p: Dictionary) -> void:
	preview = p
	_logic.preview = p
	queue_redraw()


func warning() -> String:
	return _logic._warning()


func _process(delta: float) -> void:
	if not preview.is_empty():
		_pulse += delta
		queue_redraw()


func _draw() -> void:
	var s := size
	var font := get_theme_default_font()
	var k := s.y / 100.0
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.04, 0.05, 0.07, 0.9))
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.35, 0.55, 0.75, 0.6), false, 1.0)
	var pad := 8.0 * k
	var row := (s.y - pad * 2.0) / 4.0
	var icon := row * 0.72
	var bar_x := pad + icon + 6 * k
	var bar_w := s.x - bar_x - pad - 58 * k
	var a := 0.55 + 0.45 * sin(_pulse * 8.0)
	# HP.
	var hp: Array = _logic._pair("hp")
	_icon("structure", Vector2(pad, pad), icon, HP_COL)
	_bar(font, Rect2(bar_x, pad + row * 0.2, bar_w, row * 0.55), hp, HP_COL, k, 0, [], a)
	# Heat with Danger Zone.
	var heat: Array = _logic._pair("heat")
	_icon("heat", Vector2(pad, pad + row), icon, HEAT_COL)
	var hr := Rect2(bar_x, pad + row * 1.2, bar_w, row * 0.55)
	_bar(font, hr, heat, HEAT_COL, k, 0, _logic._heat_preview(), a)
	if not heat.is_empty() and data.has("danger_zone"):
		var x := hr.position.x + hr.size.x * float(data["danger_zone"]) / maxf(1.0, float(heat[1]))
		draw_line(Vector2(x, hr.position.y - 2), Vector2(x, hr.end.y + 2), DZ_COL, 2.0)
	# Structure, stress, repairs as pips.
	var y := pad + row * 2.0
	var x0 := pad
	for key: String in ["structure", "stress", "repairs"]:
		var icon_name := {"structure": "structure", "stress": "reactor", "repairs": "repair"}[key] as String
		var col: Color = Icons.color(icon_name)
		_icon(icon_name, Vector2(x0, y), icon * 0.85, col)
		var p: Array = _logic._pair(key)
		var txt := "??" if p.is_empty() else "%d/%d" % p
		draw_string(font, Vector2(x0 + icon * 0.9, y + row * 0.62), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(row * 0.5), col)
		x0 += (s.x - pad * 2.0) / 3.0
	# Actions left, Overcharge, core power, burn.
	y = pad + row * 3.0
	x0 = pad
	var e: Dictionary = data.get("economy", {})
	for key: String in ["quick", "full", "reaction"]:
		if not e.has(key):
			continue
		var v: Array = e[key]
		var icon_name := Icons.cost(key)
		var col := Icons.color(icon_name)
		if int(v[0]) <= 0:
			col = Color(0.4, 0.4, 0.45)
		if preview.has(key):
			col = Color(col.r, col.g, col.b, a)
		_icon(icon_name, Vector2(x0, y), icon * 0.85, col)
		draw_string(font, Vector2(x0 + icon * 0.9, y + row * 0.62), "%d/%d" % [int(v[0]), int(v[1])], HORIZONTAL_ALIGNMENT_LEFT, -1, int(row * 0.5), col)
		x0 += icon * 0.9 + 36 * k
	if e.has("overcharge_next"):
		_icon("overcharge", Vector2(x0, y), icon * 0.85, Icons.color("overcharge"))
		draw_string(font, Vector2(x0 + icon * 0.9, y + row * 0.62), String(e["overcharge_next"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(row * 0.5), Icons.color("overcharge"))
		x0 += icon * 0.9 + 40 * k
	var cp := String(data.get("core_power", ""))
	if cp != "":
		var col := Color(0.4, 1.0, 0.6) if cp == "available" else Color(0.45, 0.45, 0.5)
		if preview.has("core_power") and cp == "available":
			col = Color(1.0, 0.85, 0.3, a)
		_icon("corebonus", Vector2(x0, y), icon * 0.85, col)
		x0 += icon
	if int(data.get("burn", 0)) > 0:
		_icon("burn", Vector2(x0, y), icon * 0.85, Icons.color("burn"))
		draw_string(font, Vector2(x0 + icon * 0.9, y + row * 0.62), str(int(data["burn"])), HORIZONTAL_ALIGNMENT_LEFT, -1, int(row * 0.5), Icons.color("burn"))


func _icon(icon_name: String, pos: Vector2, px: float, col: Color) -> void:
	var t := Icons.tex(icon_name, int(px * 2))
	if t:
		draw_texture_rect(t, Rect2(pos, Vector2(px, px)), false, col)


func _bar(font: Font, r: Rect2, p: Array, col: Color, k: float, delta: int, heat_add: Array, a: float) -> void:
	draw_rect(r, Color(0.08, 0.1, 0.12))
	if p.is_empty():
		draw_string(font, Vector2(r.end.x + 6, r.end.y), "??", HORIZONTAL_ALIGNMENT_LEFT, -1, int(r.size.y * 1.1), Color(0.7, 0.7, 0.75))
		return
	var mx := maxf(1.0, float(p[1]))
	var fill := clampf(float(p[0]) / mx, 0.0, 1.0)
	draw_rect(Rect2(r.position, Vector2(r.size.x * fill, r.size.y)), col)
	if not heat_add.is_empty():
		var lo := clampf((float(p[0]) + float(heat_add[0])) / mx, 0.0, 1.0)
		var hi := (float(p[0]) + float(heat_add[1])) / mx
		draw_rect(Rect2(r.position + Vector2(r.size.x * fill, 0), Vector2(r.size.x * (lo - fill), r.size.y)), Color(1.0, 0.85, 0.45, a))
		if hi > lo:
			draw_rect(Rect2(r.position + Vector2(r.size.x * lo, 0), Vector2(r.size.x * (minf(hi, 1.0) - lo), r.size.y)), Color(1.0, 0.85, 0.45, a * 0.4))
		if hi > 1.0:
			draw_rect(Rect2(r.end.x, r.position.y - 2, 6 * k, r.size.y + 4), Color(DZ_COL.r, DZ_COL.g, DZ_COL.b, a))
	if mx <= 30.0:
		for i in range(1, int(mx)):
			var x := r.position.x + r.size.x * i / mx
			draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(0, 0, 0, 0.5), 1.0)
	draw_rect(r, Color(0.5, 0.7, 0.8, 0.5), false, 1.0)
	var txt := "%d/%d" % [int(p[0]), int(mx)]
	if not heat_add.is_empty():
		txt += " +%s" % (str(heat_add[0]) if heat_add[0] == heat_add[1] else "%d–%d" % heat_add)
	draw_string(font, Vector2(r.end.x + 6, r.end.y), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(r.size.y * 1.15), Color.WHITE)
