class_name AISystems
extends RefCounted
## AIs (Core p.107, tags: AI). A mech with the AI tag (one AI system at most) can hand its
## controls to the AI as a protocol: the AI gets its own set of actions and reactions on the
## same turn, and doesn't benefit from the pilot's talents or other features. Control comes
## back as a protocol at the start of a later turn, if the pilot is inside. Cascade: whenever
## a mech with the AI tag makes a structure damage or overheating check, roll 1d20; on a 1
## its NHP cascades and takes over as a GM-controlled NPC until the pilot Shuts Down the mech
## (the only action left to them). COMP/CONs and UNCLE don't cascade (tags: No Cascade).
## Also the NHP systems' own actions: SEKHMET, TLALOC, ATHENA, OSIRIS, SCYLLA, NOAH.

const REF := "Core p.107 AIs"


static func has_ai(u: Unit) -> bool:
	return u.loadout.has("ai")


static func controlled(u: Unit) -> bool:
	return u.counters.get("ai_control", false)


static func cascading(u: Unit) -> bool:
	return u.counters.has("cascade")


## The AI tag from systems and mods: {"source": id, "cascade": bool}.
static func detect(db: ContentDB, u: Unit) -> void:
	var count := 0
	for s: Dictionary in u.loadout.get("systems", []):
		if Weapons.has_tag(s, "tg_ai"):
			count += 1
			if not u.loadout.has("ai"):
				u.loadout["ai"] = {"source": s["id"], "cascade": not Weapons.has_tag(s, "tg_no_cascade")}
	if count > 0:
		u.loadout["ai"]["count"] = count  # The Lesson of Shaping: a second AI keeps control
		return
	for w: Dictionary in u.loadout.get("weapons", []):
		if w.has("mod"):
			var mod := db.get_entry("mods", String(w["mod"]["id"]))
			for t: Dictionary in mod.get("tags", []):
				if t.get("id", "") == "tg_ai":
					u.loadout["ai"] = {"source": mod["id"], "cascade": not Weapons.has_tag(mod, "tg_no_cascade")}
					return


## Effects the AI can't use while it's in control: the pilot's talents and other features.
static func pilot_feature(e: Dictionary) -> bool:
	var label := String(e.get("label", ""))
	return label.begins_with("t_") or label.begins_with("cb_") or label.begins_with("pg_")


static func hand_over(state: GameState, u: Unit, label: String) -> Array[Dictionary]:
	u.counters["ai_control"] = true
	u.counters["ai_since"] = state.round_number
	# "The AI gains its own set of actions and reactions."
	u.turn = {"quick": 0, "full": false, "taken": [], "quick_tech": [], "move_spent": 0,
		"moved": false, "acted": false, "overcharged": false, "free_quick": 0}
	u.counters.erase("reactions")
	return [{"type": "ai_control", "unit": u.id, "on": true, "source": label, "rule_ref": REF}] as Array[Dictionary]


static func take_back(state: GameState, u: Unit, why: String) -> Array[Dictionary]:
	u.counters.erase("ai_control")
	u.counters.erase("ai_since")
	return [{"type": "ai_control", "unit": u.id, "on": false, "source": why, "rule_ref": REF}] as Array[Dictionary]


static func check_take_back(state: GameState, u: Unit) -> RuleResult:
	if not controlled(u):
		return RuleResult.deny("Your AI isn't in control.", REF)
	if cascading(u):
		return RuleResult.deny("A cascading NHP won't give control back: Shut Down the mech.", REF)
	if int(u.counters.get("ai_since", -1)) >= state.round_number:
		return RuleResult.deny("You can take control back at the start of a later turn.", REF)
	if u.counters.get("empty", false):
		return RuleResult.deny("You must be inside the mech to take control back.", REF)
	return RuleResult.allow()


