class_name Automation
extends RefCounted
## What the engine does for each piece of a mech and its pilot, and what the table still
## handles, in plain words for players (the builder and the action bar show it).
## Entry: {kind: trait|core|system|weapon|talent, id, name, status: automated|partial|manual,
##         note: what the table handles (partial), guidance: what to do, text: the rule}.

const NOTES := "res://data/game/automation_notes.json"
const MANUAL_GUIDANCE := "The game doesn't do this one for you yet. When it comes up, read the rule and resolve it together at the table: the GM has the final say and can change HP, heat, conditions or positions by hand."
const PARTIAL_GUIDANCE := "Mostly automatic. The table handles one part: %s"

static var _notes: Dictionary = {}


## Weapons whose special rules live in the rules code (by id) rather than weapon_effects.json.
const CODE_WEAPONS := ["mw_autopod", "mw_vorpal_gun", "mw_mimic_gun", "mw_gravity_gun", "mw_ghoul_nexus", "mw_tachyon_lance",
	"mw_prototype_1", "mw_prototype_2", "mw_prototype_3", "mw_raleigh_integrated", "mw_pinaka_missiles", "mw_ghast_nexus"]


static func notes() -> Dictionary:
	if _notes.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(NOTES))
		_notes = d if d is Dictionary else {}
	return _notes


static func entry(kind: String, id: String, name: String, status: String, note: String, text: String) -> Dictionary:
	var guidance := ""
	match status:
		"manual":
			guidance = MANUAL_GUIDANCE
		"partial":
			guidance = PARTIAL_GUIDANCE % note
	return {"kind": kind, "id": id, "name": name, "status": status, "note": note, "guidance": guidance, "text": text}


static func _strip(v: Variant) -> String:
	if v == null:
		return ""
	if v is Dictionary:
		return _strip((v as Dictionary).get("detail", ""))
	return RegEx.create_from_string("<[^>]+>").sub(str(v), "", true).strip_edges()


## A ready-made unit (in battle or built for the builder).
static func for_unit(db: ContentDB, u: Unit) -> Array:
	var out: Array = []
	var n := notes()
	for t: Dictionary in u.loadout.get("traits", []):
		var tnote := String(t.get("manual_note", ""))
		var ts := "manual" if not t.get("automated", false) else ("partial" if tnote != "" else "automated")
		out.append(entry("trait", String(t["name"]), String(t["name"]), ts, tnote, _strip(t.get("text", ""))))
	var core: Dictionary = u.loadout.get("core", {})
	if not core.is_empty():
		var cnote := String(core.get("manual_note", ""))
		var cs := "manual" if not core.get("automated", false) else ("partial" if cnote != "" else "automated")
		out.append(entry("core", String(core.get("name", "")), String(core.get("name", "")), cs, cnote, _strip(core.get("text", ""))))
	var gear := UnitFactory.gear_effects_data()
	for s: Dictionary in u.loadout.get("systems", []):
		var id := String(s["id"])
		var raw := db.system(id)
		var abil := (u.loadout.get("abilities", []) as Array).filter(func(a: Dictionary) -> bool: return a["source_key"] == s["key"])
		var status := "automated"
		if abil.is_empty():
			if not gear.has(id) and _strip(raw.get("effect", "")) != "":
				status = "manual"
		else:
			var done := abil.filter(func(a: Dictionary) -> bool: return a.get("automated", false)).size()
			if done == 0 and not gear.has(id):
				status = "manual"
			elif done < abil.size():
				status = "partial"
		var note := String(n.get(id, ""))
		if status == "partial" and note == "":
			var left := abil.filter(func(a: Dictionary) -> bool: return not a.get("automated", false)).map(func(a: Dictionary) -> String: return String(a["name"]))
			note = "%s %s applied at the table." % [", ".join(left), "is" if left.size() == 1 else "are"]
		elif status == "automated" and note != "":
			status = "partial"
		out.append(entry("system", id, String(raw.get("name", id)), status, note, _strip(raw.get("effect", ""))))
	var seen := {}
	for w: Dictionary in u.loadout.get("weapons", []):
		var id := String(w.get("id", ""))
		if seen.has(id):
			continue
		seen[id] = true
		var raw := db.weapon(id)
		if raw.is_empty() and w.has("npc_on_hit"):
			raw = {"name": w.get("name", id), "on_hit": w.get("npc_on_hit", ""), "effect": w.get("npc_effect", "")}  # an NPC feature
		var text := " ".join([_strip(raw.get("effect", "")), _strip(raw.get("on_hit", "")), _strip(raw.get("on_crit", "")), _strip(raw.get("on_attack", ""))]).strip_edges()
		var wabil := (u.loadout.get("abilities", []) as Array).filter(func(a: Dictionary) -> bool: return a["source_key"] == "w:" + String(w["key"]))
		var encoded: bool = w.has("rules") or w.has("data_on_hit") or w.has("data_on_crit") or CODE_WEAPONS.has(id) or not WeaponRules.rules(w).is_empty()
		if not wabil.is_empty():
			encoded = wabil.all(func(a: Dictionary) -> bool: return a.get("automated", false))
		var status := "automated" if text == "" or encoded else "manual"
		var note := String(n.get(id, ""))
		if status == "automated" and note != "":
			status = "partial"
		out.append(entry("weapon", id, String(raw.get("name", id)), status, note, text))
		if w.has("mod"):
			var mid := String(w["mod"]["id"])
			var mraw := db.get_entry("mods", mid)
			var mnote := String(n.get(mid, ""))
			out.append(entry("mod", mid, String(mraw.get("name", mid)), "partial" if mnote != "" else "automated", mnote, _strip(mraw.get("effect", ""))))
	return out


## Talents, rank by rank (from the pilot record: {talent id: rank}).
static func for_talents(db: ContentDB, talents: Dictionary) -> Array:
	var out: Array = []
	var gear := UnitFactory.gear_effects_data()
	var acts := UnitFactory.activation_data()
	var n := notes()
	for tid: String in talents:
		var tal := db.get_entry("talents", tid)
		var ranks: Array = tal.get("ranks", [])
		for r in range(mini(int(talents[tid]), ranks.size())):
			var rank: Dictionary = ranks[r]
			var enc := (gear.get(tid, {}) as Dictionary).has(str(r + 1)) if gear.get(tid) is Dictionary else false
			for a: Dictionary in rank.get("actions", []):
				enc = enc or acts.get("%s:%s" % [tid, a.get("name", "")]) is Array
			var key := "%s:%d" % [tid, r + 1]
			var status := "automated" if enc else "manual"
			if enc and n.has(key):
				status = "partial"
			out.append(entry("talent", key, "%s %d: %s" % [tal.get("name", tid), r + 1, rank.get("name", "")], status, String(n.get(key, "")), _strip(rank.get("description", ""))))
	return out


## For the builder: a frame, loadout and pilot record, before any battle.
static func for_build(db: ContentDB, frame_id: String, loadout: Dictionary, pilot: Dictionary) -> Array:
	var u := UnitFactory.build_mech(db, "preview", frame_id, loadout, pilot)
	var out := for_unit(db, u)
	out.append_array(for_talents(db, pilot.get("talents", {})))
	return out


## Just the things a player has to handle themselves (manual or partial).
static func needs_table(report: Array) -> Array:
	return report.filter(func(e: Dictionary) -> bool: return e["status"] != "automated")
