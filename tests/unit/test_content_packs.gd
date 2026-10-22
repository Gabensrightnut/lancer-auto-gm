extends TestCase
## Lancer Content Packs (.lcp): reading, adding to ContentDB, the packs folder, join checks.
## Packs here are tiny hand-made test packs written to a scratch folder.

var dir := ""


func _dir() -> String:
	dir = "user://test_packs_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


func _cleanup() -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


static func make_pack(path: String, manifest: Variant, files: Dictionary) -> void:
	var zip := ZIPPacker.new()
	zip.open(path)
	if manifest != null:
		zip.start_file(ContentPack.MANIFEST)
		zip.write_file(JSON.stringify(manifest).to_utf8_buffer())
		zip.close_file()
	for name: String in files:
		zip.start_file(name)
		zip.write_file(JSON.stringify(files[name]).to_utf8_buffer())
		zip.close_file()
	zip.close()


## A test pack: a frame with its gear (license collection), a library weapon without an id,
## and NPC data in all three layouts.
static func sample_files() -> Dictionary:
	return {
		"license_testframe.json": [
			{"id": "mf_test_hound", "name": "Hound", "mechtype": ["Striker"], "source": "TESTCO", "license_level": 2, "license_id": "mf_test_hound",
			 "mounts": ["Main", "Heavy"], "stats": {"size": 1, "hp": 9, "evasion": 9, "edef": 8, "heatcap": 6, "speed": 5,
			 "sensor_range": 10, "save": 10, "armor": 1, "repcap": 4, "sp": 6, "tech_attack": 0}},
			{"id": "mw_test_fang", "name": "Fang Cannon", "mount": "Heavy", "type": "Cannon", "license_level": 2,
			 "damage": [{"type": "Kinetic", "val": "2d6"}], "range": [{"type": "Range", "val": 8}], "tags": []},
		],
		"weapons.json": [{"name": "Test Blade-Whip", "mount": "Main", "type": "Melee", "license_level": 0, "source": "GMS",
			"damage": [{"type": "Energy", "val": "1d6"}], "range": [{"type": "Threat", "val": 2}]}],
		"npc_classes.json": [{"id": "npcc_test_grunt", "name": "Test Grunt", "role": "striker"}],
		"npc_templates.json": [{"id": "npct_test_elite", "name": "Test Elite"}],
		"npc_features.json": [{"id": "npcf_test_jab", "name": "Jab", "origin": "npcc_test_grunt"}],
		"npcc_scout.json": [{"id": "npcc_test_scout", "name": "Scout", "role": "controller"},
			{"id": "npcf_test_ping", "name": "Ping"}],
	}


const MANIFEST := {"name": "Test Pack", "author": "Lancer TTRPG tests", "version": "1.2.0", "item_prefix": "tst"}


func test_reads_a_pack_like_compcon_does() -> void:
	_dir()
	make_pack(dir.path_join("test.lcp"), MANIFEST, sample_files())
	var p := ContentPack.read(dir.path_join("test.lcp"))
	expect_eq(p.error, "")
	expect_eq(p.name, "Test Pack")
	expect_eq(p.version, "1.2.0")
	expect_eq(p.id, ContentPack.pack_id("Lancer TTRPG tests", "Test Pack"))
	var db := ContentDB.new()
	db.load_all()
	var frames_before := db.count("frames")
	expect(db.add_pack(p))
	expect_eq(db.count("frames"), frames_before + 1)
	expect_eq(db.frame("mf_test_hound").get("name"), "Hound")
	var fang := db.weapon("mw_test_fang")
	expect_eq(fang.get("license_id"), "mf_test_hound", "license collection gear belongs to its frame")
	expect_eq(fang.get("license"), "Hound")
	expect(not db.weapon("tst__mw_test_blade_whip").is_empty(), "entries without an id get one from the prefix and name")
	expect_eq(db.count("npc_classes"), 2, "npc_classes.json plus an npcc_ collection")
	expect_eq(db.count("npc_templates"), 1)
	expect_eq(db.get_entry("npc_features", "npcf_test_ping").get("origin"), "npcc_test_scout")
	expect_eq(db.packs.size(), 1)
	expect_eq(db.packs[0]["version"], "1.2.0")
	_cleanup()


func test_pack_gear_follows_license_rules() -> void:
	_dir()
	make_pack(dir.path_join("test.lcp"), MANIFEST, sample_files())
	var db := ContentDB.new()
	db.load_all()
	db.add_pack(ContentPack.read(dir.path_join("test.lcp")))
	var loadout := {"mounts": [{"weapons": ["mw_assault_rifle"]}, {"weapons": ["mw_test_fang"]}], "systems": []}
	expect(not UnitFactory.check_loadout(db, "mf_test_hound", loadout, {"ll": 0}).ok, "LL0 can't take the Hound")
	var legal := UnitFactory.check_loadout(db, "mf_test_hound", loadout, {"ll": 2, "licenses": {"mf_test_hound": 2}})
	expect(legal.ok, legal.reason)
	var u := UnitFactory.build_mech(db, "h", "mf_test_hound", loadout, {"ll": 2})
	expect_eq(u.max_hp, 9 + 1)
	_cleanup()


