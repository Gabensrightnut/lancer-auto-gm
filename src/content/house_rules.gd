class_name HouseRules
extends RefCounted
## The house rules registry (DESIGN.md "House rules") for the settings page and the flow:
## every optional switch that isn't a book rule, from the two parts of the game that build
## them. The rules engine's (HouseRuleSwitches, data/game/house_rules_engine.json: the Lancer
## Tactics options, combat ideas, community rules) live in state.house_rules during a battle
## and switch with the `set_house_rule` action; the story's (StoryHouseRules,
## data/game/story/house_rules.json: wallet, printers, travel...) switch with the StoryEngine
## `house_rule` action. Both keep the campaign's set in campaign.options["house_rules"].
##
## Each entry: {id, name, description, source ("joe" / "Community" / "Lancer Tactics"),
## source_link, default, system ("rules" / "story")}. Who may switch them: HouseRulesFlow.
## "joe" marks the user's own ideas (the "Joe's Rules" tab; the older "Your idea" counts as
## joe). Every switch is off by default unless the user picked it; the book comes first.

const JOE := "joe"
const SOURCES := [JOE, "Lancer Tactics", "Community"]
const SOURCE_NAMES := {JOE: "Joe's Rules", "Lancer Tactics": "Lancer Tactics options", "Community": "Community house rules"}


## A source as written in the data, with the old "Your idea" read as joe.
static func source_of(raw: String) -> String:
	return JOE if raw in ["", "Your idea", "your idea", JOE] else raw


## What a source's tab is called.
static func source_name(source: String) -> String:
	return str(SOURCE_NAMES.get(source, source))


## The panel's tabs, in order: [{source, name, rules: [entries]}], Joe's Rules first.
static func tabs() -> Array:
	var out: Array = []
	for src: String in sources():
		out.append({"source": src, "name": source_name(src), "rules": all().filter(func(r: Dictionary) -> bool: return str(r["source"]) == src)})
	return out


## Presets for the panel's buttons. "joe": every one of Joe's Rules on (the rest as they
## are); "book": everything off, the core book only. Returns the new full set.
static func preset(kind: String, current: Dictionary) -> Dictionary:
	var out := normalized(current)
	for r: Dictionary in all():
		var id := str(r["id"])
		if kind == "book":
			out[id] = false
		elif kind == "joe" and str(r["source"]) == JOE:
			out[id] = true
	return out


## Every house rule, the rules engine's first.
static func all() -> Array:
	var out: Array = []
	for e: Dictionary in HouseRuleSwitches.catalog():
		out.append({"id": str(e["id"]), "name": str(e.get("name", e["id"])), "description": str(e.get("text", "")), "source": source_of(str(e.get("source", ""))),
			"source_link": str(e.get("source_link", "")), "default": bool(e.get("default", false)), "system": "rules"})
	for r: Dictionary in StoryHouseRules.definitions():
		out.append({"id": str(r["id"]), "name": str(r.get("name", r["id"])), "description": str(r.get("text", "")), "source": source_of(str(r.get("source", JOE))),
			"source_link": "", "default": bool(r.get("default", false)), "system": "story"})
	return out


## The groups on the page: the three known sources first, then any new one a rule brings.
static func sources() -> Array:
	var out: Array = SOURCES.duplicate()
	for r: Dictionary in all():
		if not str(r["source"]) in out:
			out.append(str(r["source"]))
	return out


static func rule(id: String) -> Dictionary:
	for r: Dictionary in all():
		if str(r["id"]) == id:
			return r
	return {}


static func is_battle_rule(id: String) -> bool:
	return not HouseRuleSwitches.entry(id).is_empty()


## id -> on, from each rule's default.
static func defaults() -> Dictionary:
	var out := {}
	for r: Dictionary in all():
		out[str(r["id"])] = bool(r["default"])
	return out


## A full set (every known rule) from a partial one; unknown ids are dropped.
static func normalized(set: Dictionary) -> Dictionary:
	var out := defaults()
	for id: String in set:
		if out.has(id):
			out[id] = bool(set[id])
	return out


## Is house rule `id` on in this battle (rules engine switches)?
static func on(state: GameState, id: String) -> bool:
	return HouseRuleSwitches.on(state, id)


## Is house rule `id` on in this campaign?
static func on_campaign(campaign: Campaign, id: String) -> bool:
	return campaign != null and bool(of_campaign(campaign).get(id, false))


## The campaign's set (every rule).
static func of_campaign(campaign: Campaign) -> Dictionary:
	return normalized(campaign.options.get("house_rules", {}) if campaign != null else {})


## Copies the campaign's whole set into a battle state when it starts (no announcement:
## nothing changed mid-fight). Returns the ids that differ from what the state had.
static func put(state: GameState, set: Dictionary) -> Array:
	var changed: Array = []
	var full := normalized(set)
	for id: String in full:
		if bool(state.house_rules.get(id, rule(id).get("default", false))) != bool(full[id]):
			changed.append(id)
		state.house_rules[id] = full[id]
	return changed


## One line for the lobby: "Book only" when no house rule is on, else what's on by source,
## e.g. "House rules on: Joe's Rules (3), Lancer Tactics (2)".
static func summary(set: Dictionary) -> String:
	var full := normalized(set)
	var by_source := {}
	for id: String in full:
		if bool(full[id]):
			var src := str(rule(id).get("source", ""))
			by_source[src] = int(by_source.get(src, 0)) + 1
	if by_source.is_empty():
		return "Book only"
	var parts := PackedStringArray()
	for src: String in sources():
		if by_source.has(src):
			parts.append("%s (%d)" % [src, by_source[src]])
	return "House rules on: " + ", ".join(parts)


## What a switch says in the log.
static func announce(id: String, is_on: bool) -> String:
	var r := rule(id)
	return "House rule %s: %s (%s, not a book rule)." % ["on" if is_on else "off", str(r.get("name", id)), source_name(str(r.get("source", "")))]
