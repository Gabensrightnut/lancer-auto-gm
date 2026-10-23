extends SceneTree
## Headless test runner:
##   godot --headless --path . -s res://tests/run_tests.gd
## Runs every test_* method in every tests/unit/*.gd file. Exit code 1 on any failure.
## Only some: ... -s res://tests/run_tests.gd -- <text>  (files or tests containing it).

const UNIT_DIR := "res://tests/unit/"


func _init() -> void:
	ContentDB.use_local_pack = false  # results never depend on the gitignored local NPC pack
	var total := 0
	var failed: Array[String] = []
	var only: Array = OS.get_cmdline_user_args()  # several filters run tests matching any of them
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
			if not only.is_empty() and not only.any(func(f: String) -> bool: return (file + "." + name).contains(f)):
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
