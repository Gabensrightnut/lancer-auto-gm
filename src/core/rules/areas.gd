class_name Areas
extends RefCounted
## Area attacks: Blast, Burst, Cone, Line (glossary entries of the same names; tags.json).
## Templates are built from GridLayout calls only, so they work on hex and square grids.
##
## Book rules used: one attack roll per character in the area, damage rolled once; Blast is
## centered on a point within RANGE and line of sight, with cover and line of sight from its
## center; Burst is centered on the user (who isn't affected), cover and line of sight from
## the user; Cone starts 1 space wide and is X wide at its far end; Line is X spaces long.
## Hidden characters can still be hit by area attacks (actions: Hide).
## PROVISIONAL (docs/RULES_TODO.md "Area templates"): Line and Cone start from the user's
## footprint space nearest the aim point and take cover/line of sight from the user; Cone
## width grows evenly from 1 to X; templates are flat and catch characters whose footprint
## is in them and whose height gap to the origin is at most X; characters with no line of
## sight from the origin aren't hit (unless Arcing/Seeking); Line/Cone "Range" variants
## (template drawn from a point in range) aren't supported yet.

const REF := "glossary: Blast, Burst, Cone, Line"


## The template's cells. `origin_cells` is the user's footprint (Burst, Cone, Line);
## `aim` is the blast center or the direction to point a Cone/Line at.
static func template(grid: GridLayout, pattern: String, size: int, origin_cells: Array[Vector2i], aim: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	match pattern:
		"Blast":
			out = grid.cells_within(aim, size)
		"Burst":
			var seen := {}
			for c in origin_cells:
				for n in grid.cells_within(c, size):
					if not seen.has(n):
						seen[n] = true
						out.append(n)
		"Line":
			var o := _nearest(grid, origin_cells, aim)
			var d := grid.distance(o, aim)
			if d == 0:
				return out
			var far := o + (aim - o) * ceili(float(size) / d + 1)
			var line := grid.line(o, far)
			for i in range(1, mini(size + 1, line.size())):
				if not origin_cells.has(line[i]):
					out.append(line[i])
		"Cone":
			var o := _nearest(grid, origin_cells, aim)
			var ow := grid.to_world(o)
			var dir := grid.to_world(aim) - ow
			dir.y = 0
			if dir.length() < 0.001:
				return out
			dir = dir.normalized()
			for c in grid.cells_within(o, size):
				if origin_cells.has(c):
					continue
				var v := grid.to_world(c) - ow
				v.y = 0
				var along := v.dot(dir) / GridLayout.SPACE
				if along < 0.5 or along > size + 0.01:
					continue
				var perp := (v - dir * along * GridLayout.SPACE).length() / GridLayout.SPACE
				var half := 0.5
				if size > 1:
					half = 0.5 + (size / 2.0 - 0.5) * clampf((along - 1.0) / (size - 1), 0.0, 1.0)
				if perp <= half + 0.01:
					out.append(c)
	return out


static func _nearest(grid: GridLayout, cells: Array[Vector2i], aim: Vector2i) -> Vector2i:
	var best := cells[0]
	for c in cells:
		if grid.distance(c, aim) < grid.distance(best, aim):
			best = c
	return best


## Everything about an area attack before it's rolled. Never changes the state.
## Returns {ok, reason, rule_ref, pattern, size, cells: [[x, y]], origin: [x, y, level],
##  targets: [unit ids], origin_body (Sight.Body, host-side only)}.
## `from`: for Line/Cone weapons that list a Range, the origin point within that Range and
## line of sight (Core p.64); Burst weapons with a Range are centered on `aim`.
static func plan(state: GameState, attacker: Unit, w: Dictionary, aim: Variant, aim_level: int = -1, from: Variant = null) -> Dictionary:
	var out := {"ok": false, "reason": "", "rule_ref": REF, "pattern": Weapons.area(w), "size": 0,
		"cells": [], "origin": [], "targets": []}
	var pattern: String = out["pattern"]
	if pattern == "":
		out["reason"] = "Not an area weapon."
		return out
	var size := Weapons.range_value(w, pattern)
	out["size"] = size
	var grid := state.map.grid
	var me := Sight.body_of(state, attacker)
	var ignores_los := Weapons.has_tag(w, "tg_arcing") or Weapons.has_tag(w, "tg_seeking")
	var origin_body: Sight.Body
	var aim_cell: Vector2i = attacker.cell
	if aim is Vector2i:
		aim_cell = aim
	elif pattern != "Burst":
		out["reason"] = "Choose where to aim (params.aim = [x, y])."
		return out
	var listed_range := Weapons.range_for(attacker, w)
	var origin_cells: Array[Vector2i] = me.cells
	if pattern != "Blast" and listed_range > 0:
		# "The attack's origin point can be drawn from a point within the range specified and
		# line of sight" (Core p.64).
		var point: Variant = aim_cell if pattern == "Burst" else from
		if point is Vector2i:
			var plv := state.map.ground_height(point)
			var pbody := Sight.make_body(state, point, plv, 0.5)
			if Sight.distance(state, me, pbody) > listed_range:
				out["reason"] = "The origin point must be within Range %d." % listed_range
				out["rule_ref"] = "Core p.64 Range and Patterns"
				return out
			if not ignores_los and not Sight.line_of_sight(state, me, pbody):
				out["reason"] = "No line of sight to the origin point."
				out["rule_ref"] = "Core p.64 Range and Patterns"
				return out
			origin_cells = [point] as Array[Vector2i]
			origin_body = pbody
			out["origin"] = [point.x, point.y, plv]
	if pattern == "Blast":
		if not state.map.has_cell(aim_cell):
			out["reason"] = "Aim at a space on the map."
			return out
		var lv := aim_level if aim_level >= 0 else state.map.ground_height(aim_cell)
		origin_body = Sight.make_body(state, aim_cell, lv, 0.5)
		var reach := Weapons.range_for(attacker, w)
		if Sight.distance(state, me, origin_body) > reach:
			out["reason"] = "The blast center must be within Range %d." % reach
			out["rule_ref"] = "glossary: Blast"
			return out
		if not ignores_los and not Sight.line_of_sight(state, me, origin_body):
			out["reason"] = "No line of sight to the blast center."
			out["rule_ref"] = "glossary: Blast"
			return out
		out["origin"] = [aim_cell.x, aim_cell.y, lv]
	elif origin_body == null:
		origin_body = me
		out["origin"] = [attacker.cell.x, attacker.cell.y, attacker.level]
	var cells := template(grid, pattern, size, origin_cells, aim_cell)
	var cell_set := {}
	for c in cells:
		if state.map.has_cell(c):
			cell_set[c] = true
			(out["cells"] as Array).append([c.x, c.y])
	var ids: Array = []
	for u: Unit in state.units.values():
		if not Combat.is_present(u) or u.kind == Unit.KIND_DEPLOYABLE:
			continue
		if u == attacker:
			continue  # the user isn't affected by their own Burst; Line/Cone start beside them
		var body := Sight.body_of(state, u)
		var inside := false
		for c in body.cells:
			inside = inside or cell_set.has(c)
		if not inside:
			continue
		var vertical := Sight.distance(state, origin_body, body) if pattern == "Blast" or pattern == "Burst" else _vertical_gap(origin_body, body)
		if pattern == "Blast" or pattern == "Burst":
			if vertical > size:
				continue
		elif vertical > size:
			continue
		if not ignores_los and not Sight.line_of_sight(state, origin_body, body):
			continue
		ids.append(u.id)
	ids.sort()
	out["targets"] = ids
	out["origin_body"] = origin_body
	out["ok"] = true
	return out


static func _vertical_gap(a: Sight.Body, b: Sight.Body) -> int:
	return maxi(0, maxi(b.level - (a.level + a.height - 1), a.level - (b.level + b.height - 1)))


## Rolls the attack against everyone in the area. Damage is rolled once and shared.
static func attack(state: GameState, attacker: Unit, w: Dictionary, params: Dictionary) -> Array[Dictionary]:
	var p := plan(state, attacker, w, TurnAction.cell_param(params, "aim"), int(params.get("aim_level", -1)), TurnAction.cell_param(params, "from"))
	var events: Array[Dictionary] = []
	if not p["ok"]:
		events.append({"type": "attack_skipped", "attacker": attacker.id, "weapon": w.get("key", ""), "reason": p["reason"], "rule_ref": p["rule_ref"]})
		return events
	events.append({"type": "area_attack", "attacker": attacker.id, "weapon": w.get("key", ""), "weapon_name": w.get("name", ""),
		"pattern": p["pattern"], "size": p["size"], "cells": p["cells"], "origin": p["origin"], "targets": p["targets"], "rule_ref": REF})
	FrameSystems.before_area(attacker, w)
	if not params.get("skip_spend", false):
		events.append_array(Attacks._spend_weapon(state, attacker, w))
	if String(w.get("id", "")) == "mw_gravity_gun":
		events.append_array(GearSystems.gravity_gun(state, attacker, w, p))
		attacker.turn["attacked"] = true
		return events
	var shared: Dictionary = params.get("_shared", {})
	var origin: Array = p["origin"]
	for id: String in p["targets"]:
		var target := state.unit(id)
		if target == null or target.destroyed:
			continue
		if WeaponRules.rules(w).get("spare_allies_cover", false) and target.side == attacker.side:
			# Veil Rifle: allies in the area get soft cover until the end of their next turn instead.
			events.append_array(Effects.activate(state, target, [{"kind": "soft_cover_aura", "self_only": true}], String(w.get("name", "")), "end_next_turn"))
			continue
		var opts := params.duplicate()
		opts["area_origin"] = p["origin_body"]
		opts["skip_spend"] = true
		opts["shared_damage"] = shared
		opts["knockback_from"] = Vector2i(origin[0], origin[1])
		opts["area"] = true
		opts["area_targets"] = (p["targets"] as Array).size()
		events.append_array(Attacks.attack(state, attacker, w, target, opts))
	events.append_array(FrameSystems.after_area(state, attacker, w, events))
	events.append_array(TerrainDamage.after_area(state, attacker, w, p["cells"]))
	events.append_array(GearSystems.area_left_behind(state, attacker, w, p["cells"], params))
	return events
