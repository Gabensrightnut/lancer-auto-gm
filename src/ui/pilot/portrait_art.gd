class_name PortraitArt
extends Control
## A pilot or NPC portrait drawn from parts in code (our own illustrated style, no images,
## no pixel art): head and shoulders built from a v2 portrait (PortraitSpec format:
## {version: 2, parts: {part: {option, primary, secondary}}}), with any of the expressions in
## portraits.json. Drop-in for the placeholder Portrait: same set_look(look, expr) and `lit`.
##
## Layers, back to front: card, hair (back), hood (back), ears, neck, body, inner outfit,
## outer outfit, body detail, scarves, jewelry (chest), head, face detail, eyes, eyebrows,
## nose, mouth, beard, mustache, hair (front), glasses, hats, other, jewelry (face).

const EXPRESSIONS := ["neutral", "smiling", "angry", "worried", "shouting", "sad", "surprised", "determined", "smug", "hurt"]

var look: Dictionary = {}
var expression := "neutral"
## Dimmed when the other side is talking.
var lit := true:
	set(v):
		lit = v
		queue_redraw()
## Draw the card background (off for thumbnails on a panel that has its own).
var card := true

var _o := Vector2.ZERO  # canvas origin (head center line)
var _s := 1.0  # canvas scale: 1 unit = portrait width
var _skin := Color("c68d66")


func _init() -> void:
	custom_minimum_size = Vector2(200, 240)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)


## `l` = a v2 portrait or an older flat look; `expr` = an expression id from portraits.json.
func set_look(l: Dictionary, expr: String = "neutral") -> void:
	look = PortraitSpec.normalize(l)
	expression = expr if EXPRESSIONS.has(expr) else PortraitSpec.draw_as(expr)
	if not EXPRESSIONS.has(expression):
		expression = "neutral"
	queue_redraw()


func _part(id: String) -> Dictionary:
	return (look.get("parts", {}) as Dictionary).get(id, {})


func _opt(id: String, fallback: String = "none") -> String:
	return String(_part(id).get("option", fallback))


func _col(id: String, slot: String = "primary", fallback: String = "#808080") -> Color:
	var p := _part(id)
	return Color(String(p.get(slot, p.get("primary", fallback))))


# --- drawing helpers (unit space: x -0.5..0.5, y -0.6 top .. 0.6 bottom, head at 0,-0.08) ----

func _p(x: float, y: float) -> Vector2:
	return _o + Vector2(x, y) * _s


func _pts(arr: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v: Vector2 in arr:
		out.append(_o + v * _s)
	return out


func _ell(c: Vector2, rx: float, ry: float, n: int = 28, a0: float = 0.0, a1: float = TAU) -> Array:
	var out: Array = []
	for i in range(n + 1 if a1 - a0 < TAU - 0.001 else n):
		var a := a0 + (a1 - a0) * float(i) / float(n)
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out


func _bez(a: Vector2, b: Vector2, c: Vector2, n: int = 10) -> Array:
	var out: Array = []
	for i in range(n + 1):
		var t := float(i) / n
		out.append(a.lerp(b, t).lerp(b.lerp(c, t), t))
	return out


## Filled shape with a shadow side (lower right) and an outline.
func _fill(arr: Array, col: Color, shade: float = 0.22, outline: float = 1.0) -> void:
	var pts := _clean(_pts(arr))
	if pts.size() < 3:
		return
	if Geometry2D.triangulate_polygon(pts).is_empty():
		pts = Geometry2D.convex_hull(pts)
		pts.remove_at(pts.size() - 1)
		if pts.size() < 3:
			return
	if shade > 0.0:
		draw_colored_polygon(pts, col.darkened(shade))
		var c := Vector2.ZERO
		for v in pts:
			c += v
		c /= pts.size()
		var lit_pts := PackedVector2Array()
		for v in pts:
			lit_pts.append(c + (v - c) * 0.9 + Vector2(-0.012, -0.014) * _s)
		draw_colored_polygon(lit_pts, col)
	else:
		draw_colored_polygon(pts, col)
	if outline > 0.0:
		var loop := pts.duplicate()
		loop.append(pts[0])
		draw_polyline(loop, col.darkened(0.62), maxf(1.0, _s * 0.0055 * outline), true)


## Drops repeated points (they break triangulation).
func _clean(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for v in pts:
		if out.is_empty() or out[out.size() - 1].distance_squared_to(v) > 0.01:
			out.append(v)
	if out.size() > 1 and out[0].distance_squared_to(out[out.size() - 1]) < 0.01:
		out.remove_at(out.size() - 1)
	return out


func _line(arr: Array, col: Color, w: float) -> void:
	var pts := _pts(arr)
	if pts.size() >= 2:
		draw_polyline(pts, col, maxf(1.0, w * _s), true)


func _dot(c: Vector2, r: float, col: Color) -> void:
	draw_circle(_o + c * _s, maxf(0.5, r * _s), col)


# --- face geometry -------------------------------------------------------------------------

const HEAD_C := Vector2(0, -0.08)


func _head_dims() -> Dictionary:
	match _opt("face", "oval"):
		"round":
			return {"rx": 0.178, "ry": 0.2, "n": 2.3, "chin": 0.16, "top": 0.0}
		"square":
			return {"rx": 0.172, "ry": 0.208, "n": 3.3, "chin": 0.2, "top": 0.0}
		"long":
			return {"rx": 0.152, "ry": 0.232, "n": 2.3, "chin": 0.26, "top": 0.0}
		"heart":
			return {"rx": 0.172, "ry": 0.212, "n": 2.2, "chin": 0.46, "top": 0.07}
	return {"rx": 0.163, "ry": 0.214, "n": 2.2, "chin": 0.27, "top": 0.0}


func _head_pts() -> Array:
	var d := _head_dims()
	var out: Array = []
	var n := 48
	for i in range(n):
		var t := TAU * i / n
		var c := cos(t)
		var s := sin(t)
		var x := float(d["rx"]) * signf(c) * pow(absf(c), 2.0 / float(d["n"]))
		var y := float(d["ry"]) * signf(s) * pow(absf(s), 2.0 / float(d["n"]))
		if y > 0.0:
			x *= 1.0 - float(d["chin"]) * pow(y / float(d["ry"]), 2.0)
		else:
			x *= 1.0 + float(d["top"]) * (-y / float(d["ry"]))
		out.append(HEAD_C + Vector2(x, y))
	return out


## Half-width of the face at height y (unit space), for placing things on the cheeks/jaw.
func _face_half(y: float) -> float:
	var d := _head_dims()
	var ry := float(d["ry"])
	var v := clampf((y - HEAD_C.y) / ry, -1.0, 1.0)
	var c := pow(1.0 - pow(absf(v), float(d["n"])), 1.0 / float(d["n"]))
	var x := float(d["rx"]) * c
	if v > 0.0:
		x *= 1.0 - float(d["chin"]) * v * v
	return x


func _chin_y() -> float:
	return HEAD_C.y + float(_head_dims()["ry"])


# --- main draw -----------------------------------------------------------------------------

func _draw() -> void:
	var w := size.x
	var h := size.y
	_s = minf(w * 1.12, h * 0.98)
	_o = Vector2(w * 0.5, h * 0.46)
	_skin = _col("face", "primary", "#c68d66")
	if card:
		_draw_card(w, h)
	_hair_back()
	_hood(true)
	_ears()
	_neck()
	_body()
	_inner_outfit()
	_outer_outfit()
	_body_detail()
	_scarves()
	_jewelry(true)
	_fill(_head_pts(), _skin, 0.16)
	_cheeks()
	_face_detail()
	_eyes()
	_brows()
	_nose()
	_mouth()
	_beard()
	_mustache()
	_hair_front()
	_glasses()
	_hats()
	_other()
	_jewelry(false)
	if not lit:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.05, 0.45))


