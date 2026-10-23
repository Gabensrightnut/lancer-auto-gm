class_name ActionGroupButton
extends Control
## One of the action bar's nine group buttons (Quick attacks, Full attacks, ...): its icon,
## name and how many abilities it holds; greyed when nothing in it can be used this turn,
## with a dark sweep when everything in it is waiting on a cooldown. Clicking (or its keypad
## key) opens the group's sub-bar. Dropping an ability on it moves the ability into the group.

signal pressed(group: int)

var group := 0
var bar: ActionBar
var title := ""
var icon := ""
var hotkey := ""
var count := 0
var usable := 0
var lock_fraction := 0.0
var open := false
var _hover := false


func _init(p: int, owner_bar: ActionBar, t: String, icon_name: String) -> void:
	group = p
	bar = owner_bar
	title = t
	icon = icon_name
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	mouse_entered.connect(func() -> void:
		_hover = true
		queue_redraw())
	mouse_exited.connect(func() -> void:
		_hover = false
		queue_redraw())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(group)
		accept_event()


func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return ActionButton.drag_enabled and data is Dictionary and data.has("action_id")


func _drop_data(_pos: Vector2, data: Variant) -> void:
	bar.move_to_group(String(data["action_id"]), group)


func _draw() -> void:
	var s := size
	var r := Rect2(Vector2.ZERO, s)
	var empty := count == 0
	var dim := usable == 0
	var bg := Color(0.08, 0.1, 0.13, 0.95)
	if open:
		bg = Color(0.13, 0.2, 0.28, 0.98)
	elif _hover:
		bg = Color(0.11, 0.15, 0.2, 0.98)
	draw_rect(r, bg)
	var accent := Color(0.4, 0.7, 0.95) if not dim else Color(0.35, 0.38, 0.42)
	draw_rect(Rect2(Vector2.ZERO, Vector2(s.x, 3)), accent)
	var font := get_theme_default_font()
	var ip := s.y * 0.5
	var t := Icons.tex(icon, int(ip * 2))
	var col := Icons.color(icon) if not dim else Color(0.45, 0.47, 0.5)
	if t:
		draw_texture_rect(t, Rect2(Vector2(s.y * 0.12, (s.y - ip) * 0.5), Vector2(ip, ip)), false, col)
	var fs := int(maxf(12.0, s.y * 0.24))
	var tx := s.y * 0.12 + ip + 6
	draw_string(font, Vector2(tx, s.y * 0.44), title, HORIZONTAL_ALIGNMENT_LEFT, s.x - tx - 4, fs, Color(0.93, 0.95, 0.98) if not dim else Color(0.55, 0.57, 0.6))
	var sub := "empty" if empty else ("%d" % count if usable == count else "%d/%d ready" % [usable, count])
	draw_string(font, Vector2(tx, s.y * 0.78), sub, HORIZONTAL_ALIGNMENT_LEFT, s.x - tx - 4, int(fs * 0.85), Color(0.7, 0.78, 0.86, 0.9 if not dim else 0.5))
	if hotkey != "":
		var hw := font.get_string_size(hotkey, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.8)).x
		draw_string(font, Vector2(s.x - hw - 4, s.y * 0.3), hotkey, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs * 0.8), Color(1, 1, 1, 0.55))
	# Everything in it waiting on a cooldown: a dark sweep like the slots' own.
	if count > 0 and usable == 0 and lock_fraction > 0.001:
		var c := s * 0.5
		var pts := PackedVector2Array([c])
		var a0 := -PI / 2.0
		var steps := 24
		for i in range(steps + 1):
			var a := a0 + TAU * lock_fraction * i / steps
			pts.append(c + Vector2(cos(a), sin(a)) * s.length())
		draw_colored_polygon(pts, Color(0, 0, 0, 0.45))
	draw_rect(r, Color(0.45, 0.65, 0.85, 0.9) if open or _hover else Color(0.35, 0.5, 0.65, 0.5), false, 2.0 if open else 1.0)
