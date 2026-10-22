extends TestCase
## Boarding actions (Core p.42: board a hostile ship and take it over; pirates, p.40-42).

const Setup := preload("res://tests/unit/test_story_dialogue.gd")
const MissionTest := preload("res://tests/unit/test_gm_mission.gd")


func test_boarding_jobs_tell_the_map_what_to_build() -> void:
	var t := Setup.setup(250)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	for tid: String in ["seize_ship", "rescue_crew", "take_smuggler"]:
		var h := MissionHooks.make(s, c, tid, {})
		expect(h.has("boarding") and str(h["landscape"]) == "starship", "%s is a boarding job" % tid)
		expect(not str(h["objective"]).contains("{"), str(h["objective"]))
	var hook := MissionHooks.make(s, c, "seize_ship", {})
	s.hooks.append(hook)
	t["engine"].submit(s, c, {"type": "choose_hook", "seat": "gm", "params": {"hook": hook["id"]}})
	Dialogue.close(s)
	t["engine"].submit(s, c, {"type": "confirm_reserves", "seat": "gm"})
	var gen := CampaignLoop.build_mission(c, s, MissionTest.db())
	expect_eq(str(gen["mission"].flavor["boarding"]["map"]), "docked", "two docked ships")


func test_pirates_board_the_transport_on_the_way() -> void:
	var t := Setup.setup(251)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	c.options["travel_events"] = true
	c.options["pirate_chance"] = 100
	s.phase = "downtime"
	var far: Dictionary = {}
	for w: Dictionary in Sector.get_sector(s)["worlds"]:
		if str(w["system"]) == "sys_1":
			far = w
	var r: Dictionary = t["engine"].submit(s, c, {"type": "travel", "seat": "gm", "params": {"world": far["id"]}})
	expect(r["ok"], str(r["reason"]))
	expect((r["events"] as Array).any(func(x: Dictionary) -> bool: return x["type"] == "boarded"), "grapples on the hull")
	expect_eq(s.phase, "mission", "straight into the fight")
	expect_eq(str(s.current_hook["template"]), "repel_boarders")
	expect_eq(str(s.current_hook["boarding"]["map"]), "own_ship", "on the squad's own decks")
	expect(not bool(s.current_hook.get("in_town", false)), "not in town")


func test_the_long_arrival_is_boarded() -> void:
	var d := CampaignScript.data("long_arrival")
	expect_eq(str(d["chapters"]["c12_final_ship"]["hook"]["boarding"]["map"]), "docked", "the finale aboard the colony ship")
	expect_eq(str(d["chapters"]["c6_wakeful"]["hook"]["boarding"]["kind"]), "rescue")