func _draw_card(w: float, h: float) -> void:
	var accent := _col("outer_outfit", "secondary", "#3a8ac8")
	if _opt("outer_outfit") == "none":
		accent = _col("inner_outfit", "secondary", "#3a8ac8")
	var top := Color(0.09, 0.11, 0.15).lerp(accent, 0.22)
	var bottom := Color(0.03, 0.035, 0.05)
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([top, top, bottom, bottom]))
	for i in range(7):
		var x := w * (0.08 + i * 0.16)
		draw_line(Vector2(x, 0), Vector2(x - h * 0.6, h), Color(1, 1, 1, 0.025), maxf(2.0, w * 0.03))
	draw_circle(_p(0, -0.1), _s * 0.36, Color(accent.r, accent.g, accent.b, 0.07))


func _cheeks() -> void:
	if expression in ["smiling", "smug", "shouting"]:
		for sx: float in [-1.0, 1.0]:
			_dot(Vector2(sx * 0.095, 0.005), 0.03, Color(0.85, 0.35, 0.3, 0.12))


# --- body and clothes ----------------------------------------------------------------------

func _shoulder_w() -> float:
	match _opt("body", "average"):
		"slim":
			return 0.33
		"broad":
			return 0.43
		"heavy":
			return 0.46
	return 0.38


func _torso_pts(neck_w: float, neck_y: float, widen: float = 0.0) -> Array:
	var sw := _shoulder_w() + widen
	var out: Array = []
	out.append(Vector2(-sw - 0.04, 0.62))
	out.append_array(_bez(Vector2(-sw, 0.42), Vector2(-sw + 0.005, 0.29), Vector2(-sw + 0.1, 0.27), 6))
	out.append_array(_bez(Vector2(-neck_w - 0.04, neck_y + 0.02), Vector2(0, neck_y + 0.05), Vector2(neck_w + 0.04, neck_y + 0.02), 6))
	out.append_array(_bez(Vector2(sw - 0.1, 0.27), Vector2(sw - 0.005, 0.29), Vector2(sw, 0.42), 6))
	out.append(Vector2(sw + 0.04, 0.62))
	return out


func _neck() -> void:
	var nw := 0.058 if _opt("body", "average") != "heavy" else 0.07
	var cy := _chin_y()
	_fill([Vector2(-nw, cy - 0.06), Vector2(-nw - 0.008, 0.26), Vector2(nw + 0.008, 0.26), Vector2(nw, cy - 0.06)], _skin, 0.1)
	# Shadow under the jaw.
	_fill(_ell(Vector2(0, cy + 0.005), nw * 1.05, 0.03, 16, 0.0, PI), _skin.darkened(0.3), 0.0, 0.0)


func _body() -> void:
	_fill(_torso_pts(0.06, 0.235), _skin, 0.15)


func _inner_outfit() -> void:
	var a := _col("inner_outfit", "primary", "#3b4c5e")
	var b := _col("inner_outfit", "secondary", "#d8a23a")
	match _opt("inner_outfit", "flight_suit"):
		"flight_suit":
			_fill(_torso_pts(0.075, 0.2), a)
			_fill([Vector2(-0.085, 0.2), Vector2(-0.075, 0.27), Vector2(0, 0.29), Vector2(0.075, 0.27), Vector2(0.085, 0.2), Vector2(0, 0.225)], a.lightened(0.08), 0.1)
			_line([Vector2(0, 0.24), Vector2(0, 0.62)], b, 0.008)
			_line([Vector2(-_shoulder_w() + 0.05, 0.33), Vector2(-0.12, 0.31)], b, 0.01)
			_line([Vector2(_shoulder_w() - 0.05, 0.33), Vector2(0.12, 0.31)], b, 0.01)
		"shirt":
			_fill(_torso_pts(0.07, 0.24), a)
			_fill([Vector2(-0.07, 0.24), Vector2(0, 0.38), Vector2(0.07, 0.24)], _skin, 0.12)
			_fill([Vector2(-0.075, 0.235), Vector2(-0.12, 0.3), Vector2(-0.03, 0.33)], b, 0.1)
			_fill([Vector2(0.075, 0.235), Vector2(0.12, 0.3), Vector2(0.03, 0.33)], b, 0.1)
		"undersuit":
			_fill(_torso_pts(0.062, 0.235), a, 0.25)
			_line(_bez(Vector2(-0.07, 0.25), Vector2(0, 0.285), Vector2(0.07, 0.25), 8), b, 0.012)
			for sx: float in [-1.0, 1.0]:
				_line([Vector2(sx * 0.08, 0.28), Vector2(sx * (_shoulder_w() - 0.04), 0.36), Vector2(sx * (_shoulder_w() - 0.02), 0.62)], b, 0.007)
		"turtleneck":
			_fill(_torso_pts(0.07, 0.24), a)
			_fill([Vector2(-0.07, _chin_y() + 0.02), Vector2(-0.078, 0.26), Vector2(0, 0.275), Vector2(0.078, 0.26), Vector2(0.07, _chin_y() + 0.02), Vector2(0, _chin_y() + 0.035)], a.lightened(0.06), 0.15)
			for i in range(5):
				var x := -0.05 + i * 0.025
				_line([Vector2(x, _chin_y() + 0.035), Vector2(x, 0.262)], a.darkened(0.3), 0.004)


