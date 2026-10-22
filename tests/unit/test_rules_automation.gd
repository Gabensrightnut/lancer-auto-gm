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
		"systems": ["ms_pattern_b_hex_charges", "ms_comp_con_class_assistant_unit", "ms_ramjet"]}
	var report := RulesQueries.automation_for_build(db(), "mf_standard_pattern_i_everest", loadout, {"ll": 6, "talents": {"t_brutal": 1, "t_leader": 1}})
	expect_eq(_find(report, "Initiative")["status"], "automated")
	expect_eq(_find(report, "ms_pattern_b_hex_charges")["status"], "automated")
	var comp := _find(report, "ms_comp_con_class_assistant_unit")
	expect_eq(comp["status"], "manual", "COMP/CON: handing control over is the table's")
	expect(String(comp["guidance"]).contains("at the table"), "plain words about what to do")
	var ram := _find(report, "ms_ramjet")
	expect_eq(ram["status"], "partial")
	expect(String(ram["guidance"]).contains("straight lines"))
	expect_eq(_find(report, "mw_pinaka_missiles")["status"], "partial")
	expect_eq(_find(report, "t_brutal:1")["status"], "automated")
	expect_eq(_find(report, "t_leader:1")["status"], "manual")
	expect(Automation.needs_table(report).size() >= 3)


func test_manual_ability_on_the_action_bar() -> void:
	var s := GameState.new(1, GridLayout.Shape.SQUARE)
	s.map = BattleMap.flat(GridLayout.Shape.SQUARE, 8, 8)
	var u := UnitFactory.build_mech(db(), "a", "mf_standard_pattern_i_everest", {"mounts": [], "systems": ["ms_comp_con_class_assistant_unit"]})
	s.add_unit(u)
	var found := false
	for x: Dictionary in RulesQueries.available_actions(s, "a"):
		if x.get("name", "") == "Engage COMP/CON":
			found = true
			expect_eq(x["automation"], "manual")
			expect(String(x["table_note"]).contains("GM"))
	expect(found)
