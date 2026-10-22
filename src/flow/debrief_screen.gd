extends Control
## Debrief after a mission: the outcome, what happened, each pilot's new License Level (with a
## shortcut to spend the new points in the builder), then the next mission or the main menu.
## The campaign is already saved when this shows.

var d: Dictionary


func _ready() -> void:
	d = GameFlow.debrief if not GameFlow.debrief.is_empty() else _example()
	var col := MenuTheme.screen(self, "Debrief", str(d.get("campaign", "")))
	var won: bool = d.get("outcome", "") == "players"
	var color := MenuTheme.GOOD if won else (MenuTheme.BAD if d.get("outcome", "") == "enemies" else MenuTheme.WARN)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)

	var result := MenuTheme.panel("", color)
	result.custom_minimum_size = Vector2(760, 0)
	var rb := MenuTheme.body(result)
	rb.add_theme_constant_override("separation", 16)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	head.add_child(MenuTheme.icon("achievement_3" if won else "destroyed", 96, color))
	var titles := VBoxContainer.new()
	titles.add_child(MenuTheme.heading(str(d.get("title", "Mission over")), 46, color))
	if str(d.get("operation", "")) != "":
		titles.add_child(MenuTheme.label("%s  ·  %s" % [d["operation"], d.get("sitrep", "")], 18, MenuTheme.MUTED))
	head.add_child(titles)
	rb.add_child(head)
	rb.add_child(MenuTheme.label(str(d.get("reason", "")), 20, MenuTheme.TEXT, true))
	if int(d.get("rounds", 0)) > 0:
		rb.add_child(MenuTheme.label("The fight lasted %d rounds." % int(d["rounds"]), 17, MenuTheme.MUTED))
	if d.get("client", false):
		rb.add_child(MenuTheme.label("The host saved the campaign. Your pilot's progress is in their campaign.", 17, MenuTheme.MUTED, true))
	else:
		rb.add_child(MenuTheme.label("Campaign saved. Mechs destroyed in the field are printed again at the next Full Repair, so everyone starts the next mission whole (Core p.82).", 16, MenuTheme.MUTED, true))
	row.add_child(result)

	var squad := MenuTheme.panel("Level up", MenuTheme.ACCENT, "license")
	squad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := MenuTheme.body(squad)
	if not (d.get("pilots", []) as Array).is_empty():
		sb.add_child(MenuTheme.label("After every mission each pilot gains a License Level: one more license rank, skill point, talent rank and mech skill point to spend (and a core bonus every third level).", 16, MenuTheme.MUTED, true))
	for p: Dictionary in d.get("pilots", []):
		var line := PanelContainer.new()
		var st := MenuTheme.box(MenuTheme.PANEL_2, MenuTheme.LINE, 1, 0)
		st.border_width_left = 4
		st.border_color = MenuTheme.ACCENT
		line.add_theme_stylebox_override("panel", st)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		var names := VBoxContainer.new()
		names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.add_child(MenuTheme.heading(str(p["callsign"]), 22))
		names.add_child(MenuTheme.label("%s  ·  %s%s" % [p["name"], p["mech"], "  ·  mech destroyed" if p.get("mech_destroyed", false) else ""], 15, MenuTheme.MUTED))
		h.add_child(names)
		h.add_child(MenuTheme.chip("LL %d → %d" % [p["old_ll"], p["new_ll"]], MenuTheme.GOOD))
		var spend := Button.new()
		spend.text = "Spend points"
		spend.icon = MenuTheme.icon_texture("frame", 22, MenuTheme.TEXT)
		spend.pressed.connect(func() -> void:
			MenuSession.builder_pilot = str(p["id"])
			MenuSession.back_to = "debrief"
			MenuSession.go(self, "builder"))
		h.add_child(spend)
		line.add_child(h)
		sb.add_child(line)
	row.add_child(squad)

	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 14)
	var menu := Button.new()
	menu.text = "Main menu"
	menu.custom_minimum_size = Vector2(220, 60)
	menu.pressed.connect(func() -> void:
		GameFlow.debrief = {}
		MenuSession.lobby = null
		MenuSession.go(self, "main"))
	bottom.add_child(menu)
	if not d.get("client", false):
		var next := Button.new()
		next.text = "NEXT MISSION  ›"
		next.custom_minimum_size = Vector2(320, 60)
		next.add_theme_font_override("font", MenuTheme.bold_font())
		next.add_theme_font_size_override("font_size", 24)
		next.add_theme_stylebox_override("normal", MenuTheme.box(MenuTheme.ACCENT.darkened(0.25), MenuTheme.ACCENT, 1, 3))
		next.pressed.connect(func() -> void:
			GameFlow.debrief = {}
			var c := MenuSession.ensure_campaign()
			MenuSession.lobby = GameFlow.next_lobby(MenuSession.lobby, c, MenuSession.content())
			MenuSession.go(self, "lobby"))
		bottom.add_child(next)
	col.add_child(bottom)


## Opened on its own (screenshots): an example debrief.
func _example() -> Dictionary:
	var c := MenuSession.ensure_campaign()
	var pilots: Array = []
	for pid: String in c.pilots:
		var p: Dictionary = c.pilots[pid]
		pilots.append({"id": pid, "callsign": p["callsign"], "name": p["name"], "old_ll": 0, "new_ll": 1,
			"mech": "%s (Everest)" % p["mechs"][0]["name"], "mech_destroyed": pilots.size() == 2})
	return {"outcome": "players", "reason": "All enemy forces have been defeated.", "title": "Mission complete",
		"sitrep": "Basic Combat", "operation": "OPERATION THETA LASH", "rounds": 7, "pilots": pilots, "campaign": c.name}
