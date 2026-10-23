class_name SessionZeroScreen
extends Control
## Session zero, the way the book suggests starting a campaign (Core p.40-41): decide who the
## squad is, who gives it orders, and a little history between the pilots, then the table's
## tone, focus and any themes to leave out. Every question has a "Roll" button, like the
## book's d20 tables. Applying it submits the StoryEngine "session_zero" action.

signal done(events: Array)

var engine: StoryEngine
var story: StoryState
var campaign: Campaign

var _identity: OptionButton
var _identity_own: LineEdit
var _patron: OptionButton
var _history_rows: Array = []  # [{"a": pid, "q": OptionButton, "b": OptionButton}] (optional questions)
var _shared_rows: Array = []  # [{"a", "b", "edit": LineEdit}]: the history made from the pilots
var _shared_box: VBoxContainer
var _questions: VBoxContainer
var _variant := 0
var _tone := "heroic"
var _focus := "balanced"
var _content: Dictionary = {}  # id -> CheckBox ("leave this out")
var _box: VBoxContainer
var _msg: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 80
	scroll.offset_right = -80
	scroll.offset_top = 24
	scroll.offset_bottom = -92
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	# The way forward is always on screen, however long the page gets (4 pilots' history).
	var foot := PanelContainer.new()
	foot.name = "Footer"
	foot.add_theme_stylebox_override("panel", StoryStyle.panel(StoryStyle.EDGE, Color(0.04, 0.05, 0.08, 0.98), 2, 0, 14))
	foot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	foot.offset_top = -80
	add_child(foot)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	foot.add_child(row)
	var hint := StoryStyle.label("Scroll down for every question ↓  (all of them are optional)", 14, StoryStyle.DIM)
	row.add_child(hint)
	_msg = StoryStyle.label("", 14, StoryStyle.RED)
	_msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_msg)
	var go := StoryStyle.button("Start the campaign", 18)
	go.name = "StartButton"
	go.pressed.connect(_apply)
	row.add_child(go)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 10)
	scroll.add_child(_box)


func bind(e: StoryEngine, s: StoryState, c: Campaign) -> void:
	engine = e
	story = s
	campaign = c
	_build()


func _section(title: String, help: String) -> void:
	_box.add_child(StoryStyle.label(title, 20, StoryStyle.GOLD))
	if help != "":
		_box.add_child(StoryStyle.label(help, 14, StoryStyle.DIM, 1200))


func _build() -> void:
	for ch in _box.get_children():
		ch.queue_free()
	var d := SessionZero.data()
	_box.add_child(StoryStyle.label("SESSION ZERO  ·  %s" % campaign.name, 28, StoryStyle.GOLD))
	_box.add_child(StoryStyle.label("Before the first mission, the book suggests working out together who your squad is, who gives you orders, and how your pilots know each other (Core p.40-41). Nothing here changes the rules; it shapes the stories the GM tells.", 15, StoryStyle.TEXT, 1200))
	_section("Who are we?", "What kind of group is this, and why do these pilots work together?")
	var row := HBoxContainer.new()
	_box.add_child(row)
	_identity = OptionButton.new()
	for t: Variant in d.get("identity", []):
		_identity.add_item(str(t))
	row.add_child(_identity)
	row.add_child(_roll_button(func() -> void: _identity.select(story.dice.die(_identity.item_count) - 1)))
	_identity_own = LineEdit.new()
	_identity_own.placeholder_text = "...or write your own"
	_identity_own.custom_minimum_size.x = 420
	row.add_child(_identity_own)
	_section("Who gives us orders?", "A patron or parent organization. This decides who usually brings you work.")
	var prow := HBoxContainer.new()
	_box.add_child(prow)
	_patron = OptionButton.new()
	for p: Dictionary in d.get("patrons", []):
		_patron.add_item(str(p["text"]))
		_patron.set_item_metadata(_patron.item_count - 1, p["id"])
	prow.add_child(_patron)
	prow.add_child(_roll_button(func() -> void: _patron.select(story.dice.die(_patron.item_count) - 1)))
	_section("How do we know each other?", "Made from the pilots you already built: their backgrounds and where they come from. Change any line, or reroll for a different take.")
	_shared_box = VBoxContainer.new()
	_shared_box.add_theme_constant_override("separation", 6)
	_box.add_child(_shared_box)
	var reroll := StoryStyle.button("Reroll the history", 14)
	reroll.name = "RerollHistory"
	reroll.pressed.connect(func() -> void:
		_variant += 1
		_fill_shared())
	_box.add_child(reroll)
	_fill_shared()
	# The question game, for tables that want it: optional and folded away.
	var more := StoryStyle.button("▸ Add squad history questions (optional)", 14)
	more.name = "QuestionsToggle"
	more.flat = true
	_box.add_child(more)
	_questions = VBoxContainer.new()
	_questions.name = "Questions"
	_questions.visible = false
	_questions.add_theme_constant_override("separation", 8)
	_box.add_child(_questions)
	more.pressed.connect(func() -> void:
		_questions.visible = not _questions.visible
		more.text = ("▾ " if _questions.visible else "▸ ") + "Add squad history questions (optional)")
	_questions.add_child(StoryStyle.label("Each pilot can ask the squad a question, and another pilot answers it. Skip any you like.", 14, StoryStyle.DIM, 1200))
	_history_rows = []
	var ids := campaign.pilots.keys()
	ids.sort()
	for pid: String in ids:
		var hr := HBoxContainer.new()
		hr.add_theme_constant_override("separation", 8)
		_questions.add_child(hr)
		hr.add_child(StoryStyle.label("%s asks:" % campaign.pilots[pid].get("callsign", ""), 15, StoryStyle.TEXT))
		var q := OptionButton.new()
		q.add_item("(skip)")
		q.set_item_metadata(0, "")
		for h: Dictionary in d.get("history", []):
			q.add_item(str(h["text"]))
			q.set_item_metadata(q.item_count - 1, h["id"])
		hr.add_child(q)
		var b := OptionButton.new()
		for o: String in ids:
			if o != pid:
				b.add_item("%s answers" % campaign.pilots[o].get("callsign", ""))
				b.set_item_metadata(b.item_count - 1, o)
		hr.add_child(b)
		hr.add_child(_roll_button(func() -> void:
			q.select(story.dice.die(q.item_count - 1))
			if b.item_count > 0:
				b.select(story.dice.die(b.item_count) - 1)))
		_history_rows.append({"a": pid, "q": q, "b": b})
	_section("Tone", "What kind of story do you want? It changes which situations and twists come up.")
	_box.add_child(_choice_row(d.get("tones", {}), func(id: String) -> void: _tone = id, _tone))
	_section("Focus", "How much time between fights?")
	_box.add_child(_choice_row(d.get("focus", {}), func(id: String) -> void: _focus = id, _focus))
	_section("Leave out", "Themes the table would rather not see. They're taken out of the stories the GM builds.")
	_content = {}
	for id: String in d.get("content", {}):
		var cb := CheckBox.new()
		cb.text = "%s: %s" % [d["content"][id]["name"], d["content"][id]["text"]]
		_content[id] = cb
		_box.add_child(cb)


