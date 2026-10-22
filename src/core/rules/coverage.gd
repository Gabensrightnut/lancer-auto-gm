class_name Coverage
extends RefCounted
## How much of the core book (data/lancer-data) the engine handles, item by item. Frames,
## systems, weapons and talent ranks use the engine's own automation report (Automation:
## automated / partial / manual); core bonuses, weapon mods and pilot gear count as handled
## when the engine's data or rules code refers to them. NPCs: the free core book has no NPC data,
## so it counts the placeholder NPC pack's features that have encoded effects.
## tools/coverage_audit.gd writes docs/COVERAGE.md; tests/unit/test_rules_coverage.gd fails if
## the handled counts drop below data/game/coverage_floor.json.

const FRAME := "mf_standard_pattern_i_everest"
const SOURCES := ["res://src/core/rules", "res://src/core/rules/handlers", "res://src/content"]
const DATA := ["res://data/game/gear_effects.json", "res://data/game/activation_effects.json", "res://data/game/weapon_effects.json",
	"res://data/game/frame_effects.json", "res://data/game/automation_notes.json"]


## {kind: {"total", "automated", "partial", "manual", "gaps": [{id, name, status, note}]}}
static func audit(db: ContentDB) -> Dictionary:
	var out := {}
	var pilot := {"ll": 12, "talents": {}}
	# Frames: traits and core systems.
	var frames := _bucket()
	for f: Dictionary in db.all("frames"):
		var u := UnitFactory.build_mech(db, "c", String(f["id"]), {"mounts": [], "systems": []}, pilot)
		if u == null:
			continue
		for e: Dictionary in Automation.for_unit(db, u):
			if e["kind"] in ["trait", "core"]:
				_add(frames, "%s: %s" % [f.get("name", f["id"]), e["name"]], e)
	out["frame traits and core systems"] = frames
	# Systems, one at a time on a bare Everest.
	var systems := _bucket()
	for s: Dictionary in db.all("systems"):
		var u := UnitFactory.build_mech(db, "c", FRAME, {"mounts": [], "systems": [String(s["id"])]}, pilot)
		for e: Dictionary in Automation.for_unit(db, u):
			if e["kind"] == "system":
				_add(systems, String(s.get("name", s["id"])), e)
	out["mech systems"] = systems
	# Weapons, each on the Everest's Heavy mount.
	var weapons := _bucket()
	for w: Dictionary in db.all("weapons"):
		var u := UnitFactory.build_mech(db, "c", FRAME, {"mounts": [{"weapons": []}, {"weapons": []}, {"weapons": [String(w["id"])]}], "systems": []}, pilot)
		for e: Dictionary in Automation.for_unit(db, u):
			if e["kind"] == "weapon" and e["id"] == w["id"]:
				_add(weapons, String(w.get("name", w["id"])), e)
	out["weapons"] = weapons
	# Talents, every rank.
	var talents := _bucket()
	for t: Dictionary in db.all("talents"):
		for e: Dictionary in Automation.for_talents(db, {String(t["id"]): (t.get("ranks", []) as Array).size()}):
			_add(talents, String(e["name"]), e)
	out["talent ranks"] = talents
	# Referenced by id in the engine's data or rules code.
	var text := _engine_text()
	for pair: Array in [["core bonuses", "core_bonuses"], ["weapon mods", "mods"], ["pilot gear", "pilot_gear"]]:
		var b := _bucket()
		for x: Dictionary in db.all(String(pair[1])):
			var generic: bool = pair[1] == "mods" and (x.has("added_tags") or x.has("added_range") or x.has("added_damage"))  # applied from the data
			var status := "automated" if generic or text.contains("\"%s\"" % x["id"]) or text.contains(String(x["id"]) + ":") else "manual"
			_add(b, String(x.get("name", x["id"])), {"id": x["id"], "status": status, "note": ""})
		out[pair[0]] = b
	# NPC features (placeholder pack until an NPC pack is loaded).
	var npc := _bucket()
	var enc := NPCBuilder.feature_effects()
	for f: Dictionary in NPCBuilder.placeholder_pack().get("npc_features", []):
		var plain := String(f.get("type", "")) in ["Weapon", "Tech"] or not (f.get("bonus", {}) as Dictionary).is_empty()
		_add(npc, String(f.get("name", f["id"])), {"id": f["id"], "status": "automated" if plain or enc.has(f["id"]) else "manual", "note": ""})
	out["NPC features (placeholder pack)"] = npc
	return out


static func _bucket() -> Dictionary:
	return {"total": 0, "automated": 0, "partial": 0, "manual": 0, "gaps": []}


static func _add(b: Dictionary, name: String, e: Dictionary) -> void:
	var status := String(e.get("status", "manual"))
	b["total"] = int(b["total"]) + 1
	b[status] = int(b.get(status, 0)) + 1
	if status != "automated":
		(b["gaps"] as Array).append({"id": String(e.get("id", "")), "name": name, "status": status, "note": String(e.get("note", ""))})


static func _engine_text() -> String:
	var parts: PackedStringArray = []
	for p in DATA:
		parts.append(FileAccess.get_file_as_string(p))
	for dir_path in SOURCES:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for f in dir.get_files():
			if f.ends_with(".gd"):
				parts.append(FileAccess.get_file_as_string(dir_path + "/" + f))
	return "\n".join(parts)


## The report as Markdown, for docs/COVERAGE.md.
static func markdown(report: Dictionary) -> String:
	var lines: PackedStringArray = ["# Core-book coverage", "",
		"What the rules engine handles from the core book (data/lancer-data). Made by",
		"`tools/coverage_audit.gd` (see `src/core/rules/coverage.gd` for how each kind is counted);",
		"`tests/unit/test_rules_coverage.gd` fails if a count drops below `data/game/coverage_floor.json`.",
		"Partial = automated with a note for the table; manual = the table resolves it.", "",
		"| Kind | Total | Automated | Partial | Manual |", "|---|---|---|---|---|"]
	for k: String in report:
		var b: Dictionary = report[k]
		lines.append("| %s | %d | %d | %d | %d |" % [k, b["total"], b["automated"], b["partial"], b["manual"]])
	lines.append("")
	lines.append("## Gaps")
	for k: String in report:
		var gaps: Array = report[k]["gaps"]
		if gaps.is_empty():
			continue
		lines.append("")
		lines.append("### " + k)
		lines.append("")
		for g: Dictionary in gaps:
			var note := (": " + String(g["note"])) if String(g["note"]) != "" else ""
			lines.append("- %s (%s)%s" % [g["name"], g["status"], note])
	return "\n".join(lines) + "\n"
