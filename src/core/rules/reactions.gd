class_name Reactions
extends RefCounted
## Reactions, and how the engine asks a defender whether to take one.
##
## When something triggers a reaction (a hostile starts moving in your THREAT: Overwatch; you
## are hit and damage has been rolled: Brace), the rules call offer(). What happens depends
## on the unit's policy for that reaction (counters["reaction_policy"][reaction]):
## - "ask" (default for player-controlled units): the engine stops, rewinds the action to
##   where it started, and sends a `reaction_offered` event. The unit's controller answers
##   with {"type": "react", "actor": unit, "params": {"take": bool, ...}} and the engine
##   replays the action from the start with the same dice, now using that answer.
## - "auto" (default for GM units, until the GM AI decides): the offering rule's default.
## - "never", or "on_structure" for Brace (only when the hit would take the last HP).
##
## Each reaction can be used again from the start of your next turn, and only one reaction
## per turn (Core p.73). Whether NPCs Brace is the table's "npc_brace" ruling; AI seats
## answer prompts with suggested_answer().

const REF_BRACE := "actions: Brace"
const REF_OVERWATCH := "actions: Overwatch"
const POLICIES := ["ask", "auto", "never", "on_structure"]


static func policy(u: Unit, reaction: String) -> String:
	var set: Dictionary = u.counters.get("reaction_policy", {})
	if set.has(reaction):
		return set[reaction]
	if reaction == "brace" and u.counters.has("brace_policy"):
		return u.counters["brace_policy"]
	return "auto" if u.controller == "gm" else "ask"


## Asks `u` whether to take `reaction`. `auto` is the answer used under the "auto" policy.
## Returns the decision, e.g. {"take": true, "weapon": "0:0"}.
static func offer(state: GameState, u: Unit, reaction: String, context: Dictionary, auto: Dictionary) -> Dictionary:
	var run := state.reaction_run
	match policy(u, reaction):
		"never":
			return {"take": false}
		"auto", "on_structure":
			return auto
	if run.is_empty():
		return auto  # called outside RulesEngine.submit (direct rules calls in tests/tools)
	var n := int(run.get("count", 0))
	run["count"] = n + 1
	var id := "%s:%s:%d" % [reaction, u.id, n]
	var decisions: Dictionary = run.get("decisions", {})
	if decisions.has(id):
		return decisions[id]
	if (run.get("pending", {}) as Dictionary).is_empty():
		run["pending"] = {"id": id, "unit": u.id, "reaction": reaction, "context": context}
	return {"take": false}


## A sensible answer to the reaction the engine is waiting on (for AI seats and defaults):
## Overwatch with the first listed weapon, take prepared actions, Brace only if the hit would
## take the last HP. Returns the params for a "react" action, or {} if nothing is pending.
static func suggested_answer(state: GameState) -> Dictionary:
	var p := state.pending
	if p.is_empty():
		return {}
	var ctx: Dictionary = p.get("context", {})
	if ctx.has("suggested"):
		return ctx["suggested"]
	match String(p.get("reaction", "")):
		"overwatch":
			var weapons: Array = ctx.get("weapons", [])
			return {"take": not weapons.is_empty(), "weapon": weapons[0] if not weapons.is_empty() else ""}
		"brace":
			var u := state.unit(String(p.get("unit", "")))
			var dmg := 0
			for part: Dictionary in ctx.get("damage", []):
				if part.get("type", "") != "Heat":
					dmg += int(part.get("amount", 0))
			if not ctx.get("ap", false) and u != null and not u.has_status("Shredded"):
				dmg -= u.armor
			return {"take": u != null and dmg >= u.hp + u.overshield}
	return {"take": true}


