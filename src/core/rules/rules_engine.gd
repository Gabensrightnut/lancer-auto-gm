class_name RulesEngine
extends RefCounted
## The only way to change a GameState during play. Everything (players, the procedural GM,
## network clients) submits actions here; illegal actions are refused with a reason.
## Read-only questions (movement arrow, cover, hit chance) go through RulesQueries.
##
## Note for callers: the engine checks the rules, not who sent the action. The host must
## check that the sending seat controls `actor` (Unit.controller) before submitting.

var _handlers: Dictionary = {}  # type -> ActionHandler


func _init() -> void:
	for h: ActionHandler in [
		TurnActions.StartCombat.new(), TurnActions.StartTurn.new(), TurnActions.EndTurn.new(),
		MoveActions.Move.new(), MoveActions.Boost.new(), MoveActions.StandUp.new(),
		MoveActions.Disengage.new(),
		AttackActions.Skirmish.new(), AttackActions.Barrage.new(), AttackActions.Improvised.new(),
		TechActions.Scan.new(), TechActions.LockOn.new(), TechActions.Invade.new(),
		SystemActions.Overcharge.new(), SystemActions.Stabilize.new(), SystemActions.Hide.new(),
		SystemActions.Search.new(), SystemActions.ShutDown.new(), SystemActions.BootUp.new(),
		SystemActions.SetBracePolicy.new(),
	]:
		register(h)


func register(handler: ActionHandler) -> void:
	assert(not _handlers.has(handler.type()), "duplicate action type " + handler.type())
	_handlers[handler.type()] = handler


func has_action(type: String) -> bool:
	return _handlers.has(type)


func action_types() -> Array:
	return _handlers.keys()


func validate(state: GameState, action: Dictionary) -> RuleResult:
	var handler: ActionHandler = _handlers.get(action.get("type", ""))
	if handler == null:
		return RuleResult.deny("Unknown action '%s'." % action.get("type", ""), "")
	if handler.needs_actor():
		var actor: Unit = state.unit(action.get("actor", ""))
		if actor == null:
			return RuleResult.deny("No such unit.", "")
	if not action.get("params", {}) is Dictionary:
		return RuleResult.deny("Action params must be a dictionary.", "")
	return handler.validate(state, action)


## Validates, then resolves. Returns {"result": RuleResult, "events": Array[Dictionary]}.
## A grey area is not applied until a ruling exists in state.rulings.
func submit(state: GameState, action: Dictionary) -> Dictionary:
	var result := validate(state, action)
	if not result.ok or (result.grey_area != "" and not state.rulings.has(result.grey_area)):
		return {"result": result, "events": [] as Array[Dictionary]}
	var handler: ActionHandler = _handlers[action["type"]]
	return {"result": result, "events": handler.resolve(state, action)}
