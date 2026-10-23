class_name ContentDB
extends RefCounted
## Read-only access to the official Lancer data in res://data/lancer-data/, plus any content
## packs added on top (add_pack). Entries are the raw lancer-data dictionaries; see that repo's
## wiki for field meanings. NPC collections (npc_classes, npc_templates, npc_features) are
## empty in the core data and filled by packs such as the official NPC pack.

const DATA_DIR := "res://data/lancer-data/"

## Collection name -> file. Entries are keyed by "id", or "name" where there is no id.
const FILES := {
	"frames": "frames.json",
	"weapons": "weapons.json",
	"systems": "systems.json",
	"mods": "mods.json",
	"core_bonuses": "core_bonuses.json",
	"talents": "talents.json",
	"tags": "tags.json",
	"statuses": "statuses.json",
	"actions": "actions.json",
	"glossary": "glossary.json",
	"environments": "environments.json",
	"sitreps": "sitreps.json",
	"manufacturers": "manufacturers.json",
	"pilot_gear": "pilot_gear.json",
	"reserves": "reserves.json",
	"skills": "skills.json",
	"backgrounds": "backgrounds.json",
	"downtime_actions": "downtime_actions.json",
	"tables": "tables.json",
}

## Collections that only content packs provide.
const PACK_ONLY := ["npc_classes", "npc_templates", "npc_features"]
## The official NPC numbers typed from the user's own core book (docs/NPC_PACK.md). Local
## only: /local/ is gitignored, so the public repo never has it; loaded when present.
const LOCAL_NPC_PACK := "res://local/content/core_npcs.json"

## Packs added on top of the core data, in order: [ContentPack.summary()].
var packs: Array = []
var _collections: Dictionary = {}  # name -> {key -> entry}
var _by_name: Dictionary = {}  # collection -> {lowercase display name -> key}
## rules.json: base numbers (structure, stress, mount fittings, overcharge...).
var rules: Dictionary = {}
var info: Dictionary = {}


## Loads everything. Returns false (and logs) if a file is missing or malformed.
func load_all(dir: String = DATA_DIR) -> bool:
	var ok := true
	for collection: String in FILES:
		var data: Variant = _read_json(dir + FILES[collection])
		if not data is Array:
			ok = false
			continue
		_collections[collection] = {}
		_by_name[collection] = {}
		_index(collection, data)
	for collection: String in PACK_ONLY:
		_collections[collection] = {}
		_by_name[collection] = {}
	rules = _read_json(dir + "rules.json") if FileAccess.file_exists(dir + "rules.json") else {}
	info = _read_json(dir + "info.json") if FileAccess.file_exists(dir + "info.json") else {}
	if FileAccess.file_exists(LOCAL_NPC_PACK):
		add_pack(ContentPack.from_json(LOCAL_NPC_PACK))
	return ok


## Adds a content pack's entries on top of what's loaded (same id = the pack's version wins,
## as in COMP/CON). Returns false if the pack couldn't be read.
func add_pack(pack: ContentPack) -> bool:
	if pack.error != "":
		return false
	for collection: String in pack.collections:
		if not _collections.has(collection):
			_collections[collection] = {}
			_by_name[collection] = {}
		_index(collection, pack.collections[collection])
	packs.append(pack.summary())
	return true


func _index(collection: String, data: Array) -> void:
	var index: Dictionary = _collections[collection]
	var names: Dictionary = _by_name[collection]
	for entry: Variant in data:
		if not entry is Dictionary:
			continue
		var key: String = str(entry.get("id", entry.get("name", "")))
		# Some files repeat a name for pilot and mech versions (e.g. actions); keep both.
		if index.has(key) and entry.has("activation"):
			key = "%s|%s" % [key, entry["activation"]]
		index[key] = entry
		if entry.has("name"):
			names[String(entry["name"]).to_lower()] = key


## Looks up by id first, then by display name (case-insensitive), e.g. "Jammed".
func get_entry(collection: String, key: String) -> Dictionary:
	var index: Dictionary = _collections.get(collection, {})
	if index.has(key):
		return index[key]
	var by_name: Dictionary = _by_name.get(collection, {})
	return index.get(by_name.get(key.to_lower(), ""), {})


func all(collection: String) -> Array:
	return _collections.get(collection, {}).values()


func count(collection: String) -> int:
	return _collections.get(collection, {}).size()


func frame(id: String) -> Dictionary:
	return get_entry("frames", id)


func weapon(id: String) -> Dictionary:
	return get_entry("weapons", id)


func system(id: String) -> Dictionary:
	return get_entry("systems", id)


## Rule text for a status or glossary term, with HTML tags stripped.
func rule_text(term: String) -> String:
	var entry := get_entry("statuses", term)
	var text: String = entry.get("effects", "")
	if text == "":
		text = get_entry("glossary", term).get("description", "")
	var re := RegEx.create_from_string("<[^>]+>")
	return re.sub(text, "", true).strip_edges()


func _read_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("ContentDB: can't read " + path)
		return null
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("ContentDB: bad JSON in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data
