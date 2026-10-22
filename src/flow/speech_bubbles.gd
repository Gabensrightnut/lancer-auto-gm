class_name SpeechBubbles
extends Control
## Short speech bubbles over mechs in battle: AI squadmates' barks (Squadmate.barks_for), "Good
## hit!", "I'm hit". Each sits above the unit's nameplate and follows it on screen, one per
## unit (a new line replaces the old), and fades after a few seconds. Cosmetic only.

const SHOW_SECONDS := 3.6
const MAX_WIDTH := 300.0

var view: BattleView
## How long bubbles stay (the "pop-ups stay up" setting).
var duration_scale := 1.0
var _bubbles: Dictionary = {}  # unit id -> {panel, left}


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Shows `text` from `unit_id`'s pilot (`speaker` = their callsign).
func say(unit_id: String, speaker: String, text: String) -> void:
	if view == null or not view.units.has(unit_id) or text.strip_edges() == "":
		return
	if _bubbles.has(unit_id):
		(_bubbles[unit_id]["panel"] as Control).queue_free()
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", StoryStyle.panel(Color(0.85, 0.88, 0.92), Color(0.93, 0.94, 0.95, 0.96), 1, 10, 10))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var who := StoryStyle.label(speaker, 13, Color(0.2, 0.35, 0.55))
	v.add_child(who)
	var line := StoryStyle.label(text, 16, Color(0.08, 0.1, 0.13))
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size.x = minf(MAX_WIDTH, 16.0 + 8.6 * text.length())
	v.add_child(line)
	add_child(p)
	p.reset_size()
	_bubbles[unit_id] = {"panel": p, "left": SHOW_SECONDS * duration_scale}
	_place(unit_id)


func showing(unit_id: String) -> String:
	if not _bubbles.has(unit_id):
		return ""
	var line: Label = (_bubbles[unit_id]["panel"] as PanelContainer).get_child(0).get_child(1)
	return line.text


func _process(delta: float) -> void:
	for id: String in _bubbles.keys():
		var b: Dictionary = _bubbles[id]
		b["left"] = float(b["left"]) - delta
		var p: Control = b["panel"]
		if float(b["left"]) <= 0.0 or not view.units.has(id):
			p.queue_free()
			_bubbles.erase(id)
			continue
		p.modulate.a = clampf(float(b["left"]) / 0.4, 0.0, 1.0)
		_place(id)


func _place(id: String) -> void:
	var p: Control = _bubbles[id]["panel"]
	var mv: MechView = view.units.get(id)
	var cam := get_viewport().get_camera_3d()
	if mv == null or cam == null or cam.is_position_behind(mv.plate_anchor()):
		p.visible = false
		return
	p.visible = true
	var at := cam.unproject_position(mv.plate_anchor())
	var scale_y := get_viewport_rect().size.y / 1080.0
	at.y -= mv.plate_size().y * scale_y + 10.0
	p.position = Vector2(at.x - p.size.x / 2.0, at.y - p.size.y)
