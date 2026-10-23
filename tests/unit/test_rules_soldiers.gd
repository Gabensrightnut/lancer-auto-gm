extends TestCase
## Soldiers (Soldiers, data/game/soldiers.json): squads and single humans on foot, under the
## book's rules for unmounted characters (Core p.74), played only by their own AI.

const F = preload("res://tests/unit/test_rules_fixtures.gd")

static var _db: ContentDB


static func db() -> ContentDB:
	if _db == null:
		_db = ContentDB.new()
		_db.load_all()
	return _db


func test_a_squad_is_ten_people_sharing_one_hp_pool() -> void:
	var s := F.state()
	var sq := Soldiers.build(db(), "sq", "rifle_squad", "enemies", 2, s)
	expect(sq != null and sq.on_foot(), "a squad is on foot")
	expect_eq([sq.kind, sq.size, sq.max_hp, sq.grit, sq.heat_cap], [Unit.KIND_NPC, 1.0, 10, 2, 0])
	expect_eq(sq.controller, "soldiers_enemies")
	expect(s.seats["soldiers_enemies"].get("ai_only", false), "the soldier seat is the AI's")
	expect(sq.loadout["weapons"].any(func(w: Dictionary) -> bool: return w.get("id", "") == "pg_medium_signature"), "armed with pilot weapons")
	sq.cell = Vector2i(3, 3)
	s.add_unit(sq)
	expect_eq(Soldiers.men_left(sq), 10)
	sq.hp = 4
	expect_eq(Soldiers.men_left(sq), 4, "men left = ceil(hp / max_hp * 10), for the look only")
	sq.hp = 1
	expect_eq(Soldiers.men_left(sq), 1)
	# Everyone can see what a soldier unit is and how many are left (not its stats).
	s.seats["p1"] = {"name": "P1", "side": "players"}
	sq.hp = 4
	var seen: Dictionary = ViewFilter.new().view_for(s, "p1")["units"]["sq"]
	expect_eq([seen.get("soldier"), seen.get("men_left")], ["rifle_squad", 4])
	expect(not seen.has("hp"), "stats stay hidden")
	var one := Soldiers.build(db(), "s1", "soldier", "players", 1, s)
	expect_eq([one.size, one.loadout["form"], one._soldier_fields().has("men_left")], [0.5, "human", false])


func test_soldiers_follow_the_rules_for_people_on_foot() -> void:
	var s := F.state(GridLayout.Shape.SQUARE, 12, 1)
	var e := RulesEngine.new()
	var m := F.mech(s, "m", "players", Vector2i(0, 0))
	var sq := Soldiers.build(db(), "sq", "rifle_squad", "enemies", 1, s)
	sq.cell = Vector2i(2, 0)
	s.add_unit(sq)
	F.begin(e, s, m)
	# Mechs move through people on foot, and people on foot don't Engage mechs (Core p.74).
	var out := F.act(e, s, "move", "m", {"to": [3, 0]})
	expect(F.ok(out), F.reason(out))
	expect(not m.has_status("Engaged"), "the squad doesn't Engage the mech")
	expect(not Attacks.tech_target_check(s, m, sq).ok and Attacks.tech_target_check(s, m, sq).reason.contains("BIOLOGICAL"), "immune to tech")
	F.act(e, s, "end_turn", "m")
	s.turn_side = "enemies"
	F.act(e, s, "start_turn", "sq")
	var gun: String = sq.loadout["weapons"].filter(func(w: Dictionary) -> bool: return w.get("id", "") == "pg_medium_signature")[0]["key"]
	out = F.act(e, s, "skirmish", "sq", {"weapon": gun, "target": "m"})
	expect(not F.ok(out) and F.reason(out).contains("Fight"), "people on foot attack with Fight: " + F.reason(out))
	out = F.act(e, s, "mount", "sq", {"mech": "m"})
	expect(not F.ok(out), "soldiers don't climb into mechs")
	F.load_dice(s, [12, 1])  # the d20, then the Difficulty die for being Engaged by the mech
	out = F.act(e, s, "fight", "sq", {"weapon": gun, "target": "m"})
	expect(F.ok(out), F.reason(out))
	expect_eq(m.hp, 8, "the rifle's 2 kinetic")
	var roll: Dictionary = F.events_of(out, "attack_rolled")[0]["check"]
	expect_eq(int(roll.get("bonus", -1)), 1, "Grit to the attack roll")
	# Biological: heat becomes energy damage.
	Combat.apply_heat(s, sq, 3, "test")
	expect_eq([sq.heat, sq.hp], [0, 7])


