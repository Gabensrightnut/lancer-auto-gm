class_name Effects
extends RefCounted
## Data-driven effects from frame traits, core systems and NPC features. Effects are plain
## Dictionaries with a "kind" and a "label" (shown as the source in roll breakdowns); they
## live in Unit.loadout["effects"] (always on) and Unit.counters["active_effects"]
## (switched on in play, e.g. a core power, for the rest of the scene).
## Data: data/game/frame_effects.json, data/game/npc_templates.json.
##
## Kinds the engine applies (anything else is "manual": shown to players, not automated):
##   accuracy        {on: attack|ranged_attack|melee_attack|tech_attack|check|save, skill?,
##                    reaction_only?, value (+ Accuracy / - Difficulty)}
##   attack_bonus    {on: attack|ranged_attack|melee_attack, value} flat bonus to the roll
##   resist          {damage: [types or "All"], area_only?, within?}
##   immune          {status?: name, damage?: type}
##   free_action     {id, action: type or "any_quick", per: turn|round|scene}
##   heavy_frame     can't be pushed, pulled, knocked Prone or back by smaller characters
##   guardian        adjacent allied characters can use this unit as hard cover
##   status          {status, when: own_turn|always}
##   hover           can hover when it moves
##   jammed_ranged   can make ranged attacks while Jammed
##   reload_if_idle  reloads Loading weapons at end of turn if it made no attacks
##   thorns          {value, range}: attackers within range take value AP kinetic first
##   regenerate      {fraction}: regains that much of max HP at the end of its turn
##   vent_on_structure  clears all heat when it takes structure damage
##   soft_cover_plus {value}: extra Difficulty when it's in soft cover
##   maze            hostiles must stop when Engaged with it, whatever their Size
##   immobilize_shreds  Immobilize it inflicts also Shreds for the same duration
##   grapple_free    can Boost and take reactions while grappling

const REF := "data/game: effects"


static func all(u: Unit) -> Array:
	if u == null:
		return []
	return (u.loadout.get("effects", []) as Array) + (u.counters.get("active_effects", []) as Array)


static func of(u: Unit, kind: String) -> Array:
	return all(u).filter(func(e: Dictionary) -> bool: return e.get("kind", "") == kind)


static func has(u: Unit, kind: String) -> bool:
	return not of(u, kind).is_empty()


## Accuracy/Difficulty sources for a roll. `on` lists the roll types this counts as, e.g.
## ["attack", "ranged_attack"] or ["save"]. Returns sources for Dice.check.
static func accuracy_sources(u: Unit, on: Array, skill: String = "", reaction: bool = false) -> Array:
	var out: Array = []
	for e: Dictionary in of(u, "accuracy"):
		if not on.has(e.get("on", "")):
			continue
		if e.has("skill") and e["skill"] != skill:
			continue
		if e.get("reaction_only", false) and not reaction:
			continue
		var v := int(e.get("value", 1))
		var kind := "accuracy" if v > 0 else "difficulty"
		out.append({"label": e.get("label", "Effect"), "kind": kind, "type": kind, "value": absi(v), "rule_ref": e.get("rule_ref", REF)})
	return out


static func attack_bonus(u: Unit, on: Array) -> Array:
	var out: Array = []
	for e: Dictionary in of(u, "attack_bonus"):
		if on.has(e.get("on", "")):
			out.append({"label": e.get("label", "Effect"), "value": int(e.get("value", 1))})
	return out


## Does `u` resist `dtype` damage here? `area` = from a Blast/Burst/Line/Cone attack;
## `distance` = from the source (-1 unknown).
static func resists(u: Unit, dtype: String, area: bool, distance: int) -> bool:
	for e: Dictionary in of(u, "resist"):
		var types: Array = e.get("damage", ["All"])
		if not (types.has(dtype) or types.has("All")):
			continue
		if e.get("area_only", false) and not area:
			continue
		if e.has("within") and (distance < 0 or distance > int(e["within"])):
			continue
		return true
	return false


static func immune_to_status(u: Unit, status: String) -> bool:
	for e: Dictionary in of(u, "immune"):
		if e.get("status", "") == status:
			return true
	return false


