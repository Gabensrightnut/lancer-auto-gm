class_name Compcon
extends RefCounted
## COMP/CON pilot files in and out (COMP/CON by Massif Press, GPL-3.0; format learned from its
## test fixtures). Reads both the v2 pilot export and the v3 "Save Pilot" export
## ({"EXPORT_TYPE": "Save Pilot", "data": {...}}); writes the v2 layout, which COMP/CON imports.
##
## Our pilot record (also what UnitFactory and the campaign use):
##   {id, name, callsign, player_name, background, notes, history, ll,
##    hull, agility, systems, engineering, skills: {id: rank}, talents: {id: rank},
##    licenses: {frame id: rank}, core_bonuses: [id], reserves: [id], pilot_gear: [id],
##    mechs: [{id, name, frame, loadout: {mounts: [{weapons: [id], mod: id}], systems: [id]}}],
##    active_mech: mech id, compcon_id: the id COMP/CON gave the pilot}
## Only what the game uses is kept; everything else is listed in `notes` of the import result.


## Reads a COMP/CON pilot export (JSON text or the parsed Dictionary).
## Returns {ok, pilot, warnings: [String], errors: [String]}. `ok` is false only when the file
## can't be used at all; warnings explain anything that was dropped or isn't legal.
static func import_pilot(source: Variant, db: ContentDB) -> Dictionary:
	var out := {"ok": false, "pilot": {}, "warnings": [], "errors": []}
	var d: Variant = source
	if source is String:
		var json := JSON.new()
		if json.parse(source) != OK:
			out["errors"].append("This isn't a COMP/CON file (not valid JSON).")
			return out
		d = json.data
	if not d is Dictionary:
		out["errors"].append("This isn't a COMP/CON pilot file.")
		return out
	var v3: bool = d.has("EXPORT_TYPE")
	if v3:
		if str(d["EXPORT_TYPE"]) != "Save Pilot":
			out["errors"].append("That's a COMP/CON \"%s\" export, not a pilot. Export the pilot itself." % d["EXPORT_TYPE"])
			return out
		d = d.get("data", {})
	if not (d is Dictionary and d.has("callsign") and d.has("mechs")):
		out["errors"].append("This isn't a COMP/CON pilot file (no callsign or mechs).")
		return out
	var warn: Array = out["warnings"]
	var packs_hint := _packs_hint(d)
	var hase: Array = d.get("mechSkills", [0, 0, 0, 0])
	var p := {
		"id": "pilot_" + _uuid().left(8), "compcon_id": str(d.get("id", "")),
		"name": str(d.get("name", "")), "callsign": str(d.get("callsign", "")),
		"player_name": str(d.get("player_name", "")), "background": str(d.get("background", "")),
		"notes": _plain(str(d.get("notes", ""))), "history": _plain(str(d.get("history", ""))),
		"ll": clampi(int(d.get("level", 0)), 0, int(db.rules.get("max_pilot_level", 12))),
		"hull": int(hase[0]) if hase.size() > 0 else 0, "agility": int(hase[1]) if hase.size() > 1 else 0,
		"systems": int(hase[2]) if hase.size() > 2 else 0, "engineering": int(hase[3]) if hase.size() > 3 else 0,
		"skills": {}, "talents": {}, "licenses": {}, "core_bonuses": [], "reserves": [], "pilot_gear": [],
		"mechs": [], "active_mech": "",
	}
	for s: Variant in d.get("skills", []):
		if s is Dictionary:
			var sid := str(s.get("id", ""))
			if s.get("custom", false):
				warn.append("Custom skill trigger \"%s\" isn't supported yet and was left out." % s.get("custom_desc", sid))
			elif _known(db, "skills", sid, "skill trigger", warn, packs_hint):
				p["skills"][sid] = int(s.get("rank", 1))
	for t: Variant in d.get("talents", []):
		if t is Dictionary and _known(db, "talents", str(t.get("id", "")), "talent", warn, packs_hint):
			p["talents"][str(t["id"])] = int(t.get("rank", 1))
	for l: Variant in d.get("licenses", []):
		if l is Dictionary and _known(db, "frames", str(l.get("id", "")), "license", warn, packs_hint):
			p["licenses"][str(l["id"])] = int(l.get("rank", 1))
	for cb: Variant in d.get("core_bonuses", []):
		var cid := str(cb.get("id", "")) if cb is Dictionary else str(cb)
		if _known(db, "core_bonuses", cid, "core bonus", warn, packs_hint):
			p["core_bonuses"].append(cid)
	for r: Variant in d.get("reserves", []):
		if r is Dictionary and str(r.get("id", "")) != "":
			p["reserves"].append(str(r["id"]))
	var gear: Dictionary = d.get("loadout", {}) if not v3 else _pick(d.get("loadouts", []), int(d.get("active_index", 0)))
	for key in ["armor", "weapons", "gear"]:
		for g: Variant in gear.get(key, []):
			if g is Dictionary and str(g.get("id", "")) != "":
				p["pilot_gear"].append(str(g["id"]))
	if not p["pilot_gear"].is_empty():
		warn.append("Pilot gear (%d items) is kept but not used in battles yet." % p["pilot_gear"].size())
	for skipped in ["bond", "bondId", "orgs", "clocks"]:
		var val: Variant = d.get(skipped)
		if (val is Array and not val.is_empty()) or (val is String and val != "") or (val is Dictionary and not val.is_empty()):
			warn.append("COMP/CON %s data isn't used by this game yet and was left out." % skipped.replace("Id", ""))
	# Mechs.
	var active_id := str(d.get("state", {}).get("active_mech_id", "")) if not v3 else str(d.get("favorite_mech", ""))
	for m: Variant in d.get("mechs", []):
		if not m is Dictionary:
			continue
		var mech := _import_mech(m, db, p, warn, packs_hint)
		if mech.is_empty():
			continue
		p["mechs"].append(mech)
		if str(m.get("id", "")) == active_id or (m.get("active", false) and p["active_mech"] == ""):
			p["active_mech"] = mech["id"]
	if p["active_mech"] == "" and not p["mechs"].is_empty():
		p["active_mech"] = p["mechs"][0]["id"]
	for problem: Dictionary in UnitFactory.check_pilot(db, p):
		warn.append("Pilot: %s" % problem["reason"])
	out["pilot"] = p
	out["ok"] = true
	return out


