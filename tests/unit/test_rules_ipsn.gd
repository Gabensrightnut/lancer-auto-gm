extends TestCase
## IPS-N weapons and systems (WeaponRules, GearSystems).

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


func _ability(u: Unit, name: String) -> String:
	for x: Dictionary in Abilities.all(u):
		if x["name"] == name:
			return x["key"]
	return ""


func _act(name: String, params: Dictionary = {}) -> Dictionary:
	var p := params.duplicate()
	p["ability"] = _ability(a, name)
	return F.act(e, s, "activate", "a", p)


func _next_turn(u: Unit) -> void:
	F.act(e, s, "end_turn", s.active_unit)
	s.acted = PackedStringArray()
	s.round_number += 1
	s.turn_side = u.side
	F.act(e, s, "start_turn", u.id)


func test_on_hit_save_conditions_from_lancer_data() -> void:
	_setup([], [{"weapons": ["mw_impaler_nailgun"]}])
	F.load_dice(s, [15, 3, 4])  # hit, 1d6+1 = 4, Hull save 4 fails
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect(F.ok(out), F.reason(out))
	expect(t.has_status("Immobilized"), "Impaler: Hull save or Immobilized")


func test_chain_axe_crit_shreds_this_turn() -> void:
	_setup([], [{"weapons": ["mw_chain_axe"]}], Vector2i(1, 0))
	F.load_dice(s, [20, 3, 3])
	F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect(t.has_status("Shredded"))
	_next_turn(t)
	expect(not t.has_status("Shredded"), "until the end of the current turn")


func test_bristlecrown_and_impact_lance_and_drill() -> void:
	_setup([], [{"weapons": ["mw_impact_lance"]}], Vector2i(3, 0))
	var mid := F.mech(s, "mid", "enemies", Vector2i(2, 0))
	F.load_dice(s, [15, 2, 15, 2])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "attack_rolled").size(), 2, "also attacks everyone on the line")
	expect_eq(mid.hp, 8)
	expect_eq(a.heat, 1, "1 heat per extra target")
	_setup([], [{"weapons": ["mw_bristlecrown_flechette_launcher"]}, {}, {}], Vector2i(1, 0))
	t.counters["grapple"] = {"with": "x"}
	F.load_dice(s, [15])
	F.act(e, s, "skirmish", "a", {"weapon": "0:0"})
	expect_eq(t.hp, 27, "3 kinetic to a grappled target instead of 1")


func test_assault_cannon_spin_up() -> void:
	_setup([], [{"weapons": ["mw_assault_cannon"]}])
	var w := Weapons.find(a, "0:0")
	expect_eq(Weapons.tag_value(w, "tg_reliable"), 0)
	var out := _act("Spin Up Assault Cannon")
	expect(F.ok(out), F.reason(out))
	expect_eq(Weapons.tag_value(w, "tg_reliable"), 3, "Spin-Up: Reliable 3")
	expect(a.has_status("Slowed"))
	_next_turn(a)
	expect(F.ok(_act("Spin Down Assault Cannon")))
	expect(not a.has_status("Slowed"))


