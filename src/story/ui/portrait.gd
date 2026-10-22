class_name Portrait
extends Control
## A placeholder character portrait drawn in code (our own art, no images): head and
## shoulders from a "look" (skin, hair, hair style, eyes, outfit, accent, extra) with an
## expression: neutral, smiling, angry, worried or shouting. Pilots without a look get one
## derived from their id, from the same tables NPCs use (data/game/npcs/tables.json).

const EXPRESSIONS := ["neutral", "smiling", "angry", "worried", "shouting"]

var look: Dictionary = {}
var expression := "neutral"
var lit := true  # dimmed when the other side is talking


func _init() -> void:
	custom_minimum_size = Vector2(200, 240)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## `l` = a v2 portrait (PortraitSpec) or a flat look; `expr` = any expression id from
## portraits.json, drawn with its placeholder face until the real art exists.
func set_look(l: Dictionary, expr: String = "neutral") -> void:
	look = PortraitSpec.flatten(l)
	var face := expr if EXPRESSIONS.has(expr) else PortraitSpec.draw_as(expr)
	expression = face if EXPRESSIONS.has(face) else "neutral"
	queue_redraw()


## A stable look for a pilot record (its own "look" if it has one).
static func look_for_pilot(p: Dictionary) -> Dictionary:
	if p.get("portrait") is Dictionary and not (p["portrait"] as Dictionary).is_empty():
		return PortraitSpec.flatten(p["portrait"])
	if p.get("look") is Dictionary and not (p["look"] as Dictionary).is_empty():
		return PortraitSpec.flatten(p["look"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(p.get("id", p.get("name", "pilot"))))
	var looks: Dictionary = NpcGen.tables().get("looks", {})
	var out := {}
	for k: String in looks:
		var arr: Array = looks[k]
		out[k] = arr[rng.randi_range(0, arr.size() - 1)]
	out["outfit"] = "#3b4c5e"  # pilot flight suit
	return out


func _c(key: String, fallback: String) -> Color:
	return Color.html(str(look.get(key, fallback)))


func _draw() -> void:
	var w := size.x
	var h := size.y
	var accent := _c("accent", "#3a8ac8")
	var dim := 1.0 if lit else 0.55
	# Card background.
	var top := Color(0.08, 0.1, 0.14).lerp(accent, 0.18)
	var bottom := Color(0.03, 0.035, 0.05)
	var bg := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)])
	draw_polygon(bg, PackedColorArray([top, top, bottom, bottom]))
	for i in range(6):
		draw_line(Vector2(0, h * (0.15 + i * 0.14)), Vector2(w, h * (0.1 + i * 0.14)), Color(accent, 0.05), 1.0)
	var skin := _c("skin", "#c68d66")
	var hair := _c("hair", "#3a2518")
	var outfit := _c("outfit", "#4a5a6a")
	var style := str(look.get("hair_style", "short"))
	var extra := str(look.get("extra", "none"))
	var cx := w / 2.0
	var hy := h * 0.42
	var rx := w * 0.2
	var ry := h * 0.2
	# Long hair goes behind everything.
	if style in ["long", "braids"]:
		draw_colored_polygon(_ellipse(Vector2(cx, hy + ry * 0.55), rx * 1.25, ry * 1.25), hair.darkened(0.15))
	# Shoulders and neck.
	var sh := PackedVector2Array([Vector2(cx - w * 0.44, h), Vector2(cx - w * 0.36, h * 0.74), Vector2(cx - w * 0.1, h * 0.66),
		Vector2(cx + w * 0.1, h * 0.66), Vector2(cx + w * 0.36, h * 0.74), Vector2(cx + w * 0.44, h)])
	draw_colored_polygon(sh, outfit)
	draw_colored_polygon(PackedVector2Array([Vector2(cx - w * 0.36, h * 0.74), Vector2(cx - w * 0.3, h * 0.72), Vector2(cx - w * 0.33, h), Vector2(cx - w * 0.4, h)]), outfit.lightened(0.12))
	draw_rect(Rect2(cx - rx * 0.42, hy + ry * 0.7, rx * 0.84, h * 0.12), skin.darkened(0.18))
	draw_colored_polygon(PackedVector2Array([Vector2(cx - w * 0.12, h * 0.67), Vector2(cx, h * 0.76), Vector2(cx + w * 0.12, h * 0.67), Vector2(cx + w * 0.08, h * 0.65), Vector2(cx, h * 0.71), Vector2(cx - w * 0.08, h * 0.65)]), accent)
	if extra == "scarf":
		draw_colored_polygon(_ellipse(Vector2(cx, h * 0.68), w * 0.2, h * 0.04), accent.darkened(0.1))
	# Head and ears.
	draw_colored_polygon(_ellipse(Vector2(cx - rx * 0.98, hy + ry * 0.05), rx * 0.16, ry * 0.2), skin.darkened(0.08))
	draw_colored_polygon(_ellipse(Vector2(cx + rx * 0.98, hy + ry * 0.05), rx * 0.16, ry * 0.2), skin.darkened(0.08))
	draw_colored_polygon(_ellipse(Vector2(cx, hy), rx, ry), skin)
	draw_colored_polygon(_ellipse(Vector2(cx + rx * 0.35, hy + ry * 0.1), rx * 0.55, ry * 0.8), Color(skin.darkened(0.12), 0.35))
	if extra == "beard":
		draw_colored_polygon(PackedVector2Array([Vector2(cx - rx * 0.85, hy + ry * 0.1), Vector2(cx - rx * 0.6, hy + ry * 0.75), Vector2(cx, hy + ry * 1.08),
			Vector2(cx + rx * 0.6, hy + ry * 0.75), Vector2(cx + rx * 0.85, hy + ry * 0.1), Vector2(cx + rx * 0.4, hy + ry * 0.45), Vector2(cx - rx * 0.4, hy + ry * 0.45)]), hair)
	# Hair on top.
	match style:
		"short", "braids", "swept", "bun":
			draw_colored_polygon(_cap(Vector2(cx, hy), rx * 1.04, ry * 1.02, 0.32 if style != "swept" else 0.18), hair)
			if style == "swept":
				draw_colored_polygon(PackedVector2Array([Vector2(cx - rx, hy - ry * 0.2), Vector2(cx + rx * 0.2, hy - ry * 0.9), Vector2(cx + rx * 1.05, hy - ry * 0.3), Vector2(cx - rx * 0.3, hy - ry * 0.45)]), hair.lightened(0.08))
			if style == "bun":
				draw_colored_polygon(_ellipse(Vector2(cx, hy - ry * 1.08), rx * 0.38, ry * 0.26), hair)
			if style == "braids":
				for sx: float in [-1.0, 1.0]:
					draw_line(Vector2(cx + sx * rx * 0.95, hy), Vector2(cx + sx * rx * 1.05, h * 0.78), hair, rx * 0.22)
		"long":
			draw_colored_polygon(_cap(Vector2(cx, hy), rx * 1.06, ry * 1.04, 0.38), hair)
		"buzz":
			draw_colored_polygon(_cap(Vector2(cx, hy), rx * 1.01, ry * 1.0, 0.25), Color(hair, 0.55))
		"mohawk":
			draw_colored_polygon(_ellipse(Vector2(cx, hy - ry * 0.75), rx * 0.18, ry * 0.42), hair)
	if extra == "cap":
		draw_colored_polygon(_cap(Vector2(cx, hy - ry * 0.05), rx * 1.1, ry * 1.05, 0.45), accent.darkened(0.25))
		draw_rect(Rect2(cx - rx * 1.15, hy - ry * 0.48, rx * 1.6, ry * 0.12), accent.darkened(0.4))
	_face(cx, hy, rx, ry, skin, hair)
	match extra:
		"visor":
			draw_rect(Rect2(cx - rx * 0.95, hy - ry * 0.22, rx * 1.9, ry * 0.28), Color(accent, 0.6))
			draw_line(Vector2(cx - rx * 0.95, hy - ry * 0.22), Vector2(cx + rx * 0.95, hy - ry * 0.22), accent.lightened(0.4), 2.0)
		"glasses":
			for sx: float in [-1.0, 1.0]:
				draw_arc(Vector2(cx + sx * rx * 0.4, hy - ry * 0.08), rx * 0.24, 0, TAU, 20, Color(0.1, 0.1, 0.12), 2.0)
			draw_line(Vector2(cx - rx * 0.16, hy - ry * 0.1), Vector2(cx + rx * 0.16, hy - ry * 0.1), Color(0.1, 0.1, 0.12), 2.0)
		"eyepatch":
			draw_line(Vector2(cx - rx, hy - ry * 0.45), Vector2(cx + rx, hy + ry * 0.05), Color(0.08, 0.08, 0.08), 2.0)
			draw_colored_polygon(_ellipse(Vector2(cx + rx * 0.4, hy - ry * 0.08), rx * 0.24, ry * 0.15), Color(0.08, 0.08, 0.08))
		"headset":
			draw_arc(Vector2(cx, hy - ry * 0.1), rx * 1.08, PI * 1.05, PI * 1.95, 24, Color(0.15, 0.16, 0.18), 4.0)
			draw_colored_polygon(_ellipse(Vector2(cx - rx * 1.02, hy), rx * 0.14, ry * 0.18), Color(0.15, 0.16, 0.18))
			draw_line(Vector2(cx - rx * 1.0, hy + ry * 0.1), Vector2(cx - rx * 0.4, hy + ry * 0.55), Color(0.15, 0.16, 0.18), 2.0)
	# Frame.
	draw_rect(Rect2(Vector2.ZERO, size), Color(accent, 0.9), false, 2.0)
	draw_rect(Rect2(0, 0, w, 4), accent)
	if dim < 1.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 1.0 - dim))


