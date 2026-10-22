class_name NarrationPopup
extends PanelContainer
## The GM speaking mid-battle, in the story's dialogue look (portrait card and speech panel,
## StoryStyle): a mission twist (twist_revealed, Core p.43: goals can change mid-mission) or
## a line of narration (gm_narration, e.g. how the squad arrived). Shows one at a time; the AI
## waits while it's open. Events are those the on-screen seat was sent (ViewFilter keeps a
## twist to the squad's side).

signal closed

var _portrait: Portrait
var _kind: Label
var _speaker: Label
var _text: Label
var _question: Label
var _ref: Label
var _queue: Array = []
var _shown: Dictionary = {}


func _init() -> void:
	add_theme_stylebox_override("panel", StoryStyle.panel(StoryStyle.GOLD, Color(0.04, 0.05, 0.07, 0.96), 3, 6, 16))
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	add_child(row)
	_portrait = Portrait.new()
	_portrait.custom_minimum_size = Vector2(150, 180)
	row.add_child(_portrait)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	row.add_child(col)
	_kind = StoryStyle.label("", 14, StoryStyle.GOLD)
	col.add_child(_kind)
	_speaker = StoryStyle.label("", 16, StoryStyle.DIM)
	col.add_child(_speaker)
	_text = StoryStyle.label("", 22, StoryStyle.TEXT, 560)
	col.add_child(_text)
	_question = StoryStyle.label("", 18, StoryStyle.BLUE, 560)
	col.add_child(_question)
	_ref = StoryStyle.label("", 13, StoryStyle.DIM, 560)
	col.add_child(_ref)
	var ok := StoryStyle.button("Continue", 16)
	ok.alignment = HORIZONTAL_ALIGNMENT_CENTER
	ok.custom_minimum_size = Vector2(180, 44)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	ok.pressed.connect(_next)
	col.add_child(ok)


## Takes any events; queues the GM's narration among them. Each is shown once (hot-seat
## players at one screen get the events they missed, which may repeat).
func show_events(events: Array) -> void:
	for e: Dictionary in events:
		var type := str(e.get("type", ""))
		if not type in ["twist_revealed", "gm_narration"]:
			continue
		var key := "%s|%s" % [type, JSON.stringify(e.get("twist", e.get("text", "")))]
		if _shown.has(key):
			continue
		_shown[key] = true
		_queue.append(e)
	if not visible:
		_next()


func _next() -> void:
	if _queue.is_empty():
		if visible:
			visible = false
			closed.emit()
		return
	var e: Dictionary = _queue.pop_front()
	var twist: Dictionary = e.get("twist", {})
	var is_twist := not twist.is_empty()
	_kind.text = "TWIST: THE MISSION CHANGES" if is_twist else str(e.get("title", "GM")).to_upper()
	var speaker := str(e.get("speaker", ""))
	_speaker.text = ("%s, on comms" % speaker) if speaker != "" else "Your GM"
	_portrait.set_look(Portrait.look_for_pilot({"id": speaker if speaker != "" else "gm"}), "worried" if is_twist else "neutral")
	_text.text = str(twist.get("reveal", "")) if is_twist else str(e.get("text", ""))
	_question.text = str(twist.get("question", ""))
	_question.visible = _question.text != ""
	_ref.text = str(e.get("rule_ref", ""))
	_ref.visible = _ref.text != ""
	visible = true
	reset_size()
	_place.call_deferred()


func _place() -> void:
	reset_size()
	var vp := get_viewport_rect().size
	position = Vector2((vp.x - size.x) / 2.0, vp.y * 0.19)
