class_name Decisions
extends RefCounted
## Story-changing decisions made by the whole squad (DESIGN.md: split decisions). All the
## options show side by side (DecisionPanel); every human player votes for one, sees who voted
## for what, and can change their vote until it's settled. AI squadmates always side with their
## human (the seat that owns them, else the squad's lead human): they grumble in character but
## never split the squad. If the humans agree, the choice stands at once. If they split, a
## countdown starts (host setting campaign.options.split_countdown, 15-30 s, default 20; votes
## can still change, and agreement calls the fight off), then the flow runs a player-vs-player
## fight with teams by vote ("party_split": only the players' mechs, nobody dies) and the
## winners' option becomes the story's answer ("split_resolved {winner}"). The losers' option
## isn't taken. With one human there's never a split.
##
## Also the "gather" marker: events that pull a roaming squad together (DESIGN.md "Exploring vs.
## fighting"): a chapter starting, a decision, a split, the finale. gathering(events) lists them.
##
## StoryEngine actions: decide {option} (or {accept: bool}: the options "accept"/"decline"),
## split_start {} (host: the arena fight begins, votes lock), split_resolved {winner: option id}.
## A decision is opened with the effect {"decision": {id, prompt, options: [{id, label, effects}],
## fight: {place, map}}}, or the two-way {id, prompt, accept: [effects], decline: [effects],
## accept_label, decline_label}. Raised in a conversation, the human who said it has already
## voted for the first option; with one human, it stands at once.
##
## Events: decision_started {id, prompt, options: [{id, label}], humans}, decision_vote {votes,
## sides, waiting}, party_split {id, prompt, options, sides: {option: [seats]}, countdown, fight,
## note (the first time)}, party_split_update {sides} (a vote changed during the countdown),
## decision_made {id, choice, accepted, split_cancelled?}.

const KEY := "_decision"
const GATHER := ["chapter_started", "decision_started", "party_split", "campaign_ending_due", "boots_on_the_ground", "boarded", "combat_requested"]
const COUNTDOWN := 20
const EXPLAINED := "_split_explained"
const NOTE := "The squad can't agree, so you settle it in the arena: a quick fight between your own mechs, teams by vote. Nobody dies, the mechs just get beaten up, and the winning side decides."


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


## The host's countdown before an arena fight (seconds, 15-30).
static func countdown(campaign: Campaign) -> int:
	return clampi(int(campaign.options.get("split_countdown", COUNTDOWN)) if campaign != null else COUNTDOWN, 15, 30)


static func options_of(spec: Dictionary) -> Array:
	if spec.has("options"):
		return (spec["options"] as Array).duplicate(true)
	return [{"id": "accept", "label": str(spec.get("accept_label", "Yes")), "effects": (spec.get("accept", []) as Array).duplicate(true)},
		{"id": "decline", "label": str(spec.get("decline_label", "No")), "effects": (spec.get("decline", []) as Array).duplicate(true)}]


static func _labels(opts: Array) -> Array:
	return opts.map(func(o: Dictionary) -> Dictionary: return {"id": str(o["id"]), "label": str(o.get("label", o["id"]))})


static func open(story: StoryState, spec: Dictionary, campaign: Campaign = null, raiser: String = "") -> Array:
	var opts := options_of(spec)
	story.flags[KEY] = {"id": str(spec.get("id", "decision")), "prompt": str(spec.get("prompt", "")), "options": opts,
		"votes": {}, "raised_by": raiser, "fight": (spec.get("fight", {}) as Dictionary).duplicate()}
	var events: Array = [{"type": "decision_started", "id": spec.get("id", ""), "prompt": spec.get("prompt", ""), "gather": true,
		"humans": humans(story), "options": _labels(opts), "text": str(spec.get("prompt", "")), "raised_by": raiser}]
	if campaign != null and humans(story).has(raiser) and not opts.is_empty():
		events.append_array(vote(story, campaign, raiser, str(opts[0]["id"])))
	return events


