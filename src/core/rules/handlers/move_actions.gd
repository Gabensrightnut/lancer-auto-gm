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
	var plan := _plan_raw(state, u, params, mode)
	if plan["ok"] and u.counters.has("cable") and not (plan["path"] as Array).is_empty():
		var last: Array = (plan["path"] as Array).back()
		if not Riders.tether_ok(state, u, Vector2i(last[0], last[1]), int(last[2])):
			plan["ok"] = false
			plan["reason"] = "The cable holds you within 5 spaces of the other end."
			plan["rule_ref"] = Riders.REF_WINCH
	var scary := state.unit(String(u.counters.get("terrified_of", "")))
	if plan["ok"] and scary != null and Combat.is_present(scary) and u.has_status("Impaired") and String(u.statuses["Impaired"].get("source", "")) == scary.id \
			and not (plan["path"] as Array).is_empty():
		# Hunter Logic Suite Terrify: no voluntary moves that bring it closer.
		var lt: Array = (plan["path"] as Array).back()
		if Sight.distance(state, Sight.make_body(state, Vector2i(lt[0], lt[1]), int(lt[2]), u.size), Sight.body_of(state, scary)) < Sight.unit_distance(state, u, scary):
			plan["ok"] = false
			plan["reason"] = "Terrified: you can't move any closer to it."
			plan["rule_ref"] = "systems: Hunter Logic Suite"
	var foe := state.unit(String(u.counters.get("duel", "")))
	if plan["ok"] and foe != null and Combat.is_present(foe) and not (plan["path"] as Array).is_empty():
		# Exemplar To The Death: can't voluntarily move away from the mark.
		var last2: Array = (plan["path"] as Array).back()
		var there := Sight.make_body(state, Vector2i(last2[0], last2[1]), int(last2[2]), u.size)
		if Sight.distance(state, there, Sight.body_of(state, foe)) > Sight.unit_distance(state, u, foe):
			plan["ok"] = false
			plan["reason"] = "Duel to the death: you can't move away from your mark."
			plan["rule_ref"] = "talents: Exemplar"
	return plan


static func _plan_raw(state: GameState, u: Unit, params: Dictionary, mode: String) -> Dictionary:
	var to: Variant = TurnAction.cell_param(params, "to")
	if to == null:
		return {"ok": false, "reason": "Say where to move (params.to = [x, y]).", "rule_ref": Movement.REF_MOVE}
	if Effects.has(u, "teleport_moves") and mode != Movement.MODE_BONUS:
		# "You teleport when you Boost or make a standard move" (Mourning Cloak core).
		return Movement.plan_teleport(state, u, to, int(params.get("level", -1)), mode)
	return Movement.plan(state, u, to, int(params.get("level", -1)), mode, bool(params.get("fly", false)))


static func _plan_result(plan: Dictionary) -> RuleResult:
	if not plan["ok"]:
		return RuleResult.deny(plan["reason"], plan["rule_ref"])
	if plan.get("grey_area", "") != "":
		return Rulings.needed(String(plan["grey_area"]))
	return RuleResult.allow()


## After reactions to the start of a move (Overwatch), can the move still happen? Returns a
## `movement_cancelled` event if not, else {}.
static func _still_can_move(state: GameState, u: Unit, params: Dictionary, mode: String) -> Dictionary:
	var why := ""
	if not Combat.is_present(u):
		why = "Destroyed before moving."
	else:
		var r := _can_move_voluntarily(u)
		if not r.ok:
			why = r.reason
		else:
			var plan := _plan(state, u, params, mode)
			if not plan["ok"]:
				why = plan["reason"]
	if why == "":
		return {}
	return {"type": "movement_cancelled", "unit": u.id, "reason": why, "rule_ref": Movement.REF_MOVE}


