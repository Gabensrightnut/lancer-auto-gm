class_name AttackActions
extends RefCounted
## Skirmish, Barrage and Improvised Attack.
## Each attack is {"weapon": "<key from loadout.weapons>", "target": "<unit id>",
## "knockback": bool/int, "use_lock_on": bool}. Area weapons (Blast, Burst, Cone, Line) take
## {"weapon", "aim": [x, y], "aim_level": n} instead of a target (Burst needs no aim).

const IMPROVISED := {"key": "improvised", "name": "Improvised Attack", "type": "Melee", "size": "",
	"damage": [{"type": "Kinetic", "val": "1d6"}], "range": [{"type": "Threat", "val": 1}], "tags": []}


## Lancer Tactics option "lt_aux_mount": firing only the Auxiliary weapon of a mount that also
## has a Main weapon counts as firing the mount, without bonus damage.
static func lt_aux_only(state: GameState, u: Unit, w: Dictionary) -> bool:
	if String(w.get("size", "")) != "Auxiliary" or not HouseRuleSwitches.on(state, "lt_aux_mount"):
		return false
	for x: Dictionary in u.loadout.get("weapons", []):
		if x != w and int(x.get("mount", -1)) == int(w.get("mount", -2)) and String(x.get("size", "")) == "Main":
			return true
	return false


## Ghast Nexus deployed as a drone: Range and line of sight from the drone (weapons: Ghast
## Nexus). A destroyed drone can't be used until repaired. Returns the attack params to use, or
## {"denied": reason}.
static func from_drone(state: GameState, u: Unit, a: Dictionary) -> Dictionary:
	var w := Weapons.find(u, String(a.get("weapon", "")))
	if String(w.get("id", "")) != "mw_ghast_nexus":
		return a
	for d: Unit in state.units.values():
		if String(d.counters.get("owner", "")) != u.id or not String(d.counters.get("ability", "")).begins_with("w:" + String(w["key"])):
			continue
		if d.destroyed:
			return {"denied": "The Ghast drone was destroyed: repair it before using the weapon again."}
		var out := a.duplicate()
		out["origin_cell"] = d.cell
		return out
	return a


static func _check_attack(state: GameState, u: Unit, a: Variant, ref: String) -> RuleResult:
	if a is Dictionary and String(Weapons.find(u, String((a as Dictionary).get("weapon", ""))).get("id", "")) == "mw_lancaster_integrated":
		return GearSystems.check_latch(state, u, Weapons.find(u, String(a["weapon"])), state.unit(String((a as Dictionary).get("target", ""))))
	if a is Dictionary:
		var fd := AttackActions.from_drone(state, u, a)
		if fd.has("denied"):
			return RuleResult.deny(String(fd["denied"]), "weapons: Ghast Nexus")
		if fd.has("origin_cell") and not (a as Dictionary).has("origin_cell"):
			return _check_attack(state, u, fd, ref)
	if a is Dictionary and (a as Dictionary).get("lunge", false):
		# Hunter Lunge: check the attack from where the lunge ends.
		var lr := TalentRules.check_lunge(state, u, Weapons.find(u, String(a.get("weapon", ""))), state.unit(String(a.get("target", ""))))
		if not lr.ok:
			return lr
		var path := TalentRules.lunge_path(state, u, state.unit(String(a["target"])))
		var at: Array = [u.cell, u.level]
		var last: Array = path.back()
		u.cell = Vector2i(last[0], last[1])
		u.level = int(last[2])
		var inner: Dictionary = (a as Dictionary).duplicate()
		inner.erase("lunge")
		var r := _check_attack(state, u, inner, ref)
		u.cell = at[0]
		u.level = at[1]
		return r
	if not a is Dictionary:
		return RuleResult.deny("Each attack needs a weapon and a target.", ref)
	var w := WeaponRules.variant(Weapons.find(u, String(a.get("weapon", ""))), a)
	if w.is_empty():
		return RuleResult.deny("No such weapon on this mech.", ref)
	if u.counters.get("overheated", false) and HouseRuleSwitches.on(state, "hr_overheated") and (Weapons.has_tag(w, "tg_heat_self") or Weapons.has_tag(w, "tg_overkill")):
		return RuleResult.deny("Overheated (house rule): no Heat (Self) or Overkill weapons until you Stabilize to cool down.", "House rule: Overheated")
	if a.has("ammo"):
		var ar := TalentRules.check_ammo(u, w, String(a["ammo"]))
		if not ar.ok:
			return ar
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


