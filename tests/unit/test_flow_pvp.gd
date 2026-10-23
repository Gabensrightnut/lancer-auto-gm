extends TestCase
## Player against player (PvpBattle): the squad split into two groups that fight each other.
## Each group's view is filtered for its own side, turns alternate between them, and the
## winner goes back to the story.

const MissionTest := preload("res://tests/unit/test_gm_mission.gd")
const Online := preload("res://tests/unit/test_flow_story_online.gd")


func _split(allies: Dictionary = {}) -> Dictionary:
	var gen := MissionGenerator.generate(919, {"db": MissionTest.db(), "size": 24, "players": 3, "sitrep": "sitrep_standardcombat", "environments": []})
	var why := PvpBattle.split(gen, {"a": ["p1", "p3"], "b": ["p2"]}, allies, "mutiny")
	expect_eq(why, "")
	return gen


func _unit_of(state: GameState, seat: String) -> Unit:
	for u: Unit in state.units.values():
		if u.controller == seat:
			return u
	return null


func test_the_two_groups_are_on_opposite_sides() -> void:
	var gen := _split({"b": [{"template": "ph_grunt", "count": 2, "name": "Mutineer"}]})
	var state: GameState = gen["state"]
	expect(state.units_on_side(Mission.ENEMIES).all(func(u: Unit) -> bool: return u.controller == "p2" or u.controller == NetHost.GM_SEAT), "no generated enemies, only group b and its allies")
	expect_eq(_unit_of(state, "p2").side, Mission.ENEMIES)
	expect_eq(_unit_of(state, "p1").side, Mission.PLAYERS)
	expect_eq(str(state.seats["p2"]["side"]), Mission.ENEMIES)
	expect_eq(state.units_on_side(Mission.ENEMIES).size(), 3, "p2 and two allies")
	expect_eq(TurnRules.sides(state).size(), 2, "turns alternate between the two groups")
	expect(PvpBattle.split(gen, {"a": ["p1"], "b": []}) != "", "both sides need someone")


func test_each_side_sees_only_what_its_side_knows() -> void:
	var gen := _split()
	var state: GameState = gen["state"]
	var f := ViewFilter.new()
	var a_unit := _unit_of(state, "p1")
	var b_unit := _unit_of(state, "p2")
	var from_a := f.view_for(state, "p1")
	var from_b := f.view_for(state, "p2")
	expect((from_a["units"][b_unit.id] as Dictionary).size() <= ViewFilter.PUBLIC_FIELDS.size(), "group a doesn't see group b's stats")
	expect((from_b["units"][a_unit.id] as Dictionary).size() <= ViewFilter.PUBLIC_FIELDS.size(), "group b doesn't see group a's stats")
	expect((from_a["units"][_unit_of(state, "p3").id] as Dictionary).size() > ViewFilter.PUBLIC_FIELDS.size(), "but sees its own group's")
	b_unit.statuses["Hidden"] = {}
	expect(bool(f.view_for(state, "p1")["units"][b_unit.id].get("hidden", false)), "a Hidden mutineer is only an approximate location")


func test_online_the_other_group_gets_its_own_filtered_view() -> void:
	var gen := _split()
	var state: GameState = gen["state"]
	var host := NetHost.new(state, RulesEngine.new())
	host.add_local_seat("p1")
	host.add_local_seat("p3")
	var hub := LoopbackTransport.Hub.new()
	host.open_room(LoopbackTransport.new(hub), "PVP001")
	var friend := NetClient.new(LoopbackTransport.new(hub))
	friend.join("PVP001", "Dee", "p2")
	Online._pump(host, friend)
	expect_eq(friend.seat, "p2")
	var a_unit := _unit_of(state, "p1")
	expect((friend.view["units"][a_unit.id] as Dictionary).size() <= ViewFilter.PUBLIC_FIELDS.size(), "the other group's player can't peek")


func test_the_winner_goes_back_to_the_story() -> void:
	var gen := _split()
	var state: GameState = gen["state"]
	var mission: Mission = gen["mission"]
	expect_eq(PvpBattle.winner(mission), "")
	for u: Unit in state.units_on_side(Mission.ENEMIES):
		u.destroyed = true
	mission.observe(state, [])
	expect_eq(PvpBattle.winner(mission), "a")
	var r := PvpBattle.result(mission)
	expect(r["id"] == "mutiny" and r["winner"] == "a" and r["b"] == ["p2"], str(r))


