class_name Agendas
extends RefCounted
## Personal agendas: a pilot's own grudge or goal that grows out of what happens to them, and
## colours the story (DESIGN.md: personal agendas). E.g. with the food-and-water house rule, a
## pilot whose mech is wrecked lives on short rations until it's reprinted; resentment builds,
## and in the pirate career they become the one pushing for mutiny. Kept in
## story.flags["_agendas"] = {pilot id: {kind, why, strength}}. The condition
## {"agenda": kind} (optionally "pilot": "speaker") and the effect
## {"agenda": {"pilot": "speaker" | id, "kind", "why", "add": 1}} read and write them.

const KEY := "_agendas"


static func of(story: StoryState, pid: String) -> Dictionary:
	return story.flags.get(KEY, {}).get(pid, {})


static func anyone(story: StoryState, kind: String) -> String:
	var all: Dictionary = story.flags.get(KEY, {})
	for pid: String in all:
		if str(all[pid].get("kind", "")) == kind and int(all[pid].get("strength", 0)) >= 2 and story.is_alive(pid):
			return pid
	return ""


static func add(story: StoryState, campaign: Campaign, pid: String, kind: String, why: String, amount: int = 1) -> Array:
	if not campaign.pilots.has(pid):
		return []
	var all: Dictionary = (story.flags.get(KEY, {}) as Dictionary).duplicate(true)
	var a: Dictionary = all.get(pid, {"kind": kind, "why": why, "strength": 0})
	if str(a["kind"]) != kind:
		a = {"kind": kind, "why": why, "strength": 0}
	a["strength"] = int(a["strength"]) + amount
	a["why"] = why
	all[pid] = a
	story.flags[KEY] = all
	var cs := str(campaign.pilots[pid].get("callsign", ""))
	var text := ("%s is done keeping quiet about it: %s." % [cs, why]) if int(a["strength"]) == 2 else ("%s is keeping score: %s." % [cs, why])
	return [{"type": "agenda", "pilot": pid, "kind": kind, "strength": a["strength"], "text": text}]
