class_name Reactions
extends RefCounted
## Reactions, and how the engine asks a defender whether to take one.
##
## When something triggers a reaction (a hostile starts moving in your THREAT: Overwatch; you
## are hit and damage has been rolled: Brace), the rules call offer(). What happens depends
## on the unit's policy for that reaction (counters["reaction_policy"][reaction]):
## - "ask" (default for player-controlled units): the engine stops, rewinds the action to
##   where it started, and sends a `reaction_offered` event. The unit's controller answers
##   with {"type": "react", "actor": unit, "params": {"take": bool, ...}} and the engine
##   replays the action from the start with the same dice, now using that answer.
## - "auto" (default for GM units, until the GM AI decides): the offering rule's default.
## - "never", or "on_structure" for Brace (only when the hit would take the last HP).
##
## PROVISIONAL (docs/RULES_TODO.md "Reactions"): each reaction once per round, refreshed at
## the start of the unit's turn; NPCs have no Brace (lancer-data has NPC versions of Overwatch
## but not of Brace).

const REF_BRACE := "actions: Brace"
const REF_OVERWATCH := "actions: Overwatch"
const POLICIES := ["ask", "auto", "never", "on_structure"]


static func policy(u: Unit, reaction: String) -> String:
	var set: Dictionary = u.counters.get("reaction_policy", {})
	if set.has(reaction):
		return set[reaction]
	if reaction == "brace" and u.counters.has("brace_policy"):
		return u.counters["brace_policy"]
	return "auto" if u.controller == "gm" else "ask"


## Asks `u` whether to take `reaction`. `auto` is the answer used under the "auto" policy.
## Returns the decision, e.g. {"take": true, "weapon": "0:0"}.
static func offer(state: GameState, u: Unit, reaction: String, context: Dictionary, auto: Dictionary) -> Dictionary:
	var run := state.reaction_run
	match policy(u, reaction):
		"never":
			return {"take": false}
		"auto", "on_structure":
			return auto
	if run.is_empty():
		return auto  # called outside RulesEngine.submit (direct rules calls in tests/tools)
	var n := int(run.get("count", 0))
	run["count"] = n + 1
	var id := "%s:%s:%d" % [reaction, u.id, n]
	var decisions: Dictionary = run.get("decisions", {})
	if decisions.has(id):
		return decisions[id]
	if (run.get("pending", {}) as Dictionary).is_empty():
		run["pending"] = {"id": id, "unit": u.id, "reaction": reaction, "context": context}
	return {"take": false}


static func can_react(u: Unit, reaction: String) -> RuleResult:
	if not Combat.is_present(u):
		return RuleResult.deny("Not on the field.", "")
	if u.has_status("Stunned") or u.has_status("Shut Down"):
		return RuleResult.deny("Stunned mechs can't take reactions.", "statuses: Stunned")
	if u.has_status("Jammed"):
		return RuleResult.deny("Jammed characters can't take reactions.", "statuses: Jammed")
	if u.has_status("Braced"):
		return RuleResult.deny("After Bracing you can't take reactions until the end of your next turn.", REF_BRACE)
	if u.counters.has("grapple"):
		return RuleResult.deny("Grappling characters can't take reactions.", "actions: Grapple")
	if u.counters.has("prepared"):
		return RuleResult.deny("Holding a prepared action: no other reactions until it triggers.", "actions: Prepare")
	if reaction == "brace" and u.kind == Unit.KIND_NPC:
		return RuleResult.deny("NPCs don't Brace.", REF_BRACE)
	if (u.counters.get("reactions", []) as Array).has(reaction):
		return RuleResult.deny("You've already used that reaction this round.", "PROVISIONAL Core: Reactions (docs/RULES_TODO.md)")
	return RuleResult.allow()


static func _mark_used(u: Unit, reaction: String) -> void:
	var used: Array = u.counters.get("reactions", [])
	used.append(reaction)
	u.counters["reactions"] = used


## BRACE: resistance to the triggering attack's damage, burn and heat (applied by the caller),
## +1 Difficulty on other attacks against you and no reactions until the end of your next
## turn, and next turn only one quick action.
static func brace(state: GameState, u: Unit, attacker: String) -> Array[Dictionary]:
	_mark_used(u, "brace")
	u.counters["brace_next_turn"] = true
	var events: Array[Dictionary] = [{"type": "reaction", "unit": u.id, "reaction": "brace", "trigger": attacker, "rule_ref": REF_BRACE}]
	events.append_array(Combat.add_status(state, u, "Braced", "Brace", u.id))
	if u.has_status("Hidden"):
		events.append_array(Combat.remove_status(u, "Hidden", "took a reaction"))
	return events


## Weapons `u` could Overwatch `mover` with right now: in THREAT, not Ordnance or Superheavy.
static func overwatch_weapons(state: GameState, u: Unit, mover: Unit) -> Array[String]:
	var out: Array[String] = []
	var dist := Sight.unit_distance(state, u, mover)
	for w: Dictionary in u.loadout.get("weapons", []):
		if Weapons.threat(w) < dist or Weapons.has_tag(w, "tg_ordnance") or w.get("size", "") == "Superheavy" or Weapons.area(w) != "":
			continue
		if Attacks.preview(state, u, w, mover)["ok"]:
			out.append(String(w["key"]))
	return out


## OVERWATCH: hostiles whose THREAT the mover starts a move in may Skirmish it first, as a
## reaction (actions: Overwatch; tags: Ordnance can't Overwatch). Returns events.
static func overwatch(state: GameState, mover: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if mover.turn.get("disengaged", false):
		return events  # Disengage: movement doesn't provoke reactions.
	var ids := Movement.threatened_by(state, mover)
	ids.sort()
	for id in ids:
		var h := state.unit(id)
		if not can_react(h, "overwatch").ok or not Combat.is_present(mover) or mover.destroyed:
			continue
		var weapons := overwatch_weapons(state, h, mover)
		if weapons.is_empty():
			continue
		var d := offer(state, h, "overwatch", {"mover": mover.id, "weapons": weapons}, {"take": true, "weapon": weapons[0]})
		if not d.get("take", false):
			continue
		var key := String(d.get("weapon", weapons[0]))
		if not weapons.has(key):
			key = weapons[0]
		_mark_used(h, "overwatch")
		events.append({"type": "reaction", "unit": h.id, "reaction": "overwatch", "trigger": mover.id, "weapon": key, "rule_ref": REF_OVERWATCH})
		events.append_array(Attacks.attack(state, h, Weapons.find(h, key), mover, {}))
	return events
