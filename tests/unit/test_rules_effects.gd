extends TestCase
## Frame traits, core systems and NPC features through the effects system.

const F = preload("res://tests/unit/test_rules_fixtures.gd")

static var _db: ContentDB

var s: GameState
var e: RulesEngine


func db() -> ContentDB:
	if _db == null:
		_db = ContentDB.new()
		_db.load_all()
	return _db


## A frame from lancer-data at `cell` with an assault rifle in its first mount.
func _frame(id: String, frame: String, side: String, cell: Vector2i) -> Unit:
	var u := UnitFactory.build_mech(db(), id, frame, {"mounts": [{"weapons": ["mw_assault_rifle"]}]})
	u.side = side
	u.cell = cell
	s.add_unit(u)
	return u


func _setup() -> void:
	s = F.state()
	e = RulesEngine.new()


func _next_turn(u: Unit) -> void:
	if s.active_unit != "":
		F.act(e, s, "end_turn", s.active_unit)
	s.acted = PackedStringArray()
	s.turn_side = u.side
	if s.phase != GameState.PHASE_COMBAT:
		e.submit(s, {"type": "start_combat", "params": {"first_side": u.side}})
		s.turn_side = u.side
	F.act(e, s, "start_turn", u.id)


func _labels(sources: Array) -> Array:
	return sources.map(func(x: Dictionary) -> String: return x["label"])


func test_everest_traits_are_listed_and_initiative_is_a_free_quick_action() -> void:
	_setup()
	var ev := _frame("ev", "mf_standard_pattern_i_everest", "players", Vector2i(0, 0))
	F.mech(s, "t", "enemies", Vector2i(5, 0))
	var traits: Array = ev.loadout["traits"]
	expect_eq(traits.size(), 2)
	expect(traits[0]["automated"] and not traits[1]["automated"], "Initiative automated, Replaceable Parts (resting) not")
	_next_turn(ev)
	F.act(e, s, "lock_on", "ev", {"target": "t"})
	F.act(e, s, "boost", "ev", {"to": [1, 0]})
	expect(not F.ok(F.act(e, s, "hide", "ev")), "out of quick actions")
	var out := F.act(e, s, "scan", "ev", {"target": "t", "free_via": "initiative"})
	expect(F.ok(out), F.reason(out))
	expect(not F.ok(F.act(e, s, "invade", "ev", {"target": "t", "free_via": "initiative"})), "1/scene")


func test_everest_core_power_protocol() -> void:
	_setup()
	var ev := _frame("ev", "mf_standard_pattern_i_everest", "players", Vector2i(0, 0))
	F.mech(s, "t", "enemies", Vector2i(5, 0))
	_next_turn(ev)
	var out := F.act(e, s, "core_power", "ev")
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "core_power")[0]["core"], "Hyperspec Fuel Injector")
	var p := RulesQueries.attack_preview(s, "ev", "0:0", "t")
	expect(_labels(p["sources"]).has("Hyperspec Fuel Injector"))
	expect_eq(p["accuracy"], 1)
	var check := Combat.skill_check(s, ev, "hull", "test")
	expect(_labels(check["sources"]).has("Hyperspec Fuel Injector"), "+1 Accuracy on checks too")
	F.act(e, s, "boost", "ev", {"to": [1, 0]})
	expect(F.ok(F.act(e, s, "boost", "ev", {"to": [2, 0], "free_via": "hyperspec_boost"})), "Boost as a free action")
	expect(not F.ok(F.act(e, s, "boost", "ev", {"to": [3, 0], "free_via": "hyperspec_boost"})), "1/turn")
	_next_turn(ev)
	expect(F.ok(F.act(e, s, "boost", "ev", {"to": [3, 0], "free_via": "hyperspec_boost"})), "next turn again")
	expect(not F.ok(F.act(e, s, "core_power", "ev")), "one Core Power")


func test_protocol_only_at_start_of_turn() -> void:
	_setup()
	var ev := _frame("ev", "mf_standard_pattern_i_everest", "players", Vector2i(0, 0))
	_next_turn(ev)
	F.act(e, s, "move", "ev", {"to": [1, 0]})
	expect(not F.ok(F.act(e, s, "core_power", "ev")))


func test_drake_heavy_frame_blast_plating_guardian_and_slow() -> void:
	_setup()
	var drake := _frame("dr", "mf_drake", "enemies", Vector2i(4, 0))
	var small := F.mech(s, "small", "players", Vector2i(3, 0), 0.5)
	_next_turn(small)
	F.load_dice(s, [15])
	var out := F.act(e, s, "ram", "small", {"target": "dr"})
	expect(not F.ok(out), "Ram needs the target to be your Size or smaller")
	# Blast Plating: resistance to area damage only.
	var before := drake.hp
	Combat.deal_damage(s, drake, [{"type": "Kinetic", "amount": 6}], {"area": true})
	expect_eq(before - drake.hp, 2, "6 - Armor 2 = 4, halved")
	# Slow: Difficulty on Agility saves.
	var save := Combat.skill_check(s, drake, "agility", "test", 10, 0, 0, [], true)
	expect(_labels(save["sources"]).has("Slow"))
	# Guardian: an ally next to the Drake gets hard cover from it.
	var ally := F.mech(s, "ally", "enemies", Vector2i(5, 0))
	small.cell = Vector2i(9, 0)
	var c := RulesQueries.cover(s, "small", "ally")
	expect_eq(c["cover"], "none", "the Drake is on the far side")
	ally.cell = Vector2i(3, 0)
	small.cell = Vector2i(6, 0)
	expect_eq(RulesQueries.cover(s, "small", "ally")["cover"], "hard", "now the Drake stands between")


