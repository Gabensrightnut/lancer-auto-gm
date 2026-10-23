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


func _mech_with(id: String, cell: Vector2i, mounts: Array, systems: Array = []) -> Unit:
	var u := UnitFactory.build_mech(db(), id, "mf_standard_pattern_i_everest", {"mounts": mounts, "systems": systems}, {"ll": 12})
	u.side = "players"
	u.cell = cell
	s.add_unit(u)
	return u


func test_autopod() -> void:
	_setup([], Vector2i(6, 0))
	var pod := _mech_with("pod", Vector2i(0, 3), [{"weapons": ["mw_autopod"]}])
	expect(not F.ok(F.act(e, s, "skirmish", "pod", {"weapon": "0:0", "target": "t"})), "only through its reaction")
	t.statuses["Lock On"] = {"source": "a"}
	F.load_dice(s, [5, 1, 2])  # d20 (+6 Grit at LL12), Lock On's Accuracy die, damage
	F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t", "use_lock_on": true})
	expect_eq(t.hp, 40 - 2 - 3, "the Autopod hits automatically for 3")


func test_vorpal_gun() -> void:
	_setup([], Vector2i(3, 0))
	var vorpal := _mech_with("v", Vector2i(2, 2), [{"weapons": ["mw_vorpal_gun"]}])
	F.act(e, s, "end_turn", "a")
	F.act(e, s, "start_turn", "t")
	F.load_dice(s, [15, 2, 15, 3, 3])
	var out := F.act(e, s, "skirmish", "t", {"weapon": "0:0", "target": "a"})
	expect_eq(F.events_of(out, "attack_rolled").filter(func(x: Dictionary) -> bool: return x["attacker"] == "v").size(), 1, "Snicker-Snack")


func test_monitor_module() -> void:
	_setup(["ms_monitor_module"], Vector2i(4, 0))
	var ally := F.mech(s, "ally", "players", Vector2i(1, 0))
	F.load_dice(s, [2])
	var out := F.act(e, s, "activate", "a", {"ability": _key("Monitor Module"), "target": "ally"})
	expect(F.ok(out), F.reason(out))
	F.act(e, s, "end_turn", "a")
	F.act(e, s, "start_turn", "t")
	F.load_dice(s, [15, 2, 5, 4])  # the reaction: 5 + 6 Grit hits without a crit
	out = F.act(e, s, "skirmish", "t", {"weapon": "0:0", "target": "ally"})
	expect_eq(t.hp, 38, "the Gorgon's half-damage Skirmish")


func test_gravity_gun() -> void:
	_setup([], Vector2i(5, 1))
	a.loadout["weapons"] = [{"key": "0:0", "id": "mw_gravity_gun", "name": "Gravity Gun", "mount": 0, "size": "Heavy", "type": "Rifle", "damage": [],
		"range": [{"type": "Range", "val": 8}, {"type": "Blast", "val": 3}], "tags": []}]
	F.load_dice(s, [4, 3])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "aim": [6, 0]})
	expect(F.ok(out), F.reason(out))
	expect_eq(t.hp, 36, "failed the Hull save: 1d6 energy")


func test_fade_cloak() -> void:
	_setup(["ms_fade_cloak"], Vector2i(3, 0))
	var out := F.act(e, s, "activate", "a", {"ability": _key("FADE Cloak")})
	expect(F.ok(out), F.reason(out))
	expect(not F.ok(F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})), "can't attack while intangible")
	F.act(e, s, "end_turn", "a")
	F.act(e, s, "start_turn", "t")
	expect(not F.ok(F.act(e, s, "skirmish", "t", {"weapon": "0:0", "target": "a"})), "can't be attacked")
	F.act(e, s, "end_turn", "t")
	s.acted = PackedStringArray()
	s.turn_side = "players"
	F.load_dice(s, [2])
	F.act(e, s, "start_turn", "a")
	expect(not GearSystems.intangible(a), "rolled 3 or less: back in realspace this turn")


