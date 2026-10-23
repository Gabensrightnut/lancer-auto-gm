class_name TerrainDamage
extends RefCounted
## Attacking and destroying terrain (Core p.68 "Objects and damage"; terrain is an object,
## Core p.58). Objects have 5 Evasion and 10 HP per Size, and each Size 1 section is
## destroyed separately; solid rock can have 1-2 Armor, fortified places 3-4.
##
## On the map: a column tagged "destructible" is made of Size 1 sections, one per level above
## its floor (tag "floor_N", else 0). Its Armor comes from a tag "armor_N", else its
## "material:<name>" tag (MATERIAL_ARMOR), else 0; each section has 10 HP unless tagged
## "hp_N". Columns without the tag can't be damaged: the GM waived the rule for them (Core
## p.68 lets the GM waive it for objects characters didn't make).
##
## Attacking it: any attack or action whose target is "terrain:x,y" (Skirmish, Barrage, Ram,
## Improvised Attack, an ability) hits the column's top section. While that action is checked
## and resolved, the section stands on the field as a temporary object unit (section_unit),
## so every attack rule (range, line of sight, cover, Armor, AP, weapon tags, object damage
## such as Sherman's COREBURN or the Siege Ram) works unchanged. Afterwards settle() keeps the
## damage in state.terrain_damage and removes the unit.
##
## Destroying a section lowers the column by one level and sends
## {"type": "terrain_destroyed", "cells": [[x, y, new ground]], "source", "rule_ref"}. The book
## doesn't make rubble difficult terrain, so the cell gets no new tags; at its floor it loses
## "destructible". Characters left standing on nothing fall (Core p.63).
## PROVISIONAL: excess damage doesn't carry over to the next section; "automatically hit"
## area effects hit every section of the columns in the area (docs/RULES_TODO.md).

const REF := "Core p.68 Objects and Damage"
const PREFIX := "terrain:"
const SECTION_HP := 10
const EVASION := 5


## What a cell looks like after damage, for drawing it (visuals): the top section's HP left,
## a stage 0 intact, 1 cracked, 2 badly damaged, 3 about to go; sections lost so far (rubble).
static func damage_state(state: GameState, c: Vector2i) -> Dictionary:
	var dmg := int(state.terrain_damage.get(key(c), 0))
	var stage := 0 if dmg == 0 else (1 if dmg < 5 else (2 if dmg < 8 else 3))
	return {"hp_left": SECTION_HP - dmg, "section_hp": SECTION_HP, "stage": stage,
		"sections_lost": int(state.terrain_lost.get(key(c), 0))}


static func key(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]


static func id_for(c: Vector2i) -> String:
	return PREFIX + key(c)


## The cell a "terrain:x,y" id names, or null.
static func cell_of(id: String) -> Variant:
	if not id.begins_with(PREFIX):
		return null
	var parts := id.substr(PREFIX.length()).split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return null
	return Vector2i(int(parts[0]), int(parts[1]))


static func _tag_value(col: BattleMap.Column, prefix: String, lo: int, hi: int) -> int:
	for t in col.tags:
		if t.begins_with(prefix) and t.substr(prefix.length()).is_valid_int():
			return clampi(int(t.substr(prefix.length())), lo, hi)
	return 0


static func floor_of(col: BattleMap.Column) -> int:
	return _tag_value(col, "floor_", 0, 1000)


## Armor: an explicit "armor_N" tag (0-4) wins; else the material's (Core p.68: solid rock
## 1-2, fortified 3-4, everything else 0).
const MATERIAL_ARMOR := {"wood": 0, "prefab": 0, "glass": 0, "metal": 1, "rock": 1, "stone": 2, "concrete": 2, "reinforced": 3, "fortified": 4}


static func armor_of(col: BattleMap.Column) -> int:
	for t in col.tags:
		if t.begins_with("armor_") and t.substr(6).is_valid_int():
			return clampi(int(t.substr(6)), 0, 4)
	for t in col.tags:
		if t.begins_with("material:"):
			return int(MATERIAL_ARMOR.get(t.substr(9), 0))
	return 0


