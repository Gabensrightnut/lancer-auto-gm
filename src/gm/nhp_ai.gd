class_name NhpAi
extends RefCounted
## Units an AI drives by its own written rules instead of their player (the director plays
## them, after asking the pilot's seat the one thing the rules leave to the pilot):
##
## - Cascading NHP (Core p.107): the mech is the GM's until the pilot Shuts Down. At the start
##   of its turn the pilot's seat is asked: Shut Down, or let it act (then the GM's tactics play
##   it). PROVISIONAL (docs/RULES_TODO.md "Cascade timing"): the book doesn't say when the pilot
##   may Shut Down; we offer it at the start of each of the mech's turns.
## - SEKHMET Protocol (systems: SEKHMET-Class NHP): the NHP "uses all available actions and
##   movement to move toward the closest visible character, allied or hostile, and attacks them
##   with melee attacks"; with nobody in Threat it moves as directly as possible toward the next
##   closest; never ranged attacks. The pilot may take back control as a protocol (Stunned).
## - COMP/CON (systems: COMP/CON-Class Assistant Unit): no initiative of its own; it follows the
##   pilot's basic command (attack this enemy, defend this area, protect someone), or defends
##   itself. The pilot gives a new command at the start of their turn (or takes back control).
## - Fourth Gate (systems: OSIRIS-Class NHP): an allied NPC on its new side until the end of its
##   next turn: the GM's tactics play it for that side.

const COMPCON := "ms_comp_con_class_assistant_unit"
const SEKHMET := "ms_sekhmet_class_nhp"
const REF_SEKHMET := "systems: SEKHMET-Class NHP"
const REF_COMPCON := "systems: COMP/CON-Class Assistant Unit"


## "cascade", "sekhmet", "compcon", "fourth_gate" or "" (the player plays it as usual).
static func kind(u: Unit) -> String:
	if u == null:
		return ""
	if AISystems.cascading(u):
		return "cascade"
	if u.counters.has("converted"):
		return "fourth_gate"
	if AISystems.controlled(u):
		match str(u.loadout.get("ai", {}).get("source", "")):
			SEKHMET:
				return "sekhmet"
			COMPCON:
				return "compcon"
	return ""


static func auto(u: Unit) -> bool:
	return kind(u) != ""


## The seat whose pilot is in the mech (for a cascade, the seat it had before).
static func pilot_seat(u: Unit) -> String:
	if AISystems.cascading(u):
		return str(u.counters["cascade"].get("controller", u.controller))
	return u.controller


## What the pilot's seat may still send for an AI-driven unit.
static func pilot_may(state: GameState, u: Unit, action: Dictionary) -> bool:
	var type := str(action.get("type", ""))
	if type in ["start_turn", "react", "set_reaction_policy", "nhp_answer"]:
		return true
	match kind(u):
		"cascade":
			return type == "shut_down"
		"sekhmet":
			return type == "overcharge" or (type == "activate" and str(action.get("params", {}).get("ability", "")) == _take_back_key(u))
		"compcon":
			return type == "ai_control" and bool(action.get("params", {}).get("take_back", false))
	return false


## The question for the pilot's seat at the start of the unit's turn:
## {kind, unit, seat, text, options: [{label, action, tip}], default: action} or {}.
static func question(state: GameState, u: Unit) -> Dictionary:
	var k := kind(u)
	if k == "" or k == "fourth_gate":
		return {}
	var name := u.name if u.name != "" else u.id
	var let_it := {"type": "nhp_answer", "actor": u.id, "params": {}}
	var q := {"kind": k, "unit": u.id, "seat": pilot_seat(u), "options": []}
	match k:
		"cascade":
			q["text"] = "Your NHP has cascaded and controls %s. Shut Down to stop it: the mech is Stunned until you Boot Up, and its heat is cleared (Core p.107). Or let it act this turn: the GM plays it." % name
			q["options"] = [{"label": "Shut Down", "action": {"type": "shut_down", "actor": u.id, "params": {}}, "tip": "The only action left to you while it cascades."},
				{"label": "Let it act", "action": let_it, "tip": "The cascading NHP takes this turn as the GM's."}]
			q["default"] = q["options"][0]["action"]
		"sekhmet":
			q["text"] = "SEKHMET controls %s: it charges the closest visible character, friend or foe, with melee attacks." % name
			var tb := _take_back_key(u)
			if tb != "" and AISystems.check_take_back(state, u).ok:
				q["options"].append({"label": "Take back control", "action": {"type": "activate", "actor": u.id, "params": {"ability": tb}},
					"tip": "A protocol: you're Stunned until the start of your next turn."})
			q["options"].append({"label": "Let SEKHMET act", "action": let_it, "tip": REF_SEKHMET})
			q["default"] = let_it
		"compcon":
			q["text"] = "Your COMP/CON controls %s and needs a command: it follows basic orders, or defends itself." % name
			q["options"] = compcon_orders(state, u)
			if AISystems.check_take_back(state, u).ok:
				q["options"].append({"label": "Take back control", "action": {"type": "ai_control", "actor": u.id, "params": {"take_back": true}}, "tip": "A protocol at the start of your turn."})
			q["default"] = q["options"][0]["action"]
	return q


