extends TestCase
## The squad-creation lobby (SquadLobby): four slots, Join, a character for each (always
## sanity-checked), Ready, bots, kick, the shared history, and starting the campaign with them.

const MissionTest := preload("res://tests/unit/test_gm_mission.gd")


func test_slots_ready_bots_and_start() -> void:
	var db := MissionTest.db()
	var c := Campaign.create("Squad", {"start_ll": 0})
	var l := SquadLobby.new(db, c)
	expect(l.can_start() != "", "nobody has joined")
	expect_eq(l.claim("p1", "Ama"), "")
	expect(l.claim("p1", "Rin") != "", "a claimed slot is taken")
	expect(l.set_ready("p1", true) != "", "no character yet")
	var mine := CharacterRoster.from_pilot(c.new_pilot("Ama Okafor", "Bluebird"))
	expect_eq(l.set_character("p1", mine), "")
	expect(bool(l.slots["p1"]["passed"]), "a clean character passes the sanity check")
	expect(l.can_start() != "", "not ready yet")
	l.set_ready("p1", true)
	expect_eq(l.can_start(), "")

	# A friend brings a tampered character: it comes in legal, with the report.
	l.on_message("p2", "Rin", {"squad": {"claim": true}})
	l.on_message("p2", "Rin", {"squad": {"character": {"schema": 1, "identity": {"name": "Rin", "callsign": "Kettle"},
		"build": {"talents": {"t_fake": 3}, "mech": {"frame": "mf_barbarossa"}}, "manna": 9999}}})
	expect(not bool(l.slots["p2"]["passed"]) and not (l.slots["p2"]["report"] as Array).is_empty(), "the sanity check lists what was removed")
	expect_eq(l.can_start(), "Waiting for Rin to be ready.")
	l.on_message("p2", "Rin", {"squad": {"ready": true}})
	expect_eq(l.can_start(), "")

	expect_eq(l.add_bot("p3", "p1"), "")
	expect(not (l.slots["p3"]["pilot"] as Dictionary).is_empty() and bool(l.slots["p3"]["ready"]), "a bot is made, checked and ready")
	expect((l.history as Array).size() >= 1, "the squad's shared history from their backgrounds")
	l.release("p2")
	expect_eq(str(l.slots["p2"]["state"]), "empty", "kicked: the slot is free again")
	expect_eq(l.summary()["slots"]["p1"]["pilot"]["callsign"], "Bluebird", "everyone sees the finished pilots")

	var store := SaveStore.new("user://test_squad_%d" % Time.get_ticks_usec())
	GameFlow.story = null
	var camp := GameFlow.start_story_campaign(store, db, "Squad", 0, 0, "Standard", GameFlow.DEFAULT_ARCS, "", "standard", l.squad())
	expect_eq(camp.pilots.size(), 2, "the lobby's pilots, no random extras")
	var by_seat := {}
	for seat: String in GameFlow.story.seats:
		by_seat[seat] = camp.pilots[GameFlow.story.pilot_of_seat(seat)]["callsign"]
	expect_eq(by_seat.get("p1", ""), "Bluebird")
	expect(GameFlow.story.is_ai("p3") and not GameFlow.story.is_ai("p1"), "the bot is an AI squadmate")
	GameFlow.story = null
	preload("res://tests/unit/test_campaign_saves.gd")._remove(store.dir)
