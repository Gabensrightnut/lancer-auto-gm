class_name GearActions
extends RefCounted
## Actions that gear gives to characters other than its owner.


class AIControl:
	extends TurnAction
	## Protocol: hand the controls to your AI, or take them back at the start of a later turn
	## (Core p.107). params: {"take_back": bool}

	func type() -> String:
		return "ai_control"

	func kinds() -> Array:
		return [Unit.KIND_MECH]

	func cost() -> String:
		return TurnRules.FREE

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		if u.turn.get("acted", false) or u.turn.get("moved", false):
			return RuleResult.deny("A protocol: only at the start of your turn.", "tags: Protocol")
		if params.get("take_back", false):
			return AISystems.check_take_back(state, u)
		if not AISystems.has_ai(u):
			return RuleResult.deny("This mech has no AI system.", AISystems.REF)
		if AISystems.controlled(u):
			return RuleResult.deny("The AI already has control.", AISystems.REF)
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		if params.get("take_back", false):
			return AISystems.take_back(state, u, "pilot")
		return AISystems.hand_over(state, u, String(u.loadout["ai"]["source"]))


class ClimbOn:
	extends TurnAction
	## Quick action: climb onto an adjacent mech's MULE Harness. params: {"host"}

	func type() -> String:
		return "climb_on"

	func kinds() -> Array:
		return [Unit.KIND_MECH, Unit.KIND_NPC, Unit.KIND_PILOT]

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		return Riders.check_climb(state, u, state.unit(String(params.get("host", ""))))

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		return Riders.climb(state, u, state.unit(String(params["host"])))


class Board:
	extends TurnAction
	## Full action: board an adjacent mech's Expanded Compartment as its passenger.
	## params: {"mech"}

	func type() -> String:
		return "board"

	func kinds() -> Array:
		return [Unit.KIND_PILOT]

	func cost() -> String:
		return TurnRules.FULL

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		return Riders.check_board(state, u, state.unit(String(params.get("mech", ""))))

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		u.counters["passenger_in"] = String(params["mech"])
		return [{"type": "boarded", "unit": u.id, "mech": params["mech"], "rule_ref": Riders.REF_COMPARTMENT}] as Array[Dictionary]


class Disembark:
	extends TurnAction
	## Full action: a passenger climbs out to a free adjacent space. params: {"to"}

	func type() -> String:
		return "disembark"

	func kinds() -> Array:
		return [Unit.KIND_PILOT]

	func cost() -> String:
		return TurnRules.FULL

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		if not u.counters.has("passenger_in"):
			return RuleResult.deny("You aren't a passenger.", Riders.REF_COMPARTMENT)
		var mech := state.unit(String(u.counters["passenger_in"]))
		var to: Variant = TurnAction.cell_param(params, "to")
		if to == null or Pilots.free_adjacent(state, mech, to) == null:
			return RuleResult.deny("Choose a free space next to the mech (params.to).", Riders.REF_COMPARTMENT)
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var mech := state.unit(String(u.counters["passenger_in"]))
		var spot: Array = Pilots.free_adjacent(state, mech, TurnAction.cell_param(params, "to"))
		u.counters.erase("passenger_in")
		u.cell = spot[0]
		u.level = int(spot[1])
		if mech.counters.has("passenger_control"):
			Riders.transfer(state, mech)
		return [{"type": "disembarked", "unit": u.id, "mech": mech.id, "cell": [u.cell.x, u.cell.y, u.level], "rule_ref": Riders.REF_COMPARTMENT}] as Array[Dictionary]


class CutCable:
	extends TurnAction
	## Quick action: a melee hit against Evasion 10 cuts a Cable Winch cable on an adjacent
	## character. params: {"target": a character at one end}

	func type() -> String:
		return "cut_cable"

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var t := state.unit(String(params.get("target", "")))
		if t == null or not t.counters.has("cable"):
			return RuleResult.deny("Choose a character tied by a cable.", Riders.REF_WINCH)
		if t != u and Sight.unit_distance(state, u, t) > 1:
			return RuleResult.deny("It must be adjacent (or yourself).", Riders.REF_WINCH)
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var check := state.dice.check(u.grit, 0, 0, 10, [])
		check["target_label"] = "Evasion 10"
		var events: Array[Dictionary] = [{"type": "attack_rolled", "attacker": u.id, "target": String(params["target"]), "weapon": "", "weapon_name": "Cut the cable",
			"kind": "melee", "check": check, "result": "hit" if check["success"] else "miss", "cover": "none", "cover_cells": [], "invisible_miss": false,
			"lock_on_consumed": false, "rule_ref": Riders.REF_WINCH}]
		if check["success"]:
			events.append_array(Riders.cut(state, state.unit(String(params["target"]))))
		return events


