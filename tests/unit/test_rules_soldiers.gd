extends TestCase
## Soldiers on the book's special classes (Core p.322-323): the Squad and the Human. The
## numbers come from whichever NPC source is loaded (the official local pack or our
## placeholders), so these tests check the rules, not the numbers.

const F = preload("res://tests/unit/test_rules_fixtures.gd")

static var _db: ContentDB


static func db() -> ContentDB:
	if _db == null:
		_db = ContentDB.new()
		_db.load_all()
	return _db


static func squad(s: GameState, id: String, kind: String, side: String, cell: Vector2i) -> Unit:
	var u := Soldiers.build(db(), id, kind, side, 1, s)
	u.cell = cell
	u.level = s.map.ground_height(cell)
	s.add_unit(u)
	return u


func test_a_squad_is_the_books_special_class() -> void:
	var s := F.state(GridLayout.Shape.SQUARE, 16, 16)
	var cls: Dictionary = NPCBuilder.source(db())["classes"]["npcc_squad"]
	var sq := squad(s, "sq", "rifle_squad", "enemies", Vector2i(3, 3))
	expect_eq(sq.size, 4.0, "Size 4 (1/2 individually)")
	expect_eq(sq.max_hp, int(cls["stats"]["hp"][0]))
	expect(sq.biological() and sq.heat_cap == 0 and sq.max_structure == 0, "Biological, no Heat Cap, never gains Structure")
	expect(not sq.on_foot(), "a squad follows its own traits, not the pilot-on-foot rules")
	expect_eq(sq.controller, "soldiers_enemies")
	expect(s.seats["soldiers_enemies"].get("ai_only", false), "the soldier seat is the AI's")
	expect_eq(Soldiers.men_left(sq), 10, "10 members")
	sq.hp = sq.max_hp / 2
	expect_eq(Soldiers.men_left(sq), 5)
	s.seats["p1"] = {"name": "P1", "side": "players"}
	var seen: Dictionary = ViewFilter.new().view_for(s, "p1")["units"]["sq"]
	expect_eq([seen.get("soldier"), seen.get("men_left")], ["rifle_squad", 5])
	expect(not seen.has("hp"), "stats stay hidden")
	var one := squad(s, "s1", "soldier", "players", Vector2i(12, 12))
	expect(one.size == 0.5 and one.on_foot() and one.biological(), "a Human: Size 1/2, on foot, Biological")
	var armored := squad(s, "g", "guard_squad", "players", Vector2i(10, 2))
	expect_eq(armored.armor, sq.armor + 1, "the Armored module")


func test_squad_traits_in_combat() -> void:
	var s := F.state(GridLayout.Shape.SQUARE, 16, 16)
	var e := RulesEngine.new()
	var m := F.mech(s, "m", "players", Vector2i(1, 1))
	var sq := squad(s, "sq", "rifle_squad", "enemies", Vector2i(6, 1))
	# Undersize: soft cover even in the open, never hard.
	expect_eq(Sight.unit_cover(s, m, sq)["cover"], "soft")
	F.begin(e, s, m)
	# Strength in Numbers: Resistance to a single shot's damage.
	F.load_dice(s, [15, 1, 4])  # d20, the soft cover's Difficulty die, the rifle's 1d6
	var hp := sq.hp
	var out := F.act(e, s, "skirmish", "m", {"weapon": "0:0", "target": "sq"})
	expect(F.ok(out), F.reason(out))
	expect_eq(sq.hp, hp - 2, "4 damage, halved")
	# Immune to Grapple and Stunned, can't be knocked back; Biological: no Invade.
	expect(not F.ok(F.act(e, s, "grapple", "m", {"target": "sq"})), "immune to Grapple")
	Combat.add_status(s, sq, "Stunned", "test")
	expect(not sq.has_status("Stunned"), "immune to Stunned")
	expect_eq(Attacks.knock_back(s, sq, m.cell, 2, m)[0]["type"], "knockback_blocked")
	expect(not Attacks.tech_target_check(s, m, sq, "invade").ok, "Biological: no Invade")
	expect(Attacks.tech_target_check(s, m, sq, "lock_on").ok, "Lock On still works")
	F.act(e, s, "end_turn", "m")
	s.turn_side = "enemies"
	F.act(e, s, "start_turn", "sq")
	expect(not F.ok(F.act(e, s, "lock_on", "sq", {"target": "m"})), "Biological NPCs take no tech actions")
	expect(not F.ok(F.act(e, s, "ram", "sq", {"target": "m"})), "a squad can't Ram")
	# Main Rifle: two attacks at a time while it has more than half its HP.
	var rifle: Dictionary = sq.loadout["weapons"].filter(func(w: Dictionary) -> bool: return w.get("id", "") == "npcf_squad_main_rifle")[0]
	expect_eq(Soldiers.attacks_with(sq, rifle), 2)
	m.cell = Vector2i(4, 1)
	F.load_dice(s, [10, 10])
	out = F.act(e, s, "skirmish", "sq", {"weapon": rifle["key"], "target": "m"})
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "attack_rolled").size(), 2, "two attacks")
	sq.hp = sq.max_hp / 2 - 1
	expect_eq(Soldiers.attacks_with(sq, rifle), 1, "one attack once it has lost more than half its HP")


