class_name TurnAction
extends ActionHandler
## Base for actions a unit takes on its own turn. Checks whose turn it is and the action
## economy (TurnRules), then the action's own rules in check(); resolve() records the action
## as taken and calls apply().


## TurnRules.QUICK, FULL or FREE (moves use "move").
func cost() -> String:
	return TurnRules.QUICK


## Cost for these params (e.g. Fight is quick with a Sidearm). Defaults to cost().
func cost_for(_params: Dictionary) -> String:
	return cost()


## Name recorded in the turn's taken-actions list (repeats are refused). Defaults to type().
func economy_name() -> String:
	return type()


## Unit kinds that can take this action. Pilots on foot have their own list (actions.json
## marks pilot actions): Move, Hide, Search, Prepare, Fight, Mount, Jump, Overwatch.
func kinds() -> Array:
	return [Unit.KIND_MECH, Unit.KIND_NPC]


## The action's own rules. Must not change state.
func check(_state: GameState, _u: Unit, _params: Dictionary) -> RuleResult:
	return RuleResult.allow()


## Changes state. Returns events.
func apply(_state: GameState, _u: Unit, _params: Dictionary) -> Array[Dictionary]:
	return []


func validate(state: GameState, action: Dictionary) -> RuleResult:
	var u := state.unit(action.get("actor", ""))
	var r := TurnRules.check_own_turn(state, u)
	if not r.ok:
		return r
	if not kinds().has(u.kind):
		var who := "Pilots on foot" if u.kind == Unit.KIND_PILOT else ("Mechs" if u.kind == Unit.KIND_MECH else "This unit")
		return RuleResult.deny("%s can't take this action (%s)." % [who, type()], "actions.json")
	var params: Dictionary = action.get("params", {})
	if cost_for(params) != "move":
		r = TurnRules.can_spend(u, cost_for(params), economy_name())
		if not r.ok:
			return r
	return check(state, u, params)


func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
	var u := state.unit(action["actor"])
	var params: Dictionary = action.get("params", {})
	var events := apply(state, u, params)
	if cost_for(params) != "move":
		TurnRules.spend(u, cost_for(params), economy_name())
	return events


static func cell_param(params: Dictionary, key: String) -> Variant:
	var v: Variant = params.get(key)
	if v is Array and (v as Array).size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	if v is Vector2i:
		return v
	return null
