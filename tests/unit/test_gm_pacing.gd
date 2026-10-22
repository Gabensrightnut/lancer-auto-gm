extends TestCase
## Pacing: AI squadmates taking their turns on their own, "Let the AI go", and the approach
## dial that brings Basic Combat's deployment zones closer.

const MissionTest := preload("res://tests/unit/test_gm_mission.gd")


func _battle(auto: bool) -> Dictionary:
	var gen := MissionGenerator.generate(606, {"db": MissionTest.db(), "size": 20, "players": 2, "sitrep": "sitrep_standardcombat", "environments": [], "weather": "clear"})
	var state: GameState = gen["state"]
	var host := NetHost.new(state, RulesEngine.new())
	var director := AiDirector.new(host, GmSettings.from_preset("Standard"), gen["mission"])
	host.add_local_seat("p1")
	host.set_seat_ai("p2", true)
	host.ai_squad_auto = auto
	host.submit(NetHost.GM_SEAT, {"type": "start_combat", "params": {"first_side": Mission.PLAYERS}})
	return {"state": state, "host": host, "director": director}


func test_ai_squadmates_wait_for_people_then_go_on_their_own() -> void:
	var b := _battle(true)
	var state: GameState = b["state"]
	var host: NetHost = b["host"]
	expect(not b["director"].step(), "the squad's pick, and p1 (a person) hasn't acted: the AI waits")
	expect_eq(state.active_unit, "")
	host.submit("p1", {"type": "start_turn", "actor": "p1"})
	host.submit("p1", {"type": "end_turn", "actor": "p1"})
	# The enemies take their turn, then it's the squad's pick again with only p2 left.
	for i in range(40):
		if state.turn_side == Mission.PLAYERS and state.active_unit == "" and state.acted.has("p1"):
			break
		b["director"].step()
	expect(state.turn_side == Mission.PLAYERS and not state.acted.has("p2"), "back to the squad with p2 still to act")
	expect(b["director"].step(), "only an AI squadmate is left: it goes by itself")
	expect(state.acted.has("p2") or state.active_unit == "p2")


func test_let_the_ai_go_and_turning_it_off() -> void:
	var b := _battle(false)
	var state: GameState = b["state"]
	var host: NetHost = b["host"]
	expect(not b["director"].step(), "off: people pick every activation")
	host.ai_go_now = true
	expect(b["director"].step(), "\"Let the AI go\": an AI squadmate acts now")
	expect(state.acted.has("p2") or state.active_unit == "p2")
	expect(not host.ai_go_now, "one activation only")


func test_approach_dial_brings_deployment_closer() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var far := SitrepLayout.layout("sitrep_standardcombat", 30, 34, GridLayout.Shape.SQUARE, rng, 0)
	var near := SitrepLayout.layout("sitrep_standardcombat", 30, 34, GridLayout.Shape.SQUARE, rng, 14)
	var gap := func(lay: Dictionary) -> int:
		var top := 0
		for c: Array in lay["deployment"][Mission.ENEMIES]:
			top = maxi(top, int(c[1]))
		var bottom := 999
		for c: Array in lay["deployment"][Mission.PLAYERS]:
			bottom = mini(bottom, int(c[1]))
		return bottom - top - 1
	expect_eq(gap.call(far), 34 - 2 * SitrepLayout.DEPTH, "0: deploy at the map edges")
	expect(gap.call(near) <= 14 and gap.call(near) >= 13, "14: about fourteen rows apart (%d)" % gap.call(near))
	# Every sitrep follows the dial now, so big maps don't start with long walks.
	var control := SitrepLayout.layout("sitrep_control", 30, 34, GridLayout.Shape.SQUARE, rng, 14)
	expect(gap.call(control) <= 14, "sitreps with zones follow the dial too (%d)" % gap.call(control))
	expect_eq(GmSettings.from_preset("Standard").approach, 14.0)
	expect(GmSettings.from_preset("Cautious").approach > GmSettings.from_preset("Standard").approach)
