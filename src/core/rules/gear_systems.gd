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
	if op.has("object_damage"):
		# Terrain is an object too (Core p.58): destructible terrain in the area is hit.
		events.append_array(TerrainDamage.damage_area(state, cells, int(op["object_damage"]), String(op.get("type", "Energy")), true, u.id))
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
	if AISystems.exposed_to(state, attacker, target):
		return true  # ATHENA: no Hidden or Invisible inside the model
	if (target.counters.get("tracked_by", []) as Array).has(attacker.id):
		return true
	if Effects.has(attacker, "eye_of_horus") and Sight.unit_distance(state, attacker, target) <= attacker.sensors:
		return true  # Eye of Horus: no Hidden or Invisible against you within Sensors
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
		"Banished":
			u.counters.erase("banish")


## Stalk Prey ends when the hunter takes damage from that target; Active Camouflage and the
## cloaking field end when their user takes damage.
static func took_damage(state: GameState, u: Unit, source: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	spoil_cooler(u)
	events.append_array(AISystems.harmed_by(state, u, state.unit(source)))
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


# --- HORUS systems --------------------------------------------------------------------

static func _pay_energy(state: GameState, u: Unit, expr: String, label: String) -> Array[Dictionary]:
	var roll := state.dice.roll(expr)
	var events: Array[Dictionary] = [{"type": "effect_triggered", "unit": u.id, "effect": label, "target": u.id, "rule_ref": "systems: " + label}]
	events.append_array(Combat.deal_damage(state, u, [{"type": "Energy", "amount": int(roll["total"])}], {"ap": true, "source": u.id}))
	return events


## HORUS invades and tech hits. Most effects need the target; some cost the user AP energy.
static func horus_effect(state: GameState, u: Unit, t: Unit, op: Dictionary, params: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	match String(op.get("op", "")):
		"eject_power_cores":
			var used: Array = t.counters.get("power_cores_ejected", [])
			if used.has(u.id):
				return events  # 1/scene on each character
			used.append(u.id)
			t.counters["power_cores_ejected"] = used
			events.append_array(Combat.add_status(state, t, "Jammed", u.id, t.id))
			for o: Unit in state.units.values():
				if o != t and Combat.is_present(o) and o.kind != Unit.KIND_DEPLOYABLE and Sight.unit_distance(state, o, t) <= 1:
					events.append_array(Combat.deal_damage(state, o, [{"type": "Energy", "amount": 2}], {"source": u.id}))
		"beckon":
			events.append_array(_pay_energy(state, u, "1d6+2", "Beckoner"))
			if t.kind != Unit.KIND_MECH or t.size < u.size or not Combat.is_present(u):
				events.append({"type": "no_effect", "target": t.id, "reason": "Beckon needs a mech the same Size or larger."})
				return events
			var uc := u.cell
			var ul := u.level
			u.cell = t.cell
			u.level = t.level
			t.cell = uc
			t.level = ul
			events.append({"type": "moved", "unit": u.id, "path": [[uc.x, uc.y, ul], [u.cell.x, u.cell.y, u.level]], "mode": "teleport", "cost": 0})
			events.append({"type": "moved", "unit": t.id, "path": [[u.cell.x, u.cell.y, u.level], [uc.x, uc.y, ul]], "mode": "teleport", "cost": 0})
			events.append_array(Combat.after_movement(state))
		"summon":
			var ids: Array = state.units.keys()
			ids.sort()
			for id: String in ids:
				var o := state.unit(id)
				if o != t and Combat.is_present(o) and o.kind != Unit.KIND_DEPLOYABLE and Sight.unit_distance(state, o, t) <= 3:
					events.append_array(Attacks.pull(state, o, t))
		"smite":
			events.append_array(_pay_energy(state, u, "1d6", "Smite"))
			var once: Array = t.counters.get("smitten", [])
			if once.has(u.id):
				return events  # each character can only be Stunned by this once per scene
			var save := Combat.skill_check(state, t, "systems", "Save vs Smite", u.save_target, 0, 0, [], true)
			events.append({"type": "skill_check", "unit": t.id, "check": save, "rule_ref": "systems: Smite"})
			if not save["success"]:
				once.append(u.id)
				t.counters["smitten"] = once
				events.append_array(Combat.add_status(state, t, "Stunned", u.id, t.id))
		"sear":
			events.append_array(_pay_energy(state, u, "1d6", "Sear"))
			var n := 0
			for o: Unit in state.units.values():
				if o != t and Combat.is_present(o) and o.kind != Unit.KIND_DEPLOYABLE and o.size >= 1.0 and Sight.unit_distance(state, o, t) <= 1:
					n += 1
			if n > 0:
				events.append_array(Combat.apply_heat(state, t, mini(6, 2 * n), u.id))
		"logic_bomb":
			var ids: Array = state.units.keys()
			ids.sort()
			for id: String in ids:
				var o := state.unit(id)
				if o.side == u.side or not Combat.is_present(o) or o.kind == Unit.KIND_DEPLOYABLE or Sight.unit_distance(state, o, t) > 2:
					continue
				var save := Combat.skill_check(state, o, "systems", "Save vs Logic Bomb", u.save_target, 0, 0, [], true)
				events.append({"type": "skill_check", "unit": o.id, "check": save, "rule_ref": "systems: Viral Logic Suite"})
				if not save["success"]:
					events.append_array(Combat.add_status(state, o, "Slowed", "Logic Bomb"))
					o.counters["logic_bomb"] = true  # until it ends a turn next to nobody
		"banish":
			t.counters["banish"] = {"by": u.id, "heat": 0}
			events.append_array(Combat.add_status(state, t, "Banished", u.id, t.id))
		"chains":
			_one_at_a_time(state, u, "chains")
			events.append_array(Combat.apply_heat(state, t, 4, u.id))
			t.counters["chains"] = {"by": u.id, "save_target": u.save_target}
		"excommunicate":
			_one_at_a_time(state, u, "excommunicate")
			t.counters["excommunicate"] = {"by": u.id, "save_target": u.save_target}
		"ophidian_trek":
			var n := int(state.dice.roll("1d6+1")["total"])
			var path := Movement.pull_path_to(state, t, Sight.body_of(state, u), 1, n)
			var last: Array = path.back()
			events.append({"type": "moved", "unit": t.id, "path": [path[0], last], "mode": "teleport", "cost": 0, "rule_ref": "systems: Metafold Carver"})
			t.cell = Vector2i(last[0], last[1])
			t.level = int(last[2])
			events.append_array(Combat.after_movement(state))
		"fold_space":
			t.counters["folded"] = [t.cell.x, t.cell.y, t.level]
			events.append({"type": "unit_folded", "unit": t.id, "rule_ref": "systems: Metafold Carver"})
		"hunter_lock":
			if u.counters.has("hunter_lock") and state.unit(String(u.counters["hunter_lock"])) != null and Combat.is_present(state.unit(String(u.counters["hunter_lock"]))):
				return events
			u.counters["hunter_lock"] = t.id
			events.append({"type": "effect_triggered", "unit": u.id, "effect": "Hunter Lock", "target": t.id, "rule_ref": "systems: Hunter Lock"})
	return events


static func _one_at_a_time(state: GameState, u: Unit, key: String) -> void:
	for o: Unit in state.units.values():
		if String(o.counters.get(key, {}).get("by", "")) == u.id:
			o.counters.erase(key)


## Electropulse: hostiles in Sensors next to any drone or deployable take 2 energy.
static func electropulse(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var ids: Array = state.units.keys()
	ids.sort()
	for id: String in ids:
		var o := state.unit(id)
		if o.side == u.side or not Combat.is_present(o) or o.kind == Unit.KIND_DEPLOYABLE or Sight.unit_distance(state, u, o) > u.sensors:
			continue
		for d: Unit in state.units.values():
			if d.kind == Unit.KIND_DEPLOYABLE and not d.destroyed and Sight.unit_distance(state, d, o) <= 1:
				events.append_array(Combat.deal_damage(state, o, [{"type": "Energy", "amount": 2}], {"source": u.id}))
				break
	return events


## EMP Pulse: you're Stunned until the end of your next turn; characters in burst 1 that
## aren't Biological save (Systems) or are Stunned too (1/scene each).
static func emp_pulse(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var ids: Array = state.units.keys()
	ids.sort()
	for id: String in ids:
		var o := state.unit(id)
		if o == u or not Combat.is_present(o) or o.kind == Unit.KIND_PILOT or o.kind == Unit.KIND_DEPLOYABLE or Sight.unit_distance(state, u, o) > 1:
			continue
		if (o.counters.get("emp_stunned", []) as Array).has(u.id):
			continue
		var save := Combat.skill_check(state, o, "systems", "Save vs EMP Pulse", u.save_target, 0, 0, [], true)
		events.append({"type": "skill_check", "unit": o.id, "check": save, "rule_ref": "systems: EMP Pulse"})
		if not save["success"]:
			var once: Array = o.counters.get("emp_stunned", [])
			once.append(u.id)
			o.counters["emp_stunned"] = once
			events.append_array(Combat.add_status(state, o, "Stunned", u.id, o.id))
	events.append_array(Combat.add_status(state, u, "Stunned", "EMP Pulse", u.id))
	return events


## Lightning Generator: energy to every character and object next to you (2; 4 AP when it
## goes off by itself in the Danger Zone).
static func lightning(state: GameState, u: Unit, amount: int, ap: bool) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var ids: Array = state.units.keys()
	ids.sort()
	for id: String in ids:
		var o := state.unit(id)
		if o != u and Combat.is_present(o) and Sight.unit_distance(state, u, o) <= 1:
			events.append_array(Combat.deal_damage(state, o, [{"type": "Energy", "amount": amount}], {"ap": ap, "source": u.id}))
	return events


## Start of a turn: HORUS effects that run by themselves.
static func horus_turn_started(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if Effects.has(u, "lightning_generator") and u.has_status("Danger Zone"):
		events.append({"type": "effect_triggered", "unit": u.id, "effect": "Lightning Generator", "target": u.id, "rule_ref": "systems: Lightning Generator"})
		events.append_array(Combat.apply_heat(state, u, 1, "Lightning Generator"))
		events.append_array(lightning(state, u, 4, true))
	if u.counters.has("folded"):
		var at: Array = u.counters["folded"]
		u.counters.erase("folded")
		events.append({"type": "unit_unfolded", "unit": u.id, "cell": at, "rule_ref": "systems: Metafold Carver"})
	var ex: Dictionary = u.counters.get("excommunicate", {})
	if not ex.is_empty():
		events.append_array(_excommunicate(state, u, ex))
	return events


## End of a turn: Chains of Prometheus, Logic Bomb clearing, Banish's heat bookkeeping.
static func horus_turn_ending(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var ch: Dictionary = u.counters.get("chains", {})
	var by := state.unit(String(ch.get("by", "")))
	if by != null and Combat.is_present(by) and Sight.unit_distance(state, u, by) > 3:
		events.append({"type": "effect_triggered", "unit": by.id, "effect": "Chains of Prometheus", "target": u.id, "rule_ref": "systems: Aggressive System Sync"})
		events.append_array(Combat.apply_heat(state, u, 2, by.id))
	if u.counters.get("logic_bomb", false):
		var alone := true
		for o: Unit in state.units.values():
			alone = alone and (o == u or not Combat.is_present(o) or o.kind == Unit.KIND_DEPLOYABLE or Sight.unit_distance(state, o, u) > 1)
		if alone:
			u.counters.erase("logic_bomb")
			if u.has_status("Slowed") and u.statuses["Slowed"].get("source", "") == "Logic Bomb":
				events.append_array(Combat.remove_status(u, "Slowed", "ended a turn next to nobody"))
	return events


## Excommunicate: the first time in a round it starts its turn next to an ally (or moves next
## to one), both take 3 heat.
static func _excommunicate(state: GameState, u: Unit, ex: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if int(ex.get("round", -1)) == state.round_number:
		return events
	for o: Unit in state.units.values():
		if o != u and o.side == u.side and Combat.is_present(o) and o.kind != Unit.KIND_DEPLOYABLE and Sight.unit_distance(state, o, u) <= 1:
			ex["round"] = state.round_number
			events.append({"type": "effect_triggered", "unit": String(ex.get("by", "")), "effect": "Excommunicate", "target": u.id, "rule_ref": "systems: Aggressive System Sync"})
			events.append_array(Combat.apply_heat(state, u, 3, String(ex.get("by", ""))))
			events.append_array(Combat.apply_heat(state, o, 3, String(ex.get("by", ""))))
			break
	return events


## After a voluntary move on its own turn: Banish heat, Excommunicate, Clamp Bombs, Auto-Cooler.
static func horus_moved(state: GameState, u: Unit, spaces: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	spoil_cooler(u)
	if u.counters.has("clamp_bombs") and state.active_unit == u.id:
		u.counters["clamp_bombs"]["moved"] = int(u.counters["clamp_bombs"].get("moved", 0)) + spaces
	var b: Dictionary = u.counters.get("banish", {})
	if not b.is_empty() and u.has_status("Banished"):
		var add := mini(2 * spaces, 6 - int(b.get("heat", 0)))
		if add > 0:
			b["heat"] = int(b.get("heat", 0)) + add
			events.append_array(Combat.apply_heat(state, u, add, String(b.get("by", ""))))
	var ex: Dictionary = u.counters.get("excommunicate", {})
	if not ex.is_empty() and state.active_unit == u.id:
		events.append_array(_excommunicate(state, u, ex))
	return events


## Sentinel drones: hostiles in their burst 2 take 3 kinetic before making any attack.
static func sentinel_fire(state: GameState, attacker: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for d: Unit in state.units.values():
		if d.counters.get("aura", "") != "sentinel" or d.destroyed or d.side == attacker.side or Sight.unit_distance(state, d, attacker) > 2:
			continue
		events.append({"type": "effect_triggered", "unit": d.id, "effect": "Sentinel Drone", "target": attacker.id, "rule_ref": "systems: Sentinel Drone"})
		events.append_array(Combat.deal_damage(state, attacker, [{"type": "Kinetic", "amount": 3}], {"source": String(d.counters.get("owner", ""))}))
	return events


## //SCORPION: when you or an adjacent ally is missed by a tech attack, the attacker becomes
## Impaired and takes 2 heat, or becomes Jammed (the owner chooses; default Impaired + heat).
static func scorpion(state: GameState, attacker: Unit, target: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for o: Unit in state.units.values():
		if not Effects.has(o, "scorpion") or o.side != target.side or not Combat.is_present(o) or Sight.unit_distance(state, o, target) > (0 if o == target else 1):
			continue
		var auto := {"take": true, "choice": "impaired"}
		var d := Reactions.offer(state, o, "scorpion", {"attacker": attacker.id, "options": ["impaired", "jammed"], "suggested": auto}, auto)
		if not d.get("take", false):
			continue
		events.append({"type": "effect_triggered", "unit": o.id, "effect": "//SCORPION", "target": attacker.id, "rule_ref": "systems: //SCORPION V70.1"})
		if String(d.get("choice", "impaired")) == "jammed":
			events.append_array(Combat.add_status(state, attacker, "Jammed", o.id, attacker.id))
		else:
			events.append_array(Combat.add_status(state, attacker, "Impaired", o.id, attacker.id))
			events.append_array(Combat.apply_heat(state, attacker, 2, o.id))
		break
	return events


# --- Harrison Armory systems ----------------------------------------------------------

## Effects a system switches on and off with the same action (Siege Stabilizers).
static func toggle(state: GameState, u: Unit, label: String, effects: Array) -> Array[Dictionary]:
	for e: Dictionary in u.counters.get("active_effects", []):
		if e.get("label", "") == label:
			return remove_effects(state, u, label)
	return Effects.activate(state, u, effects, label, "scene")


## Reload one Loading weapon (External Ammo Feed, Autoloader Drone).
static func reload_one(state: GameState, u: Unit, key: String, source: String) -> Array[Dictionary]:
	var w := Weapons.find(u, key)
	if w.is_empty():
		for x: Dictionary in u.loadout.get("weapons", []):
			if Weapons.has_tag(x, "tg_loading") and not Weapons.state_of(u, x)["loaded"]:
				w = x
				break
	if w.is_empty():
		return [] as Array[Dictionary]
	Weapons.state_of(u, w)["loaded"] = true
	reloaded(u)
	return [{"type": "reloaded", "unit": u.id, "weapon": w["key"], "source": source}] as Array[Dictionary]


## FADE Cloak: out of phase with realspace (active, and not back for this turn).
static func intangible(u: Unit) -> bool:
	return u != null and u.counters.get("fade", false) and not u.counters.get("fade_back", false)


## FADE Cloak on: intangible for the scene, or until switched off.
static func fade(state: GameState, u: Unit, on: bool) -> Array[Dictionary]:
	u.counters["fade"] = on
	u.counters.erase("fade_back")
	if not on:
		u.counters.erase("fade")
	var events: Array[Dictionary] = [{"type": "effect_triggered", "unit": u.id, "effect": "FADE Cloak: " + ("intangible" if on else "back in realspace"), "target": u.id, "rule_ref": "systems: FADE Cloak"}]
	events.append_array(Combat.refresh_engagement(state))
	return events


## Start of its turn: 1d6; on 3 or less it's back in realspace until the start of its next turn.
static func fade_roll(state: GameState, u: Unit) -> Array[Dictionary]:
	if not u.counters.get("fade", false):
		return [] as Array[Dictionary]
	var roll := state.dice.die(6)
	u.counters["fade_back"] = roll <= 3
	var events: Array[Dictionary] = [{"type": "effect_triggered", "unit": u.id, "effect": "FADE Cloak", "target": u.id, "roll": roll,
		"text": "Back in realspace until your next turn." if roll <= 3 else "Still out of phase.", "rule_ref": "systems: FADE Cloak"}]
	events.append_array(Combat.refresh_engagement(state))
	return events


## H0R_OS II False Idol: a decoy (Evasion 10, E-Defense 10, 1 HP, the target's Size) of you or
## an ally within Sensors (params.target, default you). Before a hostile action against that
## character, a character that can see the idol makes a Systems save; on a failure it keeps
## its action but can't target the character until the end of its next turn.
static func idol_made(state: GameState, u: Unit, idol: Unit, params: Dictionary) -> Array[Dictionary]:
	var t := state.unit(String(params.get("target", u.id)))
	if t == null:
		t = u
	for o: Unit in state.units.values():
		if o != idol and String(o.counters.get("idol_of", "")) != "" and String(o.counters.get("owner", "")) == u.id and not o.destroyed:
			o.destroyed = true  # a second idol: the previous one disappears
	idol.counters["idol_of"] = t.id
	idol.size = t.size
	idol.max_hp = 1
	idol.hp = 1
	idol.evasion = 10
	idol.edef = 10
	return [{"type": "effect_triggered", "unit": u.id, "effect": "False Idol", "target": t.id, "rule_ref": "systems: H0R_OS System Upgrade II"}] as Array[Dictionary]


## Before a hostile attack or tech action against `target`: the False Idol's save. Returns
## {"events", "fooled": bool}.
static func false_idol(state: GameState, actor: Unit, target: Unit) -> Dictionary:
	var out := {"events": [] as Array[Dictionary], "fooled": false}
	if actor == null or target == null or actor.side == target.side:
		return out
	for o: Unit in state.units.values():
		if o.destroyed or String(o.counters.get("idol_of", "")) != target.id or not Sight.unit_line_of_sight(state, actor, o):
			continue
		var owner := state.unit(String(o.counters.get("owner", "")))
		var save := Combat.skill_check(state, actor, "systems", "Save vs False Idol", owner.save_target if owner != null else 10, 0, 0, [], true)
		out["events"].append({"type": "skill_check", "unit": actor.id, "check": save, "rule_ref": "systems: H0R_OS System Upgrade II"})
		if not save["success"]:
			out["fooled"] = true
			out["events"].append_array(Effects.activate(state, actor, [{"kind": "fooled", "target": target.id, "label": "False Idol"}], "False Idol", "end_next_turn"))
			out["events"].append({"type": "effect_triggered", "unit": o.id, "effect": "False Idol: fooled", "target": actor.id,
				"text": "Fooled: it can't target the real one until the end of its next turn, but keeps its action.", "rule_ref": "systems: H0R_OS System Upgrade II"})
		return out
	return out


## Fooled by a False Idol: can't target that character.
static func fooled_by(u: Unit, target: Unit) -> bool:
	for e: Dictionary in Effects.of(u, "fooled"):
		if String(e.get("target", "")) == target.id:
			return true
	return false


## Mimic Gun: 3d20 at the start of combat (X, Y, Z); its base Range cycles through them at the
## start of each of your turns after the first; kinetic damage 1 + half its Range (rounded up,
## Core p.12). "Provoke" (full action) rolls a new set.
static func mimic_roll(state: GameState, u: Unit) -> void:
	for w: Dictionary in u.loadout.get("weapons", []):
		if String(w.get("id", "")) == "mw_mimic_gun":
			var st := Weapons.state_of(u, w)
			st["mimic"] = [state.dice.die(20), state.dice.die(20), state.dice.die(20)]
			st["mimic_i"] = 0


static func mimic_cycle(u: Unit) -> void:
	for w: Dictionary in u.loadout.get("weapons", []):
		if String(w.get("id", "")) == "mw_mimic_gun" and Weapons.state_of(u, w).has("mimic"):
			var st := Weapons.state_of(u, w)
			st["mimic_i"] = (int(st["mimic_i"]) + 1) % 3


static func mimic_range(u: Unit, w: Dictionary) -> int:
	var st := Weapons.state_of(u, w)
	if not st.has("mimic"):
		return 0
	return int(st["mimic"][int(st.get("mimic_i", 0))])


## Perimeter Command Plate: a flat 2x2 plate within Range 5 (params.aim), set to "repulse" or
## "attract" (params.setting). A new one replaces the old. It has 20 HP and Evasion 5
## (target "zone:<id>"). It goes off for a character the first time it enters in a round, or
## when it ends its turn there.
static func print_pcp(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for z: Dictionary in Zones.of_kind(state, "pcp").duplicate():
		if z.get("owner", "") == u.id:
			events.append_array(Zones.remove(state, String(z["id"]), "replaced"))
	var aim: Vector2i = TurnAction.cell_param(params, "aim")
	var cells: Array = []
	for c in state.map.grid.footprint(aim, 2.0):
		cells.append([c.x, c.y])
	events.append_array(Zones.add(state, {"kind": "pcp", "owner": u.id, "label": "Perimeter Command Plate", "center": [aim.x, aim.y], "cells": cells,
		"setting": String(params.get("setting", "attract")), "hp": 20, "hit": {}, "rule_ref": "systems: Perimeter Command Plate"}))
	return events


static func pcp_trigger(state: GameState, z: Dictionary, t: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var owner := state.unit(String(z.get("owner", "")))
	var hit: Dictionary = z.get("hit", {})
	if owner == null or int(hit.get(t.id, -1)) == state.round_number or t.kind == Unit.KIND_DEPLOYABLE:
		return events
	if String(z.get("setting", "")) == "repulse" and t.side == owner.side:
		return events  # allies may fly 3 spaces as a free action (the table's)
	hit[t.id] = state.round_number
	z["hit"] = hit
	var save := Combat.skill_check(state, t, "hull", "Save vs Perimeter Command Plate", owner.save_target, 0, 0, [], true)
	events.append({"type": "skill_check", "unit": t.id, "check": save, "rule_ref": "systems: Perimeter Command Plate"})
	if save["success"]:
		return events
	if String(z.get("setting", "")) == "repulse":
		# Pushed 3 spaces (PROVISIONAL: away from the plate's center); Prone if it hits an obstruction.
		var from := t.cell
		var kb := Attacks.knock_back(state, t, Vector2i(int(z["center"][0]), int(z["center"][1])), 3, owner)
		events.append_array(kb)
		if state.map.grid.distance(from, t.cell) < 3:
			events.append_array(Combat.add_status(state, t, "Prone", owner.id))
	else:
		events.append_array(Combat.add_status(state, t, "Immobilized", "pcp:" + String(z["id"])))
	return events


## Assassin Drone: on deployment it targets a Blast 2 area (params.aim) within line of sight and
## Sensors. Area Denial (reaction, any number per round): a hostile starts moving in it or
## enters it: a ranged attack from the drone with your Grit, 3 kinetic on a hit.
static func assassin_area(state: GameState, u: Unit, drone: Unit, params: Dictionary) -> Array[Dictionary]:
	var aim: Variant = TurnAction.cell_param(params, "aim")
	if aim == null:
		return [] as Array[Dictionary]
	for z: Dictionary in Zones.of_kind(state, "assassin").duplicate():
		if z.get("owner", "") == u.id:
			Zones.remove(state, String(z["id"]), "retargeted")
	var cells := Zones.cells_around(state, [aim] as Array[Vector2i], 2)
	return Zones.add(state, {"kind": "assassin", "owner": u.id, "drone": drone.id, "label": "Assassin Drone", "center": [aim.x, aim.y], "cells": cells,
		"rule_ref": "systems: Assassin Drone"})


static func area_denial(state: GameState, z: Dictionary, t: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var owner := state.unit(String(z.get("owner", "")))
	var drone := state.unit(String(z.get("drone", "")))
	if owner == null or drone == null or not Combat.is_present(drone) or t.side == owner.side or t.kind == Unit.KIND_DEPLOYABLE:
		return events
	if owner.has_status("Stunned") or not Combat.is_present(owner):
		return events
	var d := Reactions.offer(state, owner, "area_denial", {"target": t.id, "suggested": {"take": true}}, {"take": true})
	if not d.get("take", false):
		return events
	var check := state.dice.check(owner.grit, 0, 0, t.evasion)
	events.append({"type": "attack_rolled", "attacker": drone.id, "target": t.id, "weapon": "", "weapon_name": "Assassin Drone", "kind": Attacks.KIND_RANGED,
		"check": check, "result": ("crit" if check["crit"] else "hit") if check["success"] else "miss", "rule_ref": "systems: Assassin Drone"})
	if check["success"]:
		events.append_array(Combat.deal_damage(state, t, [{"type": "Kinetic", "amount": 3}], {"source": owner.id}))
	return events


## Area Denial when a hostile starts moving inside the area.
static func area_denial_start(state: GameState, mover: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for z: Dictionary in Zones.of_kind(state, "assassin"):
		if Zones.contains(state, z, mover):
			events.append_array(area_denial(state, z, mover))
	return events


## Mesmer Beacon: Systems save, or until the end of its next turn its only voluntary movements
## are toward you.
static func mesmer(state: GameState, u: Unit, t: Unit) -> Array[Dictionary]:
	var save := Combat.skill_check(state, t, "systems", "Save vs Mesmer Beacon", u.save_target, 0, 0, [], true)
	var events: Array[Dictionary] = [{"type": "skill_check", "unit": t.id, "check": save, "rule_ref": "systems: Mesmer Charges"}]
	if not save["success"]:
		events.append_array(Effects.activate(state, t, [{"kind": "mesmerized", "by": u.id, "label": "Mesmer Beacon"}], "Mesmer Beacon", "end_next_turn"))
	return events


## Mimic Mesh: until the end of your next turn, Battlefield Awareness for an ally in Sensors.
static func mimic_mesh(state: GameState, u: Unit, ally: Unit) -> Array[Dictionary]:
	return Effects.activate(state, u, [{"kind": "mimic_target", "ally": ally.id, "label": "Mimic Mesh"}], "Mimic Mesh", "end_next_turn")


## Battlefield Awareness (reaction): a hostile action against your Mimic Mesh target: move 3
## spaces toward it first, ignoring engagement, without provoking. PROVISIONAL: hostile actions
## are attacks and tech actions; "as many times per round as it's triggered" means it doesn't
## use up your one reaction per turn.
static func battlefield_awareness(state: GameState, actor: Unit, target: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if actor == null or target == null or actor.side == target.side:
		return events
	var ids: Array = state.units.keys()
	ids.sort()
	for id: String in ids:
		var o := state.unit(id)
		if o == target or not Combat.is_present(o) or o.has_status("Stunned"):
			continue
		var on := false
		for e: Dictionary in Effects.of(o, "mimic_target"):
			on = on or String(e.get("ally", "")) == target.id
		if not on or Sight.unit_distance(state, o, target) <= 1:
			continue
		var d := Reactions.offer(state, o, "battlefield_awareness", {"target": target.id, "suggested": {"take": true}}, {"take": true})
		if not d.get("take", false):
			continue
		var path := Movement.pull_path_to(state, o, Sight.body_of(state, target), 1, 3)
		if path.size() < 2:
			continue
		var last: Array = path.back()
		o.cell = Vector2i(last[0], last[1])
		o.level = int(last[2])
		events.append({"type": "moved", "unit": o.id, "path": path, "mode": "walk", "cost": 0, "rule_ref": "systems: Mimic Mesh"})
		events.append_array(Combat.refresh_engagement(state))
	return events


## Guide the Flock (Puppetmaster): drones within Sensors, anyone's, each move up to 4 spaces.
## params.moves: [{"drone": id, "to": [x, y]}].
static func check_guide(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
	var ref := "systems: Puppetmaster"
	var moves: Variant = params.get("moves", [])
	if not moves is Array or (moves as Array).is_empty():
		return RuleResult.deny("Say which drones go where (params.moves: [{drone, to}]).", ref)
	for m: Variant in moves:
		var d := state.unit(String((m as Dictionary).get("drone", "")))
		var to: Variant = TurnAction.cell_param(m, "to")
		if d == null or d.destroyed or String(d.counters.get("deploy_type", "")) != "Drone":
			return RuleResult.deny("Only drones.", ref)
		if Sight.unit_distance(state, u, d) > u.sensors:
			return RuleResult.deny("That drone is out of your Sensors.", ref)
		if to == null or not state.map.has_cell(to) or state.map.grid.distance(d.cell, to) > 4:
			return RuleResult.deny("Up to 4 spaces.", ref)
	return RuleResult.allow()


static func guide_flock(state: GameState, _u: Unit, params: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for m: Dictionary in params.get("moves", []):
		var d := state.unit(String(m["drone"]))
		var to: Vector2i = TurnAction.cell_param(m, "to")
		var from := [d.cell.x, d.cell.y, d.level]
		var lv := maxi(d.level, state.map.ground_height(to))
		var clear := true
		for o: Unit in state.units.values():
			if o != d and Combat.is_present(o) and Movement._overlaps(Sight.make_body(state, to, lv, d.size), Sight.body_of(state, o)):
				clear = false
		if not clear:
			continue
		d.cell = to
		d.level = lv
		events.append({"type": "moved", "unit": d.id, "path": [from, [to.x, to.y, lv]], "mode": "fly", "cost": 0, "rule_ref": "systems: Puppetmaster"})
	return events


## Annihilation Nexus secondary attack (Protocol): if you attacked with it on your last turn,
## attack again centered on yourself or one of your drones within Sensors (params.center); no
## bonus damage, no further secondary attack.
static func annihilation_second(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
	var w: Dictionary = {}
	for x: Dictionary in u.loadout.get("weapons", []):
		if String(x.get("id", "")) == "mw_annihilation_nexus":
			w = x
	if w.is_empty():
		return [] as Array[Dictionary]
	var center := state.unit(String(params.get("center", u.id)))
	var at := [u.cell, u.level]
	if center != null and center != u:
		u.cell = center.cell  # the Burst is centered on the drone
		u.level = center.level
	var events := Areas.attack(state, u, w, {"skip_spend": true, "no_bonus_damage": true, "secondary": true, "aim": [u.cell.x, u.cell.y]})
	u.cell = at[0]
	u.level = at[1]
	u.counters.erase("annihilation_round")
	return events


## SISYPHUS Bend Probability: roll 2d20 and keep them (X, Y) until the end of your next turn,
## with the Probabilistic Cannibalism reaction.
static func bend_probability(state: GameState, u: Unit) -> Array[Dictionary]:
	var x := state.dice.die(20)
	var y := state.dice.die(20)
	u.counters["bent"] = [x, y]
	u.counters["bent_uses"] = 0
	var events: Array[Dictionary] = [{"type": "effect_triggered", "unit": u.id, "effect": "Bend Probability", "target": u.id, "rolls": [x, y], "rule_ref": "systems: SISYPHUS-Class NHP"}]
	events.append_array(Effects.activate(state, u, [{"kind": "prob_cannibal", "label": "Probabilistic Cannibalism"}], "Bend Probability", "end_next_turn"))
	return events


## Probabilistic Cannibalism (reaction, at most twice before the start of your next turn): when
## you or a character within Sensors would roll a d20, X or Y becomes the result. Offered only
## when a kept number would change the outcome your way (success for you and allies, failure
## for hostiles), with that number suggested.
static func sisyphus(state: GameState, roller: Unit, check: Dictionary) -> Dictionary:
	if state == null or check.is_empty() or not check.has("d20"):
		return check
	var ids: Array = state.units.keys()
	ids.sort()
	for id: String in ids:
		var o := state.unit(id)
		if not o.counters.has("bent") or not Effects.has(o, "prob_cannibal") or int(o.counters.get("bent_uses", 0)) >= 2 or not Combat.is_present(o):
			continue
		if o != roller and Sight.unit_distance(state, o, roller) > o.sensors:
			continue
		if not Reactions.can_react(o, "probabilistic_cannibalism", state).ok:
			continue
		var want_success := o.side == roller.side
		var pick := -1
		for v: int in o.counters["bent"]:
			var total := int(check["total"]) - int(check["d20"]) + v
			var success := total >= int(check.get("target", 10))
			if success != bool(check["success"]) and success == want_success:
				pick = v
				break
		if pick < 0:
			continue
		var d := Reactions.offer(state, o, "probabilistic_cannibalism", {"roller": roller.id, "rolled": check["d20"], "numbers": o.counters["bent"],
			"suggested": {"take": true, "value": pick}}, {"take": true, "value": pick})
		if not d.get("take", false):
			continue
		var v2 := int(d.get("value", pick))
		if not (o.counters["bent"] as Array).has(v2):
			v2 = pick
		o.counters["bent_uses"] = int(o.counters.get("bent_uses", 0)) + 1
		Reactions._mark_used(o, "probabilistic_cannibalism", state)
		var out := check.duplicate()
		out["rerolled_from"] = check["d20"]
		out["reroll_source"] = "SISYPHUS: Probabilistic Cannibalism"
		out["d20"] = v2
		out["total"] = int(check["total"]) - int(check["d20"]) + v2
		out["success"] = int(out["total"]) >= int(check.get("target", 10))
		out["crit"] = int(out["total"]) >= 20
		return out
	return check


## Conditions (statuses: Impaired, Immobilized, Jammed, Lock On, Shredded, Slowed, Stunned).
const CONDITIONS := ["Impaired", "Immobilized", "Jammed", "Lock On", "Shredded", "Slowed", "Stunned"]


## Metahook: the character linked with `u`, while it's within the Goblin's Sensors and line
## of sight; null otherwise.
static func metahook_partner(state: GameState, u: Unit) -> Unit:
	if state == null or u == null or not u.counters.has("metahook"):
		return null
	var o := state.unit(String(u.counters["metahook"]))
	if o == null or not Combat.is_present(o) or not Combat.is_present(u):
		return null
	var goblin: Unit = u if u.counters.get("metahook_owner", false) else o
	var other: Unit = o if goblin == u else u
	if Sight.unit_distance(state, goblin, other) > goblin.sensors or not Sight.unit_line_of_sight(state, goblin, other):
		return null
	return o


static func metahook(state: GameState, u: Unit, ally: Unit) -> Array[Dictionary]:
	for x: Unit in state.units.values():
		if String(x.counters.get("metahook", "")) == u.id or x == u:
			x.counters.erase("metahook")
			x.counters.erase("metahook_owner")
	u.counters["metahook"] = ally.id
	u.counters["metahook_owner"] = true
	ally.counters["metahook"] = u.id
	return [{"type": "effect_triggered", "unit": u.id, "effect": "Metahook", "target": ally.id, "rule_ref": "systems: Metahook"}] as Array[Dictionary]


## Puppet System (H0R_OS I): the target moves its maximum Speed toward params.toward. It's
## involuntary but provokes reactions and Engagement as normal (not a knockback, push or pull).
## PROVISIONAL: in a straight line, stopping at obstructions.
static func puppet(state: GameState, u: Unit, t: Unit, params: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = Reactions.overwatch(state, t)
	if not Combat.is_present(t):
		return events
	var toward: Vector2i = TurnAction.cell_param(params, "toward")
	var path := Movement.push_path(state, t, t.cell * 2 - toward, t.speed)
	if path.size() < 2:
		return events
	var last: Array = path.back()
	t.cell = Vector2i(last[0], last[1])
	events.append({"type": "moved", "unit": t.id, "path": path, "mode": "involuntary", "cost": 0, "rule_ref": "systems: H0R_OS System Upgrade I"})
	events.append_array(Abilities.check_mines(state, t, path))
	events.append_array(Zones.check_path(state, t, path))
	events.append_array(Combat.after_movement(state))
	return events


## Law of Blades, Predator/Prey Concepts: the target attacks a character or object you choose
## (params.forced_target, not you... any different character) with a weapon you choose
## (params.forced_weapon, else its first that can reach), as a reaction.
static func predator_prey(state: GameState, u: Unit, t: Unit, params: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var victim := state.unit(String(params.get("forced_target", "")))
	if victim == null or victim == t or not Combat.is_present(victim):
		return events
	var w := Weapons.find(t, String(params.get("forced_weapon", "")))
	if w.is_empty():
		for x: Dictionary in t.loadout.get("weapons", []):
			if Attacks.preview(state, t, x, victim, {"reaction": true})["ok"]:
				w = x
				break
	if w.is_empty() or not Attacks.preview(state, t, w, victim, {"reaction": true})["ok"]:
		events.append({"type": "action_skipped", "unit": t.id, "action": "predator_prey", "reason": "No weapon can reach that target.", "rule_ref": "systems: Law of Blades"})
		return events
	Reactions._mark_used(t, "law_of_blades", state)
	events.append_array(Attacks.attack(state, t, w, victim, {"reaction": true}))
	return events


## Law of Blades, Slave Systems: the target takes an action you choose as a reaction: boost,
## stabilize, improvised_attack, grapple or ram (params.forced_action, forced_params).
static func slave_systems(state: GameState, u: Unit, t: Unit, params: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var what := String(params.get("forced_action", ""))
	if not what in ["boost", "stabilize", "improvised_attack", "grapple", "ram"]:
		return events
	var h: TurnAction = RulesEngine.registry[what]
	var p: Dictionary = (params.get("forced_params", {}) as Dictionary).duplicate()
	var saved := t.turn
	t.turn = {"quick": 0, "full": false, "taken": [], "quick_tech": [], "move_spent": 0, "moved": false, "acted": false, "overcharged": false, "free_quick": 0}
	var r := h.check(state, t, p)
	if r.ok:
		Reactions._mark_used(t, "law_of_blades", state)
		events.append_array(h.apply(state, t, p))
	else:
		events.append({"type": "action_skipped", "unit": t.id, "action": what, "reason": r.reason, "rule_ref": "systems: Law of Blades"})
	t.turn = saved
	return events


## H0R_OS III Dimensional Emblems: three Size 1 constructs in free spaces next to the target,
## not next to each other (params.cells to choose, else the first that fit). Replaces your
## earlier ones.
static func emblems(state: GameState, u: Unit, t: Unit, params: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for z: Dictionary in Zones.of_kind(state, "emblem").duplicate():
		if z.get("owner", "") == u.id:
			events.append_array(Zones.remove(state, String(z["id"]), "replaced"))
	var wanted: Array = params.get("cells", [])
	var options: Array[Vector2i] = []
	for c: Variant in wanted:
		options.append(Vector2i(int(c[0]), int(c[1])))
	if options.is_empty():
		for c in Zones.cells_around(state, state.map.grid.footprint(t.cell, t.size), 1):
			options.append(Vector2i(int(c[0]), int(c[1])))
	var chosen: Array[Vector2i] = []
	for c in options:
		if chosen.size() >= 3 or state.map.grid.footprint(t.cell, t.size).has(c) or not Movement.placement(state, 1.0, c, state.map.ground_height(c))["ok"]:
			continue
		var taken := false
		for o: Unit in state.units.values():
			taken = taken or (Combat.is_present(o) and state.map.grid.footprint(o.cell, o.size).has(c))
		if taken or chosen.any(func(x: Vector2i) -> bool: return state.map.grid.distance(x, c) <= 1):
			continue
		chosen.append(c)
	for c in chosen:
		events.append_array(Zones.add(state, {"kind": "emblem", "owner": u.id, "label": "Dimensional Emblem", "cells": [[c.x, c.y]], "center": [c.x, c.y],
			"rule_ref": "systems: H0R_OS System Upgrade III"}))
	return events


## Celestial Shackles: the target's space is marked; once during your turn, if it has left,
## a free action (shackle_return) teleports it back. A Systems save (quick action) ends it.
static func shackle(u: Unit, t: Unit) -> Array[Dictionary]:
	t.counters["shackled"] = {"by": u.id, "cell": [t.cell.x, t.cell.y], "level": t.level}
	return [{"type": "effect_triggered", "unit": u.id, "effect": "Celestial Shackles", "target": t.id, "rule_ref": "systems: H0R_OS System Upgrade III"}] as Array[Dictionary]


## Weapon and system reactions to an attack: Autopod (an ally's attack consumed Lock On on a
## target within 15: hit it automatically for 3 kinetic), Vorpal Gun (a hostile in Range and
## line of sight damaged an ally: attack it), Monitor Module (the monitored ally was attacked
## next to the Gorgon: Skirmish the attacker for half damage).
static func after_attack(state: GameState, attacker: Unit, target: Unit, lock_on: bool, dealt: bool) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if target.kind == Unit.KIND_DEPLOYABLE:
		return events
	var ids: Array = state.units.keys()
	ids.sort()
	for id: String in ids:
		var o := state.unit(id)
		if o == attacker or not Combat.is_present(o) or not Combat.is_present(attacker):
			continue
		for w: Dictionary in o.loadout.get("weapons", []):
			match String(w.get("id", "")):
				"mw_autopod":
					if lock_on and o != target and Combat.is_present(target) and Sight.unit_distance(state, o, target) <= 15 \
							and TalentRules._round_ok(state, o, "autopod") and Reactions.can_react(o, "autonomous_assault", state).ok:
						var d := Reactions.offer(state, o, "autonomous_assault", {"target": target.id, "suggested": {"take": true}}, {"take": true})
						if d.get("take", false):
							TalentRules._use_round(state, o, "autopod")
							Reactions._mark_used(o, "autonomous_assault", state)
							events.append({"type": "effect_triggered", "unit": o.id, "effect": "Autopod: Autonomous Assault", "target": target.id, "rule_ref": "weapons: Autopod"})
							events.append_array(Combat.deal_damage(state, target, [{"type": "Kinetic", "amount": 3}], {"source": o.id}))
				"mw_vorpal_gun":
					if dealt and o.side == target.side and o != target and attacker.side != o.side and TalentRules._round_ok(state, o, "vorpal") \
							and Reactions.can_react(o, "snicker_snack", state).ok and Attacks.preview(state, o, w, attacker, {"reaction": true, "fired_by_rule": true})["ok"]:
						var d := Reactions.offer(state, o, "snicker_snack", {"target": attacker.id, "suggested": {"take": true}}, {"take": true})
						if d.get("take", false):
							TalentRules._use_round(state, o, "vorpal")
							Reactions._mark_used(o, "snicker_snack", state)
							events.append_array(Attacks.attack(state, o, w, attacker, {"reaction": true, "fired_by_rule": true}))
		var mon: Dictionary = o.counters.get("monitor", {})
		if not mon.is_empty() and Effects.has(o, "monitor_on") and String(mon.get("ally", "")) == target.id and int(mon.get("charges", 0)) > 0 and o.side != attacker.side \
				and Sight.unit_distance(state, o, target) <= 1 and Reactions.can_react(o, "monitor", state).ok:
			for mw: Dictionary in o.loadout.get("weapons", []):
				if Attacks.preview(state, o, mw, attacker, {"reaction": true})["ok"]:
					var d := Reactions.offer(state, o, "monitor", {"target": attacker.id, "weapon": mw.get("key", ""), "suggested": {"take": true}}, {"take": true})
					if d.get("take", false):
						mon["charges"] = int(mon["charges"]) - 1
						Reactions._mark_used(o, "monitor", state)
						events.append_array(Attacks.attack(state, o, mw, attacker, {"reaction": true, "half_damage": true}))
					break
	return events


## Monitor Module: 1d3 charges and an adjacent ally, until the end of your next turn.
static func monitor(state: GameState, u: Unit, ally: Unit) -> Array[Dictionary]:
	var roll := state.dice.roll("1d3")
	u.counters["monitor"] = {"ally": ally.id, "charges": int(roll["total"])}
	var events: Array[Dictionary] = [{"type": "effect_triggered", "unit": u.id, "effect": "Monitor Module", "target": ally.id, "charges": int(roll["total"]), "rule_ref": "systems: Monitor Module"}]
	events.append_array(Effects.activate(state, u, [{"kind": "monitor_on", "label": "Monitor Module"}], "Monitor Module", "end_next_turn"))
	return events


## Gravity Gun: no attack roll; characters in the blast make a Hull save or take 1d6 energy and
## are pulled as close to the center as they can.
static func gravity_gun(state: GameState, u: Unit, w: Dictionary, p: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var roll := state.dice.roll("1d6")
	var origin: Array = p["origin"]
	var center := Sight.make_body(state, Vector2i(origin[0], origin[1]), state.map.ground_height(Vector2i(origin[0], origin[1])), 1.0)
	for id: String in p["targets"]:
		var t := state.unit(id)
		if t == null or not Combat.is_present(t):
			continue
		var save := Combat.skill_check(state, t, "hull", "Save vs Gravity Gun", u.save_target, 0, 0, [], true)
		events.append({"type": "skill_check", "unit": t.id, "check": save, "rule_ref": "weapons: Gravity Gun"})
		if save["success"]:
			continue
		events.append_array(Combat.deal_damage(state, t, [{"type": "Energy", "amount": int(roll["total"])}], {"source": u.id, "area": true}))
		if Combat.is_present(t):
			events.append_array(Attacks.pull_to(state, t, center, 0))
	return events


## Lands a flyer at once without falling damage; it can't fly until the end of its next turn
## (Bouncing Mine).
static func ground_flyer(state: GameState, t: Unit, by: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if t.flying:
		var start := [t.cell.x, t.cell.y, t.level]
		var lv := state.map.ground_height(t.cell)
		t.level = lv
		t.flying = false
		events.append({"type": "moved", "unit": t.id, "path": [start, [t.cell.x, t.cell.y, lv]], "mode": "fall", "cost": 0, "note": "lands without damage"})
	events.append_array(Combat.add_status(state, t, "Grounded", by.id if by != null else "", t.id))
	return events


## Roller Grenade: rolls along a line 10 path from the user toward params.aim and goes off at
## the first character it passes through or next to: Agility save or 1d6+3 explosive and
## knocked 3 spaces the way it rolled; half damage and no knockback on a success.
## PROVISIONAL: it rolls over terrain (it bounces over obstructions up to Size 1).
static func roller_grenade(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var aim: Vector2i = TurnAction.cell_param(params, "aim")
	var line := state.map.grid.line(u.cell, u.cell + (aim - u.cell) * 12)
	var path: Array = []
	var victim: Unit = null
	for c: Vector2i in line:
		if c == u.cell:
			continue
		if path.size() >= 10 or not state.map.has_cell(c):
			break
		path.append([c.x, c.y])
		var ids: Array = state.units.keys()
		ids.sort()
		for id: String in ids:
			var o := state.unit(id)
			if o != u and Combat.is_present(o) and o.kind != Unit.KIND_DEPLOYABLE and state.map.grid.footprint_distance(state.map.grid.footprint(o.cell, o.size), [c] as Array[Vector2i]) <= 1:
				victim = o
				break
		if victim != null:
			break
	events.append({"type": "area_effect", "unit": u.id, "cells": path, "center": path.back() if not path.is_empty() else [u.cell.x, u.cell.y], "rule_ref": "systems: Roller Grenade"})
	if victim == null:
		return events
	var roll := state.dice.roll("1d6+3")
	var save := Combat.skill_check(state, victim, "agility", "Save vs Roller Grenade", u.save_target, 0, 0, [], true)
	events.append({"type": "skill_check", "unit": victim.id, "check": save, "rule_ref": "systems: Roller Grenade"})
	var amount := int(roll["total"])
	if save["success"]:
		amount -= amount / 2
	events.append_array(Combat.deal_damage(state, victim, [{"type": "Explosive", "amount": amount}], {"source": u.id, "area": true}))
	if not save["success"] and Combat.is_present(victim):
		events.append_array(Attacks.knock_back(state, victim, victim.cell - (aim - u.cell), 3, u))
	return events


## Flak Launcher: a flying character saves (Agility) or lands at once (no damage), is Slowed
## and can't fly until the end of its next turn.
static func flak(state: GameState, u: Unit, t: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var save := Combat.skill_check(state, t, "agility", "Save vs Flak Launcher", u.save_target, 0, 0, [], true)
	events.append({"type": "skill_check", "unit": t.id, "check": save, "rule_ref": "systems: Flak Launcher"})
	if save["success"]:
		return events
	if t.flying:
		var start := [t.cell.x, t.cell.y, t.level]
		var lv := state.map.ground_height(t.cell)
		t.level = lv
		t.flying = false
		events.append({"type": "moved", "unit": t.id, "path": [start, [t.cell.x, t.cell.y, lv]], "mode": "fall", "cost": 0, "note": "lands without damage"})
	events.append_array(Combat.add_status(state, t, "Slowed", u.id, t.id))
	events.append_array(Combat.add_status(state, t, "Grounded", u.id, t.id))
	return events


## Explosive Vents: 1/round, when it clears all heat or takes stress, burst 1: 2 heat and 2 burn.
static func vents(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not Effects.has(u, "explosive_vents") or int(u.counters.get("vents_round", -1)) == state.round_number or not Combat.is_present(u):
		return events
	u.counters["vents_round"] = state.round_number
	events.append({"type": "effect_triggered", "unit": u.id, "effect": "Explosive Vents", "target": u.id, "rule_ref": "systems: Explosive Vents"})
	var ids: Array = state.units.keys()
	ids.sort()
	for id: String in ids:
		var o := state.unit(id)
		if o != u and Combat.is_present(o) and o.kind != Unit.KIND_DEPLOYABLE and Sight.unit_distance(state, u, o) <= 1:
			events.append_array(Combat.deal_damage(state, o, [{"type": "Burn", "amount": 2}, {"type": "Heat", "amount": 2}], {"source": u.id}))
	return events


## Napalm Grenade: a line 5 from where it lands toward params.toward; Agility save, 2 burn or 1.
static func napalm(state: GameState, u: Unit, op: Dictionary, params: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var aim: Vector2i = TurnAction.cell_param(params, "aim")
	var toward: Variant = TurnAction.cell_param(params, "toward")
	_mark_launcher(state, u, op, aim)
	var cells: Array = [[aim.x, aim.y]]
	if toward != null and toward != aim:
		var line := state.map.grid.line(aim, toward)
		for i in range(1, mini(5, line.size())):
			cells.append([line[i].x, line[i].y])
	events.append({"type": "area_effect", "unit": u.id, "cells": cells, "center": [aim.x, aim.y], "rule_ref": "systems: HAVOK Charges"})
	var ids: Array = state.units.keys()
	ids.sort()
	for id: String in ids:
		var o := state.unit(id)
		if not Combat.is_present(o) or o.kind == Unit.KIND_DEPLOYABLE:
			continue
		var inside := false
		for c in state.map.grid.footprint(o.cell, o.size):
			inside = inside or cells.has([c.x, c.y])
		if not inside:
			continue
		var save := Combat.skill_check(state, o, "agility", "Save vs Napalm Grenade", u.save_target, 0, 0, [], true)
		events.append({"type": "skill_check", "unit": o.id, "check": save})
		events.append_array(Combat.deal_damage(state, o, [{"type": "Burn", "amount": 1 if save["success"] else 2}], {"source": u.id}))
	return events


## Auto-Cooler / AGNI and other start/end of turn heat systems.
static func ha_turn_started(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if u.counters.get("auto_cooler", false):
		u.counters.erase("auto_cooler")
		events.append({"type": "effect_triggered", "unit": u.id, "effect": "Auto-Cooler", "target": u.id, "rule_ref": "systems: Auto-Cooler"})
		events.append_array(Combat.clear_heat(u, "Auto-Cooler"))
		events.append_array(vents(state, u))
	if Effects.has(u, "deep_well") and u.has_status("Danger Zone"):
		# Deep Well Heat Sink: Resistance to heat for the rest of the turn.
		var active: Array = u.counters.get("active_effects", [])
		active.append({"kind": "resist", "damage": ["Heat"], "label": "Deep Well Heat Sink", "expires": {"unit": u.id, "when": "end", "count": 1}})
		u.counters["active_effects"] = active
	return events


static func ha_turn_ending(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if u.counters.get("agni", false):
		u.counters.erase("agni")
		events.append({"type": "effect_triggered", "unit": u.id, "effect": "AGNI Protocol", "target": u.id, "rule_ref": "systems: AGNI-Class NHP"})
		events.append_array(Combat.clear_heat(u, "AGNI Protocol"))
		events.append_array(vents(state, u))
		var foot: Array[Vector2i] = []
		foot.assign(state.map.grid.footprint(u.cell, u.size))
		var ids: Array = state.units.keys()
		ids.sort()
		for id: String in ids:
			var o := state.unit(id)
			var d := Sight.unit_distance(state, u, o) if o != u else 99
			if o == u or not Combat.is_present(o) or o.kind == Unit.KIND_DEPLOYABLE or d > 2:
				continue
			var save := Combat.skill_check(state, o, "engineering", "Save vs AGNI vent", u.save_target, 0, 0, [], true)
			events.append({"type": "skill_check", "unit": o.id, "check": save})
			if not save["success"]:
				events.append_array(Combat.deal_damage(state, o, [{"type": "Burn", "amount": 2}], {"source": u.id}))
				events.append_array(Attacks.knock_back(state, o, u.cell, 3 - d, u))
		events.append_array(Zones.add(state, {"kind": "smoke", "owner": u.id, "label": "AGNI vent", "center": [u.cell.x, u.cell.y],
			"cells": Zones.cells_around(state, foot, 2), "expires": {"unit": u.id, "when": "end", "count": 1}, "rule_ref": "systems: AGNI-Class NHP"}))
	if u.counters.has("grounded_check"):
		if not u.turn.get("moved", false):
			u.counters.erase("grounded_check")
			if u.has_status("Slowed") and u.statuses["Slowed"].get("source", "") == "Gravity Grenade":
				events.append_array(Combat.remove_status(u, "Slowed", "no voluntary movement for a full turn"))
	return events


## The Auto-Cooler is spoiled by damage, movement or exceeding the Heat Cap.
static func spoil_cooler(u: Unit) -> void:
	u.counters.erase("auto_cooler")


## Gravity Grenade: the target saves (Agility) or is Slowed until a turn of its own with no
## voluntary movement.
static func gravity_grenade(state: GameState, u: Unit, t: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var save := Combat.skill_check(state, t, "agility", "Save vs Gravity Grenade", u.save_target, 0, 0, [], true)
	events.append({"type": "skill_check", "unit": t.id, "check": save, "rule_ref": "systems: Grounding Charges"})
	if not save["success"]:
		events.append_array(Combat.add_status(state, t, "Slowed", "Gravity Grenade"))
		t.counters["grounded_check"] = true
	return events


## Grounding Mine, detonated remotely: one character within 5 of it saves (Hull) or is pulled
## to it and knocked Prone (flyers land).
static func grounding_mine(state: GameState, u: Unit, t: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var mine: Unit = null
	for m: Unit in state.units.values():
		if m.counters.get("owner", "") == u.id and m.name == "Grounding Mine" and not m.destroyed and m.counters.get("armed", false) and Sight.unit_distance(state, m, t) <= 5:
			mine = m
	if mine == null:
		return events
	mine.destroyed = true
	events.append({"type": "mine_triggered", "mine": mine.id, "unit": t.id, "text": mine.counters.get("text", ""), "rule_ref": "systems: Grounding Charges"})
	var save := Combat.skill_check(state, t, "hull", "Save vs Grounding Mine", u.save_target, 0, 0, prone_save_sources(t), true)
	events.append({"type": "skill_check", "unit": t.id, "check": save})
	if save["success"]:
		return events
	t.flying = false
	events.append_array(Attacks.pull_to(state, t, Sight.body_of(state, mine), 0))
	events.append_array(Combat.add_status(state, t, "Prone", u.id))
	return events


## Repulser Field: burst 2, Hull save or knocked 2 away; then every mine in the area goes off.
static func repulser(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var ids: Array = state.units.keys()
	ids.sort()
	for id: String in ids:
		var o := state.unit(id)
		if o == u or not Combat.is_present(o) or o.kind == Unit.KIND_DEPLOYABLE or Sight.unit_distance(state, u, o) > 2:
			continue
		var save := Combat.skill_check(state, o, "hull", "Save vs Repulser Field", u.save_target, 0, 0, prone_save_sources(o), true)
		events.append({"type": "skill_check", "unit": o.id, "check": save, "rule_ref": "systems: Repulser Field"})
		if not save["success"]:
			events.append_array(Attacks.knock_back(state, o, u.cell, 2, u))
	for id: String in ids:
		var m := state.unit(id)
		if m != null and not m.destroyed and m.counters.get("deploy_type", "") == "Mine" and Sight.unit_distance(state, u, m) <= 2:
			events.append_array(Abilities.detonate(state, m, u))
	return events


## Clamp Bombs: Engineering save or they clamp on; they go off at the end of the target's
## next turn (1d6+3 AP explosive, half to adjacent characters) unless it moves 4+ spaces.
static func clamp_bombs(state: GameState, u: Unit, t: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var save := Combat.skill_check(state, t, "engineering", "Save vs Clamp Bombs", u.save_target, 0, 0, [], true)
	events.append({"type": "skill_check", "unit": t.id, "check": save, "rule_ref": "systems: Clamp Bombs"})
	if not save["success"]:
		t.counters["clamp_bombs"] = {"by": u.id, "turns": 2 if state.active_unit == t.id else 1, "moved": 0}
		events.append_array(Combat.add_status(state, t, "Clamp Bombs", u.id))
	return events


static func clamp_turn_end(state: GameState, t: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var cb: Dictionary = t.counters.get("clamp_bombs", {})
	if cb.is_empty():
		return events
	if int(cb.get("moved", 0)) >= 4:
		t.counters.erase("clamp_bombs")
		return Combat.remove_status(t, "Clamp Bombs", "shaken off")
	cb["moved"] = 0
	cb["turns"] = int(cb["turns"]) - 1
	if int(cb["turns"]) > 0:
		return events
	t.counters.erase("clamp_bombs")
	events.append_array(Combat.remove_status(t, "Clamp Bombs", "detonated"))
	var roll := state.dice.roll("1d6+3")
	var dmg := int(roll["total"])
	events.append_array(Combat.deal_damage(state, t, [{"type": "Explosive", "amount": dmg}], {"ap": true, "source": String(cb["by"])}))
	for o: Unit in state.units.values():
		if o != t and Combat.is_present(o) and o.kind != Unit.KIND_DEPLOYABLE and Sight.unit_distance(state, o, t) <= 1:
			events.append_array(Combat.deal_damage(state, o, [{"type": "Explosive", "amount": dmg - dmg / 2}], {"ap": true, "source": String(cb["by"])}))
	return events


## Stasis Generator: Stunned, immune to all damage and effects, can't be moved or targeted,
## until the end of its next turn (1/scene each; hostiles may save, Engineering).
static func stasis(state: GameState, u: Unit, t: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var once: Array = t.counters.get("stasis_used", [])
	if once.has(u.id):
		return [{"type": "no_effect", "target": t.id, "reason": "Only once per scene on each character."}] as Array[Dictionary]
	once.append(u.id)
	t.counters["stasis_used"] = once
	if t.side != u.side:
		var save := Combat.skill_check(state, t, "engineering", "Save vs Stasis Generator", u.save_target, 0, 0, [], true)
		events.append({"type": "skill_check", "unit": t.id, "check": save, "rule_ref": "systems: Stasis Generator"})
		if save["success"]:
			return events
	events.append_array(Combat.add_status(state, t, "Stunned", u.id, t.id))
	events.append_array(Combat.add_status(state, t, "In Stasis", u.id, t.id))
	var active: Array = t.counters.get("active_effects", [])
	var exp := {"unit": t.id, "when": "end", "count": 2 if state.active_unit == t.id else 1}
	for e: Dictionary in [{"kind": "immune", "damage": "All"}, {"kind": "immovable"}]:
		var c := e.duplicate()
		c["label"] = "Stasis Generator"
		c["expires"] = exp.duplicate()
		active.append(c)
	t.counters["active_effects"] = active
	return events


static func in_stasis(t: Unit) -> bool:
	return t != null and t.has_status("In Stasis")


## Enclave-Pattern Support Shield: a burst 3 dome until the end of your next turn; you're
## Immobilized; attacks from outside against characters inside get +1 Difficulty.
static func enclave(state: GameState, u: Unit) -> Array[Dictionary]:
	var foot: Array[Vector2i] = []
	foot.assign(state.map.grid.footprint(u.cell, u.size))
	var events := Zones.add(state, {"kind": "enclave", "owner": u.id, "label": "Enclave dome", "center": [u.cell.x, u.cell.y],
		"cells": Zones.cells_around(state, foot, 3), "expires": {"unit": u.id, "when": "end", "count": 2 if state.active_unit == u.id else 1},
		"rule_ref": "systems: Enclave-Pattern Support Shield"})
	events.append_array(Combat.add_status(state, u, "Immobilized", "Enclave-Pattern Support Shield", u.id))
	return events


static func enclave_difficulty(state: GameState, attacker: Unit, target: Unit) -> int:
	for z: Dictionary in Zones.of_kind(state, "enclave"):
		if Zones.contains(state, z, target) and not Zones.contains(state, z, attacker):
			return 1
	return 0


## Blinkfield Intervention (the dome's owner, 2 heat): Resistance to an attack inside the dome.
static func blinkfield(state: GameState, attacker: Unit, target: Unit) -> Dictionary:
	var out := {"events": [] as Array[Dictionary], "resist": false}
	for z: Dictionary in Zones.of_kind(state, "enclave"):
		var owner := state.unit(String(z.get("owner", "")))
		if owner == null or not Zones.contains(state, z, target) or not Reactions.can_react(owner, "blinkfield", state).ok:
			continue
		var auto := {"take": target.side == owner.side}
		var d := Reactions.offer(state, owner, "blinkfield", {"attacker": attacker.id, "target": target.id, "suggested": auto}, auto)
		if not d.get("take", false):
			continue
		Reactions._mark_used(owner, "blinkfield", state)
		out["events"].append({"type": "reaction", "unit": owner.id, "reaction": "blinkfield", "target": target.id, "rule_ref": "systems: Enclave-Pattern Support Shield"})
		out["events"].append_array(Combat.apply_heat(state, owner, 2, "Blinkfield Intervention"))
		out["resist"] = true
		return out
	return out


## Flash Anchor: when a character in its Sensors and line of sight would be pushed, pulled,
## knocked back or knocked Prone, its owner may take 2 heat to prevent it (and that character is
## immune to it until the start of its next turn).
static func flash_anchor(state: GameState, target: Unit, what: String) -> Dictionary:
	var out := {"events": [] as Array[Dictionary], "prevented": false}
	if int(target.counters.get("anchored_round", -1)) == state.round_number:
		out["prevented"] = true
		return out
	for o: Unit in state.units.values():
		if not Effects.has(o, "flash_anchor") or o.side != target.side or not Combat.is_present(o):
			continue
		if o != target and (Sight.unit_distance(state, o, target) > o.sensors or not Sight.unit_line_of_sight(state, o, target)):
			continue
		if not Reactions.can_react(o, "flash_lock", state).ok:
			continue
		var auto := {"take": true}
		var d := Reactions.offer(state, o, "flash_lock", {"target": target.id, "what": what, "suggested": auto}, auto)
		if not d.get("take", false):
			continue
		Reactions._mark_used(o, "flash_lock", state)
		target.counters["anchored_round"] = state.round_number
		out["events"].append({"type": "reaction", "unit": o.id, "reaction": "flash_lock", "target": target.id, "what": what, "rule_ref": "systems: Flash Anchor"})
		out["events"].append_array(Combat.apply_heat(state, o, 2, "Flash Lock"))
		out["prevented"] = true
		return out
	return out


## Stasis Bolt (charged): Interdiction Point, a contested ranged attack roll against a ranged
## attack on you or an ally within range 5; win, and the attack misses.
static func interdiction_point(state: GameState, attacker: Unit, target: Unit, attack_total: int) -> Dictionary:
	var out := {"events": [] as Array[Dictionary], "missed": false}
	for o: Unit in state.units.values():
		if not o.counters.get("stasis_bolt", false) or o.side != target.side or not Combat.is_present(o) or Sight.unit_distance(state, o, target) > 5:
			continue
		if not Reactions.can_react(o, "interdiction_point", state).ok:
			continue
		var auto := {"take": true}
		var d := Reactions.offer(state, o, "interdiction_point", {"attacker": attacker.id, "target": target.id, "suggested": auto}, auto)
		if not d.get("take", false):
			continue
		Reactions._mark_used(o, "interdiction_point", state)
		o.counters.erase("stasis_bolt")
		var roll := state.dice.check(o.grit, 0, 0, 0, [])
		out["missed"] = int(roll["total"]) >= attack_total
		out["events"].append({"type": "reaction", "unit": o.id, "reaction": "interdiction_point", "target": target.id, "roll": roll, "against": attack_total, "missed": out["missed"], "rule_ref": "systems: Stasis Bolt"})
		return out
	return out


## Plasma Gauntlet (Danger Zone only): an adjacent character saves (Agility) or takes 4d6 AP
## energy and is knocked Prone; half on a success. You take half of it as heat and are Stunned.
static func plasma_gauntlet(state: GameState, u: Unit, t: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var roll := state.dice.roll("4d6")
	var save := Combat.skill_check(state, t, "agility", "Save vs Plasma Gauntlet", u.save_target, 0, 0, prone_save_sources(t), true)
	events.append({"type": "skill_check", "unit": t.id, "check": save, "rule_ref": "systems: Plasma Gauntlet"})
	var dmg := int(roll["total"])
	if save["success"]:
		dmg -= dmg / 2
	events.append_array(Combat.deal_damage(state, t, [{"type": "Energy", "amount": dmg}], {"ap": true, "source": u.id}))
	if not save["success"] and Combat.is_present(t):
		events.append_array(Combat.add_status(state, t, "Prone", u.id))
	events.append_array(Combat.apply_heat(state, u, dmg - dmg / 2, "Plasma Gauntlet"))
	events.append_array(Combat.add_status(state, u, "Stunned", "Plasma Gauntlet", "", u.id))
	return events


## External Batteries: destroyed when it takes structure damage, 1d6 AP explosive to it.
static func batteries_blow(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for s: Dictionary in u.loadout.get("systems", []):
		if s.get("id", "") != "ms_external_batteries" or Abilities.source_state(u, String(s["key"]))["destroyed"]:
			continue
		Abilities.source_state(u, String(s["key"]))["destroyed"] = true
		u.loadout["effects"] = (u.loadout.get("effects", []) as Array).filter(func(e: Dictionary) -> bool: return e.get("label", "") != "ms_external_batteries")
		events.append({"type": "equipment_destroyed", "unit": u.id, "system": s["key"], "name": "External Batteries"})
		var roll := state.dice.roll("1d6")
		events.append_array(Combat.deal_damage(state, u, [{"type": "Explosive", "amount": int(roll["total"])}], {"ap": true, "unreducible": true, "source": u.id}))
	return events
