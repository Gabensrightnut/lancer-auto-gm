extends Control
## Main menu: Continue / New campaign / Tutorial / Join online / Settings / Quit. The right side
## shows the form for whichever is picked.

var side: VBoxContainer
var join_status: Label
var continue_button: Button


func _ready() -> void:
	# Development QA: "qa:<mode>" launches the playtest driver (src/flow/dev/playtest_driver.gd).
	for a in OS.get_cmdline_user_args():
		if a.begins_with("qa:") and get_tree().root.get_node_or_null("PlaytestDriver") == null:
			var driver := PlaytestDriver.new()
			driver.name = "PlaytestDriver"
			get_tree().root.add_child.call_deferred(driver)
	theme = MenuTheme.theme()
	MenuTheme.backdrop(self)
	MenuSession.settings().apply(get_tree())
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 90 if s in ["left", "right"] else 70)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 90)
	margin.add_child(row)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 14)
	left.custom_minimum_size = Vector2(560, 0)
	row.add_child(left)
	var brand := HBoxContainer.new()
	brand.add_theme_constant_override("separation", 18)
	brand.add_child(MenuTheme.icon("lancer", 88, MenuTheme.ACCENT))
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", -6)
	titles.add_child(MenuTheme.heading("Lancer", 76))
	titles.add_child(MenuTheme.heading("TTRPG", 40, MenuTheme.ACCENT))
	brand.add_child(titles)
	left.add_child(brand)
	left.add_child(MenuTheme.label("An unofficial LANCER fan game", 20, MenuTheme.MUTED))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 40)
	left.add_child(gap)

	var saves := MenuSession.store.list()
	continue_button = MenuTheme.big_button("Continue", "campaign")
	continue_button.disabled = saves.is_empty()
	continue_button.pressed.connect(_show_continue)
	left.add_child(continue_button)
	var new_button := MenuTheme.big_button("New campaign", "encounter")
	new_button.pressed.connect(_show_new)
	left.add_child(new_button)
	var tutorial_button := MenuTheme.big_button("Tutorial", "pilot", MenuTheme.GOOD)
	tutorial_button.pressed.connect(_show_tutorial)
	left.add_child(tutorial_button)
	var join_button := MenuTheme.big_button("Join online", "orbital", MenuTheme.maker_color("IPS-N"))
	join_button.pressed.connect(_show_join)
	left.add_child(join_button)
	var settings_button := MenuTheme.big_button("Settings", "system")
	settings_button.pressed.connect(func() -> void:
		MenuSession.back_to = "main"
		MenuSession.go(self, "settings"))
	left.add_child(settings_button)
	var quit_button := MenuTheme.big_button("Quit", "deactivate")
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	left.add_child(quit_button)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	left.add_child(MenuTheme.label("Version %s  ·  LANCER is © Massif Press. Not an official product." % NetProtocol.game_version(), 14, MenuTheme.MUTED))

	side = VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(side)
	if "stage:tutorial" in OS.get_cmdline_user_args():
		_show_tutorial()  # screenshots
	elif saves.is_empty():
		_show_new()
	else:
		_show_continue()
	(continue_button if not saves.is_empty() else new_button).grab_focus()


func _panel(title: String, icon_name: String, accent: Color = MenuTheme.ACCENT) -> VBoxContainer:
	for c in side.get_children():
		c.queue_free()
	var p := MenuTheme.panel(title, accent, icon_name)
	p.custom_minimum_size = Vector2(720, 0)
	side.add_child(p)
	var body := MenuTheme.body(p)
	body.add_theme_constant_override("separation", 14)
	return body


func _show_continue() -> void:
	var body := _panel("Continue a campaign", "campaign")
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	for s: Dictionary in MenuSession.store.list().slice(0, 6):
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 64)
		var when := Time.get_datetime_string_from_unix_time(int(s["updated_at"]), true)
		b.text = "%s\n%s%s" % [s["name"], when, "   ·   mission in progress" if s["has_mission"] else ""]
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_load_campaign.bind(s["id"]))
		list.add_child(b)
	body.add_child(list)


