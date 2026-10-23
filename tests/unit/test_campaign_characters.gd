extends TestCase
## Saved characters (CharacterRoster) and the sanity check that rebuilds them for a campaign
## (CharacterSanity): identity and choices only, never numbers; nothing illegal gets in.

const MissionTest := preload("res://tests/unit/test_gm_mission.gd")


func _roster() -> CharacterRoster:
	return CharacterRoster.new("user://test_chars_%d/" % Time.get_ticks_usec())


func test_the_roster() -> void:
	var r := _roster()
	var c := Campaign.create("Roster")
	var p := c.new_pilot("Ama Okafor", "Bluebird")
	p["persona"] = "steady"
	p["notes"] = "Grew up on a hauler."
	var id := r.save(CharacterRoster.from_pilot(p))
	expect(id != "")
	var other := r.save(CharacterRoster.from_pilot(c.new_pilot("Rin Sato", "Kettle")))
	expect_eq(r.list().size(), 2)
	expect_eq(r.list("blue").size(), 1, "search by callsign")
	r.set_favourite(other, true)
	expect_eq(str(r.list()[0]["identity"]["name"]), "Rin Sato", "favourites first")
	r.rename(id, "Ama O.")
	var dup := r.duplicate_one(id)
	expect(dup != "" and str(r.load_one(dup)["identity"]["name"]).ends_with("(copy)"))
	r.add_history(id, "Held the Saltpan lander for six rounds.")
	expect_eq((r.load_one(id)["history"] as Array).size(), 1)
	var path := r.dir.path_join("share.lancerpilot")
	expect(r.export_to(id, path))
	var imported := r.import_from(path)
	expect(imported != "" and imported != id, "a friend's file comes in as a new character")
	r.delete(dup)
	expect(r.load_one(dup).is_empty())
	var big := FileAccess.open(r.dir.path_join("huge.json"), FileAccess.WRITE)
	big.store_string("{\"schema\": 1, \"identity\": {\"name\": \"x\"}, \"pad\": \"%s\"}" % "x".repeat(CharacterRoster.MAX_BYTES))
	big = null
	expect_eq(r.import_from(r.dir.path_join("huge.json")), "", "oversized files are refused")


## The user's test: a tampered save (inflated HP, a fake talent, an LL5 frame in an LL0 game,
## extra manna) loads as a legal LL0 pilot, with the removals listed.
func test_a_tampered_save_is_rebuilt_legal() -> void:
	var db := MissionTest.db()
	var c := Campaign.create("Fair play", {"start_ll": 0})
	var tampered := {"schema": 1, "identity": {"name": "Cheat", "callsign": "Ace", "persona": "bold"},
		"build": {"talents": {"t_fake_talent": 3, "t_ace": 3}, "licenses": {"mf_barbarossa": 3},
			"mech": {"frame": "mf_barbarossa", "loadout": {"mounts": [{"weapons": ["mw_assault_rifle"]}]}},
			"hase": {"hull": 6}},
		"hp": 999, "manna": 100000, "ll": 5, "reserves": ["reserve_knowledge"], "bounties": {"x": 1}}
	var r := CharacterSanity.rebuild(db, c, tampered)
	var pilot: Dictionary = r["pilot"]
	expect_eq(int(pilot["ll"]), 0, "the campaign's LL, not the file's")
	expect(not pilot.has("manna") and not pilot.has("hp") and (pilot.get("reserves", []) as Array).is_empty(), "no money, HP or reserves from the file")
	expect(not (pilot["talents"] as Dictionary).has("t_fake_talent"), "no fake talent")
	expect(int((pilot["talents"] as Dictionary).get("t_ace", 0)) < 3, "no rank 3 at LL0")
	var mech: Dictionary = {}
	for m: Dictionary in pilot["mechs"]:
		mech = m
	expect_eq(str(mech["frame"]), Campaign.STARTER_FRAME, "an LL0 pilot flies the Everest")
	var b := BuilderModel.new(db, pilot)
	expect(b.is_legal(), "a legal LL0 pilot: %s" % str(b.problems()))
	expect(not bool(r["passed"]))
	var text := CharacterSanity.describe(r["report"])
	expect(text.contains("Talent") and text.contains("Frame") and text.contains("Core p."), text)
	expect_eq(str(pilot["persona"]), "bold", "their personality stays")

	var clean := CharacterSanity.rebuild(db, c, CharacterRoster.from_pilot(c.new_pilot("Honest", "Abe")))
	expect(bool(clean["passed"]), "a clean character passes: %s" % str(clean["report"]))
	expect_eq(CharacterSanity.build_hash(clean["pilot"]).length(), 16)
