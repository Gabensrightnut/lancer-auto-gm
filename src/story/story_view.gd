class_name StoryView
extends RefCounted
## What a client may know about the story (secrets stay on the host, CLAUDE.md): everything
## the squad can see, minus NPC secrets nobody has uncovered, the hidden twist of every job,
## the story dice and the GM's line bookkeeping. Pilots come along (names, triggers, LL, gear)
## so a client can draw the UI. A client rebuilds a StoryState from it (StoryClient).
## A human GM's seat ("gm") keeps the secrets and twists: the GM tools work on them.


static func view_for(story: StoryState, campaign: Campaign, seat: String = "") -> Dictionary:
	var d := story.to_dict()
	d.erase("dice_state")
	d.erase("line_memory")
	d["story_seed"] = 0
	if seat != "gm":
		var npcs: Dictionary = d.get("npcs", {})
		for id: String in npcs:
			var npc: Dictionary = npcs[id]
			if not bool(story.flags.get("secret_known:" + id, false)):
				npc.erase("secret")
		for h: Dictionary in d.get("hooks", []):
			h.erase("twist")
		(d.get("current_hook", {}) as Dictionary).erase("twist")
	var flags := {}
	for k: String in story.flags:
		if k != StoryState.KEY:
			flags[k] = story.flags[k]
	var pilots := {}
	for pid: String in campaign.pilots:
		var p: Dictionary = campaign.pilots[pid]
		pilots[pid] = {"id": pid, "name": p.get("name", ""), "callsign": p.get("callsign", ""), "ll": p.get("ll", 0),
			"skills": (p.get("skills", {}) as Dictionary).duplicate(), "background": p.get("background", ""),
			"pilot_gear": (p.get("pilot_gear", []) as Array).duplicate(), "hull": p.get("hull", 0), "agility": p.get("agility", 0),
			"systems": p.get("systems", 0), "engineering": p.get("engineering", 0), "reserves": (p.get("reserves", []) as Array).duplicate(),
			"mechs": (p.get("mechs", []) as Array).duplicate(true), "active_mech": p.get("active_mech", ""),
			"portrait": p.get("portrait", {}), "look": p.get("look", {})}
	return {"story": d, "flags": flags, "pilots": pilots, "options": campaign.options.duplicate(true),
		"history": campaign.history.duplicate(true)}


## Events as a client may see them: hooks without their hidden twist (until it's revealed at
## the debrief), NPC records without secrets.
static func events_for(events: Array, seat: String = "") -> Array:
	var out: Array = []
	for e: Dictionary in events:
		var c := e.duplicate(true)
		if c.get("hook") is Dictionary and seat != "gm":
			(c["hook"] as Dictionary).erase("twist")
		out.append(c)
	return out


## A client-side StoryState and Campaign rebuilt from a view.
static func mirror(view: Dictionary) -> Dictionary:
	var c := Campaign.new()
	c.pilots = (view.get("pilots", {}) as Dictionary).duplicate(true)
	c.options.merge(view.get("options", {}), true)
	c.history = (view.get("history", []) as Array).duplicate(true)
	c.story_flags = (view.get("flags", {}) as Dictionary).duplicate(true)
	var s := StoryState.from_dict(view.get("story", {}), c.story_flags)
	return {"story": s, "campaign": c}