func test_a_story_split_hot_seat() -> void:
	var store := SaveStore.new("user://test_pvp_%d" % Time.get_ticks_usec())
	var db := MissionTest.db()
	GameFlow.story = null
	GameFlow.session = null
	var c := GameFlow.start_tutorial(store, db, "Ama Okafor", "Bluebird")
	var p2 := GameFlow.story.pilot_of_seat("p2")
	GameFlow.story_engine.submit(GameFlow.story, c, {"type": "set_seat", "seat": "gm", "params": {"seat": "p2", "pilot": p2, "ai": false}})
	var s := GameFlow.start_pvp_mission(c, db, store, {"a": ["p1"], "b": ["p2"]}, {}, "mutiny", ["p1", "p2"])
	expect(s != null)
	if s == null:
		return
	var st := s.host.state
	expect_eq(str(st.seats["p2"]["side"]), Mission.ENEMIES, "the other group is the other side")
	expect(st.units_on_side(Mission.ENEMIES).all(func(u: Unit) -> bool: return u.controller == "p2"), "no generated enemies")
	expect_eq(Array(s.hot.seats), ["p1", "p2"], "both people at this screen: hand-offs between them")
	GameFlow.session = null
	GameFlow.story = null
	preload("res://tests/unit/test_campaign_saves.gd")._remove(store.dir)


## Online: the host and two friends, split by a story choice. Each friend's client gets only
## its own side's picture, and nobody can command the other group.
func test_online_split_two_friends() -> void:
	var store := SaveStore.new("user://test_pvp_net_%d" % Time.get_ticks_usec())
	var db := MissionTest.db()
	GameFlow.story = null
	GameFlow.session = null
	var c := GameFlow.start_story_campaign(store, db, "Split", 3, 0, "Standard")
	var host := GameFlow.host_story_online(c, db, store, ["p1"])
	var hub := LoopbackTransport.Hub.new()
	host.open_room(LoopbackTransport.new(hub), "SPLIT1")
	var rin := NetClient.new(LoopbackTransport.new(hub))
	var kai := NetClient.new(LoopbackTransport.new(hub))
	rin.join("SPLIT1", "Rin", "p2")
	kai.join("SPLIT1", "Kai", "p3")
	for i in range(10):
		host.poll()
		rin.poll(0.1)
		kai.poll(0.1)
	expect(rin.seat == "p2" and kai.seat == "p3")
	GameFlow.story_client = null
	var hs := GameFlow.start_pvp_mission(c, db, store, {"a": ["p1", "p3"], "b": ["p2"]}, {}, "mutiny", ["p1"])
	expect(hs != null)
	if hs == null:
		return
	hs.start()
	for i in range(10):
		hs.poll(0.0)
		rin.poll(0.1)
		kai.poll(0.1)
	var st := hs.host.state
	var mine := func(seat: String) -> String:
		for u: Unit in st.units.values():
			if u.controller == seat:
				return u.id
		return ""
	var p1_unit: String = mine.call("p1")
	var p2_unit: String = mine.call("p2")
	expect((rin.view["units"][p1_unit] as Dictionary).size() <= ViewFilter.PUBLIC_FIELDS.size(), "Rin (the other group) can't see the host's stats")
	expect((kai.view["units"][p1_unit] as Dictionary).size() > ViewFilter.PUBLIC_FIELDS.size(), "Kai (the host's group) can")
	expect((kai.view["units"][p2_unit] as Dictionary).size() <= ViewFilter.PUBLIC_FIELDS.size(), "and Kai can't see Rin's")
	var r := hs.host.submit("p2", {"type": "start_turn", "actor": p1_unit})
	expect(not (r["result"] as RuleResult).ok, "Rin can't send the host's mech")
	GameFlow.leave_story_online()
	GameFlow.session = null
	GameFlow.story = null
	preload("res://tests/unit/test_campaign_saves.gd")._remove(store.dir)


