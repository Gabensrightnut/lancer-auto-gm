extends RefCounted
## The launcher's update logic without any UI or networking, so it can be tested headless:
## reading a GitHub release, checking SHA-256 sums, unpacking a build, and keeping the
## current + previous version on disk for rollback.
##
## On disk (inside the launcher's own user data folder, never the game's saves):
##   <root>/versions/<version>/LancerAutoGM.exe   one folder per installed version
##   <root>/installs.json                         {"current": "1.2.0", "previous": "1.1.0"}
##   <root>/downloads/                            temporary downloads

const REPO := "Gabensrightnut/lancer-auto-gm"
const LATEST_RELEASE_URL := "https://api.github.com/repos/" + REPO + "/releases/latest"
const GAME_ZIP_PREFIX := "LancerAutoGM-windows-"
const SUMS_NAME := "SHA256SUMS.txt"
const GAME_EXE := "LancerAutoGM.exe"

var root: String


func _init(root_dir: String = "user://") -> void:
	root = root_dir


# --- Release info -----------------------------------------------------------------------

## Reads a GitHub "latest release" response. Returns {version, zip_url, zip_name, sums_url,
## notes} or {"error": "..."} when the release has no Windows game build.
static func parse_release(json_text: String) -> Dictionary:
	var data: Variant = _parse_json(json_text)
	if not data is Dictionary or not data.has("tag_name"):
		return {"error": "GitHub sent something unexpected."}
	var out := {"version": version_from_tag(str(data["tag_name"])), "notes": str(data.get("body", ""))}
	for asset: Variant in data.get("assets", []):
		if not asset is Dictionary:
			continue
		var name := str(asset.get("name", ""))
		if name.begins_with(GAME_ZIP_PREFIX) and name.ends_with(".zip"):
			out["zip_name"] = name
			out["zip_url"] = str(asset.get("browser_download_url", ""))
		elif name == SUMS_NAME:
			out["sums_url"] = str(asset.get("browser_download_url", ""))
	if not out.has("zip_url") or not out.has("sums_url"):
		return {"error": "The latest release (%s) has no Windows game download yet." % out["version"]}
	if not is_safe_version(out["version"]):
		return {"error": "The latest release has an odd version name: %s" % out["version"]}
	return out


## Like JSON.parse_string, but quiet on bad input (returns null).
static func _parse_json(text: String) -> Variant:
	var json := JSON.new()
	return json.data if json.parse(text) == OK else null


static func version_from_tag(tag: String) -> String:
	return tag.trim_prefix("v")


## Version names become folder names, so only allow plain characters.
static func is_safe_version(version: String) -> bool:
	if version == "" or version.begins_with("."):
		return false
	for ch in version:
		if not (ch.is_valid_identifier() or ch in "0123456789.-+"):
			return false
	return true


# --- Checksums --------------------------------------------------------------------------

## Reads `sha256sum` output ("<hash>  <file>" per line) into {file name: lowercase hash}.
static func parse_sums(text: String) -> Dictionary:
	var sums := {}
	for line in text.split("\n", false):
		var parts := line.strip_edges().split(" ", false)
		if parts.size() == 2 and parts[0].length() == 64:
			sums[parts[1].trim_prefix("*")] = parts[0].to_lower()
	return sums


static func sha256_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	while not f.eof_reached():
		ctx.update(f.get_buffer(1 << 20))
	return ctx.finish().hex_encode()


# --- Installed versions -----------------------------------------------------------------

func versions_dir() -> String:
	return root.path_join("versions")


func downloads_dir() -> String:
	return root.path_join("downloads")


func load_state() -> Dictionary:
	var path := root.path_join("installs.json")
	if not FileAccess.file_exists(path):
		return {"current": "", "previous": ""}
	var data: Variant = _parse_json(FileAccess.get_file_as_string(path))
	if not data is Dictionary:
		return {"current": "", "previous": ""}
	return {"current": str(data.get("current", "")), "previous": str(data.get("previous", ""))}


func save_state(state: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(root)
	var f := FileAccess.open(root.path_join("installs.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(state, "\t"))


func current_version() -> String:
	return load_state()["current"]


func previous_version() -> String:
	return load_state()["previous"]


## Path of the game exe for `version` ("" = current), or "" if it isn't installed.
func game_exe(version: String = "") -> String:
	if version == "":
		version = current_version()
	var path := "%s/%s/%s" % [versions_dir(), version, GAME_EXE]
	return path if version != "" and FileAccess.file_exists(path) else ""


## Checks `zip_path` against `expected_sha256`, unpacks it as `version`, makes it current and
## keeps the old current as previous. Returns "" on success or a reason it failed. A failed
## install leaves the installed versions as they were.
func install(zip_path: String, version: String, expected_sha256: String) -> String:
	if not is_safe_version(version):
		return "Bad version name: " + version
	var actual := sha256_file(zip_path)
	if actual == "" or actual != expected_sha256.to_lower():
		return "The download is damaged (its checksum doesn't match). Try again."
	var final_dir := "%s/%s" % [versions_dir(), version]
	var temp_dir := final_dir + ".partial"
	_remove_tree(temp_dir)
	var err := _unzip(zip_path, temp_dir)
	if err != "":
		_remove_tree(temp_dir)
		return err
	if not FileAccess.file_exists(temp_dir + "/" + GAME_EXE):
		_remove_tree(temp_dir)
		return "The download doesn't contain %s." % GAME_EXE
	var state := load_state()
	if state["current"] == version:
		state["current"] = state["previous"]  # Reinstalling: don't keep it as its own backup.
	_remove_tree(final_dir)
	if DirAccess.rename_absolute(temp_dir, final_dir) != OK:
		_remove_tree(temp_dir)
		return "Couldn't move the new version into place."
	save_state({"current": version, "previous": state["current"]})
	prune()
	return ""


## Swaps back to the previous version. Returns "" or why it can't.
func rollback() -> String:
	var state := load_state()
	if state["previous"] == "" or game_exe(state["previous"]) == "":
		return "There's no previous version to go back to."
	save_state({"current": state["previous"], "previous": state["current"]})
	return ""


## Deletes every installed version except current and previous, and leftover downloads.
func prune() -> void:
	var state := load_state()
	var keep := [state["current"], state["previous"]]
	for dir in DirAccess.get_directories_at(versions_dir()):
		if not dir in keep:
			_remove_tree(versions_dir() + "/" + dir)
	_remove_tree(downloads_dir())


static func _unzip(zip_path: String, dest: String) -> String:
	var zip := ZIPReader.new()
	if zip.open(zip_path) != OK:
		return "The download isn't a readable zip file."
	DirAccess.make_dir_recursive_absolute(dest)
	for name in zip.get_files():
		# Refuse paths that would land outside the version folder.
		if name.begins_with("/") or ".." in name.split("/") or ":" in name:
			zip.close()
			return "The download contains an unsafe file path: " + name
		if name.ends_with("/"):
			DirAccess.make_dir_recursive_absolute(dest + "/" + name)
			continue
		DirAccess.make_dir_recursive_absolute((dest + "/" + name).get_base_dir())
		var f := FileAccess.open(dest + "/" + name, FileAccess.WRITE)
		if f == null:
			zip.close()
			return "Couldn't write %s (disk full or no permission?)." % name
		f.store_buffer(zip.read_file(name))
	zip.close()
	return ""


static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path + "/" + file)
	for dir in DirAccess.get_directories_at(path):
		_remove_tree(path + "/" + dir)
	DirAccess.remove_absolute(path)
