class_name DowntimePanel
extends PanelContainer
## Downtime between missions (Core p.50-55), explained plainly: pick one of the book's
## downtime actions, say what you're doing, pick a trigger that fits, and roll. Results that
## say "choose" wait here for the pilot's player. Actions that aren't possible right now
## show why.

signal story_events(events: Array)

var engine: StoryEngine
var story: StoryState
var campaign: Campaign
var seat := "p1"

var _list: VBoxContainer
var _detail: VBoxContainer
var _result: VBoxContainer
var _selected := ""
var _subject: LineEdit
var _preset: OptionButton
var _trigger: OptionButton
var _extra: Dictionary = {}  # name -> Control
var _header: Label


func _init() -> void:
	add_theme_stylebox_override("panel", StoryStyle.panel())
	custom_minimum_size = Vector2(1060, 0)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	add_child(root)
	var top := HBoxContainer.new()
	root.add_child(top)
	_header = StoryStyle.label("DOWNTIME", 22, StoryStyle.GOLD)
	_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_header)
	var close := StoryStyle.button("Close (Esc)", 14)
	close.pressed.connect(func() -> void: visible = false)
	top.add_child(close)
	var intro := StoryStyle.label("Between missions each pilot usually gets one downtime action (Core p.53). What you gain becomes RESERVES for the next mission only. You've had a full repair: HP restored, mechs fixed and reprinted.", 14, StoryStyle.DIM, 720)
	root.add_child(intro)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	root.add_child(cols)
	_list = VBoxContainer.new()
	_list.custom_minimum_size.x = 230
	_list.add_theme_constant_override("separation", 4)
	cols.add_child(_list)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(780, 600)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cols.add_child(scroll)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	scroll.add_child(right)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 6)
	right.add_child(_detail)
	_result = VBoxContainer.new()
	_result.add_theme_constant_override("separation", 6)
	right.add_child(_result)
	visible = false


func bind(e: StoryEngine, s: StoryState, c: Campaign, local_seat: String) -> void:
	engine = e
	story = s
	campaign = c
	seat = local_seat
	refresh()


func pilot_id() -> String:
	return story.pilot_of_seat(seat)


func open(action_id: String = "", npc: String = "", subject: String = "") -> void:
	visible = true
	refresh()
	if action_id != "":
		select(action_id, npc)
		if subject != "" and _subject != null:
			_subject.text = subject


func refresh() -> void:
	if story == null:
		return
	var pid := pilot_id()
	var p: Dictionary = campaign.pilots.get(pid, {})
	var left := int(story.downtime.get("actions_left", {}).get(pid, 0))
	_header.text = "DOWNTIME  ·  %s  ·  %s" % [p.get("callsign", "?"), "%d action%s left" % [left, "" if left == 1 else "s"] if story.phase == "downtime" else "not in downtime"]
	for ch in _list.get_children():
		ch.queue_free()
	for aid: String in Downtime.action_ids():
		var b := StoryStyle.button(str(Downtime.book(aid).get("name", aid)), 15)
		b.tooltip_text = str(Downtime.book(aid).get("terse", ""))
		if aid == _selected:
			b.add_theme_color_override("font_color", StoryStyle.GOLD)
		var id := aid
		b.pressed.connect(func() -> void: select(id))
		_list.add_child(b)
	_show_pending()


