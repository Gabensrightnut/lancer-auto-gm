extends Control
## The lobby: seats (you / AI / open / reserved), pilots, fill-with-AI, content packs, GM style,
## grid shape, ready-up and the reasons the mission can't start yet. Joining players see the
## same screen read-only, with their own Ready button. All logic is in LobbyModel.

var lobby: LobbyModel
var seats_box: VBoxContainer
var side_box: VBoxContainer
var problems_box: VBoxContainer
var ready_button: Button
var start_button: Button
var room_label: Label
var squad_auto: CheckButton
var _refreshing := false


func _ready() -> void:
	if MenuSession.lobby == null:
		MenuSession.ensure_campaign()
		MenuSession.lobby = LobbyModel.for_host(MenuSession.campaign, MenuSession.content())
	lobby = MenuSession.lobby
	var subtitle := lobby.campaign.name if lobby.is_host else "Joined %s's game" % str(lobby.remote.get("campaign", "a"))
	var col := MenuTheme.screen(self, "Lobby", subtitle, _back)
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 24)
	main.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(main)

	var seats_panel := MenuTheme.panel("Squad", MenuTheme.ACCENT, "pilot")
	seats_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seats_panel.size_flags_stretch_ratio = 1.7
	main.add_child(seats_panel)
	var sb := MenuTheme.body(seats_panel)
	seats_box = VBoxContainer.new()
	seats_box.add_theme_constant_override("separation", 10)
	sb.add_child(seats_box)
	if lobby.is_host:
		var add := Button.new()
		add.text = "+ New pilot"
		add.icon = MenuTheme.icon_texture("pilot", 22, MenuTheme.TEXT)
		add.tooltip_text = "Make a new pilot for this campaign: their look first, then their build. Put them in a seat with the pilot list."
		add.pressed.connect(_new_pilot)
		sb.add_child(add)
	var fill := CheckButton.new()
	fill.text = "Fill empty seats with AI pilots (a friend who joins later takes over)"
	fill.button_pressed = bool(lobby.options.get("fill_empty_with_ai", false))
	fill.disabled = not lobby.is_host
	fill.toggled.connect(func(on: bool) -> void: lobby.set_fill_empty(on))
	sb.add_child(fill)
	squad_auto = CheckButton.new()
	squad_auto.text = "AI squadmates take their turns on their own (you can still pick them earlier)"
	squad_auto.tooltip_text = "Once only AI squadmates are left to act, they go by themselves, best pick first. Off by default online, so friends see every choice."
	if lobby.is_host and not lobby.options.has("_auto_set"):
		lobby.options["ai_squad_auto"] = MenuSession.settings().ai_squad_auto
		lobby.options["_auto_set"] = true
	squad_auto.button_pressed = bool(lobby.options.get("ai_squad_auto", true))
	squad_auto.disabled = not lobby.is_host
	squad_auto.toggled.connect(func(on: bool) -> void: lobby.options["ai_squad_auto"] = on)
	sb.add_child(squad_auto)
	var online := HBoxContainer.new()
	online.add_theme_constant_override("separation", 12)
	room_label = MenuTheme.label("", 18, MenuTheme.MUTED)
	if lobby.is_host:
		var host_button := Button.new()
		host_button.text = "Invite friends online"
		host_button.icon = MenuTheme.icon_texture("orbital", 22, MenuTheme.TEXT)
		host_button.pressed.connect(_host_online)
		online.add_child(host_button)
	online.add_child(room_label)
	sb.add_child(online)

	side_box = VBoxContainer.new()
	side_box.add_theme_constant_override("separation", 18)
	side_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_child(side_box)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 18)
	col.add_child(bottom)
	problems_box = VBoxContainer.new()
	problems_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(problems_box)
	ready_button = Button.new()
	ready_button.toggle_mode = true
	ready_button.text = "READY"
	ready_button.custom_minimum_size = Vector2(200, 64)
	ready_button.add_theme_font_size_override("font_size", 24)
	ready_button.add_theme_font_override("font", MenuTheme.bold_font())
	ready_button.toggled.connect(func(on: bool) -> void:
		if not _refreshing:
			lobby.set_local_ready(on))
	bottom.add_child(ready_button)
	if lobby.is_host:
		start_button = Button.new()
		start_button.text = "START MISSION  ›"
		start_button.custom_minimum_size = Vector2(300, 64)
		start_button.add_theme_font_size_override("font_size", 24)
		start_button.add_theme_font_override("font", MenuTheme.bold_font())
		start_button.add_theme_stylebox_override("normal", MenuTheme.box(MenuTheme.ACCENT.darkened(0.25), MenuTheme.ACCENT, 1, 3))
		start_button.add_theme_stylebox_override("hover", MenuTheme.box(MenuTheme.ACCENT, MenuTheme.ACCENT.lightened(0.3), 1, 3))
		start_button.pressed.connect(_start)
		bottom.add_child(start_button)
	lobby.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	if not lobby.is_host and (lobby.started or not lobby.story_payload.is_empty() or str(lobby.client.view.get("phase", "")) == GameState.PHASE_COMBAT):
		_follow_host.call_deferred()
		return
	_refreshing = true
	for c in seats_box.get_children():
		c.queue_free()
	for r: Dictionary in lobby.rows():
		seats_box.add_child(_seat_row(r))
	for c in side_box.get_children():
		c.queue_free()
	side_box.add_child(_mission_panel())
	side_box.add_child(_packs_panel())
	for c in problems_box.get_children():
		c.queue_free()
	for m: Dictionary in lobby.messages.slice(-2):
		problems_box.add_child(_note(m["text"], MenuTheme.BAD if m["kind"] == "error" else MenuTheme.WARN))
	var problems := lobby.start_problems()
	if problems.is_empty():
		problems_box.add_child(_note("All set. Start when you're ready.", MenuTheme.GOOD))
	for p: String in problems.slice(0, 3):
		problems_box.add_child(_note(p, MenuTheme.WARN))
	if problems.size() > 3:
		problems_box.add_child(MenuTheme.label("…and %d more" % (problems.size() - 3), 15, MenuTheme.MUTED))
	var mine_ready := false
	for r: Dictionary in lobby.rows():
		if (lobby.is_host and r["mode"] == "you") or (not lobby.is_host and lobby.client != null and r["seat"] == lobby.client.seat):
			mine_ready = mine_ready or r["ready"]
	ready_button.button_pressed = mine_ready
	ready_button.text = "✓ READY" if mine_ready else "READY"
	if start_button != null:
		start_button.disabled = not lobby.can_start()
	_refreshing = false


