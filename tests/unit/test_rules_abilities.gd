extends TestCase
## Activated abilities, uses, Recharge, Protocols, deployables, drones, mines, action bar.

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


func _everest(systems: Array, pilot: Dictionary = {}) -> void:
	s = F.state()
	e = RulesEngine.new()
	a = UnitFactory.build_mech(db(), "a", "mf_standard_pattern_i_everest", {"mounts": [{"weapons": ["mw_assault_rifle"]}], "systems": systems}, pilot)
	a.side = "players"
	s.add_unit(a)
	t = F.mech(s, "t", "enemies", Vector2i(6, 0))
	F.begin(e, s, a)


func _next_turn(u: Unit) -> void:
	if s.active_unit != "":
		F.act(e, s, "end_turn", s.active_unit)
	s.acted = PackedStringArray()
	s.turn_side = u.side
	F.act(e, s, "start_turn", u.id)


func _ability(u: Unit, name: String) -> Dictionary:
	for x: Dictionary in Abilities.all(u):
		if x["name"] == name:
			return x
	return {}


func _bar(u: Unit, id: String) -> Dictionary:
	for x: Dictionary in RulesQueries.available_actions(s, u.id):
		if x["id"] == id:
			return x
	return {}


func test_factory_lists_system_actions_and_deployables() -> void:
	_everest(["ms_pattern_a_smoke_charges", "ms_turret_drones", "ms_pattern_a_jericho_deployable_cover"])
	expect(not _ability(a, "Smoke Grenade").is_empty())
	expect_eq(_ability(a, "Deploy Smoke Mine")["kind"], "deploy")
	expect_eq(_ability(a, "Deploy Turret Drone")["deployable"]["type"], "Drone")
	expect_eq(_ability(a, "Recall Jericho Deployable Cover")["activation"], "Full")


func test_limited_charges_and_once_per_system_per_turn() -> void:
	_everest(["ms_pattern_a_smoke_charges"])
	var key: String = _ability(a, "Smoke Grenade")["key"]
	expect(not F.ok(F.act(e, s, "activate", "a", {"ability": key})), "a grenade needs somewhere to land")
	var out := F.act(e, s, "activate", "a", {"ability": key, "aim": [3, 0]})
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "zone_created").size(), 1, "smoke: soft cover in a Blast 2")
	expect_eq(_bar(a, "ability:" + key)["uses_left"], 2, "Limited 3")
	expect(not F.ok(F.act(e, s, "activate", "a", {"ability": key, "aim": [3, 0]})), "can't Activate the same system twice a turn (Core p.71)")
	for i in range(2):
		_next_turn(a)
		expect(F.ok(F.act(e, s, "activate", "a", {"ability": key, "aim": [3, 0]})))
	_next_turn(a)
	var bar := _bar(a, "ability:" + key)
	expect(not bar["available"], "out of charges")
	expect(String(bar["reason"]).contains("charges"))


func test_deploy_drone_and_cover_object_and_recall() -> void:
	_everest(["ms_turret_drones", "ms_pattern_a_jericho_deployable_cover"])
	var drone: String = _ability(a, "Deploy Turret Drone")["key"]
	expect(not F.ok(F.act(e, s, "activate", "a", {"ability": drone, "to": [11, 11]})), "drones go within Sensors... and line of sight")
	var out := F.act(e, s, "activate", "a", {"ability": drone, "to": [3, 3]})
	expect(F.ok(out), F.reason(out))
	var dep: Dictionary = F.events_of(out, "deployed")[0]["object"]
	var d := s.unit(dep["id"])
	expect_eq(d.hp, 5)
	expect_eq(d.evasion, 10)
	expect_eq(d.size, 0.5)
	_next_turn(a)
	var cover: String = _ability(a, "Deploy Jericho Deployable Cover")["key"]
	expect(not F.ok(F.act(e, s, "activate", "a", {"ability": cover, "to": [[3, 0]]})), "deployables go in adjacent spaces")
	out = F.act(e, s, "activate", "a", {"ability": cover, "to": [[1, 0], [1, 1]]})
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "deployed").size(), 2, "2 sections")
	expect_eq(RulesQueries.cover(s, "t", "a")["cover"], "hard", "a deployed wall is hard cover (PROVISIONAL)")
	_next_turn(a)
	out = F.act(e, s, "activate", "a", {"ability": _ability(a, "Recall Jericho Deployable Cover")["key"]})
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "recalled").size(), 2)


func test_mines_arm_and_trigger() -> void:
	_everest(["ms_pattern_b_hex_charges"])
	var mine: String = _ability(a, "Deploy Explosive Mine")["key"]
	var out := F.act(e, s, "activate", "a", {"ability": mine, "to": [1, 0]})
	expect(F.ok(out), F.reason(out))
	var m := s.unit(F.events_of(out, "deployed")[0]["object"]["id"])
	expect(m.has_status("Hidden"), "undetected mines are Hidden")
	expect(not m.counters["armed"])
	F.act(e, s, "end_turn", "a")
	expect(m.counters["armed"], "armed at the end of the owner's turn")
	s.acted = PackedStringArray()
	s.turn_side = "enemies"
	F.act(e, s, "start_turn", "t")
	F.load_dice(s, [6, 6, 2])  # 2d6 = 12 (Core p.120; lancer-data says 3d6), Agility save 2 fails
	out = F.act(e, s, "move", "t", {"to": [2, 0]})
	expect_eq(F.events_of(out, "mine_triggered").size(), 1)
	expect_eq(t.structure, 3, "12 explosive: one structure, the excess carried over")
	expect_eq(t.hp, 8)
	expect(m.destroyed)


