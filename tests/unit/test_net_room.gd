extends TestCase
## NetRoom: one online room, several areas at once (exploring). Friends only see the area they
## are in, act there, keep their seat when they move, and come back after a drop.

const F = preload("res://tests/unit/test_rules_fixtures.gd")


func _area(prefix: String) -> NetHost:
	var s := F.state()
	s.seats = {"p1": {"name": "Ama", "side": "players"}, "p2": {"name": "Rin", "side": "players"}}
	F.mech(s, prefix + "_ama", "players", Vector2i(0, 0))
	F.mech(s, prefix + "_rin", "players", Vector2i(2, 0))
	s.unit(prefix + "_ama").controller = "p1"
	s.unit(prefix + "_rin").controller = "p2"
	var host := NetHost.new(s, RulesEngine.new())
	host.add_local_seat("p1")
	return host


func _pump(room: NetRoom, clients: Array, n: int = 8) -> void:
	for i in range(n):
		room.poll()
		for c: NetClient in clients:
			c.poll(0.1)


func test_friends_explore_different_places_and_keep_their_seat() -> void:
	var town := _area("town")
	var pan := _area("pan")
	var room := NetRoom.new()
	room.add_area("town", town)
	room.add_area("saltpan", pan)
	var hub := LoopbackTransport.Hub.new()
	room.open(LoopbackTransport.new(hub), "AREAS1")
	var rin := NetClient.new(LoopbackTransport.new(hub))
	var joins: Array = []
	rin.joined.connect(func(s: String) -> void: joins.append(s))
	rin.join("AREAS1", "Rin", "p2")
	_pump(room, [rin])
	expect_eq(rin.seat, "p2")
	expect_eq(room.area_of("p2"), "town")
	expect(rin.view.get("units", {}).has("town_rin"), "sees the town")
	var token := rin.token

	expect(room.move_seat("p2", "saltpan"))
	_pump(room, [rin])
	expect(rin.view.get("units", {}).has("pan_rin") and not rin.view.get("units", {}).has("town_rin"), "now sees only the Saltpan")
	expect_eq(joins.size(), 1, "no second welcome: the same game, another place")
	rin.submit({"type": "explore_move", "actor": "pan_rin", "params": {"to": [2, 2]}})
	_pump(room, [rin])
	expect_eq(pan.state.unit("pan_rin").cell, Vector2i(2, 2), "acts in the area it's in")
	expect_eq(town.state.unit("town_rin").cell, Vector2i(2, 0), "not in the town")
	town.submit("p1", {"type": "explore_move", "actor": "town_ama", "params": {"to": [0, 2]}})
	_pump(room, [rin])
	expect(not rin.view.get("units", {}).has("town_ama"), "town updates don't reach the Saltpan")

	expect(room.move_seat("p2", "town"))
	_pump(room, [rin])
	expect_eq(rin.seat, "p2", "back in town, same seat")
	expect(rin.view.get("units", {}).has("town_rin"))

	# A drop and a reconnect with the room's token: back in the area they were in.
	room.move_seat("p2", "saltpan")
	_pump(room, [rin])
	rin.transport.close()
	_pump(room, [])
	var again := NetClient.new(LoopbackTransport.new(hub))
	again.token = token
	again.join("AREAS1", "Rin")
	_pump(room, [again])
	expect_eq(again.seat, "p2", "reconnected to the same seat")
	expect(again.view.get("units", {}).has("pan_rin"), "in the Saltpan, where they were")
