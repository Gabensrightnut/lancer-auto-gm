class_name CharacterSanity
extends RefCounted
## The sanity check for characters (DESIGN.md section 7, the game's sanity checker applied to
## characters): a saved, imported, online or bot character is rebuilt from the book for this
## campaign, never trusted. A fresh pilot at the campaign's starting License Level gets the
## character's identity, then each of its build choices goes through the builder's own legality
## checks (BuilderModel: stats, skills, talents, licenses, core bonuses, frame, mounts, gear).
## Whatever isn't legal here is left out, with the reason and the rule, like a refused action.
## Numbers in the file (HP, money, manna, XP, License Level, reserves, implants, bounties) are
## never read: they come from the campaign and the book.
##
##   var r := CharacterSanity.rebuild(db, campaign, saved)
##   r["pilot"]   a legal pilot record for this campaign
##   r["report"]  [{what, why, rule_ref}] ("Removed: Talent X rank 3": "needs LL2")
##   r["passed"]  true when nothing had to change

const REF := BuilderModel.REF


static func rebuild(db: ContentDB, campaign: Campaign, saved: Dictionary) -> Dictionary:
	var c := CharacterRoster.clean(saved)
	var report: Array = []
	if c.is_empty():
		return {"pilot": {}, "report": [{"what": "Not a character file", "why": "It has no name or isn't in the character format.", "rule_ref": ""}], "passed": false}
	var id: Dictionary = c["identity"]
	var pilot := campaign.new_pilot(str(id.get("name", "Pilot")), str(id.get("callsign", "")))
	campaign.pilots.erase(pilot["id"])  # only a record here; the lobby seats it
	for k: String in CharacterRoster.IDENTITY:
		if id.has(k) and k != "name" and k != "callsign":
			pilot[k] = id[k]
	if id.has("bio"):
		pilot["notes"] = str(id["bio"]).left(2000)
	var b := BuilderModel.new(db, pilot)
	var build: Dictionary = c.get("build", {})
	var try := func(what: String, why: String) -> void:
		if why != "":
			report.append({"what": "Removed: " + what, "why": why, "rule_ref": REF})
	for key: String in ["hull", "agility", "systems", "engineering"]:
		var v := int(build.get("hase", {}).get(key, 0))
		if v > 0:
			try.call("%s %d" % [key.capitalize(), v], b.set_hase(key, v))
	for skill: String in build.get("skills", {}):
		try.call("Skill %s rank %d" % [_name(db, "skills", skill), int(build["skills"][skill])], b.set_skill(skill, int(build["skills"][skill])))
	for lic: String in build.get("licenses", {}):
		try.call("License %s rank %d" % [_name(db, "frames", lic), int(build["licenses"][lic])], b.set_license(lic, int(build["licenses"][lic])))
	for t: String in build.get("talents", {}):
		try.call("Talent %s rank %d" % [_name(db, "talents", t), int(build["talents"][t])], b.set_talent(t, int(build["talents"][t])))
	for cb: Variant in build.get("core_bonuses", []):
		try.call("Core bonus %s" % _name(db, "core_bonuses", str(cb)), b.toggle_core_bonus(str(cb)))
	var mech: Dictionary = build.get("mech", {}) if build.get("mech") is Dictionary else {}
	if str(mech.get("frame", "")) != "" and str(mech["frame"]) != str(b.mech().get("frame", "")):
		var why := b.set_frame(str(mech["frame"]))
		try.call("Frame %s" % _name(db, "frames", str(mech["frame"])), why)
	var lo: Dictionary = mech.get("loadout", {}) if mech.get("loadout") is Dictionary else {}
	if not lo.is_empty() and str(mech.get("frame", b.mech().get("frame", ""))) == str(b.mech().get("frame", "")):
		var mounts: Array = lo.get("mounts", [])
		for m in range(mounts.size()):
			var ws: Array = (mounts[m] as Dictionary).get("weapons", []) if mounts[m] is Dictionary else []
			for slot in range(ws.size()):
				try.call("Weapon %s" % _name(db, "weapons", str(ws[slot])), b.set_weapon(m, slot, str(ws[slot])))
		for s: Variant in lo.get("systems", []):
			try.call("System %s" % _name(db, "systems", str(s)), b.add_system(str(s)))
	if mech.has("name"):
		b.set_mech_name(str(mech["name"]).left(48))
	if mech.get("paint") is Dictionary:
		b.mech()["paint"] = (mech["paint"] as Dictionary).duplicate(true)
	for p: String in b.problems():
		report.append({"what": "Changed", "why": p, "rule_ref": REF})
	return {"pilot": b.pilot, "report": report, "passed": report.is_empty() and b.is_legal()}


static func _name(db: ContentDB, kind: String, id: String) -> String:
	var e := db.get_entry(kind, id) if db != null else {}
	return str(e.get("name", id)) if not e.is_empty() else id


## One line per change for the slot's "Sanity check" panel.
static func describe(report: Array) -> String:
	if report.is_empty():
		return "Passed sanity check."
	return "\n".join(PackedStringArray(report.map(func(r: Dictionary) -> String: return "%s: %s (%s)" % [r["what"], r["why"], r["rule_ref"]])))


## A short fingerprint of a validated build, for the match record (online seating).
static func build_hash(pilot: Dictionary) -> String:
	var keep: Dictionary = CharacterRoster.from_pilot(pilot)["build"]
	return JSON.stringify(keep, "", true).sha256_text().left(16)
