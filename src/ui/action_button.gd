class_name ActionButton
extends Control
## One square action button: official icon, cost badge, extra badges (heat, charges,
## Overcharge), a number-key hint, and a WoW-style lockout overlay. The overlay greys the
## button with a dark radial slice that shrinks like a clock hand as a timed wait runs down
## (animating to its new size each time a turn passes); waits with no fixed length stay fully
## grey with their label. Drag a button onto another to swap them.

signal pressed(action: Dictionary)
signal hovered(action: Dictionary, on: bool)
signal swap_requested(from_id: String, to_id: String)

var action: Dictionary = {}
var hotkey := ""
## Fraction of the button still greyed (1 = fully locked, 0 = free); animated.
var sweep := 0.0
var _hover := false
var _pulse := 0.0


func _init(a: Dictionary) -> void:
	action = a
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	sweep = lock_fraction(a)
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw()
		hovered.emit(action, true))
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw()
		hovered.emit(action, false))


## Updates the action (e.g. a turn passed); the sweep animates to its new size.
func set_action(a: Dictionary) -> void:
	action = a
	var to := lock_fraction(a)
	if absf(to - sweep) > 0.001:
		var tw := create_tween()
		tw.tween_method(func(v: float) -> void:
			sweep = v
			queue_redraw(), sweep, to, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	queue_redraw()


static func locked(a: Dictionary) -> bool:
	return not bool(a.get("enabled", true))


## How much of the button the lockout covers: timed waits shrink, others cover it all.
static func lock_fraction(a: Dictionary) -> float:
	if not locked(a):
		return 0.0
	var lo: Dictionary = a.get("lockout", {})
	if String(lo.get("kind", "")) == "turns" and int(lo.get("total", 0)) > 0:
		return clampf(float(lo.get("left", 0)) / float(lo["total"]), 0.0, 1.0)
	return 1.0


func _process(delta: float) -> void:
	var lo: Dictionary = action.get("lockout", {})
	if String(lo.get("kind", "")) == "recharge" and bool(lo.get("ready", false)) or _hover:
		_pulse += delta
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not event.double_click:
		if not locked(action):
			pressed.emit(action)


func _get_drag_data(_pos: Vector2) -> Variant:
	var preview := TextureRect.new()
	preview.texture = Icons.tex(_icon_name(), 64)
	preview.size = size * 0.7
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.modulate = Color(1, 1, 1, 0.7)
	set_drag_preview(preview)
	return {"action_id": action.get("id", "")}


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.has("action_id") and data["action_id"] != action.get("id", "")


func _drop_data(_pos: Vector2, data: Variant) -> void:
	swap_requested.emit(String(data["action_id"]), String(action.get("id", "")))


func _icon_name() -> String:
	if action.has("icon"):
		return String(action["icon"])
	return Icons.cost(String(action.get("cost", "quick")))


func _draw() -> void:
	var s := size
	var r := Rect2(Vector2.ZERO, s)
	var cost := String(action.get("cost", "quick"))
	var cost_icon := Icons.cost(cost)
	var cost_col := Icons.color(cost_icon)
	var is_locked := locked(action)
	# Frame.
	var bg := Color(0.07, 0.085, 0.11, 0.95) if not _hover else Color(0.11, 0.15, 0.2, 0.98)
	draw_rect(r, bg)
	draw_rect(Rect2(Vector2.ZERO, Vector2(s.x, 3)), cost_col.darkened(0.15))
	# Main icon.
	var icon_px := int(s.y * 0.55)
	var t := Icons.tex(_icon_name(), icon_px * 2)
	var tint: Color = action.get("tint", Icons.color(_icon_name()))
	if t:
		var ir := Rect2((s - Vector2(icon_px, icon_px)) / 2.0 + Vector2(0, -s.y * 0.04), Vector2(icon_px, icon_px))
		draw_texture_rect(t, ir, false, tint)
	# Cost badge (top-left) and extras (top-right).
	var badge := s.y * 0.26
	var ct := Icons.tex(cost_icon, int(badge * 2))
	if ct:
		draw_rect(Rect2(Vector2(2, 4), Vector2(badge + 2, badge + 2)), Color(0, 0, 0, 0.55))
		draw_texture_rect(ct, Rect2(Vector2(3, 5), Vector2(badge, badge)), false, cost_col)
	var font := get_theme_default_font()
	var fs := int(s.y * 0.16)
	var x := s.x - 3
	for e: Dictionary in action.get("extras", []):
		var et := Icons.tex(String(e.get("icon", "heat")), int(badge * 2))
		var txt := str(e.get("value", ""))
		var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		x -= tw
		draw_string(font, Vector2(x, 5 + badge * 0.8), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)
		if et:
			x -= badge * 0.8
			draw_texture_rect(et, Rect2(Vector2(x, 5), Vector2(badge * 0.8, badge * 0.8)), false, Icons.color(String(e.get("icon", "heat"))))
		x -= 4
	# Name strip.
	var name := String(action.get("short", action.get("name", "")))
	var nfs := int(s.y * 0.15)
	draw_rect(Rect2(Vector2(0, s.y - nfs - 6), Vector2(s.x, nfs + 6)), Color(0, 0, 0, 0.55))
	draw_string(font, Vector2(4, s.y - 5), name, HORIZONTAL_ALIGNMENT_CENTER, s.x - 8, nfs, Color(0.92, 0.94, 0.97) if not is_locked else Color(0.6, 0.6, 0.65))
	# "Table" badge: the game doesn't (fully) apply this one; the table does.
	if action.has("table"):
		var tfs := int(s.y * 0.13)
		var tw := font.get_string_size("TABLE", HORIZONTAL_ALIGNMENT_LEFT, -1, tfs).x + 6
		var tr := Rect2(Vector2(3, s.y - nfs - 8 - tfs - 4), Vector2(tw, tfs + 3))
		draw_rect(tr, Color(0.75, 0.55, 0.15, 0.92) if String(action["table"]) == "manual" else Color(0.45, 0.42, 0.3, 0.92))
		draw_string(font, tr.position + Vector2(3, tfs), "TABLE", HORIZONTAL_ALIGNMENT_LEFT, -1, tfs, Color(0.06, 0.05, 0.03))
	# Hotkey.
	if hotkey != "":
		draw_string(font, Vector2(s.x - fs * 0.9, s.y - nfs - 9), hotkey, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.6))
	# Lockout overlay.
	if sweep > 0.001 or is_locked:
		_draw_lockout(font)
	# Recharge ready: a glow around the frame.
	var lo: Dictionary = action.get("lockout", {})
	if String(lo.get("kind", "")) == "recharge" and bool(lo.get("ready", false)):
		var a := 0.5 + 0.5 * sin(_pulse * 5.0)
		draw_rect(r.grow(-1), Color(0.5, 1.0, 0.6, a), false, 3.0)
	draw_rect(r, Color(0.45, 0.6, 0.75, 0.9 if _hover else 0.5), false, 1.0)


