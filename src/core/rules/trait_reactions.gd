class_name TraitReactions
extends RefCounted
## Reactions and checks from frame traits and core systems that happen around an attack.
## Each is asked through Reactions.offer (players are prompted; "auto" takes it), counts as
## the unit's one reaction this turn and its 1/round use (Core p.73), and is refused while it
## can't react (Stunned, Jammed, Braced...).
##
##   basilisk       Gorgon core: hostiles save (Systems) before attacking the Gorgon or its
##                  allies within range 3, or are Stunned; once per scene per Gorgon. Not a
##                  reaction.
##   warp_shield    Saladin: +1 Difficulty on an attack against it or an ally within Sensors,
##                  before the roll.
##   defensive_pulse  Saladin core: its Tachyon Shield target gains Resistance to all damage
##                  from the attack (the reroll on a miss is left to the table).
##   mag_parry      Black Witch: an attack that would deal kinetic damage to it or an
##                  adjacent ally: 1d6, on 5+ it misses (not if the target is Invisible).
##   reactive_code  Goblin: when hit by a tech attack, any Quick Tech option against the
##                  attacker.
##   tactical_simulation  Swallowtail core: an ally in line of sight takes damage from a
##                  character in line of sight: 1d6, on 4+ Resistance to that damage and a
##                  teleport of up to 3; otherwise a teleport of up to 6.

const KINDS := ["warp_shield", "defensive_pulse", "mag_parry", "reactive_code", "tactical_simulation"]


static func _sorted(state: GameState) -> Array[Unit]:
	var out: Array[Unit] = []
	var ids: Array = state.units.keys()
	ids.sort()
	for id: String in ids:
		out.append(state.unit(id))
	return out


static func _label(u: Unit, kind: String) -> String:
	var e := Effects.of(u, kind)
	return String(e[0].get("label", kind)) if not e.is_empty() else kind


static func _take(state: GameState, u: Unit, kind: String, context: Dictionary, auto: Dictionary) -> Dictionary:
	if not Effects.has(u, kind) or not Reactions.can_react(u, kind, state).ok:
		return {"take": false}
	context["suggested"] = auto
	var d := Reactions.offer(state, u, kind, context, auto)
	if d.get("take", false):
		Reactions._mark_used(u, kind, state)
	return d


## Before an attack roll (melee, ranged or tech). Returns {"events", "cancel" (the attack
## doesn't happen), "sources" (extra Difficulty for Dice.check), "resist_all"}.
static func before_attack(state: GameState, attacker: Unit, target: Unit) -> Dictionary:
	var out := {"events": [] as Array[Dictionary], "cancel": false, "sources": [], "resist_all": false}
	for g: Unit in _sorted(state):
		if g.side == attacker.side or not Combat.is_present(g) or not Effects.has(g, "basilisk"):
			continue
		if not (target == g or (target.side == g.side and Sight.unit_distance(state, g, target) <= int(Effects.of(g, "basilisk")[0].get("range", 3)))):
			continue
		var once: Array = attacker.counters.get("basilisk_stunned", [])
		if once.has(g.id):
			continue
		var save := Combat.skill_check(state, attacker, "systems", "Save vs %s" % _label(g, "basilisk"), g.save_target, 0, 0, [], true)
		out["events"].append({"type": "skill_check", "unit": attacker.id, "check": save, "source": g.id, "rule_ref": "frames: Gorgon core system"})
		if save["success"]:
			continue
		once.append(g.id)
		attacker.counters["basilisk_stunned"] = once
		out["events"].append_array(Combat.add_status(state, attacker, "Stunned", g.id, attacker.id))
		if Rulings.ask(state, "basilisk_failed_save") == "no_attack":
			out["cancel"] = true
			out["events"].append({"type": "attack_cancelled", "attacker": attacker.id, "target": target.id,
				"reason": "Failed the save against the Basilisk: Stunned before attacking.", "rule_ref": "frames: Gorgon core system"})
			return out
	for sal: Unit in _sorted(state):
		if sal.side != target.side or not Combat.is_present(sal):
			continue
		if sal != target and Sight.unit_distance(state, sal, target) > sal.sensors:
			continue
		var d := _take(state, sal, "warp_shield", {"attacker": attacker.id, "target": target.id}, {"take": true})
		if d.get("take", false):
			out["events"].append({"type": "reaction", "unit": sal.id, "reaction": "warp_shield", "trigger": attacker.id, "target": target.id, "rule_ref": "frames: Saladin, Warp Shield"})
			out["sources"].append({"label": _label(sal, "warp_shield"), "kind": "difficulty", "type": "difficulty", "value": 1, "rule_ref": "frames: Saladin, Warp Shield"})
			break
	for sal: Unit in _sorted(state):
		if String(sal.counters.get("tachyon_target", "")) != target.id or not Combat.is_present(sal):
			continue
		var d := _take(state, sal, "defensive_pulse", {"attacker": attacker.id, "target": target.id}, {"take": true})
		if d.get("take", false):
			out["resist_all"] = true
			out["events"].append({"type": "reaction", "unit": sal.id, "reaction": "defensive_pulse", "trigger": attacker.id, "target": target.id,
				"note": "If the attack misses, the Saladin may force a reroll against another target: the table applies that.", "rule_ref": "frames: Saladin core system"})
			break
	return out


