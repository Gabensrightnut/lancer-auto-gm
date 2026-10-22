extends TestCase
## The tutorial from the main menu, headless: a new story campaign at the training base, the
## briefing at the hub, the drill as a real battle with lessons and tips fed from the battle's
## events (as the battle screen does), then back to the hub for the debrief. Also: teaching
## hints off, and the twist reveal in a story mission.

const Flow := preload("res://tests/unit/test_flow_campaign.gd")
const MissionTest := preload("res://tests/unit/test_gm_mission.gd")

var store: SaveStore


func _store() -> SaveStore:
	store = SaveStore.new("user://test_tutorial_%d" % Time.get_ticks_usec())
	return store


## What the hub does between the briefing and boots on the ground (the player picks the drill,
## reads the briefing, and deploys).
static func _brief_and_deploy(c: Campaign) -> Array:
	var story := GameFlow.story
	var e := GameFlow.story_engine
	var out: Array = []
	out.append_array(e.submit(story, c, {"type": "choose_hook", "seat": "gm", "params": {"hook": story.hooks[0]["id"]}})["events"])
	var guard := 0
	while Dialogue.is_open(story) and guard < 50:
		guard += 1
		var o := Dialogue.offered(story)
		var a := {"type": "dialogue_next", "seat": "gm", "params": {}} if o.is_empty() else {"type": "dialogue_choose", "seat": "gm", "params": {"choice": o[0]["id"]}}
		out.append_array(e.submit(story, c, a)["events"])
	out.append_array(e.submit(story, c, {"type": "confirm_reserves", "seat": "gm", "params": {}})["events"])
	return out


func test_tutorial_from_menu_to_debrief() -> void:
	_store()
	var db := MissionTest.db()
	GameFlow.story = null
	var c := GameFlow.start_tutorial(store, db, "Ama Okafor", "Bluebird", true)
	expect(GameFlow.is_story(c))
	expect_eq(c.pilots.size(), 2, "your pilot and an AI squadmate")
	expect(Tutorial.active(GameFlow.story))
	expect_eq(GameFlow.story.phase, "briefing")
	expect(GameFlow.story_events.any(func(e: Dictionary) -> bool: return e.get("type", "") == "tutorial_prompt"), "the first lesson is waiting for the hub")
	var saved: Campaign = store.load_campaign(c.id)["campaign"]
	expect(GameFlow.is_story(saved) and bool(saved.options["teaching_hints"]), "saved as a story campaign with hints on")
	expect_eq(StoryState.of(saved).phase, "briefing", "the story is saved with it")

	var hub_events := _brief_and_deploy(c)
	expect(hub_events.any(func(e: Dictionary) -> bool: return e.get("type", "") == "boots_on_the_ground"), "the hub asks for the mission")
	var s := GameFlow.start_story_mission(c, db, store)
	expect(s != null, "the drill starts")
	if s == null:
		return
	expect(store.has_mission(c.id))
	expect(s.mission.flavor.get("hook", {}).get("tutorial", false), "the battle is the tutorial's drill")
	expect(s.host.is_ai_seat("p2") and not s.host.is_ai_seat("p1"), "you fly p1, the AI flies your squadmate")
	var mate_orders: Dictionary = s.director.orders.get("p2", {})
	expect(str(mate_orders.get("stance", "")) != "", "the AI squadmate fights to its character (Squadmate.orders): %s" % str(s.director.orders))
	expect(not s.director.orders.has("p1"), "no orders for your own mech")
	for u: Unit in s.host.state.units_on_side(Mission.ENEMIES):
		expect_eq(u.content_id, "training_drone", "training targets only")

	# The battle screen's part: every batch of events goes to Tutorial.observe_battle.
	var prompts: Array = []
	var story := GameFlow.story
	s.events_seen.connect(func(_seat: String, events: Array) -> void:
		var mine: Array = []
		for u: Unit in s.host.state.units.values():
			if u.controller == "p1":
				mine.append(u.id)
		prompts.append_array(Tutorial.observe_battle(story, c, events, mine)))
	s.start()
	var me := Flow.ScriptedPlayer.new(s)
	Flow.play_out([s], [me])
	expect(s.over, "the drill ends")
	var ids := prompts.map(func(p: Dictionary) -> String: return str(p.get("id", "")))
	expect(ids.has("turns") and ids.has("move"), "battle lessons came up in order: %s" % str(ids))
	expect(prompts.any(func(p: Dictionary) -> bool: return p.get("type", "") == "tutorial_prompt" and p.get("kind", "") == "tip"), "first-time tips with hints on")
	expect(int(story.tutorial["step"]) > 3, "lessons were completed by playing: step %d" % int(story.tutorial["step"]))

	var d := GameFlow.finish_mission(s, c, store, db)
	expect(d.get("story", false), "the screen goes back to the hub, not the plain debrief")
	expect_eq(GameFlow.story.phase, "debrief")
	expect(GameFlow.story_events.any(func(e: Dictionary) -> bool: return e.get("type", "") == "debrief"), "the hub shows the debrief")
	expect(not store.has_mission(c.id), "mission autosave cleared")
	var back: Campaign = store.load_campaign(c.id)["campaign"]
	expect_eq(back.history.size(), 1)
	expect_eq(int(back.pilots[back.pilots.keys()[0]]["ll"]), 0, "leveling up happens at the hub (story level_up), not here")
	expect_eq(StoryState.of(back).phase, "debrief", "the story's progress is saved")
	preload("res://tests/unit/test_campaign_saves.gd")._remove(store.dir)


