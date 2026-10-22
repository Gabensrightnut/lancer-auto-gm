class_name ActionHandler
extends RefCounted
## One kind of action (Move, Skirmish, Boost, Hide...). Subclass, register with RulesEngine.
##
## An action is a plain Dictionary so it can travel over the network:
##   {"type": "move", "actor": "unit_id", "params": {...}}
## Handlers never touch rendering or networking. They check legality and produce events.

## Action type string, e.g. "move". Must be unique.
func type() -> String:
	return ""


## Is this action legal right now? Must not change `state`.
func validate(_state: GameState, _action: Dictionary) -> RuleResult:
	return RuleResult.deny("not implemented", "")


## Apply a validated action. Changes `state` and returns the events that happened, in order.
## Every roll must use state.dice. See docs/ARCHITECTURE.md for event shapes.
func resolve(_state: GameState, _action: Dictionary) -> Array[Dictionary]:
	return []
