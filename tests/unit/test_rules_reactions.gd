extends TestCase
## Reaction windows: the engine pauses, asks the defender, then replays with the answer.

const F = preload("res://tests/unit/test_rules_fixtures.gd")

var s: GameState
var e: RulesEngine
var a: Unit
var t: Unit


func _setup(t_cell := Vector2i(3, 0)) -> void:
	s = F.state()
	e = RulesEngine.new()
	a = F.mech(s, "a", "players", Vector2i(0, 0))
	a.controller = "seat1"
	t = F.mech(s, "t", "enemies", t_cell)
	t.controller = "seat2"
	F.begin(e, s, a)


func test_brace_is_asked_and_applied_by_choice() -> void:
	_setup()
	F.load_dice(s, [15, 6])
	var out := F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	expect(F.ok(out))
	expect_eq(out["events"].size(), 1)
	expect_eq(out["events"][0]["type"], "reaction_offered")
	expect_eq(out["events"][0]["reaction"], "brace")
	expect_eq(t.hp, 10, "nothing applied while waiting")
	expect(not F.ok(F.act(e, s, "end_turn", "a")), "everything waits for the answer")
	expect(not F.ok(e.submit(s, {"type": "react", "actor": "a", "params": {"take": true}})), "only the asked unit answers")
	out = e.submit(s, {"type": "react", "actor": "t", "params": {"take": true}})
	expect(F.ok(out), F.reason(out))
	expect_eq(F.events_of(out, "attack_rolled")[0]["check"]["d20"], 15, "same dice on replay")
	expect_eq(F.events_of(out, "reaction").size(), 1)
	expect_eq(t.hp, 7, "6 damage halved by Brace")
	expect(t.has_status("Braced"))
	expect(s.pending.is_empty())


func test_declining_brace_takes_full_damage() -> void:
	_setup()
	F.load_dice(s, [15, 6])
	F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	e.submit(s, {"type": "react", "actor": "t", "params": {"take": false}})
	expect_eq(t.hp, 4)
	expect(not t.has_status("Braced"))


func test_overwatch_interrupts_a_move() -> void:
	_setup(Vector2i(1, 0))
	Combat.refresh_engagement(s)
	F.load_dice(s, [15, 1, 3])  # t is Engaged: +1 Difficulty on its ranged Overwatch (the 1)
	t.counters["reaction_policy"] = {"brace": "never"}
	a.counters["reaction_policy"] = {"brace": "never"}
	var out := F.act(e, s, "move", "a", {"to": [0, 3]})
	expect_eq(out["events"][0]["type"], "reaction_offered")
	expect_eq(out["events"][0]["reaction"], "overwatch")
	expect_eq(out["events"][0]["context"]["weapons"], ["0:0"])
	out = e.submit(s, {"type": "react", "actor": "t", "params": {"take": true, "weapon": "0:0"}})
	expect(F.ok(out), F.reason(out))
	var types: Array = out["events"].map(func(x: Dictionary) -> String: return x["type"])
	expect(types.find("attack_rolled") < types.find("moved"), "the attack comes before the move")
	expect_eq(a.hp, 7)
	expect_eq(a.cell, Vector2i(0, 3))
	expect(not Reactions.can_react(t, "overwatch").ok, "once per round")


func test_declined_overwatch_and_disengage() -> void:
	_setup(Vector2i(1, 0))
	Combat.refresh_engagement(s)
	F.act(e, s, "move", "a", {"to": [0, 3]})
	var out := e.submit(s, {"type": "react", "actor": "t", "params": {"take": false}})
	expect_eq(F.events_of(out, "attack_rolled").size(), 0)
	expect_eq(a.cell, Vector2i(0, 3))
	_setup(Vector2i(1, 0))
	Combat.refresh_engagement(s)
	F.act(e, s, "disengage", "a")
	out = F.act(e, s, "move", "a", {"to": [0, 3]})
	expect_eq(F.events_of(out, "moved").size(), 1, "Disengage: no Overwatch")


func test_gm_units_react_automatically_and_can_cancel_the_move() -> void:
	_setup(Vector2i(1, 0))
	t.controller = "gm"
	t.loadout["weapons"][0]["tags"] = [{"id": "tg_knockback", "val": 1}]
	Combat.refresh_engagement(s)
	F.load_dice(s, [15, 3])  # Prone (+1 Accuracy) cancels Engaged (+1 Difficulty)
	a.counters["reaction_policy"] = {"brace": "never"}
	a.statuses["Prone"] = {"source": "x"}
	a.hp = 2
	a.structure = 1
	var out := F.act(e, s, "move", "a", {"to": [0, 2]})
	expect_eq(F.events_of(out, "reaction").size(), 1, "GM default: take Overwatch")
	expect(a.destroyed)
	expect_eq(F.events_of(out, "movement_cancelled").size(), 1)


func test_pending_reaction_survives_save_and_load() -> void:
	_setup()
	F.load_dice(s, [15, 6])
	F.act(e, s, "skirmish", "a", {"weapon": "0:0", "target": "t"})
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	expect_eq(loaded.pending["reaction"], "brace")
	var view := ViewFilter.new().view_for(s, "seat2")
	expect(not view["pending"].has("snapshot"), "the rewind point stays on the host")
	var out := e.submit(loaded, {"type": "react", "actor": "t", "params": {"take": false}})
	expect(F.ok(out), F.reason(out))
	expect(loaded.pending.is_empty())
	expect_eq(F.events_of(out, "attack_rolled").size(), 1)
