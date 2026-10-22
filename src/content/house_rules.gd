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
## Each entry: {id, name, description, source ("Your idea" / "Community" / "Lancer Tactics"),
## source_link, default, system ("rules" / "story")}. Who may switch them: HouseRulesFlow.

const SOURCES := ["Lancer Tactics", "Your idea", "Community"]


## Every house rule, the rules engine's first.
static func all() -> Array:
	var out: Array = []
	for e: Dictionary in HouseRuleSwitches.catalog():
		out.append({"id": str(e["id"]), "name": str(e.get("name", e["id"])), "description": str(e.get("text", "")), "source": str(e.get("source", "")),
			"source_link": str(e.get("source_link", "")), "default": bool(e.get("default", false)), "system": "rules"})
	for r: Dictionary in StoryHouseRules.definitions():
		out.append({"id": str(r["id"]), "name": str(r.get("name", r["id"])), "description": str(r.get("text", "")), "source": str(r.get("source", "Your idea")),
			"source_link": "", "default": bool(r.get("default", false)), "system": "story"})
	return out


static func sources() -> Array:
	return SOURCES


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


## What a switch says in the log.
static func announce(id: String, is_on: bool) -> String:
	var r := rule(id)
	return "House rule %s: %s (%s, not a book rule)." % ["on" if is_on else "off", str(r.get("name", id)), str(r.get("source", ""))]
