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


## Unit kinds that can take this action. Pilots on foot (Core p.74): Boost, Hide, Search,
## Activate, Skill Check, Disengage, Prepare, Mount, Overwatch (with Fight), Fight, Jockey,
## Reload; plus moving and jumping.
func kinds() -> Array:
	return [Unit.KIND_MECH, Unit.KIND_NPC]


## Pilot actions that only a mech's own pilot takes (soldiers don't climb into mechs).
const PILOT_ONLY := ["mount", "eject", "dismount", "self_destruct"]
const TECH_ACTIONS := ["quick_tech", "full_tech", "scan", "lock_on", "invade", "bolster"]


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
	# Soldiers on foot take the actions pilots on foot can (Core p.74), but never get into mechs.
	var as_kind := Unit.KIND_PILOT if u.on_foot() else u.kind
	if not kinds().has(as_kind) or (u.kind != Unit.KIND_PILOT and u.on_foot() and type() in PILOT_ONLY):
		var who := "People on foot" if u.on_foot() else ("Mechs" if u.kind == Unit.KIND_MECH else "This unit")
		var hint := " They attack with Fight." if u.on_foot() and type() in ["skirmish", "barrage"] else ""
		return RuleResult.deny("%s can't take this action (%s).%s" % [who, type(), hint], "Core p.74 Pilots in Mech Combat")
	if u.kind == Unit.KIND_NPC and u.biological() and type() in TECH_ACTIONS:
		return RuleResult.deny("Biological NPCs can't take tech actions.", "Core p.282 Biological")
	var params: Dictionary = action.get("params", {})
	if params.has("free_via") and Effects.grant(grant_holder(state, u, params), String(params["free_via"]), type(), cost() == TurnRules.QUICK).is_empty():
		return RuleResult.deny("That free action isn't available (used up, or doesn't cover %s)." % type(), Effects.REF)
	var c := _cost(params)
	if c != "move":
		r = TurnRules.can_spend(u, c, economy_name())
		if not r.ok:
			return r
	return check(state, u, params)


## Whose free-action grant (params.free_via) pays for this action: usually the actor.
func grant_holder(_state: GameState, u: Unit, _params: Dictionary) -> Unit:
	return u


func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
	var u := state.unit(action["actor"])
	var params: Dictionary = action.get("params", {})
	if type() != "bonus_move":
		u.turn.erase("bonus_move")  # an after-attack move has to be taken immediately
	var events := apply(state, u, params)
	if params.has("free_via"):
		var holder := grant_holder(state, u, params)
		Effects.use_grant(holder, Effects.grant(holder, String(params["free_via"]), type(), cost() == TurnRules.QUICK))
	var c := _cost(params)
	if u.turn.get("no_spend", false):
		u.turn.erase("no_spend")  # the action didn't happen (False Idol: they don't lose it)
	elif c != "move":
		TurnRules.spend(u, c, economy_name())
	return events


## A free-action grant (params.free_via, e.g. the Everest's Initiative) makes it free.
func _cost(params: Dictionary) -> String:
	return TurnRules.FREE if params.has("free_via") else cost_for(params)


static func cell_param(params: Dictionary, key: String) -> Variant:
	var v: Variant = params.get(key)
	if v is Array and (v as Array).size() >= 2:
		return Vector2i(int(v[0]), int(v[1]))
	if v is Vector2i:
		return v
	return null