static func can_react(u: Unit, reaction: String, state: GameState = null) -> RuleResult:
	if not Combat.is_present(u):
		return RuleResult.deny("Not on the field.", "")
	if state != null and String(u.counters.get("reaction_turn", "")) == _turn_key(state) \
			and int(u.counters.get("reaction_turn_count", 1)) >= maxi(1, Effects.value(u, "reactions_per_turn")):
		return RuleResult.deny("Only one reaction per turn (yours or anyone else's).", "Core p.73 Reactions")
	if Effects.has(u, "no_reactions"):
		return RuleResult.deny("No reactions until the end of your next turn.", "House rule: No Stun from a Direct Hit")
	if u.counters.has("dragging"):
		return RuleResult.deny("While dragging or lifting you can't take reactions.", Riders.REF_DRAG)
	if state != null and Movement.above_ceiling(state, u):
		return RuleResult.deny("More than 10 spaces above the battlefield you can't take reactions.", "Core p.63 Flight")
	if u.has_status("Stunned") or u.has_status("Shut Down"):
		return RuleResult.deny("Stunned mechs can't take reactions.", "statuses: Stunned")
	if u.has_status("Jammed"):
		return RuleResult.deny("Jammed characters can't take reactions.", "statuses: Jammed")
	if u.has_status("Braced"):
		return RuleResult.deny("After Bracing you can't take reactions until the end of your next turn.", REF_BRACE)
	if u.counters.has("grapple") and not Effects.has(u, "grapple_free") and not (reaction == "brace" and Effects.has(u, "armor_lock")):
		return RuleResult.deny("Grappling characters can't take reactions.", "actions: Grapple")
	if u.counters.has("prepared"):
		return RuleResult.deny("Holding a prepared action: no other reactions until it triggers.", "actions: Prepare")
	if u.has_status("Reeling"):
		return RuleResult.deny("Reeling from an ambush: no reactions until the end of its next turn.", "talents: Infiltrator")
	if Effects.has(u, "aegis"):
		return RuleResult.deny("Inside the Trueblack Aegis you can't take reactions.", "frames: Napoleon core system")
	if u.counters.has("focus"):
		return RuleResult.deny("While focusing on a Mark for Death target you can't take reactions.", "frames: Death's Head core system")
	if reaction == "brace" and u.kind == Unit.KIND_NPC:
		if state == null or Rulings.ask(state, "npc_brace") != "yes":
			return RuleResult.deny("NPCs don't Brace (table ruling).", REF_BRACE)
	var allowed := 1 + (Effects.value(u, "overwatch_extra") if reaction == "overwatch" else 0)
	if reaction == "scylla":
		allowed = 2  # SCYLLA: two special reactions
	if reaction == "turret_attack" and state != null:
		allowed = GearSystems.turret_count(state, u)  # once for each deployed turret drone
	if (u.counters.get("reactions", []) as Array).count(reaction) >= allowed:
		return RuleResult.deny("You've already used that reaction; it comes back at the start of your next turn.", "Core p.73 Reactions")
	return RuleResult.allow()


static func _turn_key(state: GameState) -> String:
	return "%d:%s" % [state.round_number, state.active_unit]


static func _mark_used(u: Unit, reaction: String, state: GameState = null) -> void:
	var used: Array = u.counters.get("reactions", [])
	used.append(reaction)
	u.counters["reactions"] = used
	if state != null:
		var key := _turn_key(state)
		u.counters["reaction_turn_count"] = (int(u.counters.get("reaction_turn_count", 0)) + 1) if u.counters.get("reaction_turn", "") == key else 1
		u.counters["reaction_turn"] = key
	Effects.reacted(u)


