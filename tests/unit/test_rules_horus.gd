extends TestCase
## HORUS weapons and systems.

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


func test_smite_sear_and_eject_power_cores() -> void:
	_setup(["ms_smite", "ms_h0r_os_system_upgrade_i"])
	var hp := a.hp
	F.load_dice(s, [19, 2, 3])  # hit, 1d6 = 2 to you, Systems save 3 fails
	var out := _act("Smite", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	expect_eq(a.hp, hp - 2, "Smite costs you 1d6 AP energy")
	expect(t.has_status("Stunned"))
	_next_turn(a)
	t.statuses.erase("Stunned")
	var near := F.mech(s, "near", "enemies", Vector2i(5, 0))
	F.load_dice(s, [19])
	out = _act("Eject Power Cores", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	expect(t.has_status("Jammed"))
	expect_eq(near.hp, 8, "adjacent characters take 2 energy")


func test_beckon_summon_ophidian_trek() -> void:
	_setup(["ms_beckoner", "ms_metafold_carver"], [{"weapons": ["mw_assault_rifle"]}], Vector2i(5, 0))
	F.load_dice(s, [19, 1])
	var out := _act("Beckon", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	expect_eq([a.cell, t.cell], [Vector2i(5, 0), Vector2i(0, 0)], "swapped places")
	_next_turn(a)
	F.load_dice(s, [19, 2])  # 1d6+1 = 3
	out = _act("Ophidian Trek", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	expect_eq(t.cell, Vector2i(3, 0), "teleported 3 spaces toward you")


func test_chains_of_prometheus_and_shake_off() -> void:
	_setup(["ms_aggressive_system_sync"])
	F.load_dice(s, [19])
	var out := _act("Chains of Prometheus", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	expect_eq(t.heat, 4)
	_next_turn(t)
	F.act(e, s, "end_turn", "t")
	expect_eq(t.heat, 6, "2 heat ending a turn more than range 3 away")
	_next_turn(t)
	F.load_dice(s, [19])
	out = F.act(e, s, "shake_off", "t", {"what": "chains"})
	expect(F.ok(out), F.reason(out))
	expect(not t.counters.has("chains"))


func test_fold_space_and_hunter_lock() -> void:
	_setup(["ms_metafold_carver", "ms_hunter_lock"])
	F.load_dice(s, [19])
	expect(F.ok(_act("Fold Space", {"target": "t"})))
	expect(not Combat.is_present(t), "gone until the start of its next turn")
	_next_turn(t)
	expect(Combat.is_present(t))
	_next_turn(a)
	expect(F.ok(_act("Hunter Lock", {"target": "t"})))
	F.load_dice(s, [15, 2])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	var bonus: Array = F.events_of(out, "bonus_damage")
	expect_eq(bonus.size(), 1)
	expect_eq(bonus[0]["amount"], 3)


func test_emp_lightning_eye() -> void:
	_setup(["ms_emp_pulse", "ms_lightning_generator", "ms_eye_of_horus"], [{"weapons": ["mw_assault_rifle"]}], Vector2i(1, 0))
	var lg := _act("Lightning Generator")
	expect(F.ok(lg), F.reason(lg))
	expect_eq(t.hp, 28, "2 energy to adjacent characters")
	expect_eq(a.heat, 1)
	_next_turn(a)
	t.cell = Vector2i(6, 0)
	t.statuses["Hidden"] = {"source": "t"}
	var eye := _act("Eye of HORUS")
	expect(F.ok(eye), F.reason(eye))
	expect(RulesQueries.attack_preview(s, "a", "0:0", "t")["ok"], "no Hidden against you")
	_next_turn(a)
	t.cell = Vector2i(1, 0)
	F.load_dice(s, [2])
	expect(F.ok(_act("EMP Pulse")))
	expect(a.has_status("Stunned"))
	expect(t.has_status("Stunned"))


func test_hive_sentinel_tempest_drones() -> void:
	_setup(["ms_hive_drone", "ms_sentinel_drone"], [{"weapons": ["mw_assault_rifle"]}], Vector2i(6, 0))
	expect(F.ok(_act("Deploy Hive Drone", {"to": [5, 2]})))
	_next_turn(a)
	expect(F.ok(_act("Deploy Sentinel Drone", {"to": [5, 1]})))
	_next_turn(t)
	expect_eq(t.hp, 29, "starting a turn in the hive swarm: 1 AP kinetic")
	F.load_dice(s, [1])
	F.act(e, s, "skirmish", "t", {"weapon": "0:0", "target": "a"})
	expect_eq(t.hp, 26, "the sentinel shoots before it attacks")


func test_swarm_body_and_interdiction() -> void:
	_setup(["ms_swarm_body", "ms_interdiction_field"], [{"weapons": ["mw_assault_rifle"]}], Vector2i(5, 0))
	expect(F.ok(_act("Swarm Body")))
	_next_turn(t)
	F.load_dice(s, [2])
	F.act(e, s, "move", "t", {"to": [1, 0]})
	expect_eq(t.hp, 27, "entering the swarm on its turn: 3 kinetic")
	_next_turn(a)
	F.load_dice(s, [2])
	expect(F.ok(_act("Interdiction Field")))
	expect(a.has_status("Slowed"))
	_next_turn(t)
	expect(t.has_status("Slowed"), "a hostile starting its turn in the field saves or is Slowed")


func test_scorpion_scanner_and_mesmer_mine() -> void:
	_setup(["ms___scorpion_v70.1", "ms_scanner_swarm", "ms_mesmer_charges"], [{"weapons": ["mw_assault_rifle"]}], Vector2i(1, 0))
	expect_eq(RulesQueries.tech_preview(s, "a", "t")["accuracy"], 1, "Scanner Swarm: +1 against adjacent targets")
	t.cell = Vector2i(3, 0)
	var out := _act("Deploy Mesmer Mine", {"to": [0, 1]})
	expect(F.ok(out), F.reason(out))
	_next_turn(t)
	t.cell = Vector2i(1, 0)
	F.load_dice(s, [1, 1])
	F.act(e, s, "invade", "t", {"target": "a"})
	t.cell = Vector2i(3, 0)
	expect(t.has_status("Impaired"), "//SCORPION: a missed tech attack leaves the attacker Impaired")
	expect_eq(t.heat, 2)
	t.statuses.erase("Impaired")
	F.load_dice(s, [2])
	F.act(e, s, "move", "t", {"to": [1, 2]})
	expect(t.has_status("Immobilized"), "Mesmer Mine: Systems save or Immobilized")


func test_horus_weapons() -> void:
	_setup([], [{"weapons": ["mw_ghoul_nexus"]}])
	F.load_dice(s, [15, 2])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t", "damage_type": "Energy"})
	expect_eq(F.events_of(out, "damage_rolled")[0]["damage_type"], "Energy", "you set its damage type")
	_setup([], [{}, {}, {"weapons": ["mw_arc_projector"]}], Vector2i(3, 0))
	var t2 := F.mech(s, "t2", "enemies", Vector2i(5, 0))
	F.load_dice(s, [15, 2, 15, 2])
	out = F.act(e, s, "skirmish", "a", {"weapon": "2:0", "target": "t", "chain": ["t2"]})
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "attack_rolled").size(), 2, "a hit chains to another target within 3")
	expect(t2.hp < 10)
	_setup([], [{"weapons": ["mw_autogun"]}])
	expect(not F.ok(F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})), "the Autogun can't attack normally")
	F.load_dice(s, [15])
	out = _act("Fire Autogun", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	expect_eq(t.hp, 27)
