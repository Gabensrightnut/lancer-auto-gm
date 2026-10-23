class_name Zones
extends RefCounted
## Areas that frame systems leave on the field, kept in state.zones as plain Dictionaries:
## {id, kind, owner, label, cells: [[x, y]], center: [x, y], expires: {unit, when, count},
##  phase, blocked, entered: {unit id: round}, rule_ref}.
##   mag_field   Black Witch core: difficult terrain; ranged kinetic/explosive attacks can't
##               enter or leave it (each one is recorded); metal characters that start their
##               turn in it or first enter it in a round save (Hull) or are pulled toward the
##               center and Immobilized; when it ends, the stopped attacks resume toward the
##               center: an attack on everyone inside at +1 per blocked attack (max +6) for 1d6
##               kinetic per blocked attack (max 6d6).
##   smoke_cloud Genghis core: phase "smoke" (until the start of its next turn) everyone inside
##               counts as Invisible except to the Genghis, and others take 2 burn and 2 heat
##               when they start their turn in it or first enter it in a round; then phase
##               "cover" (until the start of its following turn) soft cover the Genghis ignores.
##   hologram    Dusk Wing core: left where each of its movements starts; hostiles that start
##               their turn in it, move through it or move adjacent to it set it off (Agility
##               save or 1d6 energy, half on a success).

const REF_FIELD := "frames: Black Witch core system"
const REF_CLOUD := "frames: Genghis core system"
const REF_HOLO := "frames: Dusk Wing core system"


static func add(state: GameState, z: Dictionary) -> Array[Dictionary]:
	var n := int(state.zones.size())
	var id := "zone_%s_%d_%d" % [z.get("owner", ""), state.round_number, n]
	while state.zones.any(func(x: Dictionary) -> bool: return x["id"] == id):
		n += 1
		id = "zone_%s_%d_%d" % [z.get("owner", ""), state.round_number, n]
	z["id"] = id
	if not z.has("entered"):
		z["entered"] = {}
	state.zones.append(z)
	return [{"type": "zone_created", "zone": z.duplicate(true), "rule_ref": z.get("rule_ref", "")}] as Array[Dictionary]


