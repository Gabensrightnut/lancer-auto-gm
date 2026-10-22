class_name ContentPack
extends RefCounted
## A Lancer Content Pack (.lcp): the format COMP/CON uses for official supplements (Long Rim,
## Wallflower, KTB, Dustgrave...), the NPC pack and community content. It's a zip of
## lancer-data-style JSON files plus lcp_manifest.json {name, author, version, item_prefix...}.
## Packs are the player's own files in user://packs/ and never go in the repo.
##
## Read the same way COMP/CON reads them:
## - library files: frames.json, weapons.json, systems.json, mods.json, talents.json,
##   core_bonuses.json, tags.json, pilot_gear.json, npc_classes.json, npc_templates.json,
##   npc_*.json (NPC features) and the rest of ContentDB.FILES;
## - collection files: license_*.json (a frame plus its gear), npcc_*.json (an NPC class plus
##   its features), npct_*.json (an NPC template plus its features);
## - entries without an id get one made from the item prefix and name.

const MANIFEST := "lcp_manifest.json"

## The id COMP/CON gives a pack (SHA-1 of "author/name", base64), so pack lists match between
## the two programs.
var id := ""
var name := ""
var author := ""
var version := ""
var description := ""
var website := ""
var item_prefix := ""
var path := ""
## collection name -> Array of entries
var collections: Dictionary = {}
## Why the pack couldn't be read ("" = fine).
var error := ""


## Reads a .lcp file. Check `error` on the result.
static func read(file_path: String) -> ContentPack:
	var p := ContentPack.new()
	p.path = file_path
	var zip := ZIPReader.new()
	if zip.open(file_path) != OK:
		p.error = "Not a readable content pack (expected a .lcp zip file)."
		return p
	var files := zip.get_files()
	var manifest: Variant = _zip_json(zip, MANIFEST)
	if not manifest is Dictionary:
		p.error = "This content pack has no lcp_manifest.json."
		zip.close()
		return p
	for key in ["name", "author", "version"]:
		if not manifest.get(key) is String:
			p.error = "The content pack's manifest is missing its %s." % key
			zip.close()
			return p
	p.name = manifest["name"]
	p.author = manifest["author"]
	p.version = manifest["version"]
	p.description = str(manifest.get("description", ""))
	p.website = str(manifest.get("website", ""))
	p.item_prefix = str(manifest.get("item_prefix", ""))
	p.id = pack_id(p.author, p.name)
	# Library files: same names as core lancer-data.
	var prefixes := {"tags": "tg", "core_bonuses": "cb", "pilot_gear": "pg", "talents": "t",
		"frames": "mf", "weapons": "mw", "systems": "ms", "mods": "wm"}
	for collection: String in ContentDB.FILES:
		var data := _zip_array(zip, ContentDB.FILES[collection])
		if prefixes.has(collection):
			data = p._with_ids(data, prefixes[collection])
		if not data.is_empty():
			p.collections[collection] = data
	for collection in ["npc_classes", "npc_templates"]:
		var data := _zip_array(zip, collection + ".json")
		if not data.is_empty():
			p.collections[collection] = data
	var features: Array = []
	for f in files:
		if f.begins_with("npc_") and not "classes" in f and not "templates" in f and f.ends_with(".json"):
			features.append_array(_zip_array(zip, f))
	# Collection files.
	for f in files:
		if f.begins_with("license_"):
			var group := _zip_array(zip, f)
			var frame := {}
			for e: Variant in group:
				if e is Dictionary and e.has("mechtype"):
					frame = e
					break
			if frame.is_empty():
				continue
			p._append("frames", frame)
			for e: Variant in group:
				if not e is Dictionary or e == frame:
					continue
				e["license_id"] = frame.get("id", "")
				e["source"] = frame.get("source", "")
				e["license"] = frame.get("name", "")
				if e.get("data_type", "") == "weapon" or e.has("mount"):
					p._append("weapons", e)
				elif e.get("data_type", "") == "mod" or e.has("allowed_types"):
					p._append("mods", e)
				else:
					p._append("systems", e)
		elif f.begins_with("npcc_") or f.begins_with("npct_"):
			var is_class := f.begins_with("npcc_")
			var group := _zip_array(zip, f)
			var head := {}
			for e: Variant in group:
				if e is Dictionary and e.has("role" if is_class else "template"):
					head = e
					break
			if head.is_empty():
				continue
			p._append("npc_classes" if is_class else "npc_templates", head)
			for e: Variant in group:
				if e is Dictionary and e != head:
					e["origin"] = head.get("id", "")
					features.append(e)
	if not features.is_empty():
		p.collections["npc_features"] = features
	# A frame is its own license (as in lancer-data); older packs leave license_id out.
	for f: Variant in p.collections.get("frames", []):
		if f is Dictionary and not f.has("license_id"):
			f["license_id"] = f.get("id", "")
	zip.close()
	return p


## COMP/CON's pack id: base64(SHA-1("author/name")).
static func pack_id(pack_author: String, pack_name: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update(("%s/%s" % [pack_author, pack_name]).to_utf8_buffer())
	return Marshalls.raw_to_base64(ctx.finish())


## What gets recorded in a game or campaign so others can check they have the same pack.
func summary() -> Dictionary:
	return {"id": id, "name": name, "author": author, "version": version, "website": website}


func count() -> int:
	var n := 0
	for c: Array in collections.values():
		n += c.size()
	return n


func _append(collection: String, entry: Dictionary) -> void:
	if not collections.has(collection):
		collections[collection] = []
	(collections[collection] as Array).append(entry)


## COMP/CON gives entries without an id one built from the pack prefix and the name.
func _with_ids(data: Array, type_prefix: String) -> Array:
	var out: Array = []
	for e: Variant in data:
		if e is Dictionary and not e.has("id") and e.get("name") is String:
			var clean := RegEx.create_from_string("[^A-Za-z0-9_]").sub(
				RegEx.create_from_string("[ /-]").sub(e["name"], "_", true), "", true).to_lower()
			e = e.duplicate()
			e["id"] = "%s__%s_%s" % [item_prefix, type_prefix, clean]
		out.append(e)
	return out


static func _zip_json(zip: ZIPReader, file: String) -> Variant:
	if not zip.file_exists(file):
		return null
	var json := JSON.new()
	if json.parse(zip.read_file(file).get_string_from_utf8()) != OK:
		push_warning("Content pack file %s isn't valid JSON; skipped." % file)
		return null
	return json.data


static func _zip_array(zip: ZIPReader, file: String) -> Array:
	var data: Variant = _zip_json(zip, file)
	return data if data is Array else []