static func _run(state: GameState, u: Unit, a0: Dictionary, aux: bool) -> Array[Dictionary]:
	var a := AttackActions.from_drone(state, u, a0)
	var lw := Weapons.find(u, String(a.get("weapon", "")))
	if String(lw.get("id", "")) == "mw_lancaster_integrated":
		return GearSystems.latch(state, u, lw, state.unit(String(a.get("target", ""))), a)
	if String(lw.get("id", "")) == "mw_fuel_rod_gun" and u.heat > 0:
		# Fuel Rod Gun: clear 4 heat when you attack with it.
		u.heat = maxi(0, u.heat - 4)
		var fr := _fire(state, u, WeaponRules.variant(lw, a), a, aux)
		fr.push_front({"type": "heat_changed", "unit": u.id, "amount": -4, "total": u.heat, "source": "Fuel Rod Gun"})
		return fr
	if String(Weapons.find(u, String(a.get("weapon", ""))).get("id", "")) == "mw_annihilation_nexus" and state.active_unit == u.id:
		u.counters["annihilation_round"] = state.round_number  # its secondary attack next turn
	var w := WeaponRules.variant(Weapons.find(u, String(a["weapon"])), a)
	var pre := TalentRules.spend_ammo(u, String(a.get("ammo", "")))
	var lunge: Array[Dictionary] = TalentRules.lunge(state, u, state.unit(String(a.get("target", "")))) if a.get("lunge", false) else ([] as Array[Dictionary])
	var events := lunge + _fire(state, u, w, a, aux)
	if not pre.is_empty():
		events.push_front(pre)
		events.append_array(TalentRules.shock_ammo(state, u, String(a.get("ammo", "")), state.unit(String(a.get("target", a.get("shock_target", "")))), events))
	if WeaponRules.rules(w).get("backblast", false) and a.has("target") and state.unit(String(a["target"])) != null:
		events.append_array(AttackActions.backblast(state, u, state.unit(String(a["target"]))))
	return events


## Tachyon Lance backblast: a cone 3 behind you; Engineering save or 4 burn and 2 heat; soft
## cover in it until the start of your next turn.
static func backblast(state: GameState, u: Unit, target: Unit) -> Array[Dictionary]:
	var aim := u.cell * 2 - target.cell
	var cells: Array = []
	for c in Areas.template(state.map.grid, "Cone", 3, state.map.grid.footprint(u.cell, u.size), aim):
		if state.map.has_cell(c):
			cells.append([c.x, c.y])
	var events: Array[Dictionary] = Zones.add(state, {"kind": "smoke", "owner": u.id, "label": "Backblast", "center": [u.cell.x, u.cell.y], "cells": cells,
		"expires": {"unit": u.id, "when": "start", "count": 1}, "rule_ref": "weapons: Tachyon Lance"})
	var ids: Array = state.units.keys()
	ids.sort()
	for id: String in ids:
		var o := state.unit(id)
		if o == u or not Combat.is_present(o) or o.kind == Unit.KIND_DEPLOYABLE or not cells.has([o.cell.x, o.cell.y]):
			continue
		var save := Combat.skill_check(state, o, "engineering", "Save vs backblast", u.save_target, 0, 0, [], true)
		events.append({"type": "skill_check", "unit": o.id, "check": save})
		if not save["success"]:
			events.append_array(Combat.deal_damage(state, o, [{"type": "Burn", "amount": 4}, {"type": "Heat", "amount": 2}], {"source": u.id}))
	return events


## Pinaka delayed impact: the areas are marked for everyone and land at the end of the next
## round for 3d6 explosive instead of 2d6; the user is Slowed until the end of its next turn.
static func delay_pinaka(state: GameState, u: Unit, w: Dictionary, a: Dictionary) -> Array[Dictionary]:
	var aims: Array = a.get("aims", [a.get("aim", [])])
	var events: Array[Dictionary] = Attacks._spend_weapon(state, u, w)
	var cells: Array = []
	for aim: Variant in aims:
		if aim is Array and (aim as Array).size() >= 2:
			cells.append_array(Zones.cells_around(state, [Vector2i(int(aim[0]), int(aim[1]))] as Array[Vector2i], 1))
	events.append_array(Zones.add(state, {"kind": "pinaka_strike", "owner": u.id, "label": "Pinaka: incoming", "cells": cells,
		"center": aims[0], "aims": aims, "weapon": String(w.get("key", "")), "land_round": state.round_number + 1, "rule_ref": "weapons: Pinaka Missiles"}))
	events.append_array(Combat.add_status(state, u, "Slowed", u.id, u.id))
	u.turn["attacked"] = true
	return events


