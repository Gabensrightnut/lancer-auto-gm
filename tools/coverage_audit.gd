extends SceneTree
## Writes docs/COVERAGE.md (core-book coverage) and prints the counts. Run headless through the
## GPU lock: tools/gpu_lock.sh run <session> -- <godot> --headless --path . -s res://tools/coverage_audit.gd


func _init() -> void:
	var db := ContentDB.new()
	db.load_all()
	var report := Coverage.audit(db)
	var f := FileAccess.open("res://docs/COVERAGE.md", FileAccess.WRITE)
	f.store_string(Coverage.markdown(report))
	f.close()
	for k: String in report:
		print("%s: %d/%d automated, %d partial, %d manual" % [k, report[k]["automated"], report[k]["total"], report[k]["partial"], report[k]["manual"]])
	quit()
