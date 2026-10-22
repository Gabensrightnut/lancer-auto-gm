extends TestCase
## Campaigns: book-default starting pilots, saves that survive updates and crashes, mission
## autosave between turns, and resuming once everyone has reconnected.

const MissionTest := preload("res://tests/unit/test_gm_mission.gd")

var store: SaveStore


func _store() -> SaveStore:
	store = SaveStore.new("user://test_saves_%d" % Time.get_ticks_usec())
	return store


func _cleanup() -> void:
	_remove(store.dir)


## JSON text with every number as JSON would read it back, for comparing saved data.
static func _norm(d: Dictionary) -> String:
	return JSON.stringify(JSON.parse_string(JSON.stringify(d)))


static func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		_remove(path.path_join(d))
	DirAccess.remove_absolute(path)


func test_new_pilots_start_at_ll0_with_gms_gear() -> void:
	var db := MissionTest.db()
	var c := Campaign.create("Test")
	expect_eq(c.options["start_ll"], 0, "book default")
	var p := c.new_pilot("Ama Okafor", "Bluebird")
	expect_eq(p["ll"], 0)
	expect(p["licenses"].is_empty())
	expect_eq(p["mechs"][0]["frame"], Campaign.STARTER_FRAME)
	expect_eq(c.validate_pilot(p, db), [], "the starter build is legal")
	# Non-GMS gear isn't allowed at LL0.
	p["mechs"][0]["frame"] = "mf_blackbeard"
	var problems := c.validate_pilot(p, db)
	expect(not problems.is_empty())
	expect(" ".join(problems).contains("license"), str(problems))
	var veteran := Campaign.create("Vets", {"start_ll": 3}).new_pilot("Old Hand", "Granite")
	expect_eq(veteran["ll"], 3, "campaign option: start higher")


func test_compcon_pilots_join_a_campaign() -> void:
	var db := MissionTest.db()
	var c := Campaign.create("Test")
	var r := Compcon.import_pilot(preload("res://tests/unit/test_content_compcon.gd").v2_pilot(), db)
	var problems := c.add_pilot(r["pilot"], db)
	expect(c.pilots.has(r["pilot"]["id"]))
	expect(problems.is_empty(), str(problems))
	var squad := c.squad()
	expect_eq(squad.size(), 1)
	expect_eq(squad[0]["mech"]["name"], "Old Faithful")
	var g := MissionGenerator.generate(4, {"squad": squad, "sitrep": "sitrep_standardcombat", "db": db})
	var u: Unit = g["state"].unit("p1")
	expect_eq(u.name, "Bluebird", "the campaign's own pilot flies in the mission")
	expect_eq(g["state"].seats["p1"]["pilot"], "Ama Okafor")


func test_campaign_save_round_trip() -> void:
	_store()
	var c := Campaign.create("Long Haul")
	c.new_pilot("A", "Alpha")
	c.new_pilot("B", "Bravo")
	c.story_flags["spared_the_baron"] = true
	c.rulings["uneven_ground"] = {"choice": "allow"}
	c.packs = [{"id": "abc", "name": "Test Pack", "version": "1.0"}]
	expect_eq(store.save_campaign(c), "")
	var r := store.load_campaign(c.id)
	expect_eq(r["error"], "")
	var back: Campaign = r["campaign"]
	expect_eq(_norm(back.to_dict()), _norm(c.to_dict()))
	expect_eq(typeof(back.pilots.values()[0]["ll"]), TYPE_INT, "numbers come back as ints")
	var listed := store.list()
	expect_eq(listed.size(), 1)
	expect_eq(listed[0]["name"], "Long Haul")
	_cleanup()


func test_old_saves_upgrade_and_newer_saves_are_refused() -> void:
	var old := {"id": "c_old", "name": "Before versions", "pilots": {}}
	var r := Campaign.from_dict(old)
	expect_eq(r["error"], "")
	expect_eq(r["campaign"].options["start_ll"], 0)
	var future := Campaign.from_dict({"save_version": Campaign.SAVE_VERSION + 1, "name": "From the future"})
	expect(future["campaign"] == null)
	expect(future["error"].contains("newer version"))