## Basic commands for a COMP/CON: defend itself, hold this area, protect an ally, attack an enemy.
static func compcon_orders(state: GameState, u: Unit) -> Array:
	var out: Array = []
	var cmd := func(label: String, order: Dictionary, tip: String) -> void:
		out.append({"label": label, "action": {"type": "nhp_answer", "actor": u.id, "params": {"order": order}}, "tip": tip})
	cmd.call("Defend yourself", {"stance": "defensive"}, "It stays safe and fights back.")
	cmd.call("Hold this area", {"stance": "hold"}, "It stays where it is and fights from there.")
	var others: Array = state.units.values().filter(func(o: Unit) -> bool:
		return o != u and Combat.is_present(o) and o.kind != Unit.KIND_DEPLOYABLE and not (o.side != u.side and o.has_status("Hidden")))
	others.sort_custom(func(a: Unit, b: Unit) -> bool: return state.map.grid.distance(u.cell, a.cell) < state.map.grid.distance(u.cell, b.cell))
	var allies := others.filter(func(o: Unit) -> bool: return o.side == u.side).slice(0, 2)
	var foes := others.filter(func(o: Unit) -> bool: return o.side != u.side).slice(0, 3)
	for a: Unit in allies:
		cmd.call("Protect %s" % (a.name if a.name != "" else a.id), {"stance": "defensive", "follow": a.id}, "It stays close to them.")
	for e: Unit in foes:
		cmd.call("Attack %s" % (e.name if e.name != "" else e.id), {"stance": "aggressive", "focus": e.id}, "It goes after this enemy.")
	return out


static func _take_back_key(u: Unit) -> String:
	for a: Dictionary in u.loadout.get("abilities", []):
		if str(a.get("name", "")) == "Take Back Control":
			return str(a.get("key", ""))
	return ""


# --- SEKHMET's turn ---------------------------------------------------------------------

## SEKHMET's whole turn by its text: toward the closest visible character (any side), melee
## attacks only, using the free melee Skirmish too; with nobody in Threat, Boost toward them.
## Plans on the side's knowledge copy (what it can see). {steps, log}
static func plan_sekhmet(know: AiKnowledge, unit_id: String) -> Dictionary:
	var s := know.state
	var u := s.unit(unit_id)
	var who := u.name if u.name != "" else u.id
	if u.has_status("Stunned") or u.has_status("Shut Down"):
		return {"steps": [], "log": "%s can't act." % who}
	var melee: Array = (u.loadout.get("weapons", []) as Array).filter(func(w: Dictionary) -> bool: return Weapons.is_melee(w))
	var target := _closest_character(s, u)
	if target == null:
		return {"steps": [], "log": "SEKHMET finds no one to charge."}
	var tname := target.name if target.name != "" else target.id
	var steps: Array = []
	var reach := 1
	for w: Dictionary in melee:
		reach = maxi(reach, Weapons.threat(w))
	var home := u.cell
	var home_level := u.level
	var best := _toward(s, u, target, reach, Movement.MODE_MOVE)
	if best["cell"] != u.cell:
		steps.append({"type": "move", "actor": u.id, "params": {"to": [best["cell"].x, best["cell"].y], "level": best["level"]}})
		u.cell = best["cell"]
		u.level = best["level"]
	var attacks := 0
	if not melee.is_empty() and s.map.grid.distance(u.cell, target.cell) <= reach:
		var w: Dictionary = melee[0]
		steps.append({"type": "skirmish", "actor": u.id, "params": {"weapon": w["key"], "target": target.id}})
		steps.append({"type": "skirmish", "actor": u.id, "params": {"weapon": w["key"], "target": target.id, "free_via": "sekhmet"}})
		attacks = 2
	elif TacticsAi._can_boost(u):
		var b := _toward(s, u, target, reach, Movement.MODE_BOOST)
		if b["cell"] != u.cell:
			steps.append({"type": "boost", "actor": u.id, "params": {"to": [b["cell"].x, b["cell"].y], "level": b["level"]}})
			u.cell = b["cell"]
			u.level = b["level"]
			if not melee.is_empty() and s.map.grid.distance(u.cell, target.cell) <= reach:
				steps.append({"type": "skirmish", "actor": u.id, "params": {"weapon": melee[0]["key"], "target": target.id, "free_via": "sekhmet"}})
				attacks = 1
	u.cell = home
	u.level = home_level
	var ally := " (an ally!)" if target.side == u.side else ""
	return {"steps": steps, "log": "SEKHMET drives %s at %s%s%s." % [who, tname, ally, ", melee attacks" if attacks > 0 else ", closing in"]}


## The closest visible character, allied or hostile (not itself, not deployables).
static func _closest_character(s: GameState, u: Unit) -> Unit:
	var best: Unit = null
	var best_d := 99999
	var ids := s.units.keys()
	ids.sort()
	for id: String in ids:
		var o: Unit = s.units[id]
		if o == u or not Combat.is_present(o) or o.kind == Unit.KIND_DEPLOYABLE or o.has_status("Hidden") or o.has_status("Invisible"):
			continue
		var d := s.map.grid.distance(u.cell, o.cell)
		if d < best_d:
			best_d = d
			best = o
	return best


## The reachable space that gets closest to `t` (inside `reach` if possible).
static func _toward(s: GameState, u: Unit, t: Unit, reach: int, mode: String) -> Dictionary:
	var best := {"cell": u.cell, "level": u.level, "d": s.map.grid.distance(u.cell, t.cell)}
	if best["d"] <= reach or (mode == Movement.MODE_MOVE and not TacticsAi._can_move(u)):
		return best
	for sp: Dictionary in RulesQueries.reachable(s, u.id, mode)["spaces"]:
		if sp.get("ruling", false):
			continue
		var c := Vector2i(int(sp["cell"][0]), int(sp["cell"][1]))
		var d := s.map.grid.distance(c, t.cell)
		if d < int(best["d"]):
			best = {"cell": c, "level": int(sp["level"]), "d": d}
	return best
