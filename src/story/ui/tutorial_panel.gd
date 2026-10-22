class_name TutorialPanel
extends PanelContainer
## Shows tutorial lessons and first-time rule tips (Tutorial `tutorial_prompt` events): the
## title, a plain explanation, what to try now, and the rulebook page. Works over the hub and
## over the battle screen: feed it events with show_events(). "Hide hints" turns teaching
## hints off for the campaign (they can be turned back on in settings).

signal hints_toggled(on: bool)
## "More in the Codex": look the lesson's topic up in the rules reference.
signal codex_requested(query: String)

var campaign: Campaign
var _title: Label
var _step: Label
var _text: Label
var _objective: Label
var _ref: Label
var _queue: Array = []


func _init() -> void:
	add_theme_stylebox_override("panel", StoryStyle.panel(StoryStyle.GOLD, Color(0.04, 0.05, 0.07, 0.95), 3, 6, 14))
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var top := HBoxContainer.new()
	box.add_child(top)
	_step = StoryStyle.label("", 13, StoryStyle.DIM)
	_step.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_step)
	var hide_hints := StoryStyle.button("Hide hints", 12)
	hide_hints.pressed.connect(func() -> void:
		if campaign != null:
			campaign.options["teaching_hints"] = false
		hints_toggled.emit(false)
		_queue = _queue.filter(func(p: Dictionary) -> bool: return str(p.get("kind", "")) == "lesson")
		_next())
	top.add_child(hide_hints)
	_title = StoryStyle.label("", 20, StoryStyle.GOLD, 420)
	box.add_child(_title)
	_text = StoryStyle.label("", 15, StoryStyle.TEXT, 420)
	box.add_child(_text)
	_objective = StoryStyle.label("", 15, StoryStyle.BLUE, 420)
	box.add_child(_objective)
	_ref = StoryStyle.label("", 12, StoryStyle.DIM, 420)
	box.add_child(_ref)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var ok := StoryStyle.button("Got it", 14)
	ok.pressed.connect(_next)
	row.add_child(ok)
	var more := StoryStyle.button("More in the Codex", 14)
	more.pressed.connect(func() -> void: codex_requested.emit(str(get_meta("codex", ""))))
	row.add_child(more)
	visible = false


func bind(c: Campaign) -> void:
	campaign = c


## Takes any events; shows the tutorial prompts among them (in order, one at a time).
func show_events(events: Array) -> void:
	for e: Dictionary in events:
		if str(e.get("type", "")) == "tutorial_prompt":
			_queue.append(e)
	if not visible:
		_next()


func showing() -> String:
	return str(get_meta("prompt_id", "")) if visible else ""


func _next() -> void:
	if _queue.is_empty():
		visible = false
		return
	var p: Dictionary = _queue.pop_front()
	set_meta("prompt_id", p.get("id", ""))
	set_meta("codex", str(p.get("codex", p.get("title", ""))))
	var is_tip := str(p.get("kind", "")) == "tip"
	_step.text = "TIP" if is_tip else "LESSON %d OF %d" % [int(p.get("step", 0)), int(p.get("of", 0))]
	_title.text = str(p.get("title", ""))
	_text.text = str(p.get("text", ""))
	_objective.text = ("Try it: " + str(p["objective"])) if str(p.get("objective", "")) != "" else ""
	_objective.visible = _objective.text != ""
	_ref.text = str(p.get("rule_ref", ""))
	(get_theme_stylebox("panel") as StyleBoxFlat).border_color = StoryStyle.BLUE if is_tip else StoryStyle.GOLD
	visible = true
	reset_size()


func _process(_delta: float) -> void:
	if visible:
		reset_size()
		var vp := get_viewport_rect().size
		position = Vector2(vp.x - size.x - 16, minf(250.0, vp.y - size.y - 16))
