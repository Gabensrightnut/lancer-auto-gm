extends TestCase
## Gear that used to be left to the table: Breaching Charge vs objects, Magnetic Shield,
## Stasis Barrier.

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


func _setup(systems: Array, t_cell: Vector2i = Vector2i(6, 0)) -> void:
	s = F.state()
	e = RulesEngine.new()
	a = UnitFactory.build_mech(db(), "a", "mf_standard_pattern_i_everest", {"mounts": [{"weapons": ["mw_assault_rifle"]}], "systems": systems}, {"ll": 12})
	a.side = "players"
	s.add_unit(a)
	t = F.mech(s, "t", "enemies", t_cell)
	t.max_hp = 40
	t.hp = 40
	F.begin(e, s, a)


func _key(name: String) -> String:
	for x: Dictionary in Abilities.all(a):
		if x["name"] == name:
			return x["key"]
	return ""


func test_breaching_charge_hits_walls() -> void:
	_setup(["ms_bb_breach_blast_charges"])
	s.map.set_column(Vector2i(2, 1), 2, PackedStringArray([BattleMap.TAG_DESTRUCTIBLE]))
	var out := F.act(e, s, "activate", "a", {"ability": _key("Deploy Breaching Charge"), "to": [1, 0]})
	expect(F.ok(out), F.reason(out))
	F.act(e, s, "end_turn", "a")
	s.acted = PackedStringArray()
	s.turn_side = "players"
	F.act(e, s, "start_turn", "a")
	out = F.act(e, s, "activate", "a", {"ability": _key("Detonate Breaching Charge")})
	expect(F.ok(out), F.reason(out))
	expect_eq(s.map.ground_height(Vector2i(2, 1)), 0, "30 AP explosive to objects and terrain in the burst")


func test_magnetic_shield() -> void:
	_setup(["ms_magnetic_shield"])
	var out := F.act(e, s, "activate", "a", {"ability": _key("Magnetic Shield"), "aim": [1, 0]})
	expect(F.ok(out), F.reason(out))
	expect(Zones.blocks_step(s, Vector2i(1, 1), Vector2i(2, 0)), "an obstruction")
	F.act(e, s, "end_turn", "a")
	F.act(e, s, "start_turn", "t")
	F.load_dice(s, [19, 1, 4])  # d20, the soft cover Difficulty die, damage
	out = F.act(e, s, "skirmish", "t", {"weapon": "0:0", "target": "a"})
	expect_eq(F.events_of(out, "damage_dealt")[0]["amount"], 2, "behind it: Resistance to kinetic")


func test_stasis_barrier() -> void:
	_setup(["ms_stasis_barrier"])
	var out := F.act(e, s, "activate", "a", {"ability": _key("Deploy Stasis Barrier"), "aim": [1, 0]})
	expect_eq(F.events_of(out, "deployed").size(), 0, "a barrier field, not an object")
	expect(F.ok(out), F.reason(out))
	F.act(e, s, "end_turn", "a")
	F.act(e, s, "start_turn", "t")
	F.load_dice(s, [5])
	out = F.act(e, s, "skirmish", "t", {"weapon": "0:0", "target": "a"})
	expect_eq(F.events_of(out, "attack_blocked").size(), 1, "4+: the attack is consumed")


func _next(u: Unit) -> void:
	F.act(e, s, "end_turn", s.active_unit)
	s.acted = PackedStringArray()
	s.round_number += 1
	s.turn_side = u.side
	F.act(e, s, "start_turn", u.id)


func test_roller_grenade() -> void:
	_setup(["ms_roller_directed_payload_charges"], Vector2i(6, 1))
	F.load_dice(s, [4, 3])  # damage 4+3 = 7, Agility save 3 fails
	var out := F.act(e, s, "activate", "a", {"ability": _key("Roller Grenade"), "aim": [1, 0]})
	expect(F.ok(out), F.reason(out))
	expect_eq(t.hp, 33, "1d6+3 explosive")
	expect_eq(t.cell.x, 9, "knocked 3 spaces the way it rolled")


func test_havok_mine_line() -> void:
	_setup(["ms_havok_charges"], Vector2i(8, 8))
	var out := F.act(e, s, "activate", "a", {"ability": _key("Deploy HAVOK Mine"), "to": [1, 0]})
	expect(F.ok(out), F.reason(out))
	t.cell = Vector2i(4, 0)
	var behind := F.mech(s, "behind", "enemies", Vector2i(5, 0))
	_next(a)
	_next(t)
	F.load_dice(s, [3, 3])
	F.act(e, s, "move", "t", {"to": [2, 0]})
	expect_eq(t.burn, 4, "failed: 4 burn")
	expect_eq(behind.burn, 4, "the line runs on toward the mover and past it")


func test_bouncing_mine_grounds_flyers() -> void:
	_setup(["ms_roller_directed_payload_charges"], Vector2i(8, 8))
	F.act(e, s, "activate", "a", {"ability": _key("Deploy Bouncing Mine"), "to": [1, 0]})
	_next(a)
	t.cell = Vector2i(4, 0)
	t.flight = "flight"
	_next(t)
	F.load_dice(s, [2, 3, 3])
	F.act(e, s, "move", "t", {"to": [2, 0], "fly": true, "level": 3})
	expect(t.has_status("Grounded"), "can't fly until the end of its next turn")
	expect(not t.flying)
