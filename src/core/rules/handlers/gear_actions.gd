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


class DetectMines:
	extends TurnAction
	## Quick action: a Systems check; on a success every hostile mine within your Sensors is
	## detected (no longer Hidden) (tags: Mine). PROVISIONAL: one check covers all of them.

	func type() -> String:
		return "detect_mines"

	func kinds() -> Array:
		return [Unit.KIND_MECH, Unit.KIND_NPC, Unit.KIND_PILOT]

	func check(_state: GameState, _u: Unit, _params: Dictionary) -> RuleResult:
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, _params: Dictionary) -> Array[Dictionary]:
		var check := Combat.skill_check(state, u, "systems", "Detect mines: Systems check")
		var events: Array[Dictionary] = [{"type": "skill_check", "unit": u.id, "check": check, "rule_ref": "tags: Mine"}]
		if not check["success"]:
			return events
		var ids: Array = state.units.keys()
		ids.sort()
		for id: String in ids:
			var m := state.unit(id)
			if m.destroyed or String(m.counters.get("deploy_type", "")) != "Mine" or m.side == u.side or not m.has_status("Hidden"):
				continue
			if Sight.unit_distance(state, u, m) <= u.sensors:
				events.append_array(Combat.remove_status(m, "Hidden", "detected by " + u.id))
				events.append({"type": "mine_detected", "unit": u.id, "mine": m.id, "cell": [m.cell.x, m.cell.y], "rule_ref": "tags: Mine"})
		return events


class DisarmMine:
	extends TurnAction
	## Quick action: a detected mine in an adjacent space; a Systems check disarms it, and on a
	## failure it detonates as normal (tags: Mine). params: {"mine"}

	func type() -> String:
		return "disarm_mine"

	func kinds() -> Array:
		return [Unit.KIND_MECH, Unit.KIND_NPC, Unit.KIND_PILOT]

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var m := state.unit(String(params.get("mine", "")))
		if m == null or m.destroyed or String(m.counters.get("deploy_type", "")) != "Mine":
			return RuleResult.deny("Choose a mine (params.mine).", "tags: Mine")
		if m.has_status("Hidden"):
			return RuleResult.deny("Detect it first.", "tags: Mine")
		if Sight.unit_distance(state, u, m) > 1:
			return RuleResult.deny("Disarm it from an adjacent space.", "tags: Mine")
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var m := state.unit(String(params["mine"]))
		var check := Combat.skill_check(state, u, "systems", "Disarm the mine: Systems check")
		var events: Array[Dictionary] = [{"type": "skill_check", "unit": u.id, "check": check, "rule_ref": "tags: Mine"}]
		if check["success"]:
			m.destroyed = true
			events.append({"type": "mine_disarmed", "unit": u.id, "mine": m.id, "rule_ref": "tags: Mine"})
		else:
			events.append_array(Abilities.detonate(state, m, u))
		return events


class ShackleReturn:
	extends TurnAction
	## Celestial Shackles: free, once during your turn: teleport the shackled character back to
	## its marked space (or as close as possible); the effect ends. params: {"target"}

	func type() -> String:
		return "shackle_return"

	func cost() -> String:
		return TurnRules.FREE

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var t := state.unit(String(params.get("target", "")))
		var sh: Dictionary = t.counters.get("shackled", {}) if t != null else {}
		if sh.is_empty() or String(sh.get("by", "")) != u.id:
			return RuleResult.deny("Choose a character you shackled.", "systems: H0R_OS System Upgrade III")
		if t.cell == Vector2i(int(sh["cell"][0]), int(sh["cell"][1])):
			return RuleResult.deny("It hasn't left its space.", "systems: H0R_OS System Upgrade III")
		return RuleResult.allow()

	func apply(state: GameState, _u: Unit, params: Dictionary) -> Array[Dictionary]:
		var t := state.unit(String(params["target"]))
		var sh: Dictionary = t.counters["shackled"]
		t.counters.erase("shackled")
		var goal := Sight.make_body(state, Vector2i(int(sh["cell"][0]), int(sh["cell"][1])), int(sh.get("level", 0)), t.size)
		var path := Movement.pull_path_to(state, t, goal, 0)
		var last: Array = path.back()
		var from := [t.cell.x, t.cell.y, t.level]
		t.cell = Vector2i(last[0], last[1])
		t.level = int(last[2])
		var events: Array[Dictionary] = [{"type": "moved", "unit": t.id, "path": [from, last], "mode": "teleport", "cost": 0, "rule_ref": "systems: H0R_OS System Upgrade III"}]
		events.append_array(Combat.refresh_engagement(state))
		return events


class BreakShackles:
	extends TurnAction
	## Quick action: a Systems save ends Celestial Shackles.

	func type() -> String:
		return "break_shackles"

	func check(_state: GameState, u: Unit, _params: Dictionary) -> RuleResult:
		return RuleResult.allow() if u.counters.has("shackled") else RuleResult.deny("You aren't shackled.", "systems: H0R_OS System Upgrade III")

	func apply(state: GameState, u: Unit, _params: Dictionary) -> Array[Dictionary]:
		var by := state.unit(String(u.counters["shackled"].get("by", "")))
		var save := Combat.skill_check(state, u, "systems", "Break the shackles: Systems save", by.save_target if by != null else 10, 0, 0, [], true)
		var events: Array[Dictionary] = [{"type": "skill_check", "unit": u.id, "check": save, "rule_ref": "systems: H0R_OS System Upgrade III"}]
		if save["success"]:
			u.counters.erase("shackled")
			events.append({"type": "effect_ended", "unit": u.id, "effect": "Celestial Shackles", "reason": "saved"})
		return events