func _seat_row(r: Dictionary) -> Control:
	var accent := MenuTheme.maker_color(r.get("source", "GMS"))
	var p := PanelContainer.new()
	var style := MenuTheme.box(MenuTheme.PANEL_2, MenuTheme.LINE, 1, 0)
	style.border_width_left = 5
	style.border_color = accent if r["mode"] != "open" or r["connected"] else MenuTheme.LINE
	p.add_theme_stylebox_override("panel", style)
	var v := VBoxContainer.new()
	p.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	v.add_child(h)
	h.add_child(MenuTheme.icon(MenuTheme.maker_icon(r.get("source", "GMS")), 48, accent))
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.custom_minimum_size = Vector2(420, 0)
	names.add_child(MenuTheme.heading(r["callsign"] if r["callsign"] != "" else r["seat"], 24))
	var mech_text: String = r["mech"] if r["frame"] == "" or r["frame"] in r["mech"] else "%s (%s)" % [r["mech"], r["frame"]]
	names.add_child(MenuTheme.label("%s  ·  %s  ·  LL %d" % [r["pilot"], mech_text, r["ll"]], 15, MenuTheme.MUTED))
	h.add_child(names)
	var status := HBoxContainer.new()
	status.add_theme_constant_override("separation", 6)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if r.get("me", false):
		status.add_child(MenuTheme.chip("You", MenuTheme.TEXT))
	elif r.get("host_seat", false):
		status.add_child(MenuTheme.chip("Host", MenuTheme.maker_color("IPS-N").lightened(0.2)))
	else:
		_status_chip(status, r)
	if r["ready"] and not r["ai"]:
		status.add_child(MenuTheme.chip("Ready", MenuTheme.GOOD))
	if int(r.get("unspent", 0)) > 0 and lobby.is_host:
		var c := MenuTheme.chip("%d point%s to spend" % [r["unspent"], "" if r["unspent"] == 1 else "s"], MenuTheme.WARN)
		c.tooltip_text = "This pilot leveled up. Open Edit build to choose new skills, talents, licenses or mech skills."
		status.add_child(c)
	h.add_child(status)
	if lobby.is_host:
		var mode := OptionButton.new()
		mode.custom_minimum_size = Vector2(230, 0)
		for m in LobbyModel.MODES:
			mode.add_item(LobbyModel.MODE_LABELS[m])
		mode.select(LobbyModel.MODES.find(r["mode"]))
		mode.item_selected.connect(func(i: int) -> void: lobby.set_mode(r["seat"], LobbyModel.MODES[i]))
		mode.tooltip_text = "Who flies this mech: you, an AI pilot, or a friend who joins online."
		h.add_child(mode)
		var pilot := OptionButton.new()
		pilot.custom_minimum_size = Vector2(170, 0)
		var ids := lobby.campaign.pilots.keys()
		ids.sort()
		for i in range(ids.size()):
			pilot.add_item(str(lobby.campaign.pilots[ids[i]].get("callsign", ids[i])))
			if ids[i] == r["pilot_id"]:
				pilot.select(i)
		pilot.item_selected.connect(func(i: int) -> void: lobby.assign_pilot(r["seat"], ids[i]))
		pilot.tooltip_text = "Which pilot sits in this seat (picking one in use swaps them)."
		h.add_child(pilot)
		var edit := Button.new()
		edit.text = "Edit build"
		edit.icon = MenuTheme.icon_texture("frame", 22, MenuTheme.TEXT)
		edit.pressed.connect(func() -> void:
			MenuSession.builder_pilot = r["pilot_id"]
			MenuSession.back_to = "lobby"
			MenuSession.go(self, "builder"))
		h.add_child(edit)
	if not r["problems"].is_empty():
		v.add_child(_note("%s's build isn't legal: %s" % [r["callsign"], r["problems"][0]], MenuTheme.BAD))
	return p