func select(action_id: String, npc: String = "") -> void:
	_selected = action_id
	_extra = {}
	_subject = null
	_preset = null
	_trigger = null
	for ch in _detail.get_children():
		ch.queue_free()
	var book := Downtime.book(action_id)
	var cfg := Downtime.action_cfg(action_id)
	_detail.add_child(_l(str(book.get("name", action_id)).to_upper(), 19, StoryStyle.GOLD))
	var d := _l(StoryText.plain(str(book.get("detail", ""))), 14, StoryStyle.TEXT)
	d.custom_minimum_size.x = 740
	_detail.add_child(d)
	var pid := pilot_id()
	var pilot: Dictionary = campaign.pilots.get(pid, {})
	match action_id:
		"dt_get_focused":
			_detail.add_child(_l("Learn a new +2 trigger, or improve one: +2 to +4, +4 to +6. No roll.", 14, StoryStyle.DIM))
			var ob := OptionButton.new()
			for t: Dictionary in NarrativeCheck.triggers_of(pilot):
				if int(t["rank"]) < 3:
					ob.add_item("Improve %s (+%d -> +%d)" % [t["name"], t["bonus"], int(t["bonus"]) + 2])
					ob.set_item_metadata(ob.item_count - 1, t["id"])
			for s: String in _all_skills():
				if not pilot.get("skills", {}).has(s):
					ob.add_item("Learn %s (+2)" % NarrativeCheck.trigger_name(s))
					ob.set_item_metadata(ob.item_count - 1, s)
			_extra["trigger"] = ob
			_detail.add_child(ob)
			_subject = _line("Or name your own (e.g. Playing Chess, Dancing):")
		"dt_get_organized":
			_subject = _line(str(cfg.get("subject_prompt", "")))
			_extra["focus"] = _options("Focus", cfg.get("focuses", []))
			_extra["start_stat"] = _options("Starts with +2 in", ["efficiency", "influence"])
		"dt_power_at_a_cost":
			_subject = _line(str(cfg.get("subject_prompt", "")))
			_extra["scale"] = _options("How outlandish is it?", ["modest", "outlandish"])
			_detail.add_child(_l("You'll get it. The GM chooses the cost (one, or two if it's outlandish).", 14, StoryStyle.DIM))
		"dt_get_connected":
			var contacts: Array = story.contacts.filter(func(n: String) -> bool: return not bool(story.npcs.get(n, {}).get("dead", false)))
			var names: Array = contacts.map(func(n: String) -> String: return "%s (%s, %s)" % [story.npcs[n]["name"], story.npcs[n]["title"], story.npcs[n]["faction"]])
			if contacts.is_empty():
				_detail.add_child(_l("You have no contacts yet. Talk to people around the hub first.", 14, StoryStyle.RED))
			_extra["npc"] = _options("Contact", names, contacts)
			if npc != "" and contacts.has(npc):
				(_extra["npc"] as OptionButton).select(contacts.find(npc))
		_:
			_subject = _line(str(cfg.get("subject_prompt", "")))
	if action_id == "dt_get_creative":
		var cb := CheckBox.new()
		cb.text = "It's especially complex"
		_extra["complex"] = cb
		_detail.add_child(cb)
		var open_projects: Array = []
		for key: String in story.downtime.get("projects", {}):
			var pr: Dictionary = story.downtime["projects"][key]
			if pr["state"] == "in_progress" and pr["pilot"] == pid:
				open_projects.append(key)
		if not open_projects.is_empty():
			_extra["finish"] = _options("Or finish a project (no roll)", [""] + open_projects.map(func(k: String) -> String: return story.downtime["projects"][k]["name"]), [""] + open_projects)
	var presets: Array = cfg.get("subject_presets", [])
	if not presets.is_empty() and _subject != null:
		_preset = OptionButton.new()
		_preset.add_item("(write your own)")
		for pr: Variant in presets:
			_preset.add_item(str(pr["label"]) if pr is Dictionary else str(pr))
		_preset.item_selected.connect(func(i: int) -> void:
			if i > 0:
				_subject.text = _preset.get_item_text(i))
		_detail.add_child(_preset)
	if not cfg.get("no_roll", false):
		_trigger = OptionButton.new()
		_trigger.add_item("No trigger (plain d20)")
		_trigger.set_item_metadata(0, "")
		var fits: Array = cfg.get("triggers", [])
		for t: Dictionary in NarrativeCheck.triggers_of(pilot):
			if fits.has(t["id"]):
				_trigger.add_item("%s +%d" % [t["name"], t["bonus"]])
				_trigger.set_item_metadata(_trigger.item_count - 1, t["id"])
		if _trigger.item_count > 1:
			_trigger.select(1)
		_detail.add_child(_l("Trigger that fits (one counts):", 14, StoryStyle.DIM))
		_detail.add_child(_trigger)
	else:
		_trigger = null
	var go := StoryStyle.button("Do it" if cfg.get("no_roll", false) else "Roll", 17)
	var why := engine.validate(story, campaign, {"type": "downtime_action", "seat": seat, "params": _params()})
	go.pressed.connect(_go)
	_detail.add_child(go)
	if not why.is_empty() and str(why["reason"]).find("Say") < 0 and str(why["reason"]).find("Name") < 0 and str(why["reason"]).find("?") < 0:
		_detail.add_child(_l("✕ " + str(why["reason"]), 14, StoryStyle.RED))
	refresh()


func _line(prompt: String) -> LineEdit:
	_detail.add_child(_l(prompt, 14, StoryStyle.DIM))
	var le := LineEdit.new()
	le.custom_minimum_size.x = 420
	_detail.add_child(le)
	return le


func _options(label: String, items: Array, values: Array = []) -> OptionButton:
	_detail.add_child(_l(label, 14, StoryStyle.DIM))
	var ob := OptionButton.new()
	for i in range(items.size()):
		ob.add_item(str(items[i]) if str(items[i]) != "" else "-")
		ob.set_item_metadata(i, values[i] if i < values.size() else items[i])
	_detail.add_child(ob)
	return ob


func _params() -> Dictionary:
	var p := {"pilot": pilot_id(), "action": _selected}
	if _subject != null and is_instance_valid(_subject):
		p["subject"] = _subject.text
	if _trigger != null and is_instance_valid(_trigger) and _trigger.selected >= 0:
		p["use_trigger"] = str(_trigger.get_item_metadata(_trigger.selected))
	for k: String in _extra:
		var c: Control = _extra[k]
		if c is OptionButton and (c as OptionButton).selected >= 0:
			p[k] = (c as OptionButton).get_item_metadata((c as OptionButton).selected)
		elif c is CheckBox:
			p[k] = (c as CheckBox).button_pressed
	if _selected == "dt_get_focused" and str(p.get("subject", "")).strip_edges() != "":
		p["trigger"] = "custom:" + str(p["subject"]).strip_edges()
	if _selected == "dt_get_connected":
		p["subject"] = str(p.get("npc", ""))
	return p


