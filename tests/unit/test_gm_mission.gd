extends TestCase
## Whole missions played AI against AI through the rules engine, start to finish.

static var _db: ContentDB


static func db() -> ContentDB:
	if _db == null:
		_db = ContentDB.new()
		_db.load_all()
	return _db


## Generates a mission, makes every seat AI-played, and runs it to the end.
static func play(mission_seed: int, opts: Dictionary = {}) -> Dictionary:
	opts["db"] = db()
	var gen := MissionGenerator.generate(mission_seed, opts)
	var state: GameState = gen["state"]
	var mission: Mission = gen["mission"]
	var host := NetHost.new(state, RulesEngine.new())
	var settings: GmSettings = opts.get("settings", GmSettings.from_preset("Standard"))
	var director := AiDirector.new(host, settings, mission)
	host.set_fill_empty_with_ai(true)
	var events: Array = []
	host.action_resolved.connect(func(_s: String, _a: Dictionary, _r: RuleResult, e: Array) -> void: events.append_array(e))
	var steps := director.run(4000)
	return {"state": state, "mission": mission, "director": director, "events": events, "steps": steps}


func test_basic_combat_plays_to_the_end() -> void:
	var t0 := Time.get_ticks_msec()
	var r := play(1234, {"sitrep": "sitrep_standardcombat", "size": 24})
	var m: Mission = r["mission"]
	var state: GameState = r["state"]
	var d: AiDirector = r["director"]
	print("        basic combat: %s after round %d, %d AI steps, %d ms. %s" % [m.outcome, state.round_number, r["steps"], Time.get_ticks_msec() - t0, m.outcome_reason])
	expect(m.outcome != "", "the mission reached an outcome")
	expect_eq(state.phase, GameState.PHASE_ENDED)
	expect(m.ended)
	expect(d.refusals.size() <= 3, "AI actions are almost never refused: %s" % str(d.refusals.slice(0, 3)))
	var types := {}
	for e: Dictionary in r["events"]:
		types[e["type"]] = true
	for t in ["combat_started", "turn_started", "moved", "attack_rolled", "damage_dealt", "mission_ended"]:
		expect(types.has(t), "saw a %s event" % t)
	expect(d.log_lines.size() > 4, "the AI explained its moves")


func test_control_mission_scores_zones() -> void:
	var r := play(77, {"sitrep": "sitrep_control", "size": 22, "players": 2})
	var m: Mission = r["mission"]
	print("        control: %s, scores %s. %s" % [m.outcome, m.scores, m.outcome_reason])
	expect(m.outcome != "")
	expect(r["state"].phase == GameState.PHASE_ENDED)
	expect(r["state"].round_number <= 7, "control ends after round 6 at the latest")
