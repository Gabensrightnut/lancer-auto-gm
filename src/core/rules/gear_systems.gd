class_name GearSystems
extends RefCounted
## Systems from the gear catalogue that need more than a passive effect (data in
## data/game/activation_effects.json and gear_effects.json). Ops and effect kinds:
##   op blast_save {range, blast, save, damage, type, half, grenade?}  everyone in a Blast at
##        params.aim saves or takes the damage (Frag Grenade). Grenades: within Range and line
##        of sight (tags: Grenade); Iskander Assault Launcher: range 15, 1/round.
##   op smoke {range, blast, grenade?}  soft cover in a Blast until the end of your next turn
##   op project_shield  a character in line of sight: attacks between you gain +2 Difficulty
##        until the start of your next turn (Type-3 Projected Shield)
##   paint_job         before structure damage roll 1d6: on 6, back to 1 HP instead; once per
##                     Full Repair (Custom Paint Job)
##   hp_bonus {value}  more max HP (Personalizations)
##   save_vs_prone {value}  Accuracy on saves to avoid Prone or knockback (Stable Structure)
## Turret drones: when an allied character within 10 of a deployed turret hits, the owner may
## react: the turret deals 3 kinetic to that target if it has line of sight (1/round each).

const REF_GRENADE := "tags: Grenade"


static func _aim(params: Dictionary) -> Variant:
	return TurnAction.cell_param(params, "aim")


## Range for throwing a grenade: its own, or Iskander's Assault Launcher (1/round).
static func grenade_reach(state: GameState, u: Unit, op: Dictionary) -> int:
	var reach := int(op.get("range", 5))
	if op.get("grenade", false):
		reach = maxi(reach, FrameSystems.mine_reach(state, u))
	return reach


static func check_aimed(state: GameState, u: Unit, op: Dictionary, params: Dictionary) -> RuleResult:
	var aim: Variant = _aim(params)
	if aim == null or not state.map.has_cell(aim):
		return RuleResult.deny("Choose where to throw it (params.aim).", REF_GRENADE)
	var body := Sight.make_body(state, aim, state.map.ground_height(aim), 0.5)
	var reach := grenade_reach(state, u, op)
	if Sight.distance(state, Sight.body_of(state, u), body) > reach:
		return RuleResult.deny("Throw it within Range %d." % reach, REF_GRENADE)
	if not Sight.line_of_sight(state, Sight.body_of(state, u), body):
		return RuleResult.deny("No line of sight to that space.", REF_GRENADE)
	return RuleResult.allow()


static func _mark_launcher(state: GameState, u: Unit, op: Dictionary, aim: Vector2i) -> void:
	if op.get("grenade", false) and Sight.distance(state, Sight.body_of(state, u), Sight.make_body(state, aim, state.map.ground_height(aim), 0.5)) > int(op.get("range", 5)):
		u.counters["launcher_round"] = state.round_number  # Assault Launcher used this round


static func blast_save(state: GameState, u: Unit, op: Dictionary, params: Dictionary) -> Array[Dictionary]:
	var aim: Vector2i = _aim(params)
	_mark_launcher(state, u, op, aim)
	var cells := Zones.cells_around(state, [aim] as Array[Vector2i], int(op.get("blast", 1)))
	var events: Array[Dictionary] = [{"type": "area_effect", "unit": u.id, "cells": cells, "center": [aim.x, aim.y], "rule_ref": REF_GRENADE}]
	var ids: Array = []
	for o: Unit in state.units.values():
		if not Combat.is_present(o):
			continue
		var inside := false
		for c in state.map.grid.footprint(o.cell, o.size):
			inside = inside or cells.has([c.x, c.y])
		if not inside:
			continue
		if o.kind != Unit.KIND_DEPLOYABLE:
			ids.append(o.id)
		elif op.has("object_damage"):
			# Objects are hit automatically (Thermal Grenade: 10 AP energy).
			events.append_array(Combat.deal_damage(state, o, [{"type": String(op.get("type", "Energy")), "amount": int(op["object_damage"])}], {"ap": true, "source": u.id}))
	ids.sort()
	var save_op := op.duplicate()
	save_op["op"] = "save_damage"
	events.append_array(AbilityActions.apply_target_ops(state, u, [save_op], ids))
	return events