static func _import_mech(m: Dictionary, db: ContentDB, pilot: Dictionary, warn: Array, hint: String) -> Dictionary:
	var mname := str(m.get("name", "Unnamed mech"))
	var frame_id := str(m.get("frame", ""))
	var frame := db.frame(frame_id)
	if frame.is_empty():
		warn.append("%s: frame %s isn't available%s, so this mech was left out." % [mname, frame_id, hint])
		return {}
	var lo: Dictionary = _pick(m.get("loadouts", []), int(m.get("active_loadout_index", 0)))
	var src_mounts: Array = lo.get("mounts", []).duplicate()
	var mounts: Array = []
	for mount_type: String in frame.get("mounts", []):
		var found := {}
		for i in range(src_mounts.size()):
			if src_mounts[i] is Dictionary and str(src_mounts[i].get("mount_type", "")) == mount_type:
				found = src_mounts[i]
				src_mounts.remove_at(i)
				break
		mounts.append(_import_mount(found, mname, db, warn, hint))
	for leftover: Variant in src_mounts:
		if leftover is Dictionary and not _mount_weapons(leftover).is_empty():
			warn.append("%s: a %s mount doesn't match the frame's mounts; its weapons were left off." % [mname, leftover.get("mount_type", "?")])
	for extra in ["improved_armament", "integratedWeapon", "superheavy_mounting"]:
		var em: Variant = lo.get(extra)
		if em is Dictionary and not _mount_weapons(em).is_empty():
			warn.append("%s: extra mounts from core bonuses (%s) aren't supported yet; that weapon was left off." % [mname, extra.capitalize()])
	for im: Variant in lo.get("integratedMounts", []):
		if im is Dictionary and not _mount_weapons(im).is_empty():
			warn.append("%s: integrated weapons aren't supported yet and were left off." % mname)
	var systems: Array = []
	for s: Variant in lo.get("systems", []):
		var sid := str(s.get("id", "")) if s is Dictionary else str(s)
		if db.system(sid).is_empty():
			warn.append("%s: system %s isn't available%s; left off." % [mname, sid, hint])
		else:
			systems.append(sid)
	var mech := {"id": "mech_" + _uuid().left(8), "name": mname, "frame": frame_id,
		"loadout": {"mounts": mounts, "systems": systems}}
	var check := UnitFactory.check_loadout(db, frame_id, mech["loadout"], pilot)
	if not check.ok:
		for problem: Dictionary in (check.details if not check.details.is_empty() else [{"reason": check.reason}]):
			if not str(problem["reason"]).begins_with("License ranks") and not str(problem["reason"]).begins_with("License Level"):
				warn.append("%s isn't legal for this pilot: %s" % [mname, problem["reason"]])
	return mech


