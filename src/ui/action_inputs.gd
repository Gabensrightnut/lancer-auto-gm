class_name ActionInputs
extends RefCounted
## What the player has to pick on the board before an action can be submitted, as a list of
## steps: [{param, pick: "unit"|"cell", count, optional, label, area (blast size to preview),
## who ("ally"/"other"/"any"), pairs (cells come in lines of two: Drake sections)}].
## `count` > 1 collects that many picks into an array param (targets, aims, spaces, to,
## drones); a single pick is stored as the id or [x, y].
##
## Worked out from the weapon and ability data the engine uses (WeaponRules, ability ops,
## the core power spec). TODO(rules): a RulesQueries.action_inputs(state, unit, action) query
## would let the engine say this itself; until then, anything not recognized is probed with
## RulesEngine.validate (no params, then a unit target, then a space).

const AIMED_OPS := ["smoke", "blast_save", "napalm"]
## Actions with a known param: [param, pick, who, label].
const BY_TYPE := {
	"climb_on": ["host", "unit", "ally", "Pick the adjacent mech with the MULE Harness"],
	"board": ["mech", "unit", "ally", "Pick the adjacent mech to ride in"],
	"disembark": ["to", "cell", "", "Pick a free space next to the mech"],
	"cut_cable": ["target", "unit", "any", "Pick a character on the cable (next to you)"],
	"use_object": ["object", "unit", "ally", "Pick the object next to you (Restock Drone...)"],
	"mount": ["mech", "unit", "ally", "Pick the mech to climb into"],
	"dismount": ["to", "cell", "", "Pick where to climb down"],
	"eject": ["to", "cell", "", "Pick where to land (up to 6 away)"],
	"grapple": ["target", "unit", "other", "Pick who to grapple"],
	"ram": ["target", "unit", "other", "Pick who to ram"],
	"improvised_attack": ["target", "unit", "other", "Pick a target"],
	"search": ["target", "unit", "other", "Pick who to search for"],
	"bolster": ["target", "unit", "ally", "Pick an ally to Bolster"],
}
const PROBE_RANGE := 8


static func steps(state: GameState, engine: RulesEngine, u: Unit, a: Dictionary) -> Array:
	var type := String(a.get("type", ""))
	var params: Dictionary = a.get("params", {})
	if params.has("weapon") and type in ["skirmish", ""]:
		return weapon_steps(u, Weapons.find(u, String(params["weapon"])))
	if BY_TYPE.has(type):
		var b: Array = BY_TYPE[type]
		return [{"param": b[0], "pick": b[1], "count": 1, "who": b[2], "label": b[3]}]
	match type:
		"ai_control":
			return []  # a protocol; take_back is set by the catalog
		"activate":
			return ability_steps(state, engine, u, Abilities.find(u, String(params.get("ability", ""))), a)
		"core_power":
			return core_steps(state, engine, u, a)
	return probe(state, engine, u, a)


static func weapon_steps(u: Unit, w: Dictionary) -> Array:
	var out: Array = []
	var rules := WeaponRules.rules(w)
	var area := Weapons.area(w)
	if area != "":
		var blasts := int(rules.get("blasts", 1))
		if area != "Burst":
			out.append({"param": "aims" if blasts > 1 else "aim", "pick": "cell", "count": blasts,
				"label": "Aim the %s" % area.to_lower() + (" (%d of them)" % blasts if blasts > 1 else ""), "weapon": String(w.get("key", ""))})
	elif int(rules.get("targets", 1)) > 1:
		out.append({"param": "targets", "pick": "unit", "count": int(rules["targets"]), "who": "other", "label": "Pick up to %d targets" % int(rules["targets"])})
	else:
		out.append({"param": "target", "pick": "unit", "count": 1, "who": "other", "label": "Pick a target"})
	if rules.has("on_crit_teleport"):
		out.append({"param": "fold_to", "pick": "cell", "count": 1, "optional": true, "label": "Where to fold to on a critical hit (optional)"})
	return out