static func smoke(state: GameState, u: Unit, op: Dictionary, params: Dictionary) -> Array[Dictionary]:
	var aim: Vector2i = _aim(params)
	_mark_launcher(state, u, op, aim)
	return Zones.add(state, {"kind": "smoke", "owner": u.id, "label": "Smoke", "center": [aim.x, aim.y],
		"cells": Zones.cells_around(state, [aim] as Array[Vector2i], int(op.get("blast", 2))),
		"expires": {"unit": u.id, "when": "end", "count": 2 if state.active_unit == u.id else 1}, "rule_ref": "systems: Pattern-A Smoke Charges"})


## Smoke Mine: soft cover in its burst until the end of the detonating character's next turn.
static func smoke_mine(state: GameState, m: Unit, trigger: Unit) -> Array[Dictionary]:
	var foot: Array[Vector2i] = []
	foot.assign(state.map.grid.footprint(m.cell, m.size))
	return Zones.add(state, {"kind": "smoke", "owner": String(m.counters.get("owner", "")), "label": "Smoke", "center": [m.cell.x, m.cell.y],
		"cells": Zones.cells_around(state, foot, int(m.counters.get("zone_size", 3))),
		"expires": {"unit": trigger.id, "when": "end", "count": 2 if state.active_unit == trigger.id else 1}, "rule_ref": "systems: Pattern-A Smoke Charges"})


static func project_shield(state: GameState, u: Unit, target: Unit) -> Array[Dictionary]:
	return Effects.activate(state, u, [{"kind": "projected_shield", "target": target.id}], "Type-3 Projected Shield", "start_next_turn")


## +2 Difficulty between a Projected Shield's user and its nominee.
static func shield_difficulty(attacker: Unit, target: Unit) -> int:
	for e: Dictionary in Effects.of(attacker, "projected_shield"):
		if String(e.get("target", "")) == target.id:
			return 2
	for e: Dictionary in Effects.of(target, "projected_shield"):
		if String(e.get("target", "")) == attacker.id:
			return 2
	return 0