func test_pinaka_delayed() -> void:
	_setup([], Vector2i(8, 0))
	a.loadout["weapons"] = [{"key": "0:0", "id": "mw_pinaka_missiles", "name": "Pinaka Missiles", "mount": 0, "size": "Heavy", "type": "Launcher",
		"damage": [{"type": "Explosive", "val": "2d6"}], "range": [{"type": "Range", "val": 15}, {"type": "Blast", "val": 1}], "tags": [{"id": "tg_arcing"}]}]
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "aims": [[8, 0]], "delayed": true})
	expect(F.ok(out), F.reason(out))
	expect_eq(Zones.of_kind(s, "pinaka_strike").size(), 1, "the target area is marked")
	expect(a.has_status("Slowed"))
	var round := s.round_number
	F.act(e, s, "end_turn", "a")
	F.act(e, s, "start_turn", "t")
	F.act(e, s, "end_turn", "t")
	expect_eq(t.hp, 40, "not yet: it lands at the end of the next round")
	F.act(e, s, "start_turn", "a")
	F.act(e, s, "end_turn", "a")
	F.act(e, s, "start_turn", "t")
	F.load_dice(s, [15, 6, 6, 6])
	F.act(e, s, "end_turn", "t")
	expect_eq(s.round_number, round + 2)
	expect(t.hp < 40, "landed: 3d6 explosive")
	expect(Zones.of_kind(s, "pinaka_strike").is_empty())


func test_terrify_and_reactive_weave() -> void:
	_setup(["ms_hunter_logic_suite", "ms_reactive_weave"], Vector2i(4, 0))
	t.statuses["Impaired"] = {"source": "a"}
	t.counters["terrified_of"] = "a"
	F.act(e, s, "end_turn", "a")
	F.act(e, s, "start_turn", "t")
	expect(not F.ok(F.act(e, s, "move", "t", {"to": [3, 0]})), "Terrify: no moving closer")
	expect(F.ok(F.act(e, s, "move", "t", {"to": [5, 0]})), "away is fine")
	var hp := a.hp
	Reactions.brace(s, a, "t", [0, 3])
	expect_eq(a.cell, Vector2i(0, 3), "Reactive Weave: a move after Bracing")
	expect(a.has_status("Invisible"))


