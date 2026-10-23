extends TestCase
## The gitignored local official NPC pack (docs/NPC_PACK.md): loaded when present. Skipped on
## machines that don't have it.


func test_local_pack_loads_when_present() -> void:
	if not FileAccess.file_exists(ContentDB.LOCAL_NPC_PACK):
		return  # no local pack here: nothing to check
	ContentDB.use_local_pack = true
	var db := ContentDB.new()
	db.load_all()
	ContentDB.use_local_pack = false
	expect(db.count("npc_classes") > 0, "the local pack's NPC classes are loaded")
	var src := NPCBuilder.source(db)
	expect((src["official"] as Dictionary).has("npcc_squad"), "the official Squad replaces our placeholder")
	var sq := Soldiers.build(db, "sq", "rifle_squad", "enemies", 1)
	expect(sq != null and not sq.loadout["placeholder"], "built from the official numbers")
