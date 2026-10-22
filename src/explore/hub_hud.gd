class_name HubHud
extends Control
## The hub's on-screen info: where you are and what phase of the campaign it is (explained
## plainly), the squad (HP, Down and Out, reserves), standing with the factions you've met,
## the "Talk to" prompt, short toasts for story events, and the job board.

signal story_events(events: Array)
signal codex_requested
signal map_requested
signal market_requested

const PHASE_HELP := {
	"briefing": "BRIEFING. Pick a job from the board (J). The briefing sets the goal and the stakes.",
	"reserves": "RESERVES. Check what each pilot is bringing on this mission, then deploy.",
	"mission": "MISSION. Boots on the ground.",
	"debrief": "DEBRIEF. Talk over the mission. Next, everyone levels up, win or lose.",
	"level_up": "LEVEL UP. Each pilot picks +2 to a trigger and +1 to a mech skill (talents and licenses in the builder).",
	"downtime": "DOWNTIME. Walk around, talk to people, and take one downtime action each (Tab). Then start the next briefing.",
}

const NEXT_STEP := {"downtime": "End downtime: go to the briefing", "briefing": "Job board (J)",
	"reserves": "Deploy: boots on the ground", "debrief": "Level up"}

var engine: StoryEngine
var story: StoryState
var campaign: Campaign
var seat := "p1"

var _info: RichTextLabel
var _phase: Label
var _prompt: Label
var _toasts: VBoxContainer
var _board: PanelContainer
var _board_list: VBoxContainer
var _next: Button


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var info_panel := PanelContainer.new()
	info_panel.name = "Info"
	info_panel.add_theme_stylebox_override("panel", StoryStyle.panel())
	info_panel.position = Vector2(16, 16)
	add_child(info_panel)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.scroll_active = false
	_info.custom_minimum_size = Vector2(330, 0)
	_info.add_theme_font_size_override("normal_font_size", StorySettings.size(14))
	_info.add_theme_font_size_override("bold_font_size", StorySettings.size(18))
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_panel.add_child(_info)
	_phase = StoryStyle.label("", 15, StoryStyle.GOLD, 700)
	_phase.add_theme_stylebox_override("normal", StoryStyle.panel(StoryStyle.GOLD, Color(0.05, 0.05, 0.04, 0.85), 1, 4, 8))
	_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_phase)
	_next = StoryStyle.button("", 15)
	_next.pressed.connect(_next_step)
	add_child(_next)
	var codex_btn := StoryStyle.button("Codex (K)", 14)
	codex_btn.name = "CodexButton"
	codex_btn.pressed.connect(func() -> void: codex_requested.emit())
	add_child(codex_btn)
	var map_btn := StoryStyle.button("Map (M)", 14)
	map_btn.name = "MapButton"
	map_btn.tooltip_text = "The sector: other worlds, who likes you where, and travel."
	map_btn.pressed.connect(func() -> void: map_requested.emit())
	add_child(map_btn)
	var market_btn := StoryStyle.button("Market (B)", 14)
	market_btn.name = "MarketButton"
	market_btn.tooltip_text = "Buying, selling, food and printers (house rules)."
	market_btn.pressed.connect(func() -> void: market_requested.emit())
	add_child(market_btn)
	_prompt = StoryStyle.label("", 20, Color.WHITE)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	add_child(_prompt)
	_toasts = VBoxContainer.new()
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.add_theme_constant_override("separation", 4)
	add_child(_toasts)
	_board = PanelContainer.new()
	_board.add_theme_stylebox_override("panel", StoryStyle.panel())
	_board.visible = false
	add_child(_board)
	var bb := VBoxContainer.new()
	bb.add_theme_constant_override("separation", 8)
	_board.add_child(bb)
	bb.add_child(StoryStyle.label("JOB BOARD", 22, StoryStyle.GOLD))
	bb.add_child(StoryStyle.label("Jobs pay in favors, reserves and goodwill (and some manna, which the rules don't count). Every mission you finish, win or lose, raises your License Level.", 14, StoryStyle.DIM, 560))
	_board_list = VBoxContainer.new()
	_board_list.add_theme_constant_override("separation", 8)
	bb.add_child(_board_list)


func bind(e: StoryEngine, s: StoryState, c: Campaign, local_seat: String) -> void:
	engine = e
	story = s
	campaign = c
	seat = local_seat