func test_dragging_and_towing() -> void:
	_setup(["ms_cable_winch_system"], Vector2i(1, 0))
	t.side = "players"
	var out := F.act(e, s, "drag", "a", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	expect(a.has_status("Slowed"), "Slowed while dragging")
	expect(not Reactions.can_react(a, "overwatch", s).ok, "no reactions while dragging")
	F.act(e, s, "move", "a", {"to": [0, 3]})
	expect(Sight.unit_distance(s, a, t) <= 1, "it follows")
	F.act(e, s, "release_drag", "a")
	expect(not a.has_status("Slowed"))
	var big := F.mech(s, "big", "enemies", Vector2i(1, 4), 3.0)
	expect(not F.ok(F.act(e, s, "drag", "a", {"target": "big"})), "up to twice your Size")


func test_grapple_swing() -> void:
	_setup(["ms_reinforced_cabling"], Vector2i(9, 9))
	for x in range(0, 6):
		for y in range(0, 3):
			if Vector2i(x, y) != Vector2i(0, 0):
				s.map.set_column(Vector2i(x, y), 0, PackedStringArray([BattleMap.TAG_DIFFICULT]))  # deep mud
	expect(not F.ok(F.act(e, s, "move", "a", {"to": [3, 0]})), "too far through the mud on foot")
	var out := F.act(e, s, "move", "a", {"to": [3, 0], "swing": true})
	expect(F.ok(out), F.reason(out))
	expect(not a.flying, "landed on a surface")
	expect(not F.ok(F.act(e, s, "move", "a", {"to": [3, 2], "swing": true})), "once per turn")


func test_lifting_and_flying_carry_limit() -> void:
	_setup([], Vector2i(1, 0))
	t.side = "players"
	var out := F.act(e, s, "drag", "a", {"target": "t", "lift": true})
	expect(F.ok(out), F.reason(out))
	expect(a.has_status("Immobilized"), "Immobilized while lifting")
	F.act(e, s, "release_drag", "a")
	expect(not a.has_status("Immobilized"))
	var big := F.mech(s, "big", "players", Vector2i(0, 1), 2.0)
	expect(not F.ok(F.act(e, s, "drag", "a", {"target": "big", "lift": true})), "lift only your Size or smaller")
	a.flight = "flight"
	F.act(e, s, "drag", "a", {"target": "t"})
	expect(not F.ok(F.act(e, s, "move", "a", {"to": [0, 3], "fly": true})), "flying carries at most Size 1/2")


func test_ghast_nexus_drone() -> void:
	_setup([], Vector2i(11, 0))
	s.units.erase("a")
	a = UnitFactory.build_mech(db(), "a", "mf_standard_pattern_i_everest", {"mounts": [{"weapons": []}, {"weapons": []}, {"weapons": ["mw_ghast_nexus"]}], "systems": []}, {"ll": 12})
	a.side = "players"
	s.add_unit(a)
	s.active_unit = "a"
	a.turn = {"quick": 0, "full": false, "taken": [], "quick_tech": [], "move_spent": 0, "moved": false, "acted": false, "overcharged": false, "free_quick": 0}
	var key: String = Weapons.find(a, "2:0")["key"]
	expect(not F.ok(F.act(e, s, "skirmish", "a", {"weapon": key, "target": "t"})), "11 away: out of Range 10")
	var out := F.act(e, s, "activate", "a", {"ability": _key("Deploy Ghast Drone"), "to": [6, 0]})
	expect(F.ok(out), F.reason(out))
	expect(F.ok(F.act(e, s, "skirmish", "a", {"weapon": key, "target": "t"})), "Range traced from the drone")


func test_dimensional_emblems_and_shackles() -> void:
	_setup(["ms_h0r_os_system_upgrade_iii"], Vector2i(4, 4))
	F.load_dice(s, [19])
	var out := F.act(e, s, "activate", "a", {"ability": _key("Dimensional Emblems"), "target": "t"})
	expect(F.ok(out), F.reason(out))
	expect_eq(Zones.of_kind(s, "emblem").size(), 3, "three constructs around the target")
	F.act(e, s, "end_turn", "a")
	s.acted = PackedStringArray()
	s.turn_side = "players"
	F.act(e, s, "start_turn", "a")
	F.load_dice(s, [19])
	out = F.act(e, s, "activate", "a", {"ability": _key("Celestial Shackles"), "target": "t"})
	expect(F.ok(out), F.reason(out))
	t.cell = Vector2i(8, 8)
	out = F.act(e, s, "shackle_return", "a", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	expect_eq(t.cell, Vector2i(4, 4), "pulled back to its marked space")


func test_puppet_system_and_law_of_blades() -> void:
	_setup(["ms_h0r_os_system_upgrade_i", "ms_law_of_blades"], Vector2i(4, 0))
	var other := F.mech(s, "o", "enemies", Vector2i(6, 0))
	F.load_dice(s, [19])
	var out := F.act(e, s, "activate", "a", {"ability": _key("Puppet System"), "target": "t", "toward": [4, 5]})
	expect(F.ok(out), F.reason(out))
	expect_eq(t.cell, Vector2i(4, 4), "moves its full Speed where you choose")
	F.act(e, s, "end_turn", "a")
	s.acted = PackedStringArray()
	s.turn_side = "players"
	F.act(e, s, "start_turn", "a")
	t.cell = Vector2i(5, 0)
	F.load_dice(s, [19, 15, 3])
	out = F.act(e, s, "activate", "a", {"ability": _key("Predator/Prey Concepts"), "target": "t", "forced_target": "o"})
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "attack_rolled").filter(func(x: Dictionary) -> bool: return x["attacker"] == "t" and x["target"] == "o").size(), 1, "it shoots its friend")


func test_metahook_shares_heat_and_systems() -> void:
	_setup(["ms_metahook"], Vector2i(9, 9))
	var ally := F.mech(s, "ally", "players", Vector2i(0, 2))
	a.systems = 4
	var out := F.act(e, s, "activate", "a", {"ability": _key("Metahook"), "target": "ally"})
	expect(F.ok(out), F.reason(out))
	var check := Combat.skill_check(s, ally, "systems", "test", 10)
	expect_eq(check["bonus"], 4, "the ally uses the Goblin's Systems")
	Combat.apply_heat(s, ally, 2, "test")
	expect_eq(a.heat, 2, "heat is shared")
	Combat.add_status(s, a, "Jammed", "test")
	expect(ally.has_status("Jammed"), "conditions are shared")


func test_sisyphus() -> void:
	_setup(["ms_sisyphus_class_nhp"], Vector2i(4, 0))
	F.load_dice(s, [19, 2])
	var out := F.act(e, s, "activate", "a", {"ability": _key("Bend Probability")})
	expect(F.ok(out), F.reason(out))
	expect_eq(a.counters["bent"], [19, 2])
	F.act(e, s, "end_turn", "a")
	F.act(e, s, "start_turn", "t")
	F.load_dice(s, [18, 3])  # t would hit a (18 vs Evasion 8)...
	out = F.act(e, s, "skirmish", "t", {"weapon": "0:0", "target": "a"})
	var roll: Dictionary = F.events_of(out, "attack_rolled")[0]
	expect_eq(roll["result"], "miss", "...but the Goblin's 2 replaces the d20")
	expect_eq(int(a.counters["bent_uses"]), 1)
	var check := Combat.skill_check(s, t, "hull", "test", 10)
	expect(check.get("reroll_source", "") == "", "a reaction per turn: no second use this turn")


