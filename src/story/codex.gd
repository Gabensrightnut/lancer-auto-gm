class_name Codex
extends RefCounted
## The in-game rules reference (DESIGN.md section 8: "A searchable in-game rules reference
## answers questions any time"). Everything comes from Massif's lancer-data text: rule terms
## (glossary), statuses and conditions, actions, weapon and system tags, frames,
## manufacturers, skill triggers, backgrounds, downtime actions, reserves, pilot gear and
## talents, plus a few entries for this game's own story features (marked as not book rules).

const DIR := "res://data/lancer-data/"
const OWN := "res://data/game/story/codex_own.json"

static var _entries: Array = []


## [{id, category, title, text, source}] (built once).
static func entries() -> Array:
	if not _entries.is_empty():
		return _entries
	var out: Array = []
	for g: Dictionary in _load("glossary"):
		out.append(_e("rule:" + str(g["name"]), "Rules", str(g["name"]), str(g.get("description", "")), "Core rules (glossary)"))
	for s: Dictionary in _load("statuses"):
		var kind := str(s.get("type", "Status"))
		out.append(_e(str(s.get("id", s["name"])), "Statuses and conditions", str(s["name"]), "%s\n\n%s" % [s.get("terse", ""), s.get("effects", "")], kind))
	for a: Dictionary in _load("actions"):
		out.append(_e(str(a["id"]), "Actions", str(a["name"]), "%s action. %s\n\n%s" % [a.get("activation", ""), a.get("terse", ""), a.get("detail", "")], "Actions"))
	for t: Dictionary in _load("tags"):
		if bool(t.get("hidden", false)):
			continue
		out.append(_e(str(t["id"]), "Tags", str(t["name"]).replace(" {VAL}", " X"), str(t.get("description", "")).replace("{VAL}", "X"), "Tags"))
	var makers := {}
	for m: Dictionary in _load("manufacturers"):
		makers[str(m["id"])] = str(m["name"])
		out.append(_e(str(m["id"]), "Manufacturers", str(m["name"]).capitalize(), "%s\n\n%s" % [m.get("quote", ""), m.get("description", "")], "Manufacturers"))
	for f: Dictionary in _load("frames"):
		out.append(_e(str(f["id"]), "Frames", "%s %s" % [makers.get(str(f.get("source", "")), str(f.get("source", ""))).capitalize(), f["name"]], _frame_text(f), str(f.get("source", ""))))
	for s: Dictionary in _load("skills"):
		out.append(_e(str(s["id"]), "Skill triggers", str(s["name"]), "%s\n\n%s" % [s.get("description", ""), s.get("detail", "")], "Skill triggers"))
	for b: Dictionary in _load("backgrounds"):
		out.append(_e(str(b["id"]), "Backgrounds", str(b["name"]), str(b.get("description", "")), "Backgrounds"))
	for d: Dictionary in _load("downtime_actions"):
		out.append(_e(str(d["id"]), "Downtime actions", str(d["name"]), "%s\n\n%s\n\n%s" % [d.get("terse", ""), d.get("detail", ""), _table_text(d.get("table", {}))], "Downtime"))
	for r: Dictionary in _load("reserves"):
		out.append(_e(str(r["id"]), "Reserves", str(r["name"]), "%s reserve. %s" % [r.get("type", ""), r.get("description", "")], "Reserves"))
	for g: Dictionary in _load("pilot_gear"):
		out.append(_e(str(g["id"]), "Pilot gear", str(g["name"]), "%s. %s\n\n%s" % [g.get("type", ""), g.get("effect", ""), g.get("description", "")], "Pilot gear"))
	for t: Dictionary in _load("talents"):
		var ranks := PackedStringArray()
		for r: Dictionary in t.get("ranks", []):
			ranks.append("%s: %s" % [r.get("name", ""), r.get("description", "")])
		out.append(_e(str(t["id"]), "Talents", str(t["name"]), "%s\n\n%s" % [t.get("terse", t.get("description", "")), "\n\n".join(ranks)], "Talents"))
	var own: Variant = JSON.parse_string(FileAccess.get_file_as_string(OWN)) if FileAccess.file_exists(OWN) else null
	for o: Dictionary in (own.get("entries", []) if own is Dictionary else []):
		out.append(_e("game:" + str(o["title"]), "This game", str(o["title"]), str(o["text"]), "Game feature (not a book rule)"))
	_entries = out
	return out


