class_name BattleBarks
extends Control
## Speech bubbles in battle: squadmate barks and NPC lines, each with a small portrait (the
## speaker's face and expression) and their name. A bubble with a unit hangs over that unit
## on screen, with a tail pointing at it, and follows it as the camera moves. A line without
## a unit (radio, an NPC off the board) shows as a comms box at the upper left. Bubbles fade
## after a time that fits the length of the line; several stack instead of overlapping, and
## nameplates under them fade (LabelDeclutter keep-out).
##
##   var barks := BattleBarks.new()
##   ui_layer.add_child(barks)
##   barks.view = battle_view
##   barks.say({"unit": "everest", "face": {"portrait": v2, "expression": "smiling"},
##              "text": "Splash one!", "name": "Hawk"})
## Story's bark records (Squadmate.barks_for: {unit, pilot, face, text}) can be passed as
## they are; "name" falls back to the unit's name on the board.

signal finished(bark: Dictionary)

const MAX_ON_SCREEN := 3
const COMMS_POS := Vector2(24, 230)
## Below the turn-order bar, its banner and the hint.
const TOP := 220.0

var view: BattleView
## Seconds per character on top of a base time; Fx.speed shortens it.
var read_rate := 0.055

var _live: Array = []  # [{bark, panel, left}]


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Shows a line. Keys: text, face {portrait, expression}, unit (optional), name (optional),
## side ("players"/"enemies", optional, colors the frame), duration (optional seconds).
func say(bark: Dictionary) -> void:
	while _live.size() >= MAX_ON_SCREEN:
		_drop(_live[0])
	var panel := _make_panel(bark)
	add_child(panel)
	var text_len := String(bark.get("text", "")).length()
	var t := float(bark.get("duration", 2.2 + text_len * read_rate)) / maxf(0.5, Fx.speed if Fx.speed > 0.0 else 1.0)
	var entry := {"bark": bark, "panel": panel, "left": t, "age": 0.0}
	_live.append(entry)
	_place_all()


func clear() -> void:
	for e: Dictionary in _live.duplicate():
		_drop(e)


func _drop(e: Dictionary) -> void:
	_live.erase(e)
	(e["panel"] as Control).queue_free()
	finished.emit(e["bark"])


func _process(delta: float) -> void:
	if _live.is_empty():
		return
	for e: Dictionary in _live.duplicate():
		e["left"] = float(e["left"]) - delta
		e["age"] = float(e["age"]) + delta
		var p: Control = e["panel"]
		p.modulate.a = clampf(minf(float(e["age"]) * 6.0, float(e["left"]) * 2.5), 0.0, 1.0)
		if float(e["left"]) <= 0.0:
			_drop(e)
	_place_all()


## Bubbles over their units (clamped to the screen, nudged apart); unit-less lines stack
## in the comms corner.
func _place_all() -> void:
	var vp := get_viewport_rect().size if is_inside_tree() else Vector2(1920, 1080)
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var placed: Array[Rect2] = []
	var comms_y := COMMS_POS.y
	for e: Dictionary in _live:
		var p: Control = e["panel"]
		p.reset_size()
		var sz := p.size
		var mv: MechView = view.units.get(String(e["bark"].get("unit", ""))) if view else null
		var tail_to := Vector2(-1, -1)
		var pos: Vector2
		if mv and cam and not cam.is_position_behind(mv.global_position):
			var head := cam.unproject_position(mv.global_position + Vector3.UP * (mv.model.height + 0.6))
			pos = head - Vector2(sz.x * 0.25, sz.y + 28)
			tail_to = head
			if pos.y < TOP:
				# Too close to the turn bar: hang below the unit instead.
				var feet := cam.unproject_position(mv.global_position)
				pos = feet + Vector2(-sz.x * 0.25, 30)
				tail_to = feet
		else:
			pos = Vector2(COMMS_POS.x, comms_y)
			comms_y += sz.y + 8
		pos.x = clampf(pos.x, 12, vp.x - sz.x - 12)
		pos.y = clampf(pos.y, TOP, vp.y - sz.y - 140)
		var r := Rect2(pos, sz)
		for i in range(6):
			var hit := false
			for o: Rect2 in placed:
				if o.grow(4).intersects(r):
					r.position.y = o.position.y - sz.y - 8
					hit = true
			if not hit:
				break
		p.position = r.position
		placed.append(r)
		p.set_meta("tail", tail_to - r.position if tail_to.x >= 0.0 else Vector2(-1, -1))
		p.queue_redraw()


func _make_panel(bark: Dictionary) -> Control:
	var side := String(bark.get("side", ""))
	var mv: MechView = view.units.get(String(bark.get("unit", ""))) if view else null
	if side == "" and mv:
		side = String(mv.unit.get("side", ""))
	var edge: Color = MechView.SIDE_COLORS.get(side, Color(0.95, 0.8, 0.45))
	var panel := BubblePanel.new()
	panel.edge = edge
	panel.add_to_group(LabelDeclutter.GROUP_KEEPOUT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var face: Dictionary = bark.get("face", {}) if bark.get("face") is Dictionary else {}
	if face.get("portrait") is Dictionary and not (face["portrait"] as Dictionary).is_empty():
		var pa := PortraitArt.new()
		pa.custom_minimum_size = Vector2(64, 76)
		pa.set_look(face["portrait"], String(face.get("expression", "neutral")))
		row.add_child(pa)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	var name := String(bark.get("name", ""))
	if name == "" and mv:
		name = String(mv.unit.get("name", ""))
	if name != "":
		var nl := Label.new()
		nl.text = name.to_upper()
		nl.add_theme_font_size_override("font_size", 13)
		nl.add_theme_color_override("font_color", edge.lightened(0.25))
		col.add_child(nl)
	var tl := Label.new()
	tl.text = String(bark.get("text", ""))
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.custom_minimum_size = Vector2(minf(320.0, 90.0 + tl.text.length() * 7.5), 0)
	tl.add_theme_font_size_override("font_size", 17)
	tl.add_theme_color_override("font_color", Color(0.94, 0.95, 0.97))
	col.add_child(tl)
	return panel


## The bubble: a dark rounded box with a colored edge and a tail toward its unit.
class BubblePanel extends PanelContainer:
	var edge := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.04, 0.05, 0.07, 0.94)
		sb.set_corner_radius_all(8)
		sb.set_border_width_all(1)
		sb.border_width_left = 4
		sb.set_content_margin_all(8)
		sb.content_margin_right = 14
		add_theme_stylebox_override("panel", sb)

	func _ready() -> void:
		(get_theme_stylebox("panel") as StyleBoxFlat).border_color = edge

	func _draw() -> void:
		var t: Vector2 = get_meta("tail", Vector2(-1, -1))
		if t.x < 0.0:
			return
		var below := t.y > size.y * 0.5
		var base := Vector2(clampf(t.x, 18.0, size.x - 18.0), size.y - 1.0 if below else 1.0)
		var tip := Vector2(t.x, minf(t.y, size.y + 26.0) if below else maxf(t.y, -26.0))
		draw_colored_polygon(PackedVector2Array([base + Vector2(-10, 0), base + Vector2(10, 0), tip]), Color(0.04, 0.05, 0.07, 0.94))
		draw_polyline(PackedVector2Array([base + Vector2(-10, 0), tip, base + Vector2(10, 0)]), edge, 1.5, true)
