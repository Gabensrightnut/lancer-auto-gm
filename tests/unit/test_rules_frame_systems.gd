extends TestCase
## Core systems and traits with their own state (FrameSystems): Blackbeard, Balor, Lancaster,
## Minotaur, Napoleon, Drake, Manticore, Sherman, Barbarossa, Iskander.

const F = preload("res://tests/unit/test_rules_fixtures.gd")

static var _db: ContentDB

var s: GameState
var e: RulesEngine


func db() -> ContentDB:
	if _db == null:
		_db = ContentDB.new()
		_db.load_all()
	return _db


func _frame(id: String, frame: String, side: String, cell: Vector2i, systems: Array = []) -> Unit:
	var u := UnitFactory.build_mech(db(), id, frame, {"mounts": [{"weapons": ["mw_assault_rifle"]}], "systems": systems})
	u.side = side
	u.cell = cell
	s.add_unit(u)
	return u


func _setup() -> void:
	s = F.state()
	e = RulesEngine.new()


func _turn(u: Unit, new_round: bool = false) -> void:
	if s.active_unit != "":
		F.act(e, s, "end_turn", s.active_unit)
	if s.phase != GameState.PHASE_COMBAT:
		e.submit(s, {"type": "start_combat", "params": {"first_side": "players"}})
	if new_round:
		s.round_number += 1
	s.acted = PackedStringArray()
	s.turn_side = u.side
	F.act(e, s, "start_turn", u.id)


func _ability(u: Unit, name: String) -> String:
	for a: Dictionary in Abilities.all(u):
		if a["name"] == name:
			return a["key"]
	return ""


func test_blackbeard_omni_harpoon() -> void:
	_setup()
	var bb := _frame("bb", "mf_blackbeard", "players", Vector2i(0, 0))
	var t := F.mech(s, "t", "enemies", Vector2i(4, 0))
	var t2 := F.mech(s, "t2", "enemies", Vector2i(0, 4))
	_turn(bb)
	F.load_dice(s, [3, 4, 5, 15])  # 2d6 = 7; t fails its Hull save, t2 saves
	var out := F.act(e, s, "core_power", "bb", {"targets": ["t", "t2"]})
	expect(F.ok(out), F.reason(out))
	expect_eq(t.hp, 3)
	expect(t.has_status("Prone"))
	expect(t.has_status("Immobilized"))
	expect_eq(Sight.unit_distance(s, bb, t), 1, "pulled adjacent")
	expect_eq(t2.hp, 6, "a success: half damage, nothing else")
	expect(not t2.has_status("Prone"))
	expect_eq(t2.cell, Vector2i(0, 4))


