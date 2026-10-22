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
		if not Combat.is_present(o) or o.kind == Unit.KIND_DEPLOYABLE:
			continue
		for c in state.map.grid.footprint(o.cell, o.size):
			if cells.has([c.x, c.y]):
				ids.append(o.id)
				break
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
