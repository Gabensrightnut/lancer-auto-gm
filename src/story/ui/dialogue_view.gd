class_name DialogueView
extends Control
## Pop-up conversation over the live 3D scene, in the style of Lancer Tactics (our own art):
## the speaking pilot's portrait card on the left, the other person's on the right, a speech
## bubble from whoever is talking, and 4-6 replies to pick from. Click or Space advances;
## 1-6 pick a reply. Shows who decides (the speaking pilot's player, or a squad vote) and
## what AI squadmates chose and why. A log keeps every line.
##
## It only reads the StoryState and submits actions through StoryEngine (the host's, or a
## network client's stand-in); `story_events` carries the results to the rest of the UI.

signal story_events(events: Array)

var engine: StoryEngine
var story: StoryState
var campaign: Campaign
var seat := "p1"

var _left: Portrait
var _right: Portrait
var _left_name: Label
var _right_name: Label
var _bubble: PanelContainer
var _bubble_name: Label
var _bubble_text: RichTextLabel
var _tail: Control
var _choices: VBoxContainer
var _hint: Label
var _note: Label
var _log_panel: PanelContainer
var _log_text: RichTextLabel
var _note_timer := 0.0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_left = Portrait.new()
	_right = Portrait.new()
	_left_name = _plate()
	_right_name = _plate()
	for n: Control in [_left, _right, _left_name, _right_name]:
		add_child(n)
	_tail = Control.new()
	_tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tail.draw.connect(_draw_tail)
	add_child(_tail)
	_bubble = PanelContainer.new()
	_bubble.add_theme_stylebox_override("panel", StoryStyle.panel(Color(0.85, 0.88, 0.92), Color(0.93, 0.94, 0.95, 0.97), 1, 10, 16))
	_bubble.mouse_filter = Control.MOUSE_FILTER_STOP
	_bubble.gui_input.connect(_bubble_input)
	add_child(_bubble)
	var bb := VBoxContainer.new()
	bb.add_theme_constant_override("separation", 4)
	_bubble.add_child(bb)
	_bubble_name = StoryStyle.label("", 15, Color(0.2, 0.35, 0.55))
	bb.add_child(_bubble_name)
	_bubble_text = RichTextLabel.new()
	_bubble_text.bbcode_enabled = true
	_bubble_text.fit_content = true
	_bubble_text.scroll_active = false
	_bubble_text.mouse_filter = Control.MOUSE_FILTER_PASS
	_bubble_text.add_theme_font_size_override("normal_font_size", 19)
	_bubble_text.add_theme_font_size_override("italics_font_size", 19)
	_bubble_text.add_theme_color_override("default_color", Color(0.08, 0.09, 0.11))
	bb.add_child(_bubble_text)
	_hint = StoryStyle.label("Click or press Space to continue", 13, Color(0.35, 0.4, 0.48))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bb.add_child(_hint)
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 6)
	add_child(_choices)
	_note = StoryStyle.label("", 15, StoryStyle.GOLD)
	_note.add_theme_constant_override("outline_size", 4)
	_note.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	add_child(_note)
	var log_btn := StoryStyle.button("Log", 13)
	log_btn.name = "LogButton"
	log_btn.pressed.connect(func() -> void: _log_panel.visible = not _log_panel.visible; _refresh_log())
	add_child(log_btn)
	_log_panel = PanelContainer.new()
	_log_panel.add_theme_stylebox_override("panel", StoryStyle.panel())
	_log_panel.visible = false
	add_child(_log_panel)
	_log_text = RichTextLabel.new()
	_log_text.bbcode_enabled = true
	_log_text.scroll_following = true
	_log_text.custom_minimum_size = Vector2(520, 360)
	_log_text.add_theme_font_size_override("normal_font_size", 15)
	_log_panel.add_child(_log_text)


func _plate() -> Label:
	var l := StoryStyle.label("", 16)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_stylebox_override("normal", StoryStyle.panel(StoryStyle.EDGE, Color(0.03, 0.04, 0.06, 0.95), 1, 3, 4))
	return l


func bind(e: StoryEngine, s: StoryState, c: Campaign, local_seat: String) -> void:
	engine = e
	story = s
	campaign = c
	seat = local_seat
	refresh()