static func _import_mount(mount: Dictionary, mname: String, db: ContentDB, warn: Array, hint: String) -> Dictionary:
	var weapons: Array = []
	var mod := ""
	for w: Dictionary in _mount_weapons(mount):
		var wid := str(w.get("id", ""))
		if db.weapon(wid).is_empty():
			warn.append("%s: weapon %s isn't available%s; left off." % [mname, wid, hint])
			continue
		weapons.append(wid)
		if int(w.get("selectedProfile", 0)) != 0:
			warn.append("%s: %s uses its profile %d; only the first profile is supported yet." % [mname, db.weapon(wid).get("name", wid), int(w["selectedProfile"]) + 1])
		var m: Variant = w.get("mod")
		var mid := str(m.get("id", "")) if m is Dictionary else (str(m) if m is String else "")
		if mid != "":
			if db.get_entry("mods", mid).is_empty():
				warn.append("%s: weapon mod %s isn't available%s; left off." % [mname, mid, hint])
			elif mod == "":
				mod = mid
	return {"weapons": weapons, "mod": mod}


static func _mount_weapons(mount: Dictionary) -> Array:
	var out: Array = []
	for key in ["slots", "extra"]:
		for slot: Variant in mount.get(key, []):
			if slot is Dictionary and slot.get("weapon") is Dictionary:
				out.append(slot["weapon"])
	return out


static func _known(db: ContentDB, collection: String, id: String, what: String, warn: Array, hint: String) -> bool:
	if id != "" and not db.get_entry(collection, id).is_empty():
		return true
	warn.append("Unknown %s \"%s\"%s; left out." % [what, id, hint])
	return false


## " (it may come from: Long Rim)" from the content packs the file says it used.
static func _packs_hint(d: Dictionary) -> String:
	var names := PackedStringArray()
	for b: Variant in d.get("brews", []):
		if b is Dictionary and str(b.get("LcpName", "")) != "" and str(b.get("LcpName", "")) != "Lancer Core Book":
			names.append(str(b["LcpName"]))
	return " (it may come from a content pack: %s)" % ", ".join(names) if not names.is_empty() else ""


static func _pick(list: Variant, index: int) -> Dictionary:
	if list is Array and not list.is_empty():
		var i := clampi(index, 0, list.size() - 1)
		return list[i] if list[i] is Dictionary else {}
	return {}


static func _plain(html: String) -> String:
	return RegEx.create_from_string("<[^>]+>").sub(html.replace("<br>", "\n").replace("</p><p>", "\n"), "", true).strip_edges()