func _face(cx: float, hy: float, rx: float, ry: float, skin: Color, hair: Color) -> void:
	var ink := Color(0.12, 0.08, 0.07)
	var eye_y := hy - ry * 0.08
	var iris := _c("eyes", "#3b2a1a")
	var brow_c := hair.darkened(0.2)
	for sx: float in [-1.0, 1.0]:
		var ex := cx + sx * rx * 0.4
		var open := 0.11 if expression != "shouting" else 0.14
		if expression == "smiling":
			open = 0.08
		draw_colored_polygon(_ellipse(Vector2(ex, eye_y), rx * 0.17, ry * open), Color(0.95, 0.93, 0.9))
		draw_colored_polygon(_ellipse(Vector2(ex, eye_y), rx * 0.08, ry * minf(open, 0.09)), iris)
		draw_circle(Vector2(ex + rx * 0.02, eye_y - ry * 0.02), rx * 0.025, Color(1, 1, 1, 0.8))
		# Brows: inner end is toward the nose.
		var inner := Vector2(ex - sx * rx * 0.16, eye_y - ry * 0.2)
		var outer := Vector2(ex + sx * rx * 0.2, eye_y - ry * 0.22)
		match expression:
			"angry", "shouting":
				inner.y += ry * 0.09
				outer.y -= ry * 0.03
			"worried":
				inner.y -= ry * 0.08
				outer.y += ry * 0.03
			"smiling":
				inner.y -= ry * 0.03
				outer.y -= ry * 0.03
		draw_line(inner, outer, brow_c, maxf(2.0, rx * 0.09))
	# Nose.
	draw_line(Vector2(cx, hy), Vector2(cx - rx * 0.07, hy + ry * 0.25), Color(skin.darkened(0.3), 0.8), 2.0)
	draw_line(Vector2(cx - rx * 0.07, hy + ry * 0.25), Vector2(cx + rx * 0.06, hy + ry * 0.27), Color(skin.darkened(0.3), 0.8), 2.0)
	# Mouth.
	var my := hy + ry * 0.5
	var mw := rx * 0.36
	match expression:
		"smiling":
			draw_arc(Vector2(cx, my - ry * 0.1), mw, PI * 0.15, PI * 0.85, 16, ink, 2.5)
		"angry":
			draw_line(Vector2(cx - mw, my + ry * 0.03), Vector2(cx + mw, my + ry * 0.03), ink, 3.0)
			draw_line(Vector2(cx - mw, my + ry * 0.03), Vector2(cx - mw * 1.1, my + ry * 0.08), ink, 2.0)
			draw_line(Vector2(cx + mw, my + ry * 0.03), Vector2(cx + mw * 1.1, my + ry * 0.08), ink, 2.0)
		"worried":
			draw_arc(Vector2(cx, my + ry * 0.12), mw * 0.7, PI * 1.2, PI * 1.8, 12, ink, 2.5)
		"shouting":
			draw_colored_polygon(_ellipse(Vector2(cx, my + ry * 0.04), mw * 0.8, ry * 0.14), Color(0.25, 0.06, 0.06))
			draw_rect(Rect2(cx - mw * 0.55, my - ry * 0.08, mw * 1.1, ry * 0.05), Color(0.95, 0.93, 0.9))
		_:
			draw_line(Vector2(cx - mw * 0.8, my), Vector2(cx + mw * 0.8, my), ink, 2.5)


static func _ellipse(c: Vector2, rx: float, ry: float, n: int = 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(n):
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


## The top part of an ellipse, from the crown down to `depth` of its height (0.5 = the middle),
## with a slightly uneven fringe.
static func _cap(c: Vector2, rx: float, ry: float, depth: float) -> PackedVector2Array:
	var sn := clampf(-1.0 + 2.0 * depth, -0.99, 0.99)
	var a_left := PI - asin(sn)
	var a_right := TAU + asin(sn)
	var pts := PackedVector2Array()
	for i in range(25):
		var a := lerpf(a_left, a_right, float(i) / 24.0)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	var y_cut := c.y + sn * ry
	pts.append(Vector2(c.x + rx * 0.35, y_cut + ry * 0.1))
	pts.append(Vector2(c.x - rx * 0.25, y_cut + ry * 0.05))
	return pts
