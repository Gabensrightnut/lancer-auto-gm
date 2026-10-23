class_name SitrepActions
extends RefCounted
## Sitrep actions (rules text: data/lancer-data/sitreps.json), registered into the RulesEngine
## by GmActions.register so they go through submit() like everything else:
##   extract              (free, at the end of your turn) Escort/Extraction: while in the
##                        Extraction Zone a PC extracts; an adjacent, uncontested Objective goes
##                        with them. Events: unit_extracted, objective_extracted.
##   survey_zone          (full action) Recon: inside a Control Zone, a PC learns whether it's
##                        the True Control Zone (only their side sees the answer).
##   gm_carry_objective   (GM) the Objective moves with the character who started their turn
##                        next to it, when they make their regular move (Mission decides where).
## State: state.objectives (MissionGenerator sets it up).

const REF_ESCORT := "sitreps: Escort"
const REF_EXTRACTION := "sitreps: Extraction"
const REF_RECON := "sitreps: Recon"


static func register(engine: RulesEngine) -> void:
	for h: ActionHandler in [Extract.new(), SurveyZone.new(), CarryObjective.new()]:
		if not engine.has_action(h.type()):
			engine.register(h)


static func ref(state: GameState) -> String:
	return REF_EXTRACTION if str(state.objectives.get("sitrep", "")) == "sitrep_extraction" else REF_ESCORT


static func in_cells(state: GameState, u: Unit, cells: Array) -> bool:
	var set := {}
	for c: Array in cells:
		set[Vector2i(int(c[0]), int(c[1]))] = true
	for c in state.map.grid.footprint(u.cell, u.size):
		if set.has(c):
			return true
	return false


static func objective(state: GameState) -> Unit:
	return state.unit(str(state.objectives.get("objective", "")))


## Characters (not objects) of other sides than `side` adjacent to `u`.
static func contested(state: GameState, u: Unit, side: String) -> bool:
	for o: Unit in state.units.values():
		if o != u and o.side != side and Combat.is_present(o) and o.kind != Unit.KIND_DEPLOYABLE and Sight.unit_distance(state, o, u) <= 1:
			return true
	return false


## The Control Zone `u` stands in ("" if none).
static func zone_at(state: GameState, u: Unit) -> String:
	var zones: Dictionary = state.objectives.get("zones", {})
	var names := zones.keys()
	names.sort()
	for name: String in names:
		if str(name).begins_with("zone") and in_cells(state, u, zones[name]):
			return name
	return ""


class Extract:
	extends TurnAction

	func type() -> String:
		return "extract"

	func cost() -> String:
		return TurnRules.FREE

	func kinds() -> Array:
		return [Unit.KIND_MECH, Unit.KIND_PILOT]

	func check(state: GameState, u: Unit, _params: Dictionary) -> RuleResult:
		var cells: Array = state.objectives.get("extraction", [])
		if cells.is_empty():
			return RuleResult.deny("This mission has no Extraction Zone.", "")
		if u.side != Mission.PLAYERS:
			return RuleResult.deny("Only the squad extracts.", SitrepActions.ref(state))
		if not SitrepActions.in_cells(state, u, cells):
			return RuleResult.deny("Get into the Extraction Zone first.", SitrepActions.ref(state))
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, _params: Dictionary) -> Array[Dictionary]:
		var r := SitrepActions.ref(state)
		var events: Array[Dictionary] = []
		var obj := SitrepActions.objective(state)
		var with_objective := obj != null and Combat.is_present(obj) and Sight.unit_distance(state, u, obj) <= 1 \
			and not SitrepActions.contested(state, obj, u.side)
		# "At the end of their turn": the turn ends, then the mech leaves the battlefield.
		events.append_array(TurnRules.finish_turn(state, u))
		u.counters["extracted"] = true
		events.append({"type": "unit_extracted", "unit": u.id, "rule_ref": r})
		if with_objective:
			obj.counters["extracted"] = true
			state.objectives["objective_extracted"] = true
			events.append({"type": "objective_extracted", "unit": obj.id, "by": u.id, "rule_ref": r})
		return events


class SurveyZone:
	extends TurnAction

	func type() -> String:
		return "survey_zone"

	func cost() -> String:
		return TurnRules.FULL

	func kinds() -> Array:
		return [Unit.KIND_MECH, Unit.KIND_PILOT]

	func check(state: GameState, u: Unit, _params: Dictionary) -> RuleResult:
		if str(state.objectives.get("sitrep", "")) != "sitrep_recon":
			return RuleResult.deny("Only Recon missions have a True Control Zone to find.", SitrepActions.REF_RECON)
		if u.side != Mission.PLAYERS:
			return RuleResult.deny("Only the squad surveys the zones.", SitrepActions.REF_RECON)
		var z := SitrepActions.zone_at(state, u)
		if z == "":
			return RuleResult.deny("Stand inside a Control Zone to survey it.", SitrepActions.REF_RECON)
		if (state.objectives.get("surveyed", {}).get(u.side, {}) as Dictionary).has(z):
			return RuleResult.deny("Your squad already knows whether this one is the True Control Zone.", SitrepActions.REF_RECON)
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, _params: Dictionary) -> Array[Dictionary]:
		var z := SitrepActions.zone_at(state, u)
		var found := z == str(state.objectives.get("true_zone", ""))
		if not state.objectives.has("surveyed"):
			state.objectives["surveyed"] = {}
		if not state.objectives["surveyed"].has(u.side):
			state.objectives["surveyed"][u.side] = {}
		state.objectives["surveyed"][u.side][z] = found
		return [{"type": "zone_surveyed", "unit": u.id, "zone": z, "true": found, "seen_by": [u.side], "rule_ref": SitrepActions.REF_RECON}] as Array[Dictionary]


class CarryObjective:
	extends ActionHandler

	func type() -> String:
		return "gm_carry_objective"

	func needs_actor() -> bool:
		return false

	func validate(state: GameState, action: Dictionary) -> RuleResult:
		var obj := SitrepActions.objective(state)
		var to: Variant = action.get("params", {}).get("to")
		if obj == null or not Combat.is_present(obj):
			return RuleResult.deny("There's no Objective on the field.", SitrepActions.ref(state))
		if not to is Array or (to as Array).size() < 2:
			return RuleResult.deny("Say where to carry the Objective (params.to = [x, y]).", SitrepActions.ref(state))
		var cell := Vector2i(int(to[0]), int(to[1]))
		if not state.map.has_cell(cell):
			return RuleResult.deny("That space is off the map.", SitrepActions.ref(state))
		for o: Unit in state.units.values():
			if o != obj and Combat.is_present(o) and state.map.grid.footprint(o.cell, o.size).has(cell):
				return RuleResult.deny("That space is taken.", SitrepActions.ref(state))
		return RuleResult.allow()

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		var obj := SitrepActions.objective(state)
		var to: Array = action["params"]["to"]
		var from := obj.cell
		obj.cell = Vector2i(int(to[0]), int(to[1]))
		obj.level = state.map.ground_height(obj.cell)
		return [{"type": "moved", "unit": obj.id, "path": [[from.x, from.y, obj.level], [obj.cell.x, obj.cell.y, obj.level]], "mode": "carried",
			"cost": 0, "stopped_by": "", "by": str(action["params"].get("by", "")), "rule_ref": SitrepActions.ref(state)}] as Array[Dictionary]
