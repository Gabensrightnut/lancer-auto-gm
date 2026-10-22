extends TestCase
## Host/client sessions over the loopback transport: seats, actions, reconnects, version
## checks, and above all that secrets never reach a client that shouldn't have them.

# Odd numbers so a leak is easy to spot in raw wire text.
const ENEMY_HP := 7331
const ENEMY_HEAT := 6113
const SNEAKY_HP := 5147
const SNEAKY_CELL := Vector2i(4321, 8765)


## Moves the Hidden enemy (stands in for the real Move action).
class SneakHandler:
	extends ActionHandler

	func type() -> String:
		return "test_sneak"

	func validate(_s: GameState, _a: Dictionary) -> RuleResult:
		return RuleResult.allow()

	func resolve(s: GameState, a: Dictionary) -> Array[Dictionary]:
		var u := s.unit(a["actor"])
		u.cell = SNEAKY_CELL
		return [{"type": "moved", "unit": u.id, "path": [[SNEAKY_CELL.x, SNEAKY_CELL.y, 0]], "mode": "walk"}] as Array[Dictionary]


## Heats a unit and rolls a die (stands in for an attack).
class HeatHandler:
	extends ActionHandler

	func type() -> String:
		return "test_heat"

	func validate(_s: GameState, _a: Dictionary) -> RuleResult:
		return RuleResult.allow()

	func resolve(s: GameState, a: Dictionary) -> Array[Dictionary]:
		var u := s.unit(a["actor"])
		u.heat += 1
		var check := s.dice.check(0, 0, 0, 10)
		return [
			{"type": "heat_changed", "unit": u.id, "amount": 1, "total": u.heat},
			{"type": "attack_rolled", "attacker": u.id, "target": "ally1", "weapon": "", "check": check, "result": "miss"},
		] as Array[Dictionary]


var hub: LoopbackTransport.Hub
var host: NetHost
var clients: Array[NetClient] = []


func _setup() -> void:
	var s := GameState.new(98765)
	s.seats = {
		"p1": {"name": "Player 1", "side": "players"},
		"p2": {"name": "Player 2", "side": "players"},
		"gm": {"name": "GM", "side": "enemies"},
	}
	for spec in [["ally1", "players", "p1"], ["ally2", "players", "p2"], ["enemy", "enemies", "gm"], ["sneaky", "enemies", "gm"]]:
		var u := Unit.new()
		u.id = spec[0]
		u.side = spec[1]
		u.controller = spec[2]
		u.hp = 10
		s.add_unit(u)
	s.unit("enemy").hp = ENEMY_HP
	s.unit("enemy").heat = ENEMY_HEAT - 1
	s.unit("sneaky").hp = SNEAKY_HP
	s.unit("sneaky").statuses = {"Hidden": {}}
	s.dice.roll("1d20")  # Move the dice state away from the seed.
	var engine := RulesEngine.new()
	engine.register(SneakHandler.new())
	engine.register(HeatHandler.new())
	hub = LoopbackTransport.Hub.new()
	host = NetHost.new(s, engine)
	host.open_room(LoopbackTransport.new(hub), "ROOM42")
	clients.clear()


func _client(name: String, seat: String = "") -> NetClient:
	var c := NetClient.new(LoopbackTransport.new(hub))
	clients.append(c)
	c.join("ROOM42", name, seat)
	_pump()
	return c


func _pump(delta: float = 0.0, rounds: int = 6) -> void:
	for i in range(rounds):
		host.poll()
		for c in clients:
			c.poll(delta)


func _wire_to(c: NetClient) -> String:
	return hub.text_sent_to("ROOM42", (c.transport as LoopbackTransport).peer_id)


func test_clients_get_seats_and_views() -> void:
	_setup()
	var a := _client("Ana")
	var b := _client("Bo")
	expect_eq(a.seat, "p1", "first free seat")
	expect_eq(b.seat, "p2")
	expect(a.token != "" and a.token != b.token)
	expect(a.view["units"].has("ally1"))
	expect_eq(host.seat_table()["p2"]["player"], "Bo")
	expect(host.seat_table()["p1"]["connected"])


