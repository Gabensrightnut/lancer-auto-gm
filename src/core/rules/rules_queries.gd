class_name RulesQueries
extends RefCounted
## Read-only questions the renderer, UI and GM AI can ask while a player plans. Nothing here
## changes the GameState or rolls dice, and the answers are exactly what the rules will
## apply when the action is submitted. Results are plain Dictionaries (network-friendly).
## Run them on the host (they see the full state, including Hidden units).


## Movement arrow: the path to `cell` (optionally a height `level`), its cost, the movement
## left, and warnings (difficult/dangerous terrain, climbing, Engaged stop, provoking,
## needs a Boost, flight, table ruling). `mode` "move" or "boost". See Movement.plan().
static func preview_move(state: GameState, unit_id: String, cell: Vector2i, level: int = -1, mode: String = "move", fly: bool = false) -> Dictionary:
	var u := state.unit(unit_id)
	if u == null:
		return {"ok": false, "reason": "No such unit."}
	return Movement.plan(state, u, cell, level, mode, fly)


## Every space the unit can reach with its remaining move (or a Boost), for greying out the
## rest. {"budget", "spaces": [{"cell": [x, y], "level", "cost", "stops"}]}
static func reachable(state: GameState, unit_id: String, mode: String = "move", fly: bool = false) -> Dictionary:
	var u := state.unit(unit_id)
	if u == null:
		return {"budget": 0, "spaces": []}
	return Movement.reachable(state, u, mode, fly)


## Can `from_id` see `to_id`?
static func line_of_sight(state: GameState, from_id: String, to_id: String) -> bool:
	return Sight.unit_line_of_sight(state, state.unit(from_id), state.unit(to_id))


## For the line-of-sight line on screen, using the engine's own sight and cover checks:
## {visible, cover: "none"/"soft"/"hard", blocked_at: [x, y] or null, blocker: {kind, name} or
## {}, path_cells: [[x, y], ...], reason, rule_ref}. `to`: a unit id or a cell [x, y].
## Seeing someone never lets an attack through a wall: attacks need this same line of sight
## (except Arcing, Seeking and the like, per their tags).
static func los_detail(state: GameState, from_id: String, to: Variant) -> Dictionary:
	var a := state.unit(from_id)
	var out := {"visible": false, "cover": "none", "blocked_at": null, "blocker": {}, "path_cells": [], "reason": "", "rule_ref": Sight.REF_LOS}
	if a == null:
		return out
	var t: Unit = state.unit(String(to)) if to is String else null
	var cell: Vector2i = t.cell if t != null else (Vector2i(int(to[0]), int(to[1])) if to is Array else a.cell)
	for c in state.map.grid.line(a.cell, cell):
		out["path_cells"].append([c.x, c.y])
	var a_body := Sight.body_of(state, a)
	var t_body := Sight.body_of(state, t) if t != null else Sight.make_body(state, cell, state.map.ground_height(cell), 0.5)
	if t != null and t.has_status("Hidden") and t.side != a.side:
		out["blocker"] = {"kind": "hidden", "name": "Hidden"}
		out["reason"] = "Hidden: it can't be seen or targeted."
		out["rule_ref"] = "statuses: Hidden"
		return out
	if t != null and Zones.blocks_sight(state, a, t):
		out["blocker"] = {"kind": "zone", "name": "Blinded or a sight-blocking field"}
		out["reason"] = "Something blocks its sight (Blinded, a flash or a hardlight field)."
		return out
	var cov := Sight.unit_cover(state, a, t) if t != null else Sight.cover(state, a_body, t_body)
	out["visible"] = bool(cov.get("los", false))
	out["cover"] = String(cov.get("cover", "none"))
	out["reason"] = String(cov.get("reason", ""))
	out["rule_ref"] = String(cov.get("rule_ref", Sight.REF_LOS))
	# What's in the way: the first thing on the line from the target's center to the shooter's.
	var r := Sight._trace(state, Sight._center(state, t_body), Sight._center(state, a_body), Sight._skip_cells(a_body, t_body), Sight._voxels(Sight.wreck_bodies(state), a_body, t_body))
	if r["blocked"]:
		var bc: Vector2i = r["first_block"]
		out["blocked_at"] = [bc.x, bc.y]
		var col := state.map.column(bc)
		var kind := "terrain"
		var name := "Terrain"
		if col != null:
			for tag: Array in [["window", "window", "A wall with a window"], ["interior", "building", "A building"], ["building", "building", "A building"], [Sight.TAG_VEHICLE, "vehicle", "A parked vehicle"], ["wall", "wall", "A wall"], ["rock", "terrain", "Rock"]]:
				if col.has_tag(String(tag[0])) or (String(tag[0]) == "window" and Array(col.tags).any(func(x: String) -> bool: return x.begins_with("window_"))):
					kind = String(tag[1])
					name = String(tag[2])
					break
		for w: Unit in state.units.values():
			if w.destroyed and w.kind == Unit.KIND_MECH and state.map.grid.footprint(w.cell, w.size).has(bc):
				kind = "wreck"
				name = "A wreck"
		out["blocker"] = {"kind": kind, "name": name}
	elif r["soft"]:
		out["blocker"] = {"kind": "soft_cover", "name": "Smoke or foliage"}
	return out


