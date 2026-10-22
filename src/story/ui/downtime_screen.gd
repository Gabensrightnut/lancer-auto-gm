class_name DowntimeScreen
extends Control
## Downtime as its own scene (Core p.50-55; DESIGN.md "Downtime between missions as its own
## scene"): what the squad's few days look like, every pilot's card with their downtime
## actions and how they turned out (AI squadmates too), the action picker for your own pilot,
## and the step back to the hub or on to the briefing. It sits over the hub; the walking,
## talking and freeform play happen there.

signal story_events(events: Array)

var engine: StoryEngine
var story: StoryState
var campaign: Campaign
var seat := "p1"
var panel: DowntimePanel

var _title: Label
var _intro: Label
var _cards: VBoxContainer


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.015, 0.025, 0.82)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 20
	root.offset_top = 16
	root.offset_right = -20
	root.offset_bottom = -16
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	_title = StoryStyle.label("DOWNTIME", 26, StoryStyle.GOLD)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	var back := StoryStyle.button("Back to the hub (Tab)", 15)
	back.pressed.connect(func() -> void: visible = false)
	top.add_child(back)
	var end := StoryStyle.button("End downtime: go to the briefing", 15)
	end.pressed.connect(_end)
	top.add_child(end)
	_intro = StoryStyle.label("", 16, StoryStyle.DIM, 1200)
	root.add_child(_intro)
	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	root.add_child(cols)
	var left := ScrollContainer.new()
	left.custom_minimum_size = Vector2(380, 0)
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(left)
	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", 10)
	left.add_child(_cards)
	panel = DowntimePanel.new()
	panel.floating = false
	cols.add_child(panel)
	panel.story_events.connect(func(ev: Array) -> void:
		refresh()
		story_events.emit(ev))


func bind(e: StoryEngine, s: StoryState, c: Campaign, local_seat: String) -> void:
	engine = e
	story = s
	campaign = c
	seat = local_seat
	panel.bind(e, s, c, local_seat)
	panel.visible = true
	panel.close_requested.connect(func() -> void: visible = false)


func open(action_id: String = "", npc: String = "", subject: String = "") -> void:
	visible = true
	panel.open(action_id, npc, subject)
	refresh()


func refresh() -> void:
	if story == null:
		return
	_title.text = "DOWNTIME  ·  %s" % story.hub.get("name", "")
	_intro.text = str(story.downtime.get("intro", ""))
	for ch in _cards.get_children():
		ch.queue_free()
	var seats := story.seats.keys()
	seats.sort()
	var log: Array = story.downtime.get("log", [])
	for s: String in seats:
		var pid := story.pilot_of_seat(s)
		var p: Dictionary = campaign.pilots.get(pid, {})
		if p.is_empty():
			continue
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", StoryStyle.panel(StoryStyle.GOLD if s == seat else StoryStyle.EDGE))
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		card.add_child(box)
		var face := PortraitArt.new()
		face.card = false
		face.custom_minimum_size = Vector2(72, 88)
		face.set_look(PortraitArt.look_for_pilot(p), "neutral")
		box.add_child(face)
		var info := VBoxContainer.new()
		box.add_child(info)
		var state := "KIA" if story.dead.has(pid) else "%d downtime action%s left" % [int(story.downtime.get("actions_left", {}).get(pid, 0)), "" if int(story.downtime.get("actions_left", {}).get(pid, 0)) == 1 else "s"]
		info.add_child(StoryStyle.label("%s%s  ·  LL%d" % [p.get("callsign", ""), "  (AI)" if story.is_ai(s) else "", int(p.get("ll", 0))], 17, StoryStyle.GOLD if s == seat else StoryStyle.TEXT))
		info.add_child(StoryStyle.label(state, 13, StoryStyle.DIM))
		for entry: Dictionary in log:
			if str(entry.get("pilot", "")) == pid:
				info.add_child(StoryStyle.label("• " + str(entry.get("text", "")), 14, StoryStyle.TEXT, 260))
		for r: Dictionary in story.reserves.get(pid, []):
			info.add_child(StoryStyle.label("+ " + str(r["name"]), 13, StoryStyle.GREEN, 260))
		# Bonds with the rest of the squad (and the Bonded talent's bondmate).
		var bond_bits := PackedStringArray()
		for o: String in campaign.pilots:
			if o != pid and story.is_alive(o):
				var b := Bonds.get_bond(story, pid, o)
				if str(b["label"]) != "Squadmates":
					bond_bits.append("%s: %s" % [campaign.pilots[o].get("callsign", ""), b["label"]])
		if not bond_bits.is_empty():
			info.add_child(StoryStyle.label("Bonds: " + ", ".join(bond_bits), 13, StoryStyle.BLUE, 260))
		if str(p.get("bondmate", "")) != "":
			info.add_child(StoryStyle.label("Bondmate (Bonded talent): %s" % campaign.pilots.get(str(p["bondmate"]), {}).get("callsign", "?"), 13, StoryStyle.GOLD, 260))
		if s == seat and Bonds.has_bonded(p):
			var ob := OptionButton.new()
			ob.add_item("Choose a bondmate...")
			for o: String in campaign.pilots:
				if o != pid and story.is_alive(o):
					ob.add_item(str(campaign.pilots[o].get("callsign", "")))
					ob.set_item_metadata(ob.item_count - 1, o)
			ob.item_selected.connect(func(i: int) -> void:
				if i <= 0:
					return
				var r := engine.submit(story, campaign, {"type": "set_bondmate", "seat": seat, "params": {"pilot": pid, "mate": ob.get_item_metadata(i)}})
				if not r["ok"]:
					_intro.text = "✕ " + str(r["reason"])
				story_events.emit(r["events"])
				refresh())
			info.add_child(ob)
		if not story.first_choice_for(pid).is_empty():
			info.add_child(StoryStyle.label("Waiting on a choice", 13, StoryStyle.RED))
		_cards.add_child(card)
	panel.refresh()


func _end() -> void:
	var r := engine.submit(story, campaign, {"type": "end_downtime", "seat": "gm", "params": {}})
	if not r["ok"]:
		_intro.text = "✕ " + str(r["reason"])
		return
	visible = false
	story_events.emit(r["events"])
