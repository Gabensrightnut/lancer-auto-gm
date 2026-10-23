extends TestCase
## Story online, per player: each friend sees only their own wallet, inventory and bounty and
## the trades they're part of; public "wanted" notices for everyone; a story action repeated
## after a dropped connection runs once; the lobby shows the house rules in one line.

const MissionTest := preload("res://tests/unit/test_gm_mission.gd")


func test_each_friend_sees_only_their_own() -> void:
	var store := SaveStore.new("user://test_private_%d" % Time.get_ticks_usec())
	var db := MissionTest.db()
	GameFlow.story = null
	var c := GameFlow.start_story_campaign(store, db, "Private", 3, 0, "Standard")
	var host := GameFlow.host_story_online(c, db, store, ["p1"])
	var hub := LoopbackTransport.Hub.new()
	host.open_room(LoopbackTransport.new(hub), "PRIVTE")
	var rin := NetClient.new(LoopbackTransport.new(hub))
	var kai := NetClient.new(LoopbackTransport.new(hub))
	var rin_lobby := LobbyModel.for_client(rin)
	var kai_lobby := LobbyModel.for_client(kai)
	rin.join("PRIVTE", "Rin", "p2")
	kai.join("PRIVTE", "Kai", "p3")
	var pump := func() -> void:
		for i in range(10):
			host.poll()
			rin.poll(0.1)
			kai.poll(0.1)
	pump.call()
	var st := GameFlow.story
	var p1 := st.pilot_of_seat("p1")
	var p2 := st.pilot_of_seat("p2")
	var p3 := st.pilot_of_seat("p3")
	st.flags["_wallets"] = {p1: {"manna": 10}, p2: {"manna": 20}, p3: {"manna": 30}}
	st.flags["_bounties"] = {p2: {"Dawn": {"amount": 50, "reason": "stole a crate"}}}
	st.flags["_wanted"] = [{"pid": p2, "callsign": "Rin", "faction": "Dawn"}]
	st.flags["_trades"] = {"t1": {"from": p1, "to": p2, "offer": {"manna": 5}, "ask": {}, "state": "open"}}
	GameFlow.story_session.resync()
	pump.call()
	var rin_sc := GameFlow.join_story(rin, db, rin_lobby.story_payload)
	GameFlow.story_client = null
	var kai_sc := StoryClient.new(db, "p3")
	kai_sc.attach_net_client(kai)
	GameFlow.story_session.resync()
	pump.call()
	var rf: Dictionary = rin_sc.story.flags
	var kf: Dictionary = kai_sc.story.flags
	expect_eq((rf["_wallets"] as Dictionary).keys(), [p2], "Rin sees only her own wallet")
	expect_eq((kf["_wallets"] as Dictionary).keys(), [p3], "Kai only his")
	expect((rf["_bounties"] as Dictionary).has(p2) and (kf["_bounties"] as Dictionary).is_empty(), "the bounty's details are Rin's alone")
	expect_eq((kf["_wanted"] as Array).size(), 1, "but everyone sees the wanted notice")
	expect((rf["_trades"] as Dictionary).has("t1") and not (kf["_trades"] as Dictionary).has("t1"), "a trade only for the two in it")
	expect_eq(int(st.flags["_wallets"][p1]["manna"]), 10, "the host keeps everything")

	# A request repeated after a reconnect runs once.
	var runs := [0]
	GameFlow.story_session.updated.connect(func(_v: Dictionary, _e: Array) -> void: runs[0] += 1)
	var msg := {"story_action": {"type": "dialogue_next", "params": {}}, "id": 7, "nonce": "abc"}
	GameFlow.story_session.handle_message("p2", msg)
	var after_first: int = runs[0]
	GameFlow.story_session.handle_message("p2", msg)
	expect_eq(runs[0], after_first, "the same request again does nothing")
	GameFlow.leave_story_online()
	GameFlow.story = null
	preload("res://tests/unit/test_campaign_saves.gd")._remove(store.dir)


func test_lobby_house_rules_line() -> void:
	var none := {}
	for id: String in HouseRules.defaults():
		none[id] = false
	expect_eq(HouseRules.summary(none), "Book only")
	var line := HouseRules.summary({"lt_split_barrage": true})
	expect(line.begins_with("House rules on:") and line.contains("Lancer Tactics"), line)
	var c := Campaign.create("HR line")
	c.options["house_rules"] = none
	HouseRulesFlow.mine = none  # the host's own switches go into the battle
	var l := LobbyModel.for_host(c, MissionTest.db(), 5)
	expect_eq(HouseRules.summary(l.summary()["house_rules"]), "Book only", "the lobby's summary carries the set for friends")
	HouseRulesFlow.mine = {}
