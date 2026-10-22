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
		if used.has(type()) and int(u.turn.get("free_quick", 0)) <= 0:
			return RuleResult.deny("Pick a different Quick Tech option: each can be used once per turn.", "actions: Quick Tech")
		return check_tech(state, u, state.unit(String(params.get("target", ""))))

	func check_tech(state: GameState, u: Unit, target: Unit) -> RuleResult:
		return Attacks.tech_target_check(state, u, target)

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