func test_damaged_save_falls_back_to_the_backup() -> void:
	_store()
	var c := Campaign.create("Fragile")
	store.save_campaign(c)
	c.story_flags["second_save"] = true
	store.save_campaign(c)
	var path := store.dir.path_join(c.id).path_join("campaign.json")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{ half a fi")
	f.close()
	var r := store.load_campaign(c.id)
	expect_eq(r["error"], "")
	expect_eq(r["campaign"].name, "Fragile", "loaded from campaign.json.bak")
	_cleanup()


func test_rulings_and_packs_carry_into_missions() -> void:
	var c := Campaign.create("Rules")
	c.rulings["uneven_ground"] = {"choice": "forbid"}
	c.packs = [{"id": "abc", "name": "P", "version": "1"}]
	var s := GameState.new(1)
	c.prepare_mission(s)
	expect_eq(s.rulings, c.rulings)
	expect_eq(s.packs, c.packs)
	s.rulings["new_one"] = {"choice": "allow"}
	var m := Mission.new()
	m.sitrep_name = "Control"
	m.outcome = "players"
	c.record_mission(s, m)
	expect(c.rulings.has("new_one"), "rulings made in a mission stay for the campaign")
	expect_eq(c.history[0]["outcome"], "players")


## Plays part of an AI mission with autosave on, then resumes it on a fresh host and checks
## the game picks up exactly where it was, dice included.
func test_mission_autosave_and_resume() -> void:
	_store()
	var c := Campaign.create("Saves")
	var gen := MissionGenerator.generate(8, {"players": 2, "sitrep": "sitrep_standardcombat", "size": 20, "db": MissionTest.db()})
	var host := NetHost.new(gen["state"], RulesEngine.new())
	host.set_fill_empty_with_ai(true)
	var settings := GmSettings.from_preset("Standard")
	var director := AiDirector.new(host, settings, gen["mission"])
	var auto := MissionAutosave.new(host, gen["mission"], store, c.id, settings)
	var saves: Array = []
	auto.saved.connect(func(r: int) -> void: saves.append(r))
	director.run(6)
	expect(saves.size() >= 3, "saved after every turn (%d saves)" % saves.size())
	expect(store.has_mission(c.id))
	var at_save := _norm(host.state.to_dict())
	var r := MissionAutosave.resume(store, c.id)
	expect_eq(r["error"], "")
	var host2: NetHost = r["host"]
	expect_eq(_norm(host2.state.to_dict()), at_save, "same battle, same dice state")
	expect(host2.is_ai_seat("p1"), "seat setup restored")
	# Both carry on the same way: the resumed game is the same game.
	var d2 := AiDirector.new(host2, r["settings"], r["mission"])
	director.run(4)
	d2.run(4)
	expect_eq(_norm(host2.state.to_dict()), _norm(host.state.to_dict()))
	_cleanup()


func test_resume_waits_for_everyone_to_reconnect() -> void:
	_store()
	var gen := MissionGenerator.generate(9, {"players": 2, "sitrep": "sitrep_standardcombat", "size": 20, "db": MissionTest.db()})
	var host := NetHost.new(gen["state"], RulesEngine.new())
	host.add_local_seat("p1")
	var hub := LoopbackTransport.Hub.new()
	host.open_room(LoopbackTransport.new(hub), "SAVE01")
	var friend := NetClient.new(LoopbackTransport.new(hub))
	friend.join("SAVE01", "Friend", "p2")
	for i in range(6):
		host.poll()
		friend.poll()
	expect_eq(friend.seat, "p2")
	var auto := MissionAutosave.new(host, gen["mission"], store, "camp", GmSettings.new())
	expect_eq(auto.save_now(), "")
	# The host computer restarts: the old room is gone; the friend's client is cut off.
	host.close()
	friend.auto_reconnect = false
	friend.poll()
	var r := MissionAutosave.resume(store, "camp")
	var h2: NetHost = r["host"]
	expect_eq(r["room"], "SAVE01", "same room code")
	h2.open_room(LoopbackTransport.new(hub), r["room"])
	h2.hold_until_back()
	var d2 := AiDirector.new(h2, r["settings"], r["mission"])
	expect_eq(h2.paused_for, ["p2"])
	var w := h2.waiting_on()
	expect_eq(w["state"], "reconnect")
	expect(w["text"].contains("Friend"), w["text"])
	expect_eq(d2.run(50), 0, "nothing happens while a player is missing")
	expect(not (h2.submit("p1", {"type": "start_turn", "actor": "p1"})["result"] as RuleResult).ok)
	# The friend rejoins with the same seat token.
	var back := NetClient.new(LoopbackTransport.new(hub))
	back.token = friend.token
	back.join("SAVE01", "Friend")
	for i in range(6):
		h2.poll()
		back.poll()
	expect_eq(back.seat, "p2", "got the same seat back")
	expect(h2.paused_for.is_empty(), "everyone's back: the mission goes on")
	expect(d2.run(5) > 0)
	_cleanup()
