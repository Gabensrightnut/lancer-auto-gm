extends TestCase
## Core-book coverage must not drop (Coverage, docs/COVERAGE.md). Raise the floors in
## data/game/coverage_floor.json when more gets automated.


func test_coverage_does_not_drop() -> void:
	var db := ContentDB.new()
	db.load_all()
	var report := Coverage.audit(db)
	var floor: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/game/coverage_floor.json"))
	expect(floor is Dictionary, "the floor file")
	for k: String in (floor as Dictionary):
		expect(report.has(k), "kind " + k)
		if report.has(k):
			var handled := int(report[k]["automated"]) + int(report[k]["partial"])
			expect(handled >= int(floor[k]), "%s: %d handled, the floor is %d" % [k, handled, int(floor[k])])