static func _uuid() -> String:
	var h := Crypto.new().generate_random_bytes(16).hex_encode()
	return "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)]


# --- Export -------------------------------------------------------------------------------

## A pilot record as a COMP/CON v2 pilot export (Dictionary; JSON.stringify it to save).
static func export_pilot(p: Dictionary, db: ContentDB) -> Dictionary:
	var mechs: Array = []
	for m: Dictionary in p.get("mechs", []):
		mechs.append(_export_mech(m, p, db))
	var pilot_hp := 6 + UnitFactory.grit(int(p.get("ll", 0)))  # Pilot HP 6 + GRIT (pilot stats).
	var brews: Array = []
	for pack: Dictionary in db.packs:
		brews.append({"LcpId": pack.get("id", ""), "LcpName": pack.get("name", ""), "LcpVersion": pack.get("version", ""),
			"Website": pack.get("website", ""), "Status": "OK"})
	var gear := {"id": _uuid(), "name": "Primary", "armor": [], "weapons": [], "gear": [], "extendedWeapons": [], "extendedGear": []}
	for gid: String in p.get("pilot_gear", []):
		var g := db.get_entry("pilot_gear", gid)
		var slot := "gear"
		if g.get("type", "") == "Armor":
			slot = "armor"
		elif g.get("type", "") == "Weapon":
			slot = "weapons"
		gear[slot].append({"id": gid, "destroyed": false, "uses": 0, "flavorName": "", "flavorDescription": ""})
	var active := str(p.get("active_mech", ""))
	return {
		"id": str(p.get("compcon_id", "")) if str(p.get("compcon_id", "")) != "" else _uuid(),
		"level": int(p.get("ll", 0)), "callsign": str(p.get("callsign", "")), "name": str(p.get("name", "")),
		"player_name": str(p.get("player_name", "")), "status": "Active", "dead": false,
		"text_appearance": "", "notes": str(p.get("notes", "")), "history": str(p.get("history", "")),
		"quirks": [], "current_hp": pilot_hp, "background": str(p.get("background", "")), "resistances": [],
		"mechs": mechs, "special_equipment": {"PilotGear": [], "Frames": [], "MechWeapons": [], "WeaponMods": [], "MechSystems": [], "SystemMods": []},
		"state": {"active_mech_id": _export_id(active, mechs, p), "stage": "Narrative", "turn": 1, "actions": 2},
		"skills": _ranks(p.get("skills", {})), "talents": _ranks(p.get("talents", {})),
		"mechSkills": [int(p.get("hull", 0)), int(p.get("agility", 0)), int(p.get("systems", 0)), int(p.get("engineering", 0))],
		"counter_data": [], "custom_counters": [], "core_bonuses": (p.get("core_bonuses", []) as Array).duplicate(),
		"licenses": _ranks(p.get("licenses", {})), "reserves": _reserves(p.get("reserves", []), db), "orgs": [],
		"loadout": gear, "brews": brews, "portrait": "", "cloud_portrait": "",
	}


static func _export_id(active: String, mechs: Array, p: Dictionary) -> String:
	var ours: Array = p.get("mechs", [])
	for i in range(ours.size()):
		if ours[i].get("id", "") == active:
			return mechs[i]["id"]
	return mechs[0]["id"] if not mechs.is_empty() else ""


static func _ranks(d: Dictionary) -> Array:
	var out: Array = []
	for id: String in d:
		out.append({"id": id, "rank": int(d[id])})
	return out


static func _reserves(ids: Array, db: ContentDB) -> Array:
	var out: Array = []
	for rid: String in ids:
		var r := db.get_entry("reserves", rid)
		out.append({"id": rid, "type": r.get("type", ""), "name": r.get("name", rid), "label": r.get("label", ""),
			"description": r.get("description", ""), "resource_name": "", "resource_note": "", "resource_cost": "", "used": false})
	return out


