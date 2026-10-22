class_name GmPanel
extends Control
## The human GM's story panel (GmTools), usable in the hub and over a battle: write and play a
## scene, change or add jobs before the squad sees them (text, briefing, commander, twist),
## faction standing, reserves, and people. Everything is submitted as a StoryEngine action
## from the "gm" seat, so players only see their filtered view and it works online.

signal story_events(events: Array)

var engine: StoryEngine
var story: StoryState
var campaign: Campaign

var _tabs: TabContainer
var _msg: Label
# Scene tab
var _scene_npc: OptionButton
var _scene_pilot: OptionButton
var _scene_lines: TextEdit
var _scene_choices: Array = []  # [{"text": LineEdit, "fx": OptionButton}]
var _saved: VBoxContainer
# Jobs tab
var _job_pick: OptionButton
var _job_fields: Dictionary = {}
var _job_brief: TextEdit
var _job_cmd: OptionButton
var _job_cmd_new: LineEdit
var _twist_text: LineEdit
var _new_job: OptionButton
var _new_job_title: LineEdit
# Standing / reserves tab
var _stand_box: VBoxContainer
var _res_pilot: OptionButton
var _res_pick: OptionButton
var _res_custom: LineEdit
var _res_list: VBoxContainer
# People tab
var _npc_pick: OptionButton
var _npc_fields: Dictionary = {}
var _npc_dead: CheckBox
var _new_role: OptionButton
var _new_name: LineEdit

