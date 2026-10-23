class_name DecisionPanel
extends PanelContainer
## The squad's vote on a big story choice (Decisions): every option side by side; when someone
## votes, their pilot's portrait (or their mech's picture: StorySettings.vote_picture) appears
## above the option they picked, with their name over it, and AI squadmates' pictures go with
## their human's pick. Votes can change until it's settled. If the humans split, a countdown
## (the host's setting) reads "Settle it in the arena: Left (Ana, Joss) vs Right (Mara, Theo)",
## then arena_requested fires for the flow to run the fight (teams by vote). The first time it
## explains it plainly: nobody dies, the mechs just get beaten up, the winning side decides.

signal story_events(events: Array)
## The countdown ran out on the host: the flow starts the player-vs-player fight.
signal arena_requested(split: Dictionary)

var engine: StoryEngine
var story: StoryState
var campaign: Campaign
var db: ContentDB
var local_seat := "p1"
var countdown_left := 0.0

var _title: Label
var _cols: HBoxContainer
var _status: Label
var _note: Label
var _arena_sent := false


func _init() -> void:
	name = "DecisionPanel"
	visible = false
	add_theme_stylebox_override("panel", StoryStyle.panel(StoryStyle.GOLD))
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -390
	offset_right = 390
	offset_top = 90
	custom_minimum_size = Vector2(780, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	_title = StoryStyle.label("", 22, StoryStyle.GOLD, 720)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	box.add_child(StoryStyle.label("The squad decides together. Pick one; you can change your mind until it's settled.", 15, StoryStyle.DIM, 720))
	_cols = HBoxContainer.new()
	_cols.alignment = BoxContainer.ALIGNMENT_CENTER
	_cols.add_theme_constant_override("separation", 18)
	box.add_child(_cols)
	_status = StoryStyle.label("", 18, StoryStyle.TEXT, 720)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_status)
	_note = StoryStyle.label("", 15, StoryStyle.BLUE, 720)
	_note.visible = false
	box.add_child(_note)


func bind(e: StoryEngine, s: StoryState, c: Campaign, content: ContentDB, seat: String) -> void:
	engine = e
	story = s
	campaign = c
	db = content
	local_seat = seat


## Shows or updates the vote from story events (call with every batch).
func show_events(events: Array) -> void:
	for e: Dictionary in events:
		match str(e.get("type", "")):
			"decision_started", "decision_vote", "party_split_update":
				refresh()
			"party_split":
				countdown_left = float(e.get("countdown", Decisions.COUNTDOWN))
				_arena_sent = false
				_note.text = str(e.get("note", ""))
				_note.visible = e.has("note")
				refresh()
			"split_started":
				countdown_left = 0.0
				refresh()
			"decision_made":
				visible = false
				countdown_left = 0.0


func refresh() -> void:
	var d := Decisions.current(story)
	if d.is_empty():
		visible = false
		return
	visible = true
	_title.text = str(d.get("prompt", "Decide"))
	for c in _cols.get_children():
		c.queue_free()
	var sides := Decisions.sides(story)
	var mine := str((d.get("votes", {}) as Dictionary).get(local_seat, ""))
	var can_vote := not story.is_ai(local_seat) and not bool(d.get("locked", false)) and Decisions.humans(story).has(local_seat)
	for o: Dictionary in d.get("options", []):
		var id := str(o["id"])
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(220, 0)
		col.add_theme_constant_override("separation", 6)
		var voters := HFlowContainer.new()
		voters.custom_minimum_size = Vector2(220, 118)
		for seat: String in sides.get(id, []):
			voters.add_child(_voter_card(seat))
		col.add_child(voters)
		var b := StoryStyle.button(("✔ " if mine == id else "") + str(o.get("label", id)), 18, true)
		b.custom_minimum_size = Vector2(220, 52)
		b.disabled = not can_vote
		b.pressed.connect(func() -> void: _vote(id))
		col.add_child(b)
		_cols.add_child(col)
	var waiting: Array = Decisions.humans(story).filter(func(h: String) -> bool: return not (d.get("votes", {}) as Dictionary).has(h))
	if d.has("split"):
		_status.text = "%s   %d" % [_arena_text(d), ceili(countdown_left)] if countdown_left > 0.0 else _arena_text(d)
		_status.add_theme_color_override("font_color", StoryStyle.RED)
	elif not waiting.is_empty():
		_status.text = "Waiting for: %s" % ", ".join(PackedStringArray(waiting.map(func(s: String) -> String: return _callsign(s))))
		_status.add_theme_color_override("font_color", StoryStyle.DIM)
	else:
		_status.text = ""


