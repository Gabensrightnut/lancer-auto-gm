extends TestCase
## A story campaign played online over the in-memory transport: a friend joins the host at the
## hub (taking the AI squadmate's seat), sees the host's story, sends their pilot build (checked
## by the host), follows the host into the battle, plays their own mech, and gets the debrief
## back at the hub. Also: level-up picks made in the builder stop waiting.

const Flow := preload("res://tests/unit/test_flow_campaign.gd")
const Tut := preload("res://tests/unit/test_flow_tutorial.gd")
const MissionTest := preload("res://tests/unit/test_gm_mission.gd")

var store: SaveStore


func _store() -> SaveStore:
	store = SaveStore.new("user://test_story_online_%d" % Time.get_ticks_usec())
	return store


func _cleanup() -> void:
	GameFlow.leave_story_online()
	preload("res://tests/unit/test_campaign_saves.gd")._remove(store.dir)


static func _pump(host: NetHost, friend: NetClient, n: int = 10) -> void:
	for i in range(n):
		host.poll()
		friend.poll(0.1)


func test_friend_plays_a_story_campaign_with_the_host() -> void:
	_store()
	var db := MissionTest.db()
	GameFlow.story = null
	var c := GameFlow.start_tutorial(store, db, "Ama Okafor", "Bluebird")
	var host := GameFlow.host_story_online(c, db, store, ["p1"])
	var net := LoopbackTransport.Hub.new()
	host.open_room(LoopbackTransport.new(net), "STORY1")
	var friend := NetClient.new(LoopbackTransport.new(net))
	var friend_lobby := LobbyModel.for_client(friend)
	friend.join("STORY1", "Dee")
	_pump(host, friend)
	expect_eq(friend.seat, "p2", "the friend takes the AI squadmate's seat")
	expect(not GameFlow.story.is_ai("p2"), "the friend plays that pilot now, not the AI")
	expect(not friend_lobby.story_payload.is_empty(), "the friend's lobby hears it's a story campaign (goes to the hub)")
	var sc := GameFlow.join_story(friend, db, friend_lobby.story_payload)
	expect(sc.story != null and sc.story.phase == "briefing", "the friend sees the host's hub")

	# The host's hub UI acts through the session: the friend's mirror follows.
	var engine := StoryHostEngine.new(db, GameFlow.story_session)
	engine.submit(GameFlow.story, c, {"type": "choose_hook", "seat": "gm", "params": {"hook": GameFlow.story.hooks[0]["id"]}})
	_pump(host, friend)
	expect(not sc.story.current_hook.is_empty(), "the friend sees the job the squad took")

	# The friend's pilot build goes to the host, which checks it.
	var mine := str(GameFlow.story.pilot_of_seat("p2"))
	var b := BuilderModel.new(db, (sc.campaign.pilots[mine] as Dictionary).duplicate(true))
	expect_eq(b.set_skill("sk_spot", 1), "")
	GameFlow.builder_done(sc.campaign, b, store)
	_pump(host, friend)
	expect_eq(int(c.pilots[mine]["skills"].get("sk_spot", 0)), 1, "the host took the friend's legal build")
	var refused: Array = []
	sc.refused.connect(func(why: String, _r: String) -> void: refused.append(why))
	var cheat := (c.pilots[mine] as Dictionary).duplicate(true)
	cheat["skills"] = {"sk_spot": 3, "sk_charm": 3}
	friend.transport.send(NetTransport.HOST_PEER, {"t": NetProtocol.LOBBY, "pilot_update": cheat})
	var theirs := (c.pilots[str(GameFlow.story.pilot_of_seat("p1"))] as Dictionary).duplicate(true)
	theirs["callsign"] = "Hacked"
	friend.transport.send(NetTransport.HOST_PEER, {"t": NetProtocol.LOBBY, "pilot_update": theirs})
	_pump(host, friend)
	expect_eq(refused.size(), 2, "an over-budget build and someone else's pilot are refused: %s" % str(refused))
	expect(str(c.pilots[str(GameFlow.story.pilot_of_seat("p1"))]["callsign"]) != "Hacked")

	# Boots on the ground: the friend follows the host into the battle on the same connection.
	var guard := 0
	while Dialogue.is_open(GameFlow.story) and guard < 50:
		guard += 1
		var o := Dialogue.offered(GameFlow.story)
		GameFlow.story_session.submit("gm", {"type": "dialogue_next", "seat": "gm", "params": {}} if o.is_empty() else {"type": "dialogue_choose", "seat": "gm", "params": {"choice": o[0]["id"]}})
	var deploy := GameFlow.story_session.submit("gm", {"type": "confirm_reserves", "seat": "gm", "params": {}})
	expect(deploy["ok"], str(deploy.get("reason", "")))
	var started: Array = []
	friend.lobby_updated.connect(func(d: Dictionary) -> void:
		if d.get("started", false):
			started.append(true))
	GameFlow.story_client = null  # (one process plays both sides; the host's own calls follow)
	var hs := GameFlow.start_story_mission(c, db, store, ["p1"])
	expect(hs != null)
	if hs == null:
		_cleanup()
		return
	expect(hs.host == host, "the same room carries the battle")
	expect(not hs.host.is_ai_seat("p2"), "the friend flies their own mech")
	hs.start()
	for i in range(8):
		hs.poll(0.0)
		friend.poll(0.1)
	expect(not started.is_empty(), "the friend's hub hears the battle started")
	var fs := BattleSession.for_client(friend)
	var hp := Flow.ScriptedPlayer.new(hs)
	var fp := Flow.ScriptedPlayer.new(fs)
	Flow.play_out([hs, fs], [hp, fp], 6000)
	expect(hs.over and fs.over, "both saw the end")
	expect(fp.turns > 0, "the friend played their own turns")
	GameFlow.finish_mission(hs, c, store, db)
	_pump(host, friend)
	expect_eq(sc.story.phase, "debrief", "the friend's hub shows the debrief")
	_cleanup()


func test_level_up_picks_made_in_the_builder_stop_waiting() -> void:
	_store()
	var db := MissionTest.db()
	GameFlow.story = null
	var c := GameFlow.start_tutorial(store, db)
	GameFlow.story.phase = "debrief"
	var r := GameFlow.story_engine.submit(GameFlow.story, c, {"type": "level_up", "seat": "gm", "params": {}})
	expect(r["ok"], str(r.get("reason", "")))
	var pid := GameFlow.story.pilot_of_seat("p1")
	var picks: Dictionary = GameFlow.story.pending_picks[pid]
	expect_eq(int(picks["license"]), 1)
	var b := BuilderModel.new(db, c.pilots[pid])
	expect_eq(b.set_license("mf_blackbeard", 1), "")
	GameFlow.builder_done(c, b, store)
	expect_eq(int(GameFlow.story.pending_picks[pid]["license"]), 0, "the license rank was picked in the builder")
	expect(int(GameFlow.story.pending_picks[pid]["talent"]) > 0, "talent ranks still to pick")
	var saved := StoryState.of(store.load_campaign(c.id)["campaign"])
	expect_eq(int(saved.pending_picks[pid]["license"]), 0, "saved")
	_cleanup()