static func ability_steps(state: GameState, engine: RulesEngine, u: Unit, ab: Dictionary, a: Dictionary) -> Array:
	if ab.is_empty():
		return []
	match String(ab.get("kind", "action")):
		"deploy":
			var n := maxi(1, int(ab.get("instances", 1)))
			return [{"param": "to", "pick": "cell", "count": n, "label": "Where to deploy it" if n == 1 else "Where to deploy them (up to %d)" % n, "up_to": n > 1}]
		"recall":
			return []
	var out: Array = []
	for op: Dictionary in ab.get("ops", []):
		var name := String(op.get("op", ""))
		if op.has("target") and op["target"] is Dictionary:
			var spec: Dictionary = op["target"]
			out.append({"param": "target", "pick": "unit", "count": 1, "who": String(spec.get("who", "any")), "label": _target_label(spec),
				"or_space": spec.get("or_space", false)})
			if name == "ferrous_lash":
				out.append({"param": "toward", "pick": "cell", "count": 1, "optional": true, "label": "Pull toward which space (optional)"})
		elif name in AIMED_OPS:
			out.append({"param": "aim", "pick": "cell", "count": 1, "area": int(op.get("blast", 1)), "label": "Aim it (range %d)" % int(op.get("range", 5))})
		elif name == "javelin":
			out.append({"param": "spaces", "pick": "cell", "count": 3, "label": "Pick 3 spaces, not next to each other"})
		elif name in ["focus", "omnigun"]:
			out.append({"param": "target", "pick": "unit", "count": 1, "who": "other", "label": "Pick a target"})
	if not out.is_empty():
		return out
	return probe(state, engine, u, a)


static func core_steps(state: GameState, engine: RulesEngine, u: Unit, a: Dictionary) -> Array:
	var core: Dictionary = u.loadout.get("core", {})
	var out: Array = []
	var tgt: Dictionary = core.get("target", {}) if core.get("target") is Dictionary else {}
	if not tgt.is_empty() and tgt.has("who"):
		out.append({"param": "target", "pick": "unit", "count": 1, "who": String(tgt.get("who", "any")), "label": _target_label(tgt)})
	var zone: Dictionary = core.get("zone", {}) if core.get("zone") is Dictionary else {}
	if zone.get("kind", "") == "mag_field":
		out.append({"param": "aim", "pick": "cell", "count": 1, "area": int(zone.get("size", 3)), "label": "Center the field (it must touch a space next to you)"})
	if core.get("sections", false):
		out.append({"param": "sections", "pick": "cell", "count": 4, "pairs": true, "up_to": true,
			"label": "Place up to two cover sections: two spaces in a line each, the first next to you"})
	if core.get("deploy_all", false):
		var n := 0
		for ab: Dictionary in Abilities.all(u):
			if ab.get("kind", "") == "deploy":
				n += 1
		out.append({"param": "drones", "pick": "cell", "count": maxi(1, n), "label": "A space for each drone not yet deployed"})
	if out.is_empty():
		return probe(state, engine, u, a)
	return out


## Unknown needs: try no params, then any unit as the target, then a nearby space.
static func probe(state: GameState, engine: RulesEngine, u: Unit, a: Dictionary) -> Array:
	var base: Dictionary = a.get("params", {})
	var act := {"type": a.get("type", ""), "actor": u.id, "params": base}
	if engine.validate(state, act).ok:
		return []
	for o: Unit in state.units.values():
		var p := base.duplicate()
		p["target"] = o.id
		if engine.validate(state, {"type": act["type"], "actor": u.id, "params": p}).ok:
			return [{"param": "target", "pick": "unit", "count": 1, "who": "any", "label": "Pick a target"}]
	for key: String in ["to", "aim"]:
		for c: Vector2i in state.map.grid.cells_within(u.cell, PROBE_RANGE):
			if not state.map.has_cell(c):
				continue
			var p := base.duplicate()
			p[key] = [c.x, c.y]
			if engine.validate(state, {"type": act["type"], "actor": u.id, "params": p}).ok:
				return [{"param": key, "pick": "cell", "count": 1, "label": "Pick a space"}]
	return []


static func _target_label(spec: Dictionary) -> String:
	var who := {"ally": "an ally", "ally_mech": "an allied mech", "other": "a character", "any": "a character or object"}.get(String(spec.get("who", "any")), "a target") as String
	var where := ""
	if spec.get("adjacent", false):
		where = " next to you"
	elif spec.has("range"):
		where = " within %s" % ("Sensors" if String(spec["range"]) == "sensors" else "range %d" % int(spec["range"]))
	return "Pick %s%s%s" % [who, where, " (or a space)" if spec.get("or_space", false) else ""]


## True when this action is just "click one enemy" (the classic attack flow handles it).
static func is_simple_attack(steps_: Array) -> bool:
	return steps_.size() == 1 and String(steps_[0]["param"]) == "target" and String(steps_[0].get("who", "")) == "other"


## The params value for a finished step.
static func value_of(step: Dictionary, picks: Array) -> Variant:
	if bool(step.get("pairs", false)):
		var out: Array = []
		for i in range(0, picks.size() - 1, 2):
			out.append([picks[i], picks[i + 1]])
		return out
	if int(step.get("count", 1)) == 1:
		return picks[0] if not picks.is_empty() else null
	return picks.duplicate()
