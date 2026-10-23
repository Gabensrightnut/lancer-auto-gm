extends Control
## The squad-creation lobby screen (SquadLobby): four pilot slots side by side, the squad's
## shared history under them, and Start. Each slot: Join; then Create character (the builder
## and its look creator), Load saved (the roster), Save character, Ready; the sanity check's
## badge or what it changed. The host can Add bot, Randomize a bot, or Kick.

var lobby: SquadLobby
var roster := CharacterRoster.new()
var _slots_box: HBoxContainer
var _history_box: VBoxContainer
var _start: Button
var _status: Label
var _picker: PanelContainer


func _ready() -> void:
	if MenuSession.squad_lobby == null:
		var c := Campaign.create(str(MenuSession.new_campaign_settings.get("name", "New campaign")), {"start_ll": int(MenuSession.new_campaign_settings.get("start_ll", 0))})
		MenuSession.squad_lobby = SquadLobby.new(MenuSession.content(), c)
	lobby = MenuSession.squad_lobby
	lobby.changed.connect(_refresh)
	var col := MenuTheme.screen(self, "Your squad", "Up to four pilots. Join a slot, make or load a character, and press Ready.", _back)
	_slots_box = HBoxContainer.new()
	_slots_box.add_theme_constant_override("separation", 16)
	_slots_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(_slots_box)
	var hist := MenuTheme.panel("How these people know each other", MenuTheme.ACCENT, "pilot")
	_history_box = MenuTheme.body(hist)
	col.add_child(hist)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 14)
	_status = MenuTheme.label("", 16, MenuTheme.WARN)
	bottom.add_child(_status)
	_start = Button.new()
	_start.text = "START  ›"
	_start.custom_minimum_size = Vector2(220, 56)
	_start.add_theme_font_override("font", MenuTheme.bold_font())
	_start.pressed.connect(_on_start)
	bottom.add_child(_start)
	col.add_child(bottom)
	_refresh()


func _refresh() -> void:
	for ch in _slots_box.get_children():
		ch.queue_free()
	for seat: String in SquadLobby.SEATS:
		_slots_box.add_child(_slot(seat))
	for ch in _history_box.get_children():
		ch.queue_free()
	if lobby.history.is_empty():
		_history_box.add_child(MenuTheme.label("Make two or more pilots: their shared past comes from their backgrounds and origins.", 15, MenuTheme.MUTED, true))
	for h: Dictionary in lobby.history:
		_history_box.add_child(MenuTheme.label("• " + str(h.get("text", "")), 15, MenuTheme.TEXT, true))
	if not lobby.history.is_empty():
		var again := Button.new()
		again.text = "Tell it differently"
		again.pressed.connect(lobby.reroll_history)
		_history_box.add_child(again)
	var why := lobby.can_start()
	_start.disabled = why != ""
	_status.text = why


func _slot(seat: String) -> Control:
	var s: Dictionary = lobby.slots[seat]
	var p := MenuTheme.panel("Slot %s" % seat.trim_prefix("p"), MenuTheme.ACCENT if str(s["state"]) != "empty" else MenuTheme.MUTED, "pilot")
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var b := MenuTheme.body(p)
	match str(s["state"]):
		"empty":
			b.add_child(MenuTheme.label("(empty)", 28, MenuTheme.MUTED))
			b.add_child(_button("Join", func() -> void: lobby.claim(seat, "You")))
			b.add_child(_button("Add bot", func() -> void: lobby.add_bot(seat, _first_human()), "An AI squadmate. It follows its human's choices."))
		_:
			var pilot: Dictionary = s["pilot"]
			if pilot.is_empty():
				b.add_child(MenuTheme.label("%s: make your pilot." % (str(s["owner"]) if str(s["owner"]) != "" else "Bot"), 16, MenuTheme.TEXT, true))
			else:
				var face := PortraitArt.new()
				face.custom_minimum_size = Vector2(150, 170)
				face.set_look(pilot.get("portrait", {}), "neutral")
				b.add_child(face)
				b.add_child(MenuTheme.label("%s \"%s\"" % [pilot.get("name", ""), pilot.get("callsign", "")], 18, MenuTheme.TEXT, true))
				var mech: Dictionary = (pilot.get("mechs", [{}]) as Array)[0] if not (pilot.get("mechs", []) as Array).is_empty() else {}
				b.add_child(MenuTheme.label(str(MenuSession.content().frame(str(mech.get("frame", ""))).get("name", mech.get("frame", ""))), 15, MenuTheme.MUTED))
				if str(pilot.get("persona", "")) != "":
					b.add_child(MenuTheme.label("Personality: %s" % pilot["persona"], 14, MenuTheme.MUTED))
				b.add_child(_sanity(s))
			b.add_child(_button("Create character" if pilot.is_empty() else "Edit character", func() -> void: _edit(seat)))
			b.add_child(_button("Load saved", func() -> void: _pick_saved(seat)))
			if not pilot.is_empty():
				b.add_child(_button("Save character", func() -> void:
					roster.save(CharacterRoster.from_pilot(pilot))
					_status.text = "Saved %s to your characters." % pilot.get("callsign", "")))
				var ready := CheckButton.new()
				ready.text = "Ready"
				ready.button_pressed = bool(s["ready"])
				ready.toggled.connect(func(on: bool) -> void: lobby.set_ready(seat, on))
				b.add_child(ready)
			if str(s["state"]) == "bot":
				b.add_child(_button("Randomize", func() -> void: lobby.randomize_bot(seat)))
			b.add_child(_button("Leave" if str(s["state"]) == "claimed" else "Remove bot", func() -> void: lobby.release(seat)))
	return p