static func immune_to_damage(u: Unit, dtype: String) -> bool:
	for e: Dictionary in of(u, "immune"):
		if e.get("damage", "") == dtype:
			return true
	return false


static func value(u: Unit, kind: String, key: String = "value") -> int:
	var best := 0
	for e: Dictionary in of(u, kind):
		best = maxi(best, int(e.get(key, 0)))
	return best


## A free-action grant `id` usable for `action` right now? Returns the grant or {}.
static func grant(u: Unit, id: String, action: String, is_quick: bool) -> Dictionary:
	for e: Dictionary in of(u, "free_action"):
		if e.get("id", "") != id:
			continue
		var what: String = e.get("action", "")
		if what != action and not (what == "any_quick" and is_quick):
			continue
		if _used(u, e):
			return {}
		return e
	return {}


static func _used(u: Unit, e: Dictionary) -> bool:
	match e.get("per", "scene"):
		"turn":
			return (u.turn.get("grants_used", []) as Array).has(e["id"])
		"round":
			return (u.counters.get("round_grants_used", []) as Array).has(e["id"])
	return (u.counters.get("scene_grants_used", []) as Array).has(e["id"])


static func use_grant(u: Unit, e: Dictionary) -> void:
	var where := "scene_grants_used"
	match e.get("per", "scene"):
		"turn":
			var t: Array = u.turn.get("grants_used", [])
			t.append(e["id"])
			u.turn["grants_used"] = t
			return
		"round":
			where = "round_grants_used"
	var used: Array = u.counters.get(where, [])
	used.append(e["id"])
	u.counters[where] = used


## Adds effects for the rest of the scene (e.g. a core power), with their statuses.
static func activate(state: GameState, u: Unit, effects: Array, source: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var active: Array = u.counters.get("active_effects", [])
	for e: Dictionary in effects:
		var copy := e.duplicate(true)
		copy["label"] = copy.get("label", source)
		active.append(copy)
		if copy.get("kind", "") == "status" and copy.get("when", "always") == "always":
			events.append_array(Combat.add_status(state, u, String(copy["status"]), source))
	u.counters["active_effects"] = active
	return events


## Start of the unit's turn: statuses it has "during its turn".
static func turn_started(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for e: Dictionary in of(u, "status"):
		if e.get("when", "") == "own_turn":
			events.append_array(Combat.add_status(state, u, String(e["status"]), String(e.get("label", "trait"))))
	return events


## End of the unit's turn: trait upkeep.
static func turn_ending(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for e: Dictionary in of(u, "status"):
		if e.get("when", "") == "own_turn" and u.has_status(String(e["status"])) and u.statuses[e["status"]].get("source", "") == e.get("label", "trait"):
			events.append_array(Combat.remove_status(u, String(e["status"]), "end of turn"))
	if has(u, "reload_if_idle") and not u.turn.get("attacked", false):
		for w: Dictionary in u.loadout.get("weapons", []):
			if Weapons.has_tag(w, "tg_loading"):
				Weapons.state_of(u, w)["loaded"] = true
		events.append({"type": "reloaded", "unit": u.id, "source": of(u, "reload_if_idle")[0].get("label", "")})
	for e: Dictionary in of(u, "regenerate"):
		if u.has_status("Regeneration Suppressed") or u.destroyed:
			break
		var heal := mini(int(u.max_hp * float(e.get("fraction", 0.25))), u.max_hp - u.hp)
		if heal > 0:
			u.hp += heal
			events.append({"type": "hp_changed", "unit": u.id, "hp": u.hp, "overshield": u.overshield, "source": e.get("label", "Regeneration")})
		break
	return events


## Bodies of allied Guardian characters next to `target` (it can use them as hard cover).
static func guardians(state: GameState, target: Unit) -> Array[Sight.Body]:
	var out: Array[Sight.Body] = []
	var tb := Sight.body_of(state, target)
	for o: Unit in state.units.values():
		if o == target or o.side != target.side or not Combat.is_present(o) or not has(o, "guardian"):
			continue
		var ob := Sight.body_of(state, o)
		if Sight.distance(state, tb, ob) <= 1:
			out.append(ob)
	return out