## A vote split the squad 3 to 1 (the host and two friends against a third friend): the fight
## is only the squad's mechs on a small arena, each friend sees their own side's picture, the
## lone player yields from their client, the winning side's choice goes back to the story, and
## everyone keeps their damage.
func test_split_vote_three_against_one_online() -> void:
	var store := SaveStore.new("user://test_split_%d" % Time.get_ticks_usec())
	var db := MissionTest.db()
	GameFlow.story = null
	GameFlow.session = null
	var c := GameFlow.start_story_campaign(store, db, "Split", 4, 0, "Standard")
	GameFlow.finish_session_zero(c, store)
	var host := GameFlow.host_story_online(c, db, store, ["p1"])
	var hub := LoopbackTransport.Hub.new()
	host.open_room(LoopbackTransport.new(hub), "SPLIT3")
	var friends: Array = []
	for seat: String in ["p2", "p3", "p4"]:
		var f := NetClient.new(LoopbackTransport.new(hub))
		f.join("SPLIT3", seat, seat)
		friends.append(f)
	var pump := func(hs: BattleSession = null) -> void:
		for i in range(10):
			host.poll()
			if hs != null:
				hs.poll(0.0)
			for f: NetClient in friends:
				f.poll(0.1)
	pump.call()
	expect(friends.all(func(f: NetClient) -> bool: return f.seat != ""), "three friends seated")
	GameFlow.story.flags[Decisions.KEY] = {"id": "mutiny", "prompt": "Hand the colonists over", "votes": {},
		"options": [{"id": "accept", "label": "Hand them over", "effects": []}, {"id": "decline", "label": "Refuse", "effects": []}],
		"split": {"accept": ["p1", "p2", "p3"], "decline": ["p4"]}}
	GameFlow.story_client = null
	var hs := GameFlow.start_pvp_mission(c, db, store, {"accept": ["p1", "p2", "p3"], "decline": ["p4"]}, {}, "mutiny", ["p1"], {"fight": {}})
	expect(hs != null)
	if hs == null:
		return
	hs.start()
	pump.call(hs)
	var st := hs.host.state
	expect(st.units.values().all(func(u: Unit) -> bool: return GameFlow.story.seats.has(u.controller)), "only the squad's mechs: no enemies")
	expect(bool(st.objectives.get("nonlethal", false)), "non-lethal")
	expect(bool(st.objectives.get("arena", false)), "a sealed-off arena: not part of the town or region")
	expect(st.map.cells().size() <= 144, "tiny: 12x12 at most for four mechs (%d cells)" % st.map.cells().size())
	expect(hs.is_split_fight())
	var unit_of := func(seat: String) -> String:
		for u: Unit in st.units.values():
			if u.controller == seat:
				return u.id
		return ""
	var p4: NetClient = friends[2]
	var p2: NetClient = friends[0]
	expect((p4.view["units"][unit_of.call("p1")] as Dictionary).size() <= ViewFilter.PUBLIC_FIELDS.size(), "the lone dissenter can't see the others' stats")
	expect((p2.view["units"][unit_of.call("p1")] as Dictionary).size() > ViewFilter.PUBLIC_FIELDS.size(), "p2 sees its own side's")
	expect((p2.view["units"][unit_of.call("p4")] as Dictionary).size() <= ViewFilter.PUBLIC_FIELDS.size(), "but not p4's")
	# Some damage on the winners' side, kept afterwards.
	st.unit(unit_of.call("p2")).hp = 3
	# p4 yields from their own client.
	p4.transport.send(NetTransport.HOST_PEER, {"t": NetProtocol.LOBBY, "pvp_yield": true})
	pump.call(hs)
	var guard := 0
	while not hs.over and guard < 40:
		guard += 1
		pump.call(hs)
	expect(hs.over, "p4 yielded: the fight is over")
	expect_eq(PvpBattle.winner(hs.mission), "accept")
	var d := GameFlow.finish_mission(hs, c, store, db)
	expect(d.has("pvp"))
	expect_eq(str(GameFlow.story.flags.get("decided:mutiny", "")), "accept", "the winning side's choice stands")
	var pid := GameFlow.story.pilot_of_seat("p2")
	expect_eq(int(RepairBay.condition(GameFlow.story, pid).get("hp", -1)), 3, "damage is kept until a Full Repair")
	GameFlow.leave_story_online()
	GameFlow.session = null
	GameFlow.story = null
	preload("res://tests/unit/test_campaign_saves.gd")._remove(store.dir)


func test_knocked_out_mechs_are_out_of_the_fight() -> void:
	var gen := _split()
	var state: GameState = gen["state"]
	var mission: Mission = gen["mission"]
	for u: Unit in state.units_on_side(Mission.ENEMIES):
		u.counters["knocked_out"] = true  # the rules' knockout (non-lethal)
	mission.observe(state, [])
	expect_eq(PvpBattle.winner(mission), "a", "a side all knocked out has lost")
	expect(state.units_on_side(Mission.ENEMIES).all(func(u: Unit) -> bool: return not u.destroyed), "nobody destroyed")


## A three-way vote (left / middle / right): three sides, all hostile to each other; the last
## standing wins.
func test_three_way_split() -> void:
	var gen := MissionGenerator.generate(929, {"db": MissionTest.db(), "size": 24, "players": 3, "sitrep": "sitrep_standardcombat", "environments": []})
	expect_eq(PvpBattle.split(gen, {"left": ["p1"], "middle": ["p2"], "right": ["p3"]}, {}, "fork"), "")
	var state: GameState = gen["state"]
	var mission: Mission = gen["mission"]
	expect_eq(TurnRules.sides(state).size(), 3, "three sides take turns")
	expect_eq(_unit_of(state, "p3").side, "side_right")
	_unit_of(state, "p1").destroyed = true
	mission.observe(state, [])
	expect_eq(PvpBattle.winner(mission), "", "two sides still standing")
	_unit_of(state, "p3").counters["knocked_out"] = true
	mission.observe(state, [])
	expect_eq(PvpBattle.winner(mission), "middle")
