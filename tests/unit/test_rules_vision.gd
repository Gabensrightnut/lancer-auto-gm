extends TestCase
## Vision and barriers: Blinded, Flash Charges, Hardlight Defense System, Blinkshield, OASIS Wall.

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
	a = UnitFactory.build_mech(db(), "a", "mf_standard_pattern_i_everest", {"mounts": [{"weapons": ["mw_assault_rifle"]}], "systems": systems})
	a.side = "players"
	s.add_unit(a)
	t = F.mech(s, "t", "enemies", t_cell)
	F.begin(e, s, a)


func _act(name: String, params: Dictionary = {}) -> Dictionary:
	var p := params.duplicate()
	for x: Dictionary in Abilities.all(a):
		if x["name"] == name:
			p["ability"] = x["key"]
	return F.act(e, s, "activate", "a", p)


func test_blinded() -> void:
	_setup([])
	a.statuses["Blinded"] = {"source": "t"}
	expect(not RulesQueries.attack_preview(s, "a", "0:0", "t")["ok"], "only line of sight to adjacent spaces")
	t.cell = Vector2i(1, 0)
	expect(RulesQueries.attack_preview(s, "a", "0:0", "t")["ok"])


func test_flash_grenade_and_mine() -> void:
	_setup(["ms_flash_charges"])
	var out := _act("Flash Grenade", {"aim": [5, 0]})
	expect(F.ok(out), F.reason(out))
	expect(not Sight.unit_line_of_sight(s, t, a), "can't see out of the flash")
	expect(Sight.unit_line_of_sight(s, a, t), "but it can be seen into")


func test_hardlight_and_blinkshield() -> void:
	_setup(["ms_hardlight_defense_system"])
	var out := _act("Hardlight Defense System")
	expect(F.ok(out), F.reason(out))
	expect(a.has_status("Immobilized"))
	expect(not RulesQueries.attack_preview(s, "t", "0:0", "a")["ok"], "nothing crosses the shield")
	_setup(["ms_blinkshield"], Vector2i(6, 0))
	out = _act("Blinkshield")
	expect(F.ok(out), F.reason(out))
	expect(not Sight.unit_line_of_sight(s, t, a))
	expect(not RulesQueries.attack_preview(s, "a", "0:0", "t")["ok"])
	expect(Zones.blocks_step(s, Vector2i(4, 0), Vector2i(5, 0)), "movement can't cross its edge")


func test_oasis_wall() -> void:
	_setup(["ms_oasis_wall"], Vector2i(8, 8))
	expect(F.ok(_act("OASIS Wall")))
	F.act(e, s, "move", "a", {"to": [3, 0]})
	var ally := F.mech(s, "ally", "players", Vector2i(1, 1))
	expect(Zones.oasis_cover(s, ally), "next to the trail: hard cover")
	expect_eq(RulesQueries.attack_preview(s, "t", "0:0", "ally")["cover"]["cover"], "hard")
