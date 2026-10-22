extends TestCase
## The pirate career, "Dead Reckoning" (CampaignScript): three starts decided in play, splits
## at the mutiny and the captaincy, the aggrieved pilot who drives the mutiny, clones in Hask's
## vat, loot by house rule, and every ending reachable.

const MissionTest := preload("res://tests/unit/test_gm_mission.gd")
const Picks := preload("res://tests/unit/test_story_sector.gd")


static func fresh(seed_value: int, two_humans: bool = false) -> Dictionary:
	var c := Campaign.create("Dead Reckoning")
	c.id = "c_dr_%d" % seed_value
	var a := c.new_pilot("Ama Okafor", "Bluebird")
	var b := c.new_pilot("Rin Sato", "Kettle")
	a["skills"] = {"sk_charm": 2, "sk_hack_or_fix": 3}
	b["skills"] = {"sk_threaten": 2, "sk_assault": 2}
	var s := StoryState.new(seed_value)
	s.flags = c.story_flags
	var e := StoryEngine.new(MissionTest.db())
	e.submit(s, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p1", "pilot": a["id"]}})
	e.submit(s, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p2", "pilot": b["id"], "ai": not two_humans, "persona": "bold"}})
	var ev := CampaignScript.begin(s, c, e, "dead_reckoning")
	return {"campaign": c, "story": s, "engine": e, "a": a["id"], "b": b["id"], "events": ev}


static func chapter_id(t: Dictionary) -> String:
	return str(CampaignScript.state(t["story"]).get("chapter", ""))


## One chapter: its mission, the debrief, the conversation after it (reply `pick`, or the
## reply whose text contains `want`), any squad decision (p1 accepts), the end of downtime.
static func play_chapter(t: Dictionary, pick: int, won: bool = true, want: String = "", dead: Array = []) -> void:
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	var hook: Dictionary = {}
	for h: Dictionary in s.hooks:
		if h.has("chapter"):
			hook = h
	if hook.is_empty():
		return
	t["last_hook"] = hook
	e.submit(s, c, {"type": "choose_hook", "seat": "gm", "params": {"hook": hook["id"]}})
	Dialogue.close(s)
	e.submit(s, c, {"type": "confirm_reserves", "seat": "gm", "params": {}})
	var gen := CampaignLoop.build_mission(c, s, MissionTest.db())
	var mission: Mission = gen["mission"]
	t["last_mission"] = mission
	mission.outcome = Mission.PLAYERS if won else Mission.ENEMIES
	# Pilots killed in the fight.
	for u: Unit in (gen["state"] as GameState).units.values():
		if u.kind == Unit.KIND_PILOT and dead.has(s.pilot_of_seat(u.controller)):
			u.destroyed = true
	t["finish"] = CampaignLoop.finish_mission(c, s, e, gen["state"], mission, [])
	Dialogue.close(s)
	if s.phase == "ending":
		return
	e.submit(s, c, {"type": "level_up", "seat": "gm", "params": {}})
	if s.phase == "ending":
		return
	for pid: String in s.pending_picks.keys():
		e.submit(s, c, {"type": "level_picks", "seat": "gm", "params": Picks.pick_for(c.pilots[pid])})
	var down := e.submit(s, c, {"type": "start_downtime", "seat": "gm", "params": {}})
	t["downtime_events"] = down.get("events", [])
	var guard := 0
	t["offered"] = []
	while Dialogue.is_open(s) and guard < 20:
		guard += 1
		var o := Dialogue.offered(s)
		if o.is_empty():
			e.submit(s, c, {"type": "dialogue_next", "seat": "p1", "params": {}})
		else:
			var plain: Array = o.filter(func(x: Dictionary) -> bool: return not bool(x.get("extra", false)))
			(t["offered"] as Array).append_array(plain.map(func(x: Dictionary) -> String: return str(x.get("text", ""))))
			var choice: Dictionary = plain[mini(pick, plain.size() - 1)]
			if want != "":
				for x: Dictionary in plain:
					if str(x.get("text", "")).contains(want):
						choice = x
			e.submit(s, c, {"type": "dialogue_choose", "seat": "p1", "params": {"choice": choice["id"]}})
	Dialogue.close(s)
	if not Decisions.current(s).is_empty():
		for h: String in Decisions.humans(s):
			e.submit(s, c, {"type": "decide", "seat": h, "params": {"accept": true}})
	while not s.all_choices().is_empty():
		var pc: Dictionary = s.all_choices()[0]
		e.submit(s, c, {"type": "downtime_choose", "seat": "gm", "params": {"pilot": pc["pilot"], "picks": (pc["options"] as Array).slice(0, int(pc["count"])).map(func(x: Dictionary) -> String: return x["id"])}})
	e.submit(s, c, {"type": "end_downtime", "seat": "gm", "params": {}})
	Dialogue.close(s)


static func run(seed_value: int, picks: Array, final_won: bool = true) -> Dictionary:
	var t := fresh(seed_value)
	var s: StoryState = t["story"]
	var i := 0
	var site := ""
	while s.phase != "ending" and i < 20:
		var ch := CampaignScript.chapter(s, t["campaign"])
		var final := bool(ch.get("final", false))
		if final:
			site = chapter_id(t)
		play_chapter(t, int(picks[i % picks.size()]), final_won if final else true)
		i += 1
	var st := CampaignScript.state(s)
	var flav: Dictionary = (t["last_mission"] as Mission).flavor if t.has("last_mission") else {}
	return {"t": t, "ending": str(st.get("ending", "")), "chain": (st.get("branches", {}) as Dictionary).duplicate(), "site": site,
		"allies": flav.get("allies", []), "foe": str(flav.get("commander", {}).get("name", "")), "chapters": i, "line": str(st.get("line", ""))}


func test_it_starts_aboard_the_cadence() -> void:
	var t := fresh(500)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	expect(CampaignScript.active(c))
	expect_eq(str(s.hub["name"]), "The Saint Cadence")
	expect(s.hub["spots"].any(func(sp: Dictionary) -> bool: return str(sp["kind"]) == "office" and str(sp["name"]) == "the bridge"), "the office is the bridge")
	expect_eq(TownLife.room_name(s, "office", "back"), "the captain's quarters")
	expect((s.hub["npcs"] as Array).has("cs_kell") and (s.hub["npcs"] as Array).has("cs_tamsin"), "Captain Kell and the bosun are aboard")
	expect(not (s.hub["npcs"] as Array).has("cs_hask"), "Hask hasn't come yet")
	expect(Cloning.available(s, c).has("flash"), "the medical bay has a flash vat")
	var jobs: Array = s.hooks.filter(func(h: Dictionary) -> bool: return h.has("chapter"))
	expect_eq(str(jobs[0]["title"]), "Cascade")
	expect_eq(str(jobs[0].get("boarding", {}).get("map", "")), "own_ship", "the first fight is aboard your own ship")


func test_three_starts_come_from_play() -> void:
	var starts := {}
	for path: Array in [[0, 0, 0], [1, 0, 1], [0, 0, 1]]:
		var t := fresh(510 + starts.size())
		for p: int in path:
			play_chapter(t, p)
		starts[str(CampaignScript.state(t["story"])["branches"].get("b3", ""))] = true
		expect_eq(chapter_id(t), "c4_raid")
		expect((t["story"].hub["npcs"] as Array).has("cs_hask"), "Hask is aboard now")
		expect(not (t["story"].hub["npcs"] as Array).has("cs_kell"), "and Kell is gone")
	expect_eq(starts.keys().size(), 3, "pirates, stranded with the officers, alone: %s" % [starts.keys()])


func test_every_ending_is_reachable() -> void:
	# Chapters: p1 p2 p3 c4 c5 c6 c7 c8 c9 c10 c11 c12 c13 c14 final.
	var want := {
		"hasks_expendables": [0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 1, 0, 0, 0, 0],
		"brought_to_trial": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
		"the_monster": [0, 0, 0, 2, 1, 0, 0, 2, 1, 1, 0, 0, 0, 0, 0],
		"go_legit": [0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
		"meridians_children": [0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 1, 0, 0, 0],
		"free_fleet": [0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0],
		"legend_of_the_fringe": [0, 0, 0, 0, 1, 0, 2, 1, 1, 0, 0, 0, 1, 0, 0],
		"retire_rich": [0, 0, 0, 1, 0, 1, 1, 1, 1, 2, 0, 0, 1, 0, 0],
	}
	var sites := {}
	var foes := {}
	var chains := {}
	var i := 0
	for id: String in want:
		var r := run(520 + i, want[id])
		i += 1
		expect_eq(r["ending"], id, "%s: %s (line %s)" % [id, r["chain"], r["line"]])
		sites[r["site"]] = true
		foes[r["foe"]] = true
		chains[JSON.stringify(r["chain"])] = true
	var lost := run(540, [1, 1, 1, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0], false)
	expect_eq(lost["ending"], "lost_with_the_cadence", "losing the last fight")
	print("        dead reckoning: sites %s, foes %s, %d chains" % [sites.keys(), foes.keys(), chains.size()])
	expect(sites.size() == 3, "three final battles: %s" % [sites.keys()])
	expect(foes.size() >= 3, "against different people: %s" % [foes.keys()])


func test_the_mutiny_can_split_the_squad() -> void:
	var t := fresh(550, true)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	# Play the first mission, then walk the bridge conversation by hand.
	var hook: Dictionary = s.hooks.filter(func(h: Dictionary) -> bool: return h.has("chapter"))[0]
	e.submit(s, c, {"type": "choose_hook", "seat": "gm", "params": {"hook": hook["id"]}})
	Dialogue.close(s)
	e.submit(s, c, {"type": "confirm_reserves", "seat": "gm", "params": {}})
	var gen := CampaignLoop.build_mission(c, s, MissionTest.db())
	(gen["mission"] as Mission).outcome = Mission.PLAYERS
	CampaignLoop.finish_mission(c, s, e, gen["state"], gen["mission"], [])
	Dialogue.close(s)
	e.submit(s, c, {"type": "level_up", "seat": "gm", "params": {}})
	for pid: String in s.pending_picks.keys():
		e.submit(s, c, {"type": "level_picks", "seat": "gm", "params": Picks.pick_for(c.pilots[pid])})
	e.submit(s, c, {"type": "start_downtime", "seat": "gm", "params": {}})
	var guard := 0
	while Dialogue.is_open(s) and Dialogue.offered(s).is_empty() and guard < 10:
		guard += 1
		e.submit(s, c, {"type": "dialogue_next", "seat": "p1", "params": {}})
	var mut: Array = Dialogue.offered(s).filter(func(x: Dictionary) -> bool: return str(x["id"]) == "mutiny")
	expect(not mut.is_empty(), "back the mutineers, in Bluebird's own words")
	e.submit(s, c, {"type": "dialogue_choose", "seat": "p1", "params": {"choice": "mutiny"}})
	Dialogue.close(s)
	expect_eq(str(Decisions.current(s).get("id", "")), "mutiny", "the other player decides too")
	expect(not e.submit(s, c, {"type": "end_downtime", "seat": "gm", "params": {}})["ok"], "the squad has to settle it first")
	var r := e.submit(s, c, {"type": "decide", "seat": "p2", "params": {"accept": false}})
	var split: Array = (r["events"] as Array).filter(func(x: Dictionary) -> bool: return x["type"] == "party_split")
	expect(not split.is_empty(), "Kettle stands with the captain: it comes to a fight")
	expect_eq(str(split[0]["fight"].get("map", "")), "own_ship", "fought out aboard the Cadence")
	expect((split[0]["sides"]["accept"] as Array).has("p1") and (split[0]["sides"]["decline"] as Array).has("p2"))
	e.submit(s, c, {"type": "split_resolved", "seat": "gm", "params": {"winner": "decline"}})
	expect(bool(s.flags.get("dr_officers", false)) and not s.flags.has("dr_mutineers"), "Kettle won: the lance stood with Kell")
	e.submit(s, c, {"type": "end_downtime", "seat": "gm", "params": {}})
	expect_eq(str(CampaignScript.state(s)["branches"]["b1"]), "officers")


func test_the_pilot_on_short_rations_leads_the_mutiny() -> void:
	var t := fresh(560)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	e.submit(s, c, {"type": "house_rule", "seat": "gm", "params": {"id": "hr_survival", "on": true}})
	e.submit(s, c, {"type": "house_rule", "seat": "gm", "params": {"id": "hr_printers", "on": true}})
	for p: int in [0, 0, 0, 1, 1, 0, 2, 1, 1, 0]:
		play_chapter(t, p)
	expect_eq(chapter_id(t), "c11_factions")
	# Kettle's mech was wrecked and never reprinted: short rations ever since.
	s.flags[Economy.WRECKED] = [t["b"]]
	s.flags[Economy.SURVIVAL]["rations"] = 30
	Economy.eat(s, c, 2)
	Economy.eat(s, c, 2)
	expect_eq(Agendas.anyone(s, "grievance"), t["b"], "Kettle has a grudge")
	expect(CampaignScript.fill(s, c, "{grudge_line}", CampaignScript.chapter(s, c)).contains("Kettle"), "the crew knows Kettle has had enough")
	play_chapter(t, 0, true, "I'll lead it")
	expect((t["offered"] as Array).any(func(x: String) -> bool: return x.contains("I'll lead it")), "Kettle can say it: they're the one pushing")
	expect(bool(s.flags.get("dr_driver", false)), "and they drive the mutiny")
	expect_eq(str(CampaignScript.state(s)["branches"]["b11"]), "driver")
	expect(CampaignScript.fill(s, c, "{cap_line}", CampaignScript.script(c)["chapters"]["c13_captaincy"]).contains("Kettle"), "the captaincy chapter starts with Kettle moving on the bridge")


func test_a_clone_wakes_in_hasks_vat() -> void:
	var t := fresh(570)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	for p: int in [0, 0, 0]:
		play_chapter(t, p)
	expect_eq(chapter_id(t), "c4_raid")
	var r := e.submit(s, c, {"type": "store_template", "seat": "gm", "params": {"pilot": t["a"], "kind": "flash"}})
	expect(r["ok"], str(r.get("reason", "")))
	expect(int(s.flags.get("_bounty", 0)) > 0, "flash cloning is unlawful: it adds to the bounty")
	play_chapter(t, 0, true, "", [t["a"]])
	expect(s.dead.has(t["a"]), "Bluebird died boarding the Brightwater")
	for i in range(3):
		Cloning.tick(s)
	s.phase = "downtime"
	r = e.submit(s, c, {"type": "wake_clone", "seat": "gm", "params": {"pilot": t["a"]}})
	expect(r["ok"], str(r.get("reason", "")))
	var ev: Array = r["events"]
	expect(ev.any(func(x: Dictionary) -> bool: return x["type"] == "clone_woke"))
	expect(ev.any(func(x: Dictionary) -> bool: return x["type"] == "clone_beat" and str(x["text"]).contains("Bluebird")), "the crew has something to say about it")
	expect(ev.any(func(x: Dictionary) -> bool: return x["type"] == "clone_quirk"), "flash clones always come back with a quirk (Core p.83)")
	expect(bool(s.flags.get("dr_cloned", false)))


func test_raids_pay_by_house_rule() -> void:
	# By the book: the haul is a reserve.
	var t := fresh(580)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	for p: int in [0, 0, 0, 0]:
		play_chapter(t, p)
	expect(s.reserves.values().any(func(list: Array) -> bool: return list.any(func(x: Dictionary) -> bool: return str(x["id"]) == "reserve_supplies" and str(x["note"]).contains("Brightwater"))),
		"the Brightwater's cargo becomes Supplies (Core p.48)")
	# Wallet on: it sells.
	var w := fresh(581)
	w["engine"].submit(w["story"], w["campaign"], {"type": "house_rule", "seat": "gm", "params": {"id": "hr_wallet", "on": true}})
	for p: int in [0, 0, 0, 0]:
		play_chapter(w, p)
	expect(int(Economy.wallet(w["story"]).get("salvage", 0)) >= 300, "the cargo is in the hold, to sell")
	# Own ship on (no wallet): loot for the ship.
	var o := fresh(582)
	var os: StoryState = o["story"]
	var oc: Campaign = o["campaign"]
	var oe: StoryEngine = o["engine"]
	expect(not oe.submit(os, oc, {"type": "buy_upgrade", "seat": "gm", "params": {"slot": "cargo"}})["ok"], "no ship of your own without the house rule")
	oe.submit(os, oc, {"type": "house_rule", "seat": "gm", "params": {"id": "hr_own_ship", "on": true}})
	for p: int in [0, 0, 0, 0]:
		play_chapter(o, p)
	expect_eq(int(Plunder.ship(os)["loot"]), 300)
	var r := oe.submit(os, oc, {"type": "buy_upgrade", "seat": "gm", "params": {"slot": "cargo"}})
	expect(r["ok"], str(r.get("reason", "")))
	expect_eq(Plunder.level(os, oc, "cargo"), 1)
	expect(not oe.submit(os, oc, {"type": "buy_upgrade", "seat": "gm", "params": {"slot": "printer"}})["ok"], "can't afford the printer yet")


func test_the_holds_love_the_lance_and_hask_keeps_the_peace() -> void:
	var t := fresh(590)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var e: StoryEngine = t["engine"]
	for p: int in [0, 0, 0]:
		play_chapter(t, p)
	expect((s.hub["npcs"] as Array).has("cs_siddiqui") and (s.hub["npcs"] as Array).has("cs_wen"), "Hask's people live aboard now")
	expect(s.hooks.any(func(h: Dictionary) -> bool: return h.has("ship_job")), "work for the holds on the board, besides the raid")
	# Everyone works: one shift per pilot between jobs.
	var r := e.submit(s, c, {"type": "ship_work", "seat": "gm", "params": {"job": "repairs", "pilot": t["a"]}})
	expect(r["ok"], str(r.get("reason", "")))
	expect((r["events"] as Array).any(func(x: Dictionary) -> bool: return x["type"] == "narrative_check"), "a skill check (Core p.45)")
	expect(not e.submit(s, c, {"type": "ship_work", "seat": "gm", "params": {"job": "markets", "pilot": t["a"]}})["ok"], "one shift each")
	# The lance gets famous; Hask cuts it down to size, and the holds resent him for it.
	var before := ShipLife.unrest(s)
	var ev := ShipLife.add_renown(s, c, 5, "test")
	expect(ev.any(func(x: Dictionary) -> bool: return x["type"] == "captain_quells"), "Hask keeps the peace")
	expect(ShipLife.unrest(s) > before, "and the holds don't like it")
	expect(s.get_standing("The people of the Cadence") >= 1, "renown shows as standing with the people aboard")
	ShipLife.add_renown(s, c, 3, "test")
	expect(ShipLife.unrest(s) >= 2)
	expect(StoryConditions.check({"unrest": 2}, s, c, {}))
	# Away from the ship there's no ship's work.
	for p: int in [0, 0]:
		play_chapter(t, p)
	expect_eq(chapter_id(t), "c6_gallowglass")
	expect(not e.submit(s, c, {"type": "ship_work", "seat": "gm", "params": {"job": "repairs", "pilot": t["b"]}})["ok"], "not aboard")


func test_the_holds_can_drive_the_mutiny() -> void:
	var t := fresh(595)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	for p: int in [0, 0, 0, 0, 1, 0, 2, 1, 1, 0]:
		play_chapter(t, p)
	expect_eq(chapter_id(t), "c11_factions")
	(ShipLife.state(s))["unrest"] = 2
	play_chapter(t, 0, true, "They want us")
	expect((t["offered"] as Array).any(func(x: String) -> bool: return x.contains("They want us")), "with the holds angry, the lance can say so")
	expect_eq(str(CampaignScript.state(s)["branches"]["b11"]), "the_holds")
	expect(CampaignScript.fill(s, c, "{cap_line}", CampaignScript.script(c)["chapters"]["c13_captaincy"]).contains("Siddiqui"), "the families move on the bridge with you")
