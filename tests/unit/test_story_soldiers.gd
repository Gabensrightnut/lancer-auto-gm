extends TestCase
## Soldiers in the living world (Soldiers): every hub's garrison on its rounds, witnesses who
## raise the alarm, turning out when a crime becomes a fight, and the campaigns' own forces.

const Setup := preload("res://tests/unit/test_story_dialogue.gd")
const Main := preload("res://tests/unit/test_story_main_campaign.gd")
const DR := preload("res://tests/unit/test_story_dead_reckoning.gd")


func _soldiers(s: StoryState) -> Array:
	return (s.hub["npcs"] as Array).filter(func(id: String) -> bool: return str(s.npcs[id].get("role", "")) == Garrisons.ROLE)


func _by_duty(s: StoryState, duty: String) -> String:
	for id: String in _soldiers(s):
		if str(s.npcs[id].get("duty", "")) == duty:
			return id
	return ""


func test_every_hub_has_a_garrison_on_its_rounds() -> void:
	var t := Setup.setup(720)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	expect(_soldiers(s).size() >= 3, "guards, a night watch and a patrol")
	expect(str(Garrisons.garrison(s).get("faction", "")) != "")
	var guard := _by_duty(s, "guard")
	var watch := _by_duty(s, "watch")
	var patrol := _by_duty(s, "patrol")
	expect(guard != "" and watch != "" and patrol != "")
	for i in range(4):
		if TownLife.period(s) == "day":
			break
		e.submit(s, c, {"type": "wait", "seat": "gm", "params": {"periods": 1}})
	expect_eq(str(TownLife.where_npc(s, guard)["spot"]), "office", "a guard on the office door by day")
	expect(bool(TownLife.where_npc(s, watch)["asleep"]), "the night watch sleeps by day")
	expect_eq(str(TownLife.where_npc(s, patrol)["spot"]), "market", "the patrol walks the market")
	for i in range(4):
		if TownLife.period(s) == "night":
			break
		e.submit(s, c, {"type": "wait", "seat": "gm", "params": {"periods": 1}})
	var w := TownLife.where_npc(s, watch)
	expect(not bool(w["asleep"]) and str(w["spot"]) == "plaza", "the watch is out in the square at night")
	expect_eq(str(s.npcs[guard]["scene"]), "soldier", "and you can talk to them")


func test_a_soldier_who_sees_it_raises_the_alarm() -> void:
	var t := Setup.setup(721)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	for i in range(4):
		if TownLife.period(s) == "day":
			break
		e.submit(s, c, {"type": "wait", "seat": "gm", "params": {"periods": 1}})
	var ev := TownLife._seen(s, c, t["a"], "market", "floor", false, "", 10)
	expect(ev.any(func(x: Dictionary) -> bool: return x["type"] == "alarm"), "the patrol saw it: the alarm goes up")
	e._combat_from_scene(s, c, {"hook": "standoff", "on_foot": true, "in_town": true, "crime": true})
	expect_eq(str(s.current_hook.get("soldiers", {}).get("faction", "")), str(Garrisons.garrison(s)["faction"]), "the garrison turns out")


func test_the_campaigns_have_their_own_forces() -> void:
	var la := Main.fresh(722)
	var ls: StoryState = la["story"]
	expect(_soldiers(ls).any(func(id: String) -> bool: return str(ls.npcs[id]["faction"]) == "Marshal Vell's deputies"), "Redwater: the marshal's deputies")
	var dr := DR.fresh(723)
	var ds: StoryState = dr["story"]
	var dc: Campaign = dr["campaign"]
	expect(_soldiers(ds).any(func(id: String) -> bool: return str(ds.npcs[id]["faction"]) == "the Cadence's watch"), "the Cadence keeps a watch")
	var hunt := CampaignScript.build_hook(ds, dc, "c15_final_hunt")
	expect_eq(str(hunt.get("soldiers", {}).get("faction", "")), "Union Navy marines", "the Union sends marines after you")
	var boarders := CampaignScript.build_hook(ds, dc, "p3_answer")
	expect_eq(str(boarders.get("soldiers", {}).get("faction", "")), "Hask's boarding party")