func _show_new() -> void:
	var body := _panel("New campaign", "encounter")
	var name_edit := LineEdit.new()
	name_edit.text = "Campaign %d" % (MenuSession.store.list().size() + 1)
	body.add_child(_field("Campaign name", name_edit))
	var pilots := OptionButton.new()
	for n in [1, 2, 3, 4]:
		pilots.add_item("%d pilot%s" % [n, "" if n == 1 else "s"], n)
	pilots.select(3)
	body.add_child(_field("Squad size", pilots))
	var ll := OptionButton.new()
	for n in range(0, 13):
		ll.add_item("License Level %d%s" % [n, "  (book default)" if n == 0 else ""], n)
	body.add_child(_field("Pilots start at", ll))
	body.add_child(MenuTheme.label("New pilots start at License Level 0 with GMS gear only, as the core book says. Starting higher is a campaign option the book allows GMs to use.", 15, MenuTheme.MUTED, true))
	var preset := OptionButton.new()
	for p in LobbyModel.PRESETS:
		preset.add_item(p)
	body.add_child(_field("GM style", preset))
	var desc := MenuTheme.label("", 15, MenuTheme.MUTED, true)
	var show_desc := func(i: int) -> void: desc.text = str(GmSettings.presets().get(LobbyModel.PRESETS[i], {}).get("description", ""))
	preset.item_selected.connect(show_desc)
	show_desc.call(0)
	body.add_child(desc)
	var go := Button.new()
	go.text = "CREATE CAMPAIGN  ›"
	go.custom_minimum_size = Vector2(0, 54)
	go.add_theme_font_override("font", MenuTheme.bold_font())
	go.pressed.connect(func() -> void:
		var c := MenuSession.new_campaign(name_edit.text.strip_edges(), pilots.get_selected_id(), ll.get_selected_id(), LobbyModel.PRESETS[preset.selected])
		MenuSession.store.save_campaign(c)
		MenuSession.campaign = c
		MenuSession.lobby = null
		MenuSession.go(self, "lobby"))
	body.add_child(go)


## A new campaign opened the guided way (GameFlow.start_tutorial): a training base, a
## briefing, a drill that teaches one rule at a time, then debrief, level up and downtime.
func _show_tutorial() -> void:
	var body := _panel("Tutorial", "pilot", MenuTheme.GOOD)
	body.add_child(MenuTheme.label("New to LANCER? Start here. Your pilot reports to a Union training base: a briefing, then a live-fire drill against training drones that teaches one thing at a time (moving, attacking, cover, heat, tech), then the debrief, leveling up and your first downtime. An AI squadmate flies with you. It's a real campaign: keep playing after the drill.", 17, MenuTheme.TEXT, true))
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var names := NameGen.new(rng)
	var name_edit := LineEdit.new()
	name_edit.text = names.pilot_name()
	body.add_child(_field("Your pilot's name", name_edit))
	var callsign := LineEdit.new()
	callsign.text = names.callsign()
	body.add_child(_field("Callsign", callsign))
	var look := {"portrait": PortraitSpec.randomize(rng)}
	var look_row := HBoxContainer.new()
	look_row.add_theme_constant_override("separation", 14)
	var face := PortraitArt.new()
	face.custom_minimum_size = Vector2(84, 100)
	face.set_look(look["portrait"])
	look_row.add_child(face)
	var look_button := Button.new()
	look_button.text = "Design your pilot's look"
	look_button.icon = MenuTheme.icon_texture("pilot", 22, MenuTheme.TEXT)
	look_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	look_button.pressed.connect(func() -> void:
		var pc := PilotCreator.new()
		add_child(pc)
		pc.open(look["portrait"])
		pc.confirmed.connect(func(p: Dictionary) -> void:
			look["portrait"] = p
			face.set_look(p)
			pc.queue_free())
		pc.cancelled.connect(pc.queue_free))
	look_row.add_child(look_button)
	body.add_child(look_row)
	var hints := CheckButton.new()
	hints.text = "Teaching hints: explain each rule the first time it comes up"
	hints.button_pressed = true
	body.add_child(hints)
	body.add_child(MenuTheme.label("You can turn hints off any time from the in-game menu.", 15, MenuTheme.MUTED, true))
	var go := Button.new()
	go.text = "START THE TUTORIAL  ›"
	go.custom_minimum_size = Vector2(0, 54)
	go.add_theme_font_override("font", MenuTheme.bold_font())
	go.pressed.connect(func() -> void:
		MenuSession.campaign = null
		MenuSession.lobby = null
		var c := GameFlow.start_tutorial(MenuSession.store, MenuSession.content(), name_edit.text.strip_edges(), callsign.text.strip_edges(), hints.button_pressed, look["portrait"])
		MenuSession.campaign = c
		MenuSession.go(self, "hub"))
	body.add_child(go)