func refresh() -> void:
	if story == null:
		return
	var vp := get_viewport_rect().size
	var hub := story.hub
	var t := "[b]%s[/b]\n[color=#9fb2c8]%s  ·  %s  ·  %s[/color]\n" % [hub.get("name", "?"), "%s, %s" % [str(hub.get("kind", "")).capitalize(), hub.get("culture_name", "")] if hub.has("culture_name") else str(hub.get("kind", "")).capitalize(), hub.get("planet", ""), hub.get("faction", "")]
	t += "[color=#9fd0ff]Day %d  ·  %s[/color]  [color=#9fb2c8](T: wait)[/color]\n" % [int(TownLife.clock(story)["day"]), TownLife.period_name(story)]
	var conflict: Dictionary = hub.get("conflict", {})
	if not conflict.is_empty():
		t += "[color=#d0b98a][i]%s[/i][/color]\n" % conflict.get("summary", "")
	if not story.arc.is_empty():
		var n := (StoryArc.arc_def(str(story.arc["id"])).get("stages", []) as Array).size()
		t += "[color=#ffd166]Situation: %s (%d of %d)[/color]\n" % [story.arc["name"], int(story.arc["stage"]) + 1, n]
	# House rules that are on (the user's own ideas, not book rules): one line, near the top.
	var hr := PackedStringArray()
	if StoryHouseRules.on(campaign, Economy.R_WALLET) and not Economy.wallet(story).is_empty():
		hr.append(Economy.describe(story))
	if StoryHouseRules.on(campaign, Economy.R_FOOD):
		hr.append("food %d days" % Economy.rations(story))
	if StoryHouseRules.on(campaign, Economy.R_PRINTERS):
		hr.append("printer here" if Economy.has_printer(story) else "no printer here")
		for wp: String in Economy.wrecked(story, campaign):
			hr.append("[color=#ff7b6b]%s's mech wrecked[/color]" % campaign.pilots.get(wp, {}).get("callsign", ""))
	if not hr.is_empty():
		t += "[color=#e8c37a]House rules:[/color] %s" % "  ·  ".join(hr) + "\n"
	t += "\n"
	t += "[color=#ffd166]SQUAD[/color]\n"
	var seats := story.seats.keys()
	seats.sort()
	for s: String in seats:
		var pid := story.pilot_of_seat(s)
		var p: Dictionary = campaign.pilots.get(pid, {})
		if p.is_empty():
			continue
		var state := ""
		if story.dead.has(pid):
			state = " [color=#ff6b5b]KIA[/color]"
		elif story.down_and_out.has(pid):
			state = " [color=#ff6b5b]DOWN AND OUT[/color]"
		var res: Array = story.reserves.get(pid, [])
		t += "%s [b]%s[/b]  LL%d  HP %d/%d%s%s\n" % ["▶" if s == seat else " ", p.get("callsign", ""), int(p.get("ll", 0)),
			StoryEffects.current_hp(story, campaign, pid), StoryEffects.max_hp(p), state, "  [color=#9fb2c8](AI)[/color]" if story.is_ai(s) else ""]
		if story.phase == "downtime":
			t += "   [color=#9fb2c8]downtime actions left: %d[/color]\n" % int(story.downtime.get("actions_left", {}).get(pid, 0))
		t += _kit_line(p, res)
		for r: Dictionary in res:
			t += "   [color=#7fe0a0]+ %s[/color]\n" % r["name"]
	# Standing (this game's own bookkeeping, Codex: Standing): this world's factions first, then
	# anyone else the squad has dealt with.
	var met := {}
	for n: String in story.contacts:
		met[str(story.npcs.get(n, {}).get("faction", ""))] = true
	met.erase("")
	var local: Array = Sector.factions_of(story, Sector.current(story)) if not Sector.current(story).is_empty() else []
	if not met.is_empty() or not local.is_empty():
		t += "\n[color=#ffd166]STANDING[/color] [color=#9fb2c8](this game's own, not a book rule)[/color]\n"
		var rest := met.keys().filter(func(f: String) -> bool: return not local.has(f))
		rest.sort()
		var fs: Array = local + rest
		for f: String in fs:
			var v := story.get_standing(f)
			var col := "#7fb8ff" if v > 0 else ("#ff7b6b" if v < 0 else "#c8d0da")
			t += "%s  [color=%s]%s[/color]\n" % [f, col, StoryText.standing_label(v)]
	var owed: Array = (story.downtime.get("obligations", []) as Array).filter(func(o: Dictionary) -> bool: return not bool(o.get("done", false)))
	for o: Dictionary in owed:
		t += "[color=#ff9b7b]Owed: %s[/color]\n" % o["what"]
	for npc_id: String in story.deals:
		var dl: Dictionary = story.deals[npc_id]
		if str(dl.get("state", "")) == "accepted":
			t += "[color=#9fd0ff]Deal: a job for %s -> %s[/color]\n" % [story.npcs.get(npc_id, {}).get("name", "?"), StoryEffects.reserve_name(str(dl["reward"]))]
	_info.text = t
	_phase.text = PHASE_HELP.get(story.phase, story.phase)
	_phase.custom_minimum_size.x = minf(760, vp.x - 760)
	_phase.size = Vector2.ZERO
	_phase.reset_size()
	_phase.position = Vector2((vp.x - _phase.size.x) / 2.0, 16)
	_next.visible = NEXT_STEP.has(story.phase)
	_next.text = NEXT_STEP.get(story.phase, "")
	_next.reset_size()
	_next.position = Vector2(vp.x - _next.size.x - 16, 16)
	var cb := get_node("CodexButton") as Button
	cb.reset_size()
	cb.position = Vector2(16, vp.y - cb.size.y - 16)
	var mb := get_node("MapButton") as Button
	mb.reset_size()
	mb.position = Vector2(cb.position.x + cb.size.x + 8, cb.position.y)
	var kb := get_node("MarketButton") as Button
	kb.visible = MarketPanel.available(campaign)
	kb.reset_size()
	kb.position = Vector2(mb.position.x + mb.size.x + 8, cb.position.y)
	_prompt.size = Vector2(vp.x, 30)
	_prompt.position = Vector2(0, vp.y * 0.62)
	_toasts.size = Vector2(440, 300)
	_toasts.position = Vector2(vp.x - 456, 70)
	if _board.visible:
		_fill_board()


