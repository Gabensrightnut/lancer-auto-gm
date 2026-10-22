class_name Environments
extends RefCounted
## Rules environments for the whole battle (state.environments: lancer-data environments.json
## ids, set by the mission generator from the world's weather). Each one follows its text in
## that data (the core book's environments). "During storms" environments count as stormy for
## the whole battle while they're in the list.
##
## How they reach the rules:
## - Standing effects (resistances, soft cover, Difficulty, flight on Boost, no Boost) go in
##   each unit's counters["env_effects"], which Effects.all() reads. sync() refreshes them; the
##   engine calls it before every action and at combat start.
## - Turn start/end, round end and movement hooks below (TurnRules, MoveActions call them).
## - Point rules elsewhere: weapons gain AP (Attacks), +1 heat (Combat, Attacks, abilities),
##   difficult movement in the ocean (Movement), Immobilized instead of Slowed (Combat.add_status),
##   no fall damage (Combat.fall_unit).
## Readings the text leaves open are PROVISIONAL (docs/RULES_TODO.md "Environments").

const REF := "Core: Environments (lancer-data environments.json)"
const FLORA_REF := "Core: Environments, Dangerous Flora and Fauna"
const COLD_HOLD := "Extreme cold"
const SINKING_HOLD := "Sinking"
const NARRATIVE := ["env_tombworld", "env_spireworld", "env_holyworld", "env_primordealworld"]


static func active(state: GameState, id: String) -> bool:
	return state != null and state.environments.has(id)


## Mechs (and NPC mechs). Hostile flora are characters but not mechs. PROVISIONAL: NPCs count
## as mechs.
static func is_mech(u: Unit) -> bool:
	return (u.kind == Unit.KIND_MECH or u.kind == Unit.KIND_NPC) and not u.counters.get("flora", false)


static func is_character(u: Unit) -> bool:
	return u.kind != Unit.KIND_DEPLOYABLE


## Name and rule text of each environment in play, for the HUD.
static func listing(state: GameState, db: ContentDB = null) -> Array:
	var out: Array = []
	for id: Variant in state.environments:
		var e: Dictionary = db.get_entry("environments", String(id)) if db != null else {}
		out.append({"id": id, "name": e.get("name", id), "text": NPCBuilder._text(e.get("description", "")),
			"automated": not NARRATIVE.has(String(id)), "rule_ref": REF})
	return out


## Refreshes every unit's standing environment effects.
static func sync(state: GameState) -> void:
	for u: Unit in state.units.values():
		var list := effects_for(state, u)
		if list.is_empty():
			u.counters.erase("env_effects")
		else:
			u.counters["env_effects"] = list


static func effects_for(state: GameState, u: Unit) -> Array:
	var out: Array = []
	if state.environments.is_empty() or not is_character(u):
		return out
	var mech := is_mech(u)
	if mech and active(state, "env_extremecold"):
		out.append(_e({"kind": "resist", "damage": ["Heat"]}, "Extreme cold"))
	if active(state, "env_thinatmosphere"):
		out.append(_e({"kind": "resist", "damage": ["Explosive"]}, "Thin atmosphere"))
	if mech and active(state, "env_particulatestorms"):
		out.append(_e({"kind": "soft_cover_aura", "self_only": true}, "Particulate storm"))
	if active(state, "env_disruptivestorms"):
		for on in ["tech_attack", "save", "check"]:
			var d := {"kind": "accuracy", "on": on, "value": -1}
			if on != "tech_attack":
				d["skill"] = "systems"
			out.append(_e(d, "Disruptive storm"))
	if mech and active(state, "env_lowgravity"):
		out.append(_e({"kind": "boost_flight"}, "Low gravity"))
	if mech and active(state, "env_highgravity"):
		out.append(_e({"kind": "no_boost"}, "High gravity"))
	return out


static func _e(d: Dictionary, label: String) -> Dictionary:
	d["label"] = label
	d["rule_ref"] = REF
	d["environment"] = true
	return d


# --- Point rules ----------------------------------------------------------------------

## Corrosive atmosphere: all weapons gain AP.
static func weapons_ap(state: GameState) -> bool:
	return active(state, "env_corrosiveatmosphere")