func test_blackbeard_grapple_cable() -> void:
	_setup()
	var bb := _frame("bb", "mf_blackbeard", "players", Vector2i(0, 0))
	var t := F.mech(s, "t", "enemies", Vector2i(4, 0))
	_turn(bb)
	F.load_dice(s, [15])
	var out := F.act(e, s, "grapple", "bb", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	expect_eq(bb.cell, Vector2i(3, 0), "pulled to the target")
	expect(bb.counters.has("grapple"))


func test_balor_hive_frenzy() -> void:
	_setup()
	var bal := _frame("bal", "mf_balor", "enemies", Vector2i(6, 0))
	var a := F.mech(s, "a", "players", Vector2i(0, 0))
	_turn(bal)
	expect(F.ok(F.act(e, s, "core_power", "bal")))
	expect(bal.has_status("Shredded"))
	_turn(a, true)
	var p := RulesQueries.attack_preview(s, "a", "0:0", "bal")
	expect_eq(p["cover"]["cover"], "soft", "the swarm gives soft cover")
	bal.hp = 1
	var st := bal.structure
	F.load_dice(s, [6])
	Combat.deal_damage(s, bal, [{"type": "Kinetic", "amount": 5}], {"ap": true})
	expect_eq(bal.structure, st, "a 6: no structure damage")
	expect_eq(bal.hp, 1)
	Combat.deal_damage(s, bal, [{"type": "Kinetic", "amount": 5}], {"ap": true})
	expect_eq(bal.hp, 1, "immune to damage until the end of the turn")


func test_lancaster_supercharger() -> void:
	_setup()
	var lan := _frame("lan", "mf_lancaster", "players", Vector2i(0, 0))
	var ally := _frame("al", "mf_standard_pattern_i_everest", "players", Vector2i(3, 0))
	_turn(lan)
	var out := F.act(e, s, "core_power", "lan", {"target": "al"})
	expect(F.ok(out), F.reason(out))
	expect(Effects.immune_to_status(ally, "Jammed"))
	expect_eq(Effects.accuracy_sources(ally, ["save"], "hull").size(), 1, "+1 Accuracy on saves")
	_turn(ally, true)
	_turn(lan)
	expect_eq(lan.heat, 1, "1 heat at the start of each of its turns")
	Combat.add_status(s, ally, "Stunned", "x")
	expect(not Effects.immune_to_status(ally, "Jammed"), "ends if either is Stunned")


func test_minotaur_maze() -> void:
	_setup()
	var mino := _frame("mino", "mf_minotaur", "players", Vector2i(0, 0))
	var t := F.mech(s, "t", "enemies", Vector2i(5, 0))
	_turn(mino)
	var out := F.act(e, s, "core_power", "mino", {"target": "t"})
	expect(F.ok(out), F.reason(out))
	expect(t.has_status("Stunned"))
	_turn(t, true)
	F.load_dice(s, [12, 4, 1, 1])  # 12 - 4 (worst of three Difficulty dice) = 8: fails
	F.act(e, s, "end_turn", "t")
	expect(t.has_status("Stunned"))
	expect_eq(int(t.counters["maze"]["tries"]), 1)
	_turn(t, true)
	F.load_dice(s, [12, 1, 1])  # +1 Accuracy cancels one Difficulty die: 12 - 1 = 11
	F.act(e, s, "end_turn", "t")
	expect(not t.has_status("Stunned"), "escaped")


func test_napoleon_trueblack_aegis() -> void:
	_setup()
	var nap := _frame("nap", "mf_napoleon", "players", Vector2i(0, 0))
	var t := F.mech(s, "t", "enemies", Vector2i(3, 0))
	nap.statuses["Lock On"] = {"source": "t"}
	_turn(nap)
	expect(F.ok(F.act(e, s, "core_power", "nap")))
	expect(not nap.has_status("Lock On"), "tech effects end")
	var hp := nap.hp
	Combat.deal_damage(s, nap, [{"type": "Kinetic", "amount": 9}], {"ap": true})
	expect_eq(nap.hp, hp - 1, "all damage reduced to 1")
	expect(not F.ok(F.act(e, s, "skirmish", "nap", {"weapon": "0:0", "target": "t"})), "no Skirmish")
	expect(F.ok(F.act(e, s, "move", "nap", {"to": [0, 2]})), "standard moves are fine")
	_turn(t, true)
	expect(not F.ok(F.act(e, s, "lock_on", "t", {"target": "nap"})), "immune to tech actions")


func test_drake_fortress() -> void:
	_setup()
	var dr := _frame("dr", "mf_drake", "players", Vector2i(5, 5))
	var a := F.mech(s, "a", "enemies", Vector2i(5, 0))
	_turn(dr)
	var out := F.act(e, s, "core_power", "dr", {"sections": [[[4, 4], [3, 4]], [[6, 4], [7, 4]]]})
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "deployed").size(), 4)
	expect(dr.has_status("Immobilized"))
	expect(Effects.has(dr, "immovable"))
	_turn(a, true)
	dr.cell = Vector2i(5, 8)
	expect_eq(RulesQueries.attack_preview(s, "a", "0:0", "dr")["cover"]["cover"], "hard", "hard cover even in the open")
	var kb := Attacks.knock_back(s, dr, a.cell, 2, a)
	expect_eq(kb[0]["type"], "knockback_blocked")
	_turn(dr, true)
	out = F.act(e, s, "activate", "dr", {"ability": _ability(dr, "Deactivate Fortress")})
	expect(F.ok(out), F.reason(out))
	expect(not dr.has_status("Immobilized"))
	expect_eq(F.events_of(out, "recalled").size(), 4)


