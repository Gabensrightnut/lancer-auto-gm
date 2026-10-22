class_name HubHud
extends Control
## The hub's on-screen info: where you are and what phase of the campaign it is (explained
## plainly), the squad (HP, Down and Out, reserves), standing with the factions you've met,
## the "Talk to" prompt, short toasts for story events, and the job board.

signal story_events(events: Array)

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
	_info.add_theme_font_size_override("normal_font_size", 14)
	_info.add_theme_font_size_override("bold_font_size", 18)
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_panel.add_child(_info)
	_phase = StoryStyle.label("", 15, StoryStyle.GOLD, 700)
	_phase.add_theme_stylebox_override("normal", StoryStyle.panel(StoryStyle.GOLD, Color(0.05, 0.05, 0.04, 0.85), 1, 4, 8))
	_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_phase)
	_next = StoryStyle.button("", 15)
	_next.pressed.connect(_next_step)
	add_child(_next)
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
	bb.add_child(StoryStyle.label("Lancers aren't paid in money. You take jobs for the people and factions you want on your side, and every mission you finish, win or lose, raises your License Level.", 14, StoryStyle.DIM, 560))
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
	var t := "[b]%s[/b]\n[color=#9fb2c8]%s  ·  %s  ·  %s[/color]\n\n" % [hub.get("name", "?"), str(hub.get("kind", "")).capitalize(), hub.get("planet", ""), hub.get("faction", "")]
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
		for r: Dictionary in res:
			t += "   [color=#7fe0a0]+ %s[/color]\n" % r["name"]
	var met := {}
	for n: String in story.contacts:
		met[str(story.npcs.get(n, {}).get("faction", ""))] = true
	if not met.is_empty():
		t += "\n[color=#ffd166]STANDING[/color]\n"
		var fs := met.keys()
		fs.sort()
		for f: String in fs:
			var v := story.get_standing(f)
			var col := "#7fb8ff" if v > 0 else ("#ff7b6b" if v < 0 else "#c8d0da")
			t += "%s  [color=%s]%s[/color]\n" % [f, col, StoryText.standing_label(v)]
	var owed: Array = (story.downtime.get("obligations", []) as Array).filter(func(o: Dictionary) -> bool: return not bool(o.get("done", false)))
	for o: Dictionary in owed:
		t += "[color=#ff9b7b]Owed: %s[/color]\n" % o["what"]
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