func _outer_outfit() -> void:
	var a := _col("outer_outfit", "primary", "#4a5a6a")
	var b := _col("outer_outfit", "secondary", "#3a8ac8")
	var sw := _shoulder_w()
	match _opt("outer_outfit"):
		"jacket":
			for sx: float in [-1.0, 1.0]:
				_fill([Vector2(sx * (sw + 0.05), 0.62), Vector2(sx * (sw + 0.012), 0.4), Vector2(sx * (sw - 0.03), 0.285),
					Vector2(sx * 0.11, 0.255), Vector2(sx * 0.085, 0.32), Vector2(sx * 0.07, 0.62)], a)
				_fill([Vector2(sx * 0.11, 0.255), Vector2(sx * 0.16, 0.36), Vector2(sx * 0.07, 0.45), Vector2(sx * 0.085, 0.32)], b, 0.15)
		"hardsuit_collar":
			_fill(_torso_pts(0.08, 0.215, 0.015), a, 0.28)
			for sx: float in [-1.0, 1.0]:
				_fill(_bez(Vector2(sx * 0.12, 0.27), Vector2(sx * (sw + 0.03), 0.24), Vector2(sx * (sw + 0.035), 0.42), 8) + [Vector2(sx * (sw - 0.07), 0.4)], b, 0.25)
				_line([Vector2(sx * 0.14, 0.4), Vector2(sx * 0.14, 0.62)], a.darkened(0.45), 0.006)
			_fill([Vector2(-0.1, 0.205), Vector2(-0.12, 0.29), Vector2(0, 0.31), Vector2(0.12, 0.29), Vector2(0.1, 0.205), Vector2(0, 0.225)], b.darkened(0.1), 0.2)
			_dot(Vector2(0, 0.45), 0.018, b.lightened(0.4))
		"coat":
			for sx: float in [-1.0, 1.0]:
				_fill([Vector2(sx * 0.07, 0.15), Vector2(sx * 0.15, 0.13), Vector2(sx * 0.17, 0.3), Vector2(sx * 0.1, 0.27)], a.darkened(0.1), 0.15)
				_fill([Vector2(sx * (sw + 0.06), 0.62), Vector2(sx * (sw + 0.02), 0.38), Vector2(sx * (sw - 0.03), 0.285),
					Vector2(sx * 0.12, 0.26), Vector2(sx * 0.03, 0.5), Vector2(sx * 0.02, 0.62)], a)
				_fill([Vector2(sx * 0.12, 0.26), Vector2(sx * 0.2, 0.33), Vector2(sx * 0.06, 0.48), Vector2(sx * 0.03, 0.5)], b, 0.15)
				_dot(Vector2(sx * 0.06, 0.55), 0.01, b)
		"poncho":
			_fill([Vector2(-0.09, 0.22), Vector2(-sw - 0.08, 0.5), Vector2(-sw - 0.1, 0.62), Vector2(sw + 0.1, 0.62), Vector2(sw + 0.08, 0.5), Vector2(0.09, 0.22), Vector2(0, 0.25)], a, 0.25)
			_line([Vector2(-sw - 0.07, 0.53), Vector2(-0.1, 0.42), Vector2(0.1, 0.42), Vector2(sw + 0.07, 0.53)], b, 0.018)
			_line([Vector2(-sw - 0.09, 0.58), Vector2(-0.1, 0.49), Vector2(0.1, 0.49), Vector2(sw + 0.09, 0.58)], b.darkened(0.2), 0.01)
		"uniform":
			_fill(_torso_pts(0.075, 0.215, 0.01), a)
			_fill([Vector2(-0.085, 0.205), Vector2(-0.09, 0.27), Vector2(0, 0.3), Vector2(0.09, 0.27), Vector2(0.085, 0.205), Vector2(0, 0.225)], a.lightened(0.06), 0.1)
			for sx: float in [-1.0, 1.0]:
				_fill([Vector2(sx * (sw - 0.1), 0.275), Vector2(sx * (sw + 0.005), 0.3), Vector2(sx * (sw - 0.005), 0.33), Vector2(sx * (sw - 0.11), 0.31)], b, 0.15)
			for i in range(3):
				_dot(Vector2(0.0, 0.36 + i * 0.07), 0.011, b.lightened(0.2))
			_fill([Vector2(-0.2, 0.37), Vector2(-0.12, 0.37), Vector2(-0.12, 0.39), Vector2(-0.2, 0.39)], b, 0.0, 0.5)


func _body_detail() -> void:
	var c := _col("body_detail", "primary", "#3a3a3a")
	match _opt("body_detail"):
		"neck_tattoo":
			_line([Vector2(-0.045, 0.12), Vector2(-0.02, 0.15), Vector2(-0.045, 0.18), Vector2(-0.02, 0.21)], c, 0.006)
		"prosthetic_arm":
			var sw := _shoulder_w()
			_fill(_ell(Vector2(-sw + 0.035, 0.37), 0.075, 0.09, 20), Color(0.55, 0.57, 0.6), 0.3)
			_line([Vector2(-sw - 0.02, 0.34), Vector2(-sw + 0.08, 0.36)], Color(0.25, 0.26, 0.28), 0.005)
			_dot(Vector2(-sw + 0.04, 0.4), 0.01, c.lightened(0.5))
		"burn_scar":
			_fill(_ell(Vector2(0.035, 0.17), 0.03, 0.045, 14), _skin.lerp(Color(0.75, 0.4, 0.38), 0.45), 0.0, 0.0)
		"port_implants":
			for i in range(3):
				_dot(Vector2(0.045, 0.12 + i * 0.03), 0.009, Color(0.2, 0.21, 0.23))
				_dot(Vector2(0.045, 0.12 + i * 0.03), 0.004, c.lightened(0.4))


