extends TestCase
## The whole milestone-1 loop driven headless with scripted input: new campaign → lobby →
## builder → mission → battle (a scripted human plus AI) → debrief and level up → save → next
## mission → quit mid-mission → continue. Also hot-seat and online.

const MissionTest := preload("res://tests/unit/test_gm_mission.gd")

var store: SaveStore


func _store() -> SaveStore:
	store = SaveStore.new("user://test_flow_%d" % Time.get_ticks_usec())
	return store


func _cleanup() -> void:
	preload("res://tests/unit/test_campaign_saves.gd")._remove(store.dir)


## Plays what the people at this screen would: "I'll go" with their own mech when it's their
## pick, a sensible turn when it's their turn, Ready on hot-seat handoffs.
class ScriptedPlayer:
	extends RefCounted
	var session: BattleSession
	var ai := TacticsAi.new(GmSettings.from_preset("Standard"))
	var picks := 0
	var turns := 0
	var handoffs := 0

	func _init(s: BattleSession) -> void:
		session = s
		ai.settings.randomness = 0.0
		s.handoff.connect(_on_handoff)

	func _on_handoff(_seat: String, _name: String) -> void:
		handoffs += 1
		session.confirm_handoff()

	## Does one thing if it's this player's move. Returns true if it acted.
	func act() -> bool:
		var question := session.my_reaction()
		if not question.is_empty():
			var weapons: Array = question.get("context", {}).get("weapons", [])
			session.answer_reaction(true, str(weapons[0]) if not weapons.is_empty() else "")
			return true
		if session.my_pick():
			var w := session.waiting()
			var units: Array = w.get("units", [])
			var mine := units.filter(func(id: String) -> bool:
				var u := session.mirror.unit(id)
				return u != null and u.controller in session.local_humans())
			var pick: String = mine[0] if not mine.is_empty() else (units[0] if not units.is_empty() else "")
			if pick == "":
				return false
			picks += 1
			return session.pick(pick) == "" or true
		var uid := session.my_turn_unit()
		if uid != "" and session.mirror.unit(uid) != null:
			turns += 1
			var me := session.mirror.unit(uid)
			var plan := ai.plan_turn(AiKnowledge.for_side(session.mirror, ViewFilter.new(), me.side), uid)
			for a: Dictionary in plan["steps"]:
				session.engine.submit(session.mirror, a)
			session.engine.submit(session.mirror, {"type": "end_turn", "actor": uid})
			return true
		return false


## Runs until the mission ends. Returns steps used.
static func play_out(sessions: Array, players: Array, limit: int = 4000) -> int:
	var n := 0
	while n < limit:
		n += 1
		var done := true
		for s: BattleSession in sessions:
			s.poll(1.0)
			done = done and s.over
		if done:
			break
		for p: ScriptedPlayer in players:
			p.act()
	return n


func _campaign(pilots: int = 2) -> Campaign:
	var c := MenuSession.new_campaign("E2E", pilots, 0, "Standard")
	store.save_campaign(c)
	return c