func test_actions_go_through_the_rules_engine() -> void:
	_setup()
	var a := _client("Ana")
	var answers: Array = []
	a.action_answered.connect(_rec2(answers))
	var id := a.submit({"type": "end_turn", "actor": "ally1"})
	_pump()
	expect_eq(answers.size(), 1)
	expect_eq(answers[0][0], id)
	expect(not answers[0][1]["ok"], "not ally1's turn yet, so the engine refuses")
	expect(answers[0][1]["rule_ref"] != "", "refusals cite a rule")
	host.state.active_unit = "ally1"
	var updates: Array = []
	a.view_updated.connect(_rec2(updates))
	a.submit({"type": "end_turn", "actor": "ally1"})
	_pump()
	var events := _events_of(updates)
	expect(answers[1][1]["ok"])
	# The rules engine may add follow-up events (next turn, new round); the end of turn must be there.
	expect(events.any(func(e): return e["type"] == "turn_ended" and e["unit"] == "ally1"))
	expect("ally1" in host.state.acted)


func test_seat_can_only_command_its_own_units() -> void:
	_setup()
	var a := _client("Ana")
	var answers: Array = []
	a.action_answered.connect(_rec2(answers))
	host.state.active_unit = "ally2"
	a.submit({"type": "end_turn", "actor": "ally2"})
	a.submit({"type": "test_sneak", "actor": "sneaky"})
	_pump()
	expect(not answers[0][1]["ok"])
	expect(not answers[1][1]["ok"])
	expect_eq(host.state.active_unit, "ally2", "nothing changed")
	expect_eq(host.state.unit("sneaky").cell, Vector2i.ZERO)


func test_secrets_never_reach_player_clients() -> void:
	_setup()
	host.human_gm = true  # a person is the GM (only then can anyone join as the GM)
	var a := _client("Ana")
	var gm := _client("Remote GM", "gm")
	expect_eq(gm.seat, "gm")
	var a_updates: Array = []
	a.view_updated.connect(_rec2(a_updates))
	var gm_updates: Array = []
	gm.view_updated.connect(_rec2(gm_updates))
	host.submit("gm", {"type": "test_sneak", "actor": "sneaky"})
	host.submit("gm", {"type": "test_heat", "actor": "enemy"})
	_pump()
	var a_events := _events_of(a_updates)
	var gm_events := _events_of(gm_updates)
	var wire := _wire_to(a)
	expect(wire != "")
	for secret in [str(ENEMY_HP), str(ENEMY_HEAT), str(SNEAKY_HP), str(SNEAKY_CELL.x), str(SNEAKY_CELL.y)]:
		expect(not secret in wire, "player wire text contains secret " + secret)
	expect(not "dice_state" in wire and not "\"seed\"" in wire)
	expect(not str(host.state.dice.get_state()) in wire, "dice state never leaves the host")
	expect(not str(host.state.game_seed) in wire, "game seed never leaves the host")
	expect(not a.view["units"]["sneaky"].has("cell"), "Hidden enemy position unknown")
	expect(not a.view["units"]["enemy"].has("hp"), "unscanned enemy HP unknown")
	var types := a_events.map(func(e: Dictionary) -> String: return e["type"])
	expect(not "moved" in types, "the Hidden unit's move is not shown to players")
	expect("heat_changed" in types and "attack_rolled" in types, "visible events still arrive")
	for e: Dictionary in a_events:
		if e["type"] == "heat_changed":
			expect(not e.has("total"), "heat total of an unscanned enemy is removed")
	# The GM seat (its own side) sees everything about its units.
	var gm_types := gm_events.map(func(e: Dictionary) -> String: return e["type"])
	expect("moved" in gm_types)
	expect_eq(int(gm.view["units"]["sneaky"]["hp"]), SNEAKY_HP)
	expect(not "dice_state" in _wire_to(gm), "not even the GM client gets the dice state")


func test_scanned_stats_are_shared_with_that_side_only() -> void:
	_setup()
	var a := _client("Ana")
	host.view_filter.reveal_stats("players", "enemy")
	host.send_updates()
	_pump()
	expect_eq(int(a.view["units"]["enemy"]["hp"]), ENEMY_HP)
	expect(not a.view["units"]["sneaky"].has("hp"), "only the scanned unit is revealed")