func test_mesmer_beacon_and_mimic_mesh() -> void:
	_setup(["ms_mesmer_charges", "ms_mimic_mesh"], Vector2i(4, 0))
	var ally := F.mech(s, "ally", "players", Vector2i(0, 4))
	F.load_dice(s, [3])
	var out := F.act(e, s, "activate", "a", {"ability": _key("Mesmer Beacon"), "target": "t"})
	expect(F.ok(out), F.reason(out))
	out = F.act(e, s, "activate", "a", {"ability": _key("Activate Mimic Mesh"), "target": "ally"})
	expect(F.ok(out), F.reason(out))
	F.act(e, s, "end_turn", "a")
	F.act(e, s, "start_turn", "t")
	expect(not F.ok(F.act(e, s, "move", "t", {"to": [6, 0]})), "mesmerized: only toward the Minotaur")
	expect(F.ok(F.act(e, s, "move", "t", {"to": [3, 1]})), "toward is fine")
	F.load_dice(s, [2])
	out = F.act(e, s, "skirmish", "t", {"weapon": "0:0", "target": "ally"})
	expect(Sight.unit_distance(s, a, ally) < 4, "Battlefield Awareness: moved toward the ally first")


func test_guide_the_flock_and_annihilation_secondary() -> void:
	_setup(["ms_puppetmaster"], Vector2i(9, 9))
	var drone := F.mech(s, "d", "enemies", Vector2i(3, 3), 0.5)
	drone.kind = Unit.KIND_DEPLOYABLE
	drone.counters["deploy_type"] = "Drone"
	var out := F.act(e, s, "activate", "a", {"ability": _key("Guide the Flock"), "moves": [{"drone": "d", "to": [6, 3]}]})
	expect(F.ok(out), F.reason(out))
	expect_eq(drone.cell, Vector2i(6, 3), "anyone's drone, up to 4 spaces")
	s.units.erase("a")
	a = UnitFactory.build_mech(db(), "a", "mf_standard_pattern_i_everest", {"mounts": [{"weapons": []}, {"weapons": []}, {"weapons": ["mw_annihilation_nexus"]}], "systems": []}, {"ll": 12})
	a.side = "players"
	s.add_unit(a)
	s.active_unit = "a"
	a.turn = {"quick": 0, "full": false, "taken": [], "quick_tech": [], "move_spent": 0, "moved": false, "acted": false, "overcharged": false, "free_quick": 0}
	var key := _key("Annihilation Nexus Secondary Attack")
	expect(key != "", "the weapon's protocol")
	expect(not F.ok(F.act(e, s, "activate", "a", {"ability": key})), "only after attacking with it last turn")
	a.counters["annihilation_round"] = s.round_number - 1
	t.cell = Vector2i(1, 1)
	F.load_dice(s, [15, 3])
	out = F.act(e, s, "activate", "a", {"ability": key})
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "area_attack").size(), 1, "the second Burst")


func test_perimeter_command_plate_and_assassin_drone() -> void:
	_setup(["ms_perimeter_command_plate", "ms_assassin_drone"], Vector2i(6, 0))
	var out := F.act(e, s, "activate", "a", {"ability": _key("Print Perimeter Command Plate"), "aim": [3, 0], "setting": "attract"})
	expect(F.ok(out), F.reason(out))
	expect_eq(Zones.of_kind(s, "pcp").size(), 1)
	out = F.act(e, s, "activate", "a", {"ability": _key("Deploy Assassin Drone"), "to": [0, 1], "aim": [5, 4]})
	expect(F.ok(out), F.reason(out))
	expect_eq(Zones.of_kind(s, "assassin").size(), 1, "the drone's Blast 2 area")
	F.act(e, s, "end_turn", "a")
	F.act(e, s, "start_turn", "t")
	F.load_dice(s, [3])
	F.act(e, s, "move", "t", {"to": [4, 0]})
	expect(t.has_status("Immobilized"), "Attract: failed Hull save")
	t.statuses.erase("Immobilized")
	t.cell = Vector2i(9, 4)
	t.turn["move_spent"] = 0
	F.load_dice(s, [15])
	out = F.act(e, s, "move", "t", {"to": [7, 4]})
	expect_eq(t.hp, 37, "Area Denial: 3 kinetic as it entered the area")


