extends TestCase
## SSC weapons and systems.

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


func _setup(systems: Array = [], mounts: Array = [{"weapons": ["mw_assault_rifle"]}], t_cell: Vector2i = Vector2i(4, 0)) -> void:
	s = F.state()
	e = RulesEngine.new()
	a = UnitFactory.build_mech(db(), "a", "mf_standard_pattern_i_everest", {"mounts": mounts, "systems": systems})
	a.side = "players"
	s.add_unit(a)
	t = F.mech(s, "t", "enemies", t_cell)
	t.max_hp = 30
	t.hp = 30
	F.begin(e, s, a)


func _act(name: String, params: Dictionary = {}) -> Dictionary:
	var p := params.duplicate()
	for x: Dictionary in Abilities.all(a):
		if x["name"] == name:
			p["ability"] = x["key"]
	return F.act(e, s, "activate", "a", p)


func _next_turn(u: Unit) -> void:
	F.act(e, s, "end_turn", s.active_unit)
	s.acted = PackedStringArray()
	s.round_number += 1
	s.turn_side = u.side
	F.act(e, s, "start_turn", u.id)


func test_ferrous_lash_and_stuncrown() -> void:
	_setup(["ms_ferrous_lash", "ms_stuncrown"])
	F.load_dice(s, [3])
	var out := _act("Ferrous Lash", {"target": "t", "toward": [4, 6]})
	expect(F.ok(out), F.reason(out))
	expect_eq(t.cell, Vector2i(4, 5), "pulled 5 spaces")
	_next_turn(a)
	t.cell = Vector2i(2, 0)
	F.load_dice(s, [3, 3])
	out = _act("StunCrown")
	expect(F.ok(out), F.reason(out))
	expect(t.has_status("Jammed") and t.has_status("Impaired"))


func test_black_ice_escalates() -> void:
	_setup(["ms_black_ice_module"])
	_next_turn(t)
	var p1 := RulesQueries.tech_preview(s, "t", "a")
	expect_eq(p1["difficulty"], 1)
	F.load_dice(s, [1, 1, 1, 1])
	F.act(e, s, "invade", "t", {"target": "a"})
	expect_eq(RulesQueries.tech_preview(s, "t", "a")["difficulty"], 2, "+1 more for the next tech attack")


func test_core_siphon_and_kinetic_compensator() -> void:
	_setup(["ms_core_siphon", "ms_kinetic_compensator"])
	expect(F.ok(_act("Core Siphon")))
	expect_eq(RulesQueries.attack_preview(s, "a", "0:0", "t")["accuracy"], 1, "+1 Accuracy on the first attack")
	F.load_dice(s, [1, 1])
	F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	var p := RulesQueries.attack_preview(s, "a", "0:0", "t")
	expect_eq(p["difficulty"], 1, "+1 Difficulty after that")
	expect_eq(p["accuracy"], 1, "and the missed ranged attack gives +1 next time")


func test_neurospike_tracking_bug_markerlight() -> void:
	_setup(["ms_neurospike", "ms_tracking_bug", "ms_markerlight"])
	F.load_dice(s, [19])
	var out := _act("Shrike Code", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	_next_turn(t)
	F.load_dice(s, [1])
	F.act(e, s, "skirmish", "t", {"weapon": "0:0", "target": "a"})
	expect_eq(t.heat, 2 + 2, "Invade heat, then 2 heat for attacking")
	_next_turn(a)
	F.load_dice(s, [19])
	out = _act("Tracking Bug", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	t.statuses["Invisible"] = {"source": "x"}
	F.load_dice(s, [15, 3])
	out = F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect(F.events_of(out, "invisible_roll").is_empty(), "the tracker ignores Invisible")
	expect(not Combat.can_hide(s, t).ok, "can't Hide")
	_next_turn(a)
	F.load_dice(s, [19])
	out = _act("Markerlight", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	expect(t.has_status("Lock On"))


func test_retractable_profile_and_cloaking_field() -> void:
	_setup(["ms_retractable_profile", "ms_lb_oc_cloaking_field"])
	expect(F.ok(_act("Retractable Profile")))
	expect(not F.ok(F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})), "no attacks")
	expect_eq(RulesQueries.attack_preview(s, "t", "0:0", "a")["difficulty"], 1)
	expect(a.has_status("Slowed"))
	_next_turn(a)
	expect(F.ok(_act("Deactivate Retractable Profile")))
	expect(not a.has_status("Slowed"))
	_next_turn(a)
	var ally := F.mech(s, "ally", "players", Vector2i(1, 1))
	expect(F.ok(_act("LB/OC Cloaking Field")))
	expect(GearSystems.cloaked(s, ally), "allies completely inside burst 2 are Invisible")
	Combat.deal_damage(s, a, [{"type": "Kinetic", "amount": 1}], {})
	expect(not GearSystems.cloaked(s, ally), "ends when you take damage")


func test_javelin_rockets_and_iceout() -> void:
	_setup(["ms_javelin_rockets", "ms_iceout_drone"])
	expect(not F.ok(_act("Javelin Rockets", {"spaces": [[3, 3], [3, 4], [8, 8]]})), "not adjacent to each other")
	var out := _act("Javelin Rockets", {"spaces": [[4, 2], [6, 6], [8, 2]]})
	expect(F.ok(out), F.reason(out))
	_next_turn(t)
	F.act(e, s, "move", "t", {"to": [4, 2]})
	expect_eq(t.hp, 27, "3 kinetic moving into a marked space")
	_next_turn(a)
	out = _act("Deploy ICEOUT Drone", {"to": [1, 1]})
	expect(F.ok(out), F.reason(out))
	expect(not F.ok(F.act(e, s, "lock_on", "a", {"target": "t"})), "can't take tech actions inside the field")


func test_ssc_weapons() -> void:
	_setup([], [{"weapons": ["mw_magnetic_cannon"]}], Vector2i(5, 0))
	F.load_dice(s, [15, 2, 3, 2])  # hit, damage 1d3+1 = 3, Hull save 3 fails, pulled 1d3+1 = 3
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "aim": [5, 0]})
	expect(F.ok(out), F.reason(out))
	expect(t.cell.x < 5, "pulled toward the attacker")
	_setup([], [{"weapons": ["mw_sharanga_missiles"]}])
	var t2 := F.mech(s, "t2", "enemies", Vector2i(6, 2))
	F.load_dice(s, [15, 15])
	out = F.act(e, s, "skirmish", "a", {"weapon": "0:0", "targets": ["t", "t2"]})
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "attack_rolled").size(), 2, "two targets at a time")
	_setup([], [{"weapons": ["mw_variable_sword"]}], Vector2i(1, 0))
	F.load_dice(s, [20, 1, 1])
	out = F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect_eq(F.events_of(out, "bonus_damage").size(), 1, "Variable Sword: +1d6 on a crit")
	_setup([], [{"weapons": ["mw_veil_rifle"]}], Vector2i(6, 0))
	var ally := F.mech(s, "ally", "players", Vector2i(3, 0))
	F.load_dice(s, [2, 15])
	out = F.act(e, s, "skirmish", "a", {"weapon": "0:0", "aim": [6, 0]})
	expect(F.ok(out), F.reason(out))
	expect_eq(ally.hp, 10, "allies in the line aren't attacked")
	expect(Effects.has(ally, "soft_cover_aura"), "they get soft cover instead")
