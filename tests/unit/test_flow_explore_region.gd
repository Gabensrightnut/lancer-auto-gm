extends TestCase
## A region explored by several players at once (ExploreRegion over NetRoom): each in the area
## their unit is in, walking off an edge into the next area, a fight in one area while someone
## is elsewhere, and gathering everyone to the lead.

const F = preload("res://tests/unit/test_rules_fixtures.gd")


func _pump(r: ExploreRegion, clients: Array, n: int = 8) -> void:
	for i in range(n):
		r.poll()
		for c: NetClient in clients:
			c.poll(0.1)


func _mech(id: String, seat: String) -> Unit:
	var s := F.state()
	var u := F.mech(s, id, Mission.PLAYERS, Vector2i.ZERO)
	s.units.erase(id)
	u.controller = seat
	return u


func test_two_players_two_areas() -> void:
	var r := ExploreRegion.new(4242, {"p1": {"name": "Ama", "side": Mission.PLAYERS}, "p2": {"name": "Rin", "side": Mission.PLAYERS}}, {"place": "wilds", "size": 30})
	var home := r.area_at(Vector2i.ZERO)
	expect(r.place(_mech("ama", "p1"), Vector2i.ZERO))
	expect(r.place(_mech("rin", "p2"), Vector2i.ZERO))
	home.add_local_seat("p1")
	var hub := LoopbackTransport.Hub.new()
	r.open(LoopbackTransport.new(hub), "REGION")
	var rin := NetClient.new(LoopbackTransport.new(hub))
	rin.join("REGION", "Rin", "p2")
	_pump(r, [rin])
	expect_eq(rin.seat, "p2")
	expect(rin.view.get("units", {}).has("ama"), "both start in the same area")

	# Rin walks east, off the edge: on into the next area.
	var a: Dictionary = r.areas["0,0"]["area"]
	var east := Vector2i(int(a["entries"]["east"][0]), int(a["entries"]["east"][1]))
	var rin_u := home.state.unit("rin")
	rin_u.cell = home.state.map.grid.line(east, rin_u.cell)[2]  # a few steps from the edge
	rin.submit({"type": "explore_move", "actor": "rin", "params": {"to": [east.x, east.y]}})
	_pump(r, [rin])
	expect_eq(r.area_of("p2"), "1,0", "Rin is in the next area east")
	expect(not home.state.units.has("rin"))
	expect(r.host_of("1,0").state.units.has("rin"))
	expect(rin.view.get("units", {}).has("rin") and not rin.view.get("units", {}).has("ama"), "Rin's screen shows the new area only")
	expect_eq(r.area_of("p1"), "0,0", "Ama stayed")

	# A fight breaks out at home: Rin's area doesn't stop.
	var foe := _mech("foe", NetHost.GM_SEAT)
	foe.side = Mission.ENEMIES
	r.place(foe, Vector2i.ZERO, home.state.unit("ama").cell + Vector2i(3, 0))
	expect((home.submit(NetHost.GM_SEAT, {"type": "start_combat", "params": {"first_side": Mission.PLAYERS}})["result"] as RuleResult).ok)
	var before: Vector2i = r.host_of("1,0").state.unit("rin").cell
	rin.submit({"type": "explore_move", "actor": "rin", "params": {"to": [before.x, before.y + 2]}})
	_pump(r, [rin])
	expect(r.host_of("1,0").state.unit("rin").cell != before, "Rin keeps exploring in real time")

	# Gathering: everyone to the lead's area; Rin arrives outside the fight and can walk in.
	expect_eq(r.gather("p1"), "0,0")
	_pump(r, [rin])
	expect_eq(r.area_of("p2"), "0,0")
	expect(home.state.units.has("rin") and bool(home.state.unit("rin").counters.get("exploring", false)), "arrives near Ama, outside the fight")
	expect(rin.view.get("units", {}).has("ama"), "back on the same screen as Ama")