static func _export_mech(m: Dictionary, p: Dictionary, db: ContentDB) -> Dictionary:
	var frame := db.frame(str(m.get("frame", "")))
	var u := UnitFactory.build_mech(db, "x", str(m.get("frame", "")), m.get("loadout", {}), p)
	var mounts: Array = []
	var given: Array = m.get("loadout", {}).get("mounts", [])
	var frame_mounts: Array = frame.get("mounts", [])
	for i in range(frame_mounts.size()):
		var ours: Dictionary = given[i] if i < given.size() else {}
		mounts.append(_export_mount(str(frame_mounts[i]), ours.get("weapons", []), str(ours.get("mod", "")), db))
	var systems: Array = []
	for sid: String in m.get("loadout", {}).get("systems", []):
		systems.append({"id": sid, "uses": 0, "destroyed": false, "cascading": false, "flavorName": "", "flavorDescription": ""})
	var empty := func(type: String, sizes: Array) -> Dictionary:
		var slots: Array = []
		for s: String in sizes:
			slots.append({"size": s, "weapon": null})
		return {"mount_type": type, "lock": false, "slots": slots, "extra": [], "bonus_effects": [], "modifiable": true}
	return {
		"id": _uuid(), "name": str(m.get("name", "")), "notes": "", "gm_note": "", "frame": str(m.get("frame", "")),
		"active": str(m.get("id", "")) == str(p.get("active_mech", "")),
		"current_structure": u.max_structure, "current_move": u.speed, "boost": 0, "current_hp": u.max_hp,
		"overshield": 0, "current_stress": u.max_stress, "current_heat": 0, "current_repairs": u.repairs,
		"current_overcharge": 0, "current_core_energy": 1, "statuses": [], "conditions": [], "resistances": [],
		"reactions": [], "burn": 0, "destroyed": false, "defeat": "", "activations": 1,
		"meltdown_imminent": false, "reactor_destroyed": false, "core_active": false, "portrait": "", "cloud_portrait": "",
		"loadouts": [{"id": _uuid(), "name": "Primary", "systems": systems, "integratedSystems": [], "mounts": mounts,
			"integratedMounts": [], "improved_armament": empty.call("Flex", ["Flex"]),
			"integratedWeapon": empty.call("Aux", ["Auxiliary"]), "superheavy_mounting": empty.call("Superheavy", ["Superheavy"])}],
		"active_loadout_index": 0, "counter_data": [], "custom_counters": [],
	}


## COMP/CON mount layout: `slots` hold the mount's own sizes; a Flex mount with two Auxiliary
## weapons uses its Flex slot plus one `extra` Auxiliary slot.
static func _export_mount(type: String, weapons: Array, mod: String, db: ContentDB) -> Dictionary:
	var sizes: Array = {"Main": ["Main"], "Heavy": ["Heavy"], "Flex": ["Flex"], "Main/Aux": ["Main", "Auxiliary"],
		"Aux/Aux": ["Auxiliary", "Auxiliary"], "Aux": ["Auxiliary"], "Superheavy": ["Superheavy"]}.get(type, [type])
	var slots: Array = []
	var extra: Array = []
	for i in range(sizes.size()):
		slots.append({"size": sizes[i], "weapon": null})
	for i in range(weapons.size()):
		var wd := {"id": str(weapons[i]), "destroyed": false, "cascading": false, "loaded": true,
			"mod": {"id": mod, "destroyed": false, "cascading": false, "uses": 0, "flavorName": "", "flavorDescription": ""} if mod != "" and i == 0 else null,
			"flavorName": "", "flavorDescription": "", "customDamageType": null, "maxUseOverride": 0, "uses": 0, "selectedProfile": 0}
		if i < slots.size():
			slots[i]["weapon"] = wd
		else:
			extra.append({"size": "Auxiliary", "weapon": wd})
	return {"mount_type": type, "lock": false, "slots": slots, "extra": extra, "bonus_effects": [], "modifiable": true}