func test_reload_a_loading_pilot_weapon() -> void:
	var s := F.state()
	var e := RulesEngine.new()
	var mt := Soldiers.build(db(), "mt", "missile_team", "players", 1, s)
	mt.cell = Vector2i(1, 1)
	s.add_unit(mt)
	F.mech(s, "foe", "enemies", Vector2i(8, 8))
	F.begin(e, s, mt)
	var launcher: Dictionary = mt.loadout["weapons"].filter(func(w: Dictionary) -> bool: return w.get("id", "") == "pg_heavy_signature")[0]
	expect_eq(launcher["damage"][0]["type"], "Explosive", "the missile team's launcher")
	out_refused(e, s, launcher["key"], "already loaded")
	var carbine: Dictionary = mt.loadout["weapons"].filter(func(w: Dictionary) -> bool: return w.get("id", "") == "pg_light_a_c")[0]
	out_refused(e, s, carbine["key"], "Loading")
	Weapons.state_of(mt, launcher)["loaded"] = false
	var out := F.act(e, s, "reload", "mt", {"weapon": launcher["key"]})
	expect(F.ok(out), F.reason(out))
	expect(Weapons.state_of(mt, launcher)["loaded"], "loaded again")


func out_refused(e: RulesEngine, s: GameState, key: String, why: String) -> void:
	var out := F.act(e, s, "reload", "mt", {"weapon": key})
	expect(not F.ok(out) and F.reason(out).contains(why), F.reason(out))


func test_soldiers_act_on_their_own_with_their_job_and_the_objective() -> void:
	var s := F.state()
	var sq := Soldiers.build(db(), "sq", "rifle_squad", "players", 1, s)
	sq.cell = Vector2i(2, 2)
	s.add_unit(sq)
	F.mech(s, "foe", "enemies", Vector2i(5, 2))
	# Nobody takes the soldier seat, not even someone at this screen.
	var host := NetHost.new(s, RulesEngine.new())
	host.add_local_seat("soldiers_players")
	expect(host.is_ai_seat("soldiers_players"), "soldiers are always the AI's")
	var ai := TacticsAi.new()
	var plan := ai.plan_turn(AiKnowledge.for_side(s, ViewFilter.new(), "players"), "sq")
	var types: Array = plan["steps"].map(func(a: Dictionary) -> String: return a["type"])
	expect(types.has("fight") and not types.has("skirmish") and not types.has("lock_on"), "on foot: %s" % [types])
	# Role x sitrep: a defender in a Holdout holds the zone, with a plain intent.
	var p := TacticsAi.priority(ai.priorities, "defender", "sitrep_holdout")
	expect(float(p["zone"]) > 1.5, "holding the point beats chasing kills")
	expect_eq(p["intent"], "holding the zone")
	expect_eq(TacticsAi.priority(ai.priorities, "support", "")["intent"], "staying hidden and keeping its people alive")


func test_medics_patch_people_on_foot() -> void:
	var s := F.state()
	var e := RulesEngine.new()
	var medic := Soldiers.build(db(), "md", "medic_team", "players", 1, s)
	medic.cell = Vector2i(2, 2)
	s.add_unit(medic)
	var sq := Soldiers.build(db(), "sq", "rifle_squad", "players", 1, s)
	sq.cell = Vector2i(3, 2)
	sq.hp = 3
	s.add_unit(sq)
	F.mech(s, "foe", "enemies", Vector2i(10, 10))
	var plan := TacticsAi.new().plan_turn(AiKnowledge.for_side(s, ViewFilter.new(), "players"), "md")
	var patch: Array = plan["steps"].filter(func(a: Dictionary) -> bool: return a["type"] == "activate")
	expect(not patch.is_empty() and patch[0]["params"]["target"] == "sq", "the medics go to the hurt squad: %s" % plan["log"])
	F.begin(e, s, medic)
	var out := e.submit(s, patch[0] if not patch.is_empty() else {})
	expect(F.ok(out), F.reason(out))
	expect_eq(sq.hp, 8, "half its maximum HP back")