## Moves along a planned path and applies everything that follows.
static func _do_move(state: GameState, u: Unit, plan: Dictionary, mode: String, fly: bool) -> Array[Dictionary]:
	var path: Array = plan["path"]
	var last: Array = path.back()
	var from := u.cell
	var from_level := u.level
	u.cell = Vector2i(last[0], last[1])
	u.level = int(last[2])
	u.turn["moved"] = true
	var placed := Movement.placement(state, u.size, u.cell, u.level)
	u.flying = (fly or plan.get("teleport", false)) and not placed["standing"] and not placed["uneven"]
	if fly and u.flight == "" and Effects.has(u, "optional_flight"):
		u.turn["flew_optional"] = true  # heat at the end of the turn (Type-I Flight System...)
	var anim := "teleport" if plan.get("teleport", false) else ("fly" if fly else mode)
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
	# Jump Jets: flying on a Boost must end on a surface, or the mech falls at once.
	if mode == "boost" and fly and u.flight == "" and not Effects.has(u, "optional_flight") and Effects.has(u, "boost_flight") and u.flying:
		events.append_array(Combat.begin_falling(u, "Jump jets: the Boost didn't end on a surface."))
		events.append_array(Combat.fall_unit(state, u))
	events.append_array(Effects.moved(state, u, mode))
	events.append_array(Environments.moved(state, u, path))
	events.append_array(TalentRules.covered_moved(state, u, maxi(0, path.size() - 1)))
	if u.counters.has("riding"):
		events.append_array(Riders.drop(state, u, false, "climbed down"))  # riders climb down by moving away
	events.append_array(Zones.leave_hologram(state, u, from, from_level))
	Zones.oasis_trail(state, u, path)
	events.append_array(GearSystems.horus_moved(state, u, maxi(0, path.size() - 1)))
	events.append_array(Abilities.check_mines(state, u, path))
	events.append_array(Zones.check_path(state, u, path))
	events.append_array(CloseCombat.drag_partner(state, u, from, from_level))
	events.append_array(Combat.after_movement(state))
	events.append_array(Reactions.prepared_triggers(state, u))
	return events


class Move:
	extends TurnAction
	## Standard move: up to SPEED, may be split around other actions (Core p.62).

	func type() -> String:
		return "move"

	func cost() -> String:
		return "move"

	func kinds() -> Array:
		return [Unit.KIND_MECH, Unit.KIND_NPC, Unit.KIND_PILOT]

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var r := MoveActions._can_move_voluntarily(u)
		if not r.ok:
			return r
		if u.turn.get("braced", false):
			return RuleResult.deny("After Bracing you can't move normally this turn.", TurnRules.REF_BRACE)
		if u.turn.get("prepared_lock", false):
			return RuleResult.deny("After Preparing an action you can't move until it triggers or your next turn.", "actions: Prepare")
		if u.turn.get("stood_up", false) or Movement.budget(u, Movement.MODE_MOVE) <= 0:
			return RuleResult.deny("You've used your standard move this turn (Boost to move again).", Movement.REF_MOVE)
		return MoveActions._plan_result(MoveActions._plan(state, u, params, Movement.MODE_MOVE))

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var teleport := Effects.has(u, "teleport_moves")
		var events: Array[Dictionary] = []
		if not teleport:
			events = Reactions.overwatch(state, u)  # teleports don't provoke (Core p.63)
		var r := MoveActions._still_can_move(state, u, params, Movement.MODE_MOVE)
		if not r.is_empty():
			events.append(r)
			return events
		var plan := MoveActions._plan(state, u, params, Movement.MODE_MOVE)
		u.turn["move_spent"] = int(u.turn.get("move_spent", 0)) + int(plan["cost"])
		if plan["stopped_by"] != "":
			u.turn["move_spent"] = u.speed  # lose any unused movement (statuses: Engaged)
		if teleport and Rulings.ask(state, "teleport_move_cost") == "whole_move":
			u.turn["move_spent"] = u.speed
		events.append_array(MoveActions._do_move(state, u, plan, "walk", bool(params.get("fly", false))))
		return events