func test_teaching_hints_off_means_no_tips() -> void:
	var c := Campaign.create("Hints")
	var story := StoryState.new(1)
	var events := [{"type": "combat_started"}, {"type": "attack_rolled", "attacker": "p1", "result": "miss"}, {"type": "structure_lost", "unit": "p1"}]
	c.options["teaching_hints"] = true
	expect(not Tutorial.observe_battle(story, c, events, ["p1"]).is_empty(), "hints on: tips show")
	var quiet := StoryState.new(2)
	c.options["teaching_hints"] = false
	expect(Tutorial.observe_battle(quiet, c, events, ["p1"]).is_empty(), "hints off and no tutorial running: nothing")


func test_story_mission_twist_reaches_the_screen() -> void:
	_store()
	var db := MissionTest.db()
	GameFlow.story = null
	var c := GameFlow.start_tutorial(store, db)
	_brief_and_deploy(c)
	var s := GameFlow.start_story_mission(c, db, store)
	# A real job would carry a twist from the story's hook; give the drill one.
	s.mission.flavor["twist"] = {"id": "orders_change", "reveal": "New orders: take the target intact.", "question": "Will you follow them?"}
	var seen: Array = []
	s.events_seen.connect(func(_seat: String, events: Array) -> void:
		for e: Dictionary in events:
			if e.get("type", "") == "twist_revealed":
				seen.append(e))
	s.start()
	Flow.play_out([s], [Flow.ScriptedPlayer.new(s)])
	expect_eq(seen.size(), 1, "the player's screen got the twist once")
	if not seen.is_empty():
		expect_eq(seen[0]["twist"]["reveal"], "New orders: take the target intact.")
	preload("res://tests/unit/test_campaign_saves.gd")._remove(store.dir)