func test_manticore_charge_die_and_lash() -> void:
	_setup()
	var man := _frame("man", "mf_manticore", "enemies", Vector2i(0, 0))
	var t := F.mech(s, "t", "players", Vector2i(2, 0))
	t.max_hp = 20
	t.hp = 20
	_turn(man)
	expect(F.ok(F.act(e, s, "core_power", "man")))
	expect_eq(int(man.counters["charge_die"]), 1)
	Combat.apply_heat(s, man, 1, "test")
	expect_eq(t.hp, 18, "1/round: 2 AP energy to a character within range 3")
	F.load_dice(s, [1, 1, 1, 1, 1, 1, 20, 1])  # inferno 6d6 = 6; the Manticore saves, t fails
	for i in range(4):
		Combat.apply_heat(s, man, 1, "test")
	expect(not man.counters.has("charge_die"), "discharged at 6")
	expect_eq(t.hp, 12)


func test_sherman_zf4_charges_and_vent_heat() -> void:
	_setup()
	var sh := _frame("sh", "mf_sherman", "players", Vector2i(0, 0))
	var zf := Weapons.find(sh, "int:0")
	expect_eq(Weapons.range_value(zf, "Line"), 4, "starts with 1 charge")
	_turn(sh)
	F.act(e, s, "stabilize", "sh", {"main": "cool", "extra": "reload"})
	expect_eq(Weapons.range_value(zf, "Line"), 8, "Stabilize adds a charge")
	expect(Effects.has(sh, "soft_cover_aura"), "Vent Heat: soft cover")
	_turn(sh, true)
	expect(not Effects.has(sh, "soft_cover_aura"), "until the start of its next turn")
	expect(F.ok(F.act(e, s, "core_power", "sh")))
	expect_eq(FrameSystems.zf4_charges(sh), 4, "COREBURN: +3, at most 4")
	F.mech(s, "t", "enemies", Vector2i(0, 5))
	var out := F.act(e, s, "skirmish", "sh", {"weapon": "int:0", "aim": [0, 3]})
	expect(F.ok(out), F.reason(out))
	expect_eq(FrameSystems.zf4_charges(sh), 1, "resets after the attack")


func test_barbarossa_apocalypse_rail() -> void:
	_setup()
	var bar := _frame("bar", "mf_barbarossa", "players", Vector2i(0, 0))
	var t := F.mech(s, "t", "enemies", Vector2i(10, 0))
	t.max_hp = 40
	t.hp = 40
	_turn(bar)
	expect(F.ok(F.act(e, s, "core_power", "bar")))
	var fire := _ability(bar, "Fire Apocalypse Rail")
	expect(not F.ok(F.act(e, s, "activate", "bar", {"ability": fire, "aim": [10, 0]})), "die at 4: can't fire")
	_turn(t, true)
	_turn(bar)
	expect_eq(int(bar.counters["apocalypse"]), 3)
	expect(not F.ok(F.act(e, s, "activate", "bar", {"ability": fire, "aim": [3, 0]})), "not within range 5")
	F.load_dice(s, [15, 6, 6])
	var out := F.act(e, s, "activate", "bar", {"ability": fire, "aim": [10, 0]})
	expect(F.ok(out), F.reason(out))
	expect_eq(t.hp, 28, "Charge Rail 3: 2d6 explosive")
	expect(not F.ok(F.act(e, s, "move", "bar", {"to": [0, 1]})), "nothing else this turn")
	expect_eq(int(bar.counters["apocalypse"]), 4, "the die resets")
	_turn(t, true)
	_turn(bar)
	var mv := F.act(e, s, "move", "bar", {"to": [0, 2]})
	expect(F.ok(mv), F.reason(mv))
	_turn(t, true)
	_turn(bar)
	expect_eq(int(bar.counters["apocalypse"]), 3, "moving reset it to 4 before counting down")


func test_iskander_assault_launcher_and_mine_deployers() -> void:
	_setup()
	var isk := _frame("isk", "mf_iskander", "players", Vector2i(0, 0), ["ms_pattern_b_hex_charges"])
	_turn(isk)
	var mine := _ability(isk, "Deploy Explosive Mine")
	var out := F.act(e, s, "activate", "isk", {"ability": mine, "to": [8, 0], "extra_mines": [[2, 0], [2, 1]]})
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "deployed").size(), 3, "one at range 8, two more next to it")
	F.act(e, s, "overcharge", "isk")
	expect(not F.ok(F.act(e, s, "activate", "isk", {"ability": mine, "to": [8, 4]})), "Assault Launcher is 1/round")


