extends TestCase
## House rules (HouseRules, HouseRulesFlow): the registry, the GM's set_house_rules action, who
## decides (a human GM, else the host), and the set reaching everyone's view and the save.

const MissionTest := preload("res://tests/unit/test_gm_mission.gd")
const Online := preload("res://tests/unit/test_flow_story_online.gd")


## No battle, story or preferences left over from other tests.
func _fresh() -> void:
	HouseRulesFlow.mine = {}
	GameFlow.session = null
	GameFlow.story_client = null
	GameFlow.story_session = null


func _battle() -> Dictionary:
	var gen := MissionGenerator.generate(909, {"db": MissionTest.db(), "size": 20, "players": 2, "sitrep": "sitrep_standardcombat", "environments": [], "weather": "clear"})
	var host := NetHost.new(gen["state"], RulesEngine.new())
	var director := AiDirector.new(host, GmSettings.from_preset("Standard"), gen["mission"])  # registers the GM actions
	return {"host": host, "director": director, "state": gen["state"]}


func test_registry_and_the_lancer_tactics_switches() -> void:
	_fresh()
	var d := HouseRules.defaults()
	expect(d["lt_split_barrage"] and d["lt_brace_prompt"] and not d["lt_repeat_quick_tech"], "the user's Lancer Tactics picks")
	for r: Dictionary in HouseRules.all():
		expect(str(r.get("source", "")) in HouseRules.sources(), "%s says where it's from" % r["id"])
		expect(str(r.get("description", "")) != "" and str(r.get("name", "")) != "")
	var systems := HouseRules.all().map(func(r: Dictionary) -> String: return str(r["system"]))
	expect(systems.has("rules") and systems.has("story"), "the rules engine's and the story's, in one list")
	expect(not HouseRules.is_battle_rule("hr_wallet") and HouseRules.is_battle_rule("lt_split_barrage"))
	var state := GameState.new()
	HouseRules.put(state, {})
	expect(HouseRules.on(state, "lt_split_barrage"), "on by default")
	HouseRules.put(state, {"lt_split_barrage": false})
	expect(not HouseRules.on(state, "lt_split_barrage"), "off: the book's Barrage")
	expect(state.house_rules.has("hr_wallet"), "the whole set goes into the battle")
	var c := Campaign.create("HR")
	c.options["house_rules"] = {"lt_repeat_quick_tech": true}
	var st := GameState.new()
	c.prepare_mission(st)
	expect(HouseRules.on(st, "lt_repeat_quick_tech"), "the campaign's set goes into the battle")


func test_the_gm_flips_one_mid_battle_and_everyone_is_told() -> void:
	_fresh()
	var b := _battle()
	var host: NetHost = b["host"]
	var state: GameState = b["state"]
	HouseRules.put(state, {})
	var out := host.submit(NetHost.GM_SEAT, {"type": "set_house_rule", "params": {"id": "lt_repeat_quick_tech", "on": true}})
	expect((out["result"] as RuleResult).ok, (out["result"] as RuleResult).reason)
	var ev: Array = (out["events"] as Array).filter(func(e: Dictionary) -> bool: return e["type"] == "house_rule_changed")
	expect(ev.size() == 1, "announced: %s" % str(ev))
	expect(HouseRules.announce("lt_repeat_quick_tech", true).contains("not a book rule"))
	expect(HouseRules.on(state, "lt_repeat_quick_tech"))
	var p1 := host.submit("p1", {"type": "set_house_rule", "params": {"id": "lt_repeat_quick_tech", "on": false}})
	expect(not (p1["result"] as RuleResult).ok, "a player can't change them")
	var saved := GameState.from_dict(state.to_dict())
	expect(HouseRules.on(saved, "lt_repeat_quick_tech"), "saved with the battle")