func _status_chip(status: HBoxContainer, r: Dictionary) -> void:
	match r["mode"]:
		"you":
			status.add_child(MenuTheme.chip("You", MenuTheme.TEXT))
		"ai":
			status.add_child(MenuTheme.chip("AI pilot", MenuTheme.maker_color("HORUS").lightened(0.2)))
		_:
			if r["connected"] and not r["ai"]:
				status.add_child(MenuTheme.chip(r["player"], MenuTheme.maker_color("IPS-N").lightened(0.2)))
			elif r["ai"]:
				status.add_child(MenuTheme.chip("AI until a friend joins", MenuTheme.maker_color("HORUS").lightened(0.2)))
			else:
				status.add_child(MenuTheme.chip("Reserved" if r["mode"] == "reserved" else "Open", MenuTheme.MUTED))


func _mission_panel() -> Control:
	var p := MenuTheme.panel("Mission", MenuTheme.ACCENT, "encounter")
	var b := MenuTheme.body(p)
	var briefing: String = lobby.mission.briefing if lobby.is_host and lobby.mission != null else str(lobby.remote.get("briefing", ""))
	b.add_child(MenuTheme.label(briefing, 17, MenuTheme.TEXT, true))
	b.add_child(_caption("GM style"))
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 6)
	for name: String in LobbyModel.PRESETS:
		var btn := Button.new()
		btn.text = name
		btn.toggle_mode = true
		btn.button_pressed = lobby.options.get("preset", "") == name
		btn.disabled = not lobby.is_host
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.tooltip_text = str(GmSettings.presets().get(name, {}).get("description", ""))
		btn.pressed.connect(func() -> void: lobby.set_preset(name))
		presets.add_child(btn)
	b.add_child(presets)
	b.add_child(MenuTheme.label(str(GmSettings.presets().get(lobby.options.get("preset", ""), {}).get("description", "")), 15, MenuTheme.MUTED, true))
	b.add_child(_caption("Who is the GM"))
	var gm_row := HBoxContainer.new()
	gm_row.add_theme_constant_override("separation", 6)
	var gm_now := "ai" if not lobby.options.get("human_gm", false) else str(lobby.options.get("gm_where", "local"))
	for opt: Array in LobbyModel.GM_CHOICES:
		var btn := Button.new()
		btn.text = opt[1]
		btn.toggle_mode = true
		btn.button_pressed = gm_now == opt[0]
		btn.disabled = not lobby.is_host
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.tooltip_text = opt[2]
		var id: String = opt[0]
		btn.pressed.connect(func() -> void: lobby.set_human_gm(id != "ai", id if id != "ai" else "local"))
		gm_row.add_child(btn)
	b.add_child(gm_row)
	var gm_text := ""
	for opt: Array in LobbyModel.GM_CHOICES:
		if opt[0] == gm_now:
			gm_text = opt[2]
	match lobby.gm_status() if lobby.is_host else "":
		"joined":
			gm_text += " The GM is here."
		"waiting":
			gm_text += " Waiting for them to join."
	b.add_child(MenuTheme.label(gm_text, 15, MenuTheme.MUTED, true))
	b.add_child(_caption("Fight length"))
	var lengths := HBoxContainer.new()
	lengths.add_theme_constant_override("separation", 6)
	var fl: Dictionary = GmSettings.fight_lengths()
	for id: String in ["short", "standard", "long"]:
		var btn := Button.new()
		btn.text = str(fl.get(id, {}).get("label", id.capitalize()))
		btn.toggle_mode = true
		btn.button_pressed = lobby.options.get("fight_length", "standard") == id
		btn.disabled = not lobby.is_host
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.tooltip_text = str(fl.get(id, {}).get("description", ""))
		btn.pressed.connect(func() -> void: lobby.set_fight_length(id))
		lengths.add_child(btn)
	b.add_child(lengths)
	b.add_child(MenuTheme.label(str(fl.get(lobby.options.get("fight_length", "standard"), {}).get("description", "")) + " Rules like HP and damage never change.", 15, MenuTheme.MUTED, true))
	b.add_child(_caption("Battle grid"))
	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 6)
	for shape in [["hex", "Hexes"], ["square", "Squares"]]:
		var btn := Button.new()
		btn.text = shape[1]
		btn.toggle_mode = true
		btn.button_pressed = lobby.options.get("shape", "hex") == shape[0]
		btn.disabled = not lobby.is_host
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(func() -> void: lobby.set_shape(shape[0]))
		grid.add_child(btn)
	b.add_child(grid)
	return p