## The made-up history lines, each editable.
func _fill_shared() -> void:
	for ch in _shared_box.get_children():
		ch.queue_free()
	_shared_rows = []
	for h: Dictionary in SessionZero.squad_history(story, campaign, _variant):
		var e := LineEdit.new()
		e.text = str(h["text"])
		e.custom_minimum_size = Vector2(1000, 0)
		e.add_theme_font_size_override("font_size", StorySettings.size(15))
		_shared_box.add_child(e)
		_shared_rows.append({"a": h["a"], "b": h["b"], "edit": e})


func _roll_button(cb: Callable) -> Button:
	var b := StoryStyle.button("Roll", 14)
	b.tooltip_text = "Pick one at random, like rolling a d20 on the book's table."
	b.pressed.connect(cb)
	return b


func _choice_row(opts: Dictionary, set_value: Callable, current: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for id: String in opts:
		var b := StoryStyle.button(str(opts[id]["name"]), 15)
		b.toggle_mode = true
		b.button_group = group
		b.tooltip_text = str(opts[id].get("text", ""))
		b.button_pressed = id == current
		var v := id
		b.pressed.connect(func() -> void: set_value.call(v))
		row.add_child(b)
	return row


## The choices as the session_zero action takes them.
func choices() -> Dictionary:
	var history: Array = []
	for r: Dictionary in _history_rows:
		var q: OptionButton = r["q"]
		var b: OptionButton = r["b"]
		var qid := str(q.get_item_metadata(q.selected)) if q.selected >= 0 else ""
		if qid != "" and b.selected >= 0:
			history.append({"question": qid, "a": r["a"], "b": b.get_item_metadata(b.selected)})
	var off: Array = []
	for id: String in _content:
		if (_content[id] as CheckBox).button_pressed:
			off.append(id)
	var identity := _identity_own.text.strip_edges()
	if identity == "":
		identity = _identity.get_item_text(_identity.selected)
	var shared: Array = []
	for r: Dictionary in _shared_rows:
		var t := (r["edit"] as LineEdit).text.strip_edges()
		if t != "":
			shared.append({"a": r["a"], "b": r["b"], "text": t})
	return {"identity": identity, "patron": str(_patron.get_item_metadata(_patron.selected)), "history": history, "squad_history": shared,
		"tone": _tone, "focus": _focus, "content_off": off}


func _apply() -> void:
	var r := engine.submit(story, campaign, {"type": "session_zero", "seat": "gm", "params": choices()})
	if not r["ok"]:
		_msg.text = "✕ " + str(r["reason"])
		return
	done.emit(r["events"])


## godot --path . -s res://tools/screenshot.gd -- res://scenes/story/session_zero.tscn out.png 20
func screenshot_setup(_args: Array) -> Variant:
	var d := HubDemo.make(21)
	bind(d["engine"], d["story"], d["campaign"])
	_history_rows[0]["q"].select(4)
	_history_rows[1]["q"].select(8)
	return null
