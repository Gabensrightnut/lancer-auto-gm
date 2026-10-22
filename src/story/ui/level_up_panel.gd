class_name LevelUpPanel
extends PanelContainer
## After the debrief every pilot goes up one License Level, win or lose (Core p.18). This
## panel takes the two picks the story side handles: +2 to a trigger (or a new +2 trigger)
## and +1 to a mech skill. Talent, license and core bonus picks are shown as waiting for the
## pilot builder.

signal story_events(events: Array)

var engine: StoryEngine
var story: StoryState
var campaign: Campaign
var seat := "p1"
var _box: VBoxContainer


func _init() -> void:
	add_theme_stylebox_override("panel", StoryStyle.panel(StoryStyle.GOLD))
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 8)
	add_child(_box)
	visible = false


func bind(e: StoryEngine, s: StoryState, c: Campaign, local_seat: String) -> void:
	engine = e
	story = s
	campaign = c
	seat = local_seat


func refresh() -> void:
	for ch in _box.get_children():
		ch.queue_free()
	var pid := story.pilot_of_seat(seat)
	var picks: Dictionary = story.pending_picks.get(pid, {})
	var p: Dictionary = campaign.pilots.get(pid, {})
	visible = story.phase == "level_up" and not p.is_empty()
	if not visible:
		return
	_box.add_child(StoryStyle.label("LEVEL UP  ·  %s is now LL%d (Grit +%d)" % [p.get("callsign", ""), int(p.get("ll", 0)), UnitFactory.grit(int(p.get("ll", 0)))], 22, StoryStyle.GOLD))
	_box.add_child(StoryStyle.label("Every pilot gains a License Level after a mission, whether it went well or not. Your License Level is your access to gear, favors and clout: there's no money in LANCER.", 14, StoryStyle.DIM, 620))
	var trig: OptionButton = null
	var mech: OptionButton = null
	if int(picks.get("trigger", 0)) > 0:
		_box.add_child(StoryStyle.label("+2 to a trigger you have, or a new trigger at +2:", 15))
		trig = OptionButton.new()
		for t: Dictionary in NarrativeCheck.triggers_of(p):
			if int(t["rank"]) < 3:
				trig.add_item("%s  +%d -> +%d" % [t["name"], t["bonus"], int(t["bonus"]) + 2])
				trig.set_item_metadata(trig.item_count - 1, t["id"])
		for sid: String in DowntimePanel._all_skills():
			if not p.get("skills", {}).has(sid):
				trig.add_item("New: %s +2" % NarrativeCheck.trigger_name(sid))
				trig.set_item_metadata(trig.item_count - 1, sid)
		_box.add_child(trig)
	if int(picks.get("mech_skill", 0)) > 0:
		_box.add_child(StoryStyle.label("+1 to a mech skill (Hull, Agility, Systems, Engineering; max +6):", 15))
		mech = OptionButton.new()
		for k: String in StoryEngine.MECH_SKILLS:
			mech.add_item("%s  %d -> %d" % [k.capitalize(), int(p.get(k, 0)), int(p.get(k, 0)) + 1])
			mech.set_item_metadata(mech.item_count - 1, k)
		_box.add_child(mech)
	var waiting := PackedStringArray()
	for k in ["talent", "license", "core_bonus"]:
		if int(picks.get(k, 0)) > 0:
			waiting.append("%d %s" % [int(picks[k]), {"talent": "talent rank", "license": "license rank", "core_bonus": "core bonus"}[k]])
	if not waiting.is_empty():
		_box.add_child(StoryStyle.label("Waiting for the pilot builder: " + ", ".join(waiting) + ".", 14, StoryStyle.BLUE, 620))
	if trig != null or mech != null:
		var ok := StoryStyle.button("Confirm", 16)
		ok.pressed.connect(func() -> void:
			var params := {"pilot": pid}
			if trig != null:
				params["trigger"] = trig.get_item_metadata(trig.selected)
			if mech != null:
				params["mech_skill"] = mech.get_item_metadata(mech.selected)
			var r := engine.submit(story, campaign, {"type": "level_picks", "seat": seat, "params": params})
			story_events.emit(r["events"])
			refresh())
		_box.add_child(ok)
	else:
		var go := StoryStyle.button("On to downtime", 16)
		go.pressed.connect(func() -> void:
			var r := engine.submit(story, campaign, {"type": "start_downtime", "seat": "gm", "params": {}})
			if not r["ok"]:
				_box.add_child(StoryStyle.label("✕ " + str(r["reason"]), 14, StoryStyle.RED, 620))
				return
			story_events.emit(r["events"])
			refresh())
		_box.add_child(go)


func _process(_delta: float) -> void:
	if visible:
		reset_size()
		var vp := get_viewport_rect().size
		position = ((vp - size) / 2.0).max(Vector2(8, 8))
