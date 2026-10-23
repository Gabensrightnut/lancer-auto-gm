extends TestCase
## Getting out of town and to the job (Journeys): mounting up at the gantry, the squad mounted,
## climbing out only somewhere safe, travel time on the clock, jobs at real sites, and wars.

const Setup := preload("res://tests/unit/test_story_dialogue.gd")


func _sub(t: Dictionary, type: String, params: Dictionary, seat: String = "gm") -> Dictionary:
	return t["engine"].submit(t["story"], t["campaign"], {"type": type, "seat": seat, "params": params})


func test_mount_up_and_the_squad_follows() -> void:
	var t := Setup.setup(820)
	var s: StoryState = t["story"]
	var r := _sub(t, "mount_up", {"pilot": t["a"]}, "p1")
	expect(r["ok"], str(r.get("reason", "")))
	expect(Journeys.mounted(s, t["a"]) and Journeys.mounted(s, t["b"]), "Bluebird climbs in, and their AI squadmate with them")
	var sm: Array = (r["events"] as Array).filter(func(x: Dictionary) -> bool: return x["type"] == "squad_mounted")
	expect(not sm.is_empty() and (sm[0]["seats"] as Array).has("p1") and (sm[0]["seats"] as Array).has("p2"), "the whole squad is in: onto the world map")
	expect(not _sub(t, "mount_up", {"pilot": t["a"]}, "p1")["ok"], "already in")
	expect(_sub(t, "dismount", {"pilot": t["a"]}, "p1")["ok"], "town is safe: climb out")
	s.hub = {}
	_sub(t, "mount_up", {"pilot": t["a"]}, "p1")
	expect(not _sub(t, "dismount", {"pilot": t["a"]}, "p1")["ok"], "not out in the open")
	s.flags["_safe_point"] = true
	expect(_sub(t, "dismount", {"pilot": t["a"]}, "p1")["ok"], "a cleared camp is safe")


func test_a_wrecked_mech_stays_on_the_gantry() -> void:
	var t := Setup.setup(821)
	var s: StoryState = t["story"]
	s.flags[RepairBay.KEY] = {t["b"]: {"wrecked": true}}
	expect(not _sub(t, "mount_up", {"pilot": t["b"]}, "gm")["ok"], "it has to be printed again first")
	var r := _sub(t, "mount_up", {"pilot": t["a"]}, "p1")
	expect(not Journeys.mounted(s, t["b"]), "Kettle can't follow without a mech")
	expect((r["events"] as Array).any(func(x: Dictionary) -> bool: return x["type"] == "squad_mounted"), "everyone with a mech is in")


func test_travel_time_moves_the_clock_and_the_food() -> void:
	var t := Setup.setup(822)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	_sub(t, "house_rule", {"id": "hr_survival", "on": true})
	_sub(t, "set_auto_eat", {"pilot": t["a"], "on": false}, "p1")
	var day := int(TownLife.clock(s)["day"])
	var period := TownLife.period(s)
	expect(not _sub(t, "travel_time", {"hours": 13, "group": ["p1"]}, "p1")["ok"], "the host passes travel time")
	var r := _sub(t, "travel_time", {"hours": 13, "group": ["p1", "p2"]})
	expect(r["ok"])
	expect(TownLife.period(s) != period or int(TownLife.clock(s)["day"]) != day, "the day moves on")
	expect(absf(float(s.flags.get("_clock_hours", 0.0)) - 1.0) < 0.01, "the odd hour is kept for next time")
	expect(Survival.bars(s, t["a"]).y < 100.0, "and you get thirsty on the road")


func test_jobs_are_somewhere_and_far_ones_take_a_ride() -> void:
	var t := Setup.setup(823)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	var modes := {}
	for h: Dictionary in s.hooks:
		expect(h.has("site") and h.has("travel"), "%s has a place and a way there" % h.get("title", ""))
		modes[str(h["travel"])] = true
	var seize := MissionHooks.make(s, c, "seize_ship", {})
	expect_eq(str(seize["travel"]), "ship", "boarding a ship: you fly there")
	var town := MissionHooks.make(s, c, "defend_town", {})
	if bool(town.get("in_town", false)):
		expect_eq(str(town["travel"]), "walk", "a fight in town: you walk")
	var far := MissionHooks.make(s, c, "escort_convoy", {})
	far["travel"] = "vehicle"
	far["travel_hours"] = 6
	far["travel_text"] = "A hired crawler carries the squad."
	var period := TownLife.period(s)
	var ev := Journeys.ride(s, c, far)
	expect(ev.any(func(x: Dictionary) -> bool: return x["type"] == "ride"), "too far to walk: a ride")
	expect(TownLife.period(s) != period, "six hours on the road")


func test_some_worlds_are_at_war() -> void:
	var t := Setup.setup(824)
	var s: StoryState = t["story"]
	var c: Campaign = t["campaign"]
	s.hub["conflict"] = {"id": "claim_war", "a": "Harrison Armory", "b": "the Albatross", "summary": "A claim war over the valley."}
	var w := Journeys.war(s, c)
	expect_eq(w.get("factions", []), ["Harrison Armory", "the Albatross"], "a claim war: ambushes on the roads")
	s.hub["conflict"] = {"id": "salvage_rush", "a": "x", "b": "y"}
	expect(Journeys.war(s, c).is_empty(), "a salvage rush isn't a war")
