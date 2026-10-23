class_name Soldiers
extends RefCounted
## Soldiers in the living world (data/game/story/soldiers.json): every hub has a garrison that
## keeps order: guards on the office door by day, a night watch, patrols that do their rounds
## (landing pads, the market, the bar, the square at night). They're ordinary TownLife people
## (role "soldier", their own schedule, talkable through the "soldier" scene) and witnesses:
## a soldier who sees a crime raises the alarm (town_life.json witness.guards). If it comes to
## a fight, the garrison's squads join the other side (hook["soldiers"], added as enemy units by
## CampaignLoop when the rules session's soldier squad template exists).
## A campaign world sets its own garrison (worlds.<id>.garrison: {faction, titles, ...}).

const FILE := "res://data/game/story/soldiers.json"
const ROLE := "soldier"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {}
	return _data


static func garrison_def(hub: Dictionary) -> Dictionary:
	if hub.get("garrison_def") is Dictionary:
		return hub["garrison_def"]
	var g: Dictionary = data().get("garrisons", {})
	return g.get(str(hub.get("culture", "")), g.get("default", {}))


## Posts the garrison in a new hub (NpcGen.make_hub).
static func post(story: StoryState, campaign: Campaign, hub: Dictionary, rng: RandomNumberGenerator, names: NameGen) -> void:
	var g := garrison_def(hub)
	if g.is_empty():
		return
	hub["garrison"] = {"faction": str(g.get("faction", "the town watch")), "squads": int(g.get("squads", 1))}
	var n := 0
	for duty: String in ["guards", "watch", "patrols"]:
		for i in range(int(g.get(duty, 0))):
			var id := "%s_soldier%d" % [hub["id"], n]
			n += 1
			var npc := NpcGen.make_npc(rng, names, campaign, hub, ROLE, id)
			_dress(npc, g, duty, n)
			story.npcs[id] = npc
			(hub["npcs"] as Array).append(id)


static func _dress(npc: Dictionary, g: Dictionary, duty: String, n: int) -> void:
	var titles: Array = g.get("titles", ["Guard"])
	var key := {"guards": "guard", "watch": "watch", "patrols": "patrol"}[duty] as String
	npc["title"] = str(titles[(n - 1) % titles.size()]) if key != "watch" else str(titles[titles.size() - 1])
	npc["faction"] = str(g.get("faction", "the town watch"))
	npc["duty"] = key
	npc["schedule"] = (data().get("schedules", {}).get(key, {}) as Dictionary).duplicate(true)
	npc["spot"] = str(npc["schedule"].get("day", ["office"])[0])


## A campaign world's own garrison (CampaignScript.populate): the same soldiers, its colours.
static func restyle(story: StoryState, g: Dictionary) -> void:
	story.hub["garrison_def"] = g.duplicate(true)
	story.hub["garrison"] = {"faction": str(g.get("faction", "")), "squads": int(g.get("squads", 1))}
	var n := 0
	for id: String in story.hub.get("npcs", []):
		var npc: Dictionary = story.npcs.get(id, {})
		if str(npc.get("role", "")) != ROLE:
			continue
		n += 1
		var duty := str(npc.get("duty", "guard"))
		_dress(npc, g, {"guard": "guards", "watch": "watch", "patrol": "patrols"}[duty], n)


static func garrison(story: StoryState) -> Dictionary:
	return story.hub.get("garrison", {})


## A fight that comes out of a crime here: the garrison turns out (hook["soldiers"]).
static func turn_out(story: StoryState, hook: Dictionary) -> void:
	var g := garrison(story)
	if g.is_empty():
		return
	hook["soldiers"] = {"faction": str(g["faction"]), "squads": int(g.get("squads", 1)), "template": str(data().get("unit_template", ""))}
	if str(hook.get("enemy", "")) == "" or bool(hook.get("from_scene", false)):
		hook["enemy"] = str(g["faction"])
