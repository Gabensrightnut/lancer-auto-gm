class_name PackLibrary
extends RefCounted
## The content packs installed on this computer (user://packs/*.lcp, the player's own files)
## and building a ContentDB with the ones a campaign turns on.
##
## A pack list (in a campaign, a GameState, a join request) is [{"id", "name", "version"...}];
## two lists match when every id is there with the same version.

const DIR := "user://packs/"

var dir := DIR
var _cache: Dictionary = {}  # path -> ContentPack


func _init(packs_dir: String = DIR) -> void:
	dir = packs_dir


## Every .lcp in the packs folder: [ContentPack] (check each one's `error`).
func installed() -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var files := DirAccess.get_files_at(dir)
	files.sort()
	for f in files:
		if f.get_extension().to_lower() == "lcp":
			var path := dir.path_join(f)
			if not _cache.has(path):
				_cache[path] = ContentPack.read(path)
			out.append(_cache[path])
	return out


## Summaries of the readable installed packs (what a client tells the host it has).
func installed_summaries() -> Array:
	var out: Array = []
	for p: ContentPack in installed():
		if p.error == "":
			out.append(p.summary())
	return out


func find(pack_id: String) -> ContentPack:
	for p: ContentPack in installed():
		if p.id == pack_id and p.error == "":
			return p
	return null


## Copies a .lcp the player picked into the packs folder. Returns the pack (check `error`).
func install(from_path: String) -> ContentPack:
	var pack := ContentPack.read(from_path)
	if pack.error != "":
		return pack
	DirAccess.make_dir_recursive_absolute(dir)
	var dest := dir.path_join(from_path.get_file())
	if ProjectSettings.globalize_path(dest) != ProjectSettings.globalize_path(from_path):
		DirAccess.copy_absolute(from_path, dest)
	_cache.erase(dest)
	return ContentPack.read(dest)


## The core data plus the given packs, in order. {"db": ContentDB, "missing": [summaries]}.
func load_db(wanted: Array) -> Dictionary:
	var db := ContentDB.new()
	db.load_all()
	var missing: Array = []
	for w: Variant in wanted:
		var pack := find(str(w.get("id", ""))) if w is Dictionary else null
		if pack == null or (w.get("version", "") != "" and pack.version != w["version"]):
			missing.append(w)
		else:
			db.add_pack(pack)
	return {"db": db, "missing": missing}


## Which of `required` aren't in `have` (by id and version). Used by the host on join.
static func missing(required: Array, have: Array) -> Array:
	var by_id := {}
	for h: Variant in have:
		if h is Dictionary:
			by_id[str(h.get("id", ""))] = str(h.get("version", ""))
	var out: Array = []
	for r: Dictionary in required:
		if by_id.get(str(r.get("id", "")), null) != str(r.get("version", "")):
			out.append(r)
	return out


## "Long Rim 1.2.0, KTB Data 2.0.1" for messages.
static func describe(list: Array) -> String:
	var names := PackedStringArray()
	for p: Dictionary in list:
		names.append("%s %s" % [p.get("name", p.get("id", "?")), p.get("version", "")])
	return ", ".join(names)