## BRACE: resistance to the triggering attack's damage, burn and heat (applied by the caller),
## +1 Difficulty on other attacks against you and no reactions until the end of your next
## turn, and next turn only one quick action.
static func brace(state: GameState, u: Unit, attacker: String, move_to: Variant = null) -> Array[Dictionary]:
	_mark_used(u, "brace", state)
	u.counters["brace_next_turn"] = true
	var events: Array[Dictionary] = [{"type": "reaction", "unit": u.id, "reaction": "brace", "trigger": attacker, "rule_ref": REF_BRACE}]
	if Effects.has(u, "reactive_weave"):
		# Reactive Weave: Invisible until the end of its next turn, and a move up to its Speed
		# (the brace answer's "move_to").
		events.append_array(Combat.add_status(state, u, "Invisible", "Reactive Weave", u.id))
		if move_to is Array and (move_to as Array).size() >= 2:
			var saved := u.turn
			u.turn = {"move_spent": 0}
			var plan := Movement.plan(state, u, Vector2i(int(move_to[0]), int(move_to[1])))
			u.turn = saved
			if plan["ok"]:
				var last: Array = (plan["path"] as Array).back()
				u.cell = Vector2i(last[0], last[1])
				u.level = int(last[2])
				events.append({"type": "moved", "unit": u.id, "path": plan["path"], "mode": "move", "cost": plan["cost"], "rule_ref": "systems: Reactive Weave"})
				events.append_array(Combat.after_movement(state))
	if Effects.has(u, "armor_lock"):
		# Armor-Lock Plating: grapples end; until the end of its following turn +1 Difficulty
		# against it, no failed Hull/Agility saves, Immunity to Knockback, Grapple and Prone.
		events.append_array(CloseCombat.end_grapple(state, u, "Armor-Lock Plating"))
		events.append_array(Effects.activate(state, u, [{"kind": "defense_difficulty", "value": 1}, {"kind": "auto_save", "skills": ["hull", "agility"]},
			{"kind": "immune", "status": "Prone"}, {"kind": "immovable"}, {"kind": "immune_grapple"}], "Armor-Lock Plating", "end_next_turn"))
	events.append_array(Combat.add_status(state, u, "Braced", "Brace", u.id))
	if u.has_status("Hidden"):
		events.append_array(Combat.remove_status(u, "Hidden", "took a reaction"))
	return events


## Weapons `u` could Overwatch `mover` with right now: in THREAT, not Ordnance or Superheavy.
static func overwatch_weapons(state: GameState, u: Unit, mover: Unit) -> Array[String]:
	var out: Array[String] = []
	var dist := Sight.unit_distance(state, u, mover)
	if String(mover.counters.get("feint", "")) == u.id:
		return out  # Duelist Feint: no reactions from the feinted character
	for w: Dictionary in u.loadout.get("weapons", []):
		if Weapons.threat_for(u, w) < dist or Weapons.has_tag(w, "tg_ordnance") or w.get("size", "") == "Superheavy" or Weapons.area(w) != "" or w.get("no_attack", false):
			continue
		if Attacks.preview(state, u, w, mover)["ok"]:
			out.append(String(w["key"]))
	return out


## Area weapons that could Overwatch `mover` (if the table allows it): in THREAT, not
## Ordnance or Superheavy, and the template can be aimed at the mover.
static func _area_overwatch_weapons(state: GameState, u: Unit, mover: Unit) -> Array[String]:
	var out: Array[String] = []
	var dist := Sight.range_distance(state, Sight.body_of(state, u), Sight.body_of(state, mover))
	for w: Dictionary in u.loadout.get("weapons", []):
		if Weapons.area(w) == "" or Weapons.threat_for(u, w) < dist or Weapons.has_tag(w, "tg_ordnance") or w.get("size", "") == "Superheavy" or w.get("no_attack", false):
			continue
		if Attacks.weapon_ready(u, w).ok and Areas.plan(state, u, w, mover.cell, mover.level)["ok"]:
			out.append(String(w["key"]))
	return out