static func categories() -> Array:
	var seen: Array = []
	for e: Dictionary in entries():
		if not seen.has(e["category"]):
			seen.append(e["category"])
	return seen


## Entries matching every word of `query` (in the title or text), best first: exact title,
## then title starts with it, then title contains it, then text. `category` "" = all.
static func search(query: String, category: String = "", limit: int = 60) -> Array:
	var q := query.strip_edges().to_lower()
	var words := q.split(" ", false)
	var scored: Array = []
	for e: Dictionary in entries():
		if category != "" and e["category"] != category:
			continue
		var title := str(e["title"]).to_lower()
		var body := str(e["text"]).to_lower()
		if q == "":
			scored.append([3, e])
			continue
		var all_in := true
		for w in words:
			if not (w in title or w in body):
				all_in = false
				break
		if not all_in:
			continue
		var score := 3
		if title == q:
			score = 0
		elif title.begins_with(q):
			score = 1
		elif q in title:
			score = 2
		scored.append([score, e])
	scored.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] < b[0] or (a[0] == b[0] and str(a[1]["title"]) < str(b[1]["title"])))
	return scored.slice(0, limit).map(func(x: Array) -> Dictionary: return x[1])


static func find(title: String) -> Dictionary:
	var r := search(title, "", 1)
	return r[0] if not r.is_empty() else {}


static func _e(id: String, cat: String, title: String, text: String, source: String) -> Dictionary:
	return {"id": id, "category": cat, "title": title, "text": StoryText.plain(text), "source": source}


static func _frame_text(f: Dictionary) -> String:
	var st: Dictionary = f.get("stats", {})
	var lines := PackedStringArray()
	lines.append("Role: %s. Size %s." % [", ".join(PackedStringArray(f.get("mechtype", []))), str(st.get("size", 1))])
	lines.append("HP %s, Evasion %s, E-Defense %s, Armor %s, Heat Cap %s, Speed %s, Sensors %s, Repair Cap %s, Save %s, Tech Attack %+d, SP %s." % [
		st.get("hp", "?"), st.get("evasion", "?"), st.get("edef", "?"), st.get("armor", "?"), st.get("heatcap", "?"), st.get("speed", "?"),
		st.get("sensor_range", "?"), st.get("repcap", "?"), st.get("save", "?"), int(st.get("tech_attack", 0)), st.get("sp", "?")])
	var traits := PackedStringArray()
	for t: Dictionary in f.get("traits", []):
		traits.append("%s: %s" % [t.get("name", ""), t.get("description", "")])
	if not traits.is_empty():
		lines.append("Traits. " + " ".join(traits))
	var core: Dictionary = f.get("core_system", {})
	if not core.is_empty():
		lines.append("Core system: %s. Core power: %s. %s" % [core.get("name", ""), core.get("active_name", ""), core.get("active_effect", core.get("description", ""))])
	lines.append(str(f.get("description", "")))
	return "\n\n".join(lines)


static func _table_text(t: Dictionary) -> String:
	var out := PackedStringArray()
	for r: Dictionary in t.get("results", []):
		out.append("%s: %s" % [("%d-%d" % [int(r["min"]), int(r["max"])]) if int(r["min"]) != int(r["max"]) else str(r["min"]), r.get("text", "")])
	return "\n".join(out)


static func _load(name: String) -> Array:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + name + ".json"))
	return d if d is Array else []