func _go() -> void:
	var r := engine.submit(story, campaign, {"type": "downtime_action", "seat": seat, "params": _params()})
	if not r["ok"]:
		_set_result([_l("✕ " + str(r["reason"]) + "  (" + str(r["rule_ref"]) + ")", 15, StoryStyle.RED)])
		return
	show_events(r["events"])
	story_events.emit(r["events"])
	refresh()


## Shows a downtime result (and any choice it asks for), e.g. one started from a conversation.
func show_events(events: Array) -> void:
	var out: Array = []
	for e: Dictionary in events:
		match str(e.get("type", "")):
			"downtime_result":
				var head := "%s: %s" % [e.get("name", ""), e.get("subject", "")]
				if e.has("check"):
					head += "   rolled %d" % int(e["check"]["total"])
				out.append(_l(head, 17, StoryStyle.GOLD))
				if e.has("memory_note"):
					out.append(_l(str(e["memory_note"]), 14, StoryStyle.DIM))
				out.append(_l(str(e.get("summary", "")), 15))
				if str(e.get("book_text", "")) != "":
					var bt := _l(str(e["book_text"]), 13, StoryStyle.DIM)
					bt.custom_minimum_size.x = 740
					out.append(bt)
			"reserve_gained":
				out.append(_l("+ Reserve: %s%s" % [e["reserve"]["name"], " (%s)" % e["reserve"]["note"] if str(e["reserve"]["note"]) != "" else ""], 15, StoryStyle.GREEN))
			"standing_changed":
				out.append(_l("%s: %s" % [e["faction"], e["label"]], 14, StoryStyle.BLUE if int(e["to"]) > int(e["from"]) else StoryStyle.RED))
			"obligation_added":
				out.append(_l("You owe: %s" % e["obligation"]["what"], 14, StoryStyle.RED))
			"hook_added":
				out.append(_l("New job: %s" % e["hook"]["title"], 14, StoryStyle.BLUE))
			"org_roll", "org_changed":
				out.append(_l("Organization %s" % (e.get("summary", "") if e.has("summary") else "%s: Efficiency +%d, Influence +%d" % [e["org"]["name"], e["org"]["efficiency"], e["org"]["influence"]]), 14))
	_set_result(out)


func _set_result(nodes: Array) -> void:
	for ch in _result.get_children():
		ch.queue_free()
	for n: Control in nodes:
		_result.add_child(n)
	_show_pending()


## A result that says "choose": one button per option (pick `count`).
func _show_pending() -> void:
	for old in _result.get_children():
		if str(old.name).begins_with("Pending"):
			_result.remove_child(old)
			old.queue_free()
	var pc := story.pending_choice
	if pc.is_empty():
		return
	var box := VBoxContainer.new()
	box.name = "Pending"
	var mine := story.pilot_of_seat(seat) == str(pc.get("pilot", "")) or seat == "gm"
	box.add_child(_l("%s  (choose %d)" % [pc.get("prompt", "Choose"), int(pc.get("count", 1))], 16, StoryStyle.GOLD))
	var picked: Array = []
	for o: Dictionary in pc.get("options", []):
		var b := StoryStyle.button(str(o["label"]), 15, true)
		b.toggle_mode = int(pc.get("count", 1)) > 1
		b.tooltip_text = str(o.get("detail", ""))
		b.disabled = not mine
		var id := str(o["id"])
		if b.toggle_mode:
			b.toggled.connect(func(on: bool) -> void:
				if on: picked.append(id)
				else: picked.erase(id)
				if picked.size() == int(pc.get("count", 1)): _choose(picked.duplicate()))
		else:
			b.pressed.connect(func() -> void: _choose([id]))
		box.add_child(b)
	_result.add_child(box)


func _choose(picks: Array) -> void:
	var r := engine.submit(story, campaign, {"type": "downtime_choose", "seat": seat, "params": {"picks": picks}})
	if not r["ok"]:
		_set_result([_l("✕ " + str(r["reason"]), 15, StoryStyle.RED)])
		return
	show_events(r["events"])
	story_events.emit(r["events"])
	refresh()


static func _all_skills() -> Array:
	var out: Array = []
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(NarrativeCheck.SKILLS_FILE))
	for s: Dictionary in (data if data is Array else []):
		out.append(str(s["id"]))
	return out


static func _l(text: String, size: int = 16, color: Color = StoryStyle.TEXT) -> Label:
	return StoryStyle.label(text, size, color, 740)


func _process(_delta: float) -> void:
	if visible:
		reset_size()
		var vp := get_viewport_rect().size
		position = ((vp - size) / 2.0).max(Vector2(8, 8))
