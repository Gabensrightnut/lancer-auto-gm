class_name TurnActions
extends RefCounted
## Starting combat, activating a unit, ending a turn. See TurnRules for the turn order.


class StartCombat:
	extends ActionHandler
	## {"type": "start_combat", "params": {"first_side": "players"}} (no actor; sent by the host)

	func type() -> String:
		return "start_combat"

	func needs_actor() -> bool:
		return false

	func validate(state: GameState, action: Dictionary) -> RuleResult:
		if state.phase == GameState.PHASE_COMBAT:
			return RuleResult.deny("Combat has already started.", TurnRules.REF_TURN_ORDER)
		var first: String = action.get("params", {}).get("first_side", "")
		var found := false
		for u: Unit in state.units.values():
			found = found or (u.side == first and TurnRules.takes_turns(u))
		if not found:
			return RuleResult.deny("Pick a side with units to go first.", TurnRules.REF_TURN_ORDER)
		var players_here := false
		for u: Unit in state.units.values():
			players_here = players_here or (u.side == "players" and TurnRules.takes_turns(u))
		if players_here and first != "players":
			return RuleResult.deny("Players always get to act first.", TurnRules.REF_TURN_ORDER)
		return RuleResult.allow()

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		return TurnRules.start_combat(state, action["params"]["first_side"])


class StartTurn:
	extends ActionHandler
	## {"type": "start_turn", "actor": unit} — the side whose pick it is chooses who acts.

	func type() -> String:
		return "start_turn"

	func validate(state: GameState, action: Dictionary) -> RuleResult:
		var u := state.unit(action["actor"])
		if state.phase != GameState.PHASE_COMBAT:
			return RuleResult.deny("Combat hasn't started.", TurnRules.REF_TURN_ORDER)
		if state.active_unit != "":
			return RuleResult.deny("Another unit is still taking its turn.", TurnRules.REF_TURN_ORDER)
		if not TurnRules.takes_turns(u):
			return RuleResult.deny("This unit doesn't take turns.", TurnRules.REF_TURN_ORDER)
		if state.acted.has(u.id):
			return RuleResult.deny("This unit has already acted this round.", TurnRules.REF_TURN_ORDER)
		if u.side != state.turn_side:
			return RuleResult.deny("It's the other side's pick: sides take turns activating units.", TurnRules.REF_TURN_ORDER)
		return RuleResult.allow()

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		return TurnRules.begin_turn(state, state.unit(action["actor"]))


class EndTurn:
	extends ActionHandler

	func type() -> String:
		return "end_turn"

	func validate(state: GameState, action: Dictionary) -> RuleResult:
		if state.active_unit != action.get("actor", ""):
			return RuleResult.deny("It isn't this unit's turn.", TurnRules.REF_TURN_ORDER)
		return RuleResult.allow()

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		return TurnRules.finish_turn(state, state.unit(action["actor"]))