## OVERWATCH: hostiles whose THREAT the mover starts a move in may Skirmish it first, as a
## reaction (actions: Overwatch; tags: Ordnance can't Overwatch). Returns events.
static func overwatch(state: GameState, mover: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if mover.turn.get("disengaged", false):
		return events  # Disengage: movement doesn't provoke reactions.
	var ids := Movement.threatened_by(state, mover)
	ids.sort()
	for id in ids:
		var h := state.unit(id)
		if not can_react(h, "overwatch", state).ok or not Combat.is_present(mover) or mover.destroyed:
			continue
		var body_h := Sight.body_of(state, h)
		var body_m := Sight.body_of(state, mover)
		if Sight.distance(state, body_h, body_m) != state.map.grid.footprint_distance(body_h.cells, body_m.cells):
			Rulings.ask(state, "distance_3d")
		var weapons := overwatch_weapons(state, h, mover)
		var area := _area_overwatch_weapons(state, h, mover)
		if not area.is_empty() and Rulings.ask(state, "overwatch_area_weapons") == "yes":
			weapons.append_array(area)
		if weapons.is_empty():
			continue
		var d := offer(state, h, "overwatch", {"mover": mover.id, "weapons": weapons}, {"take": true, "weapon": weapons[0]})
		if not d.get("take", false):
			continue
		var key := String(d.get("weapon", weapons[0]))
		if not weapons.has(key):
			key = weapons[0]
		_mark_used(h, "overwatch", state)
		events.append({"type": "reaction", "unit": h.id, "reaction": "overwatch", "trigger": mover.id, "weapon": key, "rule_ref": REF_OVERWATCH})
		var w := Weapons.find(h, key)
		if Weapons.area(w) != "":
			events.append_array(Areas.attack(state, h, w, {"aim": [mover.cell.x, mover.cell.y], "aim_level": mover.level, "reaction": true}))
		else:
			# Metalmark Flash Cloak: Invisible while moving.
			var res := Attacks.attack(state, h, w, mover, {"reaction": true, "target_invisible": Effects.has(mover, "flash_cloak")})
			events.append_array(res)
			var hit := res.any(func(x: Dictionary) -> bool: return x["type"] == "attack_rolled" and x["result"] != "miss")
			for e: Dictionary in Effects.of(h, "overwatch_hit_status"):
				if hit and Combat.is_present(mover):
					# Tortuga core: characters hit by Overwatch are Immobilized until the end of their next turn.
					events.append_array(Combat.add_status(state, mover, String(e["status"]), h.id, mover.id))
	return events


## After a voluntary move by `mover`: anyone holding a prepared action whose trigger matches
## takes it now, as a reaction (actions: Prepare).
static func prepared_triggers(state: GameState, mover: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if state.reaction_run.get("in_prepared", false) or not Combat.is_present(mover):
		return events
	var ids: Array = state.units.keys()
	ids.sort()
	for id: String in ids:
		var p := state.unit(id)
		if p == mover or not p.counters.has("prepared") or not Combat.is_present(p):
			continue
		if p.has_status("Stunned") or p.has_status("Jammed"):
			continue
		var prep: Dictionary = p.counters["prepared"]
		var trig: Dictionary = prep["trigger"]
		var who: String = trig.get("who", "any")
		if (who == "hostile" and p.side == mover.side) or (who == "ally" and p.side != mover.side):
			continue
		var reach := 1 if trig.get("event", "") == "moves_adjacent" else int(trig.get("range", 1))
		if Sight.unit_distance(state, p, mover) > reach:
			continue
		var d := offer(state, p, "prepared", {"trigger": mover.id, "action": prep["action"], "text": prep.get("text", "")}, {"take": true})
		if not d.get("take", false):
			continue
		var action: Dictionary = prep["action"]
		var params: Dictionary = (action.get("params", {}) as Dictionary).duplicate(true)
		for k: String in params:
			if params[k] is String and params[k] == "trigger":
				params[k] = mover.id
		p.counters.erase("prepared")
		_mark_used(p, "prepared", state)
		var h: TurnAction = RulesEngine.registry[action["type"]]
		var r := h.check(state, p, params)
		events.append({"type": "prepared_triggered", "unit": p.id, "trigger": mover.id, "action": action["type"], "ok": r.ok, "reason": r.reason, "rule_ref": "actions: Prepare"})
		if not r.ok:
			continue
		var running := state.reaction_run.is_empty()
		state.reaction_run["in_prepared"] = true
		events.append_array(h.apply(state, p, params))
		state.reaction_run.erase("in_prepared")
		if running:
			state.reaction_run.clear()
	return events