## After a melee or ranged attack hits, before damage: Mag Parry. Returns {"events", "missed"}.
static func parry(state: GameState, attacker: Unit, w: Dictionary, target: Unit) -> Dictionary:
	var out := {"events": [] as Array[Dictionary], "missed": false}
	if target.has_status("Invisible") or not Weapons.damage_types(attacker, w).has("Kinetic"):
		return out
	for bw: Unit in _sorted(state):
		if bw.side != target.side or not Combat.is_present(bw) or (bw != target and Sight.unit_distance(state, bw, target) > 1):
			continue
		var d := _take(state, bw, "mag_parry", {"attacker": attacker.id, "target": target.id}, {"take": true})
		if not d.get("take", false):
			continue
		var roll := state.dice.die(6)
		out["missed"] = roll >= 5
		out["events"].append({"type": "reaction", "unit": bw.id, "reaction": "mag_parry", "trigger": attacker.id, "target": target.id,
			"roll": roll, "missed": roll >= 5, "rule_ref": "frames: Black Witch, Mag Parry"})
		return out
	return out


## After a tech attack hits `target`: Goblin Reactive Code.
static func tech_hit(state: GameState, attacker: Unit, target: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not Effects.has(target, "reactive_code") or not Combat.is_present(attacker):
		return events
	var options: Array = []
	for t: String in ["invade", "lock_on", "scan"]:
		var h: TechActions.QuickTech = RulesEngine.registry.get(t)
		if h != null and h.check_tech(state, target, attacker).ok:
			options.append(t)
	if options.is_empty():
		return events
	var d := _take(state, target, "reactive_code", {"attacker": attacker.id, "options": options}, {"take": true, "action": options[0]})
	if not d.get("take", false):
		return events
	var pick := String(d.get("action", options[0]))
	if not options.has(pick):
		pick = options[0]
	events.append({"type": "reaction", "unit": target.id, "reaction": "reactive_code", "trigger": attacker.id, "action": pick, "rule_ref": "frames: Goblin, Reactive Code"})
	var handler: TechActions.QuickTech = RulesEngine.registry[pick]
	events.append_array(handler.apply(state, target, {"target": attacker.id}))
	return events


## A character is about to take damage from `attacker`: Swallowtail Tactical Simulation.
## Returns {"events", "resist_all", "after" (events to apply after the damage: the teleport)}.
static func before_damage(state: GameState, attacker: Unit, target: Unit) -> Dictionary:
	var out := {"events": [] as Array[Dictionary], "resist_all": false, "teleport": {}}
	for sw: Unit in _sorted(state):
		if sw == target or sw.side != target.side or not Combat.is_present(sw) or not Combat.is_present(attacker):
			continue
		if not Sight.unit_line_of_sight(state, sw, target) or not Sight.unit_line_of_sight(state, sw, attacker):
			continue
		var d := _take(state, sw, "tactical_simulation", {"attacker": attacker.id, "target": target.id}, {"take": true})
		if not d.get("take", false):
			continue
		var roll := state.dice.die(6)
		out["resist_all"] = roll >= 4
		out["events"].append({"type": "reaction", "unit": sw.id, "reaction": "tactical_simulation", "trigger": attacker.id, "target": target.id,
			"roll": roll, "resist": roll >= 4, "rule_ref": "frames: Swallowtail core system"})
		var to: Variant = TurnAction.cell_param(d, "to")
		if to != null:
			out["teleport"] = {"to": to, "reach": 3 if roll >= 4 else 6}
		return out
	return out


static func teleport(state: GameState, u: Unit, t: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if t.is_empty() or not Combat.is_present(u):
		return events
	var plan := Movement.plan_teleport(state, u, t["to"], -1, Movement.MODE_MOVE, int(t["reach"]))
	if not plan["ok"]:
		events.append({"type": "movement_cancelled", "unit": u.id, "reason": plan["reason"]})
		return events
	var last: Array = (plan["path"] as Array).back()
	u.cell = Vector2i(last[0], last[1])
	u.level = int(last[2])
	events.append({"type": "moved", "unit": u.id, "path": plan["path"], "mode": "teleport", "cost": 0, "rule_ref": "frames: Swallowtail core system"})
	events.append_array(Combat.after_movement(state))
	return events