## Redraws from story.dialogue (call after any events).
func refresh() -> void:
	if story == null or not Dialogue.is_open(story):
		visible = false
		return
	visible = true
	var ctx: Dictionary = story.dialogue.get("ctx", {})
	var npc: Dictionary = story.npcs.get(str(ctx.get("npc", "")), {})
	var pilot: Dictionary = campaign.pilots.get(str(ctx.get("speaker", "")), {})
	var speaker := str(story.dialogue.get("speaker", "npc"))
	var expr := str(story.dialogue.get("expression", "neutral"))
	_left.set_look(Portrait.look_for_pilot(pilot), expr if speaker == "pilot" else str(story.dialogue.get("pilot_expression", "neutral")))
	_right.set_look(npc.get("look", {}), expr if speaker == "npc" else "neutral")
	_right.visible = not npc.is_empty()
	_right_name.visible = _right.visible
	_left.lit = speaker != "npc"
	_right.lit = speaker != "pilot"
	_left.queue_redraw()
	_right.queue_redraw()
	_left_name.text = "%s\n%s" % [pilot.get("callsign", ""), pilot.get("name", "")]
	_right_name.text = "%s\n%s" % [npc.get("name", ""), npc.get("title", "")]
	var text := str(story.dialogue.get("text", ""))
	_bubble_name.text = Dialogue.speaker_name(story, campaign, speaker) if speaker != "narrator" else ""
	_bubble_name.visible = speaker != "narrator"
	_bubble_text.text = ("[i]%s[/i]" % text) if speaker == "narrator" else text
	_bubble_text.add_theme_color_override("default_color", Color(0.3, 0.32, 0.36) if speaker == "narrator" else Color(0.08, 0.09, 0.11))
	_bubble.visible = text != ""
	var offered := Dialogue.offered(story)
	_hint.visible = offered.is_empty()
	_build_choices(offered)
	_layout()
	_tail.queue_redraw()
	_refresh_log()


func _build_choices(offered: Array) -> void:
	for ch in _choices.get_children():
		ch.queue_free()
	if offered.is_empty():
		return
	var d := Dialogue.decider(story, campaign)
	var mine := (d["seats"] as Array).has(seat) and not story.is_ai(seat)
	var votes: Dictionary = story.dialogue.get("votes", {})
	var head := StoryStyle.label("", 14, StoryStyle.DIM)
	if d["mode"] == "vote":
		var who := PackedStringArray()
		for s: String in d["seats"]:
			var p: Dictionary = campaign.pilots.get(story.pilot_of_seat(s), {})
			who.append("%s %s" % [p.get("callsign", s), "✓" if votes.has(s) else "…"])
		head.text = "Squad vote: " + "   ".join(who)
	elif not mine:
		var sp: Dictionary = campaign.pilots.get(story.pilot_of_seat(str(d["speaker_seat"])), {})
		head.text = "%s is speaking; their player chooses." % sp.get("callsign", "Another pilot")
	_choices.add_child(head)
	head.visible = head.text != ""
	# Teamwork: anyone not rolling can help (+1) and share the consequences (Core p.45).
	var me := story.pilot_of_seat(seat)
	var speaker := str(story.dialogue.get("ctx", {}).get("speaker", ""))
	if me != "" and me != speaker and offered.any(func(o: Dictionary) -> bool: return bool(o.get("check", {}).get("teamwork", false))):
		var cb := CheckBox.new()
		cb.text = "Help with the check (+1 to the roll, and you share any consequences)"
		cb.button_pressed = bool(story.dialogue.get("helpers", {}).get(seat, true))
		cb.toggled.connect(func(on: bool) -> void: _send({"type": "dialogue_help", "seat": seat, "params": {"on": on}}))
		_choices.add_child(cb)
	var i := 0
	for o: Dictionary in offered:
		i += 1
		var b := StoryStyle.button("", 17, true)
		var label := "%d.  %s" % [i, o["text"]]
		var extra := PackedStringArray()
		if o.has("badge"):
			extra.append("[%s]" % o["badge"])
		if o.has("check"):
			var chk: Dictionary = o["check"]
			var lvl := str(chk.get("level", "normal"))
			var bonus := int(chk.get("bonus", 0))
			extra.append("Skill check%s%s%s" % [" +%d %s" % [bonus, chk.get("trigger", "")] if bonus > 0 else "", "" if lvl == "normal" else ", " + lvl.to_upper(), ", Difficult" if chk.get("difficult", false) else ""])
			b.tooltip_text = "Roll d20%s, 10+ succeeds%s.\nIf it goes wrong: %s" % [" + %d (%s)" % [bonus, chk.get("trigger", "")] if bonus > 0 else "",
				"; RISKY means consequences on anything under 20" if lvl == "risky" else ("; HEROIC needs 20+" if lvl == "heroic" else ""), chk.get("consequence", "")]
		if not extra.is_empty():
			label += "   " + "  ".join(extra)
		if votes.values().has(o["id"]):
			label += "   ◆ %d" % votes.values().count(o["id"])
		b.text = label
		if o.has("badge"):
			b.add_theme_color_override("font_color", StoryStyle.GOLD)
		b.disabled = not mine or votes.has(seat)
		var cid := str(o["id"])
		b.pressed.connect(func() -> void: choose(cid))
		_choices.add_child(b)