func _arena_text(d: Dictionary) -> String:
	var parts: Array = []
	var sides := Decisions.sides(story)
	for o: Dictionary in d.get("options", []):
		var who: Array = (sides.get(str(o["id"]), []) as Array).map(func(s: String) -> String: return _callsign(s))
		if not who.is_empty():
			parts.append("%s (%s)" % [o.get("label", o["id"]), ", ".join(PackedStringArray(who))])
	return "Settle it in the arena: %s" % " vs ".join(PackedStringArray(parts))


func _callsign(seat: String) -> String:
	return str(campaign.pilots.get(story.pilot_of_seat(seat), {}).get("callsign", seat))


## A voter: their name over their pilot's portrait, or their mech's picture.
func _voter_card(seat: String) -> Control:
	var card := VBoxContainer.new()
	card.custom_minimum_size = Vector2(68, 110)
	var nm := StoryStyle.label(_callsign(seat) + (" (AI)" if story.is_ai(seat) else ""), 13, StoryStyle.TEXT)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(nm)
	var p: Dictionary = campaign.pilots.get(story.pilot_of_seat(seat), {})
	if StorySettings.vote_picture() == "mech":
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(64, 64)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var frame := _frame_of(p)
		var path := "res://assets/icons/lancer/%s.svg" % _maker_icon(str(frame.get("source", "")))
		if ResourceLoader.exists(path):
			icon.texture = load(path)
		card.add_child(icon)
		card.add_child(StoryStyle.label(str(frame.get("name", "Mech")), 12, StoryStyle.DIM))
	else:
		var face := PortraitArt.new()
		face.custom_minimum_size = Vector2(64, 80)
		face.set_look(PortraitArt.look_for_pilot(p))
		card.add_child(face)
	return card


func _frame_of(p: Dictionary) -> Dictionary:
	if db == null:
		return {}
	for m: Dictionary in p.get("mechs", []):
		if m.get("id", "") == p.get("active_mech", "") or p.get("mechs", []).size() == 1:
			return db.frame(str(m.get("frame", Campaign.STARTER_FRAME)))
	return db.frame(Campaign.STARTER_FRAME)


static func _maker_icon(source: String) -> String:
	match source.to_upper():
		"IPS-N", "IPSN":
			return "ipsn"
		"SSC":
			return "ssc"
		"HORUS":
			return "horus"
		"HA", "HARRISON ARMORY":
			return "ha"
	return "gms"


func _vote(option: String) -> void:
	var r := engine.submit(story, campaign, {"type": "decide", "seat": local_seat, "params": {"option": option}})
	if r["ok"]:
		story_events.emit(r["events"])
		show_events(r["events"])


func _process(delta: float) -> void:
	if not visible or countdown_left <= 0.0:
		return
	countdown_left = maxf(0.0, countdown_left - delta)
	var d := Decisions.current(story)
	if d.has("split"):
		_status.text = "%s   %d" % [_arena_text(d), ceili(countdown_left)]
	if countdown_left <= 0.0 and not _arena_sent and d.has("split"):
		_arena_sent = true
		arena_requested.emit({"id": d.get("id", ""), "sides": Decisions.sides(story), "fight": d.get("fight", {}), "options": d.get("options", [])})