## Cover the target has against a ranged attack from the attacker:
## {los, cover: "none"/"soft"/"hard", difficulty, cover_cells: [[x, y]], reason, rule_ref}.
static func cover(state: GameState, attacker_id: String, target_id: String) -> Dictionary:
	return Sight.unit_cover(state, state.unit(attacker_id), state.unit(target_id))


## Cover the unit would have at a destination, against each enemy: {enemy_id: cover dict}.
static func cover_at(state: GameState, unit_id: String, cell: Vector2i, level: int) -> Dictionary:
	return Sight.cover_at(state, state.unit(unit_id), cell, level)


## Hit-chance breakdown for an attack with a weapon (key from loadout.weapons): every
## Accuracy/Difficulty source with its label and rule, the flat bonus, the target number,
## and `hit_chance` (0..1). See Attacks.preview().
static func attack_preview(state: GameState, attacker_id: String, weapon_key: String, target_id: String, use_lock_on: bool = true) -> Dictionary:
	var a := state.unit(attacker_id)
	var made := TerrainDamage.materialize(state, {"params": {"target": target_id}})  # "terrain:x,y" targets
	var p := Attacks.preview(state, a, Weapons.find(a, weapon_key), state.unit(target_id), {"use_lock_on": use_lock_on})
	if p["ok"]:
		p["hit_chance"] = hit_chance(p["bonus"], p["accuracy"] - p["difficulty"], p["target_number"])
		if state.unit(target_id).has_status("Invisible"):
			p["hit_chance"] = float(p["hit_chance"]) * 0.5
	TerrainDamage.remove(state, made)
	return p


## Is the fight over? True when the characters taking part (not exploring elsewhere) are all on
## one side, or nobody is left. The host then sends {"type": "end_combat"}. In turn-based
## exploring (mode "explore") it's never over by itself.
static func combat_over(state: GameState) -> bool:
	if state.phase != GameState.PHASE_COMBAT or state.turn_mode == "explore":
		return false
	var sides := {}
	for u: Unit in state.units.values():
		if u.kind != Unit.KIND_DEPLOYABLE and Combat.is_present(u) and not u.counters.get("exploring", false):
			sides[u.side] = true
	return sides.size() < 2


## A destructible terrain column's section HP, Evasion and Armor for the HUD (Core p.68), or
## {} if it can't be damaged. Attack it with target "terrain:x,y" (TerrainDamage.id_for).
static func terrain_info(state: GameState, cell: Vector2i) -> Dictionary:
	var out := TerrainDamage.info(state, cell)
	if not out.is_empty():
		out["target"] = TerrainDamage.id_for(cell)
	return out


