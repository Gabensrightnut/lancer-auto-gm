class_name GmTwist
extends RefCounted
## The GM's mid-mission twist (Core p.43: a mission's goal can change when new information
## comes to light). A story hook may hide one in mission.flavor["twist"] ({id, reveal, question,
## effects}); the briefing never shows it, and it stays on the host (the Mission is never sent).
##
## When the fight starts the GM picks its moment (plan()): a round, or an objective moment,
## whichever comes first. Round: 3, or halfway through a timed mission (Holdout, Gauntlet,
## Control). Objective: the first time a Control Zone scores, otherwise the first mech or NPC
## destroyed on either side. The reveal goes through the rules engine (`gm_narrate`, kind
## "twist") and is seen only by the squad's side (events with `seen_by`, ViewFilter). The
## consequence is applied by the story at the debrief (StoryEngine mission_finished).
##
## How the squad got there (mission.flavor arrived_late / arrived_spent, set by the briefing's
## journey choice) is told when combat starts. PROVISIONAL (docs/RULES_TODO.md "Arriving late
## or spent"): the book gives no battle effect for either, so the GM only narrates them, and a
## late squad meets the twist a round sooner (things were already moving when they got there).

const REF := "Core p.43: goals can change mid-mission"
const DEFAULT_ROUND := 3
## Whose players see the GM's narration.
const SEEN_BY := [Mission.PLAYERS]


## When to reveal: {"round": n, "on": "first_score" | "first_destroyed"}, or {} (no twist).
static func plan(mission: Mission) -> Dictionary:
	var twist: Dictionary = mission.flavor.get("twist", {})
	if twist.is_empty() or str(twist.get("reveal", "")) == "":
		return {}
	var r := DEFAULT_ROUND
	if mission.rounds > 0:
		r = maxi(2, ceili(mission.rounds / 2.0))
	if bool(mission.flavor.get("arrived_late", false)):
		r = maxi(2, r - 1)
	return {"round": r, "on": "first_score" if mission.sitrep_id == "sitrep_control" else "first_destroyed"}


## Host side: looks at a batch of rules events (after Mission.observe) and marks the twist due
## when its moment comes.
static func observe(mission: Mission, state: GameState, events: Array) -> void:
	var f := mission.flavor
	if not f.has("twist_plan"):
		f["twist_plan"] = plan(mission)
	var p: Dictionary = f["twist_plan"]
	if p.is_empty() or bool(f.get("twist_revealed", false)) or bool(f.get("twist_due", false)):
		return
	for e: Dictionary in events:
		match str(e.get("type", "")):
			"round_started":
				if int(e.get("round", 0)) >= int(p["round"]):
					f["twist_due"] = true
			"unit_destroyed":
				var u := state.unit(str(e.get("unit", "")))
				if p["on"] == "first_destroyed" and u != null and u.kind in [Unit.KIND_MECH, Unit.KIND_NPC]:
					f["twist_due"] = true
	if p["on"] == "first_score" and int(mission.scores.get(Mission.PLAYERS, 0)) + int(mission.scores.get(Mission.ENEMIES, 0)) > 0:
		f["twist_due"] = true


## The GM's next narration as a `gm_narrate` action, or {}: first how the squad arrived (once
## combat has started), then the twist when it's due. Call done() after submitting it.
static func next_action(mission: Mission, state: GameState) -> Dictionary:
	if state.phase != GameState.PHASE_COMBAT:
		return {}
	var f := mission.flavor
	var hook: Dictionary = f.get("hook", {})
	var speaker := str(hook.get("patron", ""))
	if not bool(f.get("arrival_told", false)):
		var lines: Array = []
		if bool(f.get("arrived_late", false)):
			lines.append("You took the long way round and got here late. Whatever is happening here started without you.")
		if bool(f.get("arrived_spent", false)):
			lines.append("The crossing was hard: every pilot took 1 damage on the way (Core p.48). Pilot HP carries into this fight if anyone leaves their mech.")
		if not lines.is_empty():
			return {"type": "gm_narrate", "params": {"kind": "arrival", "title": "Arrival", "text": " ".join(lines),
				"speaker": speaker, "seen_by": SEEN_BY.duplicate(), "rule_ref": "Core p.40-44: the mission, from the briefing to boots on the ground"}}
		f["arrival_told"] = true
	if bool(f.get("twist_due", false)) and not bool(f.get("twist_revealed", false)):
		var t: Dictionary = f.get("twist", {})
		return {"type": "gm_narrate", "params": {"kind": "twist", "id": str(t.get("id", "")), "title": "Twist",
			"text": str(t.get("reveal", "")), "question": str(t.get("question", "")), "speaker": speaker,
			"seen_by": SEEN_BY.duplicate(), "rule_ref": REF}}
	return {}


## Marks a narration as told (whether or not the engine took it, so it's never retried forever).
static func done(mission: Mission, action: Dictionary) -> void:
	match str(action.get("params", {}).get("kind", "")):
		"arrival":
			mission.flavor["arrival_told"] = true
		"twist":
			mission.flavor["twist_revealed"] = true
			mission.flavor["twist_due"] = false
