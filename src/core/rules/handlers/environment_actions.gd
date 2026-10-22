class_name EnvironmentActions
extends RefCounted
## Actions environments give (see Environments).


class BreakIce:
	extends TurnAction
	## Extreme cold: a quick action Hull save; success ends the Immobilized from freezing.

	func type() -> String:
		return "break_ice"

	func check(_state: GameState, u: Unit, _params: Dictionary) -> RuleResult:
		if not u.counters.has("env_cold"):
			return RuleResult.deny("You aren't frozen in place.", Environments.REF)
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, _params: Dictionary) -> Array[Dictionary]:
		var save := Combat.skill_check(state, u, "hull", "Break free of the ice: Hull save", Combat.CHECK_TARGET, 0, 0, [], true)
		var events: Array[Dictionary] = [{"type": "skill_check", "unit": u.id, "check": save, "rule_ref": Environments.REF}]
		if save["success"]:
			events.append_array(Environments.release(u, "cold"))
		return events


class DigOut:
	extends TurnAction
	## Sinking world: a full action Hull save by the sinking mech or a mech next to it;
	## success ends the effect. params: {"target": id (default: yourself)}

	func type() -> String:
		return "dig_out"

	func cost() -> String:
		return TurnRules.FULL

	func kinds() -> Array:
		return [Unit.KIND_MECH, Unit.KIND_NPC]

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var t := state.unit(String(params.get("target", u.id)))
		if t == null or not Environments.sinking(t):
			return RuleResult.deny("Choose a mech stuck in the mud.", Environments.REF)
		if t != u and Sight.unit_distance(state, u, t) > 1:
			return RuleResult.deny("Only a mech next to it can help it out.", Environments.REF)
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var t := state.unit(String(params.get("target", u.id)))
		var save := Combat.skill_check(state, u, "hull", "Dig out of the mud: Hull save", Combat.CHECK_TARGET, 0, 0, [], true)
		var events: Array[Dictionary] = [{"type": "skill_check", "unit": u.id, "check": save, "rule_ref": Environments.REF}]
		if save["success"]:
			events.append_array(Environments.release(t, "sinking"))
		return events
