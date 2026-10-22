class_name Decisions
extends RefCounted
## Story-changing decisions made by the whole squad (DESIGN.md: split decisions). The pilot who
## raises one doesn't have to talk the others round in game: every human player just accepts or
## declines. AI squadmates always side with their human (the seat that owns them, else the
## squad's lead human): they grumble in character but never split the squad. If the humans
## agree, the decision stands; if they split, it becomes a fight between them ("party_split",
## for the flow's player-vs-player battle), and the winning side's choice stands
## ("split_resolved"). With one human there's never a split.
##
## Also the "gather" marker: events that pull a roaming squad together (DESIGN.md "Exploring vs.
## fighting"): a chapter starting, a decision, a split, the finale. gathering(events) lists them.
##
## StoryEngine actions: decide {accept: bool} (each human), split_resolved {winner: "accept" | "decline"} (host).
## A decision is opened with the effect {"decision": {id, prompt, accept: [effects], decline: [effects],
## fight: {place, map}}}. Raised in a conversation, the human who said it has already accepted;
## with one human, it stands at once. `fight` says where a split is fought out (for the flow).

const KEY := "_decision"
const GATHER := ["chapter_started", "decision_started", "party_split", "campaign_ending_due", "boots_on_the_ground"]


static func current(story: StoryState) -> Dictionary:
	return story.flags.get(KEY, {})


## The human seats (AI squadmates follow one of them).
static func humans(story: StoryState) -> Array:
	var out: Array = story.seats.keys().filter(func(s: String) -> bool: return not story.is_ai(s) and story.is_alive(story.pilot_of_seat(s)))
	out.sort()
	return out


## The human an AI squadmate follows: its owner seat if it has one, else the first human.
static func leader_of(story: StoryState, seat: String) -> String:
	var owner := str(story.seats.get(seat, {}).get("owner", ""))
	if owner != "" and not story.is_ai(owner):
		return owner
	var h := humans(story)
	return str(h[0]) if not h.is_empty() else ""


static func open(story: StoryState, spec: Dictionary, campaign: Campaign = null, raiser: String = "") -> Array:
	story.flags[KEY] = {"id": str(spec.get("id", "decision")), "prompt": str(spec.get("prompt", "")), "accept": (spec.get("accept", []) as Array).duplicate(true),
		"decline": (spec.get("decline", []) as Array).duplicate(true), "votes": {}, "raised_by": raiser, "fight": (spec.get("fight", {}) as Dictionary).duplicate()}
	var events: Array = [{"type": "decision_started", "id": spec.get("id", ""), "prompt": spec.get("prompt", ""), "gather": true,
		"humans": humans(story), "text": str(spec.get("prompt", "")), "raised_by": raiser}]
	if campaign != null and humans(story).has(raiser):
		events.append_array(vote(story, campaign, raiser, true))
	return events


static func refusal(story: StoryState, seat: String) -> String:
	if current(story).is_empty():
		return "There's nothing to decide right now."
	if story.is_ai(seat) or not story.seats.has(seat):
		return "Only the players decide this."
	return ""


static func vote(story: StoryState, campaign: Campaign, seat: String, accept: bool) -> Array:
	var d := current(story)
	(d["votes"] as Dictionary)[seat] = accept
	var hs := humans(story)
	if not hs.all(func(h: String) -> bool: return (d["votes"] as Dictionary).has(h)):
		return [{"type": "decision_vote", "seat": seat, "accept": accept, "waiting": hs.filter(func(h: String) -> bool: return not (d["votes"] as Dictionary).has(h))}]
	var yes: Array = hs.filter(func(h: String) -> bool: return bool(d["votes"][h]))
	var no: Array = hs.filter(func(h: String) -> bool: return not bool(d["votes"][h]))
	if yes.is_empty() or no.is_empty():
		return _settle(story, campaign, not yes.is_empty())
	# A split: each AI squadmate stands with its human.
	var sides := {"accept": yes.duplicate(), "decline": no.duplicate()}
	for s: String in story.seats:
		if story.is_ai(s) and story.is_alive(story.pilot_of_seat(s)):
			(sides["accept"] if yes.has(leader_of(story, s)) else sides["decline"]).append(s)
	d["split"] = sides
	return [{"type": "party_split", "id": d["id"], "sides": sides, "gather": true, "fight": d.get("fight", {}),
		"text": "The squad can't agree: %s. It comes down to a fight between you." % d["prompt"]}]


static func resolve_split(story: StoryState, campaign: Campaign, winner: String) -> Array:
	return _settle(story, campaign, winner == "accept")


static func _settle(story: StoryState, campaign: Campaign, accepted: bool) -> Array:
	var d := current(story)
	story.flags.erase(KEY)
	story.flags["decided:%s" % d.get("id", "")] = "accept" if accepted else "decline"
	var events: Array = [{"type": "decision_made", "id": d.get("id", ""), "accepted": accepted}]
	events.append_array(StoryEffects.apply_all(d.get("accept" if accepted else "decline", []), story, campaign, {}))
	# AI squadmates say what they think of it, but go along.
	for s: String in story.seats:
		if story.is_ai(s) and story.is_alive(story.pilot_of_seat(s)):
			var pid := story.pilot_of_seat(s)
			var cs := str(campaign.pilots.get(pid, {}).get("callsign", ""))
			var lines := ["%s: \"Fine. Your call.\"", "%s: \"I'd have done it differently. But I'm with you.\"", "%s: \"Let's hope you're right.\""]
			events.append({"type": "banter", "pilot": pid, "seat": s, "topic": "decision", "text": lines[story.dice.die(lines.size()) - 1] % cs})
	return events


## Events that should pull a roaming squad together.
static func gathering(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return bool(e.get("gather", false)) or GATHER.has(str(e.get("type", ""))))