func _scarves() -> void:
	var c := _col("scarves", "primary", "#c83a2a")
	var cy := _chin_y()
	match _opt("scarves"):
		"scarf":
			_fill([Vector2(-0.1, cy + 0.02), Vector2(-0.115, 0.27), Vector2(0, 0.3), Vector2(0.115, 0.27), Vector2(0.1, cy + 0.02), Vector2(0, cy + 0.045)], c)
			_fill([Vector2(0.03, 0.27), Vector2(0.09, 0.27), Vector2(0.11, 0.5), Vector2(0.05, 0.5)], c.darkened(0.08))
			for i in range(3):
				_line([Vector2(0.055 + i * 0.015, 0.5), Vector2(0.055 + i * 0.015, 0.52)], c, 0.006)
		"shemagh":
			_fill([Vector2(-0.12, cy), Vector2(-0.16, 0.3), Vector2(0, 0.42), Vector2(0.16, 0.3), Vector2(0.12, cy), Vector2(0, cy + 0.04)], c, 0.2)
			for i in range(4):
				var y := cy + 0.04 + i * 0.05
				_line([Vector2(-0.11 + i * 0.01, y), Vector2(0, y + 0.06), Vector2(0.11 - i * 0.01, y)], c.darkened(0.35), 0.004)
		"collar_wrap":
			_fill([Vector2(-0.085, cy + 0.03), Vector2(-0.09, 0.25), Vector2(0.09, 0.25), Vector2(0.085, cy + 0.03)], c, 0.2)
			_line([Vector2(-0.088, 0.2), Vector2(0.088, 0.17)], c.darkened(0.3), 0.004)


func _jewelry(chest: bool) -> void:
	var c := _col("jewelry", "primary", "#c8b060")
	var opt := _opt("jewelry")
	if chest:
		if opt == "dog_tags":
			_line(_bez(Vector2(-0.07, 0.25), Vector2(0, 0.36), Vector2(0.07, 0.25), 10), c.darkened(0.2), 0.004)
			_fill([Vector2(-0.025, 0.33), Vector2(0.01, 0.33), Vector2(0.01, 0.39), Vector2(-0.025, 0.39)], c, 0.2, 0.6)
			_fill([Vector2(0.0, 0.335), Vector2(0.03, 0.34), Vector2(0.03, 0.395), Vector2(0.0, 0.39)], c.darkened(0.15), 0.2, 0.6)
		elif opt == "necklace":
			_line(_bez(Vector2(-0.065, 0.24), Vector2(0, 0.33), Vector2(0.065, 0.24), 10), c, 0.005)
			_fill(_ell(Vector2(0, 0.305), 0.016, 0.02, 12), c, 0.2, 0.6)
		return
	var d := _head_dims()
	match opt:
		"earring":
			_dot(Vector2(-float(d["rx"]) - 0.012, -0.0), 0.012, c)
		"nose_ring":
			_line(_ell(Vector2(0.018, 0.022), 0.011, 0.011, 10, -0.5, 2.6), c, 0.004)


func _hood(back: bool) -> void:
	if _opt("hats") != "hood":
		return
	var c := _col("hats", "primary", "#4a5a6a")
	var d := _head_dims()
	var rx := float(d["rx"]) + 0.07
	if back:
		_fill(_ell(HEAD_C + Vector2(0, 0.0), rx, float(d["ry"]) + 0.07, 32, PI, TAU) + [Vector2(rx + 0.04, 0.3), Vector2(-rx - 0.04, 0.3)], c.darkened(0.25), 0.15)


# --- head parts ----------------------------------------------------------------------------

func _ears() -> void:
	var d := _head_dims()
	var rx := float(d["rx"])
	var big := {"small": 0.75, "large": 1.25}.get(_opt("ears", "round"), 1.0) as float
	for sx: float in [-1.0, 1.0]:
		var c := Vector2(sx * (rx - 0.005), -0.035)
		if _opt("ears", "round") == "pointed_augment":
			_fill([c + Vector2(0, -0.035), c + Vector2(sx * 0.07, -0.085), c + Vector2(sx * 0.03, 0.035), c + Vector2(0, 0.03)], Color(0.6, 0.62, 0.66), 0.3)
			_dot(c + Vector2(sx * 0.03, -0.02), 0.007, Color(0.4, 0.9, 1.0))
		else:
			_fill(_ell(c + Vector2(sx * 0.012, 0), 0.03 * big, 0.045 * big, 18), _skin, 0.2)
			_line(_ell(c + Vector2(sx * 0.014, 0.002), 0.015 * big, 0.026 * big, 10, -1.2 if sx < 0 else 1.9, 1.6 if sx < 0 else 4.6), _skin.darkened(0.35), 0.004)


func _face_detail() -> void:
	var c := _col("face_detail", "primary", "#3a3a3a")
	match _opt("face_detail"):
		"freckles":
			var rng := RandomNumberGenerator.new()
			rng.seed = 11
			for i in range(18):
				var sx := -1.0 if i % 2 == 0 else 1.0
				_dot(Vector2(sx * rng.randf_range(0.04, 0.12), rng.randf_range(-0.02, 0.03)), 0.0045, _skin.darkened(0.3))
		"scar_cheek":
			_line([Vector2(0.06, -0.01), Vector2(0.11, 0.06)], _skin.lerp(Color(0.85, 0.55, 0.55), 0.6), 0.008)
			for i in range(3):
				var p := Vector2(0.068 + i * 0.016, 0.0 + i * 0.022)
				_line([p + Vector2(-0.01, 0.006), p + Vector2(0.01, -0.006)], _skin.darkened(0.25), 0.004)
		"scar_brow":
			_line([Vector2(0.05, -0.15), Vector2(0.08, -0.06)], _skin.lerp(Color(0.85, 0.55, 0.55), 0.6), 0.008)
		"wrinkles":
			for i in range(2):
				_line(_bez(Vector2(-0.07, -0.19 + i * 0.022), Vector2(0, -0.2 + i * 0.022), Vector2(0.07, -0.19 + i * 0.022), 8), _skin.darkened(0.22), 0.004)
			for sx: float in [-1.0, 1.0]:
				_line([Vector2(sx * 0.11, -0.075), Vector2(sx * 0.13, -0.085)], _skin.darkened(0.25), 0.004)
				_line([Vector2(sx * 0.11, -0.06), Vector2(sx * 0.13, -0.055)], _skin.darkened(0.25), 0.004)
		"tattoo_line":
			_line([Vector2(-0.095, -0.03), Vector2(-0.095, 0.05)], c, 0.009)
			_line([Vector2(-0.11, -0.03), Vector2(-0.11, 0.035)], c, 0.006)
		"cybernetic_plate":
			var m := Color(0.55, 0.57, 0.62)
			_fill([Vector2(0.07, -0.21), Vector2(0.15, -0.17), Vector2(0.158, -0.09), Vector2(0.12, -0.1), Vector2(0.075, -0.15)], m, 0.25)
			_line([Vector2(0.1, -0.19), Vector2(0.13, -0.12)], m.darkened(0.5), 0.004)
			_dot(Vector2(0.135, -0.155), 0.008, c.lightened(0.6))


