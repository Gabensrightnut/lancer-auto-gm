class_name RulesEngine
extends RefCounted
## The only way to change a GameState during play. Everything (players, the procedural GM,
## network clients) submits actions here; illegal actions are refused with a reason.
## Read-only questions (movement arrow, cover, hit chance) go through RulesQueries.
##
## Note for callers: the engine checks the rules, not who sent the action. The host must
## check that the sending seat controls `actor` (Unit.controller) before submitting.

var _handlers: Dictionary = {}  # type -> ActionHandler
## type -> handler, shared, for rules that run another action (Prepare, Full Tech).
static var registry: Dictionary = {}


func _init() -> void:
	for h: ActionHandler in [
		TurnActions.StartCombat.new(), TurnActions.StartTurn.new(), TurnActions.EndTurn.new(),
		MoveActions.Move.new(), MoveActions.Boost.new(), MoveActions.StandUp.new(),
		MoveActions.Disengage.new(),
		AttackActions.Skirmish.new(), AttackActions.Barrage.new(), AttackActions.Improvised.new(),
		TechActions.Scan.new(), TechActions.LockOn.new(), TechActions.Invade.new(),
		SystemActions.Overcharge.new(), SystemActions.Stabilize.new(), SystemActions.Hide.new(),
		SystemActions.Search.new(), SystemActions.ShutDown.new(), SystemActions.BootUp.new(),
		SystemActions.SetBracePolicy.new(), SystemActions.SetReactionPolicy.new(),
		CloseCombat.Ram.new(), CloseCombat.Grapple.new(), CloseCombat.EndGrapple.new(),
		CloseCombat.BreakFree.new(), CloseCombat.Jump.new(),
		TechActions.Bolster.new(), TechActions.FullTech.new(),
		PilotActions.Eject.new(), PilotActions.Dismount.new(), PilotActions.Mount.new(),
		PilotActions.Fight.new(), PilotActions.SelfDestruct.new(), PilotActions.Prepare.new(),
		PilotActions.DropPrepared.new(), SystemActions.CorePower.new(), MoveActions.BonusMove.new(),
		Rulings.SetRuling.new(), CloseCombat.GrappleContest.new(), AbilityActions.Activate.new(),
		RestActions.Rest.new(), GearActions.AIControl.new(), GearActions.ClimbOn.new(), GearActions.Board.new(), GearActions.Disembark.new(), GearActions.CutCable.new(), GearActions.PullStake.new(), GearActions.UseObject.new(), GearActions.ShakeOff.new(),
	]:
		register(h)


func register(handler: ActionHandler) -> void:
	assert(not _handlers.has(handler.type()), "duplicate action type " + handler.type())
	_handlers[handler.type()] = handler
	registry[handler.type()] = handler


func has_action(type: String) -> bool:
	return _handlers.has(type)


func action_types() -> Array:
	return _handlers.keys()


func validate(state: GameState, action: Dictionary) -> RuleResult:
	TurnRules._state_ref = weakref(state)
	Combat.state_for_presence = weakref(state)
	var handler: ActionHandler = _handlers.get(action.get("type", ""))
	if handler == null:
		return RuleResult.deny("Unknown action '%s'." % action.get("type", ""), "")
	if handler.needs_actor():
		var actor: Unit = state.unit(action.get("actor", ""))
		if actor == null:
			return RuleResult.deny("No such unit.", "")
		var limit := FrameSystems.action_allowed(state, actor, String(action.get("type", "")))
		if not limit.ok:
			return limit
		limit = AISystems.action_allowed(actor, String(action.get("type", "")))
		if not limit.ok:
			return limit
	if not action.get("params", {}) is Dictionary:
		return RuleResult.deny("Action params must be a dictionary.", "")
	return handler.validate(state, action)


## Validates, then resolves. Returns {"result": RuleResult, "events": Array[Dictionary]}.
## A grey area is not applied until a ruling exists in state.rulings.
##
## Reactions: if resolving offers a reaction to a unit whose policy is "ask", nothing is
## applied: the state is rewound, `state.pending` records the question, and the only event
## is `reaction_offered`. That unit's controller answers with
## {"type": "react", "actor": unit, "params": {"take": bool, ...}}; the action then replays
## from the start with the same dice and the answer (see Reactions).
func submit(state: GameState, action: Dictionary) -> Dictionary:
	if not state.pending.is_empty():
		return _answer(state, action)
	var result := validate(state, action)
	if not result.ok or (result.grey_area != "" and not state.rulings.has(result.grey_area)):
		return {"result": result, "events": [] as Array[Dictionary]}
	return _run(state, action, {}, result)


