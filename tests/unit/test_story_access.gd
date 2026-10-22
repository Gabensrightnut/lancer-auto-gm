extends TestCase
## Reading options for story text: text size, the scroll-back log, skipping lines already read.

const Setup := preload("res://tests/unit/test_story_dialogue.gd")


func _talk_through(t: Dictionary, npc: String) -> void:
	var s: StoryState = t["story"]
	t["engine"].submit(s, t["campaign"], {"type": "talk", "seat": "p1", "params": {"npc": npc}})
	var guard := 0
	while Dialogue.is_open(s) and guard < 40:
		guard += 1
		var offered := Dialogue.offered(s)
		var leave := ""
		for o: Dictionary in offered:
			if str(o["id"]) == "leave":
				leave = "leave"
		if offered.is_empty():
			t["engine"].submit(s, t["campaign"], {"type": "dialogue_next", "seat": "p1", "params": {}})
		else:
			t["engine"].submit(s, t["campaign"], {"type": "dialogue_choose", "seat": "p1", "params": {"choice": leave if leave != "" else offered[0]["id"]}})


func _size_of(c: Control) -> int:
	var n := c.get_theme_font_size("font_size")
	c.free()
	return n


func test_text_size_scales_story_text() -> void:
	StorySettings.reset_for_tests()
	expect_eq(_size_of(StoryStyle.label("x", 16)), 16)
	StorySettings.set_text_scale(1.5)
	expect_eq(_size_of(StoryStyle.label("x", 16)), 24, "labels")
	expect_eq(_size_of(StoryStyle.button("x", 16)), 24, "buttons")
	StorySettings.set_text_scale(9.0)
	expect_eq(StorySettings.text_scale(), 1.6, "clamped")
	StorySettings.set_text_scale(1.0)
	var heard := [0]
	var on_change := func() -> void: heard[0] += 1
	StorySettings.notifier().changed.connect(on_change)
	StorySettings.cycle_text_scale()
	StorySettings.notifier().changed.disconnect(on_change)
	expect(StorySettings.text_scale() > 1.0 and heard[0] == 1, "one button steps through sizes and tells the UI")
	StorySettings.set_text_scale(1.0)


func test_the_log_keeps_every_conversation() -> void:
	StorySettings.reset_for_tests()
	var t := Setup.setup(170)
	var s: StoryState = t["story"]
	var bar := Setup.npc_with_role(s, "bartender")
	var rep := Setup.npc_with_role(s, "company_rep")
	_talk_through(t, bar)
	var after_one := Dialogue.transcript(s)
	expect(not after_one.is_empty() and after_one[0].has("header"), "each conversation starts with a header")
	expect(str(after_one[0]["header"]).contains(str(s.npcs[bar]["name"])))
	_talk_through(t, rep)
	var all := Dialogue.transcript(s)
	expect_eq(all.filter(func(l: Dictionary) -> bool: return l.has("header")).size(), 2, "both conversations are in the log")
	expect(all.size() > after_one.size())
	for i in range(300):
		_talk_through(t, bar)
	expect((s.flags[Dialogue.TRANSCRIPT] as Array).size() <= Dialogue.TRANSCRIPT_MAX, "the log has a cap")


func test_skipping_lines_already_read() -> void:
	StorySettings.reset_for_tests()
	var key := StorySettings.line_key("bartender", "greet", "Evening.")
	expect(not StorySettings.was_seen(key))
	StorySettings.mark_seen(key)
	expect(StorySettings.was_seen(key))
	expect(not StorySettings.was_seen(StorySettings.line_key("bartender", "greet", "Morning.")), "another line isn't")
	var t := Setup.setup(171)
	var s: StoryState = t["story"]
	t["engine"].submit(s, t["campaign"], {"type": "talk", "seat": "p1", "params": {"npc": Setup.npc_with_role(s, "bartender")}})
	if Dialogue.offered(s).is_empty():
		expect(DialogueView.can_auto_skip(s, t["campaign"], "p1"), "the speaker's player moves it on")
	var guard := 0
	while Dialogue.offered(s).is_empty() and Dialogue.is_open(s) and guard < 10:
		guard += 1
		t["engine"].submit(s, t["campaign"], {"type": "dialogue_next", "seat": "p1", "params": {}})
	expect(not DialogueView.can_auto_skip(s, t["campaign"], "p1"), "choices always wait")
	s.seats["p3"] = {"pilot": "", "ai": false}
	Dialogue.close(s)
	expect(not DialogueView.can_auto_skip(s, t["campaign"], "p1"), "nothing to skip when nobody's talking")
