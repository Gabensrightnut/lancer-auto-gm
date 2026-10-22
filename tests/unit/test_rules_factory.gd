extends TestCase
## UnitFactory: mechs from lancer-data, loadout legality, hand-written NPCs.

var db: ContentDB


func _db() -> ContentDB:
	if db == null:
		db = ContentDB.new()
		db.load_all()
	return db


func test_everest_stats_and_weapons() -> void:
	var loadout := {"mounts": [{"weapons": ["mw_assault_rifle"]}, {"weapons": ["mw_pistol"]}, {"weapons": ["mw_anti_materiel_rifle"]}], "systems": []}
	var u := UnitFactory.build_mech(_db(), "p1", "mf_standard_pattern_i_everest", loadout, {"ll": 2, "hull": 1, "agility": 2, "systems": 1, "engineering": 1})
	expect_eq(u.max_hp, 10 + 1 + 2, "HP = frame 10 + Grit 1 + 2 per Hull")
	expect_eq(u.grit, 1)
	expect_eq(u.evasion, 10)
	expect_eq(u.speed, 5)
	expect_eq(u.edef, 9)
	expect_eq(u.heat_cap, 7)
	expect_eq(u.structure, 4)
	var weapons: Array = u.loadout["weapons"]
	expect_eq(weapons.size(), 3)
	expect_eq(weapons[0]["key"], "0:0")
	expect_eq(weapons[2]["size"], "Heavy")
	expect(Weapons.has_tag(weapons[2], "tg_ordnance"))
	expect_eq(Weapons.tag_value(weapons[0], "tg_reliable"), 2)


func test_legal_loadout_passes() -> void:
	var loadout := {"mounts": [{"weapons": ["mw_assault_rifle"]}, {"weapons": ["mw_pistol"]}, {"weapons": ["mw_anti_materiel_rifle"]}], "systems": []}
	var r := UnitFactory.check_loadout(_db(), "mf_standard_pattern_i_everest", loadout)
	expect(r.ok, r.reason)


func test_heavy_weapon_does_not_fit_main_mount() -> void:
	var loadout := {"mounts": [{"weapons": ["mw_anti_materiel_rifle"]}], "systems": []}
	var r := UnitFactory.check_loadout(_db(), "mf_standard_pattern_i_everest", loadout)
	expect(not r.ok)
	expect_eq(r.rule_ref, UnitFactory.REF_MOUNTS)


func test_flex_mount_takes_two_aux_but_not_main_plus_aux() -> void:
	var two_aux := {"mounts": [{}, {"weapons": ["mw_pistol", "mw_pistol"]}], "systems": []}
	expect(UnitFactory.check_loadout(_db(), "mf_standard_pattern_i_everest", two_aux).ok)
	var mixed := {"mounts": [{}, {"weapons": ["mw_assault_rifle", "mw_pistol"]}], "systems": []}
	expect(not UnitFactory.check_loadout(_db(), "mf_standard_pattern_i_everest", mixed).ok)


func test_system_points_are_enforced() -> void:
	var systems: Array = []
	for i in range(8):
		systems.append("ms_pattern_a_smoke_charges")
	var r := UnitFactory.check_loadout(_db(), "mf_standard_pattern_i_everest", {"mounts": [], "systems": systems})
	expect(not r.ok, "8 systems are well over 6 SP")
	var found := false
	for d: Dictionary in r.details:
		found = found or d["rule_ref"] == UnitFactory.REF_SP
	expect(found, "SP problem listed")


func test_superheavy_needs_a_spare_mount() -> void:
	var full := {"mounts": [{"weapons": ["mw_assault_rifle"]}, {"weapons": ["mw_pistol"]}, {"weapons": ["mw_cyclone_pulse_rifle"]}], "systems": []}
	expect(not UnitFactory.check_loadout(_db(), "mf_standard_pattern_i_everest", full).ok)
	var spare := {"mounts": [{"weapons": ["mw_assault_rifle"]}, {}, {"weapons": ["mw_cyclone_pulse_rifle"]}], "systems": []}
	expect(UnitFactory.check_loadout(_db(), "mf_standard_pattern_i_everest", spare).ok)