## HP of each Size 1 section: 10 (Core p.68) unless the map says otherwise ("hp_N").
static func section_hp(col: BattleMap.Column) -> int:
	var v := _tag_value(col, "hp_", 0, 1000)
	return v if v > 0 else SECTION_HP


static func destructible(state: GameState, c: Vector2i) -> bool:
	if not state.map.has_cell(c):
		return false
	var col := state.map.column(c)
	return col.has_tag(BattleMap.TAG_DESTRUCTIBLE) and col.ground > floor_of(col)


## HP left in the column's top section.
static func hp_left(state: GameState, c: Vector2i) -> int:
	return section_hp(state.map.column(c)) - int(state.terrain_damage.get(key(c), 0))


## Everything the HUD needs about a destructible column: {cell, ground, floor, sections,
## hp, max_hp, evasion, armor, rule_ref}. Empty if it can't be damaged.
static func info(state: GameState, c: Vector2i) -> Dictionary:
	if not destructible(state, c):
		return {}
	var col := state.map.column(c)
	return {"cell": [c.x, c.y], "ground": col.ground, "floor": floor_of(col), "sections": col.ground - floor_of(col),
		"hp": hp_left(state, c), "max_hp": section_hp(col), "evasion": EVASION, "armor": armor_of(col), "rule_ref": REF}


## A temporary object standing for the top section of the column at `c`.
static func section_unit(state: GameState, c: Vector2i) -> Unit:
	var col := state.map.column(c)
	var u := Unit.new()
	u.id = id_for(c)
	u.name = "Terrain"
	for look in ["wall", "bulkhead", "building", "rock"]:
		if col.has_tag(look):
			u.name = look.capitalize()
	u.kind = Unit.KIND_DEPLOYABLE
	u.side = "terrain"
	u.controller = ""
	u.cell = c
	u.size = 1.0
	u.level = col.ground - 1
	u.max_hp = section_hp(col)
	u.hp = hp_left(state, c)
	u.evasion = EVASION
	u.edef = 0
	u.armor = armor_of(col)
	u.max_structure = 1
	u.structure = 1
	u.counters["terrain"] = [c.x, c.y]
	u.loadout = {"weapons": [], "systems": [], "effects": []}
	return u


## Puts a section unit on the field for every "terrain:x,y" target an action names. Returns
## the ids it added (remove() or settle() takes them off again).
static func materialize(state: GameState, action: Dictionary) -> Array[String]:
	var made: Array[String] = []
	var params: Variant = action.get("params", {})
	if not params is Dictionary:
		return made
	var ids: Array = [params.get("target", "")]
	var aux: Variant = params.get("aux")
	for x: Variant in (aux if aux is Array else [aux]):
		if x is Dictionary:
			ids.append((x as Dictionary).get("target", ""))
	for x: Variant in params.get("attacks", []):
		if x is Dictionary:
			ids.append((x as Dictionary).get("target", ""))
	for id: Variant in ids:
		if str(id).begins_with(ZONE_PREFIX) and not state.units.has(str(id)):
			var zu := zone_unit(state, str(id))
			if zu != null:
				state.add_unit(zu)
				made.append(str(id))
			continue
		var c: Variant = cell_of(str(id))
		if c == null or state.units.has(str(id)) or not destructible(state, c):
			continue
		state.add_unit(section_unit(state, c))
		made.append(str(id))
	return made


## Objects that live as zones (the Portable Bunker: 40 HP, Evasion 5, Size 4) stand in as an
## object unit while attacked, with target "zone:<zone id>".
const ZONE_PREFIX := "zone:"