func test_who_decides() -> void:
	_fresh()
	var c := Campaign.create("Who")
	expect(HouseRulesFlow.i_decide(c), "the AI is the GM: the host decides")
	c.options["human_gm"] = true
	c.options["gm_where"] = "local"
	expect(HouseRulesFlow.i_decide(c), "the GM is at the host's computer")
	c.options["gm_where"] = "remote"
	expect(not HouseRulesFlow.i_decide(c), "a friend is the GM: not the host")
	HouseRulesFlow.mine = {"lt_split_barrage": false}
	expect(HouseRulesFlow.push(c) != "", "the host's switch doesn't change the GM's game")
	expect(HouseRules.on_campaign(c, "lt_split_barrage"), "unchanged")
	c.options["human_gm"] = false
	expect_eq(HouseRulesFlow.push(c), "")
	expect(not HouseRules.on_campaign(c, "lt_split_barrage"), "the host's set, the AI being the GM")


func test_an_online_gm_decides_and_players_see_it() -> void:
	_fresh()
	var b := _battle()
	var host: NetHost = b["host"]
	host.human_gm = true
	var net := LoopbackTransport.Hub.new()
	host.open_room(LoopbackTransport.new(net), "HRULES")
	var gm := NetClient.new(LoopbackTransport.new(net))
	gm.join("HRULES", "Gail", NetHost.GM_SEAT)
	var player := NetClient.new(LoopbackTransport.new(net))
	player.join("HRULES", "Dee")
	for i in range(10):
		host.poll()
		gm.poll(0.1)
		player.poll(0.1)
	expect_eq(gm.seat, NetHost.GM_SEAT)
	var told: Array = []
	player.view_updated.connect(func(_v: Dictionary, evs: Array) -> void: told.append_array(evs.filter(func(e: Dictionary) -> bool: return e["type"] == "house_rule_changed")))
	gm.submit({"type": "set_house_rule", "params": {"id": "lt_brace_prompt", "on": false}})
	var refused: Array = []
	player.action_answered.connect(func(_id: int, r: Dictionary) -> void:
		if not bool(r.get("ok", false)):
			refused.append(r))
	player.submit({"type": "set_house_rule", "params": {"id": "lt_brace_prompt", "on": true}})
	for i in range(10):
		host.poll()
		gm.poll(0.1)
		player.poll(0.1)
	expect(not HouseRules.on(host.state, "lt_brace_prompt"), "the GM's switch reached the host")
	expect(not bool(player.view["house_rules"]["lt_brace_prompt"]), "the player's view has it")
	expect(not told.is_empty(), "and the player was told")
	expect_eq(refused.size(), 1, "the player can't flip it")


func test_between_battles_only_the_gm_seat_is_heard() -> void:
	_fresh()
	var c := Campaign.create("Lobby HR")
	var lobby := LobbyModel.for_host(c, MissionTest.db(), 33)
	lobby.set_human_gm(true, "remote")
	var net := LoopbackTransport.Hub.new()
	lobby.host.open_room(LoopbackTransport.new(net), "HRLOBY")
	var gm := NetClient.new(LoopbackTransport.new(net))
	gm.join("HRLOBY", "Gail", NetHost.GM_SEAT)
	var player := NetClient.new(LoopbackTransport.new(net))
	player.join("HRLOBY", "Dee")
	for i in range(10):
		lobby.host.poll()
		gm.poll(0.1)
		player.poll(0.1)
	player.transport.send(NetTransport.HOST_PEER, {"t": NetProtocol.LOBBY, "house_rules": {"lt_split_barrage": false}})
	for i in range(5):
		lobby.host.poll()
	expect(HouseRules.on_campaign(c, "lt_split_barrage"), "a player's message is ignored")
	HouseRulesFlow.mine = {"lt_split_barrage": false}
	expect_eq(HouseRulesFlow.push(null, null, gm), "")
	for i in range(5):
		lobby.host.poll()
	expect(not HouseRules.on_campaign(c, "lt_split_barrage"), "the GM's set is the campaign's")
	expect(not HouseRules.on(lobby.host.state, "lt_split_barrage"), "and the battle about to start")
	expect(lobby.messages.any(func(m: Dictionary) -> bool: return str(m["text"]).contains(str(HouseRules.rule("lt_split_barrage")["name"]))), "announced in the lobby")