func test_false_idol() -> void:
	_setup(["ms_h0r_os_system_upgrade_ii"], Vector2i(4, 0))
	var out := F.act(e, s, "activate", "a", {"ability": _key("Deploy Construct Other: False Idol"), "to": [3, 3]})
	expect(F.ok(out), F.reason(out))
	F.act(e, s, "end_turn", "a")
	F.act(e, s, "start_turn", "t")
	F.load_dice(s, [3])  # the Systems save fails
	out = F.act(e, s, "skirmish", "t", {"weapon": "0:0", "target": "a"})
	expect(F.ok(out))
	expect_eq(F.events_of(out, "attack_rolled").size(), 0, "fooled: no attack on the real Goblin")
	expect(not t.turn.get("taken", []).has("skirmish"), "it doesn't lose the action")
	expect(not F.ok(F.act(e, s, "skirmish", "t", {"weapon": "0:0", "target": "a"})), "can't target the real one now")


func test_mimic_gun() -> void:
	_setup([], Vector2i(4, 0))
	s.units.erase("a")
	a = UnitFactory.build_mech(db(), "a", "mf_standard_pattern_i_everest", {"mounts": [{"weapons": []}, {"weapons": []}, {"weapons": ["mw_mimic_gun"]}], "systems": []}, {"ll": 12})
	a.side = "players"
	s.add_unit(a)
	var w := Weapons.find(a, "2:0")
	F.load_dice(s, [8, 12, 3])
	GearSystems.mimic_roll(s, a)
	expect_eq(Weapons.range_for(a, w), 8, "X")
	expect_eq(WeaponRules.damage_override(a, w, t)[0]["val"], "5", "1 + half of 8")
	GearSystems.mimic_cycle(a)
	expect_eq(Weapons.range_for(a, w), 12, "then Y")


func test_daisy_cutter_plasma_fuel_rod_and_latch() -> void:
	_setup([], Vector2i(3, 0))
	a.loadout["weapons"] = [
		{"key": "0:0", "id": "mw_daisy_cutter", "name": "Daisy Cutter", "mount": 0, "size": "Heavy", "type": "CQB", "damage": [{"type": "Kinetic", "val": "3d6"}], "range": [{"type": "Cone", "val": 7}], "tags": []},
		{"key": "1:0", "id": "mw_plasma_thrower", "name": "Plasma Thrower", "mount": 1, "size": "Heavy", "type": "Cannon", "damage": [{"type": "Energy", "val": "1d6+2"}], "range": [{"type": "Cone", "val": 7}], "tags": []},
		{"key": "2:0", "id": "mw_fuel_rod_gun", "name": "Fuel Rod Gun", "mount": 2, "size": "Main", "type": "CQB", "damage": [{"type": "Energy", "val": "1d3+2"}], "range": [{"type": "Range", "val": 3}], "tags": []},
		{"key": "3:0", "id": "mw_lancaster_integrated", "name": "Latch Drone", "mount": 3, "size": "Main", "type": "Launcher", "damage": [], "range": [{"type": "Range", "val": 8}], "tags": []}]
	F.load_dice(s, [1, 1, 1, 1])
	F.act(e, s, "skirmish", "a", {"weapon": "0:0", "aim": [3, 0]})
	expect(Zones.of_kind(s, "smoke").size() >= 1, "Daisy Cutter: smoke in the cone")
	_next(a)
	F.load_dice(s, [1, 1])
	F.act(e, s, "skirmish", "a", {"weapon": "1:0", "aim": [3, 0]})
	expect_eq(Zones.of_kind(s, "flames").size(), 1, "Plasma Thrower: flames left behind")
	_next(a)
	a.heat = 5
	F.load_dice(s, [1])
	F.act(e, s, "skirmish", "a", {"weapon": "2:0", "target": "t"})
	expect_eq(a.heat, 1, "Fuel Rod Gun: clear 4 heat")
	_next(a)
	var ally := F.mech(s, "ally", "players", Vector2i(0, 4))
	ally.hp = 2
	a.repairs = 2
	F.load_dice(s, [10])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "3:0", "target": "ally"})
	expect(F.ok(out), F.reason(out))
	expect_eq(ally.hp, 7, "Latch Drone: half its HP back for 1 Repair")
	expect_eq(a.repairs, 1)
