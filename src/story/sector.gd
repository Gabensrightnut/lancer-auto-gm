class_name Sector
extends RefCounted
## The part of space the squad works in (data/game/story/sector.json): a few systems joined by
## blink gates (Core p.10: fast and safe), each with a few worlds, moons or stations. Every
## world has its own culture kit and landscape (cultures.json) and one hub, generated the
## first time the squad goes there and kept afterwards: its people, its job board and its
## situation (arc) are waiting when the squad comes back. The squad's current world is
## where the hub is.
##
## Travel is narrative: the StoryEngine "travel" action, between missions, with no costs or
## travel time (CANON.md parks paid travel). Kept in story.flags["_sector"] and ["_hubs"].

const FILE := "res://data/game/story/sector.json"
const KEY := "_sector"
const HUBS := "_hubs"
const REF := "Core p.10: blink gates let ships travel between systems with speed and safety"

## Sol's worlds belong to Cradle, Union's home system (Core p.10); a frontier sector doesn't
## reuse them (COMP/CON's planet list includes them).
const SOL := ["cradle", "earth", "luna", "mars", "mercury", "venus", "jupiter", "saturn", "neptune", "uranus", "pluto",
	"phobos", "deimos", "io", "europa", "ganymede", "callisto", "titan", "enceladus", "sol"]

static var _data: Dictionary = {}


## A planet name that isn't Sol's and isn't taken. COMP/CON's list is short, so once it runs
## out a world is named after its star with a numeral, the way planets are ("Hercynia III").
static func fresh_name(names: NameGen, used: Dictionary, star: String = "") -> String:
	var n := names.planet().strip_edges()
	for i in range(40):
		if not used.has(n.to_lower()) and not SOL.has(n.to_lower()):
			used[n.to_lower()] = true
			return n
		n = names.planet().strip_edges()
	var base := star if star != "" else n
	for numeral: String in ["II", "III", "IV", "V", "VI", "VII", "VIII", "IX"]:
		var m := "%s %s" % [base, numeral]
		if not used.has(m.to_lower()):
			used[m.to_lower()] = true
			return m
	return n


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {}
	return _data


static func get_sector(story: StoryState) -> Dictionary:
	return story.flags.get(KEY, {})


## Makes the sector around the current hub the first time it's needed. The current hub's
## world is the first world of the first system.
static func ensure(story: StoryState, campaign: Campaign) -> Dictionary:
	var sec := get_sector(story)
	if not sec.is_empty() or story.hub.is_empty():
		return sec
	var d := data()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([story.story_seed, "sector"])
	var names := NameGen.new(rng)
	var kits := NpcGen.cultures()
	var kinds: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/game/story/cultures.json")) as Dictionary).get("kinds", {})
	var stars: Array = d.get("stars", ["a star"])
	var counts: Array = d.get("worlds", [2, 3])
	var systems: Array = []
	var worlds: Array = []
	var used := {str(story.hub.get("planet", "")).strip_edges().to_lower(): true}
	for i in range(int(d.get("systems", 3))):
		var sys_name := fresh_name(names, used)
		var sys := {"id": "sys_%d" % i, "name": sys_name, "star": str(stars[rng.randi_range(0, stars.size() - 1)]), "gate": true, "worlds": []}
		var n := rng.randi_range(int(counts[0]), int(counts[1]))
		for j in range(n):
			var w := {"id": "w_%d_%d" % [i, j], "system": sys["id"], "visited": false}
			if i == 0 and j == 0:
				w.merge({"name": str(story.hub.get("planet", sys_name)), "culture": str(story.hub.get("culture", "")), "kind": str(story.hub.get("kind", "town")),
					"hub_seed": int(story.hub.get("seed", 0)), "hub_id": str(story.hub.get("id", "")), "hub_name": str(story.hub.get("name", "")), "visited": true}, true)
			else:
				var culture := NpcGen.pick_culture(rng, "")
				var opts: Array = kinds.get(culture, ["town"])
				var wname := fresh_name(names, used, sys_name)
				var seed_value := rng.randi_range(1000, 99999)
				w.merge({"name": wname, "culture": culture, "kind": str(opts[rng.randi_range(0, opts.size() - 1)]), "hub_seed": seed_value,
					"hub_id": "hub_%d" % seed_value, "hub_name": ""})
			var kit: Dictionary = kits.get(str(w["culture"]), {})
			var lands: Array = kit.get("landscapes", [])
			w["culture_name"] = str(kit.get("name", w["culture"]))
			w["summary"] = str(kit.get("summary", ""))
			w["landscape"] = str(story.hub.get("landscape", "")) if i == 0 and j == 0 and str(story.hub.get("landscape", "")) != "" else (str(lands[rng.randi_range(0, lands.size() - 1)]) if not lands.is_empty() else "")
			(sys["worlds"] as Array).append(w["id"])
			worlds.append(w)
		systems.append(sys)
	sec = {"systems": systems, "worlds": worlds, "at": "w_0_0", "links": [["sys_0", "sys_1"], ["sys_1", "sys_2"]]}
	story.flags[KEY] = sec
	story.hub["world"] = "w_0_0"
	story.hub["landscape"] = str(worlds[0]["landscape"])
	return sec