func test_heavy_frame_stops_knockback_from_smaller() -> void:
	_setup()
	var drake := _frame("dr", "mf_drake", "enemies", Vector2i(4, 0))
	var small := F.mech(s, "small", "players", Vector2i(3, 0), 0.5)
	var ev := Attacks.knock_back(s, drake, small.cell, 2, small)
	expect_eq(ev[0]["type"], "knockback_blocked")
	expect_eq(drake.cell, Vector2i(4, 0))


func test_vlad_shrike_armor_hurts_close_attackers() -> void:
	_setup()
	var vlad := _frame("vl", "mf_vlad", "enemies", Vector2i(2, 0))
	var a := F.mech(s, "a", "players", Vector2i(0, 0))
	_next_turn(a)
	F.load_dice(s, [2])
	F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "vl"})
	expect_eq(a.hp, 9, "1 AP kinetic before the attack")
	expect_eq(vlad.hp, vlad.max_hp)


func test_raleigh_shoots_while_jammed_and_reloads_when_idle() -> void:
	_setup()
	var r := UnitFactory.build_mech(db(), "ra", "mf_raleigh", {})
	r.cell = Vector2i(0, 0)
	r.loadout["weapons"].append(F.weapon("9:0", "Cannon", "Main", "Cannon", "1d6", 10, [{"id": "tg_loading"}]))
	s.add_unit(r)
	F.mech(s, "t", "enemies", Vector2i(4, 0))
	_next_turn(r)
	r.statuses["Jammed"] = {"source": "x"}
	F.load_dice(s, [2])
	expect(F.ok(F.act(e, s, "skirmish", "ra", {"weapon": "9:0", "target": "t"})), "Shielded Magazines")
	r.statuses.erase("Jammed")
	_next_turn(r)
	expect(not Weapons.state_of(r, Weapons.find(r, "9:0"))["loaded"])
	F.act(e, s, "end_turn", "ra")
	expect(Weapons.state_of(r, Weapons.find(r, "9:0"))["loaded"], "Full Metal Jacket: no attacks, reload")


func test_dusk_wing_hovers_and_is_invisible_on_its_turn() -> void:
	_setup()
	var dw := _frame("dw", "mf_dusk_wing", "players", Vector2i(0, 0))
	expect_eq(dw.flight, "hover")
	_next_turn(dw)
	expect(dw.has_status("Invisible"))
	F.act(e, s, "end_turn", "dw")
	expect(not dw.has_status("Invisible"))


func test_balor_regenerates_and_genghis_vents() -> void:
	_setup()
	var balor := _frame("ba", "mf_balor", "players", Vector2i(0, 0))
	balor.hp = 2
	_next_turn(balor)
	F.act(e, s, "end_turn", "ba")
	expect_eq(balor.hp, 2 + balor.max_hp / 4)
	var g := _frame("ge", "mf_genghis", "players", Vector2i(3, 3))
	g.heat = 4
	g.hp = 1
	F.load_dice(s, [6])
	Combat.deal_damage(s, g, [{"type": "Kinetic", "amount": 5}])
	expect_eq(g.heat, 0, "Emergency Vent on structure damage")
	expect_eq(g.burn, 0)
	Combat.deal_damage(s, g, [{"type": "Burn", "amount": 3}])
	expect_eq(g.burn, 0, "Insulated: immune to burn")


func test_saladin_immune_to_shredded_and_deaths_head_bonus() -> void:
	_setup()
	var sa := _frame("sa", "mf_saladin", "players", Vector2i(0, 0))
	Combat.add_status(s, sa, "Shredded", "x")
	expect(not sa.has_status("Shredded"))
	var dh := _frame("dh", "mf_deaths_head", "players", Vector2i(0, 2))
	F.mech(s, "t", "enemies", Vector2i(5, 2))
	var p := RulesQueries.attack_preview(s, "dh", "0:0", "t")
	expect_eq(p["bonus"], 1, "Perfected Targeting +1")
	expect(_labels(p["bonus_sources"]).has("Perfected Targeting"))


func test_tiered_placeholder_npcs() -> void:
	var templates := UnitFactory.npc_templates()
	for id in ["ph_grunt", "ph_assault", "ph_artillery", "ph_brawler", "ph_controller", "ph_support"]:
		expect(templates.has(id), id)
		expect(templates[id].get("placeholder", false), id + " is labeled placeholder")
	var g2 := UnitFactory.build_npc("g", templates["ph_grunt"], 2)
	expect_eq(g2.hp, 8)
	expect_eq(g2.loadout["tier"], 2)
	var w: Dictionary = g2.loadout["weapons"][0]
	expect_eq(w["damage"][0]["val"], "1d6+1")
	expect_eq(w["attack_bonus"], 2)
	expect_eq(g2.loadout["effects"][0]["label"], "Squad Drill")
	var art := UnitFactory.build_npc("art", templates["ph_artillery"], 1)
	expect_eq(Weapons.area(art.loadout["weapons"][0]), "Blast")
	var sup := UnitFactory.build_npc("sup", templates["ph_support"], 3)
	expect(Effects.has(sup, "guardian"))
	expect(not sup.loadout["traits"][1]["automated"], "Field Patch is manual")
