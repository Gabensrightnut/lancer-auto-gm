extends TestCase
## "Human GM" (campaign option): a person in the GM seat, here or online. They see the GM's
## whole picture (battle and story), get the story's GM tools, and reveal the twist themselves;
## the AI still flies the enemies. Nobody can join as the GM otherwise.

const MissionTest := preload("res://tests/unit/test_gm_mission.gd")
const Online := preload("res://tests/unit/test_flow_story_online.gd")

var store: SaveStore


func test_joining_as_the_gm_only_when_the_host_set_one_up() -> void:
	var c := Campaign.create("GM seat")
	var lobby := LobbyModel.for_host(c, MissionTest.db(), 31)
	var net := LoopbackTransport.Hub.new()
	lobby.host.open_room(LoopbackTransport.new(net), "GMSEAT")
	var sneaky := NetClient.new(LoopbackTransport.new(net))
	var why: Array = []
	sneaky.refused.connect(func(_c: String, r: String) -> void: why.append(r))
	sneaky.join("GMSEAT", "Sneaky", NetHost.GM_SEAT)
	Online._pump(lobby.host, sneaky)
	expect(sneaky.seat != NetHost.GM_SEAT and not why.is_empty(), "the AI is the GM: no GM seat to take")

	lobby.set_human_gm(true, "remote")
	expect_eq(lobby.gm_status(), "waiting")
	expect(lobby.start_problems().any(func(p: String) -> bool: return p.contains("GM to join")), "the lobby waits for the GM")
	var gm := NetClient.new(LoopbackTransport.new(net))
	gm.join("GMSEAT", "Gail", NetHost.GM_SEAT)
	Online._pump(lobby.host, gm)
	expect_eq(gm.seat, NetHost.GM_SEAT)
	expect_eq(lobby.gm_status(), "joined")
	expect(lobby.host.is_ai_seat(NetHost.GM_SEAT), "the AI still flies the enemies")
	expect(c.options["human_gm"] and c.options["gm_where"] == "remote", "kept in the campaign")
	var enemy := ""
	for id: String in lobby.host.state.units:
		if lobby.host.state.units[id].side == Mission.ENEMIES:
			enemy = id
	var as_player := lobby.host.view_filter.view_for(lobby.host.state, "p1")
	expect((gm.view["units"][enemy] as Dictionary).size() > (as_player["units"][enemy] as Dictionary).size(), "the GM sees the enemies' full stats")

	lobby.set_human_gm(true, "local")
	expect(NetHost.GM_SEAT in lobby.host.local_seats, "a GM at this screen")
	lobby.set_human_gm(false)
	expect(not NetHost.GM_SEAT in lobby.host.local_seats and not lobby.host.human_gm)


func test_an_online_gm_gets_the_secrets_players_dont() -> void:
	store = SaveStore.new("user://test_human_gm_%d" % Time.get_ticks_usec())
	var db := MissionTest.db()
	GameFlow.story = null
	var c := GameFlow.start_tutorial(store, db, "Ama Okafor", "Bluebird")
	c.options["human_gm"] = true
	c.options["gm_where"] = "remote"
	var host := GameFlow.host_story_online(c, db, store, ["p1"])
	var net := LoopbackTransport.Hub.new()
	host.open_room(LoopbackTransport.new(net), "GMSTORY")
	var gm := NetClient.new(LoopbackTransport.new(net))
	var gm_lobby := LobbyModel.for_client(gm)
	gm.join("GMSTORY", "Gail", NetHost.GM_SEAT)
	var friend := NetClient.new(LoopbackTransport.new(net))
	var friend_lobby := LobbyModel.for_client(friend)
	friend.join("GMSTORY", "Dee")
	for i in range(10):
		host.poll()
		gm.poll(0.1)
		friend.poll(0.1)
	expect_eq(gm.seat, NetHost.GM_SEAT)
	expect_eq(friend.seat, "p2")
	var gsc := StoryClient.new(db, gm.seat)
	gsc.attach_net_client(gm)
	gsc.receive(gm_lobby.story_payload)
	var fsc := StoryClient.new(db, friend.seat)
	fsc.attach_net_client(friend)
	fsc.receive(friend_lobby.story_payload)
	var hook := str(GameFlow.story.hooks[0]["id"])
	var r := gsc.submit(gsc.story, gsc.campaign, {"type": "gm_twist", "params": {"hook": hook, "do": "set", "reveal": "The client is the raider.", "question": "Who paid?"}})
	expect(r["ok"], str(r.get("reason", "")))
	r = fsc.submit(fsc.story, fsc.campaign, {"type": "gm_twist", "params": {"hook": hook, "do": "set", "reveal": "Nope"}})
	expect(not r["ok"], "a player can't use the GM tools")
	for i in range(10):
		host.poll()
		gm.poll(0.1)
		friend.poll(0.1)
	expect_eq(str(GameFlow.story.hooks[0].get("twist", {}).get("reveal", "")), "The client is the raider.", "the remote GM's tool ran on the host")
	expect_eq(str(gsc.story.hooks[0].get("twist", {}).get("reveal", "")), "The client is the raider.", "the GM sees the hidden twist")
	expect(not fsc.story.hooks[0].has("twist"), "the players don't")
	GameFlow.leave_story_online()
	preload("res://tests/unit/test_campaign_saves.gd")._remove(store.dir)


func test_the_human_gm_reveals_the_twist_not_the_ai() -> void:
	var gen := MissionGenerator.generate(707, {"db": MissionTest.db(), "size": 20, "players": 1, "sitrep": "sitrep_standardcombat", "environments": [], "weather": "clear"})
	var state: GameState = gen["state"]
	var mission: Mission = gen["mission"]
	var host := NetHost.new(state, RulesEngine.new())
	host.human_gm = true
	host.add_local_seat(NetHost.GM_SEAT)
	var director := AiDirector.new(host, GmSettings.from_preset("Standard"), mission)
	var s := BattleSession.for_host(host, director, mission, [NetHost.GM_SEAT])
	expect(s.gm_here and s.local_humans().is_empty())
	expect_eq(Array(s.hot.seats), [NetHost.GM_SEAT], "no pilot here: the GM watches from their seat")
	expect(director.step(), "the AI still starts the battle")
	expect_eq(state.phase, GameState.PHASE_COMBAT)
	mission.flavor["arrival_told"] = true
	mission.flavor["environment_told"] = true
	mission.flavor["twist"] = {"id": "t1", "reveal": "Reinforcements were never coming."}
	mission.flavor["twist_due"] = true
	expect(not director._maybe_narrate(), "the AI leaves the twist to the human GM")
	var told: Array = []
	host.action_resolved.connect(func(_seat: String, _a: Dictionary, _r: RuleResult, evs: Array) -> void: told.append_array(evs))
	expect(s.gm_reveal_twist({"id": "t1", "reveal": "Reinforcements were never coming."}))
	expect(told.any(func(e: Dictionary) -> bool: return e["type"] == "twist_revealed"), "narrated in the battle")
	expect(bool(mission.flavor["twist_revealed"]))
