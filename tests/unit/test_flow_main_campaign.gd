extends TestCase
## Starting the main campaign from the new campaign form: a story campaign whose session zero
## ends in CampaignScript.begin (the authored first chapter), not a generated hub.

const MissionTest := preload("res://tests/unit/test_gm_mission.gd")


func test_session_zero_then_the_long_arrival() -> void:
	var store := SaveStore.new("user://test_main_campaign_%d" % Time.get_ticks_usec())
	var db := MissionTest.db()
	GameFlow.story = null
	var c := GameFlow.start_story_campaign(store, db, "Arrival", 2, 0, "Standard")
	c.options["main_campaign"] = GameFlow.MAIN_CAMPAIGN
	var ev := GameFlow.finish_session_zero(c, store)
	expect(CampaignScript.active(c), "the authored campaign runs (story_mode campaign)")
	expect(not c.options.has("main_campaign"), "started once")
	expect(ev.any(func(e: Dictionary) -> bool: return str(e.get("type", "")) == "campaign_premise"), "its premise is told")
	expect(GameFlow.story.hooks.any(func(h: Dictionary) -> bool: return h.has("chapter")), "the first chapter's job is on the board")
	var sandbox := GameFlow.start_story_campaign(store, db, "Sandbox", 2, 0, "Standard")
	GameFlow.finish_session_zero(sandbox, store)
	expect(not CampaignScript.active(sandbox), "the generated story stays its own option")
	GameFlow.story = null  # leave no open story for the next test
	GameFlow.story_events = []
	preload("res://tests/unit/test_campaign_saves.gd")._remove(store.dir)
