extends TestCase
## The launcher's update logic (launcher/update_logic.gd): release parsing, checksums,
## installing, rollback and cleanup. Uses a scratch folder in user://, never real installs.

var Logic: GDScript = load("res://launcher/update_logic.gd")
var root := ""


func _logic() -> RefCounted:
	root = "user://test_launcher_%d" % Time.get_ticks_usec()
	return Logic.new(root)


func _make_zip(path: String, files: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var zip := ZIPPacker.new()
	zip.open(path)
	for name: String in files:
		zip.start_file(name)
		zip.write_file((files[name] as String).to_utf8_buffer())
		zip.close_file()
	zip.close()
	return Logic.sha256_file(path)


func _cleanup() -> void:
	Logic._remove_tree(root)


func test_parse_release_finds_the_game_build() -> void:
	var json := JSON.stringify({
		"tag_name": "v1.4.0", "body": "Notes",
		"assets": [
			{"name": "LancerLauncher.exe", "browser_download_url": "https://x/launcher"},
			{"name": "LancerAutoGM-windows-1.4.0.zip", "browser_download_url": "https://x/game.zip"},
			{"name": "SHA256SUMS.txt", "browser_download_url": "https://x/sums"},
		],
	})
	var r: Dictionary = Logic.parse_release(json)
	expect_eq(r.get("version"), "1.4.0")
	expect_eq(r.get("zip_url"), "https://x/game.zip")
	expect_eq(r.get("sums_url"), "https://x/sums")
	expect(Logic.parse_release(JSON.stringify({"tag_name": "v2", "assets": []})).has("error"))
	expect(Logic.parse_release("not json").has("error"))
	expect(not Logic.is_safe_version("../evil"))
	expect(Logic.is_safe_version("1.4.0-beta.2"))


func test_parse_sums() -> void:
	var h := "ab".repeat(32)
	var sums: Dictionary = Logic.parse_sums("%s  LancerAutoGM-windows-1.zip\n%s *LancerLauncher.exe\n" % [h, h.to_upper()])
	expect_eq(sums.get("LancerAutoGM-windows-1.zip"), h)
	expect_eq(sums.get("LancerLauncher.exe"), h, "binary-mode marker and case are ignored")


func test_install_update_and_rollback() -> void:
	var logic := _logic()
	var zip1 := root + "/downloads/v1.zip"
	var sha1 := _make_zip(zip1, {"LancerAutoGM.exe": "game v1", "libwebrtc.dll": "dll"})
	expect_eq(logic.install(zip1, "1.0.0", sha1), "")
	expect_eq(logic.current_version(), "1.0.0")
	expect(logic.game_exe() != "")
	expect(FileAccess.file_exists(logic.versions_dir() + "/1.0.0/libwebrtc.dll"))
	var zip2 := root + "/downloads/v2.zip"
	var sha2 := _make_zip(zip2, {"LancerAutoGM.exe": "game v2"})
	expect_eq(logic.install(zip2, "1.1.0", sha2), "")
	expect_eq(logic.current_version(), "1.1.0")
	expect_eq(logic.previous_version(), "1.0.0", "old version kept for rollback")
	expect_eq(FileAccess.get_file_as_string(logic.game_exe()), "game v2")
	expect_eq(logic.rollback(), "")
	expect_eq(logic.current_version(), "1.0.0")
	expect_eq(FileAccess.get_file_as_string(logic.game_exe()), "game v1")
	expect(not DirAccess.dir_exists_absolute(logic.downloads_dir()), "downloads cleaned up")
	_cleanup()


func test_only_two_versions_are_kept() -> void:
	var logic := _logic()
	for v in ["1.0.0", "1.1.0", "1.2.0"]:
		var zip := root + "/downloads/%s.zip" % v
		expect_eq(logic.install(zip, v, _make_zip(zip, {"LancerAutoGM.exe": v})), "")
	var dirs := Array(DirAccess.get_directories_at(logic.versions_dir()))
	dirs.sort()
	expect_eq(dirs, ["1.1.0", "1.2.0"])
	_cleanup()


func test_bad_downloads_change_nothing() -> void:
	var logic := _logic()
	var good := root + "/downloads/good.zip"
	expect_eq(logic.install(good, "1.0.0", _make_zip(good, {"LancerAutoGM.exe": "ok"})), "")
	var bad := root + "/downloads/bad.zip"
	_make_zip(bad, {"LancerAutoGM.exe": "tampered"})
	expect(logic.install(bad, "2.0.0", "00".repeat(32)) != "", "checksum mismatch is refused")
	var empty := root + "/downloads/empty.zip"
	expect(logic.install(empty, "2.0.0", _make_zip(empty, {"readme.txt": "no exe"})) != "")
	var evil := root + "/downloads/evil.zip"
	expect(logic.install(evil, "2.0.0", _make_zip(evil, {"../escape.exe": "x", "LancerAutoGM.exe": "x"})) != "")
	expect(not FileAccess.file_exists(logic.versions_dir() + "/escape.exe"))
	expect_eq(logic.current_version(), "1.0.0")
	expect_eq(Array(DirAccess.get_directories_at(logic.versions_dir())), ["1.0.0"])
	expect(logic.rollback() != "", "nothing to roll back to yet")
	_cleanup()