## Openness of the eyes, lower lid lift, and whether the right eye is squeezed shut.
func _eye_shape() -> Dictionary:
	match expression:
		"smiling":
			return {"open": 0.72, "lift": 0.45, "wink": false}
		"angry":
			return {"open": 0.72, "lift": 0.15, "wink": false}
		"worried":
			return {"open": 1.0, "lift": 0.0, "wink": false}
		"shouting":
			return {"open": 0.95, "lift": 0.2, "wink": false}
		"sad":
			return {"open": 0.7, "lift": 0.0, "wink": false}
		"surprised":
			return {"open": 1.3, "lift": 0.0, "wink": false}
		"determined":
			return {"open": 0.78, "lift": 0.2, "wink": false}
		"smug":
			return {"open": 0.55, "lift": 0.2, "wink": false}
		"hurt":
			return {"open": 0.75, "lift": 0.2, "wink": true}
	return {"open": 0.9, "lift": 0.05, "wink": false}


func _eyes() -> void:
	var opt := _opt("eyes", "round")
	var iris := _col("eyes", "primary", "#3b2a1a")
	var w := 0.05
	var h := 0.028
	match opt:
		"narrow":
			w = 0.052
			h = 0.019
		"wide":
			w = 0.056
			h = 0.034
		"hooded":
			h = 0.024
	var shape := _eye_shape()
	for sx: float in [-1.0, 1.0]:
		var c := Vector2(sx * 0.068, -0.062)
		var cyber := opt == "cyber_both" or (opt == "cyber_left" and sx < 0.0)
		if shape["wink"] and sx > 0.0:
			_line(_bez(c + Vector2(-w * 0.9, 0), c + Vector2(0, h * 0.7), c + Vector2(w * 0.9, 0), 8), Color(0.12, 0.08, 0.07), 0.009)
			continue
		var o: float = h * float(shape["open"])
		var lift: float = float(shape["lift"])
		# Almond: upper arc and lower arc (raised by lift when smiling).
		var top: Array = []
		var bot: Array = []
		for i in range(13):
			var t := float(i) / 12.0
			var x := lerpf(-w, w, t)
			var k := 1.0 - pow(x / w, 2.0)
			var tilt := sx * x * 0.12
			top.append(c + Vector2(x, -o * k - tilt))
			bot.append(c + Vector2(x, o * k * (1.0 - lift) * 0.85 - tilt))
		var almond: Array = top.duplicate()
		bot.reverse()
		almond.append_array(bot)
		var sclera := Color(0.94, 0.93, 0.9) if not cyber else Color(0.08, 0.09, 0.1)
		_fill(almond, sclera, 0.0, 0.0)
		# Iris clipped to the almond.
		var ir := h * 0.85
		var ic := c + Vector2(sx * 0.003, 0.002)
		var iris_pts: Array = []
		for i in range(24):
			var a := TAU * i / 24.0
			var p := ic + Vector2(cos(a), sin(a)) * ir
			var x := clampf(p.x - c.x, -w, w)
			var k := 1.0 - pow(x / w, 2.0)
			var tilt := sx * x * 0.12
			p.y = clampf(p.y, c.y - o * k - tilt, c.y + o * k * (1.0 - lift) * 0.85 - tilt)
			iris_pts.append(p)
		if cyber:
			var glow := iris.lightened(0.3) if iris.get_luminance() > 0.3 else Color(1.0, 0.25, 0.2)
			_fill(iris_pts, glow, 0.0, 0.0)
			_dot(ic, ir * 0.4, Color(1, 1, 1, 0.9))
			_line(_ell(c, w * 1.25, h * 1.6, 20), Color(0.5, 0.52, 0.56), 0.005)
		else:
			_fill(iris_pts, iris, 0.0, 0.0)
			_dot(ic, ir * 0.45 * minf(1.0, o / h + 0.2), Color(0.05, 0.04, 0.04))
			_dot(ic + Vector2(-ir * 0.35, -ir * 0.35), ir * 0.22, Color(1, 1, 1, 0.85))
		# Upper lid and lashes; hooded eyes get a skin fold over the lid.
		_line(top, Color(0.1, 0.07, 0.06), 0.008)
		_line([top[12], (top[12] as Vector2) + Vector2(sx * 0.012, -0.006)], Color(0.1, 0.07, 0.06), 0.006)
		if opt == "hooded":
			_line(_bez(c + Vector2(-w, -o * 0.4), c + Vector2(0, -o * 1.9), c + Vector2(w, -o * 0.4), 8), _skin.darkened(0.25), 0.006)
		if lift > 0.3:
			_line(_bez(c + Vector2(-w * 0.7, o * 0.6), c + Vector2(0, o * 0.25), c + Vector2(w * 0.7, o * 0.6), 6), _skin.darkened(0.2), 0.004)


func _brows() -> void:
	var c := _col("eyebrows", "primary", _part("hair").get("primary", "#3a2518"))
	var opt := _opt("eyebrows", "straight")
	var thick := {"thick": 0.016, "thin": 0.006, "arched": 0.01}.get(opt, 0.011) as float
	var arch := 0.012 if opt == "arched" else 0.004
	# Inner-end offset (negative = down) and overall raise per expression.
	var inner := 0.0
	var raise := 0.0
	match expression:
		"angry", "determined":
			inner = -0.022 if expression == "angry" else -0.012
		"worried", "sad", "hurt":
			inner = 0.02
		"surprised":
			raise = 0.025
		"shouting":
			inner = -0.018
			raise = 0.005
		"smug":
			raise = 0.0
	for sx: float in [-1.0, 1.0]:
		var y := -0.112 - raise
		var a := Vector2(sx * 0.03, y - inner)
		var b := Vector2(sx * 0.07, y - arch * 2.0 - (0.01 if expression == "smug" and sx > 0 else 0.0))
		var e := Vector2(sx * 0.105, y + 0.008)
		var pts := _bez(a, b, e, 8)
		if opt == "scarred" and sx > 0:
			_line(pts.slice(0, 4), c, thick)
			_line(pts.slice(6), c, thick)
		else:
			_line(pts, c, thick)