## Extreme heat: +1 to each instance of heat a system or weapon inflicts (on its user or
## others). PROVISIONAL: which heat counts (see RULES_TODO).
static func gear_heat(state: GameState, amount: int) -> int:
	return amount + 1 if amount > 0 and active(state, "env_extremeheat") else amount


## Ocean world: mechs move as though in difficult terrain unless flying or with an EVA Module.
static func ocean_slows(state: GameState, u: Unit) -> bool:
	if not active(state, "env_oceanworld") or not is_mech(u):
		return false
	for s: Dictionary in u.loadout.get("systems", []):
		if s.get("id", "") == "ms_eva_module":
			return false
	return true


## High gravity: a mech that would be Slowed is Immobilized instead.
static func slowed_becomes(state: GameState, u: Unit, status: String) -> String:
	if status == "Slowed" and active(state, "env_highgravity") and is_mech(u):
		return "Immobilized"
	return status


## Low gravity: characters never take damage from falling.
static func no_fall_damage(state: GameState) -> bool:
	return active(state, "env_lowgravity")


# --- Turns and rounds -----------------------------------------------------------------

static func turn_started(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if active(state, "env_moltenworld") and is_character(u) and in_lava(state, u):
		events.append_array(_lava(state, u))
	return events


static func turn_ending(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if u.destroyed or not is_character(u) or not Combat.is_present(u):
		return events
	if active(state, "env_extremecold") and is_mech(u) and not u.turn.get("moved", false) and not u.counters.has("env_cold"):
		u.counters["env_cold"] = true
		events.append({"type": "effect_triggered", "unit": u.id, "effect": "Extreme cold", "target": u.id,
			"text": "Didn't move or Boost: frozen in place until a Hull save (quick action) breaks it free.", "rule_ref": REF})
		events.append_array(Combat.add_status(state, u, "Immobilized", COLD_HOLD))
	if active(state, "env_sinkingworld") and is_mech(u) and int(u.turn.get("spaces_moved", 0)) <= 1 and not u.counters.has("env_sinking"):
		if u.has_status("Slowed"):
			u.counters["env_sinking"] = true
			events.append({"type": "effect_triggered", "unit": u.id, "effect": "Sinking world", "target": u.id,
				"text": "Slowed and barely moved: it sinks (Immobilized) until it or an adjacent mech passes a Hull save as a full action.", "rule_ref": REF})
			events.append_array(Combat.add_status(state, u, "Immobilized", SINKING_HOLD))
		elif not u.has_status("Immobilized"):
			u.counters["env_sinking_slowed"] = true
			events.append({"type": "effect_triggered", "unit": u.id, "effect": "Sinking world", "target": u.id,
				"text": "Moved 1 space or less: Slowed by the mud.", "rule_ref": REF})
			events.append_array(Combat.add_status(state, u, "Slowed", SINKING_HOLD))
	if active(state, "env_extremesun"):
		var who: Array = [u]
		if Rulings.ask(state, "extremesun_turns") == "every_turn":
			who = state.units.values().filter(func(o: Unit) -> bool: return is_character(o) and Combat.is_present(o))
		for o: Unit in who:
			if not in_shade(state, o):
				var roll := state.dice.die(6)
				events.append({"type": "effect_triggered", "unit": o.id, "effect": "Extreme sun", "target": o.id, "roll": roll,
					"text": "Not in shade at the end of a turn: 1d6 heat.", "rule_ref": REF})
				events.append_array(Combat.apply_heat(state, o, roll, "Extreme sun"))
	if active(state, "env_dangeroustorms") and not next_to_hard_cover(state, u):
		events.append({"type": "effect_triggered", "unit": u.id, "effect": "Dangerous storm", "target": u.id,
			"text": "Not next to an object that gives hard cover: 2 energy damage (AP).", "rule_ref": REF})
		events.append_array(Combat.deal_damage(state, u, [{"type": "Energy", "amount": 2}], {"ap": true, "source": "environment"}))
	if active(state, "env_particulatestorms") and u.kind == Unit.KIND_PILOT and not u.counters.has("mounted_in") and not u.destroyed:
		events.append({"type": "effect_triggered", "unit": u.id, "effect": "Particulate storm", "target": u.id,
			"text": "A pilot outside their mech in the storm: 1 kinetic damage (AP).", "rule_ref": REF})
		events.append_array(Combat.deal_damage(state, u, [{"type": "Kinetic", "amount": 1}], {"ap": true, "source": "environment"}))
	return events


## End of each round: lightning (electrical storms) and earthquakes.
static func round_ending(state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if active(state, "env_electricalstorms"):
		var chars: Array = state.units.values().filter(func(o: Unit) -> bool: return is_character(o) and Combat.is_present(o))
		chars.sort_custom(func(a: Unit, b: Unit) -> bool: return a.id < b.id)
		if not chars.is_empty():
			var u: Unit = chars[state.dice.die(chars.size()) - 1]
			# +1 Difficulty per level of Size. PROVISIONAL: Size 1/2 adds none.
			var diff := int(u.size)
			var check := Combat.skill_check(state, u, "engineering", "Lightning strike: Engineering save", Combat.CHECK_TARGET, 0, diff,
				[{"label": "Size", "kind": "difficulty", "type": "difficulty", "value": diff, "rule_ref": REF}] if diff > 0 else [], true)
			events.append({"type": "effect_triggered", "unit": u.id, "effect": "Electrical storm", "target": u.id,
				"text": "Lightning picks a character at random: Engineering save or Stunned until the end of its next turn.", "rule_ref": REF})
			events.append({"type": "skill_check", "unit": u.id, "check": check, "rule_ref": REF})
			if not check["success"]:
				events.append_array(Combat.add_status(state, u, "Stunned", "Electrical storm", u.id))
	if active(state, "env_earthquakes"):
		var roll := state.dice.die(6)
		events.append({"type": "environment_roll", "environment": "env_earthquakes", "roll": roll,
			"text": "Earthquake roll: on a 1, every mech that isn't flying makes a Hull save or is knocked Prone.", "rule_ref": REF})
		if roll == 1:
			var ids: Array = state.units.keys()
			ids.sort()
			for id: Variant in ids:
				var u: Unit = state.units[id]
				if not is_mech(u) or not Combat.is_present(u) or u.flying:
					continue
				var check := Combat.skill_check(state, u, "hull", "Earthquake: Hull save", Combat.CHECK_TARGET, 0, 0, [], true)
				events.append({"type": "skill_check", "unit": u.id, "check": check, "rule_ref": REF})
				if not check["success"]:
					events.append_array(Combat.add_status(state, u, "Prone", "Earthquake"))
	return events


# --- Movement -------------------------------------------------------------------------

## After `u` moves along `path` ([[x, y, level]...]): spaces moved this turn, lava, flora.
static func moved(state: GameState, u: Unit, path: Array) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if state.active_unit == u.id:
		u.turn["spaces_moved"] = int(u.turn.get("spaces_moved", 0)) + maxi(0, path.size() - 1)
	if state.environments.is_empty() or not is_character(u):
		return events
	if active(state, "env_moltenworld") and state.active_unit == u.id and not u.turn.get("lava_hit", false) and in_lava(state, u):
		events.append_array(_lava(state, u))
	if active(state, "env_dangerousflorafauna"):
		events.append_array(_flora_moved(state, u, path))
	return events


## Molten world: in molten rock or lava (a column tagged "lava" or "molten", standing in it).
const LAVA_TAGS := ["lava", "molten"]
static func in_lava(state: GameState, u: Unit) -> bool:
	if u.flying:
		return false
	for c in state.map.grid.footprint(u.cell, u.size):
		var col := state.map.column(c)
		if col != null and LAVA_TAGS.any(func(t: String) -> bool: return col.has_tag(t)) and u.level <= col.ground:
			return true
	return false


static func _lava(state: GameState, u: Unit) -> Array[Dictionary]:
	u.turn["lava_hit"] = true
	var events: Array[Dictionary] = [{"type": "effect_triggered", "unit": u.id, "effect": "Molten world", "target": u.id,
		"text": "In molten rock: 5 energy damage (AP) and 3 heat.", "rule_ref": REF}]
	events.append_array(Combat.deal_damage(state, u, [{"type": "Energy", "amount": 5}], {"ap": true, "source": "environment"}))
	events.append_array(Combat.apply_heat(state, u, 3, "Molten world"))
	return events


## Next to an object that grants hard cover. PROVISIONAL: terrain right next to it at least
## as tall as it (the same test as hard cover against attacks).
static func next_to_hard_cover(state: GameState, u: Unit) -> bool:
	var b := Sight.body_of(state, u)
	for c in b.cells:
		for n in state.map.grid.neighbors(c):
			if b.cells.has(n):
				continue
			var col := state.map.column(n)
			if col != null and col.ground >= b.level + b.height:
				return true
	return false


## In shade. PROVISIONAL: a column tagged "shade", solid ground overhead, or next to an object
## that gives hard cover.
static func in_shade(state: GameState, u: Unit) -> bool:
	for c in state.map.grid.footprint(u.cell, u.size):
		var col := state.map.column(c)
		if col != null and (col.has_tag("shade") or u.level < col.ground):
			return true
	return next_to_hard_cover(state, u)


# --- Hostile flora ----------------------------------------------------------------------

## Hostile flora: an immobile character with Size 1-2, 5 HP and Evasion 10 (dangerous flora
## and fauna). It takes no turns.
static func make_flora(id: String, cell: Vector2i, size: float = 1.0, name: String = "Hostile flora") -> Unit:
	var u := Unit.new()
	u.id = id
	u.name = name
	u.kind = Unit.KIND_NPC
	u.side = "wildlife"
	u.controller = "gm"
	u.cell = cell
	u.size = clampf(size, 1.0, 2.0)
	u.max_hp = 5
	u.hp = 5
	u.evasion = 10
	u.edef = 10
	u.speed = 0
	u.max_structure = 1
	u.structure = 1
	u.max_stress = 1
	u.stress = 1
	u.counters["flora"] = true
	u.loadout = {"weapons": [], "systems": [], "effects": [], "traits": [{"name": "Hostile flora", "automated": true,
		"text": "Characters that move next to it make a Hull save or take 3 kinetic damage and are Immobilized until it's destroyed."}]}
	return u


static func _flora_moved(state: GameState, u: Unit, path: Array) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if u.counters.get("flora", false):
		return events
	for f: Unit in state.units.values():
		if not f.counters.get("flora", false) or not Combat.is_present(f):
			continue
		var touched := false
		for i in range(1, path.size()):
			var p: Array = path[i]
			var fp := state.map.grid.footprint(Vector2i(p[0], p[1]), u.size)
			if state.map.grid.footprint_distance(fp, state.map.grid.footprint(f.cell, f.size)) <= 1:
				touched = true
				break
		if not touched:
			continue
		var check := Combat.skill_check(state, u, "hull", "Hostile flora: Hull save", Combat.CHECK_TARGET, 0, 0, [], true)
		events.append({"type": "skill_check", "unit": u.id, "check": check, "rule_ref": FLORA_REF})
		if not check["success"]:
			events.append({"type": "effect_triggered", "unit": f.id, "effect": "Hostile flora", "target": u.id,
				"text": "Caught: 3 kinetic damage and Immobilized until the flora is destroyed.", "rule_ref": FLORA_REF})
			events.append_array(Combat.deal_damage(state, u, [{"type": "Kinetic", "amount": 3}], {"source": f.id}))
			events.append_array(Combat.add_status(state, u, "Immobilized", "flora:" + f.id))
	return events


## Ends Immobilized from flora that has been destroyed.
static func release_flora(state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for u: Unit in state.units.values():
		if not u.has_status("Immobilized"):
			continue
		var src := String(u.statuses["Immobilized"].get("source", ""))
		if src.begins_with("flora:"):
			var f := state.unit(src.substr(6))
			if f == null or f.destroyed:
				events.append_array(Combat.remove_status(u, "Immobilized", "the flora was destroyed"))
	return events


# --- Breaking free --------------------------------------------------------------------

## Ends an environment's hold after a successful Hull save. `what`: "cold" or "sinking".
static func release(u: Unit, what: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var src := COLD_HOLD if what == "cold" else SINKING_HOLD
	u.counters.erase("env_" + what)
	if what == "sinking":
		u.counters.erase("env_sinking_slowed")
	for st in ["Immobilized", "Slowed"]:
		if u.has_status(st) and String(u.statuses[st].get("source", "")) == src:
			events.append_array(Combat.remove_status(u, st, "broke free"))
	return events


## Is `u` held by the sinking mud (Slowed or Immobilized by it)?
static func sinking(u: Unit) -> bool:
	return u.counters.has("env_sinking") or u.counters.has("env_sinking_slowed")
