extends TestCase
## Harrison Armory weapons and systems.

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


func test_siege_stabilizers_toggle() -> void:
	_setup(["ms_siege_stabilizers"], [{"weapons": ["mw_assault_rifle"]}], Vector2i(13, 0))
	expect(not F.ok(F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})), "Range 10")
	expect(F.ok(_act("Siege Stabilizers")))
	expect(a.has_status("Immobilized"))
	expect(RulesQueries.attack_preview(s, "a", "0:0", "t")["ok"], "+5 range")
	t.cell = Vector2i(3, 0)
	expect(not RulesQueries.attack_preview(s, "a", "0:0", "t")["ok"], "nothing within range 5")
	_next_turn(a)
	expect(F.ok(_act("Siege Stabilizers")), "retract")
	expect(not a.has_status("Immobilized"))


func test_ammo_feed_autoloader_flak() -> void:
	_setup(["ms_external_ammo_feed", "ms_autoloader_drone", "ms_flak_launcher"], [{}, {}, {"weapons": ["mw_anti_materiel_rifle"]}], Vector2i(6, 0))
	Weapons.state_of(a, Weapons.find(a, "2:0"))["loaded"] = false
	F.load_dice(s, [1])
	var out := _act("External Ammo Feed", {"weapon": "2:0"})
	expect(F.ok(out), F.reason(out))
	expect(Weapons.state_of(a, Weapons.find(a, "2:0"))["loaded"])
	expect_eq(a.heat, 2, "Heat 1d3+1 (Self), rolled")
	out = _act("Deploy Autoloader Drone", {"to": [1, 0]})
	expect(F.ok(out), F.reason(out))
	var drone: String = F.events_of(out, "deployed")[0]["object"]["id"]
	Weapons.state_of(a, Weapons.find(a, "2:0"))["loaded"] = false
	_next_turn(a)
	expect(F.ok(F.act(e, s, "use_object", "a", {"object": drone, "weapon": "2:0"})))
	expect(Weapons.state_of(a, Weapons.find(a, "2:0"))["loaded"])
	t.flying = true
	t.level = 3
	F.load_dice(s, [3])
	out = _act("Flak Launcher", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	expect(not t.flying, "forced to land")
	expect(t.has_status("Slowed"))


func test_vents_auto_cooler_and_deep_well() -> void:
	_setup(["ms_explosive_vents", "ms_auto_cooler", "ms_deep_well_heat_sink"], [{"weapons": ["mw_assault_rifle"]}], Vector2i(1, 0))
	a.heat = 4
	F.act(e, s, "stabilize", "a", {"main": "cool", "extra": "reload"})
	expect_eq(t.burn, 2, "Explosive Vents: 2 burn and 2 heat in burst 1")
	expect_eq(t.heat, 2)
	_next_turn(a)
	a.heat = 3
	expect(F.ok(_act("Auto-Cooler")))
	_next_turn(a)
	expect_eq(a.heat, 0, "cleared at the start of the next turn")
	a.heat = 5
	a.statuses["Danger Zone"] = {"source": "heat"}
	_next_turn(a)
	expect(Effects.resists(a, "Heat", false, -1), "Deep Well: Resistance to heat starting in the Danger Zone")


func test_grenades_mines_and_repulser() -> void:
	_setup(["ms_havok_charges", "ms_grounding_charges", "ms_repulser_field"], [{"weapons": ["mw_assault_rifle"]}], Vector2i(4, 0))
	F.load_dice(s, [3])
	var out := _act("Napalm Grenade", {"aim": [3, 0], "toward": [5, 0]})
	expect(F.ok(out), F.reason(out))
	expect_eq(t.burn, 2, "a failed save: 2 burn")
	_next_turn(a)
	F.load_dice(s, [3])
	out = _act("Gravity Grenade", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	expect(t.has_status("Slowed"))
	_next_turn(a)
	t.cell = Vector2i(2, 0)
	F.load_dice(s, [3])
	out = _act("Repulser Field")
	expect(F.ok(out), F.reason(out))
	expect_eq(t.cell, Vector2i(4, 0), "knocked 2 away")


func test_clamp_bombs() -> void:
	_setup(["ms_clamp_bombs"])
	var near := F.mech(s, "near", "enemies", Vector2i(5, 0))
	F.load_dice(s, [3])
	var out := _act("Fire Clamp Bombs", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	expect(t.counters.has("clamp_bombs"))
	_next_turn(t)
	F.load_dice(s, [5])
	F.act(e, s, "end_turn", "t")
	expect_eq(t.hp, 22, "1d6+3 AP explosive at the end of its next turn")
	expect_eq(near.hp, 6, "half to adjacent characters")


func test_stasis_generator_and_bolt() -> void:
	_setup(["ms_stasis_generator", "ms_stasis_bolt"])
	F.load_dice(s, [3])
	var out := _act("Stasis Generator", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	expect(t.has_status("Stunned"))
	expect(not RulesQueries.attack_preview(s, "a", "0:0", "t")["ok"], "can't be targeted in stasis")
	_next_turn(t)
	_next_turn(a)
	expect(not t.has_status("In Stasis"))
	expect(F.ok(_act("Charge Stasis Bolt")))
	_next_turn(t)
	F.load_dice(s, [10, 20])
	out = F.act(e, s, "skirmish", "t", {"weapon": "0:0", "target": "a"})
	expect_eq(F.events_of(out, "attack_rolled")[0]["result"], "miss", "Interdiction Point: won the contested roll")


func test_enclave_flash_anchor_reactor_stabilizer() -> void:
	_setup(["ms_enclave_pattern_support_shield", "ms_flash_anchor", "ms_reactor_stabilizer"], [{"weapons": ["mw_assault_rifle"]}], Vector2i(8, 0))
	var out := _act("ENCLAVE-Pattern Support Shield")
	expect(F.ok(out), F.reason(out))
	expect(a.has_status("Immobilized"))
	expect_eq(RulesQueries.attack_preview(s, "t", "0:0", "a")["difficulty"], 1, "+1 Difficulty from outside the dome")
	var ev := Attacks.knock_back(s, a, t.cell, 2, t)
	expect_eq(F.events_of({"events": ev}, "reaction")[0]["reaction"], "flash_lock")
	expect_eq(a.cell, Vector2i(0, 0), "the push is prevented")
	expect_eq(a.heat, 2)


func test_lucifer_plasma_gauntlet_external_batteries() -> void:
	_setup(["ms_lucifer_class_nhp", "ms_plasma_gauntlet", "ms_external_batteries"], [{"weapons": ["mw_sol_pattern_laser_rifle"]}], Vector2i(1, 0))
	expect_eq(Weapons.range_for(a, Weapons.find(a, "0:0")), 13, "External Batteries: +5 range for energy weapons")
	F.load_dice(s, [1])
	expect(F.ok(_act("LUCIFER Protocol")))
	var heat := a.heat
	F.load_dice(s, [15, 2])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	var bonus: Array = F.events_of(out, "bonus_damage")
	expect_eq(bonus.size(), 1)
	expect_eq(bonus[0]["amount"], heat, "bonus damage equal to your heat")
	_next_turn(a)
	a.heat = 0
	a.statuses.erase("Danger Zone")
	expect(not F.ok(_act("Plasma Gauntlet", {"target": "t"})), "only in the Danger Zone")


func test_ha_weapons() -> void:
	_setup([], [{}, {}, {"weapons": ["mw_siege_cannon"]}], Vector2i(8, 0))
	var out := F.act(e, s, "barrage", "a", {"attacks": [{"weapon": "2:0", "target": "t", "profile": 1}]})
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "attack_rolled").size(), 1, "Direct Fire Mode at a target")
	_setup([], [{"weapons": ["mw_shatterhead_colony_missiles"]}], Vector2i(8, 0))
	t.statuses["Braced"] = {"source": "t"}
	expect_eq(RulesQueries.attack_preview(s, "a", "0:0", "t")["difficulty"], 0, "Shatterhead ignores Difficulty")
	_setup([], [{"weapons": ["mw_annihilator"]}], Vector2i(3, 0))
	var t2 := F.mech(s, "t2", "enemies", Vector2i(4, 0))
	F.load_dice(s, [15, 2, 15])
	out = F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect_eq(F.events_of(out, "attack_rolled").size(), 2, "secondary attack on everyone next to the target")
	expect(t2.hp < 10)