func test_npc_template() -> void:
	var templates := UnitFactory.npc_templates()
	expect(templates.has("training_drone"))
	var n := UnitFactory.build_npc("e1", templates["training_drone"])
	expect_eq(n.kind, Unit.KIND_NPC)
	expect_eq(n.hp, 10)
	expect_eq(n.structure, 1)
	var w: Dictionary = n.loadout["weapons"][0]
	expect_eq(w["attack_bonus"], 1)
	expect_eq(Weapons.range_value(w, "Range"), 8)


func test_gms_gear_needs_no_license() -> void:
	var loadout := {"mounts": [{"weapons": ["mw_assault_rifle"]}], "systems": []}
	expect(UnitFactory.check_loadout(_db(), "mf_standard_pattern_i_everest", loadout, {"ll": 0}).ok)


func test_frame_needs_its_license_rank_two() -> void:
	var r := UnitFactory.check_loadout(_db(), "mf_raleigh", {"mounts": []}, {"ll": 1, "licenses": {"mf_raleigh": 1}})
	expect(not r.ok)
	expect_eq(r.reason, "Needs Raleigh license rank 2.")
	expect_eq(r.rule_ref, UnitFactory.REF_LICENSE)
	var ok := UnitFactory.check_loadout(_db(), "mf_raleigh", {"mounts": []}, {"ll": 2, "licenses": {"mf_raleigh": 2}})
	expect(ok.ok, ok.reason)


func test_manufacturer_gear_needs_the_license_rank() -> void:
	var loadout := {"mounts": [{}, {}, {"weapons": ["mw_kinetic_hammer"]}], "systems": []}
	var r := UnitFactory.check_loadout(_db(), "mf_standard_pattern_i_everest", loadout, {"ll": 2, "licenses": {"Raleigh": 2}})
	expect(not r.ok)
	expect_eq(r.reason, "Needs Raleigh license rank 3.")
	var hand_cannon := {"mounts": [{}, {"weapons": ["mw_hand_cannon"]}], "systems": []}
	expect(UnitFactory.check_loadout(_db(), "mf_standard_pattern_i_everest", hand_cannon, {"ll": 1, "licenses": {"mf_raleigh": 1}}).ok, "license name or id both work")


func test_license_ranks_come_from_license_level() -> void:
	var r := UnitFactory.check_loadout(_db(), "mf_raleigh", {"mounts": []}, {"ll": 1, "licenses": {"mf_raleigh": 2}})
	expect(not r.ok, "2 ranks at LL1")
	expect_eq(r.rule_ref, UnitFactory.REF_LICENSE_RANKS)
	expect(not UnitFactory.check_loadout(_db(), "mf_standard_pattern_i_everest", {}, {"ll": 13}).ok, "LL above 12")


func test_talent_gear_needs_the_talent() -> void:
	var loadout := {"mounts": [{"weapons": ["mw_fuel_rod_gun"]}], "systems": []}
	expect(not UnitFactory.check_loadout(_db(), "mf_standard_pattern_i_everest", loadout, {"ll": 3}).ok)
	expect(UnitFactory.check_loadout(_db(), "mf_standard_pattern_i_everest", loadout, {"ll": 3, "talents": {"t_nuclear_cavalier": 3}}).ok)


func test_grit_comes_from_license_level() -> void:
	expect_eq(UnitFactory.grit(0), 0)
	expect_eq(UnitFactory.grit(1), 1)
	expect_eq(UnitFactory.grit(12), 6)
	var u := UnitFactory.build_mech(_db(), "p", "mf_standard_pattern_i_everest", {}, {"ll": 5})
	expect_eq(u.grit, 3)
	expect_eq(u.save_target, 10 + 3)