func _nose() -> void:
	var sh := _skin.darkened(0.3)
	var hl := _skin.lightened(0.12)
	var opt := _opt("nose", "straight")
	var wing := {"broad": 0.034, "flat": 0.036, "small": 0.018}.get(opt, 0.024) as float
	var len_ := {"small": 0.04, "flat": 0.04, "hooked": 0.07}.get(opt, 0.06) as float
	var tip := Vector2(0.006, -0.03 + len_)
	if opt == "hooked":
		_line(_bez(Vector2(0.008, -0.05), Vector2(0.03, -0.0), tip, 8), sh, 0.006)
	else:
		_line([Vector2(0.012, -0.045), tip + Vector2(0.006, -0.008)], sh, 0.005)
	_line([Vector2(-0.004, -0.04), Vector2(-0.002, tip.y - 0.015)], hl, 0.006)
	_line(_bez(tip + Vector2(-wing, -0.004), tip + Vector2(-wing * 0.3, 0.014), tip + Vector2(0, 0.006), 6), sh, 0.006)
	_line(_bez(tip + Vector2(wing, -0.004), tip + Vector2(wing * 0.3, 0.014), tip + Vector2(0, 0.006), 6), sh, 0.006)


func _mouth() -> void:
	var lip := _col("mouth", "primary", "#a0605a")
	var opt := _opt("mouth", "full")
	var w := {"wide": 0.06, "small": 0.034, "thin": 0.045}.get(opt, 0.048) as float
	var lt := {"full": 0.014, "thin": 0.005}.get(opt, 0.009) as float
	var y := 0.07
	var dark := Color(0.18, 0.06, 0.06)
	var teeth := Color(0.95, 0.93, 0.88)
	match expression:
		"shouting", "surprised", "hurt":
			var ow := w * (1.0 if expression == "shouting" else (0.55 if expression == "surprised" else 0.9))
			var oh := {"shouting": 0.05, "surprised": 0.035, "hurt": 0.022}[expression] as float
			var inner := _ell(Vector2(0, y + oh * 0.3), ow, oh, 20)
			_fill(inner, dark, 0.0, 0.0)
			if expression != "surprised":
				_fill(_ell(Vector2(0, y + oh * 0.3), ow * 0.8, oh * 0.9, 16, PI, TAU) + [Vector2(ow * 0.8, y)], teeth, 0.0, 0.0)
			if expression == "hurt":
				_fill(_ell(Vector2(0, y + oh * 0.3), ow * 0.8, oh * 0.9, 16, 0.0, PI), teeth, 0.0, 0.0)
			_line(inner + [inner[0]], lip.darkened(0.2), lt * 0.8 + 0.003)
		_:
			var curve := 0.0
			var skew := 0.0
			match expression:
				"smiling":
					curve = -0.022
				"smug":
					curve = -0.008
					skew = -0.014
				"angry":
					curve = 0.012
				"sad":
					curve = 0.018
				"worried":
					curve = 0.008
				"determined":
					curve = 0.002
			var l := Vector2(-w, y + curve * 0.0)
			var r := Vector2(w, y + skew)
			var mid := Vector2(0, y - curve)
			var left_end := Vector2(-w, y + curve * 0.6)
			var right_end := Vector2(w, y + curve * 0.6 + skew)
			# Upper and lower lip bands, then the parting line.
			var upper := _bez(left_end, Vector2(0, y - curve - lt * 1.4), right_end, 10)
			var part := _bez(left_end, Vector2(0, y + curve), right_end, 10)
			var lower := _bez(right_end, Vector2(0, y + curve + lt * 2.2), left_end, 10)
			var ul: Array = upper.duplicate()
			var pr: Array = part.duplicate()
			pr.reverse()
			ul.append_array(pr)
			_fill(ul, lip.darkened(0.08), 0.0, 0.0)
			var ll: Array = part.duplicate()
			ll.append_array(lower)
			_fill(ll, lip, 0.0, 0.0)
			_line(part, dark, 0.006)
			if expression == "smiling":
				_fill(_bez(left_end, Vector2(0, y + 0.012), right_end, 10) + _bez(right_end, Vector2(0, y - 0.004), left_end, 10), teeth, 0.0, 0.0)
				_line(_bez(left_end, Vector2(0, y + 0.012), right_end, 10), dark, 0.004)
			for e: Vector2 in [left_end, right_end]:
				_line([e + Vector2(signf(e.x) * -0.004, 0), e + Vector2(signf(e.x) * 0.008, -curve * 0.3)], _skin.darkened(0.3), 0.004)


func _beard() -> void:
	var opt := _opt("beard")
	if opt == "none":
		return
	var c := _col("beard", "primary", "#3a2518")
	var cy := _chin_y()
	var pts: Array = []
	match opt:
		"goatee":
			pts = _ell(Vector2(0, cy - 0.02), 0.04, 0.045, 18, 0.0, PI) + [Vector2(-0.04, 0.09), Vector2(-0.025, 0.088), Vector2(0.025, 0.088), Vector2(0.04, 0.09)]
			_fill(pts, c, 0.15)
			return
		"stubble":
			c = Color(c.r, c.g, c.b, 0.32)
	var drop := {"full": 0.05, "short": 0.012, "stubble": 0.0}.get(opt, 0.012) as float
	var top_y := -0.02 if opt != "stubble" else 0.0
	# Jaw band: along the face edge from cheek to cheek, around under the mouth.
	for i in range(13):
		var y := lerpf(top_y, cy, float(i) / 12.0)
		pts.append(Vector2(-_face_half(y) - 0.004, y))
	pts.append(Vector2(-0.03, cy + drop))
	pts.append(Vector2(0.03, cy + drop))
	for i in range(13):
		var y := lerpf(cy, top_y, float(i) / 12.0)
		pts.append(Vector2(_face_half(y) + 0.004, y))
	pts.append(Vector2(_face_half(top_y) - 0.03, top_y + 0.01))
	pts.append(Vector2(0.075, 0.06))
	pts.append(Vector2(0.06, 0.1))
	pts.append(Vector2(-0.06, 0.1))
	pts.append(Vector2(-0.075, 0.06))
	pts.append(Vector2(-_face_half(top_y) + 0.03, top_y + 0.01))
	_fill(pts, c, 0.12 if opt != "stubble" else 0.0, 0.8 if opt != "stubble" else 0.0)


func _mustache() -> void:
	var opt := _opt("mustache")
	if opt == "none":
		return
	var c := _col("mustache", "primary", _part("beard").get("primary", "#3a2518"))
	var y := 0.052
	match opt:
		"thin":
			_line(_bez(Vector2(-0.045, y + 0.006), Vector2(0, y - 0.008), Vector2(0.045, y + 0.006), 8), c, 0.008)
		"full":
			_fill([Vector2(-0.05, y + 0.01), Vector2(-0.035, y - 0.006), Vector2(0, y - 0.009), Vector2(0.035, y - 0.006), Vector2(0.05, y + 0.01), Vector2(0.02, y + 0.002), Vector2(0, y + 0.004), Vector2(-0.02, y + 0.002)], c, 0.12)
		"handlebar":
			_fill([Vector2(-0.072, y - 0.018), Vector2(-0.05, y + 0.008), Vector2(0, y - 0.002), Vector2(0.05, y + 0.008), Vector2(0.072, y - 0.018), Vector2(0.05, y - 0.002), Vector2(0, y - 0.01), Vector2(-0.05, y - 0.002)], c, 0.12)


