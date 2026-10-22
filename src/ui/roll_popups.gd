class_name RollPopups
extends Control
## Roll results as numbers that pop up over the board (DESIGN "Roll visuals"): no dice on
## screen. Rolls are already done by the time an event arrives; this shows the total with its
## result over the target (or over the roller for checks and saves), e.g. "20 HIT", "9 MISS",
## damage as "7 [damage icon]". Tinted blue when Accuracy helped and red when Difficulty
## hurt. Hovering a pop-up shows how it was made. Speed (Fx.speed) only changes how long
## pop-ups linger.

const LINGER := 2.2
const BLUE := Color(0.45, 0.72, 1.0)
const RED := Color(1.0, 0.42, 0.38)
const NEUTRAL := Color(0.96, 0.96, 0.98)
const GOLD := Color(1.0, 0.84, 0.35)

## Keep pop-ups on screen (screenshots, tutorial).
var hold := false

var _items: Array = []  # [{node: Control, world: Vector3, born: float, life: float}]
var _tip: PanelContainer
var _tip_text: RichTextLabel


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.06, 0.95)
	sb.border_color = Color(0.4, 0.62, 0.82, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	_tip.add_theme_stylebox_override("panel", sb)
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	_tip_text = RichTextLabel.new()
	_tip_text.bbcode_enabled = true
	_tip_text.fit_content = true
	_tip_text.autowrap_mode = TextServer.AUTOWRAP_OFF
	_tip_text.custom_minimum_size = Vector2(80, 0)
	_tip_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip_text.add_theme_font_size_override("normal_font_size", 16)
	_tip_text.add_theme_font_size_override("bold_font_size", 16)
	_tip.add_child(_tip_text)
	add_child(_tip)


## Tint for a check: blue if Accuracy was left over, red if Difficulty was, else neutral.
static func tint_for(check: Dictionary) -> Color:
	match String((check.get("accuracy_roll", {}) as Dictionary).get("color", "")):
		"blue":
			return BLUE
		"red":
			return RED
	return NEUTRAL


## Attack or tech attack result over the target: "20 HIT".
func show_check(world: Vector3, check: Dictionary, result: String) -> Control:
	var verdict := {"hit": "HIT", "miss": "MISS", "crit": "CRIT", "success": "SUCCESS", "fail": "FAIL", "failure": "FAIL"}.get(result, result.to_upper()) as String
	var tint := tint_for(check)
	return _spawn(world, "%d" % int(check.get("total", 0)), verdict, tint, "", RollDisplay.formula_bbcode(check, result), result == "crit")


## Damage over the target: "7 [energy icon]".
func show_damage(world: Vector3, amount: int, dtype: String, breakdown: String = "") -> Control:
	return _spawn(world, str(amount), "", NEUTRAL, Icons.damage(dtype), breakdown, false)


## Any other result (structure/stress checks, heat): number plus a short label.
func show_text(world: Vector3, number: String, label: String, tint: Color, breakdown: String = "", icon: String = "") -> Control:
	return _spawn(world, number, label, tint, icon, breakdown, false)


func _spawn(world: Vector3, number: String, label: String, tint: Color, icon: String, breakdown: String, big: bool) -> Control:
	var vp := get_viewport_rect().size
	var k := clampf(vp.y / 1080.0, 0.7, 1.6)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", int(6 * k))
	box.mouse_filter = Control.MOUSE_FILTER_STOP
	var num := Label.new()
	num.text = number
	num.add_theme_font_size_override("font_size", int((54 if big else 44) * k))
	num.add_theme_color_override("font_color", tint)
	num.add_theme_constant_override("outline_size", int(10 * k))
	num.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(num)
	if icon != "":
		var t := Icons.tex(icon, int(64 * k))
		if t:
			var tr := TextureRect.new()
			tr.texture = t
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.custom_minimum_size = Vector2(38, 38) * k
			tr.modulate = Icons.color(icon)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(tr)
	if label != "":
		var l := Label.new()
		l.text = label
		l.add_theme_font_size_override("font_size", int(28 * k))
		l.add_theme_color_override("font_color", GOLD if big else tint)
		l.add_theme_constant_override("outline_size", int(8 * k))
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(l)
	add_child(box)
	box.reset_size()
	if breakdown != "":
		box.mouse_entered.connect(func() -> void:
			_tip_text.text = breakdown
			_tip.visible = true
			_tip.reset_size()
			_tip.position = box.position + Vector2(0, box.size.y + 4))
		box.mouse_exited.connect(func() -> void: _tip.visible = false)
	# Stack pop-ups at the same spot so they don't overlap.
	var stack := 0
	for it: Dictionary in _items:
		if (it["world"] as Vector3).distance_to(world) < 0.3:
			stack += 1
	var life := LINGER / clampf(Fx.speed if Fx.speed > 0.0 else 4.0, 0.5, 4.0)
	_items.append({"node": box, "world": world, "born": Time.get_ticks_msec() / 1000.0, "life": life, "stack": stack})
	box.pivot_offset = box.size / 2.0
	box.scale = Vector2(1.35, 1.35)
	box.create_tween().tween_property(box, "scale", Vector2.ONE, 0.18).set_ease(Tween.EASE_OUT)
	_place(_items.back(), 0.0)
	return box


func clear_all() -> void:
	for it: Dictionary in _items:
		(it["node"] as Control).queue_free()
	_items.clear()
	_tip.visible = false


func _place(it: Dictionary, age: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var box: Control = it["node"]
	if cam == null or cam.is_position_behind(it["world"]):
		box.visible = false
		return
	box.visible = true
	var p := cam.unproject_position(it["world"])
	var rise := minf(age, 0.6) / 0.6 * 30.0
	box.position = p - Vector2(box.size.x / 2.0, box.size.y + rise + int(it["stack"]) * box.size.y * 0.9)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for it: Dictionary in _items.duplicate():
		var age: float = now - float(it["born"])
		var box: Control = it["node"]
		_place(it, age)
		var life: float = it["life"]
		if hold:
			continue
		if age > life:
			box.modulate.a = 1.0 - (age - life) / 0.4
			if age > life + 0.4:
				if _tip.visible and box.get_global_rect().has_point(get_viewport().get_mouse_position()):
					_tip.visible = false
				box.queue_free()
				_items.erase(it)
