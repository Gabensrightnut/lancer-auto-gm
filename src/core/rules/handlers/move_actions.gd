class_name MoveActions
extends RefCounted
## Standard move, Boost, standing up from Prone, Disengage.
## params for move/boost: {"to": [x, y], "level": int (optional), "fly": bool}


static func _can_move_voluntarily(u: Unit) -> RuleResult:
	if u.has_status("Stunned"):
		return RuleResult.deny("Stunned mechs can't move.", "statuses: Stunned")
	if u.has_status("Immobilized"):
		return RuleResult.deny("Immobilized: no voluntary movement.", "statuses: Immobilized")
	return RuleResult.allow()


static func _plan(state: GameState, u: Unit, params: Dictionary, mode: String) -> Dictionary:
	var to: Variant = TurnAction.cell_param(params, "to")
	if to == null:
		return {"ok": false, "reason": "Say where to move (params.to = [x, y]).", "rule_ref": Movement.REF_MOVE}
	return Movement.plan(state, u, to, int(params.get("level", -1)), mode, bool(params.get("fly", false)))


static func _plan_result(plan: Dictionary) -> RuleResult:
	if not plan["ok"]:
		return RuleResult.deny(plan["reason"], plan["rule_ref"])
	if plan.get("grey_area", "") != "":
		return RuleResult.ruling_needed(Movement.RULING_UNEVEN,
			"Can a big mech stand across uneven ground (some of its spaces higher than others)? The book doesn't say.",
			Movement.REF_PROVISIONAL, ["allow", "forbid"])
	return RuleResult.allow()


## Moves along a planned path and applies everything that follows.
static func _do_move(state: GameState, u: Unit, plan: Dictionary, mode: String, fly: bool) -> Array[Dictionary]:
	var path: Array = plan["path"]
	var last: Array = path.back()
	u.cell = Vector2i(last[0], last[1])
	u.level = int(last[2])
	u.turn["moved"] = true
	var placed := Movement.placement(state, u.size, u.cell, u.level)
	u.flying = fly and not placed["standing"] and not placed["uneven"]
	var anim := "fly" if fly else mode
	var events: Array[Dictionary] = [{"type": "moved", "unit": u.id, "path": path, "mode": anim,
		"cost": plan["cost"], "stopped_by": plan["stopped_by"], "rule_ref": Movement.REF_MOVE}]
	if plan["stopped_by"] != "":
		events.append({"type": "movement_stopped", "unit": u.id, "by": plan["stopped_by"],
			"reason": "Became Engaged with an equal or larger hostile: movement ends.", "rule_ref": Movement.REF_ENGAGED})
	for w: Dictionary in plan["warnings"]:
		if w["type"] == "dangerous":
			var col := state.map.column(Vector2i(w["at"][0], w["at"][1]))
			var dtype := "Kinetic"
			for t in ["Energy", "Explosive", "Burn"]:
				if col != null and col.has_tag("dangerous_" + t.to_lower()):
					dtype = t
			events.append_array(Combat.dangerous_roll(state, u, dtype))
			break
	events.append_array(Combat.after_movement(state))
	return events


class Move:
	extends TurnAction
	## Standard move: up to SPEED, may be split around other actions (PROVISIONAL).

	func type() -> String:
		return "move"

	func cost() -> String:
		return "move"

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var r := MoveActions._can_move_voluntarily(u)
		if not r.ok:
			return r
		if u.turn.get("braced", false):
			return RuleResult.deny("After Bracing you can't move normally this turn.", TurnRules.REF_BRACE)
		if u.turn.get("stood_up", false) or Movement.budget(u, Movement.MODE_MOVE) <= 0:
			return RuleResult.deny("You've used your standard move this turn (Boost to move again).", Movement.REF_MOVE)
		return MoveActions._plan_result(MoveActions._plan(state, u, params, Movement.MODE_MOVE))

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var plan := MoveActions._plan(state, u, params, Movement.MODE_MOVE)
		u.turn["move_spent"] = int(u.turn.get("move_spent", 0)) + int(plan["cost"])
		if plan["stopped_by"] != "":
			u.turn["move_spent"] = u.speed  # lose any unused movement (statuses: Engaged)
		return MoveActions._do_move(state, u, plan, "walk", bool(params.get("fly", false)))


class Boost:
	extends TurnAction
	## Quick action: move at least 1 space, up to SPEED (actions: Boost).

	func type() -> String:
		return "boost"

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var r := MoveActions._can_move_voluntarily(u)
		if not r.ok:
			return r
		if u.has_status("Slowed") or u.has_status("Prone"):
			return RuleResult.deny("Slowed (Prone characters are Slowed too): your only movement is your standard move, so no Boost.", "statuses: Slowed, Prone")
		if u.counters.get("grappled", false):
			return RuleResult.deny("Grappling characters can't Boost.", "actions: Grapple")
		return MoveActions._plan_result(MoveActions._plan(state, u, params, Movement.MODE_BOOST))

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var plan := MoveActions._plan(state, u, params, Movement.MODE_BOOST)
		var events := MoveActions._do_move(state, u, plan, "boost", bool(params.get("fly", false)))
		if u.has_status("Hidden"):
			# Using BOOST removes HIDDEN after it resolves (statuses: Hidden).
			events.append_array(Combat.remove_status(u, "Hidden", "boosted"))
			events.append_array(Combat.refresh_engagement(state))
		return events


class StandUp:
	extends TurnAction
	## Remove PRONE instead of taking your standard move; not movement (statuses: Prone).

	func type() -> String:
		return "stand_up"

	func cost() -> String:
		return "move"

	func check(_state: GameState, u: Unit, _params: Dictionary) -> RuleResult:
		if not u.has_status("Prone"):
			return RuleResult.deny("You aren't Prone.", "statuses: Prone")
		if u.has_status("Immobilized"):
			return RuleResult.deny("Immobilized characters can't stand up.", "statuses: Prone")
		if u.has_status("Stunned"):
			return RuleResult.deny("Stunned mechs can't take actions.", "statuses: Stunned")
		if int(u.turn.get("move_spent", 0)) > 0:
			return RuleResult.deny("Standing up takes the place of your standard move, and you've already moved.", "statuses: Prone")
		return RuleResult.allow()

	func apply(_state: GameState, u: Unit, _params: Dictionary) -> Array[Dictionary]:
		u.turn["move_spent"] = u.speed
		u.turn["stood_up"] = true
		return Combat.remove_status(u, "Prone", "stood up")


class Disengage:
	extends TurnAction
	## Full action: until the end of this turn, ignore engagement and don't provoke reactions.

	func type() -> String:
		return "disengage"

	func cost() -> String:
		return TurnRules.FULL

	func apply(_state: GameState, u: Unit, _params: Dictionary) -> Array[Dictionary]:
		u.turn["disengaged"] = true
		return [{"type": "disengaged", "unit": u.id, "rule_ref": "actions: Disengage"}] as Array[Dictionary]
