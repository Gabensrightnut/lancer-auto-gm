class_name WorldState
extends RefCounted
## What the squad does to a place stays done (data/game/story/consequences.json): blow up a
## dam and, a mission later, the town's water runs short, people remember who did it, the
## squad feels it, and there's a job to make it right. Facts per hub in story.flags["_world"]
## = {hub id: {fact: value}}, set by jobs (on win), fights in town, and the effect
## {"world": {"set": {fact: value}}}; the condition {"world": fact, "eq": value} reads them.

const FILE := "res://data/game/story/consequences.json"
const KEY := "_world"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {}
	return _data


static func facts(story: StoryState, hub_id: String = "") -> Dictionary:
	var all: Dictionary = story.flags.get(KEY, {})
	return all.get(hub_id if hub_id != "" else str(story.hub.get("id", "")), {})


static func set_facts(story: StoryState, values: Dictionary, hub_id: String = "") -> Array:
	var id := hub_id if hub_id != "" else str(story.hub.get("id", ""))
	var all: Dictionary = (story.flags.get(KEY, {}) as Dictionary).duplicate(true)
	var here: Dictionary = all.get(id, {})
	for k: String in values:
		if values[k] == null or str(values[k]) == "":
			here.erase(k)
		else:
			here[k] = values[k]
	here["_since"] = story.mission_number
	all[id] = here
	story.flags[KEY] = all
	return [{"type": "world_changed", "hub": id, "facts": values.duplicate()}]


## After a mission: what it did to the place, then what that leads to.
static func after_mission(story: StoryState, campaign: Campaign, hook: Dictionary, won: bool) -> Array:
	var events: Array = []
	var d := data()
	var job: Dictionary = d.get("from_jobs", {}).get(str(hook.get("template", "")), {})
	var fx: Dictionary = job.get("won" if won else "lost", {})
	if not fx.is_empty():
		events.append_array(set_facts(story, _filled(fx.get("set", {}), hook)))
	if bool(hook.get("in_town", false)) and not bool(hook.get("tutorial", false)):
		events.append_array(set_facts(story, _filled(d.get("town_fight", {}).get("set", {}), hook)))
	events.append_array(tick(story, campaign))
	return events


static func _filled(values: Dictionary, hook: Dictionary) -> Dictionary:
	var out := {}
	for k: String in values:
		out[k] = str(values[k]).replace("{place}", str(hook.get("place", "the site")))
	return out


## Which kind of shortage breaking `what` causes.
static func kind_of(what: String) -> String:
	var w := what.to_lower()
	var words: Dictionary = data().get("shortage_words", {})
	for k: String in words:
		for word: String in words[k]:
			if w.contains(word):
				return k
	return "supply"


## Facts that have sat long enough turn into consequences: a line about it, the squad's
## reaction, and a job to put it right.
static func tick(story: StoryState, campaign: Campaign) -> Array:
	var events: Array = []
	var here := facts(story)
	if here.is_empty():
		return events
	for r: Dictionary in data().get("rules", []):
		var cond: Dictionary = r.get("if", {})
		var fact := str(cond.get("fact", ""))
		if not here.has(fact):
			continue
		var what := str(here[fact])
		if cond.has("kind") and kind_of(what) != str(cond["kind"]):
			continue
		if story.mission_number - int(here.get("_since", 0)) < int(r.get("delay", 0)):
			continue
		var clear := {}
		for c: String in r.get("clear", []):
			clear[c] = null
		var set: Dictionary = (r.get("set", {}) as Dictionary).duplicate()
		set.merge(clear)
		set["what"] = what
		events.append_array(set_facts(story, set))
		var lines: Array = r.get("text", [""])
		var text := str(lines[story.dice.die(lines.size()) - 1]).replace("{hub}", str(story.hub.get("name", ""))).replace("{what}", what)
		events.append({"type": "consequence", "id": r["id"], "text": text, "gather": false})
		story.add_log(text)
		var ban: Array = r.get("banter", [])
		var ai: Array = story.seats.keys().filter(func(s: String) -> bool: return story.is_ai(s) and story.is_alive(story.pilot_of_seat(s)))
		if not ban.is_empty() and not ai.is_empty():
			var pid := story.pilot_of_seat(str(ai[0]))
			events.append({"type": "banter", "pilot": pid, "seat": ai[0], "topic": "consequence", "text": str(ban[story.dice.die(ban.size()) - 1])})
		if str(r.get("job", "")) != "" and not CampaignScript.active(campaign):
			var h := MissionHooks.make(story, campaign, str(r["job"]), {})
			if not h.is_empty():
				h["objective"] = str(h["objective"]).replace("{what}", what)
				story.hooks.push_front(h)
				events.append({"type": "hook_added", "hook": h})
		break
	return events