## A hub made outside travel (a new campaign, the tutorial, a test) becomes the current world's
## hub if the sector already exists.
static func adopt_hub(story: StoryState) -> void:
	var w := current(story)
	if w.is_empty() or str(w.get("hub_id", "")) == str(story.hub.get("id", "")):
		return
	# The world keeps its name (names on the map stay unique); the hub takes the world's.
	w.merge({"culture": str(story.hub.get("culture", "")), "kind": str(story.hub.get("kind", "town")), "visited": true,
		"hub_seed": int(story.hub.get("seed", 0)), "hub_id": str(story.hub.get("id", "")), "hub_name": str(story.hub.get("name", ""))}, true)
	var kit: Dictionary = NpcGen.cultures().get(str(w["culture"]), {})
	w["culture_name"] = str(kit.get("name", w["culture"]))
	w["summary"] = str(kit.get("summary", ""))
	story.hub["planet"] = str(w["name"])
	story.hub["world"] = str(w["id"])
	story.hub["landscape"] = str(w.get("landscape", ""))


static func world(story: StoryState, id: String) -> Dictionary:
	for w: Dictionary in get_sector(story).get("worlds", []):
		if str(w["id"]) == id:
			return w
	return {}


static func system_of(story: StoryState, w: Dictionary) -> Dictionary:
	for s: Dictionary in get_sector(story).get("systems", []):
		if str(s["id"]) == str(w.get("system", "")):
			return s
	return {}


static func current(story: StoryState) -> Dictionary:
	return world(story, str(get_sector(story).get("at", "")))


## The factions a world's hub deals with, once the squad has been there: the hub's own and
## both sides of its situation.
static func factions_of(story: StoryState, w: Dictionary) -> Array:
	var hub: Dictionary = story.hub if str(story.hub.get("id", "")) == str(w.get("hub_id", "")) else story.flags.get(HUBS, {}).get(str(w.get("hub_id", "")), {})
	if hub.is_empty():
		return []
	var out: Array = []
	for f: Variant in [hub.get("faction", ""), hub.get("conflict", {}).get("a", ""), hub.get("conflict", {}).get("b", "")]:
		if str(f) != "" and not out.has(str(f)):
			out.append(str(f))
	return out


## Why the squad can't travel to `id` now ("" if it can).
static func travel_refusal(story: StoryState, id: String) -> String:
	var w := world(story, id)
	if w.is_empty():
		return "There's no such place on the map."
	if str(get_sector(story).get("at", "")) == id:
		return "The squad is already there."
	if story.phase not in ["downtime", "briefing"] or not story.current_hook.is_empty():
		return "Travel happens between missions: in downtime or before you pick the next job."
	if Dialogue.is_open(story):
		return "Finish the conversation first."
	return ""


## Moves the squad (and its mechs) to another world. The hub left behind is kept with its job
## board and situation; the one arrived at is restored, or made the first time.
static func travel(story: StoryState, campaign: Campaign, id: String) -> Array:
	var sec := get_sector(story)
	var from := current(story)
	var to := world(story, id)
	var hubs: Dictionary = story.flags.get(HUBS, {}).duplicate()
	var left: Dictionary = story.hub.duplicate(true)
	left["board"] = story.hooks.duplicate(true)
	left["arc_state"] = story.arc.duplicate(true)
	hubs[str(left["id"])] = left
	var events: Array = []
	var d := data()
	var same := str(from.get("system", "")) == str(to["system"])
	var lines: Array = d.get("travel", {}).get("local" if same else "gate", [""])
	var ships: Array = d.get("ships", ["A ship"])
	var text := str(lines[story.dice.die(lines.size()) - 1])
	text = text.replace("{patron_ship}", str(ships[story.dice.die(ships.size()) - 1])).replace("{from}", str(from.get("name", "here"))).replace("{to}", str(to["name"])).replace("{system}", str(system_of(story, to).get("name", "")))
	if hubs.has(str(to["hub_id"])):
		var back: Dictionary = (hubs[str(to["hub_id"])] as Dictionary).duplicate(true)
		hubs.erase(str(to["hub_id"]))
		story.hooks = back.get("board", [])
		story.arc = back.get("arc_state", {})
		back.erase("board")
		back.erase("arc_state")
		story.hub = back
	else:
		story.hooks = []
		story.arc = {}
		NpcGen.make_hub(story, campaign, int(to["hub_seed"]), str(to["kind"]), str(to["culture"]))
		story.hub["planet"] = str(to["name"])
		story.hub["world"] = str(to["id"])
		story.hub["landscape"] = str(to["landscape"])
		to["hub_name"] = str(story.hub["name"])
	story.flags[HUBS] = hubs
	to["visited"] = true
	sec["at"] = id
	story.add_log("Travelled from %s to %s." % [from.get("name", "?"), to["name"]])
	story.flags["travelled:%d" % story.mission_number] = true
	events.append({"type": "travelled", "from": str(from.get("id", "")), "to": id, "via": "ship" if same else "blink gate", "text": text,
		"rule_ref": REF if not same else "Travel is narrative: no costs are tracked (CANON.md)"})
	events.append({"type": "hub_entered", "hub": story.hub.duplicate(true)})
	for h: Dictionary in MissionHooks.fill_board(story, campaign):
		events.append({"type": "hook_added", "hook": h})
	TownLife.seed_items(story)
	# Pirates now and then board the squad's transport on the way (Core p.40-42: pirates and
	# boarding actions). Not in the authored main campaign, whose fights are its own.
	var chance := int(campaign.options.get("pirate_chance", 14 if not same else 7))
	if bool(campaign.options.get("travel_events", true)) and not CampaignScript.active(campaign) and story.dice.die(100) <= chance:
		events.append({"type": "boarded", "text": "Halfway there, the hull rings: grapples. Pirates are boarding your transport.", "rule_ref": "Core p.42: board a hostile ship"})
		events.append({"type": "combat_requested", "spec": {"hook": "repel_boarders", "in_town": false, "reason": "Pirates boarded the squad's transport."}, "rule_ref": "Core p.45: switching to mech combat"})
	return events
