class_name GearActions
extends RefCounted
## Actions that gear gives to characters other than its owner.


class AIControl:
	extends TurnAction
	## Protocol: hand the controls to your AI, or take them back at the start of a later turn
	## (Core p.107). params: {"take_back": bool}

	func type() -> String:
		return "ai_control"

	func kinds() -> Array:
		return [Unit.KIND_MECH]

	func cost() -> String:
		return TurnRules.FREE

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		if u.turn.get("acted", false) or u.turn.get("moved", false):
			return RuleResult.deny("A protocol: only at the start of your turn.", "tags: Protocol")
		if params.get("take_back", false):
			return AISystems.check_take_back(state, u)
		if not AISystems.has_ai(u):
			return RuleResult.deny("This mech has no AI system.", AISystems.REF)
		if AISystems.controlled(u):
			return RuleResult.deny("The AI already has control.", AISystems.REF)
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		if params.get("take_back", false):
			return AISystems.take_back(state, u, "pilot")
		return AISystems.hand_over(state, u, String(u.loadout["ai"]["source"]))


class PullStake:
	extends TurnAction
	## Full action: an impaled character repeats the Hull save to remove a Charged Stake.

	func type() -> String:
		return "pull_stake"

	func cost() -> String:
		return TurnRules.FULL

	func check(_state: GameState, u: Unit, _params: Dictionary) -> RuleResult:
		if not u.counters.has("impaled"):
			return RuleResult.deny("You aren't impaled.", "systems: Charged Stake")
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, _params: Dictionary) -> Array[Dictionary]:
		var imp: Dictionary = u.counters["impaled"]
		var save := Combat.skill_check(state, u, "hull", "Pull out the stake", int(imp.get("save_target", 10)), 0, 0, [], true)
		var events: Array[Dictionary] = [{"type": "skill_check", "unit": u.id, "check": save, "rule_ref": "systems: Charged Stake"}]
		if save["success"]:
			events.append_array(GearSystems.unimpale(u, "pulled free"))
		return events


class ShakeOff:
	extends TurnAction
	## Full action: a Systems save to end Chains of Prometheus or Excommunicate.
	## params: {"what": "chains" | "excommunicate"}

	func type() -> String:
		return "shake_off"

	func cost() -> String:
		return TurnRules.FULL

	func check(_state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var what := String(params.get("what", ""))
		if not what in ["chains", "excommunicate"] or not u.counters.has(what):
			return RuleResult.deny("Nothing like that is affecting you.", "systems: Aggressive System Sync")
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var what := String(params["what"])
		var save := Combat.skill_check(state, u, "systems", "Shake off %s" % what.capitalize(), int(u.counters[what].get("save_target", 10)), 0, 0, [], true)
		var events: Array[Dictionary] = [{"type": "skill_check", "unit": u.id, "check": save, "rule_ref": "systems: Aggressive System Sync"}]
		if save["success"]:
			u.counters.erase(what)
			events.append({"type": "effect_ended", "unit": u.id, "effect": what.capitalize(), "reason": "saved"})
		return events


class UseObject:
	extends TurnAction
	## Quick action: use an adjacent allied object that allows it (Restock Drone).
	## params: {"object": id, "condition": status to clear, "weapon": Loading weapon to reload}

	func type() -> String:
		return "use_object"

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var o := state.unit(String(params.get("object", "")))
		if o == null or o.destroyed or not o.counters.has("interact"):
			return RuleResult.deny("Choose an object you can use.", Abilities.REF)
		if o.side != u.side:
			return RuleResult.deny("Only allied characters can use it.", Abilities.REF)
		if Sight.unit_distance(state, u, o) > 1:
			return RuleResult.deny("It must be adjacent.", Abilities.REF)
		if int(o.counters.get("used_round", -1)) == state.round_number:
			return RuleResult.deny("It's already been used this round.", Abilities.REF)
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var o := state.unit(String(params["object"]))
		var events: Array[Dictionary] = []
		for op: Dictionary in o.counters["interact"]:
			if op.get("op", "") == "restock":
				events.append_array(GearSystems.restock(state, u, o, params))
			if op.get("op", "") == "reload":
				# Autoloader Drone: 1/round, an adjacent character reloads a Loading weapon.
				o.counters["used_round"] = state.round_number
				events.append_array(GearSystems.reload_one(state, u, String(params.get("weapon", "")), o.name))
		return events
