extends TestCase


func _db() -> ContentDB:
	var db := ContentDB.new()
	expect(db.load_all(), "all lancer-data files load")
	return db


func test_core_content_loads() -> void:
	var db := _db()
	expect_eq(db.count("frames"), 29)
	expect_eq(db.count("weapons"), 85)
	expect(db.count("systems") > 50)
	expect(db.count("talents") > 20)
	expect_eq(db.frame("mf_standard_pattern_i_everest")["name"], "Everest")
	expect_eq(db.weapon("mw_assault_rifle")["mount"], "Main")
	expect_eq(int(db.rules["base_structure"]), 4)


func test_rule_text_lookup() -> void:
	var db := _db()
	expect("comms" in db.rule_text("Jammed"), "Jammed blocks comms")
	expect("approximate location" in db.rule_text("Hidden"))
	expect("3 AP kinetic" in db.rule_text("Falling/Fall Damage"))
	expect(not "<" in db.rule_text("Hidden"), "HTML stripped")
