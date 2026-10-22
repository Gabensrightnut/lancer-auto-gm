class_name SessionZero
extends RefCounted
## The first-session setup (Core p.40-41): who the squad is, who gives it orders, and some
## history between the pilots, plus the table's tone, focus and content choices
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
	events.append({"type": "session_zero", "identity": identity, "patron": patron.get("text", ""), "tone": campaign.options["tone"],
		"focus": campaign.options["focus"], "content_off": campaign.options["content_off"], "rule_ref": "Core p.40-41: the first session"})
	return events


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