func _answer(state: GameState, action: Dictionary) -> Dictionary:
	var p := state.pending
	if p.has("ruling"):
		# Paused for a table ruling: only set_ruling for that question goes through.
		if action.get("type", "") != "set_ruling" or action.get("params", {}).get("id", "") != p["ruling"]:
			var wait := RuleResult.deny("Waiting for the table to decide: %s" % p["context"]["question"], String(p["context"]["rule_ref"]))
			return {"result": wait, "events": [] as Array[Dictionary]}
		var r := validate_ruling(state, action)
		if not r.ok:
			return {"result": r, "events": [] as Array[Dictionary]}
		var made: Array[Dictionary] = _handlers["set_ruling"].resolve(state, action)
		var paused: Dictionary = p["action"]
		var earlier: Dictionary = p.get("decisions", {})
		state.pending = {}
		var out := _run(state, paused, earlier, RuleResult.allow())
		var events: Array[Dictionary] = made.duplicate()
		events.append_array(out["events"])
		out["events"] = events
		return out
	var who := state.unit(p["unit"])
	var name := who.name if who != null and who.name != "" else String(p["unit"])
	if action.get("type", "") != "react" or action.get("actor", "") != p["unit"]:
		var no := RuleResult.deny("Waiting for %s to decide whether to %s." % [name, String(p["reaction"]).capitalize()], "actions: Reactions")
		return {"result": no, "events": [] as Array[Dictionary]}
	var params: Variant = action.get("params", {})
	if not params is Dictionary or not (params as Dictionary).has("take"):
		var bad := RuleResult.deny("Answer with params.take = true or false.", "")
		return {"result": bad, "events": [] as Array[Dictionary]}
	var decisions: Dictionary = (p.get("decisions", {}) as Dictionary).duplicate(true)
	decisions[p["id"]] = params
	var original: Dictionary = p["action"]
	state.pending = {}
	return _run(state, original, decisions, RuleResult.allow())


func validate_ruling(state: GameState, action: Dictionary) -> RuleResult:
	return _handlers["set_ruling"].validate(state, action)


func _run(state: GameState, action: Dictionary, decisions: Dictionary, result: RuleResult) -> Dictionary:
	var snap := _snapshot(state)
	state.reaction_run = {"decisions": decisions, "count": 0, "pending": {}}
	var handler: ActionHandler = _handlers[action["type"]]
	var events := handler.resolve(state, action)
	var asked: Dictionary = state.reaction_run.get("pending", {})
	state.reaction_run = {}
	if asked.is_empty():
		return {"result": result, "events": events}
	_restore(state, snap)
	var pending := asked.duplicate(true)
	pending["action"] = action
	pending["decisions"] = decisions
	pending["snapshot"] = snap
	state.pending = pending
	if asked.has("ruling"):
		var question: Array[Dictionary] = [{"type": "ruling_needed", "id": asked["ruling"],
			"question": asked["context"]["question"], "options": asked["context"]["options"],
			"rule_ref": asked["context"]["rule_ref"], "trigger_action": action.get("type", "")}]
		return {"result": result, "events": question}
	var offered: Array[Dictionary] = [{"type": "reaction_offered", "id": asked["id"], "unit": asked["unit"],
		"reaction": asked["reaction"], "context": asked["context"], "trigger_action": action.get("type", ""),
		"rule_ref": "actions: " + String(asked["reaction"]).capitalize()}]
	return {"result": result, "events": offered}


func _snapshot(state: GameState) -> Dictionary:
	var snap := state.to_dict()
	if state.dice.has_method("checkpoint"):
		snap["dice_checkpoint"] = state.dice.call("checkpoint")
	return snap


## Puts `state` back to `snap` in place (same GameState and Unit objects, so references
## held elsewhere stay valid).
func _restore(state: GameState, snap: Dictionary) -> void:
	var fresh := GameState.from_dict(snap)
	state.map = fresh.map
	for id: String in state.units.keys():
		if not fresh.units.has(id):
			state.units.erase(id)
	for id: String in fresh.units:
		var src: Unit = fresh.units[id]
		if not state.units.has(id):
			state.units[id] = src
			continue
		var dst: Unit = state.units[id]
		for key: String in src.to_dict():
			dst.set(key, src.get(key))
	for key in ["round_number", "phase", "active_unit", "acted", "turn_side", "first_side", "intel", "rulings", "seats", "zones"]:
		state.set(key, fresh.get(key))
	state.dice.set_state(String(snap["dice_state"]).to_int())
	if snap.has("dice_checkpoint"):
		state.dice.call("rewind", snap["dice_checkpoint"])