func test_protocol_talent_steady_aim() -> void:
	_everest([], {"ll": 2, "talents": {"t_crack_shot": 1}})
	var key: String = _ability(a, "Steady Aim")["key"]
	var out := F.act(e, s, "activate", "a", {"ability": key})
	expect(F.ok(out), F.reason(out))
	expect(a.has_status("Immobilized"), "until the start of your next turn")
	var p := RulesQueries.attack_preview(s, "a", "0:0", "t")
	expect(p["sources"].any(func(x: Dictionary) -> bool: return x["label"] == "Steady Aim"), "+1 Accuracy with Rifles")
	expect(F.ok(F.act(e, s, "lock_on", "a", {"target": "t"})), "a Protocol doesn't use an action")
	_next_turn(a)
	expect(not a.has_status("Immobilized"))
	expect(not RulesQueries.attack_preview(s, "a", "0:0", "t")["sources"].any(func(x: Dictionary) -> bool: return x["label"] == "Steady Aim"))
	F.act(e, s, "move", "a", {"to": [0, 1]})
	expect(not F.ok(F.act(e, s, "activate", "a", {"ability": key})), "Protocols only at the start of your turn")


func test_frequency_jammed_core_only_and_destroyed() -> void:
	s = F.state()
	e = RulesEngine.new()
	a = F.mech(s, "a", "players", Vector2i(0, 0))
	t = F.mech(s, "t", "enemies", Vector2i(3, 0))
	a.loadout["systems"] = [{"key": "s0", "id": "x", "name": "Gizmo", "tags": []}]
	a.loadout["abilities"] = [
		{"key": "s0/a0", "name": "Zap", "source_key": "s0", "source_name": "Gizmo", "kind": "action", "activation": "Quick", "frequency": "1/round", "ops": [], "automated": false},
		{"key": "s0/a1", "name": "Hack", "source_key": "s0", "source_name": "Gizmo", "kind": "action", "activation": "Quick Tech", "frequency": "", "ops": [], "automated": false},
		{"key": "core/a0", "name": "Overdrive", "source_key": "core", "source_name": "Core", "kind": "action", "activation": "Quick", "requires_core_active": true, "frequency": "", "ops": [], "automated": false},
	]
	F.begin(e, s, a)
	expect(F.ok(F.act(e, s, "activate", "a", {"ability": "s0/a0"})))
	_next_turn(t)
	_next_turn(a)
	expect(F.ok(F.act(e, s, "activate", "a", {"ability": "s0/a0"})), "1/round refreshes at the start of your turn")
	a.statuses["Jammed"] = {"source": "x"}
	expect(not F.ok(F.act(e, s, "activate", "a", {"ability": "s0/a1"})), "Jammed: no tech actions")
	a.statuses.erase("Jammed")
	expect(not F.ok(F.act(e, s, "activate", "a", {"ability": "core/a0"})), "only while the core is active")
	Abilities.source_state(a, "s0")["destroyed"] = true
	expect(not _bar(a, "ability:s0/a1")["available"], "a destroyed system can't be used")


func test_npc_recharge_and_feature_ability() -> void:
	s = F.state()
	e = RulesEngine.new()
	t = F.mech(s, "t", "players", Vector2i(0, 0))
	var art := UnitFactory.build_npc("art", UnitFactory.npc_templates()["ph_artillery"], 1)
	art.cell = Vector2i(5, 5)
	s.add_unit(art)
	var sup := UnitFactory.build_npc("sup", UnitFactory.npc_templates()["ph_support"], 1)
	sup.cell = Vector2i(9, 9)
	s.add_unit(sup)
	F.begin(e, s, art)
	F.load_dice(s, [15, 2])
	expect(F.ok(F.act(e, s, "skirmish", "art", {"weapon": "w0", "aim": [0, 0]})))
	var bar := _bar(art, "weapon:w0")
	expect(not bar["available"], "Recharge 5+: used")
	expect_eq(bar["recharge"]["value"], 5)
	F.load_dice(s, [3])
	_next_turn(art)
	expect(not _bar(art, "weapon:w0")["available"], "rolled 3: still recharging")
	F.load_dice(s, [6])
	_next_turn(art)
	expect(_bar(art, "weapon:w0")["available"], "rolled 6: ready")
	_next_turn(sup)
	expect(F.ok(F.act(e, s, "activate", "sup", {"ability": "f1/a0"})), "placeholder feature action")


func test_action_bar_lists_everything_with_reasons() -> void:
	_everest(["ms_pattern_a_smoke_charges"])
	a.loadout["weapons"].append(F.weapon("1:0", "Cannon", "Main", "Cannon", "1d6", 10, [{"id": "tg_loading"}]))
	F.load_dice(s, [2])
	F.act(e, s, "skirmish", "a", {"weapon": "1:0", "target": "t"})
	var cannon := _bar(a, "weapon:1:0")
	expect(cannon["loading"]["has"] and not cannon["loading"]["loaded"])
	expect(not cannon["available"])
	expect(not _bar(a, "skirmish")["available"], "already Skirmished this turn")
	expect(_bar(a, "boost")["available"])
	expect(_bar(a, "reaction:brace").has("policy"))
	expect_eq(_bar(a, "core_power_charges")["uses_left"], 1)