func test_spread_out_lets_others_through_and_the_squad_overlap() -> void:
	var s := F.state(GridLayout.Shape.SQUARE, 16, 16)
	var e := RulesEngine.new()
	var m := F.mech(s, "m", "players", Vector2i(1, 6))
	var sq := squad(s, "sq", "rifle_squad", "players", Vector2i(5, 5))
	F.mech(s, "foe", "enemies", Vector2i(15, 15))
	F.begin(e, s, m)
	var inside: Vector2i = s.map.grid.footprint(sq.cell, sq.size)[0]
	for c in s.map.grid.footprint(sq.cell, sq.size):
		if s.map.grid.distance(m.cell, c) < s.map.grid.distance(m.cell, inside):
			inside = c
	var out := F.act(e, s, "move", "m", {"to": [inside.x, inside.y]})
	expect(F.ok(out), "a mech can stop inside a squad's spaces: " + F.reason(out))
	F.act(e, s, "end_turn", "m")
	s.turn_side = "players"
	F.act(e, s, "start_turn", "sq")
	# The squad moves like one of its members and may end overlapping the mech.
	out = F.act(e, s, "move", "sq", {"to": [sq.cell.x - 1, sq.cell.y]})
	expect(F.ok(out), "it overlaps the mech with plenty of free spaces left: " + F.reason(out))
	expect(Soldiers.spread_ok(s, sq, sq.cell, sq.level, sq.size), "at least 2 free spaces")


func test_a_human_fights_on_foot() -> void:
	var s := F.state(GridLayout.Shape.SQUARE, 12, 1)
	var e := RulesEngine.new()
	var m := F.mech(s, "m", "players", Vector2i(0, 0))
	var one := squad(s, "s1", "soldier", "enemies", Vector2i(2, 0))
	F.begin(e, s, m)
	var out := F.act(e, s, "move", "m", {"to": [3, 0]})
	expect(F.ok(out), "mechs move through people on foot (Core p.62): " + F.reason(out))
	expect(not m.has_status("Engaged"), "people on foot don't Engage mechs (Core p.74)")
	F.act(e, s, "end_turn", "m")
	s.turn_side = "enemies"
	F.act(e, s, "start_turn", "s1")
	var gun: String = one.loadout["weapons"][0]["key"]
	out = F.act(e, s, "skirmish", "s1", {"weapon": gun, "target": "m"})
	expect(not F.ok(out) and F.reason(out).contains("Fight"), "people on foot attack with Fight: " + F.reason(out))
	F.load_dice(s, [15, 1])
	out = F.act(e, s, "fight", "s1", {"weapon": gun, "target": "m"})
	expect(F.ok(out), F.reason(out))


func test_reload_a_loading_pilot_weapon() -> void:
	var s := F.state()
	var e := RulesEngine.new()
	var p := UnitFactory.build_pilot(db(), "p", {"name": "Pilot", "weapons": ["pg_heavy_signature", "pg_light_a_c"]}, "players", "gm")
	p.cell = Vector2i(1, 1)
	s.add_unit(p)
	F.mech(s, "foe", "enemies", Vector2i(8, 8))
	F.begin(e, s, p)
	var launcher: Dictionary = p.loadout["weapons"].filter(func(w: Dictionary) -> bool: return w.get("id", "") == "pg_heavy_signature")[0]
	var carbine: Dictionary = p.loadout["weapons"].filter(func(w: Dictionary) -> bool: return w.get("id", "") == "pg_light_a_c")[0]
	_refused(e, s, launcher["key"], "already loaded")
	_refused(e, s, carbine["key"], "Loading")
	Weapons.state_of(p, launcher)["loaded"] = false
	var out := F.act(e, s, "reload", "p", {"weapon": launcher["key"]})
	expect(F.ok(out), F.reason(out))
	expect(Weapons.state_of(p, launcher)["loaded"], "loaded again (Core p.74 Reload)")


func _refused(e: RulesEngine, s: GameState, key: String, why: String) -> void:
	var out := F.act(e, s, "reload", "p", {"weapon": key})
	expect(not F.ok(out) and F.reason(out).contains(why), F.reason(out))


func test_soldiers_act_on_their_own_with_their_job_and_the_objective() -> void:
	var s := F.state(GridLayout.Shape.SQUARE, 16, 16)
	squad(s, "sq", "rifle_squad", "players", Vector2i(2, 2))
	squad(s, "s1", "soldier", "players", Vector2i(2, 10))
	F.mech(s, "foe", "enemies", Vector2i(9, 4))
	var host := NetHost.new(s, RulesEngine.new())
	host.add_local_seat("soldiers_players")
	expect(host.is_ai_seat("soldiers_players"), "soldiers are always the AI's")
	var ai := TacticsAi.new()
	var types: Array = ai.plan_turn(AiKnowledge.for_side(s, ViewFilter.new(), "players"), "sq")["steps"].map(func(a: Dictionary) -> String: return a["type"])
	expect(not types.has("lock_on") and not types.has("scan") and not types.has("fight"), "a squad: NPC attacks, no tech: %s" % [types])
	types = ai.plan_turn(AiKnowledge.for_side(s, ViewFilter.new(), "players"), "s1")["steps"].map(func(a: Dictionary) -> String: return a["type"])
	expect(not types.has("skirmish") and not types.has("lock_on"), "a Human fights on foot: %s" % [types])
	var p := TacticsAi.priority(ai.priorities, "defender", "sitrep_holdout")
	expect(float(p["zone"]) > 1.5, "holding the point beats chasing kills")
	expect_eq(p["intent"], "holding the zone")