func test_black_witch_mag_field() -> void:
	_setup()
	var bw := _frame("bw", "mf_black_witch", "players", Vector2i(0, 0))
	var t := F.mech(s, "t", "players", Vector2i(4, 0))
	var a := F.mech(s, "a", "enemies", Vector2i(10, 0))
	_turn(bw)
	expect(not F.ok(F.act(e, s, "core_power", "bw", {"aim": [8, 8]})), "must touch a space next to the Black Witch")
	var out := F.act(e, s, "core_power", "bw", {"aim": [4, 0]})
	expect(F.ok(out), F.reason(out))
	expect(Zones.difficult_at(s, Vector2i(4, 1)), "difficult terrain")
	_turn(a, true)
	out = F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect_eq(F.events_of(out, "attack_blocked").size(), 1, "kinetic shots can't enter the field")
	expect_eq(t.hp, 10)
	_turn(bw)
	F.load_dice(s, [15, 4])
	_turn(a, true)
	expect(s.zones.is_empty(), "ends at the end of the Black Witch's next turn")
	expect_eq(t.hp, 6, "the stopped shot resumes: +1, 1d6 kinetic")


func test_genghis_expose_power_cells() -> void:
	_setup()
	var g := _frame("g", "mf_genghis", "players", Vector2i(3, 3))
	var a := F.mech(s, "a", "enemies", Vector2i(5, 3))
	var far := F.mech(s, "far", "enemies", Vector2i(11, 3))
	_turn(g)
	expect(F.ok(F.act(e, s, "core_power", "g")))
	var stress := g.stress
	Combat.apply_heat(s, g, g.heat_cap + 2, "test")
	expect_eq(g.heat, 0, "clears all heat instead of overheating")
	expect_eq(g.stress, stress)
	expect_eq(s.zones.size(), 1)
	_turn(a, true)
	expect_eq(a.burn, 2, "starting a turn in the cloud: 2 burn")
	expect_eq(a.heat, 2, "and 2 heat")
	F.load_dice(s, [1])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "g"})
	expect_eq(F.events_of(out, "invisible_roll").size(), 1, "Invisible inside the cloud")
	_turn(g)
	expect_eq(s.zones[0]["phase"], "cover")
	_turn(far, true)
	expect_eq(RulesQueries.attack_preview(s, "far", "0:0", "a")["cover"]["cover"], "soft", "then soft cover")


func test_dusk_wing_holograms() -> void:
	_setup()
	var dw := _frame("dw", "mf_dusk_wing", "players", Vector2i(0, 0))
	var h := F.mech(s, "h", "enemies", Vector2i(6, 4))
	h.max_hp = 20
	h.hp = 20
	_turn(dw)
	expect(F.ok(F.act(e, s, "core_power", "dw")))
	F.act(e, s, "move", "dw", {"to": [3, 0]})
	expect_eq(Zones.of_kind(s, "hologram").size(), 1, "a hologram where the move started")
	F.act(e, s, "boost", "dw", {"to": [3, 3]})
	expect_eq(Zones.of_kind(s, "hologram").size(), 2)
	_turn(h, true)
	F.load_dice(s, [4, 3])  # 1d6 = 4; Agility save 3 fails
	F.act(e, s, "move", "h", {"to": [4, 1]})
	expect_eq(h.hp, 16, "moving next to a hologram sets it off")
	expect_eq(Zones.of_kind(s, "hologram").size(), 1)
	_turn(dw, true)
	F.load_dice(s, [5, 2])
	var out := F.act(e, s, "activate", "dw", {"ability": _ability(dw, "Hologram Teleport"), "to": [0, 0]})
	expect(F.ok(out), F.reason(out))
	expect_eq(dw.cell, Vector2i(0, 0))
	expect(Zones.of_kind(s, "hologram").is_empty(), "every hologram detonates")
	F.act(e, s, "move", "dw", {"to": [0, 2]})
	expect(Zones.of_kind(s, "hologram").is_empty(), "no new holograms until its next turn")


func _rest_state() -> void:
	s.phase = GameState.PHASE_ENDED