static func zone_unit(state: GameState, id: String) -> Unit:
	var zid := id.substr(ZONE_PREFIX.length())
	for z: Dictionary in Zones.of_kind(state, "bunker") + Zones.of_kind(state, "pcp"):
		if String(z["id"]) != zid:
			continue
		var u := Unit.new()
		u.id = id
		u.name = String(z.get("label", "Bunker"))
		u.kind = Unit.KIND_DEPLOYABLE
		u.side = "terrain"
		u.cell = Vector2i(int(z["center"][0]), int(z["center"][1]))
		u.level = state.map.ground_height(u.cell)
		var pcp: bool = z["kind"] == "pcp"
		u.size = 2.0 if pcp else 4.0
		u.max_hp = 20 if pcp else 40
		u.hp = int(z.get("hp", u.max_hp))
		u.evasion = 5
		u.max_structure = 1
		u.structure = 1
		u.counters["zone"] = zid
		u.loadout = {"weapons": [], "systems": [], "effects": []}
		return u
	return null


static func remove(state: GameState, ids: Array[String]) -> void:
	for id in ids:
		state.units.erase(id)


## After the action: keeps the damage the section units took and destroys broken sections.
static func settle(state: GameState, ids: Array[String], source: String = "") -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for id in ids:
		var u := state.unit(id)
		if u == null:
			continue
		state.units.erase(id)
		if id.begins_with(ZONE_PREFIX):
			var zid := id.substr(ZONE_PREFIX.length())
			for z: Dictionary in Zones.of_kind(state, "bunker") + Zones.of_kind(state, "pcp"):
				if String(z["id"]) == zid:
					z["hp"] = u.hp
					if u.destroyed or u.hp <= 0:
						events.append_array(Zones.remove(state, zid, "destroyed"))
						for o: Unit in state.units.values():
							if o.has_status("Immobilized") and String(o.statuses["Immobilized"].get("source", "")) == "pcp:" + zid:
								events.append_array(Combat.remove_status(o, "Immobilized", "the plate was destroyed"))
			continue
		var c: Vector2i = cell_of(id)
		if u.destroyed or u.hp <= 0:
			events.append_array(destroy_sections(state, c, 1, source))
		elif u.hp < u.max_hp:
			var before := hp_left(state, c)
			state.terrain_damage[key(c)] = u.max_hp - u.hp
			events.append_array(collapse_roll(state, c, before - u.hp, source))
	return events


## Damage to the top section without an attack roll (effects that hit objects automatically).
## Armor counts unless `ap`. `all_sections`: every section of the column takes it.
static func damage_cell(state: GameState, c: Vector2i, amount: int, dtype: String, ap: bool, source: String, all_sections: bool = false) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not destructible(state, c):
		return events
	var col := state.map.column(c)
	var dmg := amount if ap else maxi(0, amount - armor_of(col))
	events.append({"type": "terrain_damaged", "cell": [c.x, c.y], "amount": dmg, "damage_type": dtype, "ap": ap,
		"armor": 0 if ap else armor_of(col), "source": source, "rule_ref": REF})
	if dmg <= 0:
		return events
	var sections := col.ground - floor_of(col)
	var full := section_hp(col)
	if all_sections and dmg >= full:
		events.append_array(destroy_sections(state, c, sections, source))
		return events
	var left := hp_left(state, c)
	if dmg >= left:
		events.append_array(destroy_sections(state, c, 1, source))
		if all_sections and sections > 1:
			state.terrain_damage[key(c)] = dmg  # the section below took the same damage
	else:
		state.terrain_damage[key(c)] = full - left + dmg
		events.append_array(collapse_roll(state, c, dmg, source))
	events[0]["hp_left"] = hp_left(state, c) if destructible(state, c) else 0
	return events