static func refusal(story: StoryState, seat: String, choice: String = "") -> String:
	var d := current(story)
	if d.is_empty():
		return "There's nothing to decide right now."
	if story.is_ai(seat) or not story.seats.has(seat):
		return "Only the players decide this."
	if bool(d.get("locked", false)):
		return "It's being settled in the arena now."
	if choice != "" and not (d.get("options", []) as Array).any(func(o: Dictionary) -> bool: return str(o["id"]) == choice):
		return "That isn't one of the choices."
	return ""


## Who's on which option now: {option id: [seats]}, AI squadmates with their human.
static func sides(story: StoryState) -> Dictionary:
	var d := current(story)
	var out := {}
	for o: Dictionary in d.get("options", []):
		out[str(o["id"])] = []
	for h: String in d.get("votes", {}):
		(out[str(d["votes"][h])] as Array).append(h)
	for s: String in story.seats:
		if story.is_ai(s) and story.is_alive(story.pilot_of_seat(s)):
			var lead := leader_of(story, s)
			if (d.get("votes", {}) as Dictionary).has(lead):
				(out[str(d["votes"][lead])] as Array).append(s)
	return out


## A vote (or a changed vote). `choice`: an option id, or a bool for the two-way accept/decline.
static func vote(story: StoryState, campaign: Campaign, seat: String, choice: Variant) -> Array:
	var d := current(story)
	var pick := ("accept" if bool(choice) else "decline") if choice is bool else str(choice)
	(d["votes"] as Dictionary)[seat] = pick
	var hs := humans(story)
	var waiting: Array = hs.filter(func(h: String) -> bool: return not (d["votes"] as Dictionary).has(h))
	if not waiting.is_empty():
		return [{"type": "decision_vote", "seat": seat, "choice": pick, "votes": (d["votes"] as Dictionary).duplicate(), "sides": sides(story), "waiting": waiting}]
	var picked := {}
	for h: String in hs:
		picked[str(d["votes"][h])] = true
	if picked.size() == 1:
		var cancelled := d.has("split")
		var out := _settle(story, campaign, str(picked.keys()[0]))
		if cancelled:
			out[0]["split_cancelled"] = true
			out[0]["text"] = "The squad agrees after all: no fight."
		return out
	var sd := sides(story)
	if d.has("split"):
		d["split"] = sd
		return [{"type": "party_split_update", "id": d["id"], "sides": sd, "votes": (d["votes"] as Dictionary).duplicate()}]
	d["split"] = sd
	var opts: Array = d.get("options", [])
	var parts: Array = []
	for o: Dictionary in opts:
		var who: Array = (sd.get(str(o["id"]), []) as Array).map(func(s: String) -> String: return str(campaign.pilots.get(story.pilot_of_seat(s), {}).get("callsign", s)))
		if not who.is_empty():
			parts.append("%s (%s)" % [o.get("label", o["id"]), ", ".join(PackedStringArray(who))])
	var ev := {"type": "party_split", "id": d["id"], "prompt": d.get("prompt", ""), "options": _labels(opts), "sides": sd, "gather": true,
		"fight": d.get("fight", {}), "countdown": countdown(campaign),
		"text": "Settle it in the arena: %s." % " vs ".join(PackedStringArray(parts))}
	if not bool(story.flags.get(EXPLAINED, false)):
		story.flags[EXPLAINED] = true
		ev["note"] = NOTE
	return [ev]


## The countdown ran out: the arena fight begins and the votes lock (host).
static func start_split(story: StoryState) -> Array:
	var d := current(story)
	d["locked"] = true
	return [{"type": "split_started", "id": d.get("id", ""), "sides": d.get("split", {}), "fight": d.get("fight", {})}]


static func resolve_split(story: StoryState, campaign: Campaign, winner: String) -> Array:
	return _settle(story, campaign, winner)


static func _settle(story: StoryState, campaign: Campaign, choice: String) -> Array:
	var d := current(story)
	story.flags.erase(KEY)
	story.flags["decided:%s" % d.get("id", "")] = choice
	var effects: Array = []
	for o: Dictionary in d.get("options", []):
		if str(o["id"]) == choice:
			effects = o.get("effects", [])
	var events: Array = [{"type": "decision_made", "id": d.get("id", ""), "choice": choice, "accepted": choice == "accept"}]
	events.append_array(StoryEffects.apply_all(effects, story, campaign, {}))
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
