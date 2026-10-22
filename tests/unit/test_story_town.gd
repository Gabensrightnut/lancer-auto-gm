extends TestCase
## Fights in town: jobs, standoffs and twists that put the battle in the hub itself, with the
## hub's id and layout passed to the mission build (world-maps builds the map from it).

const Setup := preload("res://tests/unit/test_story_dialogue.gd")
const MissionTest := preload("res://tests/unit/test_gm_mission.gd")


func test_defend_the_town_is_fought_in_its_streets() -> void:
	var t := Setup.setup(210)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var hook := MissionHooks.make(s, c, "defend_town", {})
	expect(bool(hook["in_town"]), "a job in town")
	var spot_ids: Array = (s.hub["spots"] as Array).map(func(x: Dictionary) -> String: return x["id"])
	expect(spot_ids.has(str(hook["town_spot"])), "at one of the hub's own buildings")
	expect(not str(hook["objective"]).contains("{"), str(hook["objective"]))
	s.hooks.append(hook)
	t["engine"].submit(s, c, {"type": "choose_hook", "seat": "gm", "params": {"hook": hook["id"]}})
	Dialogue.close(s)
	t["engine"].submit(s, c, {"type": "confirm_reserves", "seat": "gm"})
	var gen := CampaignLoop.build_mission(c, s, MissionTest.db())
	var town: Dictionary = gen["mission"].flavor["town"]
	expect_eq(str(town["hub_id"]), str(s.hub["id"]), "the battle knows which town")
	expect_eq(town["spots"], s.hub["spots"], "and its layout, the same one the 3D town is built from")
	expect_eq(str(town["at"]), str(hook["town_spot"]))
	expect(not bool(town["on_foot"]))


func test_a_standoff_breaks_out_where_you_are() -> void:
	var t := Setup.setup(211)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var bar := Setup.npc_with_role(s, "bartender")
	var r: Dictionary = t["engine"].submit(s, c, {"type": "gm_scene", "seat": "gm", "params": {"npc": bar, "lines": [{"who": "npc", "text": "There's a crowd outside, and they've brought guns."}],
		"choices": [{"text": "Then let's go meet them.", "effects": [{"start_combat": {"hook": "standoff", "on_foot": true, "patron": "$npc", "reason": "Guns out in the street."}}]}]}})
	expect(r["ok"], str(r["reason"]))
	r = t["engine"].submit(s, c, {"type": "dialogue_choose", "seat": "p1", "params": {"choice": "c0"}})
	expect(r["ok"], str(r["reason"]))
	expect_eq(s.phase, "mission", "straight into the fight")
	expect(bool(s.current_hook["in_town"]), "in town")
	expect_eq(str(s.current_hook["town_spot"]), str(s.npcs[bar]["spot"]), "right outside the bar")
	var gen := CampaignLoop.build_mission(c, s, MissionTest.db())
	var town: Dictionary = gen["mission"].flavor["town"]
	expect(bool(town["on_foot"]), "on foot beside the mechs")
	var p1_pilot := Pilots.pilot_of(gen["state"], (gen["state"] as GameState).unit("p1"))
	expect(p1_pilot == null or not p1_pilot.counters.has("mounted_in"), "the pilot starts out of the mech")


func test_jumped_before_leaving_town_stays_a_secret() -> void:
	var t := Setup.setup(212)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var hook := MissionHooks.make(s, c, "clear_raiders", {"twist": "jumped_in_town"})
	expect(not bool(hook.get("in_town", false)), "the job says it's out of town")
	expect(not str(hook["twist"]["reveal"]).contains("{"), str(hook["twist"]["reveal"]))
	var town := MissionHooks.town_for(s, hook)
	expect(not town.is_empty() and bool(town["on_foot"]), "but the fight is in town, on foot")
	s.hooks.append(hook)
	for h: Dictionary in StoryView.view_for(s, c, "p1")["story"]["hooks"]:
		expect(not h.has("twist"), "players can't see it coming")
