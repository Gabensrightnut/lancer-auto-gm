class_name Rulings
extends RefCounted
## Questions the core book leaves open, each with the canon readings it allows. The game never
## picks one silently: the table chooses (up front from catalog(), or when it first comes up)
## and the choice is stored in state.rulings[id] = {"choice": option id} and kept by the
## campaign. Each option is a reading the book supports; see docs/RULES_TODO.md "Rulings".
##
## Two ways a ruling comes up:
## - When checking an action (e.g. a move that climbs): the action is refused with
##   RuleResult.ruling_needed(id, ...) until the table decides.
## - While resolving (e.g. how much heat carries over): ask() pauses the action like a
##   reaction question; the engine sends `ruling_needed` and replays the action once the host
##   answers with {"type": "set_ruling", "params": {"id", "choice"}}.

const CATALOG := {
	"big_mech_uneven_ground": {
		"question": "Can a Size 2+ mech stand with part of its footprint over lower ground?",
		"options": {"allow": "Yes: it stands at the highest ground under it.", "forbid": "No: every space under it must be level."},
		"suggested": "forbid", "rule_ref": "Core p.59 (Size), p.62 (moving) don't say"},
	"climb_cost": {
		"question": "Climbing is half speed (Core p.63). What does a step onto higher or lower ground cost?",
		"options": {"step_plus_climb": "1 for the step, plus 2 for each level climbed.", "climb_only": "2 for each level climbed, the step included (at least 1)."},
		"suggested": "step_plus_climb", "rule_ref": "Core p.63 Jumping and Climbing"},
	"flight_difficult": {
		"question": "Does a flying character pay double for flying over difficult terrain?",
		"options": {"ignore": "No: difficult terrain is ground; flyers pass over it.", "pay": "Yes: any movement through those spaces is half speed."},
		"suggested": "ignore", "rule_ref": "Core p.62 Difficult Terrain, p.63 Flight"},
	"distance_3d": {
		"question": "How are Range, Threat and Sensors measured when heights differ?",
		"options": {"spaces_3d": "In spaces in any direction: ground distance or height gap, whichever is larger.", "ground_only": "Along the ground only, like a flat map."},
		"suggested": "spaces_3d", "rule_ref": "Core p.62 Adjacency (vertical counts), p.63 Flight, p.64 Range"},
	"heat_overflow": {
		"question": "After overheating, how much of the heat carries over (Core p.81 'excess heat beyond what was required to exceed its Heat Cap')?",
		"options": {"beyond_cap_plus_one": "Everything past Heat Cap + 1 (it took Cap + 1 to exceed the cap).", "beyond_cap": "Everything past the Heat Cap."},
		"suggested": "beyond_cap_plus_one", "rule_ref": "Core p.81 Overheating"},
	"unforced_save_target": {
		"question": "A save nobody forces (a flyer's Agility save after structure or stress damage): what's the target?",
		"options": {"ten": "10, like a check.", "attacker": "The Save Target of whoever caused the damage, if anyone; otherwise 10."},
		"suggested": "ten", "rule_ref": "Core p.13 Saves, p.63 Flight"},
	"explosion_save_target": {
		"question": "Reactor explosions (meltdown, Self-Destruct) call for an Agility save: against what?",
		"options": {"mech_save_target": "The exploding mech's Save Target.", "ten": "10."},
		"suggested": "mech_save_target", "rule_ref": "Core p.72, p.81"},
	"npc_brace": {
		"question": "Can NPCs Brace? (The free core book has no NPC rules; lancer-data gives NPCs Overwatch, Ram and Grapple versions but no Brace.)",
		"options": {"no": "No.", "yes": "Yes, like mechs."},
		"suggested": "no", "rule_ref": "Core p.73 Brace"},
	"overwatch_area_weapons": {
		"question": "Can Overwatch use a Blast/Burst/Cone/Line weapon (a Skirmish against the moving character)?",
		"options": {"no": "No: only weapons that target a character.", "yes": "Yes, aimed at the moving character."},
		"suggested": "no", "rule_ref": "Core p.73 Overwatch, p.64 Patterns"},
	"slowed_jump": {
		"question": "Can a Slowed character jump? (Slowed: only the standard move; jumping is 'instead of' the standard move.)",
		"options": {"no": "No: a jump isn't the standard move.", "yes": "Yes: the jump replaces the standard move."},
		"suggested": "no", "rule_ref": "Core p.63 Jumping, p.78 Slowed"},
	"teleport_move_cost": {
		"question": "A standard move or Boost that teleports 'counts as moving 1 space' (Core p.63). How much movement does it use?",
		"options": {"whole_move": "The whole move; range is your Speed.", "one_space": "1 space of movement; range is your Speed, the rest can still be used."},
		"suggested": "whole_move", "rule_ref": "Core p.63 Teleportation"},
	"eject_distance": {
		"question": "Eject: 'flying 6 spaces in the direction of your choice' (Core p.71). Where can the pilot land?",
		"options": {"straight_six": "Exactly 6 spaces away, in a straight line in the chosen direction.", "within_six": "Any free space up to 6 spaces away."},
		"suggested": "straight_six", "rule_ref": "Core p.71 Eject"},
	"basilisk_failed_save": {
		"question": "Gorgon Basilisk: hostiles 'must succeed on a Systems save before attacking'. On a failure (Stunned), does the attack still happen?",
		"options": {"no_attack": "No: the save comes first, and a Stunned character can't attack.", "attack_continues": "Yes: the attack goes ahead, then the attacker is Stunned."},
		"suggested": "no_attack", "rule_ref": "Core p.77 Stunned; frames: Gorgon core system"},
	"prone_ignore_difficult": {
		"question": "Does 'ignore difficult terrain' (Bulwark Mods, Kai Bioplating) also cancel Prone's 'counts as moving in difficult terrain'?",
		"options": {"cancels": "Yes.", "still_double": "No: Prone still costs double."},
		"suggested": "cancels", "rule_ref": "Core p.77 Prone"},
}


