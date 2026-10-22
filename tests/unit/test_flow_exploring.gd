extends TestCase
## Exploring before the fight (DESIGN.md "Exploring vs. fighting"): no turns until contact; you
## walk in real time (explore_move steps), AI squadmates follow, and the GM starts the fight on
## the same ground once the squad meets the enemy.

const MissionTest := preload("res://tests/unit/test_gm_mission.gd")


func test_walk_until_contact_then_the_fight_starts_in_place() -> void:
	var gen := MissionGenerator.generate(808, {"db": MissionTest.db(), "size": 30, "players": 2, "sitrep": "sitrep_standardcombat", "environments": []})
	var state: GameState = gen["state"]
	var mission: Mission = gen["mission"]
	mission.flavor["explore_first"] = true
	var host := NetHost.new(state, RulesEngine.new())
	var director := AiDirector.new(host, GmSettings.from_preset("Standard"), mission)
	host.set_seat_ai("p2", true)
	var s := BattleSession.for_host(host, director, mission, ["p1"])
	s.start()
	for i in range(6):
		s.poll(0.5)
	expect_eq(state.phase, GameState.PHASE_SETUP, "no turns before contact")
	expect(s.exploring())
	var me := ""
	var mate := ""
	for u: Unit in state.units_on_side(Mission.PLAYERS):
		if u.controller == "p1":
			me = u.id
		elif u.controller == "p2":
			mate = u.id
	var start: Vector2i = state.unit(me).cell
	var mate_start: Vector2i = state.unit(mate).cell
	var foe: Unit = state.units_on_side(Mission.ENEMIES)[0]
	expect_eq(s.walk_to(me, foe.cell), "")
	var guard := 0
	while state.phase == GameState.PHASE_SETUP and guard < 200:
		guard += 1
		s.poll(0.4)
	expect(state.unit(me).cell != start, "walked in real time")
	expect(state.unit(mate).cell != mate_start, "the AI squadmate followed")
	expect_eq(state.phase, GameState.PHASE_COMBAT, "contact: the fight starts on the same ground")
	expect(state.map.grid.distance(state.unit(me).cell, foe.cell) <= AiDirector.CONTACT + 2)
	expect(s.walk_to(me, start) != "", "in the fight: moves take turns now")


func test_a_latecomer_walks_up_and_joins_from_the_next_round() -> void:
	var gen := MissionGenerator.generate(818, {"db": MissionTest.db(), "size": 30, "players": 2, "sitrep": "sitrep_standardcombat", "environments": []})
	var state: GameState = gen["state"]
	var mission: Mission = gen["mission"]
	mission.flavor["explore_first"] = true
	var host := NetHost.new(state, RulesEngine.new())
	var director := AiDirector.new(host, GmSettings.from_preset("Standard"), mission)
	host.set_seat_ai("p2", true)
	var s := BattleSession.for_host(host, director, mission, ["p1"])
	s.start()
	var me := ""
	var fighters: Array = []
	for u: Unit in state.units.values():
		if u.controller == "p1":
			me = u.id
		else:
			fighters.append(u.id)
	# The fight broke out without p1 (they were elsewhere).
	var out := host.submit(NetHost.GM_SEAT, {"type": "start_combat", "params": {"first_side": Mission.PLAYERS, "units": fighters}})
	expect((out["result"] as RuleResult).ok, (out["result"] as RuleResult).reason)
	s.poll(0.1)
	expect(s.exploring() and me in s.exploring_units(), "p1 is outside the fight and can walk")
	var foe: Unit = state.units_on_side(Mission.ENEMIES)[0]
	expect_eq(s.walk_to(me, foe.cell), "")
	var guard := 0
	while bool(state.unit(me).counters.get("exploring", false)) and guard < 200:
		guard += 1
		s.poll(0.4)
	expect(not bool(state.unit(me).counters.get("exploring", false)), "walked up and joined the fight")
	expect(state.map.grid.distance(state.unit(me).cell, foe.cell) <= AiDirector.CONTACT + 4, "where they arrived")
