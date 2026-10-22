class_name SystemActions
extends RefCounted
## Overcharge, Stabilize, Hide, Search, Shut Down, Boot Up, and the Brace reaction policy.

## Heat for the 1st, 2nd, 3rd and later Overcharges (actions: Overcharge; rules.json).
const OVERCHARGE_HEAT := ["1", "1d3", "1d6", "1d6+4"]
## Conditions (statuses.json type "Condition") that Stabilize can clear.
const CONDITIONS := ["Immobilized", "Impaired", "Jammed", "Lock On", "Shredded", "Slowed", "Stunned"]


class Overcharge:
	extends TurnAction
	## Free action, once per turn: one extra quick action (even one already taken) for heat.

	func type() -> String:
		return "overcharge"

	func cost() -> String:
		return TurnRules.FREE

	func check(_state: GameState, u: Unit, _params: Dictionary) -> RuleResult:
		if u.turn.get("overcharged", false):
			return RuleResult.deny("You can only Overcharge once per turn.", TurnRules.REF_OVERCHARGE)
		if u.kind != Unit.KIND_MECH:
			return RuleResult.deny("Only mechs can Overcharge.", TurnRules.REF_OVERCHARGE)
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, _params: Dictionary) -> Array[Dictionary]:
		var expr: String = SystemActions.OVERCHARGE_HEAT[mini(u.overcharge_count, 3)]
		var roll := state.dice.roll(expr)
		u.overcharge_count += 1
		u.turn["overcharged"] = true
		u.turn["free_quick"] = int(u.turn.get("free_quick", 0)) + 1
		var events: Array[Dictionary] = [{"type": "overcharged", "unit": u.id, "roll": roll, "count": u.overcharge_count, "rule_ref": TurnRules.REF_OVERCHARGE}]
		events.append_array(Combat.apply_heat(state, u, int(roll["total"]), "Overcharge"))
		return events


class Stabilize:
	extends TurnAction
	## Full action (actions: Stabilize). params: {"main": "cool" | "repair",
	## "extra": "reload" | "clear_burn" | "clear_condition" | "clear_ally_condition",
	## "condition": status name, "ally": unit id}. NPCs: clears heat and Exposed, reloads.

	func type() -> String:
		return "stabilize"

	func cost() -> String:
		return TurnRules.FULL

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		if u.kind == Unit.KIND_NPC:
			return RuleResult.allow()
		var main: String = params.get("main", "")
		if main != "cool" and main != "repair":
			return RuleResult.deny("Choose: cool (clear heat and Exposed) or repair (mark 1 Repair to restore all HP).", "actions: Stabilize")
		if main == "repair" and u.repairs <= 0:
			return RuleResult.deny("No Repairs left.", "glossary: Repair Capacity")
		var extra: String = params.get("extra", "")
		var cond: String = params.get("condition", "")
		match extra:
			"reload", "clear_burn":
				pass
			"clear_condition":
				return _check_condition(u, u, cond)
			"clear_ally_condition":
				var ally := state.unit(String(params.get("ally", "")))
				if ally == null or ally.side != u.side or ally == u:
					return RuleResult.deny("Choose an allied character.", "actions: Stabilize")
				if Sight.unit_distance(state, u, ally) > 1:
					return RuleResult.deny("The ally must be adjacent.", "actions: Stabilize")
				return _check_condition(ally, ally, cond)
			_:
				return RuleResult.deny("Also choose: reload, clear_burn, clear_condition or clear_ally_condition.", "actions: Stabilize")
		return RuleResult.allow()

	func _check_condition(who: Unit, owner: Unit, cond: String) -> RuleResult:
		if not SystemActions.CONDITIONS.has(cond) or not who.has_status(cond):
			return RuleResult.deny("They don't have that condition.", "actions: Stabilize")
		if String(who.statuses[cond].get("source", "")) == owner.id:
			return RuleResult.deny("Stabilize can't clear a condition caused by the character's own systems.", "actions: Stabilize")
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var events: Array[Dictionary] = [{"type": "stabilized", "unit": u.id, "choices": params, "rule_ref": "actions: Stabilize"}]
		if u.kind == Unit.KIND_NPC or params.get("main", "") == "cool":
			events.append_array(Combat.clear_heat(u, "Stabilize"))
			events.append_array(Combat.remove_status(u, "Exposed", "Stabilize"))
		else:
			u.repairs -= 1
			u.hp = u.max_hp
			events.append({"type": "hp_changed", "unit": u.id, "hp": u.hp, "overshield": u.overshield, "source": "Stabilize"})
		var extra: String = "reload" if u.kind == Unit.KIND_NPC else params.get("extra", "")
		match extra:
			"reload":
				for w: Dictionary in u.loadout.get("weapons", []):
					if Weapons.has_tag(w, "tg_loading"):
						Weapons.state_of(u, w)["loaded"] = true
				events.append({"type": "reloaded", "unit": u.id})
			"clear_burn":
				u.burn = 0
				events.append({"type": "burn_cleared", "unit": u.id})
			"clear_condition":
				events.append_array(Combat.remove_status(u, params["condition"], "Stabilize"))
			"clear_ally_condition":
				events.append_array(Combat.remove_status(state.unit(params["ally"]), params["condition"], "Stabilize"))
		return events


class Hide:
	extends TurnAction
	## Quick action (actions: Hide).

	func type() -> String:
		return "hide"

	func check(state: GameState, u: Unit, _params: Dictionary) -> RuleResult:
		return Combat.can_hide(state, u)

	func apply(state: GameState, u: Unit, _params: Dictionary) -> Array[Dictionary]:
		var events := Combat.add_status(state, u, "Hidden", u.id)
		events.append_array(Combat.refresh_engagement(state))
		return events


