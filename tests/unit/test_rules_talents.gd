extends TestCase
## Pilot talents, rank by rank (TalentRules, gear_effects.json).

const F = preload("res://tests/unit/test_rules_fixtures.gd")

static var _db: ContentDB

var s: GameState
var e: RulesEngine
var a: Unit
var t: Unit


func db() -> ContentDB:
	if _db == null:
		_db = ContentDB.new()
		_db.load_all()
	return _db


func _setup(talents: Dictionary, mounts: Array = [{"weapons": ["mw_assault_rifle"]}], t_cell: Vector2i = Vector2i(4, 0), systems: Array = []) -> void:
	s = F.state()
	e = RulesEngine.new()
	a = UnitFactory.build_mech(db(), "a", "mf_standard_pattern_i_everest", {"mounts": mounts, "systems": systems}, {"ll": 6, "talents": talents})
	a.side = "players"
	s.add_unit(a)
	t = F.mech(s, "t", "enemies", t_cell)
	t.max_hp = 40
	t.hp = 40
	F.begin(e, s, a)


func _acc(attacker: String, key: String, target: String) -> int:
	return int(RulesQueries.attack_preview(s, attacker, key, target)["accuracy"])


func _next_turn(u: Unit) -> void:
	F.act(e, s, "end_turn", s.active_unit)
	s.acted = PackedStringArray()
	s.round_number += 1
	s.turn_side = u.side
	F.act(e, s, "start_turn", u.id)


func test_brawler_and_duelist_accuracy() -> void:
	_setup({"t_brawler": 2, "t_duelist": 1}, [{"weapons": ["mw_tactical_melee_weapon"]}], Vector2i(1, 0))
	expect_eq(_acc("a", "0:0", "t"), 1, "Duelist: first Main Melee attack on your turn")
	a.counters["grapple"] = {"with": "t", "attacker": true}
	expect_eq(_acc("a", "0:0", "t"), 2, "Brawler: +1 against a target you're grappling")
	a.counters.erase("grapple")
	F.load_dice(s, [1, 1])
	F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect_eq(_acc("a", "0:0", "t"), 0, "only the first one")
	expect_eq(TalentRules.improvised(a, AttackActions.IMPROVISED)["damage"][0]["val"], "2d6+2", "Sledgehammer")


func test_brutal() -> void:
	_setup({"t_brutal": 3})
	F.load_dice(s, [2, 1])
	F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect_eq(_acc("a", "0:0", "t"), 1, "Relentless: +1 after a miss")
	_next_turn(a)
	F.load_dice(s, [20])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect_eq(F.events_of(out, "damage_rolled")[0]["roll"]["total"], 6, "Predator: a natural 20 crit deals maximum damage")
	expect_eq(_acc("a", "0:0", "t"), 0, "a hit resets Relentless")


func test_combined_arms_and_vanguard() -> void:
	_setup({"t_combined_arms": 2, "t_vanguard": 2}, [{"weapons": ["mw_shotgun"]}], Vector2i(3, 0))
	var foe := F.mech(s, "foe", "enemies", Vector2i(1, 0))
	Combat.refresh_engagement(s)
	expect(a.has_status("Engaged"))
	var p := RulesQueries.attack_preview(s, "a", "0:0", "t")
	expect_eq(p["difficulty"], 0, "CQB-Trained: no Difficulty from Engaged")
	expect_eq(p["accuracy"], 1, "Handshake Etiquette: CQB within range 3")
	expect_eq(RulesQueries.attack_preview(s, "foe", "0:0", "a")["cover"]["cover"], "soft", "Shield of Blades: soft cover while Engaged")


func test_nuclear_cavalier_in_the_danger_zone() -> void:
	_setup({"t_nuclear_cavalier": 2})
	a.heat = 3
	a.statuses["Danger Zone"] = {"source": "heat"}
	F.load_dice(s, [15, 3, 4])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect_eq(F.events_of(out, "damage_rolled")[0]["damage_type"], "Energy", "Fusion Hemorrhage: energy")
	expect_eq(F.events_of(out, "bonus_damage")[0]["amount"], 4, "+1d6 energy bonus")
	expect_eq(t.heat, 2, "Aggressive Heat Bleed: +2 heat")


func test_skirmisher_chaff_and_weave() -> void:
	_setup({"t_skirmisher": 3})
	_next_turn(t)
	_next_turn(a)
	expect_eq(RulesQueries.attack_preview(s, "t", "0:0", "a")["cover"]["cover"], "soft", "chaff from the start of its turn")
	F.load_dice(s, [1])
	F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect_eq(RulesQueries.attack_preview(s, "t", "0:0", "a")["cover"]["cover"], "none", "lost when it attacks")
	var ev := Attacks.attack(s, t, Weapons.find(t, "0:0"), a, {"reaction": true})
	expect_eq(F.events_of({"events": ev}, "attack_rolled")[0]["result"], "miss", "Weave: the first reaction attack misses")


func test_juggernaut_hunter_spotter_hacker() -> void:
	_setup({"t_juggernaut": 1, "t_hunter": 2, "t_hacker": 1}, [{}, {"weapons": ["mw_tactical_knife"]}], Vector2i(4, 0))
	expect_eq(Weapons.tag_value(Weapons.find(a, "1:0"), "tg_thrown"), 5, "Knife Juggler: Thrown 5")
	F.act(e, s, "boost", "a", {"to": [3, 0]})
	expect(a.counters.get("ram_momentum", false))
	var out := F.act(e, s, "ram", "a", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	_next_turn(a)
	t.cell = Vector2i(5, 0)
	t.statuses["Lock On"] = {"source": "a"}
	F.load_dice(s, [19, 1])
	F.act(e, s, "invade", "a", {"target": "t"})
	expect_eq(t.heat, 4, "SNOW_CRASH: 2 heat more when consuming Lock On")


func test_grease_monkey_and_drone_commander() -> void:
	_setup({"t_grease_monkey": 2, "t_drone_commander": 1}, [{"weapons": ["mw_assault_rifle"]}], Vector2i(4, 0), ["ms_turret_drones"])
	a.statuses["Impaired"] = {"source": "t"}
	a.statuses["Lock On"] = {"source": "t"}
	F.act(e, s, "stabilize", "a", {"main": "cool", "extra": "reload"})
	expect(not a.has_status("Impaired") and not a.has_status("Lock On"), "Machine Bond clears conditions others caused")
	_next_turn(a)
	var key := ""
	for x: Dictionary in Abilities.all(a):
		if x["name"] == "Deploy Turret Drone":
			key = x["key"]
	var out := F.act(e, s, "activate", "a", {"ability": key, "to": [2, 2]})
	expect_eq(F.events_of(out, "deployed")[0]["object"]["hp"], 10, "Shepherd: drones gain +5 HP")
