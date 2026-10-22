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
##   bonus_damage    see BonusDamage (Nelson Momentum, Mourning Cloak Hunter, Tokugawa Limit
##                   Break, Death's Head Mark for Death)
##   bonus_to_burn   {weapon_damage}: in the Danger Zone, bonus damage becomes burn (Plasma Sheath)
##   damage_type_swap {from, to, when: exposed} (Tokugawa Limit Break)
##   reach_bonus     {range, threat, when?, damage_type?} (Limit Break, Tokugawa Radiance)
##   reroll_first_ranged  rerolls a missed first ranged attack each round (Death's Head Neurolink)
##   seeking_payload Launchers attack Locked On targets as if Seeking; damage can't be reduced
##   avenger_silos   {damage, range}: 1/round on a ranged crit, damage another character (Monarch)
##   average_damage_option  may deal average damage instead of rolling (Pegasus)
##   mjolnir_chambers  Raleigh Thunder God chambers (counters.chambers)
##   frequency_override {ability, count}: ability usable count/its period (Pegasus core: 3/round)
## Movement (each only because a trait/system/talent/core bonus says so, never the model):
##   ignore_difficult  ignores difficult terrain (Bulwark Mods, Kai Bioplating)
##   climb_normal      climbs at normal speed (Kai Bioplating, High-Stress Mag Clamps)
##   optional_flight   {heat: n or "size+1", land_by_turn_end?}: may count any movement as
##                     flying; heat at the end of turns it flew (Type-I Flight System,
##                     All-Theater Movement Suite, Mobility Hardsuit)
##   boost_flight      flies when it Boosts; must land at the end of that move or fall
##                     (Rapid Burst Jump Jet System)
##   boost_bonus       {value}: extra spaces when Boosting (Integrated Nerveweave)
##   teleport_moves    its standard move and Boost are teleports (Mourning Cloak core)
##   jump_plus         standard-move jumps go up to full Speed across, half Speed up (Kai)
##   after_attack_move {spaces, after: attack|skirmish}: a free move after attacking that
##                     ignores engagement and doesn't provoke (Nelson Skirmisher, Skirmisher)
##   status_if_still   {status}: at the end of a turn it didn't move, gains the status until
##                     it moves, reacts, or its next turn starts (Swallowtail Integrated Cloak)
##   afterimage        after a standard move or Boost, counts as Invisible against the next
##                     attack (Flicker Field Projector)
##   punish_movement   {damage, range}: hostiles within range that make any movement other
##                     than a standard move take that much AP explosive, 1/round each
##                     (Iskander core)
##   size_step         one Size larger, to at most 3 (Fomorian Frame)
## accuracy effects can have "while_flying": true (Ace).

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
static func accuracy_sources(u: Unit, on: Array, skill: String = "", reaction: bool = false, weapon_type: String = "") -> Array:
	var out: Array = []
	for e: Dictionary in of(u, "accuracy"):
		if not on.has(e.get("on", "")):
			continue
		if e.has("weapon_type") and e["weapon_type"] != weapon_type:
			continue
		if e.has("skill") and e["skill"] != skill:
			continue
		if e.get("reaction_only", false) and not reaction:
			continue
		if e.get("while_flying", false) and not u.flying:
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
		if e.has("beyond") and (distance < 0 or distance <= int(e["beyond"])):
			continue
		return true
	return false


## Hydra Shepherd Field: drones, deployables and objects next to a Hydra resist all damage.
static func shepherded(state: GameState, u: Unit) -> bool:
	if u.kind != Unit.KIND_DEPLOYABLE:
		return false
	for o: Unit in state.units.values():
		if o != u and Combat.is_present(o) and has(o, "shepherd_field") and Sight.unit_distance(state, o, u) <= 1:
			return true
	return false


static func immune_to_status(u: Unit, status: String) -> bool:
	for e: Dictionary in of(u, "immune"):
		if e.get("status", "") == status and (not e.get("while_overshield", false) or u.overshield > 0):
			return true
	return false