## Custom Paint Job: before structure damage, 1d6; on 6 back to 1 HP. Returns events; the
## first has "saved".
static func paint_job(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not Effects.has(u, "paint_job") or u.counters.get("paint_used", false):
		return events
	u.counters["paint_used"] = true  # once before each Full Repair
	var roll := state.dice.die(6)
	events.append({"type": "effect_triggered", "unit": u.id, "effect": "Custom Paint Job", "target": u.id, "roll": roll, "saved": roll == 6, "rule_ref": "systems: Custom Paint Job"})
	if roll == 6:
		u.hp = 1
		events.append({"type": "hp_changed", "unit": u.id, "hp": 1, "overshield": u.overshield, "source": "Custom Paint Job"})
	return events


## Accuracy for saves whose failure means Prone or knockback (Stable Structure).
static func prone_save_sources(u: Unit) -> Array:
	var out: Array = []
	for e: Dictionary in Effects.of(u, "save_vs_prone"):
		out.append({"label": e.get("label", "Stable Structure"), "kind": "accuracy", "type": "accuracy", "value": int(e.get("value", 1)), "rule_ref": e.get("rule_ref", Effects.REF)})
	return out


## After `attacker` hits `target`: turret drones near the attacker may join in.
static func turret_attacks(state: GameState, attacker: Unit, target: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var ids: Array = state.units.keys()
	ids.sort()
	for id: String in ids:
		var t := state.unit(id)
		if t.destroyed or not t.counters.get("turret", false) or not Combat.is_present(target):
			continue
		var owner := state.unit(String(t.counters.get("owner", "")))
		if owner == null or owner.side != attacker.side or int(t.counters.get("turret_round", -1)) == state.round_number:
			continue
		if Sight.unit_distance(state, t, attacker) > 10 or not Sight.unit_line_of_sight(state, t, target):
			continue
		if not Reactions.can_react(owner, "turret_attack", state).ok:
			continue
		var auto := {"take": true}
		var d := Reactions.offer(state, owner, "turret_attack", {"turret": t.id, "attacker": attacker.id, "target": target.id, "suggested": auto}, auto)
		if not d.get("take", false):
			continue
		Reactions._mark_used(owner, "turret_attack", state)
		t.counters["turret_round"] = state.round_number
		events.append({"type": "reaction", "unit": owner.id, "reaction": "turret_attack", "trigger": attacker.id, "target": target.id, "turret": t.id, "rule_ref": "systems: Turret Drones"})
		events.append_array(Combat.deal_damage(state, target, [{"type": "Kinetic", "amount": 3}], {"source": owner.id}))
	return events


## How many turret drones `u` has out (each gives one Turret Attack reaction per round).
static func turret_count(state: GameState, u: Unit) -> int:
	var n := 0
	for o: Unit in state.units.values():
		if o.counters.get("turret", false) and not o.destroyed and o.counters.get("owner", "") == u.id:
			n += 1
	return n


# --- IPS-N systems --------------------------------------------------------------------

## Drag Down (Reinforced Cabling): contested Hull check against a character in range and
## line of sight; the loser is knocked Prone (ties: the initiator, Core p.13).
static func contest_prone(state: GameState, u: Unit, t: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var mine := Combat.skill_check(state, u, "hull", "Drag Down")
	var theirs := Combat.skill_check(state, t, "hull", "Resist Drag Down")
	var won := int(mine["total"]) >= int(theirs["total"])
	events.append({"type": "contested_check", "unit": u.id, "against": t.id, "check": mine, "contest": theirs, "success": won, "rule_ref": "systems: Reinforced Cabling"})
	events.append_array(Combat.add_status(state, t if won else u, "Prone", u.id))
	return events


## Argonaut Shield: an adjacent character gains Resistance to all damage; the user takes half
## of what it would take before Armor and Resistance. Ends when they break adjacency.
static func argonaut(state: GameState, u: Unit, t: Unit) -> Array[Dictionary]:
	u.counters["argonaut"] = t.id
	return [{"type": "effect_triggered", "unit": u.id, "effect": "Argonaut Shield", "target": t.id, "rule_ref": "systems: Argonaut Shield"}] as Array[Dictionary]


## The Argonaut Shield protecting `target`, or null.
static func argonaut_for(state: GameState, target: Unit) -> Unit:
	for o: Unit in state.units.values():
		if String(o.counters.get("argonaut", "")) == target.id and Combat.is_present(o):
			if Sight.unit_distance(state, o, target) <= 1:
				return o
			o.counters.erase("argonaut")  # broke adjacency: the effect ceases
	return null


## Whitewash Sealant Spray at a character or a free space (params.target or params.aim).
static func whitewash(state: GameState, u: Unit, t: Unit, params: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var ref := "systems: Whitewash Sealant Spray"
	if t == null:
		var aim: Vector2i = TurnAction.cell_param(params, "aim")
		return Zones.add(state, {"kind": "sealant", "owner": u.id, "label": "Sealant", "center": [aim.x, aim.y],
			"cells": Zones.cells_around(state, [aim] as Array[Vector2i], 1), "rule_ref": ref})
	if t.side != u.side:
		var save := Combat.skill_check(state, t, "agility", "Save vs Whitewash", u.save_target, 0, 0, [], true)
		events.append({"type": "skill_check", "unit": t.id, "check": save, "rule_ref": ref})
		if save["success"]:
			return events
	events.append_array(Combat.add_status(state, t, "Slowed", u.id, t.id))
	if t.burn > 0:
		t.burn = 0
		events.append({"type": "burn_cleared", "unit": t.id})
	return events


## Overshield on a target (Aceso Stabilizer: Grit + 4, and Immunity to some conditions while
## it lasts).
static func overshield(state: GameState, u: Unit, t: Unit, op: Dictionary) -> Array[Dictionary]:
	var amount := u.grit + int(op.get("plus", 4))
	t.overshield = maxi(t.overshield, amount)  # overshield doesn't stack; the higher value
	var active: Array = t.counters.get("active_effects", [])
	for s: String in op.get("immune_while", []):
		active.append({"kind": "immune", "status": s, "while_overshield": true, "label": "Aceso Stabilizer"})
	t.counters["active_effects"] = active
	for s: String in op.get("immune_while", []):
		if t.has_status(s):
			Combat.remove_status(t, s, "Aceso Stabilizer")
	return [{"type": "hp_changed", "unit": t.id, "hp": t.hp, "overshield": t.overshield, "source": "Aceso Stabilizer"}] as Array[Dictionary]


## Removes effects (and statuses) a system switched on (HyperDense Armor deactivated).
static func remove_effects(state: GameState, u: Unit, label: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	u.counters["active_effects"] = (u.counters.get("active_effects", []) as Array).filter(func(e: Dictionary) -> bool: return e.get("label", "") != label)
	for s: String in u.statuses.keys():
		if String(u.statuses[s].get("source", "")) == label:
			events.append_array(Combat.remove_status(u, s, "deactivated"))
	events.append({"type": "effect_ended", "unit": u.id, "effect": label, "reason": "deactivated"})
	return events


## Charged Stake: an adjacent character saves (Hull) or is impaled: 1d6 AP energy and
## Immobilized; 1d6 AP energy at the end of each of its turns until it saves as a full action.
static func impale(state: GameState, u: Unit, t: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for o: Unit in state.units.values():
		if String(o.counters.get("impaled", {}).get("by", "")) == u.id:
			events.append_array(unimpale(o, "a new stake"))  # one character at a time
	var save := Combat.skill_check(state, t, "hull", "Save vs Charged Stake", u.save_target, 0, 0, [], true)
	events.append({"type": "skill_check", "unit": t.id, "check": save, "rule_ref": "systems: Charged Stake"})
	if save["success"]:
		return events
	t.counters["impaled"] = {"by": u.id, "save_target": u.save_target}
	var roll := state.dice.roll("1d6")
	events.append_array(Combat.deal_damage(state, t, [{"type": "Energy", "amount": int(roll["total"])}], {"ap": true, "source": u.id}))
	events.append_array(Combat.add_status(state, t, "Immobilized", "Charged Stake"))
	return events


static func unimpale(t: Unit, why: String) -> Array[Dictionary]:
	t.counters.erase("impaled")
	if t.has_status("Immobilized") and t.statuses["Immobilized"].get("source", "") == "Charged Stake":
		return Combat.remove_status(t, "Immobilized", why)
	return [] as Array[Dictionary]


static func impaled_turn_end(state: GameState, t: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var imp: Dictionary = t.counters.get("impaled", {})
	if imp.is_empty() or not Combat.is_present(t):
		return events
	var roll := state.dice.roll("1d6")
	events.append({"type": "effect_triggered", "unit": String(imp["by"]), "effect": "Charged Stake", "target": t.id, "rule_ref": "systems: Charged Stake"})
	events.append_array(Combat.deal_damage(state, t, [{"type": "Energy", "amount": int(roll["total"])}], {"ap": true, "source": String(imp["by"])}))
	return events


## Restock Drone (used by an adjacent ally): clear 1d6 heat and one condition, reload one
## Loading weapon; the drone disintegrates.
static func restock(state: GameState, user: Unit, drone: Unit, params: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var roll := state.dice.roll("1d6")
	var cleared := mini(user.heat, int(roll["total"]))
	user.heat -= cleared
	events.append({"type": "heat_changed", "unit": user.id, "amount": -cleared, "total": user.heat, "source": drone.name})
	events.append_array(Combat._danger_zone(user))
	var cond := String(params.get("condition", ""))
	if cond != "" and user.has_status(cond):
		events.append_array(Combat.remove_status(user, cond, drone.name))
	var w := Weapons.find(user, String(params.get("weapon", "")))
	if not w.is_empty():
		Weapons.state_of(user, w)["loaded"] = true
		events.append({"type": "reloaded", "unit": user.id, "weapon": w["key"], "source": drone.name})
	drone.destroyed = true
	state.units.erase(drone.id)
	events.append({"type": "recalled", "unit": String(drone.counters.get("owner", "")), "object": drone.id, "reason": "used up"})
	return events


## Aegis Shield Generator: before an attack's damage, the owner may react to roll one of its
## d6s and reduce the damage to a character in its burst by that much.
static func aegis_reduce(state: GameState, target: Unit, parts: Array) -> Dictionary:
	var out := {"events": [] as Array[Dictionary], "parts": parts}
	for g: Unit in state.units.values():
		if g.destroyed or int(g.counters.get("aegis_dice", 0)) <= 0 or Sight.unit_distance(state, g, target) > 1:
			continue
		var owner := state.unit(String(g.counters.get("owner", "")))
		if owner == null or owner.side != target.side or not Reactions.can_react(owner, "aegis_shield", state).ok:
			continue
		var auto := {"take": true}
		var d := Reactions.offer(state, owner, "aegis_shield", {"generator": g.id, "target": target.id, "suggested": auto}, auto)
		if not d.get("take", false):
			continue
		Reactions._mark_used(owner, "aegis_shield", state)
		g.counters["aegis_dice"] = int(g.counters["aegis_dice"]) - 1
		var roll := state.dice.die(6)
		var left := roll
		var reduced: Array = []
		for p: Dictionary in parts:
			var c := p.duplicate()
			if c.get("type", "") not in ["Heat", "Burn"] and left > 0:
				var cut := mini(left, int(c.get("amount", 0)))
				c["amount"] = int(c["amount"]) - cut
				left -= cut
			reduced.append(c)
		out["parts"] = reduced
		out["events"].append({"type": "reaction", "unit": owner.id, "reaction": "aegis_shield", "target": target.id, "roll": roll, "dice_left": g.counters["aegis_dice"], "rule_ref": "systems: Aegis Shield Generator"})
		return out
	return out


## Roland Chamber: after reloading, the next attack with a Loading weapon gains +1d6
## explosive bonus damage and a Hull save against Prone on a hit.
static func reloaded(u: Unit) -> void:
	if Effects.has(u, "roland_chamber"):
		u.counters["roland"] = true


## Webjaw Snare: a character moving over it saves (Hull) or takes 1d6 AP kinetic and is
## Immobilized until the snare is destroyed.
static func check_snares(state: GameState, mover: Unit, path: Array) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if mover.kind == Unit.KIND_DEPLOYABLE:
		return events
	for sn: Unit in state.units.values():
		if sn.destroyed or not sn.counters.get("snare", false) or not sn.counters.get("armed", false) or sn.counters.get("sprung", false):
			continue
		for i in range(1, path.size()):
			var c := Vector2i(int(path[i][0]), int(path[i][1]))
			if not state.map.grid.footprint(c, mover.size).has(sn.cell):
				continue
			sn.counters["sprung"] = true
			sn.statuses.erase("Hidden")
			var owner := state.unit(String(sn.counters.get("owner", "")))
			events.append({"type": "mine_triggered", "mine": sn.id, "unit": mover.id, "text": sn.counters.get("text", ""), "rule_ref": "systems: Webjaw Snare"})
			var save := Combat.skill_check(state, mover, "hull", "Save vs Webjaw Snare", owner.save_target if owner else 10, 0, 0, [], true)
			events.append({"type": "skill_check", "unit": mover.id, "check": save})
			if not save["success"]:
				var roll := state.dice.roll("1d6")
				events.append_array(Combat.deal_damage(state, mover, [{"type": "Kinetic", "amount": int(roll["total"])}], {"ap": true, "source": sn.id}))
				events.append_array(Combat.add_status(state, mover, "Immobilized", sn.id))
			break
	return events


## A snare destroyed: whoever it holds is free.
static func snare_gone(state: GameState, sn: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for o: Unit in state.units.values():
		if o.has_status("Immobilized") and String(o.statuses["Immobilized"].get("source", "")) == sn.id:
			events.append_array(Combat.remove_status(o, "Immobilized", "snare destroyed"))
	return events


## Synthetic Muscle Netting: the Size `u` counts as when it Grapples or Rams `other`.
static func grapple_size(u: Unit, other: Unit) -> float:
	if not Effects.has(u, "muscle_netting"):
		return u.size
	return other.size if other.size > u.size else u.size + 1.0


# --- SSC systems ----------------------------------------------------------------------

## Ferrous Lash: an ally is pulled 5 spaces (no save); a hostile saves (Agility) or is pulled 5
## toward params.toward. Ignores engagement, no reactions; a hostile that collides is Prone.
static func ferrous_lash(state: GameState, u: Unit, t: Unit, params: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var toward: Variant = TurnAction.cell_param(params, "toward")
	if toward == null:
		return events
	if t.side != u.side:
		var save := Combat.skill_check(state, t, "agility", "Save vs Ferrous Lash", u.save_target, 0, 0, [], true)
		events.append({"type": "skill_check", "unit": t.id, "check": save, "rule_ref": "systems: Ferrous Lash"})
		if save["success"]:
			return events
	var origin: Vector2i = t.cell - ((toward as Vector2i) - t.cell)
	var path := Movement.push_path(state, t, origin, 5)
	if Effects.has(t, "immovable"):
		return events
	if path.size() >= 2:
		var last: Array = path.back()
		t.cell = Vector2i(last[0], last[1])
		t.level = int(last[2])
		events.append({"type": "moved", "unit": t.id, "path": path, "mode": "involuntary", "cost": 0, "rule_ref": "systems: Ferrous Lash"})
		events.append_array(Abilities.check_mines(state, t, path))
		events.append_array(Zones.check_path(state, t, path))
	if t.side != u.side and path.size() < 6:
		events.append_array(Combat.add_status(state, t, "Prone", u.id))  # it hit something
	events.append_array(Combat.after_movement(state))
	return events


## Black ICE Module: tech attacks against it or adjacent allies get +1 Difficulty, +1 more
## for each later one, up to +3, then back to +1.
static func black_ice(state: GameState, target: Unit) -> Dictionary:
	for o: Unit in state.units.values():
		if Effects.has(o, "black_ice") and o.side == target.side and Combat.is_present(o) and Sight.unit_distance(state, o, target) <= (0 if o == target else 1):
			return {"unit": o, "value": int(o.counters.get("black_ice", 0)) + 1}
	return {}


static func black_ice_used(o: Unit) -> void:
	var n := int(o.counters.get("black_ice", 0)) + 1
	o.counters["black_ice"] = 0 if n >= 3 else n


## Attack roll modifiers from the attacker's own systems (Core Siphon, Kinetic Compensator)
## and from marks on the target (Markerlight, Shrike Code). Returns sources.
static func attack_sources(attacker: Unit, kind: String) -> Array:
	var out: Array = []
	if attacker.turn.get("siphon", false):
		if int(attacker.turn.get("attack_rolls", 0)) == 0:
			out.append({"label": "Core Siphon", "kind": "accuracy", "type": "accuracy", "value": 1, "rule_ref": "systems: Core Siphon"})
		else:
			out.append({"label": "Core Siphon", "kind": "difficulty", "type": "difficulty", "value": 1, "rule_ref": "systems: Core Siphon"})
	if kind == Attacks.KIND_RANGED and attacker.counters.get("compensator", false):
		out.append({"label": "Kinetic Compensator", "kind": "accuracy", "type": "accuracy", "value": 1, "rule_ref": "systems: Kinetic Compensator"})
	return out


## After an attack roll: bookkeeping for those modifiers.
static func attack_rolled(attacker: Unit, kind: String, hit: bool) -> void:
	attacker.turn["attack_rolls"] = int(attacker.turn.get("attack_rolls", 0)) + 1
	if kind == Attacks.KIND_RANGED:
		attacker.counters.erase("compensator")
		if not hit and Effects.has(attacker, "kinetic_compensator"):
			attacker.counters["compensator"] = true  # the next ranged attack gains +1 Accuracy


## Is `target` Invisible to `attacker` because of a tech effect (Mirage, Stalk Prey), or does
## a tracker see through it (Tracking Bug, Lotus Projector)?
static func seen_as_invisible(state: GameState, attacker: Unit, target: Unit) -> bool:
	for m: Dictionary in attacker.counters.get("mirage", []):
		if String(m.get("who", "")) == target.id:
			return true
	return false


static func sees_through(state: GameState, attacker: Unit, target: Unit) -> bool:
	if (target.counters.get("tracked_by", []) as Array).has(attacker.id):
		return true
	for o: Unit in state.units.values():
		if o.counters.get("aura", "") == "lotus" and not o.destroyed and o.side != target.side and Sight.unit_distance(state, o, target) <= 2:
			return true
	return false


## Iceout drone: characters in its burst 1 are immune to tech actions and can't take them.
static func iceout(state: GameState, u: Unit) -> bool:
	for o: Unit in state.units.values():
		if o.counters.get("aura", "") == "iceout" and not o.destroyed and Sight.unit_distance(state, o, u) <= 1:
			return true
	return false


## Invade options and other tech hits from SSC systems.
static func tech_effect(state: GameState, u: Unit, t: Unit, op: Dictionary, params: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	match String(op.get("op", "")):
		"shrike_code":
			t.counters["shrike_code"] = {"by": u.id}
			events.append_array(Combat.add_status(state, t, "Shrike Code", u.id, t.id))
		"mirage":
			var who := state.unit(String(params.get("ally", u.id)))
			var list: Array = t.counters.get("mirage", [])
			list.append({"who": who.id if who != null else u.id, "by": u.id})
			t.counters["mirage"] = list
			events.append_array(Combat.add_status(state, t, "Mirage", u.id, t.id))
		"stalk_prey":
			for o: Unit in state.units.values():
				o.counters["mirage"] = (o.counters.get("mirage", []) as Array).filter(func(m: Dictionary) -> bool: return not (m.get("by", "") == u.id and m.get("stalk", false)))
			var list: Array = t.counters.get("mirage", [])
			list.append({"who": u.id, "by": u.id, "stalk": true})
			t.counters["mirage"] = list
		"terrify":
			events.append_array(Combat.add_status(state, t, "Impaired", u.id, t.id))
			t.counters["terrified_of"] = u.id
		"tracking_bug":
			var by: Array = t.counters.get("tracked_by", [])
			if not by.has(u.id):
				by.append(u.id)
			t.counters["tracked_by"] = by
			ViewFilter.reveal_in_state(state, u.side, t.id)
		"markerlight":
			events.append_array(Combat.apply_heat(state, t, 2, u.id))
			events.append_array(Combat.add_status(state, t, "Lock On", u.id))
			t.counters["marked_by"] = u.id
			u.counters["markerlight_ready"] = t.id
	return events


## Mirage/Shrike end with their status (until the end of the target's next turn).
static func status_ended(u: Unit, status: String) -> void:
	match status:
		"Mirage":
			u.counters["mirage"] = (u.counters.get("mirage", []) as Array).filter(func(m: Dictionary) -> bool: return m.get("stalk", false))
		"Shrike Code":
			u.counters.erase("shrike_code")
		"Lock On":
			u.counters.erase("marked_by")


## Stalk Prey ends when the hunter takes damage from that target; Active Camouflage and the
## cloaking field end when their user takes damage.
static func took_damage(state: GameState, u: Unit, source: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var src := state.unit(source)
	if src != null:
		src.counters["mirage"] = (src.counters.get("mirage", []) as Array).filter(func(m: Dictionary) -> bool: return not (m.get("stalk", false) and m.get("who", "") == u.id))
	if u.has_status("Invisible") and String(u.statuses["Invisible"].get("source", "")) in ["Active Camouflage", "LB/OC Cloaking Field"]:
		events.append_array(Combat.remove_status(u, "Invisible", "took damage"))
	for z: Dictionary in Zones.of_kind(state, "cloak"):
		if z.get("owner", "") == u.id:
			events.append_array(Zones.remove(state, String(z["id"]), "took damage"))
	return events


## Markerlight: when an ally hits the marked target, the marker may react to make it a crit.
static func markerlight_crit(state: GameState, attacker: Unit, target: Unit) -> bool:
	var marker := state.unit(String(target.counters.get("marked_by", "")))
	if marker == null or marker == attacker or marker.side != attacker.side or String(marker.counters.get("markerlight_ready", "")) != target.id:
		return false
	if not Reactions.can_react(marker, "markerlight", state).ok:
		return false
	var auto := {"take": true}
	var d := Reactions.offer(state, marker, "markerlight", {"attacker": attacker.id, "target": target.id, "suggested": auto}, auto)
	if not d.get("take", false):
		return false
	Reactions._mark_used(marker, "markerlight", state)
	marker.counters.erase("markerlight_ready")
	return true


## Stuncrown: hostiles in burst 3 with line of sight to you and not in cover from you save
## (Agility) or are Jammed, and save (Systems) or are Impaired, until the end of their next turn.
static func stuncrown(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var ids: Array = state.units.keys()
	ids.sort()
	for id: String in ids:
		var t := state.unit(id)
		if t.side == u.side or not Combat.is_present(t) or t.kind == Unit.KIND_DEPLOYABLE or Sight.unit_distance(state, u, t) > 3:
			continue
		var cov := Sight.cover(state, Sight.body_of(state, u), Sight.body_of(state, t))
		if not cov["los"] or cov["cover"] != "none":
			continue
		for pair: Array in [["agility", "Jammed"], ["systems", "Impaired"]]:
			var save := Combat.skill_check(state, t, String(pair[0]), "Save vs Stuncrown", u.save_target, 0, 0, [], true)
			events.append({"type": "skill_check", "unit": t.id, "check": save, "rule_ref": "systems: Stuncrown"})
			if not save["success"]:
				events.append_array(Combat.add_status(state, t, String(pair[1]), u.id, t.id))
	return events


## Javelin Rockets: three spaces; the first character to move into or over each (up to 10
## spaces up) before the start of your next turn takes 3 kinetic.
static func check_javelin(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
	var cells: Variant = params.get("spaces", [])
	if not cells is Array or (cells as Array).size() != 3:
		return RuleResult.deny("Choose 3 spaces (params.spaces).", "systems: Javelin Rockets")
	var pts: Array[Vector2i] = []
	for c: Variant in cells:
		var v := Vector2i(int(c[0]), int(c[1]))
		var r := check_aimed(state, u, {"range": 15}, {"aim": [v.x, v.y]})
		if not r.ok:
			return r
		for p in pts:
			if state.map.grid.distance(p, v) <= 1:
				return RuleResult.deny("The spaces can't be adjacent to each other.", "systems: Javelin Rockets")
		pts.append(v)
	return RuleResult.allow()


static func javelin(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for c: Array in params["spaces"]:
		events.append_array(Zones.add(state, {"kind": "javelin", "owner": u.id, "label": "Javelin Rocket", "center": [int(c[0]), int(c[1])],
			"cells": [[int(c[0]), int(c[1])]], "expires": {"unit": u.id, "when": "start", "count": 1}, "rule_ref": "systems: Javelin Rockets"}))
	return events


## LB/OC Cloaking Field: you and allies completely inside a burst 2 around you are Invisible;
## you're Slowed. Ends at the end of your next turn, or if you're Stunned or take damage.
static func cloaking_field(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = Zones.add(state, {"kind": "cloak", "owner": u.id, "label": "Cloaking Field", "center": [u.cell.x, u.cell.y],
		"cells": [], "radius": 2, "expires": {"unit": u.id, "when": "end", "count": 2 if state.active_unit == u.id else 1}, "rule_ref": "systems: LB/OC Cloaking Field"})
	events.append_array(Combat.add_status(state, u, "Slowed", "LB/OC Cloaking Field"))
	return events


static func cloaked(state: GameState, target: Unit) -> bool:
	for z: Dictionary in Zones.of_kind(state, "cloak"):
		var owner := state.unit(String(z.get("owner", "")))
		if owner == null or owner.side != target.side:
			continue
		if target == owner:
			return true
		var inside := true
		for c in state.map.grid.footprint(target.cell, target.size):
			var near := false
			for oc in state.map.grid.footprint(owner.cell, owner.size):
				near = near or state.map.grid.distance(c, oc) <= int(z.get("radius", 2))
			inside = inside and near
		if inside:
			return true
	return false


## Singularity Motivator: when it takes damage, it may teleport to a free space within 1d6.
static func singularity(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not Effects.has(u, "singularity_motivator") or not Combat.is_present(u) or not Reactions.can_react(u, "exposed_singularity", state).ok:
		return events
	var auto := {"take": false}
	var d := Reactions.offer(state, u, "exposed_singularity", {"suggested": auto, "note": "Answer with to: [x, y]; the range is rolled (1d6)."}, auto)
	var to: Variant = TurnAction.cell_param(d, "to")
	if not d.get("take", false) or to == null:
		return events
	Reactions._mark_used(u, "exposed_singularity", state)
	var reach := state.dice.die(6)
	var plan := Movement.plan_teleport(state, u, to, -1, Movement.MODE_MOVE, reach)
	events.append({"type": "reaction", "unit": u.id, "reaction": "exposed_singularity", "roll": reach, "ok": plan["ok"], "rule_ref": "systems: Singularity Motivator"})
	if plan["ok"]:
		var last: Array = (plan["path"] as Array).back()
		u.cell = Vector2i(last[0], last[1])
		u.level = int(last[2])
		events.append({"type": "moved", "unit": u.id, "path": plan["path"], "mode": "teleport", "cost": 0})
		events.append_array(Combat.after_movement(state))
	return events
