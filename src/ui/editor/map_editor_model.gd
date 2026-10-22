class_name MapEditorModel
extends RefCounted
## What the map editor does, without any UI (so it can be tested headless). Every terrain or
## objective change becomes a GM action (GmMapActions) submitted to a RulesEngine, both when
## preparing a map (a private GameState) and live during a mission (the host's GameState):
## the same code path, so a live edit reaches every seat in its filtered view.
##
##   var m := MapEditorModel.new()
##   m.start_prep(MapDoc.blank(30, 26, GridLayout.Shape.HEX))      # or start_live(engine, state)
##   m.paint(cells, "raise")                                       # tools below
##   m.fairness_text()                                             # live checker

## Paint presets in plain words: what the brush makes (replaces the cell's tags).
const PRESETS := {
	"open ground": [],
	"rough ground (difficult)": ["difficult"],
	"woods (soft cover, difficult)": ["soft_cover", "difficult", "woods"],
	"water (difficult)": ["difficult", "water"],
	"fire (dangerous)": ["dangerous"],
	"lava (dangerous)": ["dangerous", "dangerous_energy", "lava"],
	"toxic pool (difficult, dangerous)": ["difficult", "dangerous", "toxic"],
	"rubble (difficult)": ["difficult", "rubble"],
	"rock": ["rock"],
	"crystal": ["crystal"],
	"wall": ["wall"],
	"building": ["building"],
	"container": ["container"],
	"bulkhead": ["bulkhead"],
	"chasm (impassable)": ["impassable", "chasm"],
	"sheer rock (impassable)": ["impassable", "rock"],
}
## Tools: "raise", "lower", "level" (to `level_to`), "preset" (to `preset`), "destructible"
## (toggle on), "sturdy" (toggle off), "zone" (add to `zone`), "unzone" (remove from zones).
const TOOLS := ["raise", "lower", "level", "preset", "destructible", "sturdy", "zone", "unzone"]
const DEPLOY_PREFIX := "deploy:"

signal changed(events: Array)

var doc: MapDoc
var engine: RulesEngine
var state: GameState
var live := false
var level_to := 1
var preset := "rough ground (difficult)"
## Zone being painted: a sitrep zone name ("zone_1", "extraction"...) or "deploy:players"/"deploy:enemies".
var zone := "deploy:players"
## Mirror every stroke through the map's center (point symmetry), which keeps maps fair.
var symmetric := false
var last_error := ""


## Editing a map before a mission: a private game state with the map, GM actions only.
func start_prep(d: MapDoc) -> void:
	doc = d
	engine = RulesEngine.new()
	GmActions.register(engine)
	state = GameState.new(1, d.map.grid.shape)
	state.map = d.map
	state.objectives = {"sitrep": d.sitrep, "zones": d.zones, "deployment": d.deployment}
	live = false


## Editing live as the human GM during a mission: the host's engine and state. Edits are
## refused while a unit would be buried or stranded (the actions' own checks).
func start_live(e: RulesEngine, s: GameState, d: MapDoc = null) -> void:
	engine = e
	GmActions.register(engine)
	state = s
	live = true
	if d == null:
		d = MapDoc.new()
	d.map = s.map
	d.sitrep = str(s.objectives.get("sitrep", "sitrep_standardcombat"))
	var cr := _extent(s.map)
	d.w = cr.x
	d.h = cr.y
	doc = d
	doc.map = s.map
	doc.zones = (s.objectives.get("zones", {}) as Dictionary).duplicate(true)
	doc.deployment = (s.objectives.get("deployment", {}) as Dictionary).duplicate(true)


static func _extent(map: BattleMap) -> Vector2i:
	var mx := 0
	var my := 0
	for c in map.cells():
		var cr := MapFairness._col_row(c, map.grid.shape)
		mx = maxi(mx, cr.x + 1)
		my = maxi(my, cr.y + 1)
	return Vector2i(mx, my)


