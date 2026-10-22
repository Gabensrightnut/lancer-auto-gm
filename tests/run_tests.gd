extends SceneTree
## Headless test runner:
##   godot --headless --path . -s res://tests/run_tests.gd
## Runs every test_* method in every tests/unit/*.gd file. Exit code 1 on any failure.

const UNIT_DIR := "res://tests/unit/"


func _init() -> void:
	var total := 0
	var failed: Array[String] = []
	var files := DirAccess.get_files_at(UNIT_DIR)
	files.sort()
	for file in files:
		if not file.ends_with(".gd"):
			continue
		var script: GDScript = load(UNIT_DIR + file)
		for method in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			var test: TestCase = script.new()
			test.run_test(name)
			total += 1
			if test.failures.is_empty():
				print("  ok    %s.%s" % [file.get_basename(), name])
			else:
				print("  FAIL  %s.%s" % [file.get_basename(), name])
				for f in test.failures:
					print("        " + f)
				failed.append(name)
	print("\n%d tests, %d failed" % [total, failed.size()])
	quit(1 if not failed.is_empty() or total == 0 else 0)