## The sanity check: a green badge, or what was removed or changed and why.
func _sanity(s: Dictionary) -> Control:
	if bool(s["passed"]):
		return MenuTheme.chip("Passed sanity check", MenuTheme.GOOD)
	var l := MenuTheme.label("Sanity check:\n" + CharacterSanity.describe(s["report"]), 13, MenuTheme.WARN, true)
	l.custom_minimum_size = Vector2(200, 0)
	return l


func _button(text: String, on_press: Callable, tip: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(on_press)
	return b


func _first_human() -> String:
	for seat: String in SquadLobby.SEATS:
		if str(lobby.slots[seat]["state"]) == "claimed":
			return seat
	return "p1"


## "Create character" / "Edit character": the builder (and its look creator) on this slot's
## pilot; Done sends it back through the sanity check.
func _edit(seat: String) -> void:
	var pilot: Dictionary = lobby.slots[seat]["pilot"]
	if pilot.is_empty():
		pilot = lobby.campaign.new_pilot("New pilot", "Callsign")
		lobby.campaign.pilots.erase(pilot["id"])
		MenuSession.open_creator = true
	lobby.campaign.pilots[pilot["id"]] = pilot.duplicate(true)
	MenuSession.campaign = lobby.campaign
	MenuSession.builder_pilot = pilot["id"]
	MenuSession.squad_seat = seat
	MenuSession.back_to = "squad_lobby"
	MenuSession.go(self, "builder")


## "Load saved": the roster, with search and favourites; the pick is rebuilt for this campaign.
func _pick_saved(seat: String) -> void:
	if _picker != null:
		_picker.queue_free()
	_picker = MenuTheme.panel("Your saved characters", MenuTheme.ACCENT, "pilot")
	_picker.position = Vector2(200, 120)
	add_child(_picker)
	var b := MenuTheme.body(_picker)
	var search := LineEdit.new()
	search.placeholder_text = "Search by name or callsign"
	b.add_child(search)
	var list := VBoxContainer.new()
	b.add_child(list)
	var fill := func(q: String) -> void:
		for ch in list.get_children():
			ch.queue_free()
		var all := roster.list(q)
		if all.is_empty():
			list.add_child(MenuTheme.label("No saved characters yet. Use Save character on a pilot you like.", 15, MenuTheme.MUTED, true))
		for c: Dictionary in all:
			var row := HBoxContainer.new()
			var who := "%s%s \"%s\"" % ["★ " if bool(c["favourite"]) else "", c["identity"].get("name", ""), c["identity"].get("callsign", "")]
			row.add_child(MenuTheme.label(who, 16))
			var cid := str(c["id"])
			row.add_child(_button("Load", func() -> void:
				lobby.set_character(seat, roster.load_one(cid))
				_picker.queue_free()
				_picker = null))
			row.add_child(_button("★", func() -> void:
				roster.set_favourite(cid, not bool(c["favourite"]))
				_pick_saved(seat), "Favourite"))
			list.add_child(row)
	search.text_changed.connect(fill)
	fill.call("")
	b.add_child(_button("Close", func() -> void:
		_picker.queue_free()
		_picker = null))


func _on_start() -> void:
	if lobby.can_start() != "":
		return
	var s := MenuSession.new_campaign_settings
	MenuSession.campaign = null
	var c := GameFlow.start_story_campaign(MenuSession.store, MenuSession.content(), str(s.get("name", "Campaign")), 0, int(s.get("start_ll", 0)),
		str(s.get("preset", "Standard")), int(s.get("arcs", GameFlow.DEFAULT_ARCS)), "", str(s.get("fight_length", "standard")), lobby.squad())
	for k: String in s.get("options", {}):
		c.options[k] = s["options"][k]
	MenuSession.store.save_campaign(c)
	MenuSession.campaign = c
	MenuSession.squad_lobby = null
	MenuSession.go(self, "hub")


func _back() -> void:
	MenuSession.squad_lobby = null
	MenuSession.go(self, "main")