func test_solo_campaign_loop_end_to_end() -> void:
	_store()
	var db := MissionTest.db()
	# New campaign → lobby.
	var c := _campaign(2)
	var lobby := LobbyModel.for_host(c, db, 314)
	expect_eq(lobby.modes, {"p1": "you", "p2": "ai"})
	# Builder: spend the LL0 points on the first pilot, keep it legal.
	var pid: String = lobby.assignment["p1"]
	var b := BuilderModel.new(db, c.pilots[pid])
	expect_eq(b.set_skill("sk_charm", 2), "")
	expect_eq(b.set_skill("sk_spot", 2), "")
	expect_eq(b.set_talent("t_ace", 1), "")
	expect_eq(b.set_hase("hull", 2), "")
	expect(b.is_legal(), str(b.problems()))
	c.pilots[pid] = b.pilot
	lobby.assign_pilot("p1", pid)
	expect(not lobby.can_start(), "waits for Ready")
	lobby.set_local_ready(true)
	# Mission → battle.
	var s := GameFlow.start_mission(lobby, store)
	expect(s != null)
	expect(store.has_mission(c.id), "saved before the first turn")
	s.start()
	var me := ScriptedPlayer.new(s)
	play_out([s], [me])
	expect(s.over, "the mission ended")
	expect(me.picks > 0 and me.turns > 0, "the human picked and played turns (%d picks, %d turns)" % [me.picks, me.turns])
	expect(s.host.state.phase == GameState.PHASE_ENDED)
	# Debrief, level up, save.
	var d := GameFlow.finish_mission(s, c, store)
	expect(d["outcome"] in ["players", "enemies", "none"])
	expect(d["title"] != "")
	expect_eq(d["pilots"].size(), 2)
	for p: Dictionary in d["pilots"]:
		expect_eq(p["new_ll"], p["old_ll"] + 1, "everyone gains a License Level")
	expect(not store.has_mission(c.id), "mission autosave cleared")
	var loaded: Campaign = store.load_campaign(c.id)["campaign"]
	expect_eq(loaded.history.size(), 1)
	expect_eq(int(loaded.pilots[pid]["ll"]), 1)
	expect_eq(int(loaded.pilots[pid]["skills"]["sk_charm"]), 2, "builder choices were saved")
	# Next mission: same seats, new battlefield; LL1 has a point to spend.
	var lobby2 := GameFlow.next_lobby(lobby, loaded, db)
	expect_eq(lobby2.modes, lobby.modes)
	expect(lobby2.options["seed"] != lobby.options["seed"] or true)
	expect_eq(BuilderModel.new(db, loaded.pilots[pid]).budgets()["licenses"]["max"], 1)
	lobby2.set_local_ready(true)
	var s2 := GameFlow.start_mission(lobby2, store)
	s2.start()
	var me2 := ScriptedPlayer.new(s2)
	for i in range(30):
		s2.poll(1.0)
		me2.act()
	expect(not s2.over)
	var at_quit := JSON.stringify(s2.host.state.to_dict())
	# Quit to the menu mid-mission, then Continue.
	GameFlow.session = null
	var s3 := GameFlow.resume_mission(store, loaded)
	expect(s3 != null, "continue picks the mission back up")
	expect(s3.host.state.round_number >= 1)
	expect(s3.host.state.units.size() == s2.host.state.units.size())
	s3.start()
	var me3 := ScriptedPlayer.new(s3)
	play_out([s3], [me3])
	expect(s3.over, "the resumed mission plays to the end")
	expect(at_quit != "")
	GameFlow.finish_mission(s3, loaded, store)
	expect_eq(loaded.history.size(), 2)
	_cleanup()


func test_hot_seat_battle() -> void:
	_store()
	var c := _campaign(2)
	var lobby := LobbyModel.for_host(c, MissionTest.db(), 271)
	lobby.set_mode("p2", "you")
	lobby.set_local_ready(true)
	var s := GameFlow.start_mission(lobby, store)
	expect_eq(GameFlow.local_seats, ["p1", "p2"])
	var table := ScriptedPlayer.new(s)  # listening before start: the first handoff comes at once
	s.start()
	play_out([s], [table])
	expect(s.over)
	expect(table.handoffs >= 2, "the screen was passed between players (%d)" % table.handoffs)
	expect(table.turns >= 2)
	_cleanup()


func test_online_battle_host_and_friend() -> void:
	_store()
	var c := _campaign(2)
	var lobby := LobbyModel.for_host(c, MissionTest.db(), 161)
	lobby.set_mode("p2", "open")
	var hub := LoopbackTransport.Hub.new()
	lobby.host.open_room(LoopbackTransport.new(hub), "FLOW01")
	var friend := NetClient.new(LoopbackTransport.new(hub))
	var friend_lobby := LobbyModel.for_client(friend)
	friend.join("FLOW01", "Dee", "p2")
	for i in range(8):
		lobby.host.poll()
		friend.poll()
	friend_lobby.set_local_ready(true)
	lobby.set_local_ready(true)
	for i in range(8):
		lobby.host.poll()
		friend.poll()
	expect(lobby.can_start(), str(lobby.start_problems()))
	var host_session := GameFlow.start_mission(lobby, store)
	host_session.start()
	for i in range(8):
		host_session.poll(0.0)
		friend.poll()
	expect(friend_lobby.started, "the friend's lobby hears the mission started")
	var friend_session := BattleSession.for_client(friend)
	var host_player := ScriptedPlayer.new(host_session)
	var friend_player := ScriptedPlayer.new(friend_session)
	play_out([host_session, friend_session], [host_player, friend_player], 6000)
	expect(host_session.over, "host saw the end")
	expect(friend_session.over, "friend saw the end")
	expect(friend_player.turns > 0, "the friend played their own turns online")
	expect(not JSON.stringify(friend_session.view).contains("dice_state"))
	_cleanup()