## Called on structure damage and overheating checks.
static func cascade_check(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not has_ai(u) or not u.loadout["ai"].get("cascade", true) or cascading(u) or u.destroyed:
		return events
	var roll := state.dice.die(20)
	events.append({"type": "cascade_check", "unit": u.id, "roll": roll, "cascade": roll == 1, "rule_ref": REF})
	if roll != 1:
		return events
	var cascaded := int(u.counters.get("ais_cascaded", 0)) + 1
	u.counters["ais_cascaded"] = cascaded
	if cascaded < int(u.loadout["ai"].get("count", 1)):
		# The Lesson of Shaping: the other AI keeps the cascading one from taking control.
		events.append({"type": "effect_triggered", "unit": u.id, "effect": "The Lesson of Shaping", "target": u.id, "rule_ref": "Core p.191"})
		return events
	u.counters["cascade"] = {"controller": u.controller}
	u.controller = "gm"
	u.counters["ai_control"] = true
	events.append_array(Combat.add_status(state, u, "Cascading", "NHP"))
	return events


## Shutting Down stabilizes a cascading NHP.
static func shut_down(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not cascading(u):
		return events
	u.controller = String(u.counters["cascade"].get("controller", u.controller))
	u.counters.erase("cascade")
	u.counters.erase("ais_cascaded")
	u.counters.erase("ai_control")
	events.append_array(Combat.remove_status(u, "Cascading", "Shut Down"))
	events.append({"type": "ai_control", "unit": u.id, "on": false, "source": "cascade stabilized", "rule_ref": REF})
	return events


static func action_allowed(u: Unit, type: String) -> RuleResult:
	if cascading(u) and not type in ["shut_down", "end_turn", "start_turn", "react", "set_reaction_policy", "set_ruling"]:
		return RuleResult.deny("The NHP is cascading and controls the mech: the pilot can only Shut Down.", REF)
	return RuleResult.allow()


# --- NHP systems ----------------------------------------------------------------------

## SEKHMET Protocol: hand over to SEKHMET; melee crits +1d6, a free melee Skirmish 1/round,
## no ranged attacks. (The NHP's own targeting is the controller's job.)
static func sekhmet(state: GameState, u: Unit) -> Array[Dictionary]:
	var events := hand_over(state, u, "SEKHMET")
	events.append_array(Effects.activate(state, u, [{"kind": "bonus_damage", "value": "1d6", "on": "melee", "crit_only": true},
		{"kind": "free_action", "id": "sekhmet", "action": "skirmish", "per": "round"}, {"kind": "melee_only"}], "SEKHMET Protocol", "scene"))
	return events


static func sekhmet_off(state: GameState, u: Unit) -> Array[Dictionary]:
	var events := take_back(state, u, "Take Back Control")
	events.append_array(GearSystems.remove_effects(state, u, "SEKHMET Protocol"))
	events.append_array(Combat.add_status(state, u, "Stunned", "SEKHMET", "", u.id))
	return events


## TLALOC: after a missed attack, one reroll against a new target within Range.
static func tlaloc_retarget(state: GameState, u: Unit, w: Dictionary, missed: Unit, hit_ids: Array) -> Unit:
	if not Effects.has(u, "tlaloc"):
		return null
	var best: Unit = null
	var best_d := 999
	for o: Unit in state.units.values():
		if o == missed or o.side == u.side or not Combat.is_present(o) or o.kind == Unit.KIND_DEPLOYABLE or hit_ids.has(o.id):
			continue
		var p := Attacks.preview(state, u, w, o, {"skip_spend": true})
		if p["ok"] and int(p["distance"]) < best_d:
			best = o
			best_d = int(p["distance"])
	return best


## ATHENA Simulacrum: a blast 3 area within range 50 (no line of sight needed).
static func simulacrum(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for z: Dictionary in Zones.of_kind(state, "athena"):
		if z.get("owner", "") == u.id:
			events.append_array(Zones.remove(state, String(z["id"]), "new area"))
	var aim: Vector2i = TurnAction.cell_param(params, "aim")
	events.append_array(Zones.add(state, {"kind": "athena", "owner": u.id, "label": "ATHENA Simulacrum", "center": [aim.x, aim.y],
		"cells": Zones.cells_around(state, [aim] as Array[Vector2i], 3), "rule_ref": "systems: ATHENA-Class NHP"}))
	events.append_array(athena_reveal(state))
	return events


static func athena_reveal(state: GameState) -> Array[Dictionary]:
	for z: Dictionary in Zones.of_kind(state, "athena"):
		var owner := state.unit(String(z.get("owner", "")))
		if owner == null:
			continue
		for o: Unit in state.units.values():
			if o.side != owner.side and Combat.is_present(o) and Zones.contains(state, z, o):
				ViewFilter.reveal_in_state(state, owner.side, o.id)
	return [] as Array[Dictionary]


## Hostiles inside an ATHENA model: no cover, no Hiding or Invisible against its side.
static func exposed_to(state: GameState, attacker: Unit, target: Unit) -> bool:
	for z: Dictionary in Zones.of_kind(state, "athena"):
		var owner := state.unit(String(z.get("owner", "")))
		if owner != null and attacker.side == owner.side and target.side != owner.side and Zones.contains(state, z, target):
			return true
	return false


## OSIRIS Hurl Into the Duat: the gates (progress persists until a rest or Full Repair).
static func duat(state: GameState, u: Unit, t: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var gate := int(u.counters.get("duat_gate", 0)) % 4 + 1
	u.counters["duat_gate"] = gate
	events.append({"type": "effect_triggered", "unit": u.id, "effect": "Gate %d" % gate, "target": t.id, "rule_ref": "systems: OSIRIS-Class NHP"})
	match gate:
		1:
			t.counters["duat_move"] = u.id  # its next standard move is yours to make
			events.append({"type": "manual_effect", "unit": u.id, "source": "First Gate", "text": "You control the target's standard move on its next turn.",
				"guidance": Automation.MANUAL_GUIDANCE})
		2:
			events.append_array(Combat.add_status(state, t, "Slowed", u.id, t.id))
			events.append_array(Combat.add_status(state, t, "Impaired", u.id, t.id))
		3:
			events.append_array(Combat.add_status(state, t, "Stunned", u.id, t.id))
		4:
			t.counters["converted"] = {"side": t.side, "controller": t.controller, "by": u.id, "turns": 2 if state.active_unit == t.id else 1}
			t.side = u.side
			t.controller = u.controller
			events.append({"type": "allegiance_changed", "unit": t.id, "side": t.side, "rule_ref": "systems: OSIRIS-Class NHP"})
	return events


static func revert(state: GameState, t: Unit, why: String) -> Array[Dictionary]:
	var c: Dictionary = t.counters.get("converted", {})
	if c.is_empty():
		return [] as Array[Dictionary]
	t.side = String(c["side"])
	t.controller = String(c["controller"])
	t.counters.erase("converted")
	return [{"type": "allegiance_changed", "unit": t.id, "side": t.side, "reason": why, "rule_ref": "systems: OSIRIS-Class NHP"}] as Array[Dictionary]


## The Fourth Gate ends early if its new allies harm it, attack it or force a save.
static func harmed_by(state: GameState, t: Unit, source: Unit) -> Array[Dictionary]:
	if t.counters.has("converted") and source != null and source.side == t.side:
		return revert(state, t, "harmed by its new allies")
	return [] as Array[Dictionary]


static func turn_ending(state: GameState, u: Unit) -> Array[Dictionary]:
	var c: Dictionary = u.counters.get("converted", {})
	if c.is_empty():
		return [] as Array[Dictionary]
	c["turns"] = int(c["turns"]) - 1
	if int(c["turns"]) <= 0:
		return revert(state, u, "end of its next turn")
	return [] as Array[Dictionary]


## SCYLLA: until the start of your next turn, 2 reactions to Skirmish (half damage) a hostile
## that attacks you or an ally within range 3.
static func scylla(state: GameState, attacker: Unit, target: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for o: Unit in state.units.values():
		if not Effects.has(o, "scylla") or o.side == attacker.side or o.side != target.side or not Combat.is_present(o):
			continue
		if o != target and Sight.unit_distance(state, o, target) > 3:
			continue
		if not Reactions.can_react(o, "scylla", state).ok:
			continue
		var weapon := ""
		for w: Dictionary in o.loadout.get("weapons", []):
			if Weapons.area(w) == "" and Attacks.preview(state, o, w, attacker, {"reaction": true})["ok"]:
				weapon = String(w["key"])
				break
		if weapon == "":
			continue
		var auto := {"take": true, "weapon": weapon}
		var d := Reactions.offer(state, o, "scylla", {"attacker": attacker.id, "weapons": [weapon], "suggested": auto}, auto)
		if not d.get("take", false):
			continue
		Reactions._mark_used(o, "scylla", state)
		events.append({"type": "reaction", "unit": o.id, "reaction": "scylla", "trigger": attacker.id, "rule_ref": "systems: SCYLLA-Class NHP"})
		events.append_array(Attacks.attack(state, o, Weapons.find(o, String(d.get("weapon", weapon))), attacker, {"reaction": true, "half_damage": true}))
		if not Combat.is_present(attacker):
			break
	return events


## NOAH Diluvian Ark: before a ranged attack on you or an adjacent ally: 1 heat and 1d6; on 4+
## another heat and the attack misses. Returns {events, miss}.
static func ark(state: GameState, attacker: Unit, target: Unit, w: Dictionary) -> Dictionary:
	var out := {"events": [] as Array[Dictionary], "miss": false}
	if Weapons.is_melee(w) or target.has_status("Invisible"):
		return out
	var noah := ark_owner(state, target)
	if noah == null or not Reactions.can_react(noah, "diluvian_ark", state).ok:
		return out
	var auto := {"take": true}
	var d := Reactions.offer(state, noah, "diluvian_ark", {"attacker": attacker.id, "target": target.id, "suggested": auto}, auto)
	if not d.get("take", false):
		return out
	Reactions._mark_used(noah, "diluvian_ark", state)
	out["events"].append_array(Combat.apply_heat(state, noah, 1, "Diluvian Ark"))
	var roll := state.dice.die(6)
	out["events"].append({"type": "reaction", "unit": noah.id, "reaction": "diluvian_ark", "target": target.id, "roll": roll, "missed": roll >= 4, "rule_ref": "systems: NOAH-Class NHP"})
	if roll >= 4:
		out["events"].append_array(Combat.apply_heat(state, noah, 1, "Diluvian Ark"))
		out["miss"] = true
	return out


static func ark_owner(state: GameState, target: Unit) -> Unit:
	for o: Unit in state.units.values():
		if Effects.has(o, "noah") and o.side == target.side and Combat.is_present(o) and Sight.unit_distance(state, o, target) <= (0 if o == target else 1):
			return o
	return null


## A ranged attack that fails to hit a NOAH or an ally next to it: 4 kinetic to the attacker.
static func ark_backlash(state: GameState, attacker: Unit, target: Unit, w: Dictionary) -> Array[Dictionary]:
	if Weapons.is_melee(w) or ark_owner(state, target) == null or not Combat.is_present(attacker):
		return [] as Array[Dictionary]
	var events: Array[Dictionary] = [{"type": "effect_triggered", "unit": ark_owner(state, target).id, "effect": "Diluvian Ark", "target": attacker.id, "rule_ref": "systems: NOAH-Class NHP"}]
	events.append_array(Combat.deal_damage(state, attacker, [{"type": "Kinetic", "amount": 4}], {"source": ark_owner(state, target).id}))
	return events