static func choice(state: GameState, id: String) -> String:
	if state == null:
		return ""
	return String(state.rulings.get(id, {}).get("choice", ""))


static func decided(state: GameState, id: String) -> bool:
	return choice(state, id) != ""


static func suggested(id: String) -> String:
	return String(CATALOG.get(id, {}).get("suggested", ""))


## The choice if made, else the suggested reading (for previews only; actions ask first).
static func choice_or_suggested(state: GameState, id: String) -> String:
	var c := choice(state, id)
	return c if c != "" else suggested(id)


## For refusing an action until the table decides.
static func needed(id: String) -> RuleResult:
	var c: Dictionary = CATALOG[id]
	return RuleResult.ruling_needed(id, String(c["question"]), String(c["rule_ref"]), (c["options"] as Dictionary).keys())


## During resolution: the table's choice, or pause the action to ask (like a reaction).
## Outside RulesEngine.submit (tests, previews) the suggested reading is used.
static func ask(state: GameState, id: String) -> String:
	var c := choice(state, id)
	if c != "":
		return c
	var run := state.reaction_run
	if not run.is_empty() and (run.get("pending", {}) as Dictionary).is_empty():
		var info: Dictionary = CATALOG[id]
		run["pending"] = {"id": "ruling:" + id, "ruling": id, "unit": "", "reaction": "",
			"context": {"question": info["question"], "options": info["options"], "rule_ref": info["rule_ref"]}}
	return suggested(id)


## Every ruling, for a "table rules" screen.
static func catalog() -> Array:
	var out: Array = []
	for id: String in CATALOG:
		var c: Dictionary = CATALOG[id]
		out.append({"id": id, "question": c["question"], "options": c["options"], "suggested": c["suggested"], "rule_ref": c["rule_ref"]})
	return out


## Sets every undecided ruling to its suggested reading (e.g. "use the suggested table rules",
## or an AI GM making the call). Returns the ids it set.
static func apply_suggested(state: GameState) -> Array:
	var set: Array = []
	for id: String in CATALOG:
		if not decided(state, id):
			state.rulings[id] = {"choice": suggested(id), "by": "suggested"}
			set.append(id)
	return set


class SetRuling:
	extends ActionHandler
	## {"type": "set_ruling", "params": {"id", "choice"}} (no actor; the host/GM's call).

	func type() -> String:
		return "set_ruling"

	func needs_actor() -> bool:
		return false

	func validate(_state: GameState, action: Dictionary) -> RuleResult:
		var p: Dictionary = action.get("params", {})
		var id := String(p.get("id", ""))
		if not Rulings.CATALOG.has(id):
			return RuleResult.deny("Unknown ruling '%s'." % id, "")
		if not (Rulings.CATALOG[id]["options"] as Dictionary).has(String(p.get("choice", ""))):
			return RuleResult.deny("Pick one of: %s." % ", ".join((Rulings.CATALOG[id]["options"] as Dictionary).keys()), "")
		return RuleResult.allow()

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		var p: Dictionary = action["params"]
		state.rulings[p["id"]] = {"choice": p["choice"], "rule_ref": Rulings.CATALOG[p["id"]]["rule_ref"]}
		return [{"type": "ruling_made", "id": p["id"], "choice": p["choice"], "text": Rulings.CATALOG[p["id"]]["options"][p["choice"]]}] as Array[Dictionary]
