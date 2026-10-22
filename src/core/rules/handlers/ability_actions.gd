class_name AbilityActions
extends RefCounted
## The "activate" action for abilities (see Abilities), and the action-bar listing.


class Activate:
	extends ActionHandler
	## {"type": "activate", "actor": unit, "params": {"ability": key, "to": [x, y] or [[x, y], ...]
	## (deploy), "target": unit id (Invade options and abilities that target someone)}}

	func type() -> String:
		return "activate"

	func validate(state: GameState, action: Dictionary) -> RuleResult:
		var u := state.unit(action["actor"])
		var r := TurnRules.check_own_turn(state, u)
		if not r.ok:
			return r
		var params: Dictionary = action.get("params", {})
		var a := Abilities.find(u, String(params.get("ability", "")))
		r = Abilities.can_activate(state, u, a)
		if not r.ok:
			return r
		if a.get("requires_core_active", false) and not u.counters.get("core_active", false):
			return RuleResult.deny("Only while %s is active." % a["source_name"], "frames: core_system")
		if a.get("activation", "") == "Protocol" and (u.turn.get("protocols", []) as Array).has(a["key"]):
			return RuleResult.deny("Each Protocol only once per turn.", "Core p.73 Protocol")
		r = TurnRules.can_spend(u, Abilities.cost_of(a), Abilities.economy_name(a))
		if not r.ok:
			return r
		match a.get("kind", "action"):
			"deploy":
				var spots := AbilityActions.spots(params)
				if spots.is_empty() or spots.size() > int(a.get("instances", 1)):
					return RuleResult.deny("Choose where to deploy it (params.to).", Abilities.REF)
				for c: Vector2i in spots:
					var ok := Abilities.check_spot(state, u, a["deployable"], c)
					if not ok.ok:
						return ok
				var extra := AbilityActions.extra_mines(params)
				if not extra.is_empty():
					var mr := AbilityActions.check_extra_mines(state, u, a, extra)
					if not mr.ok:
						return mr
			"action":
				var ops_ok := AbilityActions.check_ops(state, u, a, params)
				if not ops_ok.ok:
					return ops_ok
				if a.get("activation", "") == "Invade" or (a.get("ops", []) as Array).any(func(o: Dictionary) -> bool: return o.get("tech_attack", false)):
					return Attacks.tech_target_check(state, u, state.unit(String(params.get("target", ""))), "invade")
		return RuleResult.allow()

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		var u := state.unit(action["actor"])
		var params: Dictionary = action.get("params", {})
		var a := Abilities.find(u, String(params["ability"]))
		var acted: bool = u.turn.get("acted", false)
		TurnRules.spend(u, Abilities.cost_of(a), Abilities.economy_name(a))
		Abilities.spend(state, u, a)
		if a.get("activation", "") == "Protocol":
			u.turn["acted"] = acted  # a Protocol doesn't count as acting (tags: Ordnance)
			var p: Array = u.turn.get("protocols", [])
			p.append(a["key"])
			u.turn["protocols"] = p
		var events: Array[Dictionary] = [{"type": "activated", "unit": u.id, "ability": a["key"], "name": a["name"],
			"source": a.get("source_name", ""), "activation": a.get("activation", ""), "automated": a.get("automated", false),
			"detail": a.get("detail", ""), "rule_ref": Abilities.REF}]
		var self_heat := Abilities.heat_self(state, u, a)
		if self_heat > 0:
			events.append_array(Combat.apply_heat(state, u, self_heat, "Heat (Self): " + String(a.get("source_name", ""))))
		match a.get("kind", "action"):
			"deploy":
				for c: Vector2i in AbilityActions.spots(params):
					events.append_array(Abilities.deploy(state, u, a, c))
				var extra := AbilityActions.extra_mines(params)
				if not extra.is_empty():
					# Iskander Mine Deployers: up to two more mines next to it, as a free action.
					u.counters["mine_deployers_round"] = state.round_number
					var src := Abilities.source_state(u, String(a["source_key"]))
					for c: Vector2i in extra:
						if int(src["uses"]) > 0:
							src["uses"] = int(src["uses"]) - 1
						events.append_array(Abilities.deploy(state, u, a, c))
			"recall":
				events.append_array(Abilities.recall(state, u, a))
			_:
				var target := state.unit(String(params.get("target", "")))
				var hit := true
				var tech: bool = (a.get("ops", []) as Array).any(func(o: Dictionary) -> bool: return o.get("tech_attack", false))
				if a.get("activation", "") == "Invade" or tech:
					# Invade options and systems that make a tech attack (Markerlight, Tracking Bug).
					var topts := params.duplicate()
					for o: Dictionary in a.get("ops", []):
						if o.get("op", "") == "npc_tech":
							topts["tech_bonus"] = int(o.get("attack_bonus", 0))  # an NPC tech feature's own attack bonus
							topts["tech_accuracy"] = int(o.get("accuracy", 0))
					var r := Attacks.tech_attack(state, u, target, String(a["name"]), topts)
					events.append_array(r["events"])
					hit = r["hit"]
					if hit and a.get("activation", "") == "Invade":
						events.append_array(Combat.apply_heat(state, target, 2, u.id))
				if hit:
					events.append_array(AbilityActions.apply_ops(state, u, a, target, params))
		return events