func _show_join() -> void:
	var accent := MenuTheme.maker_color("IPS-N")
	var body := _panel("Join a friend's game", "orbital", accent)
	var code := LineEdit.new()
	code.placeholder_text = "ROOM CODE (e.g. K7M2QX)"
	code.max_length = 8
	code.add_theme_font_size_override("font_size", 30)
	code.custom_minimum_size = Vector2(0, 58)
	body.add_child(_field("Room code", code))
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "Your name"
	body.add_child(_field("Your name", name_edit))
	body.add_child(MenuTheme.label("You need the same game version and content packs as the host. No ports to open: the game connects you directly.", 15, MenuTheme.MUTED, true))
	join_status = MenuTheme.label("", 16, MenuTheme.WARN, true)
	body.add_child(join_status)
	var go := Button.new()
	go.text = "JOIN  ›"
	go.custom_minimum_size = Vector2(0, 54)
	go.pressed.connect(func() -> void:
		var room := NetProtocol.normalize_room_code(code.text)
		if room == "":
			join_status.text = "A room code is 6 letters and numbers."
			return
		join_status.text = "Connecting..."
		var net := MenuSession.net(self)
		if net == null:
			join_status.text = "Online play isn't available here."
			return
		var client: NetClient = net.join_online(room, name_edit.text.strip_edges())
		MenuSession.lobby = LobbyModel.for_client(client)
		client.joined.connect(func(_seat: String) -> void: MenuSession.go(self, "lobby"))
		client.refused.connect(func(_c: String, why: String) -> void: join_status.text = why)
		client.join_failed.connect(func(why: String) -> void: join_status.text = why))
	body.add_child(go)
	var rejoin := NetClient.last_session()
	if not rejoin.is_empty():
		var again := Button.new()
		again.text = "Rejoin your last game (%s, seat %s)" % [rejoin.get("room", ""), rejoin.get("seat", "")]
		again.pressed.connect(func() -> void:
			var net := MenuSession.net(self)
			var c: NetClient = net.rejoin_last() if net != null else null
			if c != null:
				MenuSession.lobby = LobbyModel.for_client(c)
				c.joined.connect(func(_s: String) -> void: MenuSession.go(self, "lobby")))
		body.add_child(again)


func _load_campaign(id: String) -> void:
	var r := MenuSession.store.load_campaign(id)
	if r["error"] != "":
		var body := _panel("Couldn't load", "destroyed", MenuTheme.BAD)
		body.add_child(MenuTheme.label(r["error"], 18, MenuTheme.TEXT, true))
		return
	MenuSession.campaign = r["campaign"]
	MenuSession.lobby = null
	if MenuSession.store.has_mission(id):
		var s := GameFlow.resume_mission(MenuSession.store, MenuSession.campaign, MenuSession.content())
		if s != null:
			var net := MenuSession.net(self)
			if net != null and not (s.host.export_seats()["tokens"] as Dictionary).is_empty():
				# Friends were in this mission: reopen the same room and wait for them.
				net.host = s.host
				net.open_online(s.host, GameFlow.last_room)
			MenuSession.go(self, "battle")
			return
	MenuSession.go(self, "hub" if GameFlow.is_story(MenuSession.campaign) else "lobby")


static func _field(label_text: String, control: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	v.add_child(MenuTheme.label(label_text.to_upper(), 14, MenuTheme.MUTED))
	v.add_child(control)
	return v
