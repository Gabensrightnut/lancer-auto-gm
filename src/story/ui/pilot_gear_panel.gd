class_name PilotGearPanel
extends PanelContainer
## The quartermaster's racks: pick what your pilot carries on the next mission. By the book a
## pilot takes one set of armor, up to two weapons and up to three other pieces of gear
## (Core p.108). Pilot gear isn't licensed. This is also where a pilot's own supplies live:
## Extra Rations, a Wilderness Survival Kit, Patches, a Sleeping Bag... Anything bigger comes
## as a reserve (Supplies, Extra repairs) through downtime.

signal story_events(events: Array)

const LIMITS := {"Armor": 1, "Weapon": 2, "Gear": 3}

var engine: StoryEngine
var story: StoryState
var campaign: Campaign
var seat := "p1"
var _boxes: Dictionary = {}  # gear id -> CheckBox
var _count: Label
var _msg: Label


func _init() -> void:
	add_theme_stylebox_override("panel", StoryStyle.panel())
	visible = false


func bind(e: StoryEngine, s: StoryState, c: Campaign, local_seat: String) -> void:
	engine = e
	story = s
	campaign = c
	seat = local_seat


func open() -> void:
	for ch in get_children():
		ch.queue_free()
	_boxes = {}
	var pid := story.pilot_of_seat(seat)
	var pilot: Dictionary = campaign.pilots.get(pid, {})
	var have: Array = pilot.get("pilot_gear", [])
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	var title := StoryStyle.label("PILOT GEAR  ·  %s" % pilot.get("callsign", ""), 22, StoryStyle.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var close := StoryStyle.button("Close (Esc)", 14)
	close.pressed.connect(func() -> void: visible = false)
	top.add_child(close)
	root.add_child(StoryStyle.label("Pilot gear isn't licensed: take what you need. Per mission: one set of armor, up to two weapons, up to three other pieces (Core p.108). Rations, survival kits and patches are how pilots carry their own supplies; hover an item for what it does.", 14, StoryStyle.DIM, 900))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	root.add_child(cols)
	var by_type := {"Armor": [], "Weapon": [], "Gear": []}
	for g: Dictionary in (engine.db.all("pilot_gear") if engine.db != null else []):
		var t := str(g.get("type", "Gear"))
		if by_type.has(t):
			(by_type[t] as Array).append(g)
	for t: String in ["Armor", "Weapon", "Gear"]:
		var col := VBoxContainer.new()
		col.custom_minimum_size.x = 290
		cols.add_child(col)
		col.add_child(StoryStyle.label({"Armor": "ARMOR (1)", "Weapon": "WEAPONS (2)", "Gear": "GEAR (3)"}[t], 16, StoryStyle.BLUE))
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(290, 430)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		col.add_child(scroll)
		var list := VBoxContainer.new()
		scroll.add_child(list)
		for g: Dictionary in by_type[t]:
			var cb := CheckBox.new()
			cb.text = str(g["name"])
			cb.button_pressed = have.has(g["id"])
			cb.tooltip_text = _describe(g)
			cb.add_theme_font_size_override("font_size", StorySettings.size(14))
			cb.toggled.connect(func(_on: bool) -> void: _update())
			list.add_child(cb)
			_boxes[str(g["id"])] = cb
	_count = StoryStyle.label("", 15)
	root.add_child(_count)
	_msg = StoryStyle.label("", 14, StoryStyle.RED, 900)
	root.add_child(_msg)
	var save := StoryStyle.button("Take this kit", 16)
	save.pressed.connect(_save)
	root.add_child(save)
	visible = true
	_update()


static func _describe(g: Dictionary) -> String:
	var parts := PackedStringArray()
	if str(g.get("effect", "")) != "":
		parts.append(StoryText.plain(str(g["effect"])))
	if str(g.get("description", "")) != "":
		parts.append(StoryText.plain(str(g["description"])).substr(0, 400))
	for b: Dictionary in g.get("bonuses", []):
		match str(b.get("id", "")):
			"pilot_hp":
				parts.append("+%d HP" % int(b["val"]))
			"pilot_armor":
				parts.append("Armor %d" % int(b["val"]))
	return "\n".join(parts)


func _picked() -> Array:
	var out: Array = []
	for gid: String in _boxes:
		if (_boxes[gid] as CheckBox).button_pressed:
			out.append(gid)
	return out


func _update() -> void:
	var counts := {"Armor": 0, "Weapon": 0, "Gear": 0}
	for gid: String in _picked():
		var t := str(engine.db.get_entry("pilot_gear", gid).get("type", "Gear"))
		counts[t] = int(counts.get(t, 0)) + 1
	_count.text = "Armor %d/1   ·   Weapons %d/2   ·   Gear %d/3" % [counts["Armor"], counts["Weapon"], counts["Gear"]]
	_msg.text = engine.gear_problem(_picked())


func _save() -> void:
	var r := engine.submit(story, campaign, {"type": "set_pilot_gear", "seat": seat, "params": {"pilot": story.pilot_of_seat(seat), "gear": _picked()}})
	if not r["ok"]:
		_msg.text = str(r["reason"])
		return
	visible = false
	story_events.emit(r["events"])


func _process(_delta: float) -> void:
	if visible:
		reset_size()
		var vp := get_viewport_rect().size
		position = ((vp - size) / 2.0).max(Vector2(8, 8))