func _layout() -> void:
	var vp := get_viewport_rect().size
	var card := Vector2(210, 250)
	var bottom := vp.y - 24.0
	_left.size = card
	_left.position = Vector2(28, bottom - card.y - 44)
	_right.size = card
	_right.position = Vector2(vp.x - card.x - 28, bottom - card.y - 44)
	for pair: Array in [[_left_name, _left], [_right_name, _right]]:
		var l: Label = pair[0]
		var p: Portrait = pair[1]
		l.size = Vector2(card.x, 44)
		l.position = Vector2(p.position.x, p.position.y + card.y)
	var bx := card.x + 60.0
	var bw := vp.x - 2.0 * bx
	_bubble.size = Vector2(bw, 0)
	_bubble.custom_minimum_size = Vector2(bw, 96)
	_bubble.reset_size()
	_bubble.position = Vector2(bx, bottom - _bubble.size.y - 30)
	_choices.size = Vector2(bw, 0)
	_choices.custom_minimum_size = Vector2(bw, 0)
	_choices.reset_size()
	_choices.position = Vector2(bx, _bubble.position.y - _choices.size.y - 14)
	_note.position = Vector2(bx, _choices.position.y - 36)
	_note.size = Vector2(bw, 30)
	var lb := get_node("LogButton") as Button
	lb.position = Vector2(vp.x - card.x - 28, _right.position.y - 40)
	_log_panel.position = Vector2(vp.x - 580, 80)
	_tail.position = Vector2.ZERO
	_tail.size = vp


func _draw_tail() -> void:
	if not _bubble.visible:
		return
	var speaker := str(story.dialogue.get("speaker", "npc")) if story != null else "npc"
	if speaker == "narrator":
		return
	var r := Rect2(_bubble.position, _bubble.size)
	var base_y := r.position.y + r.size.y * 0.55
	var fill := Color(0.93, 0.94, 0.95, 0.97)
	if speaker == "pilot":
		var tip := Vector2(_left.position.x + _left.size.x - 6, _left.position.y + _left.size.y * 0.45)
		_tail.draw_colored_polygon(PackedVector2Array([Vector2(r.position.x + 2, base_y - 16), Vector2(r.position.x + 2, base_y + 16), tip]), fill)
	else:
		var tip := Vector2(_right.position.x + 6, _right.position.y + _right.size.y * 0.45)
		_tail.draw_colored_polygon(PackedVector2Array([Vector2(r.end.x - 2, base_y - 16), Vector2(r.end.x - 2, base_y + 16), tip]), fill)


func _refresh_log() -> void:
	if not _log_panel.visible or story == null:
		return
	_log_text.clear()
	for l: Dictionary in story.dialogue.get("log", []):
		if str(l.get("speaker", "")) == "narrator":
			_log_text.append_text("[i][color=#9aa8b8]%s[/color][/i]\n" % l["text"])
		else:
			_log_text.append_text("[b][color=#9fd0ff]%s:[/color][/b] %s\n" % [l.get("name", ""), l["text"]])


func show_note(text: String) -> void:
	_note.text = text
	_note_timer = 4.0


func _process(delta: float) -> void:
	if visible:
		_layout()  # wrapped replies only know their height once they have a width
		_tail.queue_redraw()
	if _note_timer > 0.0:
		_note_timer -= delta
		if _note_timer <= 0.0:
			_note.text = ""


# --- Input -------------------------------------------------------------------------------

func advance() -> void:
	if story == null or not Dialogue.is_open(story) or not Dialogue.offered(story).is_empty():
		return
	_send({"type": "dialogue_next", "seat": seat, "params": {}})


func choose(choice_id: String) -> void:
	_send({"type": "dialogue_choose", "seat": seat, "params": {"choice": choice_id}})


func _send(action: Dictionary) -> void:
	var r := engine.submit(story, campaign, action)
	if not r["ok"]:
		show_note(str(r["reason"]))
		return
	for e: Dictionary in r["events"]:
		if str(e.get("type", "")) == "ai_chose" and e.has("choice"):
			show_note("%s" % e.get("why", ""))
	refresh()
	story_events.emit(r["events"])


func _bubble_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		advance()


func _unhandled_input(ev: InputEvent) -> void:
	if not visible:
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		var k := (ev as InputEventKey).keycode
		if k == KEY_SPACE or k == KEY_ENTER:
			advance()
			get_viewport().set_input_as_handled()
		elif k >= KEY_1 and k <= KEY_6:
			var offered := Dialogue.offered(story)
			var i := k - KEY_1
			if i < offered.size():
				choose(str(offered[i]["id"]))
				get_viewport().set_input_as_handled()
