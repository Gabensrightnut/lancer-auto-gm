class_name CharacterRoster
extends RefCounted
## Saved characters (the squad-creation lobby's "Save character" / "Load saved"): a personal
## roster in user://characters/, one small JSON file per character. A saved character is that
## same person in every campaign, but only their identity and their choices are kept, never
## numbers: name, callsign, look and colours, background, origin, personality, quirks,
## motivation, play style, a short bio, and the build they prefer (skills, talents, licenses,
## core bonuses, mech frame and loadout). Loading always rebuilds them from the book for that
## campaign (CharacterSanity): money, manna, items, XP, License Level, reserves, implants and
## bounties never carry over. A little history (campaigns played, notable moments) is flavour
## text only.
##
## Files are plain JSON (no code, no paths); imports are size-limited and schema-checked, and
## unknown fields are dropped.

const DIR := "user://characters/"
const SCHEMA := 1
## The biggest file an import may be (bytes): a character is a few kilobytes.
const MAX_BYTES := 65536
const IDENTITY := ["name", "callsign", "portrait", "look", "background", "origin", "persona", "quirks", "motivation", "play_style", "bio", "pronouns"]
const BUILD := ["skills", "talents", "licenses", "core_bonuses", "hase", "mech"]
const MECH := ["frame", "name", "paint", "loadout"]

var dir := DIR


func _init(folder: String = DIR) -> void:
	dir = folder


## What a pilot record keeps when saved: identity and choices only.
static func from_pilot(pilot: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var identity := {}
	for k: String in IDENTITY:
		if pilot.has(k):
			identity[k] = pilot[k]
		elif extra.has(k):
			identity[k] = extra[k]
	if not identity.has("bio") and str(pilot.get("notes", "")) != "":
		identity["bio"] = str(pilot["notes"])
	var mech := {}
	for m: Dictionary in pilot.get("mechs", []):
		if str(m.get("id", "")) == str(pilot.get("active_mech", "")) or mech.is_empty():
			for k: String in MECH:
				if m.has(k):
					mech[k] = m[k]
	var build := {"skills": pilot.get("skills", {}), "talents": pilot.get("talents", {}), "licenses": pilot.get("licenses", {}),
		"core_bonuses": pilot.get("core_bonuses", []), "mech": mech,
		"hase": {"hull": pilot.get("hull", 0), "agility": pilot.get("agility", 0), "systems": pilot.get("systems", 0), "engineering": pilot.get("engineering", 0)}}
	return {"schema": SCHEMA, "identity": identity.duplicate(true), "build": build.duplicate(true), "history": [], "favourite": false}


## Keeps only what a saved character may hold (unknown fields, numbers and anything else in a
## file are dropped). {} if it isn't a character at all.
static func clean(d: Variant) -> Dictionary:
	if not d is Dictionary or int((d as Dictionary).get("schema", 0)) != SCHEMA or not (d as Dictionary).get("identity") is Dictionary:
		return {}
	var out := {"schema": SCHEMA, "identity": {}, "build": {}, "history": [], "favourite": bool(d.get("favourite", false)),
		"id": str(d.get("id", "")).left(64), "saved_at": int(d.get("saved_at", 0))}
	for k: String in IDENTITY:
		if (d["identity"] as Dictionary).has(k):
			out["identity"][k] = d["identity"][k]
	if str(out["identity"].get("name", "")).strip_edges() == "":
		return {}
	var b: Variant = d.get("build", {})
	if b is Dictionary:
		for k: String in BUILD:
			if (b as Dictionary).has(k):
				out["build"][k] = b[k]
		if out["build"].get("mech") is Dictionary:
			var m := {}
			for k: String in MECH:
				if (out["build"]["mech"] as Dictionary).has(k):
					m[k] = out["build"]["mech"][k]
			out["build"]["mech"] = m
	for h: Variant in d.get("history", []) if d.get("history") is Array else []:
		if out["history"].size() < 50:
			out["history"].append(str(h).left(200))  # flavour text only
	return out


# --- The roster on disk -------------------------------------------------------------------

func _path(id: String) -> String:
	return dir.path_join(id.validate_filename() + ".json")


## Saves a character (new id if it has none). Returns its id.
func save(character: Dictionary) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var c := clean(character)
	if c.is_empty():
		return ""
	if str(c["id"]) == "":
		c["id"] = "char_" + Crypto.new().generate_random_bytes(5).hex_encode()
	c["saved_at"] = int(Time.get_unix_time_from_system())
	var f := FileAccess.open(_path(c["id"]), FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(c, "\t"))
	return str(c["id"])


func load_one(id: String) -> Dictionary:
	return _read(_path(id))


static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > MAX_BYTES:
		return {}
	return clean(JSON.parse_string(f.get_as_text()))


## Every saved character, favourites first, then by name; `search` matches name or callsign.
func list(search: String = "") -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for f: String in DirAccess.get_files_at(dir):
		if not f.ends_with(".json"):
			continue
		var c := _read(dir.path_join(f))
		if c.is_empty():
			continue
		var who := "%s %s" % [c["identity"].get("name", ""), c["identity"].get("callsign", "")]
		if search == "" or who.to_lower().contains(search.to_lower()):
			out.append(c)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if bool(a["favourite"]) != bool(b["favourite"]):
			return bool(a["favourite"])
		return str(a["identity"].get("name", "")) < str(b["identity"].get("name", "")))
	return out


func set_favourite(id: String, on: bool) -> void:
	var c := load_one(id)
	if not c.is_empty():
		c["favourite"] = on
		save(c)


func rename(id: String, new_name: String) -> void:
	var c := load_one(id)
	if not c.is_empty() and new_name.strip_edges() != "":
		c["identity"]["name"] = new_name.strip_edges().left(48)
		save(c)


func duplicate_one(id: String) -> String:
	var c := load_one(id)
	if c.is_empty():
		return ""
	c["id"] = ""
	c["identity"]["name"] = "%s (copy)" % c["identity"].get("name", "")
	return save(c)


func delete(id: String) -> void:
	if FileAccess.file_exists(_path(id)):
		DirAccess.remove_absolute(_path(id))


## A line of history (flavour only: it never changes a new campaign).
func add_history(id: String, text: String) -> void:
	var c := load_one(id)
	if not c.is_empty():
		(c["history"] as Array).append(text.left(200))
		save(c)


## Writes a character to a file to share with friends.
func export_to(id: String, path: String) -> bool:
	var c := load_one(id)
	if c.is_empty():
		return false
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(c, "\t"))
	return true


## Reads a friend's character file into the roster (size-limited, schema-checked; unknown
## fields dropped). Returns the new id, or "" if it wasn't a character file.
func import_from(path: String) -> String:
	var c := _read(path)
	if c.is_empty():
		return ""
	c["id"] = ""
	return save(c)