# --- hair ----------------------------------------------------------------------------------

func _hair_cols() -> Array:
	return [_col("hair", "primary", "#3a2518"), _col("hair", "secondary", "#3a2518")]


func _hair_back() -> void:
	var cols := _hair_cols()
	var d := _head_dims()
	var rx := float(d["rx"])
	var ry := float(d["ry"])
	match _opt("hair", "short"):
		"long":
			_fill(_ell(HEAD_C, rx + 0.035, ry + 0.03, 24, PI, TAU) + [Vector2(rx + 0.07, 0.34), Vector2(rx - 0.02, 0.36), Vector2(-rx + 0.02, 0.36), Vector2(-rx - 0.07, 0.34)], cols[0].darkened(0.15), 0.2)
		"braids":
			for sx: float in [-1.0, 1.0]:
				for i in range(6):
					_fill(_ell(Vector2(sx * (rx + 0.02), 0.0 + i * 0.05), 0.028, 0.03, 12), cols[0] if i % 2 == 0 else cols[0].darkened(0.12), 0.2)
				_dot(Vector2(sx * (rx + 0.02), 0.31), 0.014, cols[1])
		"bun":
			_fill(_ell(HEAD_C + Vector2(0, -ry - 0.035), 0.065, 0.055, 20), cols[0], 0.2)
		"swept", "short":
			_fill(_ell(HEAD_C + Vector2(0, -0.01), rx + 0.022, ry + 0.02, 24, PI, TAU), cols[0].darkened(0.1), 0.15)


func _hair_front() -> void:
	var opt := _opt("hair", "short")
	if opt == "bald":
		_line(_ell(HEAD_C + Vector2(-0.04, -0.12), 0.05, 0.03, 10, PI + 0.3, TAU - 0.6), _skin.lightened(0.25), 0.006)
		return
	if _opt("hats") in ["helmet", "hood"]:
		return
	var cols := _hair_cols()
	var d := _head_dims()
	var rx := float(d["rx"]) + 0.012
	var ry := float(d["ry"]) + 0.014
	var hairline := -0.15
	var cap := _ell(HEAD_C, rx, ry, 28, PI - 0.18, TAU + 0.18)
	match opt:
		"buzz":
			_fill(cap + [Vector2(rx * 0.7, hairline + 0.01), Vector2(0, hairline - 0.006), Vector2(-rx * 0.7, hairline + 0.01)], Color(cols[0].r, cols[0].g, cols[0].b, 0.6), 0.0, 0.0)
		"mohawk":
			_fill(cap + [Vector2(rx * 0.7, hairline), Vector2(-rx * 0.7, hairline)], Color(cols[0].r, cols[0].g, cols[0].b, 0.3), 0.0, 0.0)
			_fill([Vector2(-0.035, hairline - 0.01), Vector2(-0.045, -0.3), Vector2(-0.01, -0.38), Vector2(0.03, -0.37), Vector2(0.045, -0.3), Vector2(0.035, hairline - 0.01)], cols[0], 0.2)
			_line([Vector2(0.0, -0.36), Vector2(0.01, hairline)], cols[1], 0.012)
		"long", "bun", "braids":
			var part := 0.02
			_fill(cap + [Vector2(rx * 0.85, hairline + 0.04), Vector2(part, hairline - 0.02), Vector2(-rx * 0.85, hairline + 0.04)], cols[0], 0.18)
			if opt == "long":
				for sx: float in [-1.0, 1.0]:
					_fill([Vector2(sx * (rx - 0.005), -0.1), Vector2(sx * (rx + 0.03), 0.05), Vector2(sx * (rx + 0.04), 0.25), Vector2(sx * (rx - 0.035), 0.2), Vector2(sx * (rx - 0.045), -0.02)], cols[0], 0.18)
			_line(_bez(Vector2(part, hairline - 0.02), Vector2(-0.08, -0.2), Vector2(-rx * 0.8, -0.2), 8), cols[1], 0.007)
		"swept":
			_fill(cap + [Vector2(rx * 0.95, hairline + 0.03), Vector2(0.06, hairline + 0.02), Vector2(-0.05, hairline - 0.02), Vector2(-rx * 0.9, hairline - 0.03)], cols[0], 0.18)
			_fill([Vector2(-rx * 0.9, -0.22), Vector2(0.06, -0.3), Vector2(rx * 1.02, -0.17), Vector2(0.05, -0.2)], cols[0].lightened(0.06), 0.15)
			_line(_bez(Vector2(-0.1, -0.24), Vector2(0.02, -0.27), Vector2(0.13, -0.2), 8), cols[1], 0.008)
		_:  # short
			var fringe: Array = []
			for i in range(9):
				var x := lerpf(rx * 0.92, -rx * 0.92, float(i) / 8.0)
				fringe.append(Vector2(x, hairline + (0.022 if i % 2 == 0 else -0.004) + absf(x) * 0.3))
			_fill(cap + fringe, cols[0], 0.18)
			_line(_bez(Vector2(-0.06, -0.25), Vector2(0.0, -0.28), Vector2(0.07, -0.25), 6), cols[1], 0.008)


# --- accessories ---------------------------------------------------------------------------