func test_story_campaign_retire_and_sequel() -> void:
	_store()
	var db := MissionTest.db()
	GameFlow.story = null
	var c := GameFlow.start_story_campaign(store, db, "Long Road", 3, 0, "Standard", 2)
	expect(GameFlow.is_story(c))
	expect_eq(int(c.options["campaign_arcs"]), 2, "campaign length saved in the campaign's options")
	var story := GameFlow.story
	expect_eq(story.seats.size(), 3)
	expect(not story.is_ai("p1") and story.is_ai("p2") and story.is_ai("p3"), "you fly p1; AI squadmates in the rest")
	expect(str(story.seats["p2"].get("persona", "")) != "", "AI squadmates get a persona")
	expect(not GameFlow.story_events.is_empty(), "the hub has events to show when it opens")
	expect(GameFlow.session_zero_pending(c), "session zero comes first")
	expect(story.hooks.is_empty(), "no jobs until session zero is done (its choices shape them)")
	var sz := GameFlow.story_engine.submit(story, c, {"type": "session_zero", "seat": "gm", "params": {"tone": "heroic", "focus": "balanced", "content_off": []}})
	expect(sz["ok"], str(sz.get("reason", "")))
	var board := GameFlow.finish_session_zero(c, store)
	expect(not GameFlow.session_zero_pending(c))
	expect(board.any(func(e: Dictionary) -> bool: return e.get("type", "") == "hook_added"), "the first jobs go on the board")
	expect(not story.hooks.is_empty(), "jobs on the board at the first hub")
	expect(not GameFlow.session_zero_pending(store.load_campaign(c.id)["campaign"]), "saved as done")
	expect(not GameFlow.session_zero_pending(GameFlow.start_tutorial(store, db)), "the tutorial has no session zero")
	GameFlow.open_story(c, db)
	story = GameFlow.story
	expect_eq(store.load_campaign(c.id)["error"], "", "saved")
	# Retire the squad: allowed between missions, then the epilogue.
	expect_eq(GameFlow.retire_refusal(c), {}, "retiring is allowed at a briefing")
	var r := GameFlow.story_engine.submit(story, c, {"type": "end_campaign", "seat": "gm", "params": {}})
	expect(r["ok"], str(r.get("reason", "")))
	expect(r["events"].any(func(e: Dictionary) -> bool: return e.get("type", "") == "campaign_ended"), "the epilogue's data")
	expect_eq(story.phase, "ending")
	expect(not GameFlow.retire_refusal(c).is_empty(), "can't retire twice")
	# A new campaign with the same pilots.
	var old_pilots := c.pilots.keys()
	old_pilots.sort()
	var c2 := GameFlow.start_sequel(c, store, db)
	expect(c2.id != c.id)
	var new_pilots := c2.pilots.keys()
	new_pilots.sort()
	expect_eq(new_pilots, old_pilots, "the same pilots")
	expect(GameFlow.is_story(c2) and int(c2.options["campaign_arcs"]) == 2, "same options")
	expect(GameFlow.story != story and GameFlow.story.phase != "ending", "a fresh story")
	expect_eq(StoryState.of(store.load_campaign(c.id)["campaign"]).phase, "ending", "the old campaign is saved with its ending")
	expect_eq(store.load_campaign(c2.id)["error"], "", "the sequel is saved")
	preload("res://tests/unit/test_campaign_saves.gd")._remove(store.dir)


func test_parley_in_a_story_battle() -> void:
	_store()
	var db := MissionTest.db()
	GameFlow.story = null
	var c := GameFlow.start_story_campaign(store, db, "Parley", 2, 0, "Standard")
	var story := GameFlow.story
	GameFlow.story_engine.submit(story, c, {"type": "session_zero", "seat": "gm", "params": {}})
	GameFlow.finish_session_zero(c, store)
	_brief_and_deploy(c)
	var s := GameFlow.start_story_mission(c, db, store)
	expect(s != null)
	if s == null:
		return
	var b: Dictionary = story.flags.get("_battle", {})
	expect(not b.is_empty(), "the enemy has a commander")
	var early := GameFlow.story_engine.submit(story, c, {"type": "parley", "seat": "p1", "params": {}})
	expect(not early["ok"] and str(early["reason"]).contains("Core p.60"), "no terms while the fight's in question: %s" % early.get("reason", ""))
	var downs: Array = []
	for id: String in b["enemy_ids"]:
		if id != b["unit"]:
			downs.append({"type": "unit_destroyed", "unit": id})
	var told := GameFlow.story_battle_events(c, downs)
	expect(not told.is_empty() or story.flags["_battle"]["offered"], "half their force down: the commander reacts (%s)" % str(told))
	s.start()
	expect(s.end_by_parley({"outcome": "players", "reason": "Their commander yields."}), "the GM ends the fight on the agreed terms")
	expect(s.over and s.outcome == Mission.PLAYERS)
	expect_eq(s.host.state.phase, GameState.PHASE_ENDED)
	expect(not s.end_by_parley({"outcome": "enemies"}), "only once")
	expect(GameFlow.finish_mission(s, c, store, db).get("story", false))
	preload("res://tests/unit/test_campaign_saves.gd")._remove(store.dir)