## Area attack template preview: the cells it covers, its origin, and every character it
## would hit with their own hit-chance breakdown (cover from the area's origin).
## {ok, reason, pattern, size, cells: [[x, y]], origin: [x, y, level],
##  targets: [{"id", "preview": attack_preview-style dict}]}
static func area_preview(state: GameState, attacker_id: String, weapon_key: String, aim: Vector2i, aim_level: int = -1) -> Dictionary:
	var a := state.unit(attacker_id)
	var w := Weapons.find(a, weapon_key)
	var p := Areas.plan(state, a, w, aim, aim_level)
	var origin: Variant = p.get("origin_body")
	p.erase("origin_body")
	var targets: Array = []
	if p["ok"]:
		for id: String in p["targets"]:
			var t := Attacks.preview(state, a, w, state.unit(id), {"area_origin": origin, "skip_spend": true})
			if t["ok"]:
				t["hit_chance"] = hit_chance(t["bonus"], t["accuracy"] - t["difficulty"], t["target_number"])
			targets.append({"id": id, "preview": t})
	p["targets"] = targets
	return p


## Just the cells of a template, for drawing: pattern "Blast"/"Burst"/"Cone"/"Line".
static func area_cells(state: GameState, pattern: String, size: int, user_id: String, aim: Vector2i) -> Array:
	var u := state.unit(user_id)
	var out: Array = []
	for c in Areas.template(state.map.grid, pattern, size, state.map.grid.footprint(u.cell, u.size), aim):
		if state.map.has_cell(c):
			out.append([c.x, c.y])
	return out


## Same for a tech attack (Invade).
static func tech_preview(state: GameState, attacker_id: String, target_id: String) -> Dictionary:
	var p := Attacks.tech_preview(state, state.unit(attacker_id), state.unit(target_id))
	if p["ok"]:
		p["hit_chance"] = hit_chance(p["bonus"], p["accuracy"] - p["difficulty"], p["target_number"])
	return p


## Every open question the book leaves to the table, with its readings and the current
## choice: [{id, question, options {id: text}, suggested, rule_ref, choice}].
static func rulings(state: GameState) -> Array:
	var out := Rulings.catalog()
	for r: Dictionary in out:
		r["choice"] = Rulings.choice(state, r["id"])
	return out


## Everything the unit might do now, for the action bar: basic actions, weapons, abilities
## (systems, core, traits, talents, deployables), reactions and Core Power. Each entry:
## {id, type (action to submit), params (template), name, group, available, reason, rule_ref,
##  and where relevant: cost, activation, uses_left, uses_max, frequency, used, loading
##  {has, loaded}, recharge {value, charged}, destroyed, automated, detail, policy}.
static func available_actions(state: GameState, unit_id: String) -> Array:
	var u := state.unit(unit_id)
	if u == null:
		return []
	return AbilityActions.listing(state, u)


## What the game automates for this unit and what the table handles (traits, core, systems,
## weapons): [{kind, id, name, status: automated|partial|manual, note, guidance, text}].
## Add the pilot's talents with Automation.for_talents(db, talents).
static func automation(state: GameState, unit_id: String, db: ContentDB) -> Array:
	var u := state.unit(unit_id)
	return [] if u == null else Automation.for_unit(db, u)


## The same for the builder, before a battle: frame, loadout and pilot record (with talents).
static func automation_for_build(db: ContentDB, frame_id: String, loadout: Dictionary, pilot: Dictionary) -> Array:
	return Automation.for_build(db, frame_id, loadout, pilot)


## Hostiles that could react (Overwatch) if the unit starts moving now.
static func threatened_by(state: GameState, unit_id: String) -> Array[String]:
	return Movement.threatened_by(state, state.unit(unit_id))


## Exact chance that d20 + bonus + (net Accuracy d6s, highest kept) >= target.
static func hit_chance(bonus: int, net: int, target: int) -> float:
	var outcomes := {0: 1.0}  # modifier -> probability
	if net != 0:
		outcomes = {}
		var n := absi(net)
		for high in range(1, 7):
			# P(max of n d6 == high)
			var p := pow(high / 6.0, n) - pow((high - 1) / 6.0, n)
			outcomes[high * signi(net)] = p
	var chance := 0.0
	for mod: int in outcomes:
		var need := target - bonus - mod
		var p_d20 := clampf((21 - need) / 20.0, 0.0, 1.0)
		chance += outcomes[mod] * p_d20
	return chance