const QUICK_FX := [["No effect", []], ["+1 standing with their faction", [{"standing": "$npc.faction", "add": 1}]],
	["-1 standing with their faction", [{"standing": "$npc.faction", "add": -1}]],
	["Give a Knowledge reserve", [{"reserve": "reserve_knowledge", "to": "speaker"}]],
	["They become a contact", [{"contact": "$npc"}]], ["Post a job from them", [{"hook": "clear_raiders", "patron": "$npc"}]]]


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel", StoryStyle.panel(StoryStyle.GOLD))
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := StoryStyle.label("GM TOOLS", 18, StoryStyle.GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := StoryStyle.button("Close (G)", 13)
	close.pressed.connect(func() -> void: visible = false)
	head.add_child(close)
	v.add_child(StoryStyle.label("Only you see this. Players see what you reveal, never your notes or hidden twists.", 12, StoryStyle.DIM, 520))
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(560, 560)
	v.add_child(_tabs)
	_msg = StoryStyle.label("", 13, StoryStyle.GREEN, 540)
	v.add_child(_msg)


func bind(e: StoryEngine, s: StoryState, c: Campaign) -> void:
	engine = e
	story = s
	campaign = c


func open() -> void:
	visible = true
	refresh()


func _process(_d: float) -> void:
	if visible:
		var panel := get_node("Panel") as PanelContainer
		panel.reset_size()
		panel.position = Vector2(get_viewport_rect().size.x - panel.size.x - 16, 60)


func refresh() -> void:
	var keep := _tabs.current_tab
	for ch in _tabs.get_children():
		_tabs.remove_child(ch)
		ch.queue_free()
	_scene_tab()
	_jobs_tab()
	_standing_tab()
	_people_tab()
	_tabs.current_tab = clampi(keep, 0, _tabs.get_tab_count() - 1)


func _send(type: String, params: Dictionary) -> bool:
	var r := engine.submit(story, campaign, {"type": type, "seat": "gm", "params": params})
	if not r["ok"]:
		_msg.text = "✕ " + str(r["reason"])
		_msg.add_theme_color_override("font_color", StoryStyle.RED)
		return false
	_msg.text = "✓ Done."
	_msg.add_theme_color_override("font_color", StoryStyle.GREEN)
	story_events.emit(r["events"])
	refresh()
	return true


func _page(name: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	scroll.add_child(v)
	return v


func _row(parent: Container, label: String, field: Control) -> Variant:
	var h := HBoxContainer.new()
	parent.add_child(h)
	var l := StoryStyle.label(label, 13, StoryStyle.DIM)
	l.custom_minimum_size.x = 110
	h.add_child(l)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(field)
	return field


func _line(text: String = "", hint: String = "") -> LineEdit:
	var le := LineEdit.new()
	le.text = text
	le.placeholder_text = hint
	return le


func _people() -> Array:
	var ids: Array = (story.hub.get("npcs", []) as Array).duplicate()
	for c: String in story.contacts:
		if not ids.has(c):
			ids.append(c)
	for r: String in Rivals.ids(story):
		if not ids.has(r) and not bool(story.npcs.get(r, {}).get("dead", false)):
			ids.append(r)
	return ids.filter(func(id: String) -> bool: return story.npcs.has(id))


# --- Scene -------------------------------------------------------------------------------

func _scene_tab() -> void:
	var v := _page("Scene")
	_scene_npc = _row(v, "Talking to", OptionButton.new())
	for id: String in _people():
		_scene_npc.add_item("%s (%s)" % [story.npcs[id]["name"], story.npcs[id].get("title", "")])
		_scene_npc.set_item_metadata(_scene_npc.item_count - 1, id)
	_scene_pilot = _row(v, "Pilot", OptionButton.new())
	for pid: String in campaign.pilots:
		if story.is_alive(pid):
			_scene_pilot.add_item(str(campaign.pilots[pid].get("callsign", pid)))
			_scene_pilot.set_item_metadata(_scene_pilot.item_count - 1, pid)
	v.add_child(StoryStyle.label("Lines, one per row. Start with \"pilot:\" or \"narrator:\" for them; add (angry), (smiling), (worried)... for a face.", 12, StoryStyle.DIM, 540))
	_scene_lines = TextEdit.new()
	_scene_lines.custom_minimum_size = Vector2(540, 110)
	_scene_lines.placeholder_text = "So you're the lancers everyone's talking about.\nnarrator: The room goes quiet.\n(angry) What do you want?"
	v.add_child(_scene_lines)
	v.add_child(StoryStyle.label("Replies (leave empty for none; up to 6). \"Reply -> their answer\" adds an answer.", 12, StoryStyle.DIM, 540))
	_scene_choices = []
	for i in range(6):
		var h := HBoxContainer.new()
		v.add_child(h)
		var t := _line("", "Reply %d" % (i + 1))
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(t)
		var fx := OptionButton.new()
		for q: Array in QUICK_FX:
			fx.add_item(str(q[0]))
		h.add_child(fx)
		_scene_choices.append({"text": t, "fx": fx})
	var b := HBoxContainer.new()
	v.add_child(b)
	var play := StoryStyle.button("Play it now", 15)
	play.pressed.connect(func() -> void: _send("gm_scene", _scene_params(true)))
	b.add_child(play)
	var save := StoryStyle.button("Save for later", 15)
	save.pressed.connect(func() -> void: _send("gm_scene", _scene_params(false)))
	b.add_child(save)
	var saved := GmTools.scenes(story)
	if not saved.is_empty():
		v.add_child(StoryStyle.label("SAVED SCENES", 13, StoryStyle.GOLD))
		for id: String in saved:
			if id.begins_with("gm_brief_"):
				continue
			var first := str((saved[id]["nodes"] as Dictionary).get("l0", {}).get("line", ""))
			var row := StoryStyle.button("▶ %s" % first.left(60), 13)
			var sid := id
			row.pressed.connect(func() -> void: _send("gm_scene", {"id": sid}))
			v.add_child(row)


func _scene_params(start: bool) -> Dictionary:
	var lines: Array = []
	for raw: String in _scene_lines.text.split("\n", false):
		var t := raw.strip_edges()
		var who := "npc"
		for w: String in ["pilot", "narrator", "npc"]:
			if t.to_lower().begins_with(w + ":"):
				who = w
				t = t.substr(w.length() + 1).strip_edges()
		var expr := ""
		if t.begins_with("(") and t.contains(")"):
			expr = t.substr(1, t.find(")") - 1).strip_edges().to_lower()
			t = t.substr(t.find(")") + 1).strip_edges()
		if t != "":
			lines.append({"who": who, "text": t, "expression": expr if PortraitSpec.expression_ids().has(expr) else ""})
	var choices: Array = []
	for c: Dictionary in _scene_choices:
		var t := (c["text"] as LineEdit).text.strip_edges()
		if t == "":
			continue
		var parts := t.split("->", true, 1)
		choices.append({"text": parts[0].strip_edges(), "reply": parts[1].strip_edges() if parts.size() > 1 else "",
			"effects": (QUICK_FX[(c["fx"] as OptionButton).selected][1] as Array).duplicate(true)})
	return {"npc": str(_scene_npc.get_item_metadata(_scene_npc.selected)) if _scene_npc.item_count > 0 else "",
		"speaker": str(_scene_pilot.get_item_metadata(_scene_pilot.selected)) if _scene_pilot.item_count > 0 else "",
		"lines": lines, "choices": choices, "start": start}


# --- Jobs --------------------------------------------------------------------------------

func _jobs() -> Array:
	var out: Array = story.hooks.duplicate()
	if not story.current_hook.is_empty():
		out.push_front(story.current_hook)
	return out


func _jobs_tab() -> void:
	var v := _page("Jobs")
	_job_pick = _row(v, "Job", OptionButton.new())
	var jobs := _jobs()
	for h: Dictionary in jobs:
		_job_pick.add_item(("▶ " if h == story.current_hook else "") + str(h.get("title", "")))
		_job_pick.set_item_metadata(_job_pick.item_count - 1, h["id"])
	_job_pick.item_selected.connect(func(_i: int) -> void: _fill_job())
	_job_fields = {}
	for k: String in ["title", "objective", "stakes", "question", "place", "enemy"]:
		_job_fields[k] = _row(v, k.capitalize(), _line())
	v.add_child(StoryStyle.label("Your own briefing (replaces the generated one; one line per row, the patron says them):", 12, StoryStyle.DIM, 540))
	_job_brief = TextEdit.new()
	_job_brief.custom_minimum_size = Vector2(540, 70)
	v.add_child(_job_brief)
	_job_cmd = _row(v, "Commander", OptionButton.new())
	_job_cmd_new = _row(v, "New callsign", _line("", "only for \"A new commander\""))
	_twist_text = _row(v, "Twist", _line("", "what the twist is (hidden from players)"))
	var b := HBoxContainer.new()
	v.add_child(b)
	var apply := StoryStyle.button("Apply changes", 14)
	apply.pressed.connect(_apply_job)
	b.add_child(apply)
	for pair: Array in [["Set twist", "set"], ["Reveal twist now", "reveal"], ["Remove twist", "hide"]]:
		var tb := StoryStyle.button(str(pair[0]), 13)
		var what := str(pair[1])
		tb.pressed.connect(func() -> void: _send("gm_twist", {"hook": _sel_job(), "do": what, "reveal": _twist_text.text, "question": ""}))
		b.add_child(tb)
	var rm := StoryStyle.button("Remove this job", 13)
	rm.pressed.connect(func() -> void: _send("gm_remove_job", {"hook": _sel_job()}))
	v.add_child(rm)
	v.add_child(StoryStyle.label("NEW SIDE JOB", 13, StoryStyle.GOLD))
	_new_job = _row(v, "Kind", OptionButton.new())
	var temps: Dictionary = MissionHooks.data().get("templates", {})
	for id: String in temps:
		_new_job.add_item(id.replace("_", " ").capitalize())
		_new_job.set_item_metadata(_new_job.item_count - 1, id)
	_new_job_title = _row(v, "Title", _line("", "optional"))
	var add := StoryStyle.button("Post it on the board", 14)
	add.pressed.connect(func() -> void: _send("gm_job", {"template": str(_new_job.get_item_metadata(_new_job.selected)), "title": _new_job_title.text}))
	v.add_child(add)
	_fill_job()


func _sel_job() -> String:
	return str(_job_pick.get_item_metadata(_job_pick.selected)) if _job_pick.item_count > 0 and _job_pick.selected >= 0 else ""


func _fill_job() -> void:
	var h := GmTools._hook(story, _sel_job()) if _sel_job() != "" else {}
	for k: String in _job_fields:
		(_job_fields[k] as LineEdit).text = str(h.get(k, ""))
	_job_brief.text = ""
	var sid := str(h.get("briefing_scene", ""))
	if GmTools.scenes(story).has(sid):
		var nodes: Dictionary = GmTools.scenes(story)[sid]["nodes"]
		_job_brief.text = "\n".join(PackedStringArray(range(nodes.size()).map(func(i: int) -> String: return str(nodes.get("l%d" % i, {}).get("line", "")))))
	_job_cmd.clear()
	for pair: Array in [["(keep)", "keep"], ["No named commander", "none"], ["A new commander", "new"]]:
		_job_cmd.add_item(str(pair[0]))
		_job_cmd.set_item_metadata(_job_cmd.item_count - 1, pair[1])
	for id: String in Rivals.at_large(story):
		_job_cmd.add_item(Rivals.call_name(story.npcs[id]) + ("  (current)" if str(h.get("commander", {}).get("id", "")) == id else ""))
		_job_cmd.set_item_metadata(_job_cmd.item_count - 1, id)
	_twist_text.text = str(h.get("twist", {}).get("reveal", ""))


func _apply_job() -> void:
	var set := {}
	var h := GmTools._hook(story, _sel_job())
	for k: String in _job_fields:
		var t := (_job_fields[k] as LineEdit).text
		if t != str(h.get(k, "")):
			set[k] = t
	if h != story.current_hook:
		set["briefing"] = Array(_job_brief.text.split("\n", false))
	var cmd := str(_job_cmd.get_item_metadata(_job_cmd.selected))
	if cmd == "new":
		set["commander"] = {"new": {"callsign": _job_cmd_new.text}}
	elif cmd != "keep":
		set["commander"] = cmd
	_send("gm_edit_job", {"hook": _sel_job(), "set": set})


# --- Standing and reserves --------------------------------------------------------------

func _standing_tab() -> void:
	var v := _page("Standing & reserves")
	v.add_child(StoryStyle.label("STANDING (this game's own bookkeeping, not a book rule)", 13, StoryStyle.GOLD))
	var fs: Array = Sector.factions_of(story, Sector.current(story)) if not Sector.current(story).is_empty() else []
	for f: String in story.standing:
		if not fs.has(f):
			fs.append(f)
	for f: String in fs:
		var h := HBoxContainer.new()
		v.add_child(h)
		var l := StoryStyle.label("%s: %s" % [f, StoryText.standing_label(story.get_standing(f))], 14)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		for d: int in [-1, 1]:
			var b := StoryStyle.button("%+d" % d, 13)
			var fac := f
			var dd := d
			b.pressed.connect(func() -> void: _send("gm_standing", {"faction": fac, "add": dd}))
			h.add_child(b)
	v.add_child(StoryStyle.label("RESERVES (Core p.50-52: the GM hands them out)", 13, StoryStyle.GOLD))
	_res_pilot = _row(v, "To", OptionButton.new())
	_res_pilot.add_item("The whole squad")
	_res_pilot.set_item_metadata(0, "squad")
	for pid: String in campaign.pilots:
		if story.is_alive(pid):
			_res_pilot.add_item(str(campaign.pilots[pid].get("callsign", pid)))
			_res_pilot.set_item_metadata(_res_pilot.item_count - 1, pid)
	_res_pick = _row(v, "Reserve", OptionButton.new())
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(StoryEffects.RESERVES_FILE))
	for r: Dictionary in (data if data is Array else []):
		_res_pick.add_item("%s (%s)" % [r["name"], r.get("type", "")])
		_res_pick.set_item_metadata(_res_pick.item_count - 1, r["id"])
	_res_pick.add_item("Custom...")
	_res_pick.set_item_metadata(_res_pick.item_count - 1, "custom")
	_res_custom = _row(v, "Custom name", _line("", "only for Custom..."))
	var give := StoryStyle.button("Give", 14)
	give.pressed.connect(func() -> void:
		_send("gm_reserve", {"pilot": str(_res_pilot.get_item_metadata(_res_pilot.selected)), "reserve": str(_res_pick.get_item_metadata(_res_pick.selected)), "name": _res_custom.text}))
	v.add_child(give)
	for pid: String in story.reserves:
		var list: Array = story.reserves[pid]
		for i in range(list.size()):
			var h := HBoxContainer.new()
			v.add_child(h)
			var l := StoryStyle.label("%s: %s" % [campaign.pilots.get(pid, {}).get("callsign", pid), list[i].get("name", "")], 13)
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(l)
			var rb := StoryStyle.button("Take back", 12)
			var who := pid
			var idx := i
			rb.pressed.connect(func() -> void: _send("gm_reserve", {"pilot": who, "remove": idx}))
			h.add_child(rb)


# --- People ------------------------------------------------------------------------------

func _people_tab() -> void:
	var v := _page("People")
	_npc_pick = _row(v, "Person", OptionButton.new())
	for id: String in _people():
		_npc_pick.add_item(str(story.npcs[id]["name"]))
		_npc_pick.set_item_metadata(_npc_pick.item_count - 1, id)
	_npc_pick.item_selected.connect(func(_i: int) -> void: _fill_npc())
	_npc_fields = {}
	for k: String in ["name", "title", "faction", "personality", "want", "secret"]:
		_npc_fields[k] = _row(v, k.capitalize(), _line())
	_npc_dead = CheckBox.new()
	_npc_dead.text = "Dead"
	v.add_child(_npc_dead)
	var apply := StoryStyle.button("Apply", 14)
	apply.pressed.connect(func() -> void:
		var set := {}
		for k: String in _npc_fields:
			set[k] = (_npc_fields[k] as LineEdit).text
		set["dead"] = _npc_dead.button_pressed
		_send("gm_npc", {"npc": str(_npc_pick.get_item_metadata(_npc_pick.selected)), "set": set}))
	v.add_child(apply)
	v.add_child(StoryStyle.label("SOMEONE NEW AT THIS HUB", 13, StoryStyle.GOLD))
	_new_role = _row(v, "Role", OptionButton.new())
	for role: String in NpcGen.roles():
		_new_role.add_item(str(NpcGen.roles()[role].get("name", role)))
		_new_role.set_item_metadata(_new_role.item_count - 1, role)
	_new_name = _row(v, "Name", _line())
	var add := StoryStyle.button("Add them", 14)
	add.pressed.connect(func() -> void: _send("gm_npc", {"new": {"role": str(_new_role.get_item_metadata(_new_role.selected)), "name": _new_name.text}}))
	v.add_child(add)
	_fill_npc()


func _fill_npc() -> void:
	if _npc_pick.item_count == 0:
		return
	var npc: Dictionary = story.npcs.get(str(_npc_pick.get_item_metadata(_npc_pick.selected)), {})
	for k: String in _npc_fields:
		(_npc_fields[k] as LineEdit).text = str(npc.get(k, ""))
	_npc_dead.button_pressed = bool(npc.get("dead", false))


## godot --path . -s res://tools/screenshot.gd -- res://scenes/story/gm_panel.tscn out.png 20
func screenshot_setup(_args: Array) -> Variant:
	var d := HubDemo.make(21)
	bind(d["engine"], d["story"], d["campaign"])
	open()
	_scene_lines.text = "You're the lancers who blew the dam.\nnarrator: The bar goes quiet.\n(angry) Give me one reason not to call the marshal."
	(_scene_choices[0]["text"] as LineEdit).text = "We saved the valley. -> ...Fine. One drink."
	(_scene_choices[1]["text"] as LineEdit).text = "Call them. We'll wait."
	(_scene_choices[0]["fx"] as OptionButton).select(1)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.12, 0.15)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	move_child(bg, 0)
	return null
