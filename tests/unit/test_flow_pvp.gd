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