class Search:
	extends TurnAction
	## Quick action: contested Systems vs the target's Agility, target within SENSORS
	## (actions: Search). PROVISIONAL: a tie keeps the target Hidden. params: {"target"}

	func type() -> String:
		return "search"

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var target := state.unit(String(params.get("target", "")))
		if target == null or target.destroyed:
			return RuleResult.deny("Choose a character to search for.", "actions: Search")
		if Sight.unit_distance(state, u, target) > u.sensors:
			return RuleResult.deny("Out of Sensors range (%d)." % u.sensors, "actions: Search")
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var target := state.unit(String(params["target"]))
		var events: Array[Dictionary] = []
		if not target.has_status("Hidden"):
			events.append({"type": "searched", "unit": u.id, "target": target.id, "found": false, "note": "Nothing hidden there.", "rule_ref": "actions: Search"})
			return events
		var mine := Combat.skill_check(state, u, "systems", "Search: Systems", 0)
		var theirs := Combat.skill_check(state, target, "agility", "Stay hidden: Agility", 0)
		var found: bool = int(mine["total"]) > int(theirs["total"])
		events.append({"type": "searched", "unit": u.id, "target": target.id, "found": found, "check": mine, "contest": theirs, "rule_ref": "actions: Search"})
		if found:
			events.append_array(Combat.remove_status(target, "Hidden", "found by " + u.id))
			events.append_array(Combat.refresh_engagement(state))
		return events


class ShutDown:
	extends TurnAction
	## Quick action: SHUT DOWN (actions: Shut Down, statuses: Shut Down).

	func type() -> String:
		return "shut_down"

	func check(_state: GameState, u: Unit, _params: Dictionary) -> RuleResult:
		if u.kind != Unit.KIND_MECH:
			return RuleResult.deny("Only mechs can Shut Down.", "actions: Shut Down")
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, _params: Dictionary) -> Array[Dictionary]:
		var events := Combat.add_status(state, u, "Shut Down", u.id)
		events.append_array(Combat.clear_heat(u, "Shut Down"))
		events.append_array(Combat.remove_status(u, "Exposed", "Shut Down"))
		# Statuses caused by tech actions end (Lock On, Fragment Signal's Impaired/Slowed).
		events.append_array(Combat.remove_status(u, "Lock On", "Shut Down"))
		for s in ["Impaired", "Slowed"]:
			if u.has_status(s) and u.statuses[s].get("source", "") == "Fragment Signal":
				events.append_array(Combat.remove_status(u, s, "Shut Down"))
		events.append_array(Combat.add_status(state, u, "Stunned", "Shut Down"))
		return events


class BootUp:
	extends TurnAction
	## Full action: clear SHUT DOWN (actions: Boot Up).

	func type() -> String:
		return "boot_up"

	func cost() -> String:
		return TurnRules.FULL

	func check(_state: GameState, u: Unit, _params: Dictionary) -> RuleResult:
		if not u.has_status("Shut Down"):
			return RuleResult.deny("This mech isn't Shut Down.", "actions: Boot Up")
		return RuleResult.allow()

	func apply(_state: GameState, u: Unit, _params: Dictionary) -> Array[Dictionary]:
		var events := Combat.remove_status(u, "Shut Down", "Boot Up")
		if u.has_status("Stunned") and u.statuses["Stunned"].get("source", "") == "Shut Down":
			events.append_array(Combat.remove_status(u, "Stunned", "Boot Up"))
		return events


class SetBracePolicy:
	extends ActionHandler
	## Not a game action: tells the engine when this unit should take the BRACE reaction.
	## params: {"policy": "never" | "on_structure"}. Allowed any time.

	func type() -> String:
		return "set_brace_policy"

	func validate(_state: GameState, action: Dictionary) -> RuleResult:
		var p: String = action.get("params", {}).get("policy", "")
		if p != "never" and p != "on_structure":
			return RuleResult.deny("Policy must be never or on_structure.", Reactions.REF_BRACE)
		return RuleResult.allow()

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		var u := state.unit(action["actor"])
		u.counters["brace_policy"] = action["params"]["policy"]
		return [{"type": "reaction_policy", "unit": u.id, "reaction": "brace", "policy": action["params"]["policy"]}] as Array[Dictionary]


class SetReactionPolicy:
	extends ActionHandler
	## Not a game action: how the engine handles one of this unit's reactions.
	## params: {"reaction": "overwatch" | "brace" | "prepared", "policy": "ask" | "auto" |
	## "never" | "on_structure" (Brace only)}. Allowed any time. See Reactions.

	func type() -> String:
		return "set_reaction_policy"

	func validate(_state: GameState, action: Dictionary) -> RuleResult:
		var p: Dictionary = action.get("params", {})
		if not Reactions.POLICIES.has(p.get("policy", "")) or String(p.get("reaction", "")) == "":
			return RuleResult.deny("Give a reaction and a policy (ask, auto, never, on_structure).", "")
		return RuleResult.allow()

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		var u := state.unit(action["actor"])
		var p: Dictionary = action["params"]
		var set: Dictionary = u.counters.get("reaction_policy", {})
		set[p["reaction"]] = p["policy"]
		u.counters["reaction_policy"] = set
		return [{"type": "reaction_policy", "unit": u.id, "reaction": p["reaction"], "policy": p["policy"]}] as Array[Dictionary]
