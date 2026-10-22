extends TestCase
## Lobby: seat modes, fill-with-AI, pilots, presets, grid, ready-up, start checks, mismatches.

const MissionTest := preload("res://tests/unit/test_gm_mission.gd")


func _campaign(n: int = 3) -> Campaign:
	var c := Campaign.create("Lobby test")
	for i in range(n):
		c.new_pilot("Pilot %d" % i, "Call%d" % i)
	return c


func _lobby(n: int = 3) -> LobbyModel:
	return LobbyModel.for_host(_campaign(n), MissionTest.db(), 77)


func test_new_lobby_defaults() -> void:
	var l := _lobby()
	expect_eq(l.seats(), ["p1", "p2", "p3"])
	expect_eq(l.modes["p1"], "you")
	expect_eq(l.modes["p2"], "ai")
	var rows := l.rows()
	expect_eq(rows.size(), 3)
	expect(rows[1]["ai"] and rows[1]["ready"], "AI seats are always ready")
	expect(not rows[0]["ready"])
	expect(l.host.state.unit("p1") != null, "the mission is generated with the campaign's pilots")
	expect_eq(l.host.state.packs, l.campaign.packs)
	expect_eq(l.start_problems(), ["Press Ready when you're set."])
	l.set_local_ready(true)
	expect(l.can_start())
	var s := l.start()
	expect(s.has("director"))


func test_open_seats_need_a_friend_or_ai() -> void:
	var l := _lobby()
	l.set_local_ready(true)
	l.set_mode("p2", "open")
	expect(not l.can_start())
	expect(l.start_problems()[0].contains("Fill empty seats"), str(l.start_problems()))
	l.set_fill_empty(true)
	expect(l.can_start(), "filled by an AI pilot")
	l.set_mode("p3", "reserved")
	expect(not l.can_start(), "reserved seats are never filled by AI")
	expect(not l.host.is_ai_seat("p3"))
	l.set_mode("p3", "you")
	expect(l.host.local_seats.has("p3"), "hot-seat: two seats on this screen")
	l.set_local_ready(true)
	expect(l.can_start())


func test_friend_joins_and_readies_up() -> void:
	var l := _lobby()
	l.set_mode("p2", "open")
	l.set_local_ready(true)
	var hub := LoopbackTransport.Hub.new()
	l.host.open_room(LoopbackTransport.new(hub), "LOBBY1")
	var friend := NetClient.new(LoopbackTransport.new(hub))
	var mirror := LobbyModel.for_client(friend)
	friend.join("LOBBY1", "Dee", "p2")
	_pump(l, [friend])
	var row: Dictionary = l.rows()[1]
	expect_eq(row["player"], "Dee")
	expect(row["connected"])
	expect(l.start_problems()[0].contains("isn't ready"), str(l.start_problems()))
	expect_eq(mirror.rows().size(), 3, "the friend sees the seats")
	var seen := mirror.rows()
	expect(seen[1]["me"] and not seen[0]["me"], "the friend's own seat is marked as theirs")
	expect(seen[0]["host_seat"], "the host's seat is labeled as the host's")
	expect_eq(mirror.start_problems(), ["Press Ready when you're set."], "hints are written for the friend")
	mirror.set_local_ready(true)
	_pump(l, [friend])
	expect(l.can_start(), str(l.start_problems()))
	expect(mirror.start_problems().is_empty(), "the friend sees it's ready to launch")


func test_changing_grid_and_preset_regenerates_the_mission() -> void:
	var l := _lobby()
	var hex_cells := l.host.state.map.cells().size()
	expect_eq(l.host.state.map.grid.shape, GridLayout.Shape.HEX)
	l.set_shape("square")
	expect_eq(l.host.state.map.grid.shape, GridLayout.Shape.SQUARE)
	expect(l.host.state.map.cells().size() > 0 and hex_cells > 0)
	l.set_preset("Ruthless")
	expect_eq(l.campaign.gm_settings["preset"], "Ruthless")
	var ruthless_foes := l.host.state.units_on_side("enemies").size()
	l.set_preset("Teaching")
	expect(l.host.state.units_on_side("enemies").size() < ruthless_foes, "Teaching fields a smaller encounter")


func test_pilot_assignment_swaps() -> void:
	var l := _lobby()
	var a: String = l.assignment["p1"]
	var b: String = l.assignment["p2"]
	l.assign_pilot("p1", b)
	expect_eq(l.assignment["p1"], b)
	expect_eq(l.assignment["p2"], a)
	expect_eq(l.host.state.unit("p1").name, l.campaign.pilots[b]["callsign"])


func test_illegal_builds_block_the_start() -> void:
	var l := _lobby(2)
	l.set_local_ready(true)
	var p: Dictionary = l.campaign.pilots[l.assignment["p2"]]
	p["mechs"][0]["frame"] = "mf_blackbeard"
	l.set_mode("p2", "ai")
	var problems := l.start_problems()
	expect(not problems.is_empty() and problems[0].contains("isn't legal"), str(problems))


func test_mismatch_messages_for_joining_players() -> void:
	var l := _lobby()
	l.campaign.packs = [{"id": "x", "name": "Long Rim", "version": "1.0"}]
	l.host.state.packs = l.campaign.packs
	var hub := LoopbackTransport.Hub.new()
	l.host.open_room(LoopbackTransport.new(hub), "LOBBY2")
	var friend := NetClient.new(LoopbackTransport.new(hub))
	var mirror := LobbyModel.for_client(friend)
	friend.join("LOBBY2", "Dee")
	_pump(l, [friend])
	expect_eq(mirror.messages.size(), 1)
	expect(mirror.messages[0]["text"].contains("Long Rim 1.0"), str(mirror.messages))
	expect(not l.start_problems().is_empty() and l.start_problems()[0].contains("not installed"), "the host is told too")


static func _pump(l: LobbyModel, clients: Array) -> void:
	for i in range(8):
		l.host.poll()
		for c: NetClient in clients:
			c.poll()