func test_drag_down_argonaut_and_whitewash() -> void:
	_setup(["ms_reinforced_cabling", "ms_argonaut_shield", "ms_whitewash_sealant_spray"])
	F.load_dice(s, [15, 5])
	var out := _act("Drag Down", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	expect(t.has_status("Prone"), "the loser of the contested Hull check is knocked Prone")
	var ally := F.mech(s, "ally", "players", Vector2i(1, 0))
	expect(F.ok(_act("Argonaut Shield", {"target": "ally"})))
	var hp := a.hp
	Attacks._apply(s, t, ally, [{"type": "Kinetic", "amount": 8}], false)
	expect_eq(ally.hp, 6, "Resistance: 8 halved")
	expect_eq(a.hp, hp - 4, "the shield-bearer takes half, before Armor and Resistance")
	_next_turn(a)
	t.burn = 2
	F.load_dice(s, [3])
	out = _act("Whitewash Sealant Spray", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	expect(t.has_status("Slowed"))
	expect_eq(t.burn, 0)


func test_aceso_ramjet_hyperdense() -> void:
	_setup(["ms_aceso_stabilizer", "ms_ramjet", "ms_hyperdense_armor"])
	var ally := UnitFactory.build_mech(db(), "ally", "mf_standard_pattern_i_everest", {"mounts": [], "systems": []})
	ally.side = "players"
	ally.cell = Vector2i(2, 0)
	s.add_unit(ally)
	expect(F.ok(_act("Aceso Stabilizer", {"target": "ally"})))
	expect_eq(ally.overshield, a.grit + 4)
	expect(Effects.immune_to_status(ally, "Jammed"), "while the overshield lasts")
	ally.overshield = 0
	expect(not Effects.immune_to_status(ally, "Jammed"))
	_next_turn(a)
	expect(F.ok(_act("Ramjet")))
	expect_eq(a.heat, 2, "Heat 2 (Self)")
	expect_eq(Effects.value(a, "boost_bonus"), 2)
	_next_turn(a)
	expect(F.ok(_act("HyperDense Armor")))
	expect(a.has_status("Slowed"))
	expect(Effects.resists(a, "Kinetic", false, 8), "Resistance beyond range 3")
	expect(not Effects.resists(a, "Kinetic", false, 2))
	_next_turn(a)
	expect(F.ok(_act("Deactivate HyperDense Armor")))
	expect(not a.has_status("Slowed"))


func test_thermal_grenade_breaching_charge_and_stake() -> void:
	_setup(["ms_bb_breach_blast_charges", "ms_charged_stake"], [{"weapons": ["mw_assault_rifle"]}], Vector2i(1, 0))
	F.load_dice(s, [4, 3])
	var out := _act("Thermal Grenade", {"aim": [1, 0]})
	expect(F.ok(out), F.reason(out))
	expect_eq(t.hp, 26)
	_next_turn(a)
	out = _act("Deploy Breaching Charge", {"to": [0, 1]})
	expect(F.ok(out), F.reason(out))
	_next_turn(a)
	F.load_dice(s, [6, 6, 2])
	out = _act("Detonate Breaching Charge")
	expect(F.ok(out), F.reason(out))
	expect_eq(t.hp, 14, "2d6 AP explosive")
	_next_turn(a)
	F.load_dice(s, [2, 3])
	out = _act("Charged Stake", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	expect(t.has_status("Immobilized"))
	expect_eq(t.hp, 11)
	_next_turn(t)
	F.load_dice(s, [4])
	F.act(e, s, "end_turn", "t")
	expect_eq(t.hp, 7, "1d6 AP energy at the end of each of its turns")
	_next_turn(t)
	F.load_dice(s, [19])
	out = F.act(e, s, "pull_stake", "t")
	expect(F.ok(out), F.reason(out))
	expect(not t.has_status("Immobilized"), "a successful save frees it")


func test_restock_drone_and_aegis_generator() -> void:
	_setup(["ms_restock_drone", "ms_aegis_shield_generator"], [{}, {}, {"weapons": ["mw_anti_materiel_rifle"]}])
	var out := _act("Deploy Restock Drone", {"to": [1, 0]})
	expect(F.ok(out), F.reason(out))
	var drone: String = F.events_of(out, "deployed")[0]["object"]["id"]
	_next_turn(a)
	a.heat = 4
	a.statuses["Impaired"] = {"source": "t"}
	Weapons.state_of(a, Weapons.find(a, "2:0"))["loaded"] = false
	F.load_dice(s, [3])
	out = F.act(e, s, "use_object", "a", {"object": drone, "condition": "Impaired", "weapon": "2:0"})
	expect(F.ok(out), F.reason(out))
	expect_eq(a.heat, 1)
	expect(not a.has_status("Impaired"))
	expect(Weapons.state_of(a, Weapons.find(a, "2:0"))["loaded"])
	expect(s.unit(drone) == null, "disintegrates")
	expect(F.ok(_act("Deploy Aegis Shield Generator", {"to": [0, 1]})))
	F.load_dice(s, [4])
	var hp := a.hp
	Attacks._apply(s, t, a, [{"type": "Kinetic", "amount": 6}], true)
	expect_eq(a.hp, hp - 2, "a d6 off the damage")


func test_bunker_caltrops_snare() -> void:
	_setup(["ms_portable_bunker", "ms_caltrop_launcher", "ms_webjaw_snare"], [{"weapons": ["mw_assault_rifle"]}], Vector2i(9, 9))
	var out := _act("Deploy Portable Bunker", {"to": [1, 0]})
	expect(F.ok(out), F.reason(out))
	_next_turn(a)
	F.act(e, s, "move", "a", {"to": [2, 1]})
	expect(Zones.bunker_protects(s, a, t), "hard cover inside the unfolded bunker")
	expect(F.ok(_act("Deploy Caltrop Field", {"to": [6, 6]})))
	expect(Zones.difficult_at(s, Vector2i(6, 7)))
	F.act(e, s, "overcharge", "a")
	out = _act("Deploy Webjaw Snare", {"to": [3, 2]})
	expect(F.ok(out), F.reason(out))
	var snare := s.unit(F.events_of(out, "deployed")[0]["object"]["id"])
	expect(snare.has_status("Hidden"), "can't be attacked until triggered")
	F.act(e, s, "end_turn", "a")
	F.load_dice(s, [3, 5])
	var ev := GearSystems.check_snares(s, t, [[3, 1, 0], [3, 2, 0], [3, 3, 0]])
	expect_eq(F.events_of({"events": ev}, "mine_triggered").size(), 1, "moving over it springs it")
	expect(t.has_status("Immobilized"))
	Combat.deal_damage(s, snare, [{"type": "Kinetic", "amount": 20}], {"ap": true})
	expect(not t.has_status("Immobilized"), "until the snare is destroyed")


func test_roland_siege_ram_armor_lock_netting() -> void:
	_setup(["ms_roland_chamber", "ms_siege_ram", "ms_armor_lock_plating", "ms_synthetic_muscle_netting"], [{}, {}, {"weapons": ["mw_anti_materiel_rifle"]}], Vector2i(1, 0))
	var big := F.mech(s, "big", "enemies", Vector2i(0, 1), 2.0)
	expect(e.validate(s, {"type": "ram", "actor": "a", "params": {"target": "big"}}).ok, "Muscle Netting: may Ram larger targets")
	F.load_dice(s, [15])
	var hp := t.hp
	var out := F.act(e, s, "ram", "a", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	expect_eq(t.hp, hp - 2, "Siege Ram: 2 kinetic on a hit")
	_next_turn(a)
	t.cell = Vector2i(6, 0)
	big.cell = Vector2i(8, 8)
	a.counters["roland"] = true
	F.load_dice(s, [15, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1])
	out = F.act(e, s, "skirmish", "a", {"weapon": "2:0", "target": "t"})
	expect(F.events_of(out, "bonus_damage").size() == 1, "Roland: +1d6 explosive after a reload")
	expect(t.has_status("Prone"))
	Reactions.brace(s, a, "t")
	expect(Effects.has(a, "immune_grapple"), "Armor-Lock: immune to Grapple after Bracing")
	expect(Combat.skill_check(s, a, "hull", "x", 30)["success"], "can't fail Hull saves")
	expect_eq(GearSystems.grapple_size(a, big), 2.0, "Muscle Netting: counts as the larger opponent's Size")
