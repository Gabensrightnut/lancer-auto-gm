class_name SeatEngine
extends RulesEngine
## A RulesEngine stand-in for the turn UI (PlayerTurn): checks and previews run on the seat's
## own picture of the battle (ViewMirror), but submit() sends the action to the host through
## the network layer, so seat checks, every other player's update, the AI, mission scoring
## and autosave all happen as for any action.
##
## Host side: answers at once with the host's result and events.
## Online client: the answer comes later from the host; submit() returns "sent" with no events
## and the events arrive with the next view update (and refusals via `refused`).

signal refused(reason: String, rule_ref: String)

var host: NetHost
var client: NetClient
var seat := ""
## Set while our own action is being submitted on the host, so the session doesn't play its
## events twice (PlayerTurn plays them itself).
var submitting := false


func submit(_state: GameState, action: Dictionary) -> Dictionary:
	if host != null:
		submitting = true
		var out := host.submit(seat, action)
		submitting = false
		return out
	if client != null:
		client.submit(action)
		return {"result": RuleResult.allow(), "events": []}
	return {"result": RuleResult.deny("Not connected to a game.", ""), "events": []}
