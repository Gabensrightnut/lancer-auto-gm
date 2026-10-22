extends TestCase
## More frame traits and core systems from data/game/frame_effects.json.

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


func _turn(u: Unit) -> void:
	if s.active_unit != "":
		F.act(e, s, "end_turn", s.active_unit)
	if s.phase != GameState.PHASE_COMBAT:
		e.submit(s, {"type": "start_combat", "params": {"first_side": "players"}})
	s.acted = PackedStringArray()
	s.turn_side = u.side
	F.act(e, s, "start_turn", u.id)


func test_tortuga_watchdog() -> void:
	_setup()
	var tor := _frame("tor", "mf_tortuga", "enemies", Vector2i(3, 0))
	var a := F.mech(s, "a", "players", Vector2i(0, 0))
	a.counters["reaction_policy"] = {"brace": "never"}
	expect(not Movement.threatened_by(s, a).has("tor"), "Threat 1 by default")
	_turn(tor)
	expect(F.ok(F.act(e, s, "core_power", "tor")))
	expect(Movement.threatened_by(s, a).has("tor"), "ranged weapons get Threat 3")
	_turn(a)
	F.load_dice(s, [15, 3])
	F.act(e, s, "move", "a", {"to": [0, 3]})
	expect(a.has_status("Immobilized"), "hit by Overwatch: Immobilized")
	expect(Reactions.can_react(tor, "overwatch").ok, "an additional Overwatch each round")


func test_swallowtail_lock_on_shreds_once_per_round() -> void:
	_setup()
	var sw := _frame("sw", "mf_swallowtail", "players", Vector2i(0, 0))
	var t := F.mech(s, "t", "enemies", Vector2i(4, 0))
	var t2 := F.mech(s, "t2", "enemies", Vector2i(4, 2))
	_turn(sw)
	F.act(e, s, "lock_on", "sw", {"target": "t"})
	expect(t.has_status("Shredded"))
	F.act(e, s, "overcharge", "sw")
	F.act(e, s, "lock_on", "sw", {"target": "t2"})
	expect(not t2.has_status("Shredded"), "1/round")


func test_balor_scouring_swarm() -> void:
	_setup()
	_frame("bal", "mf_balor", "enemies", Vector2i(1, 0))
	var a := F.mech(s, "a", "players", Vector2i(0, 0))
	_turn(a)
	expect_eq(a.hp, 8, "starting a turn next to the Balor: 2 kinetic")


func test_gorgon_paralysis_and_gaze() -> void:
	_setup()
	var g := _frame("g", "mf_gorgon", "enemies", Vector2i(3, 0))
	var a := F.mech(s, "a", "players", Vector2i(0, 0))
	_turn(a)
	F.load_dice(s, [2])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "g"})
	expect_eq(F.events_of(out, "attack_rolled")[0]["result"], "miss")
	expect(a.has_status("Stunned"), "a 1-2 against the Gorgon Stuns the attacker")
	Reactions._mark_used(g, "overwatch", s)
	expect(Reactions.can_react(g, "brace", s).ok, "Gaze: two reactions per turn")
	Reactions._mark_used(g, "brace", s)
	expect(not Reactions.can_react(g, "other", s).ok, "but not three")


func test_hydra_drones_get_hp_and_shepherd_field() -> void:
	_setup()
	var h := _frame("h", "mf_hydra", "players", Vector2i(0, 0), ["ms_turret_drones"])
	F.mech(s, "t", "enemies", Vector2i(8, 8))
	_turn(h)
	var key := ""
	for a: Dictionary in Abilities.all(h):
		if a["name"] == "Deploy Turret Drone":
			key = a["key"]
	var out := F.act(e, s, "activate", "h", {"ability": key, "to": [1, 0]})
	expect(F.ok(out), F.reason(out))
	var d := s.unit(F.events_of(out, "deployed")[0]["object"]["id"])
	expect_eq(d.hp, 10, "5 + System Link's 5")
	Combat.deal_damage(s, d, [{"type": "Kinetic", "amount": 6}])
	expect_eq(d.hp, 7, "Shepherd Field: Resistance next to the Hydra")


func test_manticore_wreck_explodes() -> void:
	_setup()
	var m := _frame("m", "mf_manticore", "enemies", Vector2i(3, 0))
	var a := F.mech(s, "a", "players", Vector2i(4, 0))
	_turn(a)
	Combat.destroy(s, m, "test")
	var pilot := Pilots.pilot_of(s, m)
	expect(pilot != null and m.counters.has("unstable_explosion"))
	_turn(pilot)
	F.load_dice(s, [2, 2, 2, 2, 20])
	var out := F.act(e, s, "end_turn", pilot.id)
	expect_eq(F.events_of(out, "reactor_explosion").size(), 1, "explodes at the end of its next turn")
	expect(pilot.destroyed)
	expect(m.counters.get("vaporized", false))


func test_minotaur_eject_and_iskander_mines_and_napoleon() -> void:
	_setup()
	var mino := _frame("mino", "mf_minotaur", "players", Vector2i(0, 0))
	F.mech(s, "t", "enemies", Vector2i(11, 11))
	_turn(mino)
	expect(F.ok(F.act(e, s, "eject", "mino", {"to": [6, 0]})))
	expect(not mino.has_status("Impaired"), "Invert Cockpit: no Impaired on Eject")
	var isk := _frame("isk", "mf_iskander", "enemies", Vector2i(5, 5))
	expect(Abilities.check_mines(s, isk, [[5, 5, 0], [5, 6, 0]]).is_empty(), "Skeleton Key: never sets off mines")
	var nap := _frame("nap", "mf_napoleon", "enemies", Vector2i(9, 0))
	nap.counters["brace_policy"] = "on_structure"
	nap.hp = 3
	var a := F.mech(s, "a", "players", Vector2i(9, 3))
	var ev := Attacks._apply(s, a, nap, [{"type": "Kinetic", "amount": 9}], false)
	expect_eq(nap.hp, 2, "Flash Aegis: Bracing reduces the damage to 1")
	expect_eq(F.events_of({"events": ev}, "reaction").size(), 1)


func test_monarch_missiles_and_lancaster_repair() -> void:
	_setup()
	var mon := _frame("mon", "mf_monarch", "players", Vector2i(0, 0))
	var t := F.mech(s, "t", "enemies", Vector2i(10, 10))
	var t2 := F.mech(s, "t2", "enemies", Vector2i(11, 0))
	_turn(mon)
	F.load_dice(s, [4, 3, 18])  # 1d6+4 = 8; t fails (3), t2 saves (18) for half
	var out := F.act(e, s, "core_power", "mon", {"targets": ["t", "t2"]})
	expect(F.ok(out), F.reason(out))
	expect_eq(t.hp, 2)
	expect_eq(t2.hp, 6)
	var lan := _frame("lan", "mf_lancaster", "players", Vector2i(5, 5))
	var wreck := F.mech(s, "w", "players", Vector2i(5, 6))
	wreck.destroyed = true
	_turn(lan)
	var key := ""
	for a: Dictionary in Abilities.all(lan):
		if a["name"] == "Combat Repair":
			key = a["key"]
	var reps := lan.repairs
	out = F.act(e, s, "activate", "lan", {"ability": key, "target": "w"})
	expect(F.ok(out), F.reason(out))
	expect(not wreck.destroyed)
	expect_eq([wreck.structure, wreck.stress, wreck.hp], [1, 1, 1])
	expect_eq(lan.repairs, reps - 4)
