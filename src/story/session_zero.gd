class_name SessionZero
extends RefCounted
## The first-session setup (Core p.40-41): who the squad is, who gives it orders, and some
## history between the pilots (made from their backgrounds and origins, squad_history; the
## question game is an optional extra), plus the table's tone, focus and content choices
## (data/game/story/session_zero.json). It only steers our own story generators and sets
## starting bonds; no rule changes. Applied with the "session_zero" StoryEngine action before
## the first mission.

const FILE := "res://data/game/story/session_zero.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {}
	return _data


## A random pick from a list, the way the book offers a d20 roll for each question.
static func roll(dice: Dice, list_key: String) -> Variant:
	var list: Array = data().get(list_key, [])
	return list[dice.die(list.size()) - 1] if not list.is_empty() else null


## Why these choices can't be applied ("" if they can).
static func refusal(story: StoryState, campaign: Campaign, choices: Dictionary) -> String:
	if not campaign.history.is_empty() or story.mission_number > 1:
		return "Session zero happens before the first mission."
	var d := data()
	if choices.has("tone") and not d.get("tones", {}).has(str(choices["tone"])):
		return "Unknown tone."
	if choices.has("focus") and not d.get("focus", {}).has(str(choices["focus"])):
		return "Unknown focus."
	for c: Variant in choices.get("content_off", []):
		if not d.get("content", {}).has(str(c)):
			return "Unknown content toggle %s." % c
	for h: Dictionary in choices.get("history", []):
		if not campaign.pilots.has(str(h.get("a", ""))) or not campaign.pilots.has(str(h.get("b", ""))) or h.get("a") == h.get("b"):
			return "Each history answer links two different pilots."
	return ""


static func apply(story: StoryState, campaign: Campaign, choices: Dictionary) -> Array:
	var d := data()
	var events: Array = []
	var identity := str(choices.get("identity", ""))
	var patron_id := str(choices.get("patron", ""))
	var patron: Dictionary = {}
	for p: Dictionary in d.get("patrons", []):
		if str(p["id"]) == patron_id:
			patron = p
	campaign.options["identity"] = identity
	campaign.options["patron"] = patron_id
	campaign.options["patron_roles"] = patron.get("roles", [])
	campaign.options["tone"] = str(choices.get("tone", "heroic"))
	campaign.options["focus"] = str(choices.get("focus", "balanced"))
	var focus: Dictionary = d.get("focus", {}).get(campaign.options["focus"], {})
	campaign.options["long_downtime"] = bool(focus.get("long_downtime", false))
	campaign.options["banter_lines"] = int(focus.get("banter", 2))
	campaign.options["content_off"] = (choices.get("content_off", []) as Array).duplicate()
	story.flags["_identity"] = identity
	for h: Dictionary in choices.get("history", []):
		var q: Dictionary = {}
		for x: Dictionary in d.get("history", []):
			if str(x["id"]) == str(h.get("question", "")):
				q = x
		var a := str(h["a"])
		var b := str(h["b"])
		var amount := int(q.get("bond", 1))
		var text := "%s asked: \"%s\" %s answered." % [campaign.pilots[a].get("callsign", ""), q.get("text", ""), campaign.pilots[b].get("callsign", "")]
		story.add_log(text)
		events.append({"type": "history_set", "a": a, "b": b, "question": q.get("id", ""), "text": text})
		if amount != 0:
			events.append_array(Bonds.add(story, campaign, a, b, amount, "their shared history"))
	# The shared history made from the pilots (as edited): story flavour, a small start to the bond.
	for h: Dictionary in choices.get("squad_history", []):
		var a2 := str(h.get("a", ""))
		var b2 := str(h.get("b", ""))
		var text2 := str(h.get("text", "")).strip_edges()
		if text2 == "" or not campaign.pilots.has(a2) or not campaign.pilots.has(b2) or a2 == b2:
			continue
		story.add_log(text2)
		events.append({"type": "history_set", "a": a2, "b": b2, "text": text2})
		events.append_array(Bonds.add(story, campaign, a2, b2, 1, "their shared history"))
	events.append({"type": "session_zero", "identity": identity, "patron": patron.get("text", ""), "tone": campaign.options["tone"],
		"focus": campaign.options["focus"], "content_off": campaign.options["content_off"], "rule_ref": "Core p.40-41: the first session"})
	return events