## House rule "hr_collapse_save" (your idea, not a book rule): a section still standing after a
## hit of 5+ damage rolls 1d6 + its Armor; on 3 or less it collapses anyway.
static func collapse_roll(state: GameState, c: Vector2i, dmg: int, source: String) -> Array[Dictionary]:
	if dmg < 5 or not HouseRuleSwitches.on(state, "hr_collapse_save") or not destructible(state, c):
		return [] as Array[Dictionary]
	var roll := state.dice.die(6)
	var total := roll + armor_of(state.map.column(c))
	var events: Array[Dictionary] = [{"type": "collapse_roll", "cell": [c.x, c.y], "roll": roll, "total": total, "collapsed": total <= 3,
		"rule_ref": "House rule: Building collapse roll"}]
	if total <= 3:
		events.append_array(destroy_sections(state, c, 1, source))
	return events


## Every destructible column in `cells` ([[x, y]...] or Vector2i) takes the damage.
static func damage_area(state: GameState, cells: Array, amount: int, dtype: String, ap: bool, source: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for x: Variant in cells:
		var c: Vector2i = x if x is Vector2i else Vector2i(int(x[0]), int(x[1]))
		events.append_array(damage_cell(state, c, amount, dtype, ap, source, true))
	return events


## Destroys `n` sections from the top of the column at `c`.
static func destroy_sections(state: GameState, c: Vector2i, n: int, source: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var col := state.map.column(c)
	var old := col.ground
	var new_ground := maxi(floor_of(col), col.ground - n)
	if col.gap_top > 0 and new_ground <= col.gap_top:
		# The span over a gap is gone: down to the gap's floor.
		new_ground = maxi(floor_of(col), col.gap_bottom)
		col.gap_bottom = 0
		col.gap_top = 0
	col.ground = new_ground
	state.terrain_damage.erase(key(c))
	state.terrain_lost[key(c)] = int(state.terrain_lost.get(key(c), 0)) + (old - new_ground)
	if col.ground <= floor_of(col):
		var tags := col.tags
		tags.remove_at(tags.find(BattleMap.TAG_DESTRUCTIBLE))
		col.tags = tags
	events.append({"type": "terrain_destroyed", "cells": [[c.x, c.y, col.ground]], "from": old, "lost": int(state.terrain_lost[key(c)]), "source": source, "rule_ref": REF})
	if col.has_tag(Garrison.TAG_INTERIOR) and old > Garrison.room_level(col) and col.ground <= Garrison.room_level(col):
		# The building's ground storey came down on whoever was inside (house rule: Garrison).
		events.append_array(Garrison.collapse(state, c, old, source))
	# Anyone standing on what's gone has nothing under them now.
	for u: Unit in state.units.values():
		if u.destroyed or u.flying or u.level <= col.ground or u.level > old:
			continue
		if state.map.grid.footprint(u.cell, u.size).has(c) and Movement.placement(state, u.size, u.cell, u.level)["airborne"]:
			events.append_array(Combat.begin_falling(u, "The ground under it was destroyed."))
	return events


## Area attacks whose objects in the area take damage automatically (Barbarossa Apocalypse
## Rail: 20, 40 or 100 AP explosive, by Charge Rail profile).
static func after_area(state: GameState, attacker: Unit, w: Dictionary, cells: Array) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if w.get("id", "") == FrameSystems.RAIL:
		var amount: int = [0, 20, 40, 100][clampi(int(w.get("profile", 0)), 0, 3)]
		if amount > 0:
			events.append_array(object_damage_in(state, attacker, cells, amount, "Explosive"))
	return events


## Objects in `cells` (deployables and destructible terrain) take AP damage automatically.
static func object_damage_in(state: GameState, by: Unit, cells: Array, amount: int, dtype: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var ids: Array = state.units.keys()
	ids.sort()
	for id: Variant in ids:
		var o: Unit = state.units[id]
		if o.kind != Unit.KIND_DEPLOYABLE or not Combat.is_present(o) or o.counters.has("terrain"):
			continue
		for c in state.map.grid.footprint(o.cell, o.size):
			if cells.has([c.x, c.y]):
				events.append_array(Combat.deal_damage(state, o, [{"type": dtype, "amount": amount}], {"ap": true, "source": by.id}))
				break
	events.append_array(damage_area(state, cells, amount, dtype, true, by.id))
	return events
