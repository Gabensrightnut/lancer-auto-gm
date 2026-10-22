extends TestCase
## The automation report: what the game does and what the table handles.

static var _db: ContentDB


func db() -> ContentDB:
	if _db == null:
		_db = ContentDB.new()
		_db.load_all()
	return _db


func _find(report: Array, id: String) -> Dictionary:
	for e: Dictionary in report:
		if e["id"] == id:
			return e
	return {}


func test_report_for_a_build() -> void:
	var loadout := {"mounts": [{"weapons": ["mw_assault_rifle"]}, {}, {"weapons": ["mw_pinaka_missiles"]}],
		"systems": ["ms_pattern_b_hex_charges", "ms_tesseract", "ms_ramjet"]}
	var report := RulesQueries.automation_for_build(db(), "mf_standard_pattern_i_everest", loadout, {"ll": 6, "talents": {"t_brutal": 1, "t_leader": 2}})
	expect_eq(_find(report, "Initiative")["status"], "automated")
	expect_eq(_find(report, "ms_pattern_b_hex_charges")["status"], "automated")
	var comp := _find(report, "ms_tesseract")
	expect_eq(comp["status"], "manual", "Tesseract: zero-g isn't modelled")
	expect(String(comp["guidance"]).contains("at the table"), "plain words about what to do")
	var ram := _find(report, "ms_ramjet")
	expect_eq(ram["status"], "partial")
	expect(String(ram["guidance"]).contains("straight lines"))
	expect_eq(_find(report, "mw_pinaka_missiles")["status"], "automated", "the delayed strike is automated too")
	expect_eq(_find(report, "t_brutal:1")["status"], "automated")
	expect_eq(_find(report, "t_leader:1")["status"], "automated")
	expect_eq(_find(report, "t_leader:2")["status"], "partial", "Issue Command as a reaction is the table's")
	expect(Automation.needs_table(report).size() >= 3)


func test_manual_ability_on_the_action_bar() -> void:
	var s := GameState.new(1, GridLayout.Shape.SQUARE)
	s.map = BattleMap.flat(GridLayout.Shape.SQUARE, 8, 8)
	var u := UnitFactory.build_mech(db(), "a", "mf_standard_pattern_i_everest", {"mounts": [], "systems": ["ms_tesseract"]})
	s.add_unit(u)
	var found := false
	for x: Dictionary in RulesQueries.available_actions(s, "a"):
		if x.get("name", "") == "Spread Focus":
			found = true
			expect_eq(x["automation"], "manual")
			expect(String(x["table_note"]).contains("GM"))
	expect(found)