class Boost:
	extends TurnAction
	## Quick action: move at least 1 space, up to SPEED (actions: Boost).

	func type() -> String:
		return "boost"

	func kinds() -> Array:
		return [Unit.KIND_MECH, Unit.KIND_NPC, Unit.KIND_PILOT]

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var r := MoveActions._can_move_voluntarily(u)
		if not r.ok:
			return r
		if u.has_status("Slowed") or u.has_status("Prone"):
			return RuleResult.deny("Slowed (Prone characters are Slowed too): your only movement is your standard move, so no Boost.", "statuses: Slowed, Prone")
		if u.counters.has("grapple") and not Effects.has(u, "grapple_free"):
			return RuleResult.deny("Grappling characters can't Boost.", "actions: Grapple")
		if Effects.has(u, "no_boost"):
			return RuleResult.deny("High gravity: mechs can't Boost here.", Environments.REF)
		return MoveActions._plan_result(MoveActions._plan(state, u, params, Movement.MODE_BOOST))

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var events: Array[Dictionary] = []
		if not Effects.has(u, "teleport_moves"):
			events = Reactions.overwatch(state, u)
		var r := MoveActions._still_can_move(state, u, params, Movement.MODE_BOOST)
		if not r.is_empty():
			events.append(r)
			return events
		var plan := MoveActions._plan(state, u, params, Movement.MODE_BOOST)
		events.append_array(MoveActions._do_move(state, u, plan, "boost", bool(params.get("fly", false))))
		if u.has_status("Hidden"):
			# Using BOOST removes HIDDEN after it resolves (statuses: Hidden).
			events.append_array(Combat.remove_status(u, "Hidden", "boosted"))
			events.append_array(Combat.refresh_engagement(state))
		return events


class BonusMove:
	extends TurnAction
	## A free move granted right after attacking (Nelson's Skirmisher: 1 space, 4 with its core;
	## the Skirmisher talent: 2 after a Skirmish). Ignores engagement, doesn't provoke, and
	## can't be taken while Immobilized or Slowed. It must come before any other action.
	## params: {"to": [x, y], "level", "fly"}

	func type() -> String:
		return "bonus_move"

	func cost() -> String:
		return "move"

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		if int(u.turn.get("bonus_move", 0)) <= 0:
			return RuleResult.deny("No extra move available right now (it comes right after an attack that grants it).", Effects.REF)
		var r := MoveActions._can_move_voluntarily(u)
		if not r.ok:
			return r
		if u.has_status("Slowed") or u.has_status("Prone"):
			return RuleResult.deny("Slowed: no special moves from traits or talents.", "Core p.78 Slowed")
		u.turn["ignore_engagement_now"] = true
		var plan := MoveActions._plan(state, u, params, Movement.MODE_BONUS)
		u.turn.erase("ignore_engagement_now")
		return MoveActions._plan_result(plan)

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		u.turn["ignore_engagement_now"] = true
		var plan := MoveActions._plan(state, u, params, Movement.MODE_BONUS)
		u.turn["bonus_move"] = 0
		var events := MoveActions._do_move(state, u, plan, "bonus", bool(params.get("fly", false)))
		u.turn.erase("ignore_engagement_now")
		return events


class StandUp:
	extends TurnAction
	## Remove PRONE instead of taking your standard move; not movement (statuses: Prone).

	func type() -> String:
		return "stand_up"

	func cost() -> String:
		return "move"

	func kinds() -> Array:
		return [Unit.KIND_MECH, Unit.KIND_NPC, Unit.KIND_PILOT]

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

	func kinds() -> Array:
		return [Unit.KIND_MECH, Unit.KIND_NPC, Unit.KIND_PILOT]

	func cost() -> String:
		return TurnRules.FULL

	func apply(_state: GameState, u: Unit, _params: Dictionary) -> Array[Dictionary]:
		u.turn["disengaged"] = true
		return [{"type": "disengaged", "unit": u.id, "rule_ref": "actions: Disengage"}] as Array[Dictionary]