func test_broken_packs_are_reported() -> void:
	_dir()
	make_pack(dir.path_join("none.lcp"), null, sample_files())
	expect(ContentPack.read(dir.path_join("none.lcp")).error.contains("manifest"))
	make_pack(dir.path_join("half.lcp"), {"name": "X", "author": "Y"}, {})
	expect(ContentPack.read(dir.path_join("half.lcp")).error.contains("version"))
	var f := FileAccess.open(dir.path_join("junk.lcp"), FileAccess.WRITE)
	f.store_string("not a zip")
	f.close()
	expect(ContentPack.read(dir.path_join("junk.lcp")).error != "")
	var db := ContentDB.new()
	db.load_all()
	expect(not db.add_pack(ContentPack.read(dir.path_join("junk.lcp"))))
	_cleanup()


func test_pack_ids_match_compcon() -> void:
	# COMP/CON names packs by base64(SHA-1("author/name")).
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update("Massif/Long Rim".to_utf8_buffer())
	expect_eq(ContentPack.pack_id("Massif", "Long Rim"), Marshalls.raw_to_base64(ctx.finish()))
	expect_eq(ContentPack.pack_id("a", "b").length(), 28)


func test_library_enables_packs_per_campaign() -> void:
	_dir()
	make_pack(dir.path_join("test.lcp"), MANIFEST, sample_files())
	make_pack(dir.path_join("other.lcp"), {"name": "Other", "author": "Z", "version": "0.1"}, {})
	var lib := PackLibrary.new(dir)
	expect_eq(lib.installed().size(), 2)
	var test_pack := lib.find(ContentPack.pack_id("Lancer TTRPG tests", "Test Pack"))
	expect(test_pack != null)
	var on := lib.load_db([test_pack.summary()])
	expect(on["missing"].is_empty())
	expect(not on["db"].frame("mf_test_hound").is_empty())
	var off := lib.load_db([])
	expect(off["db"].frame("mf_test_hound").is_empty(), "packs are only on when the campaign turns them on")
	var newer := test_pack.summary()
	newer["version"] = "2.0.0"
	expect_eq(lib.load_db([newer])["missing"].size(), 1, "a different version counts as missing")
	expect_eq(PackLibrary.missing([test_pack.summary()], [test_pack.summary()]), [])
	expect_eq(PackLibrary.missing([test_pack.summary()], []).size(), 1)
	expect(PackLibrary.describe([test_pack.summary()]).contains("Test Pack 1.2.0"))
	_cleanup()


func test_game_state_records_packs() -> void:
	var s := GameState.new(1)
	s.packs = [{"id": "abc", "name": "Test Pack", "version": "1.2.0"}]
	expect_eq(GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict()))).packs, s.packs)


func test_join_requires_the_same_packs() -> void:
	var s := GameState.new(1)
	s.seats = {"p1": {"name": "P1", "side": "players"}, "p2": {"name": "P2", "side": "players"}}
	var pack := {"id": "abc", "name": "Test Pack", "version": "1.2.0"}
	s.packs = [pack]
	var host := NetHost.new(s, RulesEngine.new())
	var hub := LoopbackTransport.Hub.new()
	host.open_room(LoopbackTransport.new(hub), "PACKS1")
	var without := NetClient.new(LoopbackTransport.new(hub))
	var refusals: Array = []
	without.refused.connect(func(code: String, why: String) -> void: refusals.append([code, why]))
	without.join("PACKS1", "No packs")
	var old := NetClient.new(LoopbackTransport.new(hub))
	old.packs = [{"id": "abc", "name": "Test Pack", "version": "1.0.0"}]
	old.refused.connect(func(code: String, why: String) -> void: refusals.append([code, why]))
	old.join("PACKS1", "Old version")
	var good := NetClient.new(LoopbackTransport.new(hub))
	good.packs = [pack]
	good.join("PACKS1", "Matching")
	for i in range(8):
		host.poll()
		for c in [without, old, good]:
			c.poll()
	expect_eq(refusals.size(), 2)
	for r in refusals:
		expect_eq(r[0], NetProtocol.REFUSE_PACKS)
		expect(r[1].contains("Test Pack 1.2.0"), r[1])
	expect(good.seat != "", "the player with the same packs gets in")
	expect_eq(good.view.get("packs"), [pack], "clients see which packs the game uses")
