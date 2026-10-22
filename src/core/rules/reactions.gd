class_name Reactions
extends RefCounted
## Reactions. For now only BRACE, taken automatically by a policy the player sets ahead of
## time with the "set_brace_policy" action ("never" or "on_structure": brace when a hit would
## take the last of your HP), because the engine has no "wait for the defender" step yet.
## The book's trigger is "you are hit by an attack and damage has been rolled", which is
## exactly when the policy is checked (actions: Brace).
##
## PROVISIONAL (docs/RULES_TODO.md "Reactions"): each reaction once per round, refreshed at
## the start of the unit's turn.

const REF_BRACE := "actions: Brace"


static func can_react(u: Unit, reaction: String) -> RuleResult:
	if u.destroyed:
		return RuleResult.deny("Destroyed.", "")
	if u.has_status("Stunned") or u.has_status("Shut Down"):
		return RuleResult.deny("Stunned mechs can't take reactions.", "statuses: Stunned")
	if u.has_status("Jammed"):
		return RuleResult.deny("Jammed characters can't take reactions.", "statuses: Jammed")
	if u.has_status("Braced"):
		return RuleResult.deny("After Bracing you can't take reactions until the end of your next turn.", REF_BRACE)
	if (u.counters.get("reactions", []) as Array).has(reaction):
		return RuleResult.deny("You've already used that reaction this round.", "PROVISIONAL Core: Reactions (docs/RULES_TODO.md)")
	return RuleResult.allow()


## BRACE: resistance to the triggering attack's damage, burn and heat (applied by the caller),
## +1 Difficulty on other attacks against you and no reactions until the end of your next
## turn, and next turn only one quick action.
static func brace(state: GameState, u: Unit, attacker: String) -> Array[Dictionary]:
	var used: Array = u.counters.get("reactions", [])
	used.append("brace")
	u.counters["reactions"] = used
	u.counters["brace_next_turn"] = true
	var events: Array[Dictionary] = [{"type": "reaction", "unit": u.id, "reaction": "brace", "trigger": attacker, "rule_ref": REF_BRACE}]
	events.append_array(Combat.add_status(state, u, "Braced", "Brace", u.id))
	if u.has_status("Hidden"):
		events.append_array(Combat.remove_status(u, "Hidden", "took a reaction"))
	return events
