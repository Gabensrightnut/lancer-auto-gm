class_name Bonds
extends RefCounted
## Relationships between the squad's pilots, built from what they go through together:
## missions survived side by side, helping each other's checks, drinking together in
## downtime, mourning the same friend, agreeing or clashing in squad votes. Shown in the
## debrief and downtime. Two places where the book gives a bond a rules effect:
## - The GM may reward pilots who bonded in downtime with +1 Accuracy on skill checks to help
##   each other during the next mission (Core p.50). We grant it to a pair that reaches
##   Friends or better, or drinks together, in a downtime (campaign option bond_rewards, on).
## - The Bonded talent's bondmate can only be replaced between missions "if your relationship
##   with them has changed" (Core p.90): set_bondmate checks the bond's level against when
##   the bondmate was chosen.
##
## Stored in story.flags["_bonds"]["<pid>|<pid>"] = {score, label, history: [..]}.

const KEY := "_bonds"
const REWARDS := "_bond_rewards"
const LEVELS := [[-99, "Rivals"], [-2, "At odds"], [0, "Squadmates"], [3, "Friends"], [7, "Close"], [12, "Inseparable"]]
const REF_REWARD := "Core p.50: the GM may reward a new bond (+1 Accuracy on skill checks to help each other)"
const REF_BONDED := "Core p.90: Bonded (replace your bondmate only if your relationship has changed)"


static func key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


static func get_bond(story: StoryState, a: String, b: String) -> Dictionary:
	if not story.flags.has(KEY):
		story.flags[KEY] = {}
	var all: Dictionary = story.flags[KEY]
	var k := key(a, b)
	if not all.has(k):
		all[k] = {"score": 0, "label": "Squadmates", "history": []}
	return all[k]


static func label_for(score: int) -> String:
	var out := "Rivals"
	for lv: Array in LEVELS:
		if score >= int(lv[0]):
			out = str(lv[1])
	return out


## Changes a bond; returns a bond_changed event when its label changes.
static func add(story: StoryState, campaign: Campaign, a: String, b: String, amount: int, why: String) -> Array:
	if a == b or a == "" or b == "" or not campaign.pilots.has(a) or not campaign.pilots.has(b):
		return []
	var bond := get_bond(story, a, b)
	var before := str(bond["label"])
	bond["score"] = clampi(int(bond["score"]) + amount, -10, 20)
	bond["label"] = label_for(int(bond["score"]))
	(bond["history"] as Array).append({"mission": story.mission_number, "why": why, "amount": amount})
	if (bond["history"] as Array).size() > 30:
		bond["history"] = (bond["history"] as Array).slice(-30)
	if str(bond["label"]) == before:
		return []
	var an := str(campaign.pilots[a].get("callsign", ""))
	var bn := str(campaign.pilots[b].get("callsign", ""))
	return [{"type": "bond_changed", "a": a, "b": b, "from": before, "to": bond["label"], "why": why,
		"text": "%s and %s: %s now (%s)." % [an, bn, str(bond["label"]).to_lower(), why]}]


## The bond with the highest score for this pilot: {"pilot", "label", "score"} or {}.
static func closest(story: StoryState, campaign: Campaign, pid: String) -> Dictionary:
	var best: Dictionary = {}
	for o: String in campaign.pilots:
		if o == pid:
			continue
		var bond := get_bond(story, pid, o)
		if best.is_empty() or int(bond["score"]) > int(best["score"]):
			best = {"pilot": o, "label": bond["label"], "score": int(bond["score"])}
	return best