## A story campaign online, mid-battle: the host (the AI is the GM) flips a battle rule and a
## story rule. The battle rule reaches the rules engine and the friend's battle view, the story
## rule the story (announced) and the friend's story mirror; both are kept in the campaign.
func test_a_flip_mid_battle_reaches_both_and_the_friends() -> void:
	_fresh()
	var store := SaveStore.new("user://test_house_rules_%d" % Time.get_ticks_usec())
	var db := MissionTest.db()
	GameFlow.story = null
	var c := GameFlow.start_tutorial(store, db, "Ama Okafor", "Bluebird")
	var host := GameFlow.host_story_online(c, db, store, ["p1"])
	var net := LoopbackTransport.Hub.new()
	host.open_room(LoopbackTransport.new(net), "HRBATL")
	var friend := NetClient.new(LoopbackTransport.new(net))
	var friend_lobby := LobbyModel.for_client(friend)
	friend.join("HRBATL", "Dee")
	Online._pump(host, friend)
	var sc := GameFlow.join_story(friend, db, friend_lobby.story_payload)
	GameFlow.story_client = null  # (one process plays both sides: this is the host's turn)
	var engine := StoryHostEngine.new(db, GameFlow.story_session)
	engine.submit(GameFlow.story, c, {"type": "choose_hook", "seat": "gm", "params": {"hook": GameFlow.story.hooks[0]["id"]}})
	var guard := 0
	while Dialogue.is_open(GameFlow.story) and guard < 50:
		guard += 1
		var o := Dialogue.offered(GameFlow.story)
		GameFlow.story_session.submit("gm", {"type": "dialogue_next", "seat": "gm", "params": {}} if o.is_empty() else {"type": "dialogue_choose", "seat": "gm", "params": {"choice": o[0]["id"]}})
	GameFlow.story_session.submit("gm", {"type": "confirm_reserves", "seat": "gm", "params": {}})
	var hs := GameFlow.start_story_mission(c, db, store, ["p1"])
	expect(hs != null)
	if hs == null:
		return
	hs.start()
	for i in range(8):
		hs.poll(0.0)
		friend.poll(0.1)
	var fs := BattleSession.for_client(friend)
	expect(not HouseRules.on(hs.host.state, "lt_repeat_quick_tech"))
	var story_told: Array = []
	GameFlow.story_session.updated.connect(func(_v: Dictionary, evs: Array) -> void:
		story_told.append_array(evs.filter(func(e: Dictionary) -> bool: return e["type"] == "house_rule_changed")))
	HouseRulesFlow.mine = {"lt_repeat_quick_tech": true, "hr_wallet": true}
	expect_eq(HouseRulesFlow.push(c, store), "")
	for i in range(10):
		hs.poll(0.0)
		friend.poll(0.1)
	expect(HouseRules.on(hs.host.state, "lt_repeat_quick_tech"), "the battle rule reached the rules engine")
	expect(bool(fs.view.get("house_rules", {}).get("lt_repeat_quick_tech", false)), "and the friend's battle view")
	expect(HouseRules.on_campaign(c, "hr_wallet") and HouseRules.on_campaign(c, "lt_repeat_quick_tech"), "both kept in the campaign")
	expect_eq(story_told.size(), 1, "the story rule went through the story and was announced once")
	expect(StoryHouseRules.on(sc.campaign, "hr_wallet"), "the friend's story sees it")
	GameFlow.leave_story_online()
	GameFlow.session = null
	preload("res://tests/unit/test_campaign_saves.gd")._remove(store.dir)
