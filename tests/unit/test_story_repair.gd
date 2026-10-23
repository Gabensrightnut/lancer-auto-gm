extends TestCase
## Mech damage lasts until a Full Repair at a repair bay (Core p.82: 10 hours somewhere
## secure), and the hours cost what they cost: the clock, rations, and the enemy regrouping.

const Setup := preload("res://tests/unit/test_story_dialogue.gd")
const MissionTest := preload("res://tests/unit/test_gm_mission.gd")
const Picks := preload("res://tests/unit/test_story_sector.gd")


func _mission(t: Dictionary) -> Dictionary:
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	e.submit(s, c, {"type": "choose_hook", "seat": "gm", "params": {"hook": s.hooks[0]["id"]}})
	Dialogue.close(s)
	e.submit(s, c, {"type": "confirm_reserves", "seat": "gm", "params": {}})
	return CampaignLoop.build_mission(c, s, MissionTest.db())


func _finish(t: Dictionary, gen: Dictionary) -> void:
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	(gen["mission"] as Mission).outcome = Mission.PLAYERS
	CampaignLoop.finish_mission(c, s, e, gen["state"], gen["mission"], [])
	Dialogue.close(s)
	e.submit(s, c, {"type": "level_up", "seat": "gm", "params": {}})
	for pid: String in s.pending_picks.keys():
		e.submit(s, c, {"type": "level_picks", "seat": "gm", "params": Picks.pick_for(c.pilots[pid])})


func test_damage_lasts_until_a_full_repair() -> void:
	var t := Setup.setup(700)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	var gen := _mission(t)
	var mech: Unit = (gen["state"] as GameState).unit("p1")
	var full_hp := mech.max_hp
	mech.hp = full_hp - 4
	mech.structure = mech.max_structure - 1
	mech.repairs = 1
	_finish(t, gen)
	expect(RepairBay.needed(s), "the damage is remembered")
	expect_eq(int(RepairBay.condition(s, t["a"])["hp"]), full_hp - 4)
	var down := e.submit(s, c, {"type": "start_downtime", "seat": "gm", "params": {}})
	var note: Array = (down["events"] as Array).filter(func(x: Dictionary) -> bool: return x["type"] == "repairs_needed")
	expect(not note.is_empty() and str(note[0]["text"]).contains("10 hours"), "downtime says so, plainly")
	# Skip the repair: the next fight starts damaged.
	e.submit(s, c, {"type": "end_downtime", "seat": "gm", "params": {}})
	var gen2 := _mission(t)
	var m2: Unit = (gen2["state"] as GameState).unit("p1")
	expect_eq(m2.hp, full_hp - 4, "no repair, no fixed hull")
	expect_eq(m2.structure, m2.max_structure - 1)
	expect_eq(m2.repairs, 1, "Repairs spent stay spent")
	_finish(t, gen2)
	e.submit(s, c, {"type": "start_downtime", "seat": "gm", "params": {}})
	# The repair bay: ten hours.
	var before := TownLife.clock(s).duplicate()
	var r := e.submit(s, c, {"type": "full_repair", "seat": "p1", "params": {}})
	expect(r["ok"], str(r.get("reason", "")))
	expect(not RepairBay.needed(s), "everything whole")
	expect(TownLife.clock(s) != before, "the hours really pass")
	expect((r["events"] as Array).any(func(x: Dictionary) -> bool: return x["type"] == "regrouped"), "and the enemy has them too")
	expect(not e.submit(s, c, {"type": "full_repair", "seat": "p1", "params": {}})["ok"], "nothing left to fix: no spamming it")
	e.submit(s, c, {"type": "end_downtime", "seat": "gm", "params": {}})
	var gen3 := _mission(t)
	var m3: Unit = (gen3["state"] as GameState).unit("p1")
	expect_eq(m3.hp, m3.max_hp, "repaired")
	expect_eq(int((gen3["mission"] as Mission).flavor.get("regrouped", 0)), 1, "one more enemy at the next fight")


func test_a_wrecked_mech_waits_for_the_printer() -> void:
	var t := Setup.setup(701)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	var gen := _mission(t)
	(gen["state"] as GameState).unit("p1").destroyed = true
	_finish(t, gen)
	expect(RepairBay.wrecked(s, t["a"]))
	expect(not CampaignLoop.squad(c, s).any(func(x: Dictionary) -> bool: return str(x["pilot"]["id"]) == t["a"]), "no mech to fly until it's printed again")
	expect(not e.submit(s, c, {"type": "full_repair", "seat": "gm", "params": {}})["ok"] if s.phase == "mission" else true)
	s.flags["_caught"] = t["b"]
	expect(not e.submit(s, c, {"type": "full_repair", "seat": "gm", "params": {}})["ok"], "not with the alarm up")
	s.flags.erase("_caught")
	expect(e.submit(s, c, {"type": "full_repair", "seat": "gm", "params": {}})["ok"])
	expect(CampaignLoop.squad(c, s).any(func(x: Dictionary) -> bool: return str(x["pilot"]["id"]) == t["a"]), "printed again (Core p.82)")
