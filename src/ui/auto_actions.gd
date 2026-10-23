class_name AutoActions
extends RefCounted
## The action bar's auto toggle (right-click a slot; a gold bead circles it): repeatable,
## non-attack abilities the player wants used for them. The rules don't change: an auto
## ability is submitted through RulesEngine exactly like a click, pays its whole cost, and is
## skipped (with a one-line note) when it can't be paid or would push heat over the cap.
## Never auto: any attack (weapons, Barrage, Ram/Grapple, tech attacks like Invade, system
## attacks, reactions that attack such as Overwatch), Limited/charged or once-per-scene
## gear, Loading weapons, Core Power. Exception: a sustained effect (the rules' sustainable())
## may be auto-kept, paying only its sustain cost. Reactions fire when their prompt comes up
## (one auto reaction per unit); other autos fire at the start of the unit's turn in bar order.
## Saved with the bar layout (user://action_layouts/<unit>.json, key "auto").

## Tech actions that are attack rolls.
const TECH_ATTACKS := ["invade", "fragment_signal", "full_tech", "tech_attack"]
## Reactions that make an attack.
const ATTACK_REACTIONS := ["act_overwatch", "reaction:overwatch"]


## "" if the action can be set to auto, else why not (shown on right-click).
static func can_auto(a: Dictionary) -> String:
	if a.is_empty():
		return "Nothing there."
	if a.get("sustain") is Dictionary:
		return ""  # keeping a sustained effect going: only its sustain cost, no new attack roll
	var id := String(a.get("id", ""))
	var type := String(a.get("type", ""))
	var kind := String(a.get("kind", ""))
	if id == "core" or String(a.get("group", "")) == "core":
		return "Core Power is used by hand."
	if id in ATTACK_REACTIONS:
		return "Overwatch makes an attack: attacks are always yours to make."
	if kind in ["attack", "barrage"] or type in ActionBar.ATTACK_TYPES or type in TECH_ATTACKS or ActionBar.panel_of(a) in [1, 2, 3]:
		return "Attacks are always yours to make."
	var lo: Dictionary = a.get("lockout", {})
	if String(lo.get("kind", "")) in ["uses", "loading"]:
		return "Limited or Loading: used by hand."
	for e: Dictionary in a.get("extras", []):
		if String(e.get("icon", "")) == "generic_item":
			return "It has limited uses: used by hand."
	var freq := String(a.get("frequency", "")).to_lower()
	if "scene" in freq or "mission" in freq:
		return "Once per scene: used by hand."
	return ""


static func is_reaction(a: Dictionary) -> bool:
	return String(a.get("cost", "")) == "reaction" or String(a.get("group", "")) == "reactions"


## The saved autos for a unit ({action id: true}).
static func autos_for(unit_id: String) -> Dictionary:
	var path := ActionBar.LAYOUT_DIR + (unit_id if unit_id != "" else "default") + ".json"
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return (d as Dictionary).get("auto", {}) if d is Dictionary else {}


## The answer to a reaction prompt when that reaction is on auto ({} = ask the player).
## `q` is the pending question {unit, reaction, context}.
static func reaction_answer(q: Dictionary, autos: Dictionary) -> Dictionary:
	var r := String(q.get("reaction", ""))
	if r == "":
		return {}
	for id: String in autos:
		if not bool(autos[id]):
			continue
		if id == "act_" + r or id == "reaction:" + r or id.ends_with(":" + r):
			if id in ATTACK_REACTIONS:
				return {}
			return {"take": true}
	return {}


## This turn's autos in bar order: [{action, skip: "" or why}]. `resources` is
## ActionCatalog.resources() (heat [now, cap], economy).
static func turn_plan(order: Array, autos: Dictionary, resources: Dictionary) -> Array:
	var out: Array = []
	var heat: Array = resources.get("heat", [])
	var extra_heat := 0
	for a: Dictionary in order:
		var id := String(a.get("id", ""))
		if not bool(autos.get(id, false)) or is_reaction(a):
			continue
		var why := can_auto(a)
		if why == "" and not bool(a.get("enabled", true)):
			why = String(a.get("reason", "not available now"))
		var p: Dictionary = a.get("preview", {})
		var h := 0
		if p.get("heat") is Array:
			h = int((p["heat"] as Array)[-1])
		elif p.has("heat"):
			h = int(p["heat"])
		if why == "" and not heat.is_empty() and int(heat[0]) + extra_heat + h > int(heat[1]):
			why = "would overheat"
		if why == "":
			extra_heat += h
		out.append({"action": a, "skip": why})
	return out


## The action to submit for an auto ability: no target, the last target if still legal, or
## the nearest legal one (allies for Bolster-type help, enemies otherwise). {} if none.
static func action_for(state: GameState, engine: RulesEngine, unit_id: String, a: Dictionary, last_target: String = "") -> Dictionary:
	var params: Dictionary = (a.get("params", {}) as Dictionary).duplicate()
	var type := String(a.get("type", ""))
	if a.get("sustain") is Dictionary:
		return {"type": "sustain", "actor": unit_id, "params": (a["sustain"] as Dictionary).duplicate()}
	var base := {"type": type, "actor": unit_id, "params": params}
	if String(a.get("kind", "")) != "tech":
		return base if engine.validate(state, base).ok else {}
	var me := state.unit(unit_id)
	var allies := type in ["bolster"]
	var cands: Array = []
	if last_target != "":
		cands.append(last_target)
	var others: Array = []
	for u: Unit in state.units.values():
		if u.id != unit_id and not u.destroyed and (u.side == me.side) == allies:
			others.append(u)
	others.sort_custom(func(x: Unit, y: Unit) -> bool: return state.map.grid.distance(me.cell, x.cell) < state.map.grid.distance(me.cell, y.cell))
	for u: Unit in others:
		cands.append(u.id)
	for t: String in cands:
		var act := {"type": type, "actor": unit_id, "params": params.merged({"target": t}, true)}
		if engine.validate(state, act).ok:
			return act
	return {}