func test_rest_and_everest_replaceable_parts() -> void:
	_setup()
	var ev := _frame("ev", "mf_standard_pattern_i_everest", "players", Vector2i(0, 0))
	F.begin(e, s, ev)
	expect(not F.ok(F.act(e, s, "rest", "ev")), "not in combat")
	_rest_state()
	ev.heat = 3
	ev.statuses["Impaired"] = {"source": "x"}
	ev.structure = 2
	ev.hp = 1
	var reps := ev.repairs
	var out := F.act(e, s, "rest", "ev", {"spend": [{"what": "structure"}, {"what": "hp"}]})
	expect(F.ok(out), F.reason(out))
	expect_eq(ev.heat, 0)
	expect(not ev.has_status("Impaired"))
	expect_eq(ev.structure, 3)
	expect_eq(ev.hp, ev.max_hp)
	expect_eq(ev.repairs, reps - 2, "Replaceable Parts: 1 Repair per Structure, plus 1 for HP")


func test_rest_wreck_repair_and_balor() -> void:
	_setup()
	var bal := _frame("bal", "mf_balor", "players", Vector2i(0, 0))
	var wreck := _frame("w", "mf_standard_pattern_i_everest", "players", Vector2i(3, 0))
	_rest_state()
	wreck.destroyed = true
	bal.hp = 3
	var reps := bal.repairs
	var out := F.act(e, s, "rest", "bal", {"spend": [{"what": "mech", "target": "w", "from": {"bal": 2, "w": 2}}]})
	expect(F.ok(out), F.reason(out))
	expect_eq(bal.hp, bal.max_hp, "Self-Perpetuating: full HP without Repairs")
	expect(not wreck.destroyed)
	expect_eq([wreck.structure, wreck.stress, wreck.hp], [1, 1, wreck.max_hp])
	expect_eq(bal.repairs, reps - 2, "others can chip in for a wreck")


func test_manticore_castigation_and_minotaur_metafold() -> void:
	_setup()
	var man := _frame("man", "mf_manticore", "players", Vector2i(0, 0))
	var p := Pilots.ensure_pilot(s, man)
	var t := F.mech(s, "t", "enemies", Vector2i(2, 0))
	t.max_hp = 60
	t.hp = 60
	_rest_state()
	expect(F.ok(F.act(e, s, "rest", "man", {"castigation": true})))
	s.phase = GameState.PHASE_COMBAT
	F.load_dice(s, [3, 3, 3, 3, 3, 3, 3, 3, 1])
	man.structure = 1
	man.hp = 1
	Combat.deal_damage(s, man, [{"type": "Kinetic", "amount": 50}], {"ap": true})
	expect(man.counters.get("vaporized", false), "explodes at once, vaporized")
	expect(p.destroyed, "and the pilot inside dies")
	expect_eq(t.hp, 60 - 24, "8d6 explosive, failed save")
	var mino := _frame("mino", "mf_minotaur", "players", Vector2i(8, 8))
	var mp := Pilots.ensure_pilot(s, mino)
	Pilots.explode(s, mino, "test")
	expect(not mp.destroyed, "Internal Metafold: the pilot inside can't be harmed")


func test_hydra_orochi_choice_and_full_deployment() -> void:
	_setup()
	var hy := UnitFactory.build_mech(db(), "hy", "mf_hydra", {"mounts": [], "systems": [], "orochi": "Snare OROCHI Drone"})
	hy.side = "players"
	s.add_unit(hy)
	_turn(hy)
	var guard := _ability(hy, "Deploy Guardian OROCHI Drone")
	var snare := _ability(hy, "Deploy Snare OROCHI Drone")
	expect(not F.ok(F.act(e, s, "activate", "hy", {"ability": guard, "to": [3, 0]})), "only the chosen drone")
	expect(F.ok(F.act(e, s, "activate", "hy", {"ability": snare, "to": [3, 0]})))
	_turn(hy, true)
	expect(not F.ok(F.act(e, s, "core_power", "hy", {"drones": [[4, 4]]})), "a space for each drone still in")
	var out := F.act(e, s, "core_power", "hy", {"drones": [[4, 4], [5, 4], [6, 4]]})
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "deployed").size(), 3, "all four out")
