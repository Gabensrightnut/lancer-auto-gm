class_name TechActions
extends RefCounted
## Quick Tech options: Scan, Lock On, Invade (Fragment Signal). Quick Tech can be taken more
## than once a turn, but a different option each time unless granted as a free action
## (actions: Quick Tech). params: {"target": unit id}


class QuickTech:
	extends TurnAction

	func economy_name() -> String:
		return "quick_tech"

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var used: Array = u.turn.get("quick_tech", [])
		if (u.counters.get("hacked", {}) as Dictionary).has("hack_slash"):
			return RuleResult.deny("Hack/Slash: no tech actions until you reboot (a Systems check, `fix_hack`) or Shut Down.", "talents: Hacker")
		if used.has(type()) and int(u.turn.get("free_quick", 0)) <= 0 and not Rulings.lancer_tactics(state, "lt_repeat_quick_tech"):
			return RuleResult.deny("Pick a different Quick Tech option: each can be used once per turn.", "actions: Quick Tech")
		return check_tech(state, u, state.unit(String(params.get("target", ""))))

	func check_tech(state: GameState, u: Unit, target: Unit) -> RuleResult:
		return Attacks.tech_target_check(state, u, target, type())

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		var u := state.unit(action["actor"])
		(u.turn.get("quick_tech", []) as Array).append(type())
		return super(state, action)


class Scan:
	extends QuickTech
	## Learn the target's weapons, systems and full statistics (actions: Scan). Revealed to
	## the scanner's whole side through ViewFilter (state.intel).

	func type() -> String:
		return "scan"

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var target := state.unit(String(params["target"]))
		ViewFilter.reveal_in_state(state, u.side, target.id)
		return [{"type": "scanned", "unit": u.id, "target": target.id, "side": u.side,
			"note": "Information is only current as of the Scan.", "rule_ref": "actions: Scan"}] as Array[Dictionary]


class LockOn:
	extends QuickTech
	## The target gains LOCK ON (actions: Lock On).

	func type() -> String:
		return "lock_on"

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var target := state.unit(String(params["target"]))
		var events := Combat.add_status(state, target, "Lock On", u.id)
		if Effects.has(u, "lock_on_shreds") and u.counters.get("lock_on_shreds_round", -1) != state.round_number:
			# Prophetic Scanners: 1/round, Lock On also Shreds until the end of the target's next turn.
			u.counters["lock_on_shreds_round"] = state.round_number
			events.append_array(Combat.add_status(state, target, "Shredded", u.id, target.id))
		events.append({"type": "tech_action", "unit": u.id, "target": target.id, "action": "lock_on", "rule_ref": "actions: Lock On"})
		return events


class Invade:
	extends QuickTech
	## Tech attack; on a hit the target takes 2 heat and FRAGMENT SIGNAL: Impaired and Slowed
	## until the end of its next turn (actions: Invade, Fragment Signal). Willing allies:
	## automatic success, no heat, not an attack.

	func type() -> String:
		return "invade"

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var target := state.unit(String(params["target"]))
		var events: Array[Dictionary] = []
		var hit := true
		if target.side != u.side:
			var r := Attacks.tech_attack(state, u, target, "Fragment Signal", params)
			events.append_array(r["events"])
			hit = r["hit"]
			if hit:
				events.append_array(Combat.apply_heat(state, target, 2, u.id))
		else:
			events.append({"type": "tech_action", "unit": u.id, "target": target.id, "action": "invade", "note": "Willing ally: automatic success, no heat.", "rule_ref": "actions: Invade"})
		if hit and not target.destroyed:
			events.append_array(Combat.add_status(state, target, "Impaired", "Fragment Signal", target.id))
			events.append_array(Combat.add_status(state, target, "Slowed", "Fragment Signal", target.id))
		return events


class Bolster:
	extends QuickTech
	## A character within SENSORS gets +2 Accuracy on its next skill check or save until the
	## end of its next turn; only one Bolster at a time (actions: Bolster).

	func type() -> String:
		return "bolster"

	func check_tech(state: GameState, u: Unit, target: Unit) -> RuleResult:
		if u.has_status("Jammed"):
			return RuleResult.deny("Jammed: you can't take tech actions.", "statuses: Jammed")
		if target == null or not Combat.is_present(target):
			return RuleResult.deny("Choose a character.", "actions: Bolster")
		if Effects.has(target, "aegis"):
			return RuleResult.deny("Inside the Trueblack Aegis it's immune to all tech actions, even helpful ones.", "frames: Napoleon core system")
		if target.has_status("Jammed"):
			return RuleResult.deny("Jammed characters can't benefit from tech actions.", "statuses: Jammed")
		if target.has_status("Shut Down"):
			return RuleResult.deny("Shut Down mechs are immune to tech actions.", "statuses: Shut Down")
		if target.kind == Unit.KIND_PILOT:
			return RuleResult.deny("Pilots on foot are BIOLOGICAL: immune to tech actions except Lock On and Scan.", "Core p.74 Fighting on the Ground")
		if Sight.unit_distance(state, u, target) > u.sensors:
			return RuleResult.deny("Out of Sensors range (%d)." % u.sensors, "actions: Bolster")
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var target := state.unit(String(params["target"]))
		target.statuses.erase("Bolstered")
		var events := Combat.add_status(state, target, "Bolstered", u.id, target.id)
		events.append({"type": "tech_action", "unit": u.id, "target": target.id, "action": "bolster", "rule_ref": "actions: Bolster"})
		return events


class FullTech:
	extends TurnAction
	## Full action: two Quick Tech options, the same one twice allowed (actions: Full Tech).
	## params: {"options": [{"type": "scan", "target": id}, {"type": "invade", "target": id}]}

	func type() -> String:
		return "full_tech"

	func cost() -> String:
		return TurnRules.FULL

	func _option(o: Variant) -> QuickTech:
		if not o is Dictionary:
			return null
		var h: Variant = RulesEngine.registry.get(String(o.get("type", "")))
		return h as QuickTech if h is QuickTech else null

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		if (u.counters.get("hacked", {}) as Dictionary).has("hack_slash"):
			return RuleResult.deny("Hack/Slash: no tech actions until you reboot or Shut Down.", "talents: Hacker")
		var options: Array = params.get("options", [])
		if options.size() != 2:
			return RuleResult.deny("Full Tech takes two Quick Tech options.", "actions: Full Tech")
		for o: Variant in options:
			var h := _option(o)
			if h == null:
				return RuleResult.deny("Not a Quick Tech option.", "actions: Full Tech")
			var r := h.check_tech(state, u, state.unit(String(o.get("target", ""))))
			if not r.ok:
				return r
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var events: Array[Dictionary] = []
		for o: Dictionary in params["options"]:
			var h := _option(o)
			var r := h.check_tech(state, u, state.unit(String(o.get("target", ""))))
			if not r.ok:
				events.append({"type": "action_skipped", "unit": u.id, "action": o["type"], "reason": r.reason, "rule_ref": r.rule_ref})
				continue
			events.append_array(h.apply(state, u, o))
		return events
