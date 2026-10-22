class_name RulesEngine
extends RefCounted
## The only way to change a GameState during play. Everything (players, the procedural GM,
## network clients) submits actions here; illegal actions are refused with a reason.

var _handlers: Dictionary = {}  # type -> ActionHandler


func _init() -> void:
	register(EndTurnHandler.new())


func register(handler: ActionHandler) -> void:
	assert(not _handlers.has(handler.type()), "duplicate action type " + handler.type())
	_handlers[handler.type()] = handler


func has_action(type: String) -> bool:
	return _handlers.has(type)


func validate(state: GameState, action: Dictionary) -> RuleResult:
	var handler: ActionHandler = _handlers.get(action.get("type", ""))
	if handler == null:
		return RuleResult.deny("Unknown action '%s'." % action.get("type", ""), "")
	var actor: Unit = state.unit(action.get("actor", ""))
	if actor == null:
		return RuleResult.deny("No such unit.", "")
	return handler.validate(state, action)


## Validates, then resolves. Returns {"result": RuleResult, "events": Array[Dictionary]}.
## A grey area is not applied until a ruling exists in state.rulings.
func submit(state: GameState, action: Dictionary) -> Dictionary:
	var result := validate(state, action)
	if not result.ok or (result.grey_area != "" and not state.rulings.has(result.grey_area)):
		return {"result": result, "events": [] as Array[Dictionary]}
	var handler: ActionHandler = _handlers[action["type"]]
	return {"result": result, "events": handler.resolve(state, action)}


## Example handler showing the pattern. The full turn order rules belong to the rules engine work.
class EndTurnHandler:
	extends ActionHandler

	func type() -> String:
		return "end_turn"

	func validate(state: GameState, action: Dictionary) -> RuleResult:
		if state.active_unit != action.get("actor", ""):
			return RuleResult.deny("It isn't this unit's turn.", "Core: Turn order")
		return RuleResult.allow()

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		var actor: String = action["actor"]
		state.acted.append(actor)
		state.active_unit = ""
		return [{"type": "turn_ended", "unit": actor}] as Array[Dictionary]