## End of a round: delayed Pinaka strikes due now land.
static func land_delayed(state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for z: Dictionary in Zones.of_kind(state, "pinaka_strike").duplicate():
		if int(z.get("land_round", 0)) > state.round_number:
			continue
		events.append_array(Zones.remove(state, String(z["id"]), "landed"))
		var u := state.unit(String(z.get("owner", "")))
		if u == null or u.destroyed:
			continue  # PROVISIONAL: nobody left to guide them in
		var w: Dictionary = Weapons.find(u, String(z.get("weapon", ""))).duplicate(true)
		if w.is_empty():
			continue
		for d: Dictionary in w.get("damage", []):
			d["val"] = "3d6"
		var shared := {}
		var first := true
		for aim: Variant in z.get("aims", []):
			events.append_array(Areas.attack(state, u, w, {"aim": aim, "_shared": shared, "skip_spend": true, "reaction": true, "delayed_strike": true}))
			first = false
	return events


## Throughbolt Rounds: a line 3 path from you through anything in the way; everything on it
## takes 2 AP kinetic; the attack is then measured from the end of the path.
static func throughbolt(state: GameState, u: Unit, a: Dictionary) -> Dictionary:
	var toward: Variant = TurnAction.cell_param(a, "throughbolt")
	var events: Array[Dictionary] = []
	var line := state.map.grid.line(u.cell, toward)
	var path: Array[Vector2i] = []
	for i in range(1, mini(4, line.size())):
		path.append(line[i])
	var ids: Array = state.units.keys()
	ids.sort()
	for id: String in ids:
		var o := state.unit(id)
		if o == u or not Combat.is_present(o):
			continue
		for c in state.map.grid.footprint(o.cell, o.size):
			if path.has(c):
				events.append_array(Combat.deal_damage(state, o, [{"type": "Kinetic", "amount": 2}], {"ap": true, "source": u.id}))
				break
	return {"events": events, "end": path.back() if not path.is_empty() else u.cell}


static func _fire(state: GameState, u: Unit, w: Dictionary, a: Dictionary, aux: bool) -> Array[Dictionary]:
	if a.get("delayed", false) and String(w.get("id", "")) == "mw_pinaka_missiles":
		return AttackActions.delay_pinaka(state, u, w, a)
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
	var pre_events: Array[Dictionary] = []
	if a.has("throughbolt") and WeaponRules.rules(w).get("throughbolt", false):
		var tb := AttackActions.throughbolt(state, u, a)
		pre_events = tb["events"]
		opts["origin_cell"] = tb["end"]
	opts["no_bonus_damage"] = aux or AttackActions.lt_aux_only(state, u, w)
	opts["action"] = String(a.get("_action", "attack"))
	var p := Attacks.preview(state, u, w, target, opts)
	if not p["ok"]:
		# An earlier attack in the same action changed things (target destroyed, pushed away).
		pre_events.append({"type": "attack_skipped", "attacker": u.id, "weapon": a["weapon"], "target": a["target"], "reason": p["reason"], "rule_ref": p["rule_ref"]})
		return pre_events
	if not pre_events.is_empty():
		pre_events.append_array(Attacks.attack(state, u, w, target, opts))
		return pre_events
	if Effects.has(u, "tlaloc"):
		# TLALOC: reroll a missed attack once against a new target within Range.
		var ev := Attacks.attack(state, u, w, target, opts)
		if not CloseCombat._hit(ev):
			var other := AISystems.tlaloc_retarget(state, u, w, target, [target.id])
			if other != null:
				var o2 := opts.duplicate()
				o2["skip_spend"] = true
				ev.append({"type": "attack_retargeted", "attacker": u.id, "from": target.id, "to": other.id, "rule_ref": "systems: TLALOC-Class NHP"})
				ev.append_array(Attacks.attack(state, u, w, other, o2))
		return ev
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
	if int(WeaponRules.rules(w).get("splash", 0)) > 0:
		# Annihilator: on a hit, a secondary attack on everyone within burst 1 of the target
		# (no bonus damage, no heat, no further secondary attacks).
		var events: Array[Dictionary] = Attacks.attack(state, u, w, target, opts)
		if CloseCombat._hit(events):
			var ids: Array = state.units.keys()
			ids.sort()
			for id: String in ids:
				var o := state.unit(id)
				if o == u or o == target or not Combat.is_present(o) or o.kind == Unit.KIND_DEPLOYABLE or Sight.unit_distance(state, o, target) > int(WeaponRules.rules(w)["splash"]):
					continue
				var o2 := opts.duplicate()
				o2["skip_spend"] = true
				o2["no_bonus_damage"] = true
				o2["area_origin"] = Sight.body_of(state, target)
				events.append_array(Attacks.attack(state, u, w, o, o2))
		return events
	return Attacks.attack(state, u, w, target, opts)


class Backswing:
	extends TurnAction
	## Executioner 1, Backswing Cut: after a hit with a Heavy or Superheavy melee weapon, a free
	## attack with it on a different character within Threat and line of sight, half damage.
	## params: {"target"}

	func type() -> String:
		return "backswing"

	func cost() -> String:
		return TurnRules.FREE

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var bs: Dictionary = u.turn.get("backswing", {})
		if bs.is_empty():
			return RuleResult.deny("Only right after a hit with a Heavy or Superheavy melee weapon.", "talents: Executioner")
		var t := state.unit(String(params.get("target", "")))
		if t == null or t.id == String(bs["not"]) or t.kind == Unit.KIND_DEPLOYABLE:
			return RuleResult.deny("Choose a different character.", "talents: Executioner")
		var p := Attacks.preview(state, u, Weapons.find(u, String(bs["weapon"])), t, {"fired_by_rule": true})
		return RuleResult.allow() if p["ok"] else RuleResult.deny(p["reason"], p["rule_ref"])

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var bs: Dictionary = u.turn["backswing"]
		u.turn.erase("backswing")
		TalentRules._use_round(state, u, "backswing")
		return Attacks.attack(state, u, Weapons.find(u, String(bs["weapon"])), state.unit(String(params["target"])),
			{"fired_by_rule": true, "skip_spend": true, "half_damage": true, "backswing": true})


class HunterThrow:
	extends TurnAction
	## Hunter 3: after a melee hit, a free thrown attack with an Auxiliary melee weapon on any
	## character in Range; no bonus damage. params: {"weapon", "target"}

	func type() -> String:
		return "hunter_throw"

	func cost() -> String:
		return TurnRules.FREE

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		if not u.turn.get("hunter_throw", false):
			return RuleResult.deny("Only right after a melee hit (Hunter).", "talents: Hunter")
		var w := Weapons.find(u, String(params.get("weapon", "")))
		if String(w.get("size", "")) != "Auxiliary" or String(w.get("type", "")) != "Melee":
			return RuleResult.deny("Throw an Auxiliary melee weapon.", "talents: Hunter")
		var p := Attacks.preview(state, u, w, state.unit(String(params.get("target", ""))), {"fired_by_rule": true})
		return RuleResult.allow() if p["ok"] else RuleResult.deny(p["reason"], p["rule_ref"])

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		u.turn.erase("hunter_throw")
		TalentRules._use_round(state, u, "hunter_throw")
		return Attacks.attack(state, u, Weapons.find(u, String(params["weapon"])), state.unit(String(params["target"])),
			{"fired_by_rule": true, "no_bonus_damage": true, "hunter_throw": true})


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
		if Rulings.lancer_tactics(state, "lt_split_barrage") and int(w.get("mount", -1)) >= 0 and (u.turn.get("skirmish_mounts", []) as Array).has(int(w.get("mount", -1))):
			# Lancer Tactics split Barrage: the second shot must come from a different mount.
			return RuleResult.deny("Already fired that mount this turn: use a weapon on another mount.", Attacks.REF_BARRAGE)
		var r := AttackActions._check_attack(state, u, params, Attacks.REF_SKIRMISH)
		if not r.ok or not params.has("aux"):
			return r
		var fired: Array[Dictionary] = [w]
		return AttackActions._check_aux(state, u, [params["aux"]], fired, Attacks.REF_SKIRMISH)

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var p := params.duplicate()
		p["_action"] = "skirmish"
		var sm: Array = u.turn.get("skirmish_mounts", [])
		sm.append(int(Weapons.find(u, String(params.get("weapon", ""))).get("mount", -1)))
		u.turn["skirmish_mounts"] = sm
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
		var p := Attacks.preview(state, u, TalentRules.improvised(u, AttackActions.IMPROVISED), state.unit(String(params.get("target", ""))), {"improvised": true})
		if not p["ok"]:
			return RuleResult.deny(p["reason"], p["rule_ref"])
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var opts := params.duplicate()
		opts["improvised"] = true
		return Attacks.attack(state, u, TalentRules.improvised(u, AttackActions.IMPROVISED), state.unit(String(params["target"])), opts)