## Updates bonds from story events (StoryEngine.submit calls this).
static func observe(story: StoryState, campaign: Campaign, events: Array) -> Array:
	var out: Array = []
	for e: Dictionary in events:
		match str(e.get("type", "")):
			"debrief":
				var alive: Array = campaign.pilots.keys().filter(func(p: String) -> bool: return story.is_alive(p))
				alive.sort()
				for i in range(alive.size()):
					for j in range(i + 1, alive.size()):
						out.append_array(add(story, campaign, alive[i], alive[j], 1, "survived %s together" % str(story.last_mission.get("place", "a mission"))))
			"pilot_died":
				var dead := str(e["pilot"])
				var alive: Array = campaign.pilots.keys().filter(func(p: String) -> bool: return story.is_alive(p) and p != dead)
				alive.sort()
				for i in range(alive.size()):
					for j in range(i + 1, alive.size()):
						out.append_array(add(story, campaign, alive[i], alive[j], 2, "mourned %s together" % str(campaign.pilots.get(dead, {}).get("callsign", "a friend"))))
			"narrative_check":
				var rec: Dictionary = e.get("check", {})
				if (rec.get("bonus_sources", []) as Array).any(func(b: Dictionary) -> bool: return str(b.get("label", "")) == "Teamwork"):
					for h: Variant in e.get("helpers", []):
						out.append_array(add(story, campaign, str(e["pilot"]), str(h), 1, "had each other's backs"))
			"dialogue_choice":
				var votes: Dictionary = e.get("votes", {})
				var seats := votes.keys()
				seats.sort()
				for i in range(seats.size()):
					for j in range(i + 1, seats.size()):
						var pa := story.pilot_of_seat(str(seats[i]))
						var pb := story.pilot_of_seat(str(seats[j]))
						if votes[seats[i]] != votes[seats[j]]:
							out.append_array(add(story, campaign, pa, pb, -1, "disagreed in a squad vote"))
			"downtime_ended":
				out.append_array(_downtime_rewards(story, campaign, e.get("recap", [])))
	return out


## Pilots who got a damn drink in the same downtime bonded over it (the book's own example,
## Core p.50); pairs at Friends or better get the GM's reward for the next mission.
static func _downtime_rewards(story: StoryState, campaign: Campaign, recap: Array) -> Array:
	var out: Array = []
	var drinkers: Array = []
	for r: Dictionary in recap:
		if str(r.get("action", "")) == "dt_get_a_damn_drink" and not drinkers.has(str(r["pilot"])):
			drinkers.append(str(r["pilot"]))
	drinkers.sort()
	for i in range(drinkers.size()):
		for j in range(i + 1, drinkers.size()):
			out.append_array(add(story, campaign, drinkers[i], drinkers[j], 2, "went drinking together"))
	var rewards: Array = []
	if campaign == null or bool(campaign.options.get("bond_rewards", true)):
		var ids: Array = campaign.pilots.keys().filter(func(p: String) -> bool: return story.is_alive(p))
		ids.sort()
		for i in range(ids.size()):
			for j in range(i + 1, ids.size()):
				var bond := get_bond(story, ids[i], ids[j])
				var drank: bool = drinkers.has(ids[i]) and drinkers.has(ids[j])
				if int(bond["score"]) >= 3 or drank:
					rewards.append([ids[i], ids[j]])
					out.append({"type": "bond_reward", "a": ids[i], "b": ids[j], "rule_ref": REF_REWARD,
						"text": "%s and %s: +1 Accuracy on skill checks to help each other next mission." % [campaign.pilots[ids[i]].get("callsign", ""), campaign.pilots[ids[j]].get("callsign", "")]})
	story.flags[REWARDS] = rewards
	return out


## +1 Accuracy when a helper and the pilot rolling share a bond reward (Core p.50).
static func reward_between(story: StoryState, a: String, helpers: Array) -> String:
	for pair: Variant in story.flags.get(REWARDS, []):
		var p: Array = pair
		for h: Variant in helpers:
			if (str(p[0]) == a and str(p[1]) == str(h)) or (str(p[1]) == a and str(p[0]) == str(h)):
				return str(h)
	return ""


# --- Bonded (talent) ---------------------------------------------------------------------

static func has_bonded(pilot: Dictionary) -> bool:
	return int(pilot.get("talents", {}).get("t_bonded", 0)) > 0


## Why this bondmate can't be set now ("" if it can).
static func bondmate_refusal(story: StoryState, campaign: Campaign, pid: String, mate: String) -> String:
	var p: Dictionary = campaign.pilots.get(pid, {})
	if not has_bonded(p):
		return "Only a pilot with the Bonded talent has a bondmate."
	if mate == pid or not campaign.pilots.has(mate) or not story.is_alive(mate):
		return "Choose another living pilot as your bondmate."
	if story.phase == "mission":
		return "You can only change your bondmate between missions."
	var current := str(p.get("bondmate", ""))
	if current == "" or current == mate or not story.is_alive(current):
		return ""
	var since := str(p.get("bondmate_label", ""))
	if since == str(get_bond(story, pid, current)["label"]):
		return "Your relationship with %s hasn't changed since you bonded, so you can't replace them yet." % campaign.pilots[current].get("callsign", "your bondmate")
	return ""