## The cells a brush of `radius` covers around `center`, plus their mirror images.
func brush(center: Vector2i, radius: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in state.map.grid.cells_within(center, radius):
		if state.map.has_cell(c) and not out.has(c):
			out.append(c)
	if symmetric:
		for c in out.duplicate():
			var m := mirror(c)
			if state.map.has_cell(m) and not out.has(m):
				out.append(m)
	return out


func mirror(c: Vector2i) -> Vector2i:
	var cr := MapFairness._col_row(c, state.map.grid.shape)
	return SitrepLayout.cell_of(doc.w - 1 - cr.x, doc.h - 1 - cr.y, state.map.grid.shape)


## Applies `tool` to `cells` (one stroke). Returns the events, or [] with last_error set.
func paint(cells: Array, tool: String) -> Array:
	last_error = ""
	if tool in ["zone", "unzone"]:
		return _paint_zone(cells, tool == "zone")
	var changes: Array = []
	for c: Vector2i in cells:
		var col := state.map.column(c)
		if col == null:
			continue
		var e := {"cell": [c.x, c.y]}
		var tags := Array(col.tags)
		match tool:
			"raise":
				e["ground"] = mini(col.ground + 1, GmMapActions.MAX_GROUND)
			"lower":
				e["ground"] = maxi(col.ground - 1, 0)
			"level":
				e["ground"] = clampi(level_to, 0, GmMapActions.MAX_GROUND)
			"preset":
				var keep := tags.has(BattleMap.TAG_DESTRUCTIBLE)
				tags = (PRESETS.get(preset, []) as Array).duplicate()
				if keep and not tags.has(BattleMap.TAG_DESTRUCTIBLE):
					tags.append(BattleMap.TAG_DESTRUCTIBLE)
				e["tags"] = tags
			"destructible":
				if not tags.has(BattleMap.TAG_DESTRUCTIBLE):
					tags.append(BattleMap.TAG_DESTRUCTIBLE)
				e["tags"] = tags
			"sturdy":
				tags.erase(BattleMap.TAG_DESTRUCTIBLE)
				e["tags"] = tags
			_:
				continue
		changes.append(e)
	if changes.is_empty():
		return []
	return _submit({"type": "gm_edit_terrain", "params": {"cells": changes, "reason": "GM edit"}})


func _paint_zone(cells: Array, add: bool) -> Array:
	var zones := doc.zones.duplicate(true)
	var dep := doc.deployment.duplicate(true)
	var target: Dictionary = dep if zone.begins_with(DEPLOY_PREFIX) else zones
	var key := zone.trim_prefix(DEPLOY_PREFIX)
	if add:
		var list: Array = target.get(key, [])
		for c: Vector2i in cells:
			if not _has_cell(list, c):
				list.append([c.x, c.y])
		target[key] = list
	else:
		for d: Dictionary in [zones, dep]:
			for k: String in d:
				d[k] = (d[k] as Array).filter(func(e: Array) -> bool: return not cells.has(Vector2i(e[0], e[1])))
	return set_objectives(zones, dep)


static func _has_cell(list: Array, c: Vector2i) -> bool:
	for e: Array in list:
		if int(e[0]) == c.x and int(e[1]) == c.y:
			return true
	return false


func set_objectives(zones: Dictionary, deployment: Dictionary) -> Array:
	var events := _submit({"type": "gm_edit_objectives", "params": {"zones": zones, "deployment": deployment, "reason": "GM edit"}})
	if not events.is_empty():
		doc.zones = (state.objectives.get("zones", {}) as Dictionary).duplicate(true)
		doc.deployment = (state.objectives.get("deployment", {}) as Dictionary).duplicate(true)
	return events


## Lays the sitrep's zones and deployment out afresh (SitrepLayout).
func relayout(sitrep_id: String, rng: RandomNumberGenerator) -> Array:
	doc.sitrep = sitrep_id
	state.objectives["sitrep"] = sitrep_id
	var lay := SitrepLayout.layout(sitrep_id, doc.w, doc.h, state.map.grid.shape, rng)
	return set_objectives(lay["zones"], lay["deployment"])


func _submit(action: Dictionary) -> Array:
	action["seat"] = "gm"
	var r: Dictionary = engine.submit(state, action)
	var res: RuleResult = r.get("result")
	if res == null or not res.ok:
		last_error = res.reason if res != null else "Refused."
		return []
	var events: Array = r.get("events", [])
	doc.map = state.map
	changed.emit(events)
	return events


## Zone names to paint for the doc's sitrep (plus both deployment zones).
func zone_choices() -> Array:
	var out: Array = [DEPLOY_PREFIX + Mission.PLAYERS, DEPLOY_PREFIX + Mission.ENEMIES]
	var names: Array = doc.zones.keys()
	match doc.sitrep:
		"sitrep_control", "sitrep_recon":
			names.append_array(["zone_1", "zone_2", "zone_3", "zone_4"])
		"sitrep_holdout", "sitrep_gauntlet":
			names.append("zone")
		"sitrep_escort":
			names.append("extraction")
		"sitrep_extraction":
			names.append_array(["objective", "extraction"])
	for n: String in names:
		if not out.has(n):
			out.append(n)
	return out


## The live fairness checker as plain-language lines: [{ok: bool, text}].
func fairness_lines() -> Array:
	var f := doc.fairness()
	var out: Array = []
	var cover: Array = f["cover"]
	out.append({"ok": float(f["cover_ratio"]) >= MapFairness.MIN_COVER_RATIO or maxi(cover[0], cover[1]) < 6,
		"text": "Cover: squad half %d, enemy half %d (should be within 60%% of each other)" % [cover[0], cover[1]]})
	var br: Array = f.get("destructible", [0, 0])
	if br[0] + br[1] > 0:
		out.append({"ok": maxi(br[0], br[1]) < 8 or float(f.get("destructible_ratio", 1.0)) >= MapFairness.MIN_COVER_RATIO,
			"text": "Destructible cover: %d / %d" % [br[0], br[1]]})
	var hid: Dictionary = f["hidden"]
	var need_players := 0.0 if doc.sitrep == "sitrep_holdout" else MapFairness.MIN_HIDDEN
	out.append({"ok": float(hid[Mission.PLAYERS]) >= need_players,
		"text": "Squad deployment hidden from the enemy's: %d%% (need %d%%)" % [int(float(hid[Mission.PLAYERS]) * 100), int(need_players * 100)]})
	out.append({"ok": float(hid[Mission.ENEMIES]) >= MapFairness.MIN_HIDDEN,
		"text": "Enemy deployment hidden from the squad's: %d%% (need %d%%)" % [int(float(hid[Mission.ENEMIES]) * 100), int(MapFairness.MIN_HIDDEN * 100)]})
	var un: Array = f["unreachable"]
	out.append({"ok": un.is_empty(), "text": "Every objective reachable by Size 1-3" if un.is_empty() else "; ".join(un)})
	if doc.deployment.get(Mission.PLAYERS, []).is_empty() or doc.deployment.get(Mission.ENEMIES, []).is_empty():
		out.append({"ok": false, "text": "Both sides need a deployment zone"})
	return out


func fairness_ok() -> bool:
	for l: Dictionary in fairness_lines():
		if not l["ok"]:
			return false
	return true