func _glasses() -> void:
	var c := _col("glasses", "primary", "#3a3a3a")
	match _opt("glasses"):
		"glasses":
			for sx: float in [-1.0, 1.0]:
				var e := _ell(Vector2(sx * 0.068, -0.06), 0.045, 0.032, 20)
				_fill(e, Color(0.7, 0.85, 1.0, 0.18), 0.0, 0.0)
				_line(e + [e[0]], c, 0.007)
			_line(_bez(Vector2(-0.024, -0.065), Vector2(0, -0.075), Vector2(0.024, -0.065), 6), c, 0.006)
			for sx: float in [-1.0, 1.0]:
				_line([Vector2(sx * 0.113, -0.065), Vector2(sx * _face_half(-0.065), -0.07)], c, 0.006)
		"visor":
			var hw := _face_half(-0.06) + 0.01
			_fill([Vector2(-hw, -0.1), Vector2(hw, -0.1), Vector2(hw - 0.01, -0.03), Vector2(-hw + 0.01, -0.03)], Color(c.r, c.g, c.b, 0.55), 0.0, 1.0)
			_line([Vector2(-hw + 0.02, -0.085), Vector2(hw - 0.05, -0.085)], Color(1, 1, 1, 0.5), 0.006)
		"goggles":
			var hw := _face_half(-0.06) + 0.012
			_line([Vector2(-hw, -0.07), Vector2(hw, -0.07)], c.darkened(0.4), 0.02)
			for sx: float in [-1.0, 1.0]:
				_fill(_ell(Vector2(sx * 0.068, -0.065), 0.05, 0.04, 20), Color(0.25, 0.3, 0.35), 0.2)
				_fill(_ell(Vector2(sx * 0.068, -0.065), 0.036, 0.028, 18), c.lightened(0.3).lerp(Color(0.6, 0.9, 1.0), 0.5), 0.0, 0.0)
				_dot(Vector2(sx * 0.068 - 0.012, -0.075), 0.007, Color(1, 1, 1, 0.7))
		"eyepatch":
			_fill(_ell(Vector2(0.068, -0.06), 0.046, 0.038, 18), c, 0.2)
			_line([Vector2(-_face_half(-0.15), -0.15), Vector2(0.04, -0.09)], c.darkened(0.2), 0.007)
			_line([Vector2(0.11, -0.05), Vector2(_face_half(-0.02), -0.02)], c.darkened(0.2), 0.007)


func _hats() -> void:
	var c := _col("hats", "primary", "#4a5a6a")
	var d := _head_dims()
	var rx := float(d["rx"])
	var ry := float(d["ry"])
	match _opt("hats"):
		"cap":
			_fill(_ell(HEAD_C + Vector2(0, -0.035), rx + 0.02, ry * 0.85, 24, PI + 0.05, TAU - 0.05) + [Vector2(rx + 0.015, -0.16), Vector2(-rx - 0.015, -0.16)], c, 0.18)
			_fill([Vector2(-rx - 0.02, -0.165), Vector2(rx + 0.02, -0.165), Vector2(rx - 0.01, -0.135), Vector2(-rx - 0.06, -0.13)], c.darkened(0.25), 0.1)
			_dot(Vector2(0, -0.29), 0.012, c.lightened(0.2))
		"beanie":
			_fill(_ell(HEAD_C + Vector2(0, -0.05), rx + 0.02, ry * 0.85, 24, PI, TAU) + [Vector2(rx + 0.02, -0.15), Vector2(-rx - 0.02, -0.15)], c, 0.18)
			_fill([Vector2(-rx - 0.025, -0.19), Vector2(rx + 0.025, -0.19), Vector2(rx + 0.022, -0.135), Vector2(-rx - 0.022, -0.135)], c.darkened(0.12), 0.15)
			for i in range(9):
				var x := lerpf(-rx, rx, i / 8.0)
				_line([Vector2(x, -0.185), Vector2(x, -0.14)], c.darkened(0.35), 0.004)
		"helmet":
			_fill(_ell(HEAD_C + Vector2(0, -0.01), rx + 0.045, ry + 0.035, 28, PI - 0.25, TAU + 0.25) + [Vector2(rx + 0.03, -0.0), Vector2(rx - 0.02, -0.12), Vector2(-rx + 0.02, -0.12), Vector2(-rx - 0.03, -0.0)], c, 0.22)
			_line(_bez(Vector2(-rx + 0.02, -0.125), Vector2(0, -0.14), Vector2(rx - 0.02, -0.125), 8), c.lightened(0.3), 0.01)
			_line([Vector2(0, -0.32), Vector2(0, -0.2)], c.darkened(0.3), 0.012)
		"headset":
			_line(_ell(HEAD_C + Vector2(0, 0.0), rx + 0.02, ry + 0.02, 20, PI + 0.15, TAU - 0.15), c.darkened(0.2), 0.016)
			for sx: float in [-1.0, 1.0]:
				_fill(_ell(Vector2(sx * (rx + 0.018), -0.035), 0.03, 0.045, 16), c, 0.25)
			_line(_bez(Vector2(-rx - 0.02, -0.0), Vector2(-rx + 0.0, 0.07), Vector2(-0.05, 0.075), 8), c.darkened(0.3), 0.006)
			_dot(Vector2(-0.05, 0.075), 0.01, c.darkened(0.4))
		"hood":
			var pts := _ell(HEAD_C + Vector2(0, -0.005), rx + 0.06, ry + 0.06, 28, PI - 0.35, TAU + 0.35)
			var inner := _ell(HEAD_C + Vector2(0, 0.0), rx + 0.01, ry + 0.012, 28, TAU + 0.3, PI - 0.3)
			_fill(pts + inner, c, 0.2)


func _other() -> void:
	var c := _col("other", "primary", "#c83a2a")
	match _opt("other"):
		"face_paint":
			for sx: float in [-1.0, 1.0]:
				_fill([Vector2(sx * 0.03, -0.03), Vector2(sx * 0.12, -0.04), Vector2(sx * 0.115, -0.02), Vector2(sx * 0.035, -0.012)], Color(c.r, c.g, c.b, 0.85), 0.0, 0.0)
		"bandage":
			_fill([Vector2(-0.08, -0.17), Vector2(0.03, -0.2), Vector2(0.04, -0.17), Vector2(-0.075, -0.14)], Color(0.92, 0.88, 0.8), 0.15, 0.6)
			_fill([Vector2(0.075, 0.0), Vector2(0.11, -0.01), Vector2(0.115, 0.015), Vector2(0.08, 0.025)], Color(0.92, 0.85, 0.75), 0.1, 0.5)
		"cigarette":
			_line([Vector2(0.035, 0.078), Vector2(0.1, 0.095)], Color(0.95, 0.93, 0.88), 0.011)
			_dot(Vector2(0.103, 0.096), 0.007, Color(1.0, 0.45, 0.1))
			_line([Vector2(0.105, 0.085), Vector2(0.12, 0.03), Vector2(0.11, -0.02)], Color(0.8, 0.8, 0.85, 0.35), 0.005)
		"comm_bead":
			var rx := float(_head_dims()["rx"])
			_fill(_ell(Vector2(rx + 0.012, -0.025), 0.016, 0.02, 12), Color(0.2, 0.21, 0.23), 0.2, 0.6)
			_dot(Vector2(rx + 0.012, -0.03), 0.006, c.lightened(0.4))
