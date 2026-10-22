class_name CoreBonuses
extends RefCounted
## Core bonuses that act during play (GMS Core p.118, IPS-N p.127, SSC p.158, HORUS p.191,
## HA p.225). Stat changes are applied when the mech is built (UnitFactory, effect kind
## "stat"); the rest are hooks:
##   briareos            Resistance to all damage at 1 Structure or less; at 0 HP and 0 Structure
##                       not destroyed: a structure damage check each time it takes damage, and no
##                       HP back until a rest or Full Repair
##   titanomachy         after a successful Ram or Grapple against a mech, another as a free
##                       action (1/round); melee knockback +1
##   universal_compat    spending CP on a core system: all HP back, all heat cooled, 1d20: on 20,
##                       regain 1 CP
##   open_door           1/round, a character failing a save against you takes 2 heat
##   held_image          1/round reaction at the start of an ally's turn: Lock On (Sensors, LOS)
##   tomorrows_thought   after a tech hit, the next melee attack on that target: +1 Accuracy and
##                       damage that can't be reduced
##   transubstantiation  taking structure damage, it leaves the battlefield until its next turn
##   adaptive_reactor    Stabilize to cool: may spend 2 Repairs to clear 1 stress damage
##   overcharge_cover    Overcharging: soft cover until the start of your next turn
##   stasis_shielding    taking stress damage: Resistance to all damage until your next turn
##   overcharge_cap      Overcharge heat never past 1d6 (Heatfall)
##   limited_bonus       Limited systems and weapons +2 charges (Integrated Ammo Feeds)

const REF := "core bonuses"


static func briareos_resists(u: Unit) -> bool:
	return Effects.has(u, "briareos") and u.structure <= 1


## Briareos at 0 Structure: instead of being destroyed.
static func briareos_holds(u: Unit) -> bool:
	return Effects.has(u, "briareos")


static func after_hit_ram_grapple(state: GameState, u: Unit, target: Unit, hit: bool) -> void:
	if hit and target.kind == Unit.KIND_MECH and Effects.has(u, "titanomachy") and int(u.counters.get("titanomachy_round", -1)) != state.round_number:
		u.counters["titanomachy_round"] = state.round_number
		u.turn["titanomachy_ready"] = true


static func universal_compat(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not Effects.has(u, "universal_compat"):
		return events
	u.hp = u.max_hp
	events.append({"type": "hp_changed", "unit": u.id, "hp": u.hp, "overshield": u.overshield, "source": "Universal Compatibility"})
	events.append_array(Combat.clear_heat(u, "Universal Compatibility"))
	var roll := state.dice.die(20)
	events.append({"type": "effect_triggered", "unit": u.id, "effect": "Universal Compatibility", "target": u.id, "roll": roll, "rule_ref": "Core p.118"})
	if roll == 20:
		u.counters["core_power"] = int(u.counters.get("core_power", 0)) + 1
	return events


## Someone failed a save against `by`.
static func failed_save(state: GameState, by: Unit, t: Unit) -> Array[Dictionary]:
	if by == null or t == null or not Effects.has(by, "open_door") or int(by.counters.get("open_door_round", -1)) == state.round_number:
		return [] as Array[Dictionary]
	by.counters["open_door_round"] = state.round_number
	var events: Array[Dictionary] = [{"type": "effect_triggered", "unit": by.id, "effect": "The Lesson of the Open Door", "target": t.id, "rule_ref": "Core p.191"}]
	events.append_array(Combat.apply_heat(state, t, 2, by.id))
	return events


## At the start of an allied character's turn: Lesson of the Held Image.
static func turn_started(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var ids: Array = state.units.keys()
	ids.sort()
	for id: String in ids:
		var o := state.unit(id)
		if o == u or o.side != u.side or not Effects.has(o, "held_image") or not Combat.is_present(o):
			continue
		if int(o.counters.get("held_image_round", -1)) == state.round_number or not Reactions.can_react(o, "held_image", state).ok:
			continue
		var targets: Array = []
		for t: Unit in state.units.values():
			if t.side != o.side and Combat.is_present(t) and t.kind != Unit.KIND_DEPLOYABLE and Attacks.tech_target_check(state, o, t, "lock_on").ok and not t.has_status("Lock On"):
				targets.append(t.id)
		if targets.is_empty():
			continue
		targets.sort()
		var auto := {"take": true, "target": targets[0]}
		var d := Reactions.offer(state, o, "held_image", {"targets": targets, "suggested": auto}, auto)
		var t := state.unit(String(d.get("target", "")))
		if not d.get("take", false) or t == null or not targets.has(t.id):
			continue
		Reactions._mark_used(o, "held_image", state)
		o.counters["held_image_round"] = state.round_number
		events.append({"type": "reaction", "unit": o.id, "reaction": "held_image", "target": t.id, "rule_ref": "Core p.191"})
		events.append_array(Combat.add_status(state, t, "Lock On", o.id))
	return events


## Structure damage taken (not destroyed): Lesson of Transubstantiation.
static func structure_lost(state: GameState, u: Unit) -> Array[Dictionary]:
	if not Effects.has(u, "transubstantiation") or u.destroyed:
		return [] as Array[Dictionary]
	u.counters["folded"] = [u.cell.x, u.cell.y, u.level]
	return [{"type": "unit_folded", "unit": u.id, "source": "The Lesson of Transubstantiation", "rule_ref": "Core p.191"}] as Array[Dictionary]


## Stress damage taken: Stasis Shielding.
static func stress_lost(state: GameState, u: Unit) -> Array[Dictionary]:
	if not Effects.has(u, "stasis_shielding"):
		return [] as Array[Dictionary]
	return Effects.activate(state, u, [{"kind": "resist", "damage": ["All"]}], "Stasis Shielding", "start_next_turn")