func _draw_lockout(font: Font) -> void:
	var s := size
	var c := s / 2.0
	# Grey wash over the whole button, then the dark radial slice.
	draw_rect(Rect2(Vector2.ZERO, s), Color(0.15, 0.15, 0.17, 0.55))
	if sweep > 0.001:
		var pts := PackedVector2Array([c])
		var steps := 40
		var reach := s.length()
		for i in range(steps + 1):
			var a := -PI / 2.0 + TAU * sweep * float(i) / steps
			var p := c + Vector2(cos(a), sin(a)) * reach
			pts.append(Vector2(clampf(p.x, 0, s.x), clampf(p.y, 0, s.y)))
		draw_colored_polygon(pts, Color(0, 0, 0, 0.55))
	var lo: Dictionary = action.get("lockout", {})
	var kind := String(lo.get("kind", ""))
	var label := ""
	var fs := int(s.y * 0.26)
	match kind:
		"turns":
			label = str(int(lo.get("left", 0)))
		"recharge":
			label = "%d+" % int(lo.get("target", 5))
			_draw_d6(Vector2(c.x - s.y * 0.2, c.y - s.y * 0.08), s.y * 0.2)
		"loading":
			label = "Reload"
			fs = int(s.y * 0.18)
		"uses":
			label = "Used" if int(lo.get("left", 0)) <= 0 else "%d/%d" % [int(lo["left"]), int(lo.get("total", 1))]
			fs = int(s.y * 0.2)
		"status":
			var st := Icons.tex(Icons.status(String(lo.get("status", ""))), int(s.y))
			if st:
				draw_texture_rect(st, Rect2(c - Vector2(s.y * 0.22, s.y * 0.32), Vector2(s.y * 0.44, s.y * 0.44)), false, Color(1.0, 0.45, 0.4))
			label = str(int(lo.get("turns", 0))) if int(lo.get("turns", 0)) > 0 else ""
			fs = int(s.y * 0.2)
		_:
			label = ""
	if label != "":
		var off := Vector2(s.y * 0.08, 0) if kind == "recharge" else Vector2.ZERO
		var y := c.y + fs * 0.35 + (s.y * 0.18 if kind == "status" else 0.0)
		draw_string_outline(font, Vector2(off.x, y), label, HORIZONTAL_ALIGNMENT_CENTER, s.x, fs, 4, Color(0, 0, 0, 0.9))
		draw_string(font, Vector2(off.x, y), label, HORIZONTAL_ALIGNMENT_CENTER, s.x, fs, Color(1, 1, 1, 0.95))


func _draw_d6(center: Vector2, half: float) -> void:
	var r := Rect2(center - Vector2(half, half), Vector2(half, half) * 2.0)
	draw_rect(r, Color(0.9, 0.9, 0.92, 0.9))
	for p: Vector2 in [Vector2(-0.45, -0.45), Vector2(0.45, 0.45), Vector2(0.45, -0.45), Vector2(-0.45, 0.45), Vector2.ZERO]:
		draw_circle(center + p * half, half * 0.14, Color(0.1, 0.1, 0.12))