func test_version_mismatch_is_refused() -> void:
	_setup()
	var raw := LoopbackTransport.new(hub)
	var got: Array = []
	raw.message_received.connect(_rec2(got))
	raw.join("ROOM42")
	raw.poll()
	raw.send(NetTransport.HOST_PEER, {"t": NetProtocol.HELLO, "version": "0.0.1-old", "name": "Old", "token": "", "seat": ""})
	for i in range(4):
		host.poll()
		raw.poll()
	expect_eq(got.size(), 1)
	var msg: Dictionary = got[0][1]
	expect_eq(msg["t"], NetProtocol.REFUSED)
	expect_eq(msg["code"], NetProtocol.REFUSE_VERSION)
	expect("update" in msg["reason"].to_lower(), "tells the player to update")
	expect_eq(host.seat_table()["p1"]["where"], "open", "no seat given")


func test_taken_seat_and_full_room_are_refused() -> void:
	_setup()
	_client("Ana", "p1")
	var codes: Array = []
	var dup := NetClient.new(LoopbackTransport.new(hub))
	dup.refused.connect(_rec2(codes))
	clients.append(dup)
	dup.join("ROOM42", "Dup", "p1")
	_pump()
	expect_eq(codes.size(), 1)
	expect_eq(codes[0][0], NetProtocol.REFUSE_SEAT_TAKEN)
	_client("Bo")
	var late := NetClient.new(LoopbackTransport.new(hub))
	late.refused.connect(_rec2(codes))
	clients.append(late)
	late.join("ROOM42", "Late")
	_pump()
	expect_eq(codes[-1][0], NetProtocol.REFUSE_FULL, "the gm seat is never auto-assigned")


func test_wrong_room_code_fails_to_join() -> void:
	_setup()
	var c := NetClient.new(LoopbackTransport.new(hub))
	var reasons: Array = []
	c.join_failed.connect(_rec1(reasons))
	clients.append(c)
	c.join("NOPE99", "Ana")
	_pump()
	expect_eq(reasons.size(), 1)


func test_reconnect_after_drop_keeps_the_seat() -> void:
	_setup()
	var a := _client("Ana")
	var b := _client("Bo")
	var lost: Array = []
	a.connection_lost.connect(_rec1(lost))
	var rejoined: Array = []
	a.joined.connect(_rec1(rejoined))
	host.transport.disconnect_peer((a.transport as LoopbackTransport).peer_id)
	_pump()
	expect_eq(lost, [true])
	expect(not host.seat_table()["p1"]["connected"])
	expect_eq(host.seat_table()["p1"]["where"], "remote", "seat held for the player")
	# While Ana is away, the game goes on and a newcomer can't take her seat.
	host.state.active_unit = "ally2"
	b.submit({"type": "end_turn", "actor": "ally2"})
	_pump()
	_pump(1.5)
	expect_eq(rejoined, ["p1"])
	expect(a.connected)
	expect(host.seat_table()["p1"]["connected"])
	expect("ally2" in a.view["acted"], "rejoining brings the view up to date")


func test_host_gone_for_good_gives_up() -> void:
	_setup()
	var a := _client("Ana")
	var lost: Array = []
	a.connection_lost.connect(_rec1(lost))
	host.close()
	_pump()
	for i in range(NetClient.RECONNECT_DELAYS.size() + 1):
		_pump(31.0, 2)
	expect_eq(lost, [true, false])
	expect(not a.connected)


func test_room_codes_are_readable() -> void:
	var code := NetProtocol.new_room_code()
	expect_eq(code.length(), NetProtocol.CODE_LENGTH)
	expect_eq(NetProtocol.normalize_room_code(" %s-%s " % [code.left(3).to_lower(), code.right(3)]), code)
	expect_eq(NetProtocol.normalize_room_code("ABC"), "")


# Signal recorders. Static so the lambdas don't hold the test (that would be a reference cycle).
static func _rec1(into: Array) -> Callable:
	return func(a: Variant) -> void: into.append(a)


static func _rec2(into: Array) -> Callable:
	return func(a: Variant, b: Variant) -> void: into.append([a, b])


static func _rec3(into: Array) -> Callable:
	return func(a: Variant, b: Variant, c: Variant) -> void: into.append([a, b, c])


static func _events_of(updates: Array) -> Array:
	var out: Array = []
	for u: Array in updates:
		out.append_array(u[1])
	return out
