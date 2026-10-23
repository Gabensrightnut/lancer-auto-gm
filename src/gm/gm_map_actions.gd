class_name GmMapActions
extends RefCounted
## GM actions that change the battlefield, registered into the RulesEngine (via
## GmActions.register) so a human GM's edits during a mission go through submit() and every
## seat gets them in its filtered view:
##   gm_edit_terrain     {"cells": [{"cell": [x, y], "ground": n, "tags": [..], "gap": [bottom, top]}], "reason"}
##   gm_edit_objectives  {"zones": {name: [[x, y]]}, "deployment": {side: [[x, y]]}, "reason"}
## Events: terrain_edited {cells: [[x, y, ground]], reason} and objectives_changed {reason}.
## Edits never bury, cut or strand a unit: a cell under a unit can't rise above the unit's
## level or become impassable. Tags must be known rules or look tags (TAGS).

const RULES_TAGS := ["difficult", "dangerous", "impassable", "destructible", "soft_cover",
	"dangerous_energy", "dangerous_explosive", "dangerous_burn"]
const LOOK_TAGS := ["rock", "woods", "building", "wall", "water", "ice", "lava", "toxic", "crystal",
	"rubble", "chasm", "bulkhead", "container", "machinery", "platform", "deck",
	"road", "road_x", "road_z", "crossing", "farm", "dry", "house", "keep", "void", "lot", "plaza", "highway", "ramp", "crosswalk", "rail", "rail_x", "rail_z", "door", "vehicle", "safe_point", "repair_rig", "objective", "interior", "entrance",
	"hull", "breach", "torpedo", "airlock", "console", "bunk", "table", "galley"]
const MAX_GROUND := 10
const REF := "GM: battlefield edit (human GM seat)"


static func register(engine: RulesEngine) -> void:
	for h: ActionHandler in [EditTerrain.new(), EditObjectives.new()]:
		if not engine.has_action(h.type()):
			engine.register(h)


static func known_tag(t: String) -> bool:
	if t.begins_with("armor_") or t.begins_with("floor_"):
		return t.substr(t.find("_") + 1).is_valid_int()
	if t.begins_with("material_"):
		return t.substr(9) in MATERIALS
	if t.begins_with("window_") or t.begins_with("storeys_"):
		return t.substr(t.find("_") + 1).is_valid_int()  # building interiors (look; rules read them)
	if t.begins_with("spot_") or t.begins_with("door_"):
		return true  # a hub building's cells and its door (look only)
	if t.begins_with("lane"):
		return t.trim_prefix("lane").split("_").size() == 2  # road markings (look only)
	return t in RULES_TAGS or t in LOOK_TAGS


## Building materials (TerrainGen.MATERIALS): how a column looks when hit and when it breaks.
const MATERIALS := ["wood", "stone", "concrete", "metal", "fortified", "hull"]


class EditTerrain:
	extends ActionHandler

	func type() -> String:
		return "gm_edit_terrain"

	func needs_actor() -> bool:
		return false

	func validate(state: GameState, action: Dictionary) -> RuleResult:
		if state.phase == GameState.PHASE_ENDED:
			return RuleResult.deny("The mission is over.", GmMapActions.REF)
		var cells: Variant = action.get("params", {}).get("cells", [])
		if not cells is Array or (cells as Array).is_empty():
			return RuleResult.deny("Nothing to change.", GmMapActions.REF)
		var under := {}  # cell -> lowest unit level standing in it
		for u: Unit in state.units.values():
			if u.destroyed:
				continue
			for c in state.map.grid.footprint(u.cell, u.size):
				under[c] = mini(under.get(c, 999), u.level)
		for e: Variant in cells:
			if not e is Dictionary or not e.has("cell"):
				return RuleResult.deny("Each change needs a cell.", GmMapActions.REF)
			var c := Vector2i(int(e["cell"][0]), int(e["cell"][1]))
			if not state.map.has_cell(c):
				return RuleResult.deny("%s is off the map." % c, GmMapActions.REF)
			var g := int(e.get("ground", state.map.ground_height(c)))
			if g < 0 or g > MAX_GROUND:
				return RuleResult.deny("Height must be 0-%d." % MAX_GROUND, GmMapActions.REF)
			for t: Variant in e.get("tags", []):
				if not GmMapActions.known_tag(str(t)):
					return RuleResult.deny("Unknown terrain tag '%s'." % t, GmMapActions.REF)
			if under.has(c):
				if g > int(under[c]):
					return RuleResult.deny("That would bury a unit standing at %s." % c, GmMapActions.REF)
				if str(BattleMap.TAG_IMPASSABLE) in Array(e.get("tags", [])):
					return RuleResult.deny("A unit stands at %s; it can't become impassable." % c, GmMapActions.REF)
		return RuleResult.allow()

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		var out: Array = []
		for e: Dictionary in action["params"]["cells"]:
			var c := Vector2i(int(e["cell"][0]), int(e["cell"][1]))
			var col := state.map.column(c)
			if e.has("ground"):
				col.ground = int(e["ground"])
			if e.has("tags"):
				col.tags = PackedStringArray(e["tags"])
			if e.has("gap"):
				col.gap_bottom = int(e["gap"][0])
				col.gap_top = int(e["gap"][1])
			# Edited columns start undamaged.
			state.terrain_damage.erase("%d,%d" % [c.x, c.y])
			out.append([c.x, c.y, col.ground])
		return [{"type": "terrain_edited", "cells": out, "reason": str(action["params"].get("reason", "")), "rule_ref": GmMapActions.REF}]


class EditObjectives:
	extends ActionHandler

	func type() -> String:
		return "gm_edit_objectives"

	func needs_actor() -> bool:
		return false

	func validate(state: GameState, action: Dictionary) -> RuleResult:
		var p: Dictionary = action.get("params", {})
		for key: String in ["zones", "deployment"]:
			if not p.has(key):
				continue
			if not p[key] is Dictionary:
				return RuleResult.deny("%s must map names to cells." % key, GmMapActions.REF)
			for name: String in p[key]:
				for c: Variant in p[key][name]:
					if not state.map.has_cell(Vector2i(int(c[0]), int(c[1]))):
						return RuleResult.deny("%s %s has a cell off the map." % [key, name], GmMapActions.REF)
		return RuleResult.allow()

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		var p: Dictionary = action["params"]
		for key: String in ["zones", "deployment"]:
			if p.has(key):
				state.objectives[key] = (p[key] as Dictionary).duplicate(true)
		return [{"type": "objectives_changed", "reason": str(p.get("reason", "")), "rule_ref": GmMapActions.REF}]
