extends TestCase
## The squad's vote on a big story choice (Decisions, DecisionPanel): options side by side,
## who voted for what, votes that can change, the arena countdown, and the winners' answer.

const Setup := preload("res://tests/unit/test_story_dialogue.gd")
const MissionTest := preload("res://tests/unit/test_gm_mission.gd")


func _three_way(t: Dictionary) -> void:
	StoryEffects.apply({"decision": {"id": "fork", "prompt": "Which way through the canyon?", "fight": {"place": "the canyon floor"},
		"options": [{"id": "left", "label": "Left", "effects": [{"set_flag": "went_left"}]},
			{"id": "middle", "label": "Middle", "effects": [{"set_flag": "went_middle"}]},
			{"id": "right", "label": "Right", "effects": [{"set_flag": "went_right"}]}]}}, t["story"], t["campaign"], {})


func _two_humans(t: Dictionary) -> void:
	var e: StoryEngine = t["engine"]
	e.submit(t["story"], t["campaign"], {"type": "set_seat", "seat": "gm", "params": {"seat": "p2", "pilot": t["b"], "ai": false}})
	var third := str((t["campaign"] as Campaign).new_pilot("Joss Varga", "Dove")["id"])
	e.submit(t["story"], t["campaign"], {"type": "set_seat", "seat": "gm", "params": {"seat": "p3", "pilot": third, "ai": true}})


func _sub(t: Dictionary, type: String, params: Dictionary, seat: String) -> Dictionary:
	return t["engine"].submit(t["story"], t["campaign"], {"type": type, "seat": seat, "params": params})


func test_a_split_vote_can_still_be_talked_round() -> void:
	var t := Setup.setup(760)
	var s: StoryState = t["story"]
	_two_humans(t)
	_three_way(t)
	var r := _sub(t, "decide", {"option": "left"}, "p1")
	var v: Array = (r["events"] as Array).filter(func(x: Dictionary) -> bool: return x["type"] == "decision_vote")
	expect(not v.is_empty() and (v[0]["sides"]["left"] as Array).has("p3"), "Bluebird's AI squadmate stands with their pick")
	expect(not _sub(t, "decide", {"option": "up"}, "p2")["ok"], "only the choices on offer")
	r = _sub(t, "decide", {"option": "right"}, "p2")
	var split: Array = (r["events"] as Array).filter(func(x: Dictionary) -> bool: return x["type"] == "party_split")
	expect(not split.is_empty(), "the humans split")
	expect_eq(int(split[0]["countdown"]), 20, "a 20 second countdown by default")
	expect(str(split[0]["text"]).contains("Left (Bluebird") and str(split[0]["text"]).contains("Right (Kettle)"), "Settle it in the arena: %s" % split[0]["text"])
	expect(str(split[0].get("note", "")).contains("Nobody dies"), "explained plainly the first time")
	r = _sub(t, "decide", {"option": "left"}, "p2")
	var made: Array = (r["events"] as Array).filter(func(x: Dictionary) -> bool: return x["type"] == "decision_made")
	expect(not made.is_empty() and bool(made[0].get("split_cancelled", false)), "Kettle changes their mind before the countdown ends: no fight")
	expect(bool(s.flags.get("went_left", false)) and not s.flags.has("went_right"))


func test_the_arena_decides_and_only_the_winners_choice_happens() -> void:
	var t := Setup.setup(761)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	c.options["split_countdown"] = 45
	_two_humans(t)
	s.flags[Decisions.EXPLAINED] = true
	_three_way(t)
	_sub(t, "decide", {"option": "left"}, "p1")
	var r := _sub(t, "decide", {"option": "right"}, "p2")
	var split: Dictionary = (r["events"] as Array).filter(func(x: Dictionary) -> bool: return x["type"] == "party_split")[0]
	expect_eq(int(split["countdown"]), 30, "the host's countdown is 15 to 30 seconds")
	expect(not split.has("note"), "explained only once")
	expect(_sub(t, "split_start", {}, "gm")["ok"], "the countdown ran out: the arena fight starts")
	expect(not _sub(t, "decide", {"option": "left"}, "p2")["ok"], "votes lock once it's being fought out")
	expect(not _sub(t, "split_resolved", {"winner": "sideways"}, "gm")["ok"])
	r = _sub(t, "split_resolved", {"winner": "right"}, "gm")
	expect(r["ok"])
	expect(bool(s.flags.get("went_right", false)) and not s.flags.has("went_left"), "the winners' option is the story's answer; the losers' isn't taken")
	expect_eq(str(s.flags.get("decided:fork", "")), "right")


func test_the_vote_screen_shows_who_picked_what() -> void:
	var t := Setup.setup(762)
	var s: StoryState = t["story"]
	_two_humans(t)
	_three_way(t)
	var panel := DecisionPanel.new()
	panel.bind(t["engine"], s, t["campaign"], MissionTest.db(), "p1")
	var r := _sub(t, "decide", {"option": "middle"}, "p1")
	panel.show_events(r["events"])
	expect(panel.visible)
	expect_eq(panel._cols.get_child_count(), 3, "all three options side by side")
	var middle: Control = panel._cols.get_child(1)
	var voters: Control = middle.get_child(0)
	expect_eq(voters.get_child_count(), 2, "Bluebird and their AI squadmate above Middle")
	panel.free()