func _packs_panel() -> Control:
	var p := MenuTheme.panel("Content packs", MenuTheme.maker_color("SSC"), "content_manager")
	var b := MenuTheme.body(p)
	var installed := MenuSession.library.installed() if lobby.is_host else []
	var on: Array = lobby.campaign.packs if lobby.is_host else lobby.remote.get("packs", [])
	if lobby.is_host and installed.is_empty():
		b.add_child(MenuTheme.label("No content packs installed. Put .lcp files (from Massif's supplements or the NPC pack) in your packs folder to add frames, gear and NPCs.", 15, MenuTheme.MUTED, true))
	for pack: ContentPack in installed:
		var check := CheckBox.new()
		var enabled := false
		for o: Dictionary in on:
			enabled = enabled or o.get("id", "") == pack.id
		check.text = "%s  %s  —  %s" % [pack.name, pack.version, pack.author] if pack.error == "" else "%s (can't be read: %s)" % [pack.path.get_file(), pack.error]
		check.button_pressed = enabled
		check.disabled = pack.error != ""
		check.toggled.connect(_toggle_pack.bind(pack))
		b.add_child(check)
	if not lobby.is_host:
		for o: Dictionary in on:
			b.add_child(MenuTheme.label("%s %s" % [o.get("name", ""), o.get("version", "")], 16))
		if on.is_empty():
			b.add_child(MenuTheme.label("Core book only.", 15, MenuTheme.MUTED))
	if lobby.is_host:
		var open := Button.new()
		open.text = "Open packs folder"
		open.pressed.connect(func() -> void:
			DirAccess.make_dir_recursive_absolute(PackLibrary.DIR)
			OS.shell_open(ProjectSettings.globalize_path(PackLibrary.DIR)))
		b.add_child(open)
	b.add_child(MenuTheme.label("Everyone in the game needs the same packs and versions.", 14, MenuTheme.MUTED, true))
	return p


