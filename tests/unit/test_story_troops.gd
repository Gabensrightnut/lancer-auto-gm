extends TestCase
## The squad's own troops (Troops): recruited by talking, losses carried between fights,
## a ration per squad per day, desertion, and hungry troops siding with a pilot with a grudge.

const Setup := preload("res://tests/unit/test_story_dialogue.gd")
const DR := preload("res://tests/unit/test_story_dead_reckoning.gd")


func _talk_to_menu(t: Dictionary, npc: String) -> Array:
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	e.submit(s, c, {"type": "talk", "seat": "p1", "params": {"npc": npc}})
	var guard := 0
	while Dialogue.is_open(s) and Dialogue.offered(s).is_empty() and guard < 10:
		guard += 1
		e.submit(s, c, {"type": "dialogue_next", "seat": "p1", "params": {}})
	return Dialogue.offered(s)


func test_recruit_by_talking_at_the_bar() -> void:
	var t := Setup.setup(740)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	var barkeep := Setup.npc_with_role(s, "bartender")
	expect(not _talk_to_menu(t, barkeep).any(func(o: Dictionary) -> bool: return str(o["id"]).begins_with("recruit")), "no troops of your own, no hiring")
	Dialogue.close(s)
	c.options["troops"] = true
	var offered := _talk_to_menu(t, barkeep)
	expect(offered.any(func(o: Dictionary) -> bool: return str(o["id"]) == "recruit_bar"), "ask the bartender for fighters, in your own words")
	var r := e.submit(s, c, {"type": "dialogue_choose", "seat": "p1", "params": {"choice": "recruit_bar"}})
	expect(r["ok"], str(r.get("reason", "")))
	expect_eq(Troops.squads(s).size(), 1, "ten fighters sign on")
	expect_eq(Troops.men(s), 10)
	expect((r["events"] as Array).any(func(x: Dictionary) -> bool: return str(x.get("type", "")).contains("obligation")), "paid with a favour owed (no wallet)")
	Dialogue.close(s)
	expect(not _talk_to_menu(t, barkeep).any(func(o: Dictionary) -> bool: return str(o["id"]) == "recruit_bar"), "once per person")


func test_losses_carry_over_and_hunger_ends_in_desertion() -> void:
	var t := Setup.setup(741)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	c.options["troops"] = true
	Troops.recruit(s, c, {"source": "crew", "free": true, "name": "the old hands"}, {})
	Troops.recruit(s, c, {"source": "crew", "free": true, "name": "the new blood"}, {})
	var gen := MissionGenerator.generate(741, {"db": preload("res://tests/unit/test_gm_mission.gd").db(), "size": 20, "players": 2})
	var state: GameState = gen["state"]
	var a := Unit.new()
	a.id = "troop_sq1"
	a.hp = 4
	state.units[a.id] = a
	var b := Unit.new()
	b.id = "troop_sq2"
	b.destroyed = true
	state.units[b.id] = b
	var ev := Troops.after_battle(s, state)
	expect_eq(Troops.squads(s).size(), 1, "one squad lost to the last man")
	expect_eq(int(Troops.squads(s)[0]["men"]), 4, "the other came back with four: four it stays")
	expect(ev.any(func(x: Dictionary) -> bool: return x["type"] == "troops_lost"))
	expect(not Troops.reinforce(s, c).is_empty())
	expect_eq(int(Troops.squads(s)[0]["men"]), 10, "reinforced back to ten")
	# A ration per squad per day, with the food-and-water rule.
	e.submit(s, c, {"type": "house_rule", "seat": "gm", "params": {"id": "hr_survival", "on": true}})
	Economy.start(s, c, Economy.R_FOOD)
	s.flags[Economy.SURVIVAL]["rations"] = 0
	Agendas.add(s, c, t["b"], "grievance", "test", 2)
	var all: Array = []
	for i in range(3):
		all.append_array(Economy.eat(s, c, 1))
	expect(all.any(func(x: Dictionary) -> bool: return x["type"] == "troops_hungry"), "unfed, they grumble")
	expect(all.any(func(x: Dictionary) -> bool: return x["type"] == "troops_side" and str(x["pilot"]) == t["b"]), "and listen to the pilot with a grudge")
	expect(all.any(func(x: Dictionary) -> bool: return x["type"] == "deserted"), "then they leave")
	expect(Troops.squads(s).is_empty())


func test_hungry_troops_stand_with_the_instigator_in_a_split() -> void:
	var t := Setup.setup(742)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	c.options["troops"] = true
	e.submit(s, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p2", "pilot": t["b"], "ai": false}})
	Troops.recruit(s, c, {"source": "crew", "free": true}, {})
	(Troops.squads(s)[0] as Dictionary)["with"] = t["b"]
	StoryEffects.apply({"decision": {"id": "mutiny", "prompt": "Take the ship", "accept": [], "decline": []}}, s, c, {})
	e.submit(s, c, {"type": "decide", "seat": "p1", "params": {"accept": true}})
	var r := e.submit(s, c, {"type": "decide", "seat": "p2", "params": {"accept": false}})
	var split: Array = (r["events"] as Array).filter(func(x: Dictionary) -> bool: return x["type"] == "party_split")
	expect(not split.is_empty() and not split[0].has("troops"), "the arena fight is only the players' mechs")
	expect_eq((Troops.loyalties(s).get("p2", []) as Array).size(), 1, "but the hungry squad stands with Kettle in the story")


func test_dead_reckoning_crews() -> void:
	var t := DR.fresh(743)
	var s: StoryState = t["story"]
	for p: int in [0, 0, 0]:
		DR.play_chapter(t, p)
	expect(Troops.squads(s).any(func(x: Dictionary) -> bool: return str(x["name"]) == "the old Cadence hands"), "staying aboard, the old hands stand with the lance")
	DR.play_chapter(t, 0, true, "sign on with us")
	expect(Troops.squads(s).any(func(x: Dictionary) -> bool: return str(x["name"]) == "the Brightwater's turned crew"), "a beaten crew can change sides")