static func remove(state: GameState, id: String, why: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for z: Dictionary in state.zones:
		if z["id"] == id and z.get("kind", "") in ["cloak", "interdiction", "hardlight"]:
			var o := state.unit(String(z.get("owner", "")))
			var src := {"cloak": "LB/OC Cloaking Field", "interdiction": "Interdiction Field", "hardlight": "Hardlight Defense System"}[z["kind"]] as String
			var st := "Immobilized" if z["kind"] == "hardlight" else "Slowed"
			if o != null and o.has_status(st) and o.statuses[st].get("source", "") == src:
				events.append_array(Combat.remove_status(o, st, "field ended"))
	state.zones = state.zones.filter(func(z: Dictionary) -> bool: return z["id"] != id)
	events.append({"type": "zone_removed", "id": id, "reason": why})
	return events


static func _has_cell(z: Dictionary, c: Vector2i) -> bool:
	for x: Array in z.get("cells", []):
		if int(x[0]) == c.x and int(x[1]) == c.y:
			return true
	return false


## Zones with an "anchor" (a drone or mech) and "radius" follow it (Hive Drone, Swarm Body).
static func _cell_in(state: GameState, z: Dictionary, c: Vector2i) -> bool:
	if z.has("anchor"):
		var a := state.unit(String(z["anchor"]))
		if a == null or not Combat.is_present(a):
			return false
		for f in state.map.grid.footprint(a.cell, a.size):
			if state.map.grid.distance(f, c) <= int(z.get("radius", 1)):
				return true
		return false
	return _has_cell(z, c)


static func contains(state: GameState, z: Dictionary, u: Unit) -> bool:
	for c in state.map.grid.footprint(u.cell, u.size):
		if _cell_in(state, z, c):
			return true
	return false


static func of_kind(state: GameState, kind: String) -> Array:
	return state.zones.filter(func(z: Dictionary) -> bool: return z.get("kind", "") == kind)


## Cells within `radius` of any of `around` (a Burst or Blast), on the map.
static func cells_around(state: GameState, around: Array[Vector2i], radius: int) -> Array:
	var seen := {}
	var out: Array = []
	for a in around:
		for c: Vector2i in state.map.grid.cells_within(a, radius):
			if state.map.has_cell(c) and not seen.has(c):
				seen[c] = true
				out.append([c.x, c.y])
	return out


static func difficult_at(state: GameState, c: Vector2i) -> bool:
	for z: Dictionary in state.zones:
		if z.get("kind", "") in ["mag_field", "sealant", "caltrops"] and _has_cell(z, c):
			return true
	return false


## Portable Bunker: a character completely inside has hard cover against attacks from outside.
static func bunker_protects(state: GameState, target: Unit, attacker: Unit) -> bool:
	for z: Dictionary in of_kind(state, "bunker"):
		if z.get("phase", "") != "up":
			continue
		var inside := true
		for c in state.map.grid.footprint(target.cell, target.size):
			inside = inside and _has_cell(z, c)
		if inside and (attacker == null or not contains(state, z, attacker)):
			return true
	return false


## A zone from a deployed system (Caltrop Launcher, Portable Bunker).
static func from_deployable(state: GameState, owner: Unit, d: Dictionary, cell: Vector2i) -> Array[Dictionary]:
	var spec: Dictionary = d["zone"]
	var cells: Array = []
	if spec.get("kind", "") == "bunker":
		for c in state.map.grid.footprint(cell, float(spec.get("size", 4))):
			cells.append([c.x, c.y])
	else:
		cells = cells_around(state, [cell] as Array[Vector2i], int(spec.get("size", 1)))
	var z := {"kind": spec["kind"], "owner": owner.id, "label": String(d.get("name", "")), "center": [cell.x, cell.y], "cells": cells,
		"rule_ref": "systems: " + String(d.get("name", ""))}
	if spec.get("kind", "") == "bunker":
		z["phase"] = "folded"  # unfolds at the start of the owner's next turn
		z["unfold"] = {"unit": owner.id}
	return add(state, z)


# --- Attacks --------------------------------------------------------------------------

## A Mag Field that stops this ranged attack (kinetic or explosive), or {}.
static func blocking_field(state: GameState, attacker: Unit, target: Unit, w: Dictionary, kind: String) -> Dictionary:
	if kind != Attacks.KIND_RANGED:
		return {}
	var types := Weapons.damage_types(attacker, w)
	if not (types.has("Kinetic") or types.has("Explosive")):
		return {}
	for z: Dictionary in of_kind(state, "mag_field"):
		var a_in := contains(state, z, attacker)
		var t_in := contains(state, z, target)
		if a_in != t_in:
			return z
		if not a_in and not t_in:
			for c: Vector2i in state.map.grid.line(attacker.cell, target.cell):
				if _has_cell(z, c):
					return z
	return {}


## Genghis smoke: characters inside count as Invisible to everyone but the Genghis.
static func hidden_by_smoke(state: GameState, target: Unit, attacker: Unit) -> bool:
	for z: Dictionary in of_kind(state, "smoke_cloud"):
		if z.get("phase", "") == "smoke" and z.get("owner", "") != attacker.id and contains(state, z, target):
			return true
	return false


## Soft cover from a cloud (the Genghis ignores its own), smoke or an allied hive swarm.
static func soft_cover(state: GameState, target: Unit, attacker: Unit) -> bool:
	if not wall_field_between(state, attacker, target).is_empty():
		return true
	for z: Dictionary in of_kind(state, "hive"):
		var o := state.unit(String(z.get("owner", "")))
		if o != null and o.side == target.side and contains(state, z, target):
			return true
	for z: Dictionary in of_kind(state, "smoke"):
		if contains(state, z, target):
			return true
	for z: Dictionary in of_kind(state, "smoke_cloud"):
		if z.get("phase", "") == "cover" and (attacker == null or z.get("owner", "") != attacker.id) and contains(state, z, target):
			return true
	return false


# --- Movement and turns ---------------------------------------------------------------

## After `mover` moved along `path` ([[x, y, level], ...]).
static func check_path(state: GameState, mover: Unit, path: Array) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if path.size() < 2 or not Combat.is_present(mover) or mover.kind == Unit.KIND_DEPLOYABLE:
		return events
	for z: Dictionary in state.zones.duplicate():
		match String(z.get("kind", "")):
			"mag_field", "smoke_cloud", "caltrops", "hive", "swarm_body", "tempest", "interdiction":
				var entered := false
				for i in range(1, path.size()):
					var c := Vector2i(int(path[i][0]), int(path[i][1]))
					for f in state.map.grid.footprint(c, mover.size):
						entered = entered or _cell_in(state, z, f)
				if entered:
					events.append_array(_enter(state, z, mover))
			"hardlight":
				events.append_array(hardlight_crossing(state, mover, path))
			"flames":
				for i in range(1, path.size()):
					var c := Vector2i(int(path[i][0]), int(path[i][1]))
					if state.map.grid.footprint(c, mover.size).any(func(f: Vector2i) -> bool: return _has_cell(z, f)):
						events.append_array(GearSystems.flames(state, z, mover, false))
						break
			"pcp":
				for i in range(1, path.size()):
					var c := Vector2i(int(path[i][0]), int(path[i][1]))
					if state.map.grid.footprint(c, mover.size).any(func(f: Vector2i) -> bool: return _has_cell(z, f)):
						events.append_array(GearSystems.pcp_trigger(state, z, mover))
						break
			"assassin":
				for i in range(1, path.size()):
					var c := Vector2i(int(path[i][0]), int(path[i][1]))
					if state.map.grid.footprint(c, mover.size).any(func(f: Vector2i) -> bool: return _has_cell(z, f)):
						events.append_array(GearSystems.area_denial(state, z, mover))
						break
			"emblem":
				# H0R_OS Dimensional Emblems: passing through one: 2 heat, and it's gone.
				for i in range(1, path.size()):
					var c := Vector2i(int(path[i][0]), int(path[i][1]))
					if state.map.grid.footprint(c, mover.size).any(func(f: Vector2i) -> bool: return _has_cell(z, f)):
						events.append_array(remove(state, String(z["id"]), "passed through"))
						events.append({"type": "zone_triggered", "zone": z["id"], "unit": mover.id, "rule_ref": "systems: H0R_OS System Upgrade III"})
						events.append_array(Combat.apply_heat(state, mover, 2, String(z.get("owner", ""))))
						break
			"javelin":
				for i in range(1, path.size()):
					if int(path[i][0]) == int(z["center"][0]) and int(path[i][1]) == int(z["center"][1]):
						events.append_array(remove(state, String(z["id"]), "triggered"))
						events.append({"type": "zone_triggered", "zone": z["id"], "unit": mover.id, "rule_ref": z.get("rule_ref", "")})
						events.append_array(Combat.deal_damage(state, mover, [{"type": "Kinetic", "amount": 3}], {"source": String(z.get("owner", ""))}))
						break
			"hologram":
				if mover.side == _owner_side(state, z):
					continue
				for i in range(path.size()):
					var c := Vector2i(int(path[i][0]), int(path[i][1]))
					if _near(state, z, c, mover.size, 1):
						events.append_array(_detonate(state, z, [mover.id]))
						break
	return events


static func _owner_side(state: GameState, z: Dictionary) -> String:
	var o := state.unit(String(z.get("owner", "")))
	return o.side if o != null else ""


static func _near(state: GameState, z: Dictionary, c: Vector2i, size: float, reach: int) -> bool:
	for f in state.map.grid.footprint(c, size):
		for x: Array in z.get("cells", []):
			if state.map.grid.distance(f, Vector2i(int(x[0]), int(x[1]))) <= reach:
				return true
	return false


## A character starts its turn or first enters a zone this round.
static func _enter(state: GameState, z: Dictionary, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var entered: Dictionary = z.get("entered", {})
	if int(entered.get(u.id, -1)) == state.round_number:
		return events
	entered[u.id] = state.round_number
	z["entered"] = entered
	var owner := state.unit(String(z.get("owner", "")))
	match String(z.get("kind", "")):
		"mag_field":
			if u.kind != Unit.KIND_MECH and u.kind != Unit.KIND_NPC:
				return events  # only characters made at least partly of metal
			var save := Combat.skill_check(state, u, "hull", "Save vs Mag Field", owner.save_target if owner else 10, 0, 0, [], true)
			events.append({"type": "skill_check", "unit": u.id, "check": save, "source": z["id"], "rule_ref": REF_FIELD})
			if save["success"]:
				return events
			var center := Vector2i(int(z["center"][0]), int(z["center"][1]))
			events.append_array(Attacks.pull_to(state, u, Sight.make_body(state, center, state.map.ground_height(center), 0.5), 0))
			events.append_array(Combat.add_status(state, u, "Immobilized", String(z["id"])))
		"caltrops":
			events.append_array(_caltrops(state, z, u))
		"hive", "swarm_body", "tempest", "interdiction":
			events.append_array(_horus_zone(state, z, u, owner))
		"smoke_cloud":
			if z.get("phase", "") != "smoke" or u.id == z.get("owner", ""):
				return events
			events.append({"type": "zone_triggered", "zone": z["id"], "unit": u.id, "rule_ref": REF_CLOUD})
			events.append_array(Combat.deal_damage(state, u, [{"type": "Burn", "amount": 2}], {"source": String(z.get("owner", ""))}))
			events.append_array(Combat.apply_heat(state, u, 2, String(z.get("owner", ""))))
	return events


## HORUS areas a character starts its turn in or enters (first time in a round).
static func _horus_zone(state: GameState, z: Dictionary, u: Unit, owner: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if owner == null or u.kind == Unit.KIND_DEPLOYABLE:
		return events
	var hostile := u.side != owner.side
	var ref := String(z.get("rule_ref", ""))
	match String(z["kind"]):
		"hive":
			# Greywash swarm: hostiles take 1 AP kinetic; several hive drones don't stack.
			if not hostile or int(u.counters.get("hive_round", -1)) == state.round_number:
				return events
			u.counters["hive_round"] = state.round_number
			events.append({"type": "zone_triggered", "zone": z["id"], "unit": u.id, "rule_ref": ref})
			events.append_array(Combat.deal_damage(state, u, [{"type": "Kinetic", "amount": 1}], {"ap": true, "source": owner.id}))
		"swarm_body":
			if not hostile or state.active_unit != u.id:
				return events  # on their own turn
			if z.get("at", []) != [owner.cell.x, owner.cell.y, owner.level]:
				return remove(state, String(z["id"]), "the swarm's owner moved")
			var save := Combat.skill_check(state, u, "systems", "Save vs Swarm Body", owner.save_target, 0, 0, [], true)
			events.append({"type": "skill_check", "unit": u.id, "check": save, "rule_ref": ref})
			if not save["success"]:
				events.append_array(Combat.deal_damage(state, u, [{"type": "Kinetic", "amount": mini(9, 3 * (1 + int(z.get("still", 0))))}], {"source": owner.id}))
		"tempest":
			var drone := state.unit(String(z["anchor"]))
			var save := Combat.skill_check(state, u, "hull", "Save vs Tempest Drone", owner.save_target, 0, 0, GearSystems.prone_save_sources(u), true)
			events.append({"type": "skill_check", "unit": u.id, "check": save, "rule_ref": ref})
			if not save["success"]:
				events.append_array(Combat.deal_damage(state, u, [{"type": "Energy", "amount": 4}], {"source": owner.id}))
				if Combat.is_present(u) and drone != null:
					events.append_array(Attacks.knock_back(state, u, drone.cell, 3, drone))
		"interdiction":
			if not hostile:
				return events
			var save := Combat.skill_check(state, u, "systems", "Save vs Interdiction Field", owner.save_target, 0, 0, [], true)
			events.append({"type": "skill_check", "unit": u.id, "check": save, "rule_ref": ref})
			if not save["success"]:
				events.append_array(Combat.add_status(state, u, "Slowed", owner.id, u.id))
	return events


## Caltrops: mechs take 1d3 AP explosive entering for the first time in a round or ending
## their turn inside.
static func _caltrops(state: GameState, z: Dictionary, u: Unit) -> Array[Dictionary]:
	if u.kind != Unit.KIND_MECH and u.kind != Unit.KIND_NPC:
		return [] as Array[Dictionary]
	var roll := state.dice.roll("1d3")
	var events: Array[Dictionary] = [{"type": "zone_triggered", "zone": z["id"], "unit": u.id, "rule_ref": z.get("rule_ref", "")}]
	events.append_array(Combat.deal_damage(state, u, [{"type": "Explosive", "amount": int(roll["total"])}], {"ap": true, "source": String(z.get("owner", ""))}))
	return events


static func turn_started(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = hardlight_turn_start(state, u)
	for z: Dictionary in of_kind(state, "flames"):
		if Combat.is_present(u) and u.kind != Unit.KIND_DEPLOYABLE and contains(state, z, u):
			events.append_array(GearSystems.flames(state, z, u, true))  # Plasma Thrower: starting a turn in the flames
	for z: Dictionary in of_kind(state, "bunker"):
		if z.get("phase", "") == "folded" and String(z.get("unfold", {}).get("unit", "")) == u.id:
			z["phase"] = "up"
			events.append({"type": "zone_changed", "zone": z.duplicate(true), "rule_ref": z.get("rule_ref", "")})
	events.append_array(_tick(state, u, "start"))
	if not Combat.is_present(u) or u.kind == Unit.KIND_DEPLOYABLE:
		return events
	for z: Dictionary in state.zones.duplicate():
		if not contains(state, z, u):
			continue
		if z.get("kind", "") == "hologram":
			if u.side != _owner_side(state, z):
				events.append_array(_detonate(state, z, [u.id]))
		else:
			events.append_array(_enter(state, z, u))
	return events


static func turn_ended(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for z: Dictionary in of_kind(state, "pcp"):
		if Combat.is_present(u) and contains(state, z, u):
			events.append_array(GearSystems.pcp_trigger(state, z, u))
	for z: Dictionary in of_kind(state, "athena"):
		var o := state.unit(String(z.get("owner", "")))
		if o != null and o.side != u.side and Combat.is_present(u) and contains(state, z, u):
			# ATHENA: hostiles that end their turn inside are Locked On and lose Invisible/Hidden.
			events.append_array(Combat.add_status(state, u, "Lock On", o.id))
			for st in ["Invisible", "Hidden"]:
				events.append_array(Combat.remove_status(u, st, "ATHENA"))
	AISystems.athena_reveal(state)
	for z: Dictionary in of_kind(state, "swarm_body"):
		if z.get("owner", "") == u.id:
			if z.get("at", []) == [u.cell.x, u.cell.y, u.level]:
				z["still"] = mini(2, int(z.get("still", -1)) + 1)  # +3 damage per turn stationary, up to 9
			else:
				events.append_array(remove(state, String(z["id"]), "the swarm's owner moved"))
	for z: Dictionary in of_kind(state, "caltrops"):
		if Combat.is_present(u) and contains(state, z, u):
			events.append_array(_caltrops(state, z, u))
	events.append_array(_tick(state, u, "end"))
	return events


static func _tick(state: GameState, u: Unit, when: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for z: Dictionary in state.zones.duplicate():
		var exp: Dictionary = z.get("expires", {})
		if exp.is_empty() or exp.get("unit", "") != u.id or exp.get("when", "") != when:
			continue
		exp["count"] = int(exp.get("count", 1)) - 1
		if int(exp["count"]) > 0:
			continue
		events.append_array(_expire(state, z))
	return events


static func _expire(state: GameState, z: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	match String(z.get("kind", "")):
		"smoke_cloud":
			if z.get("phase", "") == "smoke":
				# The smoke settles: soft cover until the start of the Genghis's following turn.
				z["phase"] = "cover"
				z["expires"] = {"unit": z["owner"], "when": "start", "count": 1}
				events.append({"type": "zone_changed", "zone": z.duplicate(true), "rule_ref": REF_CLOUD})
				return events
		"mag_field":
			for u: Unit in state.units.values():
				if u.has_status("Immobilized") and String(u.statuses["Immobilized"].get("source", "")) == z["id"]:
					events.append_array(Combat.remove_status(u, "Immobilized", "Mag Field ended"))
			events.append_array(_resume_attacks(state, z))
	events.append_array(remove(state, String(z["id"]), "ended"))
	return events


## Mag Field ends: blocked attacks resume toward the center and hit everyone inside.
static func _resume_attacks(state: GameState, z: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var n := mini(6, int(z.get("blocked", 0)))
	if n <= 0:
		return events
	var dmg := {}
	for u: Unit in state.units.values().duplicate():
		if not Combat.is_present(u) or u.kind == Unit.KIND_DEPLOYABLE or not contains(state, z, u):
			continue
		var check := state.dice.check(n, 0, 0, u.evasion, [])
		check["bonus_sources"] = [{"label": "Blocked attacks", "value": n}]
		check["target_label"] = "Evasion"
		events.append({"type": "attack_rolled", "attacker": String(z.get("owner", "")), "target": u.id, "weapon": "", "weapon_name": "Mag Field",
			"kind": "ranged", "check": check, "result": "hit" if check["success"] else "miss", "cover": "none", "cover_cells": [],
			"invisible_miss": false, "lock_on_consumed": false, "rule_ref": REF_FIELD})
		if not check["success"]:
			continue
		if dmg.is_empty():
			dmg = state.dice.roll("%dd6" % n)
		events.append_array(Combat.deal_damage(state, u, [{"type": "Kinetic", "amount": int(dmg["total"])}], {"source": String(z.get("owner", ""))}))
	return events


# --- Holograms ------------------------------------------------------------------------

## Dusk Wing Hall of Mirrors: a hologram where a movement on its own turn starts.
static func leave_hologram(state: GameState, u: Unit, from: Vector2i, from_level: int) -> Array[Dictionary]:
	if not Effects.has(u, "hall_of_mirrors") or state.active_unit != u.id or u.counters.get("no_holograms", false):
		return [] as Array[Dictionary]
	var cells: Array = []
	for c in state.map.grid.footprint(from, u.size):
		cells.append([c.x, c.y])
	return add(state, {"kind": "hologram", "owner": u.id, "label": "Hologram", "cells": cells, "center": [from.x, from.y],
		"level": from_level, "size": u.size, "rule_ref": REF_HOLO})


static func _detonate(state: GameState, z: Dictionary, ids: Array) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not state.zones.has(z):
		return events
	events.append_array(remove(state, String(z["id"]), "detonated"))
	var owner := state.unit(String(z.get("owner", "")))
	var op := {"op": "save_damage", "save": "agility", "damage": "1d6", "type": "Energy", "half": true, "label": "Hologram"}
	if owner != null:
		events.append_array(AbilityActions.apply_target_ops(state, owner, [op], ids))
	return events


## Hologram Teleport: to a hologram within 50; then every hologram explodes (burst 1).
static func check_hologram_teleport(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
	var to: Variant = TurnAction.cell_param(params, "to")
	for z: Dictionary in of_kind(state, "hologram"):
		if z.get("owner", "") == u.id and to != null and int(z["center"][0]) == to.x and int(z["center"][1]) == to.y:
			var plan := Movement.plan_teleport(state, u, to, -1, Movement.MODE_MOVE, 50)
			return RuleResult.allow() if plan["ok"] else RuleResult.deny(plan["reason"], plan["rule_ref"])
	return RuleResult.deny("Choose one of your holograms (params.to).", REF_HOLO)


static func hologram_teleport(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var to: Vector2i = TurnAction.cell_param(params, "to")
	var plan := Movement.plan_teleport(state, u, to, -1, Movement.MODE_MOVE, 50)
	var last: Array = (plan["path"] as Array).back()
	u.cell = Vector2i(last[0], last[1])
	u.level = int(last[2])
	events.append({"type": "moved", "unit": u.id, "path": plan["path"], "mode": "teleport", "cost": 0, "rule_ref": REF_HOLO})
	u.counters["no_holograms"] = true
	var everyone := Rulings.ask(state, "hologram_blast_targets") == "everyone_else"
	for z: Dictionary in of_kind(state, "hologram"):
		if z.get("owner", "") != u.id:
			continue
		var ids: Array = []
		for o: Unit in state.units.values():
			if o == u or not Combat.is_present(o) or o.kind == Unit.KIND_DEPLOYABLE or (o.side == u.side and not everyone):
				continue
			if _near(state, z, o.cell, o.size, 1):
				ids.append(o.id)
		ids.sort()
		events.append_array(_detonate(state, z, ids))
	events.append_array(Combat.after_movement(state))
	return events


# --- Creating zones from core systems -------------------------------------------------

## core "zone" spec: {kind, size, adjacent?}. Black Witch: blast 3 with a space next to it
## (params.aim = center). Genghis makes its cloud when it next overheats (FrameSystems).
static func check_core_zone(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
	var spec: Dictionary = u.loadout.get("core", {}).get("zone", {})
	if spec.is_empty() or spec.get("kind", "") != "mag_field":
		return RuleResult.allow()
	var aim: Variant = TurnAction.cell_param(params, "aim")
	if aim == null or not state.map.has_cell(aim):
		return RuleResult.deny("Choose the center of the field (params.aim).", REF_FIELD)
	var cells := cells_around(state, [aim] as Array[Vector2i], int(spec.get("size", 3)))
	var me := Sight.body_of(state, u)
	for c: Array in cells:
		var cell := Vector2i(int(c[0]), int(c[1]))
		if Sight.distance(state, me, Sight.make_body(state, cell, state.map.ground_height(cell), 0.5)) <= 1:
			return RuleResult.allow()
	return RuleResult.deny("The field must include at least one space adjacent to you.", REF_FIELD)


static func create_core_zone(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
	var spec: Dictionary = u.loadout.get("core", {}).get("zone", {})
	if spec.get("kind", "") != "mag_field":
		return [] as Array[Dictionary]
	var aim: Vector2i = TurnAction.cell_param(params, "aim")
	var events := add(state, {"kind": "mag_field", "owner": u.id, "label": "Mag Field", "center": [aim.x, aim.y],
		"cells": cells_around(state, [aim] as Array[Vector2i], int(spec.get("size", 3))), "blocked": 0,
		"expires": {"unit": u.id, "when": "end", "count": 2 if state.active_unit == u.id else 1}, "rule_ref": REF_FIELD})
	# Characters already inside aren't "entering"; they save when their turn starts there.
	return events


static func make_cloud(state: GameState, u: Unit) -> Array[Dictionary]:
	var foot: Array[Vector2i] = []
	foot.assign(state.map.grid.footprint(u.cell, u.size))
	return add(state, {"kind": "smoke_cloud", "owner": u.id, "label": "Burning cloud", "center": [u.cell.x, u.cell.y],
		"cells": cells_around(state, foot, 3), "phase": "smoke", "expires": {"unit": u.id, "when": "start", "count": 1}, "rule_ref": REF_CLOUD})


# --- Vision and barriers --------------------------------------------------------------
#   flash       Flash Grenade: characters other than its thrower at least partly inside can't
#               draw line of sight out of it (until the end of the thrower's next turn)
#   hardlight   Hardlight Defense System (burst 3): blocks line of sight both ways and no
#               attack or effect crosses it; characters partly inside ignore it; crossing the
#               edge the first time in a round, or starting a turn on it: 2 burn
#   blink       Blinkshield (burst 4, until the end of the owner's next turn): nothing crosses
#               its edge, not even line of sight or movement
#   oasis       Oasis Wall trail: adjacent characters have hard cover and Resistance to energy
# Blinded (status): line of sight only to adjacent spaces (Flash Mine, Shock Wreath).

static func _inside_all(state: GameState, z: Dictionary, u: Unit) -> bool:
	for c in state.map.grid.footprint(u.cell, u.size):
		if not _cell_in(state, z, c):
			return false
	return true


## Can `a` see `b` past these areas and statuses? (Sight.unit_line_of_sight asks.)
static func blocks_sight(state: GameState, a: Unit, b: Unit) -> bool:
	if a.has_status("Blinded") and Sight.unit_distance(state, a, b) > 1:
		return true
	for z: Dictionary in state.zones:
		match String(z.get("kind", "")):
			"flash":
				if a.id != z.get("owner", "") and contains(state, z, a) and not contains(state, z, b):
					return true
			"hardlight", "blink":
				if blocks_crossing(state, z, a, b):
					return true
	return false


## No attack or effect crosses a Hardlight shield or a Blinkshield.
static func blocks_crossing(state: GameState, z: Dictionary, a: Unit, b: Unit) -> bool:
	var a_in := contains(state, z, a)
	var b_in := contains(state, z, b)
	if z.get("kind", "") == "hardlight":
		# Characters partly inside ignore the hardlight shield.
		if (a_in and not _inside_all(state, z, a)) or (b_in and not _inside_all(state, z, b)):
			return false
	return a_in != b_in


static func barrier_between(state: GameState, a: Unit, b: Unit) -> Dictionary:
	for z: Dictionary in state.zones:
		if z.get("kind", "") in ["hardlight", "blink"] and blocks_crossing(state, z, a, b):
			return z
	return {}


## Movement can't cross a Blinkshield's edge, or enter a wall field (Magnetic Shield, Stasis
## Barrier: obstructions 4 spaces high).
static func blocks_step(state: GameState, from: Vector2i, to: Vector2i) -> bool:
	for z: Dictionary in of_kind(state, "blink"):
		if _cell_in(state, z, from) != _cell_in(state, z, to):
			return true
	for z: Dictionary in of_kind(state, "wall_field"):
		if _has_cell(z, to) and state.map.ground_height(to) + 4 > state.map.ground_height(from):
			return true
	return false


## A wall field between attacker and target (its soft cover): the straight line crosses it.
static func wall_field_between(state: GameState, attacker: Unit, target: Unit) -> Dictionary:
	if attacker == null:
		return {}
	for z: Dictionary in of_kind(state, "wall_field"):
		for c: Vector2i in state.map.grid.line(attacker.cell, target.cell):
			if _has_cell(z, c):
				return z
	return {}


## Builds a line of up to 4 free spaces starting next to `u` toward params.aim (Magnetic
## Shield, Stasis Barrier).
static func make_wall_field(state: GameState, u: Unit, label: String, flavor: String, params: Dictionary) -> Array[Dictionary]:
	for z: Dictionary in of_kind(state, "wall_field"):
		if z.get("owner", "") == u.id and z.get("flavor", "") == flavor:
			remove(state, String(z["id"]), "replaced")  # a new one deactivates the old one
	var aim: Variant = TurnAction.cell_param(params, "aim")
	var start: Vector2i = aim if aim != null else u.cell + Vector2i(1, 0)
	var line := state.map.grid.line(start, start + (start - u.cell) * 6)
	var cells: Array = []
	for c: Vector2i in line:
		if cells.size() >= 4 or not state.map.has_cell(c):
			break
		cells.append([c.x, c.y])
	return add(state, {"kind": "wall_field", "flavor": flavor, "owner": u.id, "label": label, "cells": cells,
		"center": cells[0] if not cells.is_empty() else [start.x, start.y], "rule_ref": "systems: " + label})


## Oasis Wall: next to the trail, hard cover and Resistance to energy.
static func oasis_cover(state: GameState, u: Unit) -> bool:
	for z: Dictionary in of_kind(state, "oasis"):
		for c in state.map.grid.footprint(u.cell, u.size):
			for n: Vector2i in state.map.grid.neighbors(c):
				if _has_cell(z, n):
					return true
	return false


static func oasis_trail(state: GameState, u: Unit, path: Array) -> void:
	if not Effects.has(u, "oasis_wall"):
		return
	for z: Dictionary in of_kind(state, "oasis"):
		if z.get("owner", "") != u.id:
			continue
		var cells: Array = z["cells"]
		for p: Array in path:
			for c in state.map.grid.footprint(Vector2i(int(p[0]), int(p[1])), maxf(1.0, u.size)):
				if not cells.has([c.x, c.y]):
					cells.append([c.x, c.y])


## Hardlight: crossing the edge the first time in a round costs 2 burn.
static func hardlight_crossing(state: GameState, u: Unit, path: Array) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for z: Dictionary in of_kind(state, "hardlight"):
		var crossed := false
		for i in range(1, path.size()):
			var a := Vector2i(int(path[i - 1][0]), int(path[i - 1][1]))
			var b := Vector2i(int(path[i][0]), int(path[i][1]))
			crossed = crossed or _cell_in(state, z, a) != _cell_in(state, z, b)
		if crossed:
			events.append_array(_hardlight_burn(state, z, u))
	return events


static func _hardlight_burn(state: GameState, z: Dictionary, u: Unit) -> Array[Dictionary]:
	var entered: Dictionary = z.get("entered", {})
	if int(entered.get(u.id, -1)) == state.round_number:
		return [] as Array[Dictionary]
	entered[u.id] = state.round_number
	z["entered"] = entered
	var events: Array[Dictionary] = [{"type": "zone_triggered", "zone": z["id"], "unit": u.id, "rule_ref": z.get("rule_ref", "")}]
	events.append_array(Combat.deal_damage(state, u, [{"type": "Burn", "amount": 2}], {"source": String(z.get("owner", ""))}))
	return events


## Starting a turn overlapping a Hardlight edge (partly inside): 2 burn.
static func hardlight_turn_start(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for z: Dictionary in of_kind(state, "hardlight"):
		if contains(state, z, u) and not _inside_all(state, z, u):
			events.append_array(_hardlight_burn(state, z, u))
	return events


## Blinkshield: characters partly inside move to the nearest free space; they choose a side
## on a successful Agility save, the owner chooses otherwise (the game puts them outside).
static func blinkshield(state: GameState, u: Unit) -> Array[Dictionary]:
	var foot: Array[Vector2i] = []
	foot.assign(state.map.grid.footprint(u.cell, u.size))
	var events := add(state, {"kind": "blink", "owner": u.id, "label": "Blinkshield", "center": [u.cell.x, u.cell.y],
		"cells": cells_around(state, foot, 4), "expires": {"unit": u.id, "when": "end", "count": 2 if state.active_unit == u.id else 1},
		"rule_ref": "systems: Blinkshield"})
	var z: Dictionary = state.zones.back()
	for o: Unit in state.units.values():
		if o == u or not Combat.is_present(o) or not contains(state, z, o) or _inside_all(state, z, o):
			continue
		var save := Combat.skill_check(state, o, "agility", "Save vs Blinkshield", u.save_target, 0, 0, [], true)
		events.append({"type": "skill_check", "unit": o.id, "check": save, "rule_ref": "systems: Blinkshield"})
		var best: Variant = null
		var best_d := 999
		for c: Vector2i in state.map.grid.cells_within(o.cell, 4):
			if not state.map.has_cell(c):
				continue
			var lv := Movement.surface_levels(state, o.size, c)
			if lv.is_empty():
				continue
			var inside := true
			var outside := true
			for f in state.map.grid.footprint(c, o.size):
				inside = inside and _cell_in(state, z, f)
				outside = outside and not _cell_in(state, z, f)
			if not outside:
				continue
			var body := Sight.make_body(state, c, lv[0], o.size)
			if Movement._blocked_by_unit(body, Movement._others(state, o), true):
				continue
			var d := state.map.grid.distance(o.cell, c)
			if d < best_d:
				best = [c, lv[0]]
				best_d = d
		if best != null:
			var from := [o.cell.x, o.cell.y, o.level]
			o.cell = best[0]
			o.level = best[1]
			events.append({"type": "moved", "unit": o.id, "path": [from, [o.cell.x, o.cell.y, o.level]], "mode": "involuntary", "cost": 0})
	return events