func _toggle_pack(on: bool, pack: ContentPack) -> void:
	var list: Array = lobby.campaign.packs.filter(func(o: Dictionary) -> bool: return o.get("id", "") != pack.id)
	if on:
		list.append(pack.summary())
	lobby.campaign.packs = list
	lobby.set_packs(list, MenuSession.content())


## A new pilot: the look creator, then the builder, then back here.
func _new_pilot() -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var names := NameGen.new(rng)
	var p := lobby.campaign.new_pilot(names.pilot_name(), names.callsign())
	MenuSession.store.save_campaign(lobby.campaign)
	MenuSession.builder_pilot = str(p["id"])
	MenuSession.back_to = "lobby"
	MenuSession.open_creator = true
	MenuSession.go(self, "builder")


func _host_online() -> void:
	var net := MenuSession.net(self)
	if net == null or not net.online_available():
		room_label.text = "Online play isn't available in this build."
		return
	net.host = lobby.host
	lobby.options["ai_squad_auto"] = false  # online: friends see every choice
	squad_auto.button_pressed = false
	lobby.host.room_opened.connect(func(code: String) -> void:
		room_label.text = "Room code:  %s   (friends pick Join online and type it)" % code
		room_label.add_theme_color_override("font_color", MenuTheme.TEXT))
	lobby.host.open_failed.connect(func(why: String) -> void: room_label.text = why)
	room_label.text = "Opening a room..."
	net.open_online(lobby.host)


func _start() -> void:
	var s := GameFlow.start_mission(lobby, MenuSession.store)
	if s == null:
		_refresh()
		return
	var net := MenuSession.net(self)
	if net != null:
		net.host = s.host  # Keeps an online room open; the battle drives the AI itself.
		net.director = null
	MenuSession.go(self, "battle")


## Joining players follow the host into the battle (also when rejoining one in progress).
func _follow_host() -> void:
	if lobby.is_host or lobby.client == null:
		return
	if not lobby.story_payload.is_empty():
		# The host is at a story campaign's hub: play it there with them.
		GameFlow.join_story(lobby.client, MenuSession.content(), lobby.story_payload)
		MenuSession.go(self, "hub")
		return
	if lobby.started or str(lobby.client.view.get("phase", "")) == GameState.PHASE_COMBAT:
		GameFlow.session = BattleSession.for_client(lobby.client)
		MenuSession.go(self, "battle")


func _back() -> void:
	if lobby.is_host:
		MenuSession.store.save_campaign(lobby.campaign)
	else:
		var net := MenuSession.net(self)
		if net != null:
			net.leave()
	MenuSession.lobby = null
	MenuSession.go(self, "main")


func _note(text: String, color: Color) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var dot := ColorRect.new()
	dot.color = color
	dot.custom_minimum_size = Vector2(4, 20)
	h.add_child(dot)
	var l := MenuTheme.label(text, 16, color.lightened(0.15), true)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	return h


static func _caption(text: String) -> Label:
	return MenuTheme.label(text.to_upper(), 14, MenuTheme.MUTED)