## The squad's shared history, made from what the players already chose for their pilots:
## for each pair, what they have in common (the same homeworld, background, former employer,
## upbringing or specialty), else how they met. Every pilot is in at least one line. `variant`
## rerolls the wording and the links. Returns [{a, b, kind, text}].
static func squad_history(story: StoryState, campaign: Campaign, variant: int = 0) -> Array:
	var d: Dictionary = data().get("squad_history", {})
	var ids: Array = campaign.pilots.keys().filter(func(p: String) -> bool: return story.is_alive(p))
	ids.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([campaign.id, variant, "squad_history"])
	var out: Array = []
	var named := {}
	var pairs: Array = []
	for i in range(ids.size()):
		for j in range(i + 1, ids.size()):
			pairs.append([ids[i], ids[j]])
	# Shuffle so a reroll links different pairs first.
	for i in range(pairs.size() - 1, 0, -1):
		var k := rng.randi_range(0, i)
		var tmp: Variant = pairs[i]
		pairs[i] = pairs[k]
		pairs[k] = tmp
	for pr: Array in pairs:
		var link := _common(campaign.pilots[pr[0]], campaign.pilots[pr[1]])
		if link.is_empty() or out.size() >= ids.size() + 1:
			continue
		out.append(_line(d, campaign, pr[0], pr[1], link, rng))
		named[pr[0]] = true
		named[pr[1]] = true
	# Everyone in at least one line: the rest met somewhere along the way.
	for p: String in ids:
		if named.has(p) or ids.size() < 2:
			continue
		var others: Array = ids.filter(func(o: String) -> bool: return o != p)
		var o := str(others[rng.randi_range(0, others.size() - 1)])
		out.append(_line(d, campaign, p, o, {"kind": "none", "what": ""}, rng))
		named[p] = true
		named[o] = true
	return out


static func _common(a: Dictionary, b: Dictionary) -> Dictionary:
	var oa: Dictionary = a.get("origin", {})
	var ob: Dictionary = b.get("origin", {})
	for k: String in ["homeworld", "background", "employer", "upbringing", "specialty"]:
		if k == "background":
			if str(a.get("background", "")) != "" and a.get("background") == b.get("background"):
				return {"kind": k, "what": NarrativeCheck.background_name(a).to_lower()}
			continue
		var v := str(oa.get(k, ""))
		if v == "" or v == "none" or v != str(ob.get(k, "")):
			continue
		var e := Origin._entry(k, v)
		return {"kind": k, "what": str(e.get("name", v))}
	return {}


static func _line(d: Dictionary, campaign: Campaign, a: String, b: String, link: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var lines: Array = d.get(str(link["kind"]), d.get("none", ["{a} and {b} fly together."]))
	var t := str(lines[rng.randi_range(0, lines.size() - 1)])
	t = t.replace("{a}", str(campaign.pilots[a].get("callsign", ""))).replace("{b}", str(campaign.pilots[b].get("callsign", ""))).replace("{what}", str(link["what"]))
	return {"a": a, "b": b, "kind": link["kind"], "text": t}


## Content the table switched off: is this twist / arc allowed?
static func allowed(campaign: Campaign, kind: String, id: String) -> bool:
	if campaign == null:
		return true
	var tag := str(data().get("content_tags", {}).get(kind, {}).get(id, ""))
	return tag == "" or not (campaign.options.get("content_off", []) as Array).has(tag)


## The tone's multiplier for an arc's weight, and for the chance of a twist.
static func arc_weight(campaign: Campaign, arc_id: String) -> float:
	if campaign == null:
		return 1.0
	return float(data().get("tones", {}).get(str(campaign.options.get("tone", "")), {}).get("arcs", {}).get(arc_id, 1.0))


static func twist_factor(campaign: Campaign) -> float:
	if campaign == null:
		return 1.0
	return float(data().get("tones", {}).get(str(campaign.options.get("tone", "")), {}).get("twist", 1.0))
