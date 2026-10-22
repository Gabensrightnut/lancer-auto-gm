class_name AttackActions
extends RefCounted
## Skirmish, Barrage and Improvised Attack.
## Each attack is {"weapon": "<key from loadout.weapons>", "target": "<unit id>",
## "knockback": bool/int, "use_lock_on": bool}. Area weapons (Blast, Burst, Cone, Line) take
## {"weapon", "aim": [x, y], "aim_level": n} instead of a target (Burst needs no aim).

const IMPROVISED := {"key": "improvised", "name": "Improvised Attack", "type": "Melee", "size": "",
	"damage": [{"type": "Kinetic", "val": "1d6"}], "range": [{"type": "Threat", "val": 1}], "tags": []}


static func _check_attack(state: GameState, u: Unit, a: Variant, ref: String) -> RuleResult:
	if not a is Dictionary:
		return RuleResult.deny("Each attack needs a weapon and a target.", ref)
	var w := Weapons.find(u, String(a.get("weapon", "")))
	if w.is_empty():
		return RuleResult.deny("No such weapon on this mech.", ref)
	if Weapons.area(w) != "":
		var r := Attacks.weapon_ready(u, w, a.get("improvised", false))
		if not r.ok:
			return r
		var plan := Areas.plan(state, u, w, TurnAction.cell_param(a, "aim"), int(a.get("aim_level", -1)))
		return RuleResult.allow() if plan["ok"] else RuleResult.deny(plan["reason"], plan["rule_ref"])
	var p := Attacks.preview(state, u, w, state.unit(String(a.get("target", ""))), a)
	if not p["ok"]:
		return RuleResult.deny(p["reason"], p["rule_ref"])
	return RuleResult.allow()


## Optional auxiliary follow-ups: a different AUXILIARY weapon on a mount already fired.
static func _check_aux(state: GameState, u: Unit, aux: Array, fired: Array[Dictionary], ref: String) -> RuleResult:
	var used_mounts := {}
	for a: Variant in aux:
		var r := _check_attack(state, u, a, ref)
		if not r.ok:
			return r
		var w := Weapons.find(u, String(a["weapon"]))
		if w.get("size", "") != "Auxiliary":
			return RuleResult.deny("Only an Auxiliary weapon can make the extra attack.", ref)
		var on_fired_mount := false
		for f in fired:
			if f["key"] == w["key"]:
				return RuleResult.deny("The extra Auxiliary attack must use a different weapon.", ref)
			on_fired_mount = on_fired_mount or int(f.get("mount", -1)) == int(w.get("mount", -2))
		if not on_fired_mount:
			return RuleResult.deny("The extra Auxiliary weapon must be on a mount you just fired.", ref)
		if used_mounts.has(w["mount"]):
			return RuleResult.deny("Only one extra Auxiliary attack per mount.", ref)
		used_mounts[w["mount"]] = true
	return RuleResult.allow()


static func _run(state: GameState, u: Unit, a: Dictionary, aux: bool) -> Array[Dictionary]:
	var w := Weapons.find(u, String(a["weapon"]))
	if Weapons.area(w) != "":
		return Areas.attack(state, u, w, a)
	var target := state.unit(String(a["target"]))
	var opts := a.duplicate()
	opts["no_bonus_damage"] = aux
	opts["action"] = String(a.get("_action", "attack"))
	var p := Attacks.preview(state, u, w, target, opts)
	if not p["ok"]:
		# An earlier attack in the same action changed things (target destroyed, pushed away).
		return [{"type": "attack_skipped", "attacker": u.id, "weapon": a["weapon"], "target": a["target"], "reason": p["reason"], "rule_ref": p["rule_ref"]}] as Array[Dictionary]
	return Attacks.attack(state, u, w, target, opts)


class Skirmish:
	extends TurnAction
	## Quick action: attack with one weapon (not Superheavy), plus optionally a different
	## Auxiliary weapon on the same mount (actions: Skirmish).
	## params: {"weapon", "target", "knockback", "use_lock_on", "aux": {"weapon", "target"}}

	func type() -> String:
		return "skirmish"

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var w := Weapons.find(u, String(params.get("weapon", "")))
		if w.get("size", "") == "Superheavy":
			return RuleResult.deny("Superheavy weapons can only be fired as part of a Barrage.", Attacks.REF_SKIRMISH)
		var r := AttackActions._check_attack(state, u, params, Attacks.REF_SKIRMISH)
		if not r.ok or not params.has("aux"):
			return r
		var fired: Array[Dictionary] = [w]
		return AttackActions._check_aux(state, u, [params["aux"]], fired, Attacks.REF_SKIRMISH)

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var p := params.duplicate()
		p["_action"] = "skirmish"
		var events := AttackActions._run(state, u, p, false)
		if params.has("aux"):
			var a: Dictionary = (params["aux"] as Dictionary).duplicate()
			a["_action"] = "skirmish"
			events.append_array(AttackActions._run(state, u, a, true))
		return events


class Barrage:
	extends TurnAction
	## Full action: attack with two weapons, or one Superheavy, plus optionally an Auxiliary
	## on each mount fired (actions: Barrage).
	## params: {"attacks": [{"weapon", "target", ...}, ...], "aux": [{"weapon", "target"}, ...]}

	func type() -> String:
		return "barrage"

	func cost() -> String:
		return TurnRules.FULL

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var attacks: Array = params.get("attacks", [])
		var fired: Array[Dictionary] = []
		for a: Variant in attacks:
			var r := AttackActions._check_attack(state, u, a, Attacks.REF_BARRAGE)
			if not r.ok:
				return r
			fired.append(Weapons.find(u, String(a["weapon"])))
		var superheavy: bool = fired.size() == 1 and fired[0].get("size", "") == "Superheavy"
		if not superheavy:
			if fired.size() != 2:
				return RuleResult.deny("Barrage attacks with two weapons, or one Superheavy weapon.", Attacks.REF_BARRAGE)
			if fired[0]["key"] == fired[1]["key"]:
				return RuleResult.deny("Barrage needs two different weapons.", Attacks.REF_BARRAGE)
			for f in fired:
				if f.get("size", "") == "Superheavy":
					return RuleResult.deny("A Superheavy weapon takes the whole Barrage.", Attacks.REF_BARRAGE)
		return AttackActions._check_aux(state, u, params.get("aux", []), fired, Attacks.REF_BARRAGE)

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var events: Array[Dictionary] = []
		for a: Dictionary in params["attacks"]:
			events.append_array(AttackActions._run(state, u, a, false))
		for a: Dictionary in params.get("aux", []):
			events.append_array(AttackActions._run(state, u, a, true))
		return events


class Improvised:
	extends TurnAction
	## Full action: melee attack on an adjacent target, 1d6 kinetic (actions: Improvised Attack).
	## Allowed while Jammed. params: {"target"}

	func type() -> String:
		return "improvised_attack"

	func cost() -> String:
		return TurnRules.FULL

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var p := Attacks.preview(state, u, AttackActions.IMPROVISED, state.unit(String(params.get("target", ""))), {"improvised": true})
		if not p["ok"]:
			return RuleResult.deny(p["reason"], p["rule_ref"])
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var opts := params.duplicate()
		opts["improvised"] = true
		return Attacks.attack(state, u, AttackActions.IMPROVISED, state.unit(String(params["target"])), opts)