static func immune_to_damage(u: Unit, dtype: String) -> bool:
	for e: Dictionary in of(u, "immune"):
		if e.get("damage", "") == dtype or e.get("damage", "") == "All":
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
## `duration`: "scene", "start_next_turn" or "end_next_turn" (of `u`).
static func activate(state: GameState, u: Unit, effects: Array, source: String, duration: String = "scene") -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var active: Array = u.counters.get("active_effects", [])
	for e: Dictionary in effects:
		var copy := e.duplicate(true)
		copy["label"] = copy.get("label", source)
		if duration == "start_next_turn":
			copy["expires"] = {"unit": u.id, "when": "start", "count": 1}
		elif duration == "end_next_turn":
			copy["expires"] = {"unit": u.id, "when": "end", "count": 2 if state.active_unit == u.id else 1}
		active.append(copy)
		if copy.get("kind", "") == "status" and copy.get("when", "always") == "always":
			events.append_array(Combat.add_status(state, u, String(copy["status"]), source))
	u.counters["active_effects"] = active
	return events


## After `u` moved voluntarily (mode "walk" = standard move, "boost", "bonus"...).
static func moved(state: GameState, u: Unit, mode: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for e: Dictionary in of(u, "status_if_still"):
		events.append_array(_drop_still_status(u, e))
	if has(u, "afterimage") and (mode == "walk" or mode == "boost"):
		u.counters["afterimage"] = true
	if mode == "boost":
		for e: Dictionary in of(u, "bonus_damage"):
			if e.get("when", "") == "after_boost":
				u.counters["momentum"] = true  # Nelson Momentum: the next melee attack gains it
	if mode != "walk":
		events.append_array(punish_movement(state, u))
	return events


static func _drop_still_status(u: Unit, e: Dictionary) -> Array[Dictionary]:
	var s := String(e.get("status", ""))
	if u.has_status(s) and u.statuses[s].get("source", "") == e.get("label", ""):
		return Combat.remove_status(u, s, "moved or reacted")
	return [] as Array[Dictionary]


## Reacting ends "until it moves or takes a reaction" statuses (Swallowtail cloak).
static func reacted(u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for e: Dictionary in of(u, "status_if_still"):
		events.append_array(_drop_still_status(u, e))
	return events


## Iskander's Broad-Sweep Seeder: hostiles within its range that make any movement other than
## their standard move (involuntary included) take 3 AP explosive, 1/round each.
static func punish_movement(state: GameState, mover: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not Combat.is_present(mover):
		return events
	for o: Unit in state.units.values():
		if o.side == mover.side or not Combat.is_present(o):
			continue
		for e: Dictionary in of(o, "punish_movement"):
			var hit: Array = mover.counters.get("punished", [])
			var key := "%d:%s" % [state.round_number, o.id]
			if hit.has(key) or Sight.unit_distance(state, o, mover) > int(e.get("range", 50)):
				continue
			hit.append(key)
			mover.counters["punished"] = hit
			events.append({"type": "effect_triggered", "unit": o.id, "effect": e.get("label", ""), "target": mover.id})
			events.append_array(Combat.deal_damage(state, mover, [{"type": "Explosive", "amount": int(e.get("damage", 3))}], {"ap": true, "source": o.id}))
	return events


## After `attacker` attacks on its own turn: extra move it may take right away.
static func attacked(state: GameState, attacker: Unit, action: String) -> void:
	if state.active_unit != attacker.id:
		return
	var spaces := 0
	for e: Dictionary in of(attacker, "after_attack_move"):
		var after: String = e.get("after", "attack")
		if after == "attack" or after == action:
			spaces = maxi(spaces, int(e.get("spaces", 1)))
	if spaces > 0:
		attacker.turn["bonus_move"] = spaces


## Start of the unit's turn: statuses it has "during its turn".
static func turn_started(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	# Balor Scouring Swarm: characters of its choice (here: hostiles) that start their turn
	# grappled by or adjacent to it take 2 kinetic.
	for o: Unit in state.units.values():
		if o == u or o.side == u.side or not Combat.is_present(o):
			continue
		var swarm := of(o, "start_turn_damage")
		if swarm.is_empty():
			continue
		var grappled := String(u.counters.get("grapple", {}).get("with", "")) == o.id
		if grappled or Sight.unit_distance(state, o, u) <= 1:
			# The strongest version counts (Hive Frenzy: 4 instead of 2).
			var e: Dictionary = swarm[0]
			for x: Dictionary in swarm:
				if int(x.get("value", 2)) > int(e.get("value", 2)):
					e = x
			events.append({"type": "effect_triggered", "unit": o.id, "effect": e.get("label", ""), "target": u.id})
			events.append_array(Combat.deal_damage(state, u, [{"type": e.get("type", "Kinetic"), "amount": int(e.get("value", 2))}], {"source": o.id}))
	for e: Dictionary in of(u, "status_if_still"):
		events.append_array(_drop_still_status(u, e))
	for e: Dictionary in of(u, "status"):
		if e.get("when", "") == "own_turn":
			events.append_array(Combat.add_status(state, u, String(e["status"]), String(e.get("label", "trait"))))
	events.append_array(FrameSystems.turn_started(state, u))
	return events


## End of the unit's turn: trait upkeep.
static func turn_ending(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for e: Dictionary in of(u, "status"):
		if e.get("when", "") == "own_turn" and u.has_status(String(e["status"])) and u.statuses[e["status"]].get("source", "") == e.get("label", "trait"):
			events.append_array(Combat.remove_status(u, String(e["status"]), "end of turn"))
	# Count-as-flying systems: heat at the end of a turn flown that way; the Mobility Hardsuit
	# must end the turn on a surface or begin falling.
	if u.turn.get("flew_optional", false):
		for e: Dictionary in of(u, "optional_flight"):
			var heat: Variant = e.get("heat", 0)
			var amount := (GridLayout.spaces_per_side(u.size) + 1) if str(heat) == "size+1" else int(heat)
			if amount > 0:
				events.append_array(Combat.apply_heat(state, u, amount, String(e.get("label", "flight"))))
			if e.get("land_by_turn_end", false) and u.flying:
				events.append_array(Combat.begin_falling(u, "%s: must end the turn on a surface." % e.get("label", "")))
			break
	for e: Dictionary in of(u, "status_if_still"):
		if not u.turn.get("moved", false):
			events.append_array(Combat.add_status(state, u, String(e["status"]), String(e.get("label", "trait"))))
	if has(u, "mjolnir_chambers") and not u.turn.get("fired_mjolnir", false):
		# Raleigh Thunder God: two rounds chambered at the end of a turn it didn't fire (max 6).
		u.counters["chambers"] = mini(6, int(u.counters.get("chambers", 0)) + 2)
		events.append({"type": "effect_triggered", "unit": u.id, "effect": of(u, "mjolnir_chambers")[0].get("label", ""),
			"target": u.id, "chambers": u.counters["chambers"], "rule_ref": "frames: Raleigh core system"})
	events.append_array(GearSystems.impaled_turn_end(state, u))
	if has(u, "reload_if_idle") and not u.turn.get("attacked", false):
		GearSystems.reloaded(u)
		for w: Dictionary in u.loadout.get("weapons", []):
			if Weapons.has_tag(w, "tg_loading"):
				Weapons.state_of(u, w)["loaded"] = true
		events.append({"type": "reloaded", "unit": u.id, "source": of(u, "reload_if_idle")[0].get("label", "")})
	events.append_array(FrameSystems.turn_ending(state, u))
	var regen := of(u, "regenerate")
	regen.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("fraction", 0.25)) > float(b.get("fraction", 0.25)))
	for e: Dictionary in regen:  # the strongest (Hive Frenzy: 1/2 instead of 1/4)
		if u.has_status("Regeneration Suppressed") or u.destroyed:
			break
		var heal := mini(ceili(u.max_hp * float(e.get("fraction", 0.25))), u.max_hp - u.hp)  # always round up (Core p.12)
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