## The squad panel steps aside while a conversation or a menu needs the space.
func set_busy(busy: bool) -> void:
	(get_node("Info") as Control).visible = not busy
	_phase.visible = not busy
	_next.visible = not busy and story != null and NEXT_STEP.has(story.phase)


## Mech repairs (Repair Cap, +1 per 2 Hull, +2 with an Extra repairs reserve) and the pilot's
## own kit: how supplies show up by the book (Core p.30, p.51, p.108).
func _kit_line(p: Dictionary, res: Array) -> String:
	if engine == null or engine.db == null:
		return ""
	var mech: Dictionary = {}
	for m: Dictionary in p.get("mechs", []):
		if m["id"] == p.get("active_mech", "") or mech.is_empty():
			mech = m
	var frame := engine.db.frame(str(mech.get("frame", "")))
	var line := ""
	if not frame.is_empty():
		var rep := int(frame.get("stats", {}).get("repcap", 0)) + int(p.get("hull", 0)) / 2
		var extra := 2 if res.any(func(r: Dictionary) -> bool: return str(r["id"]) == "reserve_extra_repairs") else 0
		line += "   [color=#9fb2c8]%s · Repairs %d%s[/color]\n" % [frame.get("name", ""), rep + extra, " (+2 reserve)" if extra > 0 else ""]
	var kit: Array = (p.get("pilot_gear", []) as Array).map(func(g: Variant) -> String: return str(engine.db.get_entry("pilot_gear", str(g)).get("name", g)))
	if not kit.is_empty():
		line += "   [color=#9fb2c8]Kit: %s[/color]\n" % ", ".join(PackedStringArray(kit))
	return line


func set_prompt(text: String) -> void:
	_prompt.text = text


func toast(text: String, color: Color = StoryStyle.TEXT) -> void:
	var l := StoryStyle.label(text, 15, color, 440)
	l.add_theme_stylebox_override("normal", StoryStyle.panel(Color(color, 0.6), Color(0.03, 0.04, 0.06, 0.9), 1, 3, 8))
	l.custom_minimum_size.x = 440
	_toasts.add_child(l)
	while _toasts.get_child_count() > 6:
		_toasts.get_child(0).free()
	var tw := create_tween()
	tw.tween_interval(5.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


func board_open() -> bool:
	return _board.visible


func toggle_board() -> void:
	_board.visible = not _board.visible
	if _board.visible:
		_fill_board()


func close_board() -> void:
	_board.visible = false


func _fill_board() -> void:
	for ch in _board_list.get_children():
		ch.queue_free()
	if story.hooks.is_empty():
		_board_list.add_child(StoryStyle.label("No jobs right now.", 15, StoryStyle.DIM))
	for h: Dictionary in story.hooks:
		var box := VBoxContainer.new()
		box.add_child(StoryStyle.label("%s   [%s]" % [h.get("title", ""), _sitrep_name(str(h.get("sitrep", "")))], 17, StoryStyle.GOLD))
		var body := StoryStyle.label("%s\n%s\nFor: %s (%s)" % [h.get("objective", ""), h.get("stakes", ""), h.get("patron", ""), h.get("faction", "")], 14, StoryStyle.TEXT, 560)
		body.custom_minimum_size.x = 560
		box.add_child(body)
		var b := StoryStyle.button("Take this job", 15)
		b.disabled = story.phase != "briefing"
		b.tooltip_text = "" if story.phase == "briefing" else "Jobs are chosen at the briefing, after downtime."
		var id := str(h["id"])
		b.pressed.connect(func() -> void: _take(id))
		box.add_child(b)
		_board_list.add_child(box)
	_board.reset_size()
	var vp := get_viewport_rect().size
	_board.position = Vector2((vp.x - _board.size.x) / 2.0, 70)


func _take(id: String) -> void:
	var r := engine.submit(story, campaign, {"type": "choose_hook", "seat": "gm", "params": {"hook": id}})
	if not r["ok"]:
		toast(str(r["reason"]), StoryStyle.RED)
		return
	_board.visible = false
	story_events.emit(r["events"])


func _next_step() -> void:
	var type: String = {"downtime": "end_downtime", "reserves": "confirm_reserves", "debrief": "level_up"}.get(story.phase, "")
	if type == "":
		toggle_board()
		return
	var r := engine.submit(story, campaign, {"type": type, "seat": "gm", "params": {}})
	if not r["ok"]:
		toast(str(r["reason"]), StoryStyle.RED)
		return
	story_events.emit(r["events"])


static func _sitrep_name(id: String) -> String:
	return id.trim_prefix("sitrep_").replace("standardcombat", "basic combat").capitalize()
