extends TestCase
## The map editor's hooks: a saved map in the lobby (and "Play this map"), and a human GM's
## live edits reaching every seat.

const MissionTest := preload("res://tests/unit/test_gm_mission.gd")
const Online := preload("res://tests/unit/test_flow_story_online.gd")


func test_a_saved_map_in_the_lobby() -> void:
	var doc := MapDoc.generated(5, 24, 22, GridLayout.Shape.SQUARE, "sitrep_control", "grassy_hills")
	doc.name = "Ridge test"
	var lobby := LobbyModel.for_host(Campaign.create("Maps"), MissionTest.db(), 41)
	lobby.set_map_doc(doc)
	expect_eq(lobby.options["map"], "Ridge test")
	expect_eq(lobby.mission.sitrep_id, "sitrep_control", "the map's own sitrep")
	var st := lobby.host.state
	var c := Vector2i(3, 3)
	expect_eq(st.map.ground_height(c), doc.map.ground_height(c), "the battle is fought on the saved terrain")
	lobby.set_map("")
	expect(lobby.map_doc == null and lobby.options["map"] == "", "back to a generated map")


func test_live_edits_reach_every_seat() -> void:
	var gen := MissionGenerator.generate(515, {"db": MissionTest.db(), "size": 20, "players": 1, "sitrep": "sitrep_standardcombat", "environments": []})
	var host := NetHost.new(gen["state"], RulesEngine.new())
	host.human_gm = true
	host.add_local_seat(NetHost.GM_SEAT)
	var net := LoopbackTransport.Hub.new()
	host.open_room(LoopbackTransport.new(net), "MAPEDT")
	var friend := NetClient.new(LoopbackTransport.new(net))
	friend.join("MAPEDT", "Dee")
	Online._pump(host, friend)
	var m := MapEditorModel.new()
	m.start_live(host.engine, host.state)
	m.changed.connect(func(events: Array) -> void: host.send_updates(events))  # what the battle screen does
	var taken := {}
	for u: Unit in host.state.units.values():
		taken[u.cell] = true
	var free := Vector2i(-1, -1)
	for cell in host.state.map.cells():
		if not taken.has(cell) and cell.y > 8 and cell.y < 12:
			free = cell
			break
	expect(free != Vector2i(-1, -1))
	var before := host.state.map.ground_height(free)
	var evs := m.paint([free], "raise")
	expect(not evs.is_empty(), m.last_error)
	Online._pump(host, friend)
	var seen := BattleMap.from_dict(friend.view["map"])
	expect_eq(seen.ground_height(free), before + 1, "the friend's board has the GM's edit")
