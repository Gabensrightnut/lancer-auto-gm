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
	if w.get("no_attack", false):
		return RuleResult.deny("%s can't make normal attacks; it's fired through its own rule." % w.get("name", ""), "weapons: " + String(w.get("name", "")))
	if Weapons.area(w) != "" and not a.has("aims"):
		var r := Attacks.weapon_ready(u, w, a.get("improvised", false))
		if not r.ok:
			return r
		var plan := Areas.plan(state, u, w, TurnAction.cell_param(a, "aim"), int(a.get("aim_level", -1)), TurnAction.cell_param(a, "from"))
		return RuleResult.allow() if plan["ok"] else RuleResult.deny(plan["reason"], plan["rule_ref"])
	if a.has("targets") and int(WeaponRules.rules(w).get("targets", 1)) > 1:
		var ids: Variant = a["targets"]
		if not ids is Array or (ids as Array).is_empty() or (ids as Array).size() > int(WeaponRules.rules(w)["targets"]):
			return RuleResult.deny("Up to %d targets." % int(WeaponRules.rules(w)["targets"]), ref)
		for id: Variant in ids:
			var pp := Attacks.preview(state, u, w, state.unit(String(id)), a)
			if not pp["ok"]:
				return RuleResult.deny(pp["reason"], pp["rule_ref"])
		return RuleResult.allow()
	if Weapons.area(w) != "" and a.has("aims"):
		var aims: Variant = a["aims"]
		if not aims is Array or (aims as Array).size() > int(WeaponRules.rules(w).get("blasts", 1)):
			return RuleResult.deny("Up to %d areas." % int(WeaponRules.rules(w).get("blasts", 1)), ref)
		var seen := {}
		for aim: Variant in aims:
			var plan := Areas.plan(state, u, w, Vector2i(int(aim[0]), int(aim[1])), -1)
			if not plan["ok"]:
				return RuleResult.deny(plan["reason"], plan["rule_ref"])
			for c: Array in plan["cells"]:
				if seen.has(c):
					return RuleResult.deny("The areas can't overlap.", ref)
				seen[c] = true
		return RuleResult.allow()
	var p := Attacks.preview(state, u, w, state.unit(String(a.get("target", ""))), a)
	if p.get("grey_area", "") != "":
		return Rulings.needed(String(p["grey_area"]))
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
	if Weapons.area(w) != "" and a.has("aims") and int(WeaponRules.rules(w).get("blasts", 1)) > 1:
		# Pinaka: up to two blast areas from one attack, damage rolled once.
		var events: Array[Dictionary] = []
		var shared := {}
		var first := true
		for aim: Array in a["aims"]:
			var one := a.duplicate()
			one["aim"] = aim
			one["_shared"] = shared
			if not first:
				one["skip_spend"] = true
			events.append_array(Areas.attack(state, u, w, one))
			first = false
		return events
	if Weapons.area(w) != "":
		return Areas.attack(state, u, w, a)
	if a.has("targets") and int(WeaponRules.rules(w).get("targets", 1)) > 1:
		# Sharanga: two targets at a time; the damage is rolled once and bonus damage halved.
		var events: Array[Dictionary] = []
		var shared := {}
		var ids: Array = a["targets"]
		for id: Variant in ids:
			var o := state.unit(String(id))
			var opts := a.duplicate()
			opts["shared_damage"] = shared
			opts["area_targets"] = ids.size()
			opts["skip_spend"] = id != ids[0]
			opts["no_bonus_damage"] = aux
			if o != null and Attacks.preview(state, u, w, o, opts)["ok"]:
				events.append_array(Attacks.attack(state, u, w, o, opts))
		return events
	var target := state.unit(String(a["target"]))
	var opts := a.duplicate()
	opts["no_bonus_damage"] = aux
	opts["action"] = String(a.get("_action", "attack"))
	var p := Attacks.preview(state, u, w, target, opts)
	if not p["ok"]:
		# An earlier attack in the same action changed things (target destroyed, pushed away).
		return [{"type": "attack_skipped", "attacker": u.id, "weapon": a["weapon"], "target": a["target"], "reason": p["reason"], "rule_ref": p["rule_ref"]}] as Array[Dictionary]
	if int(WeaponRules.rules(w).get("chain", 0)) > 0 and a.has("chain"):
		# Arc Projector: on a hit, another target within range 3 of the last, 1 heat each, no
		# bonus damage, nobody twice.
		var events: Array[Dictionary] = Attacks.attack(state, u, w, target, opts)
		var last := target
		var hit := CloseCombat._hit(events)
		for id: Variant in a["chain"]:
			var nxt := state.unit(String(id))
			if not hit or nxt == null or nxt == target or not Combat.is_present(nxt) or Sight.unit_distance(state, last, nxt) > int(WeaponRules.rules(w)["chain"]):
				break
			events.append_array(Combat.apply_heat(state, u, 1, String(w.get("name", ""))))
			var o2 := opts.duplicate()
			o2["skip_spend"] = true
			o2["no_bonus_damage"] = true
			var more := Attacks.attack(state, u, w, nxt, o2)
			events.append_array(more)
			hit = CloseCombat._hit(more)
			last = nxt
		return events
	if WeaponRules.rules(w).get("line_attack", false):
		# Impact Lance: also attacks every character on the line to the target, 1 heat each
		# past the first.
		var events: Array[Dictionary] = []
		var extra := WeaponRules.line_targets(state, u, target)
		for o: Unit in extra:
			var o_opts := opts.duplicate()
			o_opts["skip_spend"] = true
			events.append_array(Attacks.attack(state, u, w, o, o_opts))
		events.append_array(Attacks.attack(state, u, w, target, opts))
		if not extra.is_empty():
			events.append_array(Combat.apply_heat(state, u, extra.size(), "Impact Lance"))
		return events
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
		var spin: Dictionary = WeaponRules.rules(w).get("spin_up", {})
		if w.get("size", "") == "Superheavy" and not (spin.get("skirmish_only_standard", false) and not w.get("spun", false)):
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
