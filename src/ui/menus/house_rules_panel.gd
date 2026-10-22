class_name HouseRulesPanel
extends RefCounted
## The settings' House Rules panel (HouseRules): a switch per rule, grouped by where it comes
## from, each with its description and a "not a book rule" label. A flip saves right away and
## goes into the open game when this player decides (HouseRulesFlow): the GM, or the host
## when the AI is the GM. Everyone else sees the game's set, read-only.

const SOURCE_COLORS := {"Your idea": Color(0.95, 0.75, 0.35), "Community": Color(0.55, 0.8, 0.6), "Lancer Tactics": Color(0.6, 0.7, 1.0)}


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
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 520)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	for source: String in HouseRules.sources():
		var rules := HouseRules.all().filter(func(r: Dictionary) -> bool: return str(r.get("source", "")) == source)
		list.add_child(MenuTheme.label(source.to_upper(), 14, SOURCE_COLORS.get(source, MenuTheme.MUTED)))
		if rules.is_empty():
			list.add_child(MenuTheme.label("None yet.", 14, MenuTheme.MUTED))
		for r: Dictionary in rules:
			list.add_child(_row(r, s, shown, mine, campaign, client, status))
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