static func spots(params: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var v: Variant = params.get("to")
	if v is Array and not (v as Array).is_empty() and v[0] is Array:
		for c: Array in v:
			out.append(Vector2i(int(c[0]), int(c[1])))
	else:
		var one: Variant = TurnAction.cell_param(params, "to")
		if one != null:
			out.append(one)
	return out


## Applies an ability's encoded ops; unencoded abilities go to the table as text.
static func apply_ops(state: GameState, u: Unit, a: Dictionary, target: Unit, params: Dictionary = {}) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not a.get("automated", false):
		events.append({"type": "manual_effect", "unit": u.id, "source": a["name"], "text": a.get("detail", ""),
			"note": "Not automated yet: the table applies this.", "guidance": Automation.MANUAL_GUIDANCE})
		return events
	for op: Dictionary in a.get("ops", []):
		var duration := String(op.get("duration", "scene"))
		match op.get("op", ""):
			"status":
				var who: Unit = u if op.get("who", "self") == "self" else target
				if who == null:
					continue
				if duration == "start_next_turn":
					events.append_array(Combat.add_status(state, who, String(op["status"]), a["name"], "", u.id))
				elif duration == "end_next_turn":
					events.append_array(Combat.add_status(state, who, String(op["status"]), a["name"], who.id))
				else:
					events.append_array(Combat.add_status(state, who, String(op["status"]), a["name"]))
			"self_effects":
				events.append_array(Effects.activate(state, u, op.get("effects", []), String(a["name"]), duration))
			"focus":
				# Death's Head Mark for Death: focus on one character; Immobilized and no
				# reactions while focusing.
				events.append_array(AbilityActions._unfocus(u))
				u.counters["focus"] = target.id
				events.append_array(Combat.add_status(state, u, "Immobilized", "Mark for Death"))
				events.append({"type": "effect_triggered", "unit": u.id, "effect": "Mark for Death", "target": target.id, "rule_ref": "frames: Death's Head core system"})
			"unfocus":
				events.append_array(AbilityActions._unfocus(u))
			"contest_prone":
				events.append_array(GearSystems.contest_prone(state, u, target))
			"argonaut":
				events.append_array(GearSystems.argonaut(state, u, target))
			"whitewash":
				events.append_array(GearSystems.whitewash(state, u, target, params))
			"overshield":
				events.append_array(GearSystems.overshield(state, u, target, op))
			"remove_effects":
				events.append_array(GearSystems.remove_effects(state, u, String(op.get("label", ""))))
			"impale":
				events.append_array(GearSystems.impale(state, u, target))
			"detonate":
				for m: Unit in state.units.values().duplicate():
					if m.counters.get("owner", "") == u.id and m.name == String(op.get("deployable", "")) and not m.destroyed and m.counters.get("armed", false):
						events.append_array(Abilities.detonate(state, m, u))
			"toggle":
				events.append_array(GearSystems.toggle(state, u, String(op.get("label", a["name"])), op.get("effects", [])))
			"reload":
				events.append_array(GearSystems.reload_one(state, u, String(params.get("weapon", "")), String(a["name"])))
			"flak":
				events.append_array(GearSystems.flak(state, u, target))
			"napalm":
				events.append_array(GearSystems.napalm(state, u, op, params))
			"auto_cooler":
				u.counters["auto_cooler"] = true
			"agni":
				u.counters["agni"] = true
			"gravity_grenade":
				events.append_array(GearSystems.gravity_grenade(state, u, target))
			"grounding_mine":
				events.append_array(GearSystems.grounding_mine(state, u, target))
			"repulser":
				events.append_array(GearSystems.repulser(state, u))
			"clamp_bombs":
				events.append_array(GearSystems.clamp_bombs(state, u, target))
			"charge_bolt":
				u.counters["stasis_bolt"] = true
			"stasis":
				events.append_array(GearSystems.stasis(state, u, target))
			"enclave":
				events.append_array(GearSystems.enclave(state, u))
			"plasma_gauntlet":
				events.append_array(GearSystems.plasma_gauntlet(state, u, target))
			"extra_actions":
				u.turn["free_quick"] = int(u.turn.get("free_quick", 0)) + int(op.get("quick", 2))
			"stabilize_quick":
				var stab: TurnAction = RulesEngine.registry["stabilize"]
				events.append_array(stab.apply(state, u, params))
			"eject_power_cores", "beckon", "summon", "smite", "sear", "logic_bomb", "banish", "chains", "excommunicate", "ophidian_trek", "fold_space", "hunter_lock":
				events.append_array(GearSystems.horus_effect(state, u, target, op, params))
			"electropulse":
				events.append_array(GearSystems.electropulse(state, u))
			"emp_pulse":
				events.append_array(GearSystems.emp_pulse(state, u))
			"lightning":
				events.append_array(GearSystems.lightning(state, u, 2, false))
			"eye_of_horus":
				events.append_array(Effects.activate(state, u, [{"kind": "eye_of_horus"}], "Eye of Horus", "end_next_turn"))
				for o: Unit in state.units.values():
					if o.side != u.side and Combat.is_present(o) and Sight.unit_distance(state, u, o) <= u.sensors:
						ViewFilter.reveal_in_state(state, u.side, o.id)
			"swarm_body":
				events.append_array(Zones.add(state, {"kind": "swarm_body", "owner": u.id, "anchor": u.id, "radius": 1, "cells": [], "center": [u.cell.x, u.cell.y],
					"at": [u.cell.x, u.cell.y, u.level], "still": -1, "label": "Swarm Body", "rule_ref": "systems: Swarm Body"}))
			"interdiction":
				events.append_array(Zones.add(state, {"kind": "interdiction", "owner": u.id, "anchor": u.id, "radius": 3, "cells": [], "center": [u.cell.x, u.cell.y],
					"label": "Interdiction Field", "rule_ref": "systems: Interdiction Field"}))
				events.append_array(Combat.add_status(state, u, "Slowed", "Interdiction Field"))
			"attach_cable":
				events.append_array(Riders.attach_cable(state, u, target))
			"transfer_control":
				events.append_array(Riders.transfer(state, u))
			"flash_grenade":
				var fa: Vector2i = TurnAction.cell_param(params, "aim")
				GearSystems._mark_launcher(state, u, op, fa)
				events.append_array(Zones.add(state, {"kind": "flash", "owner": u.id, "label": "Flash", "center": [fa.x, fa.y],
					"cells": Zones.cells_around(state, [fa] as Array[Vector2i], 3), "expires": {"unit": u.id, "when": "end", "count": 2 if state.active_unit == u.id else 1},
					"rule_ref": "systems: Flash Charges"}))
			"hardlight":
				var foot: Array[Vector2i] = []
				foot.assign(state.map.grid.footprint(u.cell, u.size))
				for z: Dictionary in Zones.of_kind(state, "hardlight"):
					if z.get("owner", "") == u.id:
						events.append_array(Zones.remove(state, String(z["id"]), "replaced"))
				events.append_array(Zones.add(state, {"kind": "hardlight", "owner": u.id, "label": "Hardlight shield", "center": [u.cell.x, u.cell.y],
					"cells": Zones.cells_around(state, foot, 3), "rule_ref": "systems: Hardlight Defense System"}))
				events.append_array(Combat.add_status(state, u, "Immobilized", "Hardlight Defense System"))
			"blinkshield":
				events.append_array(Zones.blinkshield(state, u))
			"oasis":
				for z: Dictionary in Zones.of_kind(state, "oasis"):
					if z.get("owner", "") == u.id:
						events.append_array(Zones.remove(state, String(z["id"]), "used again"))
				events.append_array(Zones.add(state, {"kind": "oasis", "owner": u.id, "label": "Oasis Wall", "center": [u.cell.x, u.cell.y],
					"cells": [], "rule_ref": "systems: Oasis Wall"}))
				events.append_array(Effects.activate(state, u, [{"kind": "oasis_wall"}], "Oasis Wall", "start_next_turn"))
			"hand_over":
				events.append_array(AISystems.hand_over(state, u, String(a["name"])))
			"sekhmet":
				events.append_array(AISystems.sekhmet(state, u))
			"sekhmet_off":
				events.append_array(AISystems.sekhmet_off(state, u))
			"simulacrum":
				events.append_array(AISystems.simulacrum(state, u, params))
			"duat":
				events.append_array(Combat.apply_heat(state, target, 2, u.id))
				events.append_array(AISystems.duat(state, u, target))
			"uncle_attack":
				# UNCLE: a free attack at +2 Difficulty with its weapon; that weapon then can't be
				# used again until the start of your next turn.
				var uw := Weapons.find(u, String(a["source_key"]).trim_prefix("mod:"))
				events.append_array(Attacks.attack(state, u, uw, target, {"extra_difficulty": 2, "extra_label": "UNCLE"}))
				Weapons.state_of(u, uw)["uncle_lock"] = true
			"shock_wreath":
				var had_burn := target.burn > 0
				var roll := state.dice.roll("1d6")
				events.append_array(Combat.deal_damage(state, target, [{"type": "Burn", "amount": int(roll["total"])}], {"source": u.id}))
				if had_burn:
					events.append_array(Combat.add_status(state, target, "Blinded", u.id, target.id))
			"fire_integrated":
				events.append_array(Attacks.attack(state, u, Weapons.find(u, "cbi:0"), target, {"fired_by_rule": true}))
			"fire_weapon":
				var fw := Weapons.find(u, String(a["source_key"]).trim_prefix("w:"))
				events.append_array(Attacks.attack(state, u, fw, target, {"fired_by_rule": true}))
			"ferrous_lash":
				events.append_array(GearSystems.ferrous_lash(state, u, target, params))
			"shrike_code", "mirage", "stalk_prey", "terrify", "tracking_bug", "markerlight":
				events.append_array(GearSystems.tech_effect(state, u, target, op, params))
			"stuncrown":
				events.append_array(GearSystems.stuncrown(state, u))
			"javelin":
				events.append_array(GearSystems.javelin(state, u, params))
			"cloaking_field":
				events.append_array(GearSystems.cloaking_field(state, u))
			"remove_zone":
				for z: Dictionary in Zones.of_kind(state, String(op.get("kind", ""))):
					if z.get("owner", "") == u.id:
						events.append_array(Zones.remove(state, String(z["id"]), "deactivated"))
			"turn_flag":
				u.turn[String(op.get("flag", ""))] = true
			"lucifer":
				u.turn["lucifer"] = u.heat  # its Heat (Self) is already taken
			"spin_up", "spin_down":
				events.append_array(WeaponRules.spin(state, u, String(op.get("weapon", "")), op["op"] == "spin_up"))
			"blast_save":
				events.append_array(GearSystems.blast_save(state, u, op, params))
			"smoke":
				events.append_array(GearSystems.smoke(state, u, op, params))
			"project_shield":
				events.append_array(GearSystems.project_shield(state, u, target))
			"detach":
				events.append_array(FrameSystems.detach(state, u, "detached"))
			"hologram_teleport":
				events.append_array(Zones.hologram_teleport(state, u, params))
			"fire_rail":
				events.append_array(FrameSystems.fire_rail(state, u, params))
			"core_off":
				events.append_array(FrameSystems.core_off(state, u))
			"tachyon_target":
				# Saladin Tachyon Shield: choose a new ally to protect.
				u.counters["tachyon_target"] = target.id
				events.append({"type": "effect_triggered", "unit": u.id, "effect": "Tachyon Shield", "target": target.id, "rule_ref": "frames: Saladin core system"})
			"omnigun":
				# Pegasus Ushabti Omnigun: not an attack; hits automatically, ignores cover,
				# bypasses Immunity, and can't be reduced.
				events.append_array(Combat.deal_damage(state, target, [{"type": "Kinetic", "amount": int(op.get("damage", 1))}],
					{"source": u.id, "ap": true, "unreducible": true, "bypass_immunity": true}))
			"revive":
				# Lancaster Combat Repair: 4 Repairs bring a destroyed mech back to 1 Structure, 1 Stress, 1 HP.
				if target != null and target.destroyed:
					u.repairs -= int(op.get("repairs", 4))
					target.destroyed = false
					target.structure = 1
					target.stress = 1
					target.hp = 1
					events.append({"type": "revived", "unit": target.id, "by": u.id})
	return events


## Target rules for an op: op.target = {who: ally|hostile|any|ally_mech, range, los?,
## adjacent?, or_space?}.
static func check_target_op(state: GameState, u: Unit, op: Dictionary, t: Unit, params: Dictionary) -> RuleResult:
	var spec: Dictionary = op["target"]
	var ref := "systems: " + String(op.get("label", ""))
	if t == null and spec.get("or_space", false) and TurnAction.cell_param(params, "aim") != null:
		return GearSystems.check_aimed(state, u, {"range": spec.get("range", 5)}, params)
	if t == null or not Combat.is_present(t) or t.kind == Unit.KIND_DEPLOYABLE:
		return RuleResult.deny("Choose a character (params.target).", ref)
	match String(spec.get("who", "any")):
		"ally":
			if t.side != u.side or t == u:
				return RuleResult.deny("Choose an allied character.", ref)
		"ally_mech":
			if t.side != u.side or t.kind != Unit.KIND_MECH:
				return RuleResult.deny("Choose an allied mech.", ref)
		"other":
			if t == u:
				return RuleResult.deny("Choose another character.", ref)
	var reach := 1 if spec.get("adjacent", false) else (u.sensors if str(spec.get("range", 5)) == "sensors" else int(spec.get("range", 5)))
	if Sight.unit_distance(state, u, t) > reach:
		return RuleResult.deny("It must be %s." % ("adjacent" if reach == 1 else "within range %d" % reach), ref)
	if spec.get("los", false) and not Sight.unit_line_of_sight(state, u, t):
		return RuleResult.deny("No line of sight to the target.", Sight.REF_LOS)
	return RuleResult.allow()


static func extra_mines(params: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Variant in params.get("extra_mines", []):
		if c is Array and (c as Array).size() >= 2:
			out.append(Vector2i(int(c[0]), int(c[1])))
	return out


static func check_extra_mines(state: GameState, u: Unit, a: Dictionary, cells: Array[Vector2i]) -> RuleResult:
	var ref := "frames: Iskander, Mine Deployers"
	if not Effects.has(u, "mine_deployers") or String(a.get("deployable", {}).get("type", "")) != "Mine":
		return RuleResult.deny("Only the Iskander's Mine Deployers plant extra mines.", ref)
	if int(u.counters.get("mine_deployers_round", -1)) == state.round_number:
		return RuleResult.deny("Mine Deployers is 1/round.", ref)
	if cells.size() > 2:
		return RuleResult.deny("Up to two other mines.", ref)
	var src := Abilities.source_state(u, String(a["source_key"]))
	if int(src["uses"]) >= 0 and int(src["uses"]) < 1 + cells.size():
		return RuleResult.deny("Not enough mines left (Limited).", "tags: Limited")
	for c: Vector2i in cells:
		var body := Sight.make_body(state, c, state.map.ground_height(c), 0.5)
		if Sight.distance(state, Sight.body_of(state, u), body) > 1:
			return RuleResult.deny("The extra mines go in free spaces adjacent to the Iskander.", ref)
		var ok := Abilities.check_spot(state, u, a["deployable"], c)
		if not ok.ok:
			return ok
	return RuleResult.allow()


static func ally_in_sensors(state: GameState, u: Unit, t: Unit) -> RuleResult:
	if t == null or not Combat.is_present(t) or t.side != u.side or t == u or t.kind == Unit.KIND_DEPLOYABLE:
		return RuleResult.deny("Choose an allied character.", "frames: core_system")
	if Sight.unit_distance(state, u, t) > u.sensors:
		return RuleResult.deny("It must be within Sensors (%d)." % u.sensors, "glossary: Sensors")
	return RuleResult.allow()


static func _unfocus(u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not u.counters.has("focus"):
		return events
	u.counters.erase("focus")
	if u.has_status("Immobilized") and u.statuses["Immobilized"].get("source", "") == "Mark for Death":
		events.append_array(Combat.remove_status(u, "Immobilized", "stopped focusing"))
	return events


## Ops that use a list of targets (params.targets), e.g. Monarch's missiles: each target
## saves or takes the damage (half on a success).
static func apply_target_ops(state: GameState, u: Unit, ops: Array, ids: Array) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for op: Dictionary in ops:
		if op.get("op", "") != "save_damage":
			continue
		var roll := state.dice.roll(String(op.get("damage", "1d6")))
		events.append({"type": "damage_rolled", "attacker": u.id, "target": "", "damage_type": op.get("type", "Kinetic"), "roll": roll, "crit": false})
		for id in ids:
			var t := state.unit(String(id))
			if t == null or not Combat.is_present(t):
				continue
			var success := false
			if not (t.kind == Unit.KIND_DEPLOYABLE and op.get("objects_hit", false)):  # objects are hit automatically
				var knock: bool = op.get("pull", false) or (op.get("on_fail", []) as Array).any(func(x: Dictionary) -> bool: return x.get("status", "") == "Prone")
				var extra: Array = GearSystems.prone_save_sources(t) if knock else []
				var acc := 0
				for x: Dictionary in extra:
					acc += int(x["value"])
				var save := Combat.skill_check(state, t, String(op.get("save", "agility")), "Save vs %s" % op.get("label", "core"), u.save_target, acc, 0, extra, true)
				events.append({"type": "skill_check", "unit": t.id, "check": save})
				success = save["success"]
				if not success:
					events.append_array(CoreBonuses.failed_save(state, u, t))
			var amount := int(roll["total"])
			if success:
				amount = amount - amount / 2 if op.get("half", false) else 0
				if op.get("half", false) and Effects.has(t, "heavy_shielding"):
					amount = mini(amount, 1)
			if amount > 0:
				events.append_array(Combat.deal_damage(state, t, [{"type": op.get("type", "Kinetic"), "amount": amount}], {"source": u.id, "area": true, "ap": op.get("ap", false)}))
			if success or not Combat.is_present(t):
				continue
			# On a failure: conditions (Blackbeard: Prone, then pulled, then Immobilized).
			for st: Dictionary in op.get("on_fail", []):
				if st.get("after_pull", false):
					continue
				events.append_array(Combat.add_status(state, t, String(st["status"]), u.id, t.id if st.get("duration", "") == "end_next_turn" else ""))
			if op.get("pull", false):
				events.append_array(Attacks.pull(state, t, u))
			for st: Dictionary in op.get("on_fail", []):
				if st.get("after_pull", false) and Combat.is_present(t):
					events.append_array(Combat.add_status(state, t, String(st["status"]), u.id, t.id if st.get("duration", "") == "end_next_turn" else ""))
	return events


## Extra checks some ops need before activating.
static func check_ops(state: GameState, u: Unit, a: Dictionary, params: Dictionary) -> RuleResult:
	for op: Dictionary in a.get("ops", []):
		if op.get("op", "") in ["focus", "omnigun"]:
			var t := state.unit(String(params.get("target", "")))
			var ref := "frames: %s" % a.get("source_name", "")
			if t == null or not Combat.is_present(t) or t == u or t.kind == Unit.KIND_DEPLOYABLE:
				return RuleResult.deny("Choose a character.", ref)
			var d := Sight.unit_distance(state, u, t)
			if d > int(op.get("range", 50)) or d <= int(op.get("min", 0)):
				return RuleResult.deny("The target must be within range %d%s." % [int(op.get("range", 50)),
					(" but further than range %d" % int(op["min"])) if op.has("min") else ""], ref)
			if op.get("los", false) and not Sight.unit_line_of_sight(state, u, t):
				return RuleResult.deny("No line of sight to the target.", Sight.REF_LOS)
		if op.has("target"):
			var tr := AbilityActions.check_target_op(state, u, op, state.unit(String(params.get("target", ""))), params)
			if not tr.ok:
				return tr
		if op.get("op", "") == "detonate":
			var any := false
			for m: Unit in state.units.values():
				any = any or (m.counters.get("owner", "") == u.id and m.name == String(op.get("deployable", "")) and not m.destroyed and m.counters.get("armed", false))
			if not any:
				return RuleResult.deny("No armed %s to detonate." % op.get("deployable", ""), "tags: Mine")
		if op.get("op", "") in ["hand_over", "sekhmet"]:
			if not AISystems.has_ai(u) or AISystems.controlled(u):
				return RuleResult.deny("Only a mech with the AI tag, not already under its AI's control.", AISystems.REF)
		if op.get("op", "") == "sekhmet_off":
			var tb := AISystems.check_take_back(state, u)
			if not tb.ok:
				return tb
		if op.get("op", "") == "simulacrum":
			var aim: Variant = TurnAction.cell_param(params, "aim")
			if aim == null or not state.map.has_cell(aim) or Sight.distance(state, Sight.body_of(state, u), Sight.make_body(state, aim, state.map.ground_height(aim), 0.5)) > 50:
				return RuleResult.deny("Choose a center within range 50 (params.aim).", "systems: ATHENA-Class NHP")
		if op.get("op", "") == "uncle_attack":
			var uw := Weapons.find(u, String(a["source_key"]).trim_prefix("mod:"))
			if (u.turn.get("fired", []) as Array).has(String(uw.get("key", ""))):
				return RuleResult.deny("UNCLE can't use a weapon that was already used this turn.", "mods: UNCLE-Class COMP/CON")
			var pv := Attacks.preview(state, u, uw, state.unit(String(params.get("target", ""))), {"extra_difficulty": 2})
			if not pv["ok"]:
				return RuleResult.deny(pv["reason"], pv["rule_ref"])
		if op.get("op", "") == "shock_wreath":
			var ww := String(a["source_key"]).trim_prefix("mod:")
			if not (u.turn.get("hits", {}).get(ww, []) as Array).has(String(params.get("target", ""))):
				return RuleResult.deny("Only right after hitting that character with the wreathed weapon this turn.", "mods: Shock Wreath")
		if op.get("op", "") == "fire_integrated":
			var fired: Array = u.turn.get("fired", [])
			if fired.filter(func(k: String) -> bool: return k != "cbi:0").is_empty():
				return RuleResult.deny("Only when you fire another weapon this turn.", "Core p.118")
			var pv2 := Attacks.preview(state, u, Weapons.find(u, "cbi:0"), state.unit(String(params.get("target", ""))), {"fired_by_rule": true})
			if not pv2["ok"]:
				return RuleResult.deny(pv2["reason"], pv2["rule_ref"])
		if op.get("op", "") == "fire_weapon":
			var fw := Weapons.find(u, String(a["source_key"]).trim_prefix("w:"))
			var pv := Attacks.preview(state, u, fw, state.unit(String(params.get("target", ""))), {"fired_by_rule": true})
			if not pv["ok"]:
				return RuleResult.deny(pv["reason"], pv["rule_ref"])
		if op.get("op", "") == "transfer_control" and Riders.passenger_of(state, u) == null and not u.counters.has("passenger_control"):
			return RuleResult.deny("There's no passenger to hand the controls to.", Riders.REF_COMPARTMENT)
		if op.get("op", "") in ["napalm", "flash_grenade"]:
			var nr := GearSystems.check_aimed(state, u, op, params)
			if not nr.ok:
				return nr
		if op.get("requires_status", "") != "" and not u.has_status(String(op["requires_status"])):
			return RuleResult.deny("This system can only be used in the %s." % op["requires_status"], "systems: " + String(a.get("source_name", "")))
		if op.get("op", "") == "stabilize_quick":
			var stab: TurnAction = RulesEngine.registry["stabilize"]
			var sr := stab.check(state, u, params)
			if not sr.ok:
				return sr
		if op.get("op", "") == "flak" and state.unit(String(params.get("target", ""))) != null and not state.unit(String(params.get("target", ""))).flying:
			return RuleResult.deny("Choose a flying character.", "systems: Flak Launcher")
		if op.get("op", "") == "javelin":
			var jr := GearSystems.check_javelin(state, u, params)
			if not jr.ok:
				return jr
		if op.get("op", "") in ["blast_save", "smoke"]:
			var gr := GearSystems.check_aimed(state, u, op, params)
			if not gr.ok:
				return gr
		if op.get("op", "") == "project_shield":
			var pt := state.unit(String(params.get("target", "")))
			if pt == null or pt == u or not Combat.is_present(pt) or not Sight.unit_line_of_sight(state, u, pt):
				return RuleResult.deny("Nominate a character in line of sight (params.target).", "systems: Type-3 Projected Shield")
		if op.get("op", "") == "detach" and not u.counters.has("symbiosis"):
			return RuleResult.deny("You aren't attached to a host.", "frames: Goblin core system")
		if op.get("op", "") == "hologram_teleport":
			var hr := Zones.check_hologram_teleport(state, u, params)
			if not hr.ok:
				return hr
		if op.get("op", "") == "fire_rail":
			var rr := FrameSystems.check_rail(state, u, params)
			if not rr.ok:
				return rr
		if op.get("op", "") == "tachyon_target":
			var r := AbilityActions.ally_in_sensors(state, u, state.unit(String(params.get("target", ""))))
			if not r.ok:
				return r
		if op.get("op", "") == "revive":
			var t := state.unit(String(params.get("target", "")))
			if t == null or not t.destroyed or t.kind != Unit.KIND_MECH or t.counters.get("vaporized", false):
				return RuleResult.deny("Choose a destroyed mech (not vaporized).", "frames: Lancaster, Combat Repair")
			if Sight.unit_distance(state, u, t) > 1:
				return RuleResult.deny("It must be adjacent.", "frames: Lancaster, Combat Repair")
			if u.repairs < int(op.get("repairs", 4)):
				return RuleResult.deny("Needs %d Repairs." % int(op.get("repairs", 4)), "frames: Lancaster, Combat Repair")
	return RuleResult.allow()


## Basic actions shown on the action bar: [type, name, group, params-free check?].
const BASIC := [
	["move", "Move", "move"], ["boost", "Boost", "move"], ["jump", "Jump", "move"], ["stand_up", "Stand Up", "move"],
	["bonus_move", "Extra Move", "move"], ["disengage", "Disengage", "move"],
	["skirmish", "Skirmish", "attack"], ["barrage", "Barrage", "attack"], ["improvised_attack", "Improvised Attack", "attack"],
	["ram", "Ram", "attack"], ["grapple", "Grapple", "attack"], ["fight", "Fight", "attack"],
	["scan", "Scan", "tech"], ["lock_on", "Lock On", "tech"], ["invade", "Invade", "tech"], ["bolster", "Bolster", "tech"],
	["full_tech", "Full Tech", "tech"],
	["hide", "Hide", "other"], ["search", "Search", "other"], ["overcharge", "Overcharge", "other"],
	["stabilize", "Stabilize", "other"], ["core_power", "Core Power", "core"], ["prepare", "Prepare", "other"],
	["shut_down", "Shut Down", "other"], ["boot_up", "Boot Up", "other"], ["eject", "Eject", "other"],
	["dismount", "Dismount", "other"], ["mount", "Mount", "other"], ["self_destruct", "Self-Destruct", "other"],
	["end_grapple", "Let Go", "other"], ["break_free", "Break Free", "other"], ["grapple_contest", "Grapple Contest", "other"],
	["climb_on", "Climb On", "move"], ["board", "Board", "other"], ["disembark", "Climb Out", "other"], ["cut_cable", "Cut Cable", "attack"],
	["pull_stake", "Pull Out Stake", "other"], ["use_object", "Use Object", "other"], ["ai_control", "Hand Over to AI", "other"],
]
## Actions whose own check needs no target, so the bar can show exactly whether they work.
const NO_TARGET := ["stand_up", "bonus_move", "disengage", "hide", "overcharge", "shut_down", "boot_up",
	"core_power", "end_grapple", "break_free", "grapple_contest", "self_destruct", "pull_stake"]


## Everything `u` might do now, for the action bar. See RulesQueries.available_actions.
static func listing(state: GameState, u: Unit) -> Array:
	var out: Array = []
	var own_turn := state.active_unit == u.id and state.pending.is_empty()
	for b: Array in BASIC:
		var h: Variant = RulesEngine.registry.get(b[0])
		if h == null:
			continue
		var entry := {"id": b[0], "type": b[0], "params": {}, "name": b[1], "group": b[2], "available": false, "reason": "", "rule_ref": ""}
		var r: RuleResult
		if not own_turn:
			r = RuleResult.deny("Not your turn.", TurnRules.REF_TURN_ORDER)
		elif h is TurnAction:
			var ta: TurnAction = h
			if not ta.kinds().has(u.kind):
				continue
			entry["cost"] = ta.cost()
			r = TurnRules.can_spend(u, ta.cost(), ta.economy_name()) if ta.cost() != "move" else RuleResult.allow()
			if r.ok and NO_TARGET.has(b[0]):
				r = (h as ActionHandler).validate(state, {"type": b[0], "actor": u.id, "params": {"delay": 1}})
			elif r.ok and b[0] in ["move", "jump"]:
				r = MoveActions._can_move_voluntarily(u)
		else:
			r = (h as ActionHandler).validate(state, {"type": b[0], "actor": u.id, "params": {}})
		entry["available"] = r.ok
		entry["reason"] = r.reason
		entry["rule_ref"] = r.rule_ref
		out.append(entry)
	for w: Dictionary in u.loadout.get("weapons", []):
		var ws := Weapons.state_of(u, w)
		var ready := Attacks.weapon_ready(u, w)
		out.append({"id": "weapon:" + String(w["key"]), "type": "skirmish", "params": {"weapon": w["key"]}, "name": w.get("name", ""),
			"group": "weapon", "available": own_turn and ready.ok, "reason": ready.reason if own_turn else "Not your turn.",
			"rule_ref": ready.rule_ref, "size": w.get("size", ""), "loading": {"has": Weapons.has_tag(w, "tg_loading"), "loaded": ws["loaded"]},
			"uses_left": int(ws["uses"]), "recharge": {"value": int(ws.get("recharge", 0)), "charged": ws.get("charged", true)},
			"destroyed": ws["destroyed"], "superheavy": w.get("size", "") == "Superheavy"})
	for a: Dictionary in Abilities.all(u):
		if a.get("activation", "") == "Reaction" and a.get("automated", false):
			continue  # listed with the other reactions below (TraitReactions)
		var src := Abilities.source_state(u, String(a["source_key"]))
		var r := RuleResult.deny("Not your turn.", TurnRules.REF_TURN_ORDER)
		if a.get("activation", "") == "Reaction":
			r = RuleResult.deny("Reaction: offered when its trigger happens (%s)." % a.get("trigger", ""), "Core p.73 Reactions")
		elif own_turn:
			r = Abilities.can_activate(state, u, a)
			if r.ok and a.get("requires_core_active", false) and not u.counters.get("core_active", false):
				r = RuleResult.deny("Only while %s is active." % a["source_name"], "frames: core_system")
			if r.ok:
				r = TurnRules.can_spend(u, Abilities.cost_of(a), Abilities.economy_name(a))
		var f := Abilities.frequency_of(a)
		out.append({"id": "ability:" + String(a["key"]), "type": "activate", "params": {"ability": a["key"]}, "name": a["name"],
			"group": "core" if a["source_key"] == "core" else ("reaction" if a.get("activation", "") == "Reaction" else "system"),
			"source": a.get("source_name", ""), "activation": a.get("activation", ""), "cost": Abilities.cost_of(a),
			"available": r.ok, "reason": r.reason, "rule_ref": r.rule_ref, "uses_left": int(src["uses"]),
			"uses_max": Abilities.max_uses(u, String(a["source_key"])), "frequency": a.get("frequency", ""),
			"used": Abilities._times_used(u, String(a["key"]), f.get("per", "scene")) if not f.is_empty() else 0,
			"recharge": {"value": int(src.get("recharge", 0)), "charged": src.get("charged", true)},
			"destroyed": src["destroyed"], "automated": a.get("automated", false), "detail": a.get("detail", ""), "kind": a.get("kind", "action"),
			"automation": "automated" if a.get("automated", false) else "manual",
			"table_note": "" if a.get("automated", false) else Automation.MANUAL_GUIDANCE})
	for kind: String in TraitReactions.KINDS:
		if not Effects.has(u, kind):
			continue
		var tr := Reactions.can_react(u, kind, state)
		out.append({"id": "reaction:" + kind, "type": "react", "params": {}, "name": String(Effects.of(u, kind)[0].get("label", kind)),
			"group": "reaction", "available": tr.ok, "reason": tr.reason, "rule_ref": tr.rule_ref, "frequency": "1/round",
			"used": 1 if (u.counters.get("reactions", []) as Array).has(kind) else 0, "policy": Reactions.policy(u, kind),
			"reaction": kind, "automated": true})
	for reaction in ["brace", "overwatch"]:
		if u.kind == Unit.KIND_DEPLOYABLE:
			break
		var rr := Reactions.can_react(u, reaction, state)
		out.append({"id": "reaction:" + reaction, "type": "react", "params": {}, "name": reaction.capitalize(), "group": "reaction",
			"available": rr.ok, "reason": rr.reason, "rule_ref": rr.rule_ref, "frequency": "1/round",
			"used": 1 if (u.counters.get("reactions", []) as Array).has(reaction) else 0,
			"policy": Reactions.policy(u, reaction)})
	var core: Dictionary = u.loadout.get("core", {})
	var cnote := String(core.get("manual_note", ""))
	var cstatus := "manual" if not core.get("automated", false) else ("partial" if cnote != "" else "automated")
	out.append({"id": "core_power_charges", "type": "", "name": "Core Power", "group": "status", "uses_left": int(u.counters.get("core_power", 0)),
		"uses_max": 1 if u.loadout.has("core") else 0, "active": u.counters.get("core_active", false),
		"automation": cstatus, "table_note": Automation.MANUAL_GUIDANCE if cstatus == "manual" else (Automation.PARTIAL_GUIDANCE % cnote if cstatus == "partial" else "")})
	return out