class DispelConstruct:
	extends TurnAction
	## A Systems check destroys a data construct next to you: a Dimensional Emblem as a quick
	## action (params.emblem: zone id), an Ideal Image as a full action (params.target: its id;
	## the check uses up your turn).

	func type() -> String:
		return "dispel_construct"

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var ref := "systems: H0R_OS System Upgrade II/III"
		if params.has("emblem"):
			for z: Dictionary in Zones.of_kind(state, "emblem"):
				if z["id"] == params["emblem"] and state.map.grid.distance(u.cell, Vector2i(int(z["center"][0]), int(z["center"][1]))) <= 1:
					return RuleResult.allow()
			return RuleResult.deny("Choose an emblem next to you.", ref)
		var t := state.unit(String(params.get("target", "")))
		if t == null or t.destroyed or not String(t.name).begins_with("Construct Other: Ideal Image") or Sight.unit_distance(state, u, t) > 1:
			return RuleResult.deny("Choose an Ideal Image construct next to you.", ref)
		if int(u.turn.get("quick", 0)) > 0 or u.turn.get("full", false):
			return RuleResult.deny("Dispelling an Ideal Image is a full action.", ref)
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var check := Combat.skill_check(state, u, "systems", "Dispel the construct: Systems check")
		var events: Array[Dictionary] = [{"type": "skill_check", "unit": u.id, "check": check, "rule_ref": "systems: H0R_OS System Upgrade II/III"}]
		if not params.has("emblem"):
			u.turn["quick"] = 2
			u.turn["full"] = true
		if check["success"]:
			if params.has("emblem"):
				events.append_array(Zones.remove(state, String(params["emblem"]), "dispelled"))
			else:
				var t := state.unit(String(params["target"]))
				t.destroyed = true
				events.append({"type": "unit_destroyed", "unit": t.id, "reason": "dispelled"})
		return events


class Drag:
	extends TurnAction
	## Start dragging (or towing on a cable) a character, wreck or object, or lift one of your
	## Size or smaller overhead (Immobilized while you hold it). params: {"target", "lift": bool}

	func type() -> String:
		return "drag"

	func cost() -> String:
		return TurnRules.FREE

	func kinds() -> Array:
		return [Unit.KIND_MECH, Unit.KIND_NPC, Unit.KIND_PILOT]

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		return Riders.check_drag(state, u, state.unit(String(params.get("target", ""))), bool(params.get("lift", false)))

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		return Riders.start_drag(state, u, state.unit(String(params["target"])), bool(params.get("lift", false)))


class LetGoDrag:
	extends TurnAction
	## Stop dragging.

	func type() -> String:
		return "release_drag"

	func cost() -> String:
		return TurnRules.FREE

	func kinds() -> Array:
		return [Unit.KIND_MECH, Unit.KIND_NPC, Unit.KIND_PILOT]

	func check(_state: GameState, u: Unit, _params: Dictionary) -> RuleResult:
		return RuleResult.allow() if u.counters.has("dragging") else RuleResult.deny("You aren't dragging anything.", Riders.REF_DRAG)

	func apply(_state: GameState, u: Unit, _params: Dictionary) -> Array[Dictionary]:
		return Riders.stop_drag(u, "let go")


class IssueOrder:
	extends TurnAction
	## Leader: 1/turn on your turn, free: an order to an allied player character and one of your
	## Leadership Dice (an ally holds one at a time). params: {"target", "order": text}

	func type() -> String:
		return "issue_order"

	func cost() -> String:
		return TurnRules.FREE

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var ref := "talents: Leader"
		if not Effects.has(u, "leadership"):
			return RuleResult.deny("Issuing orders needs the Leader talent.", ref)
		if u.turn.get("ordered", false):
			return RuleResult.deny("One order per turn.", ref)
		if TalentRules.leadership_left(u) <= 0:
			return RuleResult.deny("No Leadership Dice left.", ref)
		var t := state.unit(String(params.get("target", "")))
		if t == null or t == u or t.side != u.side or not Combat.is_present(t) or t.kind == Unit.KIND_NPC or t.kind == Unit.KIND_DEPLOYABLE:
			return RuleResult.deny("Choose an allied player character.", ref)
		if t.counters.has("leader_die"):
			return RuleResult.deny("They already hold a Leadership Die.", ref)
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var t := state.unit(String(params["target"]))
		u.turn["ordered"] = true
		u.counters["leadership"] = TalentRules.leadership_left(u) - 1
		t.counters["leader_die"] = u.id
		return [{"type": "order_issued", "unit": u.id, "target": t.id, "order": String(params.get("order", "")),
			"text": "Spend the Leadership Die (params.leadership) for +1 Accuracy on an action that follows from the order.", "rule_ref": "talents: Leader"}] as Array[Dictionary]


class AceBurst:
	extends TurnAction
	## Ace 2: while flying, before a Boost, roll 1d6: the Boost may go that many spaces further,
	## and you take heat equal to half that (rounded up).

	func type() -> String:
		return "ace_burst"

	func cost() -> String:
		return TurnRules.FREE

	func check(_state: GameState, u: Unit, _params: Dictionary) -> RuleResult:
		if not Effects.has(u, "ace_burst") or not u.flying:
			return RuleResult.deny("Only while flying, with Ace rank 2.", "talents: Ace")
		if u.turn.has("ace_extra"):
			return RuleResult.deny("Already rolled for this turn's Boost.", "talents: Ace")
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, _params: Dictionary) -> Array[Dictionary]:
		var roll := state.dice.die(6)
		u.turn["ace_extra"] = roll
		var events: Array[Dictionary] = [{"type": "effect_triggered", "unit": u.id, "effect": "Ace: afterburners", "target": u.id, "roll": roll, "rule_ref": "talents: Ace"}]
		events.append_array(Combat.apply_heat(state, u, ceili(roll / 2.0), "Ace"))
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
