extends TestCase
## Seat control: any seat human or AI, switching mid-mission, drop-in, filling empty seats.

const MissionTest := preload("res://tests/unit/test_gm_mission.gd")

var hub: LoopbackTransport.Hub
var host: NetHost
var director: AiDirector
var clients: Array[NetClient] = []


func _setup(players: int = 2) -> void:
	var g := MissionGenerator.generate(11, {"players": players, "sitrep": "sitrep_standardcombat", "size": 20, "db": MissionTest.db()})
	host = NetHost.new(g["state"], RulesEngine.new())
	director = AiDirector.new(host, GmSettings.from_preset("Standard"), g["mission"])
	hub = LoopbackTransport.Hub.new()
	host.open_room(LoopbackTransport.new(hub), "ROOMAI")
	clients.clear()
	_pump()


func _pump() -> void:
	for i in range(6):
		host.poll()
		for c in clients:
			c.poll(0.0)


func _join(seat: String) -> NetClient:
	var c := NetClient.new(LoopbackTransport.new(hub))
	clients.append(c)
	c.join("ROOMAI", "Friend", seat)
	_pump()
	return c


func test_seat_modes() -> void:
	_setup()
	expect(host.is_ai_seat("gm"), "the procedural GM plays the gm seat")
	expect(not host.is_ai_seat("p1"), "empty seats aren't filled by default")
	host.set_fill_empty_with_ai(true)
	expect(host.is_ai_seat("p1") and host.is_ai_seat("p2"))
	host.set_seat_reserved("p2", true)
	expect(not host.is_ai_seat("p2"), "reserved for a friend")
	host.add_local_seat("p1")
	expect(not host.is_ai_seat("p1"), "someone plays p1 at this machine")
	host.set_seat_ai("p1", true)
	expect(host.is_ai_seat("p1"), "...until they hand it to the AI")
	expect(host.seat_table()["p1"]["ai"])


func test_drop_in_takes_over_and_ai_picks_it_back_up() -> void:
	_setup()
	host.set_seat_ai("p2", true)
	expect(host.is_ai_seat("p2"))
	var c := _join("p2")
	expect_eq(c.seat, "p2", "a friend can take an AI pilot")
	expect(not host.is_ai_seat("p2"), "and plays it themselves")
	host.transport.disconnect_peer((c.transport as LoopbackTransport).peer_id)
	c.auto_reconnect = false
	_pump()
	expect(host.is_ai_seat("p2"), "the AI picks it back up when they leave")


func test_players_cannot_send_gm_actions() -> void:
	_setup()
	var out := host.submit("p1", {"type": "start_combat", "params": {"first_side": "players"}})
	expect(not (out["result"] as RuleResult).ok)
	out = host.submit("p1", {"type": "gm_end_mission", "params": {"outcome": "players"}})
	expect(not (out["result"] as RuleResult).ok, "a player can't declare victory")
	expect(host.state.phase == GameState.PHASE_SETUP)


func test_ai_waits_for_humans_then_takes_over_mid_mission() -> void:
	_setup()
	host.add_local_seat("p1")
	host.add_local_seat("p2")
	director.run(200)
	var s := host.state
	expect_eq(s.phase, GameState.PHASE_COMBAT, "the GM started the fight")
	expect_eq(s.turn_side, "players", "squad goes first; nobody has acted for it")
	expect_eq(s.active_unit, "", "the AI doesn't pick for a human side")
	# The players hand both pilots to the AI mid-mission.
	host.set_seat_ai("p1", true)
	host.set_seat_ai("p2", true)
	var steps := director.run(3)
	expect(steps > 0, "the AI plays them now")
	expect(s.acted.size() > 0 or s.active_unit != "")
	# One player takes theirs back: from then on the squad's picks wait for them.
	host.set_seat_ai("p1", false)
	director.run(400)
	var w := host.waiting_on()
	expect(s.phase == GameState.PHASE_ENDED or "p1" in w["seats"], "stops for the human: %s" % str(w))


func test_hot_seat_skips_ai_seats() -> void:
	var g := MissionGenerator.generate(12, {"players": 2, "sitrep": "sitrep_standardcombat", "size": 20, "db": MissionTest.db()})
	var h := NetHost.new(g["state"], RulesEngine.new())
	var hot := HotSeat.new(h, ["p1", "p2"])
	h.set_seat_ai("p2", true)
	var d := AiDirector.new(h, GmSettings.from_preset("Standard"), g["mission"])
	var handoffs: Array = []
	hot.handoff_requested.connect(func(seat: String, _n: String) -> void: handoffs.append(seat))
	hot.start("p1")
	hot.confirm_handoff()
	d.run(300)
	expect(not "p2" in handoffs, "no 'pass the screen' for the AI pilot")
	expect(h.state.round_number >= 1)
