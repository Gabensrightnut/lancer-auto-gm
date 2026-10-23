class_name HouseRulesPanel
extends RefCounted
## The settings' House Rules panel (HouseRules): a switch per rule, grouped by where it comes
## from, each with its description and a "not a book rule" label. A flip saves right away and
## goes into the open game when this player decides (HouseRulesFlow): the GM, or the host
## when the AI is the GM. Everyone else sees the game's set, read-only.

const SOURCE_COLORS := {HouseRules.JOE: Color(0.95, 0.75, 0.35), "Community": Color(0.55, 0.8, 0.6), "Lancer Tactics": Color(0.6, 0.7, 1.0)}


## `campaign`: the open campaign (or null); `client`: a friend's lobby connection (or null).
static func build(s: GameSettings, campaign: Campaign, client: NetClient = null) -> Control:
	var p := MenuTheme.panel("House rules", MenuTheme.maker_color("HA"), "compendium")
	var b := MenuTheme.body(p)
	p.custom_minimum_size = Vector2(380, 0)
	var mine := HouseRulesFlow.i_decide(campaign, client)
	var shown: Dictionary = HouseRulesFlow.my_set() if mine else HouseRulesFlow.current(campaign)
	b.add_child(_wrap("Optional rules that are not in the LANCER core book. Flip them any time, even mid-battle: they apply at once. A human GM's choices are used; with the AI as GM, the host's. Everyone is told when one changes."))
	var status := _wrap("" if mine else "The GM (or, with the AI as GM, the host) decides the house rules in this game. These are the ones in use.", MenuTheme.WARN)
	b.add_child(status)
	# Presets: every one of Joe's Rules on at once, or back to the core book only.
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 8)
	b.add_child(presets)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 520)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.add_child(tabs)
	var switches := {}
	for tab: Dictionary in HouseRules.tabs():
		var scroll := ScrollContainer.new()
		scroll.name = str(tab["name"])
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		tabs.add_child(scroll)
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list.add_theme_constant_override("separation", 10)
		scroll.add_child(list)
		list.add_child(MenuTheme.label(str(tab["name"]).to_upper(), 14, SOURCE_COLORS.get(str(tab["source"]), MenuTheme.MUTED)))
		if (tab["rules"] as Array).is_empty():
			list.add_child(MenuTheme.label("None yet.", 14, MenuTheme.MUTED))
		for r: Dictionary in tab["rules"]:
			var row := _row(r, s, shown, mine, campaign, client, status)
			list.add_child(row)
			switches[str(r["id"])] = row.find_children("*", "CheckButton", true, false)[0]
	for kind: Array in [["joe", "Turn on all of Joe's Rules"], ["book", "Book only"]]:
		var btn := Button.new()
		btn.text = str(kind[1])
		btn.disabled = not mine
		btn.pressed.connect(func() -> void:
			var set := HouseRules.preset(str(kind[0]), s.house_rules)
			for id: String in set:
				s.house_rules[id] = set[id]
				if switches.has(id):
					(switches[id] as CheckButton).set_pressed_no_signal(bool(set[id]))
			s.save()
			var why := HouseRulesFlow.push(campaign, MenuSession.store, client)
			status.text = why if why != "" else ("All of Joe's Rules are on." if kind[0] == "joe" else "Book only: every house rule is off."))
		presets.add_child(btn)
	return p


static func _wrap(text: String, color: Color = MenuTheme.MUTED) -> Label:
	var l := MenuTheme.label(text, 15, color, true)
	l.custom_minimum_size = Vector2(200, 0)
	return l


static func _row(r: Dictionary, s: GameSettings, shown: Dictionary, mine: bool, campaign: Campaign, client: NetClient, status: Label) -> Control:
	var id := str(r["id"])
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	var sw := CheckButton.new()
	sw.text = str(r["name"])
	sw.clip_text = true
	sw.custom_minimum_size = Vector2(200, 0)
	sw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sw.button_pressed = bool(shown.get(id, false))
	sw.disabled = not mine
	sw.tooltip_text = str(r["description"])
	sw.toggled.connect(func(on: bool) -> void:
		s.house_rules[id] = on
		s.save()
		var why := HouseRulesFlow.push(campaign, MenuSession.store, client)
		status.text = why if why != "" else HouseRules.announce(id, on))
	head.add_child(sw)
	v.add_child(head)
	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", 6)
	tags.add_child(MenuTheme.chip("Not a book rule", MenuTheme.MUTED))
	tags.add_child(MenuTheme.chip("Battle" if str(r["system"]) == "rules" else "Between missions", MenuTheme.maker_color("SSC")))
	if str(r.get("source_link", "")) != "":
		var link := LinkButton.new()
		link.text = "Where it's from"
		link.add_theme_font_size_override("font_size", 13)
		var url := str(r["source_link"])
		link.pressed.connect(func() -> void: OS.shell_open(url))
		tags.add_child(link)
	v.add_child(tags)
	var desc := MenuTheme.label(str(r["description"]), 14, MenuTheme.MUTED, true)
	desc.custom_minimum_size = Vector2(200, 0)
	v.add_child(desc)
	return v