class PullStake:
	extends TurnAction
	## Full action: an impaled character repeats the Hull save to remove a Charged Stake.

	func type() -> String:
		return "pull_stake"

	func cost() -> String:
		return TurnRules.FULL

	func check(_state: GameState, u: Unit, _params: Dictionary) -> RuleResult:
		if not u.counters.has("impaled"):
			return RuleResult.deny("You aren't impaled.", "systems: Charged Stake")
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, _params: Dictionary) -> Array[Dictionary]:
		var imp: Dictionary = u.counters["impaled"]
		var save := Combat.skill_check(state, u, "hull", "Pull out the stake", int(imp.get("save_target", 10)), 0, 0, [], true)
		var events: Array[Dictionary] = [{"type": "skill_check", "unit": u.id, "check": save, "rule_ref": "systems: Charged Stake"}]
		if save["success"]:
			events.append_array(GearSystems.unimpale(u, "pulled free"))
		return events


class ShakeOff:
	extends TurnAction
	## Full action: a Systems save to end Chains of Prometheus or Excommunicate.
	## params: {"what": "chains" | "excommunicate"}

	func type() -> String:
		return "shake_off"

	func cost() -> String:
		return TurnRules.FULL

	func check(_state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var what := String(params.get("what", ""))
		if not what in ["chains", "excommunicate"] or not u.counters.has(what):
			return RuleResult.deny("Nothing like that is affecting you.", "systems: Aggressive System Sync")
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var what := String(params["what"])
		var save := Combat.skill_check(state, u, "systems", "Shake off %s" % what.capitalize(), int(u.counters[what].get("save_target", 10)), 0, 0, [], true)
		var events: Array[Dictionary] = [{"type": "skill_check", "unit": u.id, "check": save, "rule_ref": "systems: Aggressive System Sync"}]
		if save["success"]:
			u.counters.erase(what)
			events.append({"type": "effect_ended", "unit": u.id, "effect": what.capitalize(), "reason": "saved"})
		return events


class FixHack:
	extends TurnAction
	## Hacker 2: undo an Invade. params: {"what": "life_support" | "hack_slash" (quick, Systems
	## check) | "jam_cockpit" (full, Engineering check)}. The cost is checked here: the jammed
	## cockpit needs the whole turn.

	func type() -> String:
		return "fix_hack"

	func check(_state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var what := String(params.get("what", ""))
		if not (u.counters.get("hacked", {}) as Dictionary).has(what):
			return RuleResult.deny("Nothing like that has been hacked.", "talents: Hacker")
		if what == "jam_cockpit" and (int(u.turn.get("quick", 0)) > 0 or u.turn.get("full", false)):
			return RuleResult.deny("Fixing the cockpit is a full action.", "talents: Hacker")
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var what := String(params["what"])
		var skill := "engineering" if what == "jam_cockpit" else "systems"
		if what == "jam_cockpit":
			u.turn["quick"] = 2
			u.turn["full"] = true
		var check := Combat.skill_check(state, u, skill, "Fix: " + what.capitalize(), Combat.CHECK_TARGET)
		var events: Array[Dictionary] = [{"type": "skill_check", "unit": u.id, "check": check, "rule_ref": "talents: Hacker"}]
		if check["success"]:
			(u.counters["hacked"] as Dictionary).erase(what)
			events.append({"type": "effect_ended", "unit": u.id, "effect": what.capitalize(), "reason": "fixed"})
		return events


class UseObject:
	extends TurnAction
	## Quick action: use an adjacent allied object that allows it (Restock Drone).
	## params: {"object": id, "condition": status to clear, "weapon": Loading weapon to reload}

	func type() -> String:
		return "use_object"

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var o := state.unit(String(params.get("object", "")))
		if o == null or o.destroyed or not o.counters.has("interact"):
			return RuleResult.deny("Choose an object you can use.", Abilities.REF)
		if o.side != u.side:
			return RuleResult.deny("Only allied characters can use it.", Abilities.REF)
		if not o.counters.get("primed", true):
			return RuleResult.deny("It primes at the end of its owner's turn.", "systems: Restock Drone")
		if Sight.unit_distance(state, u, o) > 1:
			return RuleResult.deny("It must be adjacent.", Abilities.REF)
		if int(o.counters.get("used_round", -1)) == state.round_number:
			return RuleResult.deny("It's already been used this round.", Abilities.REF)
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var o := state.unit(String(params["object"]))
		var events: Array[Dictionary] = []
		for op: Dictionary in o.counters["interact"]:
			if op.get("op", "") == "restock":
				events.append_array(GearSystems.restock(state, u, o, params))
			if op.get("op", "") == "reload":
				# Autoloader Drone: 1/round, an adjacent character reloads a Loading weapon.
				o.counters["used_round"] = state.round_number
				events.append_array(GearSystems.reload_one(state, u, String(params.get("weapon", "")), o.name))
		return events
