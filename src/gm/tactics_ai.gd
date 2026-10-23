class_name TacticsAi
extends RefCounted
## Picks a whole turn (move + actions) for one unit by scoring options (a utility system).
## Used for enemies and for AI squadmates alike. It plans on an AiKnowledge copy (what that
## side may know) with RulesQueries, so its answers match the rules; the director then
## submits the chosen actions to the rules engine like any player.
##
## Score of a turn = where it ends up (range for its role, cover, enemy reach, allies,
## objectives) + the best action package there (expected damage, Lock On, Hide, Scan, cooling
## down) + a little seeded noise. Role weights and stances are data/game/gm/behaviors.json;
## personality dials are GmSettings.
##
## orders (all optional): {"stance": "aggressive"/"defensive"/"support"/"hold"/"follow",
##   "focus": unit id, "follow": unit id, "role": role name, "zones": [[x, y], ...],
##   "zone_weight": float}

## Destinations scored in full (cover, attacks) after a cheap first pass.
const CANDIDATES := 10
## Assumed speed and weapon range for enemies whose stats are unknown.
const UNKNOWN_SPEED := 4
const UNKNOWN_RANGE := 8

var settings: GmSettings
var roles: Dictionary
var stances: Dictionary
## Role x sitrep weights and plain intents (data/game/gm/objective_priorities.json).
var priorities: Dictionary
const PRIORITIES_FILE := "res://data/game/gm/objective_priorities.json"
## Mixed into the noise seed (the director sets the real game seed) so replays match.
var seed_salt := 0


func _init(gm: GmSettings = null) -> void:
	settings = gm if gm != null else GmSettings.from_preset("Standard")
	var b := GmSettings.load_json(GmSettings.BEHAVIORS_FILE)
	roles = b.get("roles", {})
	stances = b.get("stances", {})
	priorities = GmSettings.load_json(PRIORITIES_FILE)


## Returns {"steps": [action dicts to submit in order], "log": String, "score": float}.
## Steps never include start_turn / end_turn.
func plan_turn(know: AiKnowledge, unit_id: String, orders: Dictionary = {}) -> Dictionary:
	var s := know.state
	var u := s.unit(unit_id)
	var who := _name(u)
	if u.has_status("Shut Down"):
		return {"steps": [_act(u, "boot_up")], "log": "%s boots its reactor back up." % who, "score": 0.0}
	if u.has_status("Stunned"):
		return {"steps": [], "log": "%s is Stunned and can't act." % who, "score": 0.0}
	var ctx := _context(know, u, orders)
	var home_cell := u.cell
	var home_level := u.level
	var dests := _destinations(s, u, ctx)
	for d: Dictionary in dests:
		d["cheap"] = _position_score(s, u, d, ctx, false)["score"]
	dests.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["cheap"] > b["cheap"])
	var keep := dests.slice(0, CANDIDATES)
	if not keep.any(func(d: Dictionary) -> bool: return d["cost"] == 0):
		keep.append(dests.filter(func(d: Dictionary) -> bool: return d["cost"] == 0)[0])
	var best := {"total": -INF}
	var moved_before: bool = u.turn.get("moved", false)
	for d: Dictionary in keep:
		u.cell = d["cell"]
		u.level = d["level"]
		u.turn["moved"] = moved_before or d["cost"] > 0  # Ordnance must fire before moving.
		var pos := _position_score(s, u, d, ctx, true)
		var pkg := _best_package(know, u, ctx)
		var total: float = pos["score"] + pkg["value"] + ctx["rng"].randfn(0.0, settings.randomness * 1.5)
		if total > best["total"]:
			best = {"total": total, "dest": d, "pos": pos, "pkg": pkg}
	u.turn["moved"] = moved_before
	# Shooting from where it stands (e.g. Ordnance, which must fire before moving): it can
	# still use its standard move afterwards to reposition.
	var after := {}
	if best["dest"]["cost"] == 0 and best["pkg"]["attacks"] and not ctx["hold"] and _can_move(u):
		var bar: float = best["pos"]["score"] + 0.3
		for d: Dictionary in dests:
			if d["cost"] > 0 and d["cheap"] > bar:
				bar = d["cheap"]
				after = d
	# Nothing to shoot from anywhere: spend a quick action on a Boost to close in (or pull back).
	var boost := {}
	if not best["pkg"]["attacks"] and best["pkg"]["quick_left"] >= 1 and not ctx["hold"] and _can_boost(u):
		u.cell = best["dest"]["cell"]
		u.level = best["dest"]["level"]
		boost = _best_boost(s, u, ctx, best["pos"]["score"])
	u.cell = home_cell
	u.level = home_level
	var steps: Array = []
	var dest: Dictionary = best["dest"]
	if dest["cost"] > 0:
		steps.append(_act(u, "move", {"to": [dest["cell"].x, dest["cell"].y], "level": dest["level"]}))
	steps.append_array(best["pkg"]["steps"])
	if not after.is_empty():
		steps.append(_act(u, "move", {"to": [after["cell"].x, after["cell"].y], "level": after["level"]}))
	if not boost.is_empty():
		steps.append(_act(u, "boost", {"to": [boost["cell"].x, boost["cell"].y], "level": boost["level"]}))
	return {"steps": steps, "log": _explain(u, ctx, best, boost, after), "score": best["total"]}


## The unit's role: from orders, from the unit (loadout.ai_role), or guessed from its weapons.
func role_of(u: Unit, orders: Dictionary = {}) -> String:
	var r := str(orders.get("role", u.loadout.get("ai_role", "")))
	if roles.has(r):
		return r
	var longest := 0
	var all_melee := true
	for w: Dictionary in u.loadout.get("weapons", []):
		longest = maxi(longest, _reach(w))
		all_melee = all_melee and Weapons.is_melee(w)
	if all_melee:
		return "striker"
	return "artillery" if longest >= 15 else "striker"


# --- Context -------------------------------------------------------------------------------

## The role x sitrep weights for a unit (objective_priorities.json): the defaults, then the
## role's "_any" row, then its row for the sitrep. "intent" has the objective's name filled in.
static func priority(table: Dictionary, role: String, sitrep: String) -> Dictionary:
	var out: Dictionary = (table.get("default", {}) as Dictionary).duplicate()
	var rows: Dictionary = table.get("roles", {}).get(role, {})
	out.merge(rows.get("_any", {}), true)
	out.merge(rows.get(sitrep, {}), true)
	var names: Dictionary = table.get("zone_names", {})
	out["intent"] = String(out.get("intent", "")).replace("{zone}", String(names.get(sitrep, names.get("_any", "objective"))))
	return out


func _context(know: AiKnowledge, u: Unit, orders: Dictionary) -> Dictionary:
	var s := know.state
	var stance: Dictionary = stances.get(str(orders.get("stance", "")), {})
	var role := role_of(u, orders)
	var profile: Dictionary = (roles.get(role, roles.get("striker", {})) as Dictionary).duplicate()
	# The mission's objective and this unit's job weigh every choice (objective_priorities.json).
	var prio := priority(priorities, role, str(orders.get("sitrep", "")))
	for k: Array in [["cover_weight", "cover"], ["threat_weight", "threat"], ["attack_weight", "attack"]]:
		profile[k[0]] = float(profile.get(k[0], 1.0)) * float(prio.get(k[1], 1.0))
	var aggression := settings.aggression + float(stance.get("aggression", 0.0))
	var caution := settings.caution + float(stance.get("caution", 0.0))
	var hurt := _hurt(u)
	caution += hurt * 0.6  # Damaged units get careful (dial: caution).
	var enemies := know.enemies_of(u)
	var reach := {}
	for e in enemies:
		var r := 0
		if know.knows_stats(e.id):
			for w: Dictionary in e.loadout.get("weapons", []):
				r = maxi(r, _reach(w))
			reach[e.id] = e.speed + r
		else:
			reach[e.id] = UNKNOWN_SPEED + UNKNOWN_RANGE
	var zones := {}
	for c: Variant in orders.get("zones", []):
		zones[Vector2i(int(c[0]), int(c[1]))] = true
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed_salt, s.round_number, u.id, s.acted.size(), u.cell])
	return {
		"know": know, "role": role, "profile": profile, "stance": str(orders.get("stance", "")),
		"aggression": clampf(aggression, 0.0, 1.5), "caution": clampf(caution, 0.0, 1.5),
		"focus": settings.focus_fire, "focus_target": str(orders.get("focus", "")),
		"follow": str(orders.get("follow", "")) if stance.get("follow", false) or orders.has("follow") else "",
		"hold": bool(stance.get("hold", false)),
		"tech_bonus": float(stance.get("tech_bonus", 0.0)), "ally_bonus": float(stance.get("ally_bonus", 0.0)),
		"enemies": enemies, "allies": know.allies_of(u), "reach": reach, "hurt": hurt,
		"pref_range": _preferred_range(u, profile), "keep_away": int(profile.get("keep_away", 0)),
		"zones": zones, "zone_weight": float(orders.get("zone_weight", 0.0)) * float(prio.get("zone", 1.0)), "rng": rng,
		"no_hide": bool(orders.get("no_hide", false)), "hide_w": float(prio.get("hide", 1.0)), "intent": String(prio.get("intent", "")),
		"foot": u.on_foot(), "garrison": float(prio.get("garrison", 0.0)),
	}


func _preferred_range(u: Unit, profile: Dictionary) -> float:
	var pref: Variant = profile.get("preferred_range", "weapon")
	if pref is float or pref is int:
		return float(pref)
	var best_avg := -1.0
	var best_reach := 1
	var longest := 1
	for w: Dictionary in u.loadout.get("weapons", []):
		longest = maxi(longest, _reach(w))
		if avg_damage(w) > best_avg:
			best_avg = avg_damage(w)
			best_reach = _reach(w)
	# Stand a little inside the best weapon's reach so a small enemy move doesn't break it.
	return float(longest if pref == "max" else best_reach) * (0.8 if pref == "max" else 1.0)


static func _hurt(u: Unit) -> float:
	var h := 0.0
	if u.max_hp > 0:
		h = 1.0 - float(u.hp) / u.max_hp
	if u.max_structure > 0:
		h = maxf(h, float(u.max_structure - u.structure) / u.max_structure)
	if u.heat_cap > 0:
		h = maxf(h, float(u.heat) / u.heat_cap - 0.3)
	return clampf(h, 0.0, 1.0)


# --- Where to go ---------------------------------------------------------------------------

func _destinations(s: GameState, u: Unit, ctx: Dictionary) -> Array:
	var out: Array = [{"cell": u.cell, "level": u.level, "cost": 0}]
	if ctx["hold"] or not _can_move(u):
		return out
	for sp: Dictionary in RulesQueries.reachable(s, u.id)["spaces"]:
		if sp.get("ruling", false):
			continue
		out.append({"cell": Vector2i(int(sp["cell"][0]), int(sp["cell"][1])), "level": int(sp["level"]), "cost": int(sp["cost"])})
	return out


static func _can_move(u: Unit) -> bool:
	return not (u.has_status("Immobilized") or u.has_status("Stunned") or u.turn.get("braced", false)) \
		and int(u.turn.get("move_spent", 0)) < u.speed and not u.turn.get("stood_up", false)


static func _can_boost(u: Unit) -> bool:
	return not (u.has_status("Immobilized") or u.has_status("Slowed") or u.has_status("Prone"))


## How good it is to end the turn at `d`. Cheap pass skips cover (line-of-sight traces).
func _position_score(s: GameState, u: Unit, d: Dictionary, ctx: Dictionary, full: bool) -> Dictionary:
	var grid := s.map.grid
	var cell: Vector2i = d["cell"]
	var profile: Dictionary = ctx["profile"]
	var score := 0.0
	var notes := {}
	var dmin := INF
	var threat := 0.0
	var cover_sum := 0.0
	var cover_n := 0
	var covers := {}
	if full and not ctx["enemies"].is_empty():
		covers = RulesQueries.cover_at(s, u.id, cell, int(d["level"]))
	for e: Unit in ctx["enemies"]:
		var dist := grid.distance(cell, e.cell)
		dmin = minf(dmin, dist)
		if dist <= int(ctx["reach"][e.id]):
			var c: Dictionary = covers.get(e.id, {})
			var cv := 0.0
			match str(c.get("cover", "none")):
				"hard":
					cv = 1.0
				"soft":
					cv = 0.5
			if full and not c.get("los", true):
				cv = 1.0  # Out of its sight entirely.
			cover_sum += cv
			cover_n += 1
			threat += 1.0 - 0.5 * cv
	var cover_avg := cover_sum / cover_n if cover_n > 0 else 0.0
	var caution: float = ctx["caution"]
	if dmin < INF:
		score -= float(profile.get("range_weight", 1.0)) * absf(dmin - ctx["pref_range"]) / 3.0
		if dmin < ctx["keep_away"]:
			score -= (ctx["keep_away"] - dmin) * 0.8 * caution
	score -= float(profile.get("threat_weight", 1.0)) * caution * threat * 0.6
	if full:
		score += float(profile.get("cover_weight", 1.0)) * caution * cover_avg * 2.0
		notes["cover"] = cover_avg
	var ally_w: float = float(profile.get("ally_weight", 0.0)) + ctx["ally_bonus"]
	if ally_w > 0.0 and not ctx["allies"].is_empty():
		var amin := INF
		for a: Unit in ctx["allies"]:
			amin = minf(amin, grid.distance(cell, a.cell))
		score -= ally_w * maxf(0.0, amin - 3.0) / 3.0
	if ctx["follow"] != "":
		var leader := s.unit(ctx["follow"])
		if leader != null and leader.id != u.id:
			score -= 1.5 * maxf(0.0, grid.distance(cell, leader.cell) - 2.0) / 2.0
	if not ctx["zones"].is_empty():
		if ctx["zones"].has(cell):
			score += ctx["zone_weight"]
			notes["zone"] = true
		else:
			var zmin := INF
			for z: Vector2i in ctx["zones"]:
				zmin = minf(zmin, grid.distance(cell, z))
			score -= ctx["zone_weight"] * minf(zmin, 12.0) / 12.0
	if ctx["garrison"] > 0.0 and Garrison.on(s) and Garrison.is_room(s.map, cell, int(d["level"])) and Garrison.at_window(s, cell):
		score += ctx["garrison"]  # a firing position inside a building, at a window (hard cover)
		notes["garrison"] = true
	score -= int(d["cost"]) * 0.02  # Ties go to shorter moves.
	return {"score": score, "notes": notes, "threat": threat}


func _best_boost(s: GameState, u: Unit, ctx: Dictionary, here_score: float) -> Dictionary:
	var best := {}
	var best_score := here_score + 0.4  # Only worth a quick action if clearly better.
	for sp: Dictionary in RulesQueries.reachable(s, u.id, Movement.MODE_BOOST)["spaces"]:
		if sp.get("ruling", false):
			continue
		var d := {"cell": Vector2i(int(sp["cell"][0]), int(sp["cell"][1])), "level": int(sp["level"]), "cost": 0}
		var sc: float = _position_score(s, u, d, ctx, false)["score"]
		if sc > best_score:
			best_score = sc
			best = d
	return best


# --- What to do there ----------------------------------------------------------------------

## The best set of actions from where the unit now stands (in the knowledge copy).
## Returns {value, steps, attacks: bool, quick_left, text, kind, target, chance}.
func _best_package(know: AiKnowledge, u: Unit, ctx: Dictionary) -> Dictionary:
	var s := know.state
	var profile: Dictionary = ctx["profile"]
	var atk_w: float = float(profile.get("attack_weight", 1.0)) * (0.5 + ctx["aggression"])
	var tech_w: float = float(profile.get("tech_weight", 0.5)) + ctx["tech_bonus"]
	var options: Array = [{"value": 0.0, "steps": [], "attacks": false, "quick_left": 2, "text": "", "kind": "none"}]
	# Every legal single attack: {w, t, chance, value, lock_chance, lockable}
	var shots: Array = []
	for w: Dictionary in u.loadout.get("weapons", []):
		for t: Unit in ctx["enemies"]:
			var p := RulesQueries.attack_preview(s, u.id, String(w["key"]), t.id)
			if not p.get("ok", false):
				continue
			var dmg := avg_damage(w)
			var factor := _target_factor(know, t, ctx, p["hit_chance"] * dmg)
			var lock_chance: float = p["hit_chance"]
			var lockable := false
			if not ctx["foot"] and not t.has_status("Lock On") and Attacks.tech_target_check(s, u, t).ok:
				lockable = true
				lock_chance = RulesQueries.hit_chance(p["bonus"], p["accuracy"] - p["difficulty"] + 1, p["target_number"])
			shots.append({"w": w, "t": t, "chance": p["hit_chance"], "dmg": dmg, "factor": factor,
				"value": p["hit_chance"] * dmg * factor * atk_w, "lock_chance": lock_chance, "lockable": lockable})
	shots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["value"] > b["value"])
	var skirm: Array = shots.filter(func(x: Dictionary) -> bool: return x["w"].get("size", "") != "Superheavy")
	if not skirm.is_empty():
		var top: Dictionary = skirm[0]
		# People on foot attack with Fight: a full action, or quick with a Sidearm (Core p.74).
		var quick_fight: bool = Weapons.has_tag(top["w"], "tg_sidearm")
		var sk_step := _act(u, "fight" if ctx["foot"] else "skirmish", {"weapon": top["w"]["key"], "target": top["t"].id})
		var base := {"value": top["value"], "steps": [sk_step], "attacks": true, "quick_left": 1 if not ctx["foot"] or quick_fight else 0,
			"text": "fires %s at %s (%d%% to hit)" % [top["w"]["name"], _name(top["t"]), roundi(top["chance"] * 100)],
			"kind": "skirmish", "target": top["t"].id, "chance": top["chance"]}
		options.append(base)
		# Lock On first, then shoot with +1 Accuracy.
		for x: Dictionary in skirm.slice(0, 4):
			# Not Ordnance: Lock On is an action, and Ordnance must be the first thing done.
			if x["lockable"] and not Weapons.has_tag(x["w"], "tg_ordnance"):
				var v: float = x["lock_chance"] * x["dmg"] * x["factor"] * atk_w + 0.15 * tech_w * ctx["allies"].size()
				options.append({"value": v, "steps": [_act(u, "lock_on", {"target": x["t"].id}),
						_act(u, "skirmish", {"weapon": x["w"]["key"], "target": x["t"].id})],
					"attacks": true, "quick_left": 0, "kind": "lock_skirmish", "target": x["t"].id, "chance": x["lock_chance"],
					"text": "locks on to %s, then fires %s (%d%% to hit)" % [_name(x["t"]), x["w"]["name"], roundi(x["lock_chance"] * 100)]})
				break
		# Shoot, then Scan an enemy we know nothing about.
		for t: Unit in ctx["enemies"]:
			if not ctx["foot"] and not know.knows_stats(t.id) and Attacks.tech_target_check(s, u, t).ok:
				options.append(_with(base, _act(u, "scan", {"target": t.id}), 0.5 * tech_w, ", then scans %s" % _name(t)))
				break
		# Shoot, then Hide if nobody can see us here.
		if not ctx["no_hide"] and base["quick_left"] >= 1 and Combat.can_hide(s, u).ok:
			options.append(_with(base, _act(u, "hide"), 0.9 * ctx["caution"] * ctx["hide_w"], ", then hides"))
	# Barrage: two different weapons (each at its best target), or one Superheavy.
	var by_weapon := {}
	for x: Dictionary in shots:
		if not by_weapon.has(x["w"]["key"]):
			by_weapon[x["w"]["key"]] = x
	var picks: Array = by_weapon.values()
	picks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["value"] > b["value"])
	if ctx["foot"]:
		picks = []  # no Barrage on foot
	if not picks.is_empty() and picks[0]["w"].get("size", "") == "Superheavy":
		options.append(_barrage(u, [picks[0]]))
	else:
		var two: Array = picks.filter(func(x: Dictionary) -> bool: return x["w"].get("size", "") != "Superheavy").slice(0, 2)
		if two.size() == 2:
			options.append(_barrage(u, two))
	# No attack: Hide, Lock On for allies, Scan.
	if shots.is_empty():
		if not ctx["no_hide"] and Combat.can_hide(s, u).ok:
			options.append({"value": 1.0 * ctx["caution"] * ctx["hide_w"], "steps": [_act(u, "hide")], "attacks": false, "quick_left": 0, "text": "hides", "kind": "hide"})
		for t: Unit in ctx["enemies"]:
			if not ctx["foot"] and Attacks.tech_target_check(s, u, t).ok:
				if not know.knows_stats(t.id):
					options.append({"value": 0.6 * tech_w, "steps": [_act(u, "scan", {"target": t.id})], "attacks": false,
						"quick_left": 1, "text": "scans %s" % _name(t), "kind": "scan"})
				elif not t.has_status("Lock On") and not ctx["allies"].is_empty():
					options.append({"value": 0.4 * tech_w, "steps": [_act(u, "lock_on", {"target": t.id})], "attacks": false,
						"quick_left": 1, "text": "locks on to %s for its allies" % _name(t), "kind": "lock_on"})
				break
	if ctx["foot"]:
		options.append_array(_foot_options(s, u, ctx, shots))
	# Cool down when heat is high (also reloads).
	if u.heat_cap > 0 and u.heat >= ceili(u.heat_cap * 0.6):
		var v: float = float(u.heat) / u.heat_cap * 3.0 * (0.5 + ctx["caution"])
		options.append({"value": v, "steps": [_act(u, "stabilize", {"main": "cool", "extra": "reload"})], "attacks": false,
			"quick_left": 0, "text": "vents heat (Stabilize)", "kind": "stabilize", "reason": "heat is high"})
	elif _needs_reload(u) and shots.size() <= 1 and not ctx["foot"]:
		var main := "cool" if u.kind != Unit.KIND_NPC else ""
		options.append({"value": 0.8, "steps": [_act(u, "stabilize", {"main": main, "extra": "reload"})], "attacks": false,
			"quick_left": 0, "text": "reloads (Stabilize)", "kind": "stabilize", "reason": "its weapons need reloading"})
	var best: Dictionary = options[0]
	for o: Dictionary in options:
		if o["value"] > best["value"]:
			best = o
	return best


func _barrage(u: Unit, picks: Array) -> Dictionary:
	var attacks: Array = []
	var value := 0.0
	var names := PackedStringArray()
	for x: Dictionary in picks:
		attacks.append({"weapon": x["w"]["key"], "target": x["t"].id})
		value += x["value"]
		names.append("%s at %s" % [x["w"]["name"], _name(x["t"])])
	return {"value": value, "steps": [_act(u, "barrage", {"attacks": attacks})], "attacks": true, "quick_left": 0,
		"text": "barrages: %s" % " and ".join(names), "kind": "barrage", "target": picks[0]["t"].id,
		"chance": picks[0]["chance"]}


static func _with(base: Dictionary, step: Dictionary, bonus: float, text: String) -> Dictionary:
	var o := base.duplicate()
	o["steps"] = (base["steps"] as Array) + [step]
	o["value"] = base["value"] + bonus
	o["quick_left"] = 0
	o["text"] = base["text"] + text
	return o


## How much hitting `t` is worth beyond raw damage: focus fire, likely kills, focus orders.
func _target_factor(know: AiKnowledge, t: Unit, ctx: Dictionary, expected: float) -> float:
	var f := 1.0
	var focus: float = ctx["focus"]
	if know.knows_stats(t.id) and t.max_hp > 0:
		var hurt := _hurt(t)
		f += focus * hurt * 1.5 - (1.0 - focus) * hurt * 0.4
		if expected >= t.hp + t.overshield and t.structure <= 1:
			f += 0.8 * ctx["aggression"]
	else:
		# Stats unknown: go by the harm this side saw it take (focus fire without a Scan).
		var seen := know.estimated_hurt(t.id)
		f += focus * (0.25 + seen * 1.5) - (1.0 - focus) * seen * 0.4
	if t.has_status("Lock On"):
		f += 0.3 * focus
	if t.id == ctx["focus_target"]:
		f *= 2.0
	return maxf(f, 0.1)


static func _needs_reload(u: Unit) -> bool:
	for w: Dictionary in u.loadout.get("weapons", []):
		if Weapons.has_tag(w, "tg_loading") and not bool(u.counters.get("weapons", {}).get(w.get("key", ""), {}).get("loaded", true)):
			return true
	return false


# --- Helpers -------------------------------------------------------------------------------

## Average of a damage expression list, e.g. [{"val": "2d6+4"}] -> 11.
static func avg_damage(w: Dictionary) -> float:
	var total := 0.0
	for part: Dictionary in w.get("damage", []):
		var v: Variant = part.get("val", 0)
		if v is int or v is float:
			total += float(v)
			continue
		for term in str(v).replace(" ", "").replace("-", "+-").split("+", false):
			if "d" in term:
				var bits := term.split("d")
				var n := int(bits[0]) if bits[0] != "" else 1
				total += n * (int(bits[1]) + 1) / 2.0
			else:
				total += float(term)
	return total


static func _reach(w: Dictionary) -> int:
	if Weapons.is_melee(w):
		return Weapons.threat(w)
	var r := 0
	for key in ["Range", "Line", "Cone", "Burst"]:
		r = maxi(r, Weapons.range_value(w, key))
	return maxi(r, Weapons.threat(w))


static func _act(u: Unit, type: String, params: Dictionary = {}) -> Dictionary:
	return {"type": type, "actor": u.id, "params": params}


## People on foot: Reload a Loading pilot weapon (Core p.74), Patch a hurt person on foot
## (pilot gear), Search for a Hidden enemy (Core p.70).
func _foot_options(s: GameState, u: Unit, ctx: Dictionary, shots: Array) -> Array:
	var out: Array = []
	for w: Dictionary in u.loadout.get("weapons", []):
		if Weapons.has_tag(w, "tg_loading") and not Weapons.state_of(u, w).get("loaded", true):
			out.append({"value": 0.9 if shots.size() <= 1 else 0.3, "steps": [_act(u, "reload", {"weapon": w["key"]})], "attacks": false,
				"quick_left": 1, "text": "reloads its %s" % w.get("name", "weapon"), "kind": "reload", "reason": "its weapon needs reloading"})
			break
	for a: Dictionary in u.loadout.get("abilities", []):
		if not (a.get("ops", []) as Array).any(func(o: Dictionary) -> bool: return o.get("op", "") == "patch"):
			continue
		var best: Unit = null
		var worst := 0.35
		for p: Unit in [u] + ctx["allies"]:
			if p.on_foot() and not p.has_status("Down and Out") and Sight.unit_distance(s, u, p) <= 1 and _hurt(p) > worst:
				worst = _hurt(p)
				best = p
		if best != null:
			out.append({"value": 3.0 * worst, "steps": [_act(u, "activate", {"ability": a["key"], "target": best.id})], "attacks": false,
				"quick_left": 0, "text": "patches up %s" % ("its own people" if best == u else _name(best)), "kind": "patch", "reason": "they're hurt"})
		break
	for t: Unit in s.units.values():
		if t.side != u.side and t.has_status("Hidden") and not t.destroyed and s.map.grid.distance(u.cell, t.cell) <= u.sensors:
			out.append({"value": 0.8 * ctx["hide_w"], "steps": [_act(u, "search", {"target": t.id})], "attacks": false,
				"quick_left": 1, "text": "searches for a hidden enemy", "kind": "search"})
			break
	return out


static func _name(u: Unit) -> String:
	return u.name if u.name != "" else u.id


func _explain(u: Unit, ctx: Dictionary, best: Dictionary, boost: Dictionary, after: Dictionary = {}) -> String:
	var dest: Dictionary = best["dest"]
	var pkg: Dictionary = best["pkg"]
	var notes: Dictionary = best["pos"]["notes"]
	var parts := PackedStringArray()
	if dest["cost"] == 0:
		parts.append("holds position" if ctx["hold"] else "stays put")
	else:
		var where := "moves %d space%s" % [dest["cost"], "" if dest["cost"] == 1 else "s"]
		if float(notes.get("cover", 0.0)) >= 0.75:
			where += " into hard cover"
		elif float(notes.get("cover", 0.0)) >= 0.4:
			where += " into cover"
		if notes.get("garrison", false):
			where += " into a building, at a window"
		if notes.get("zone", false):
			where += " onto the objective"
		parts.append(where)
	if pkg["text"] != "":
		parts.append(pkg["text"])
	if not after.is_empty():
		parts.append("then moves %d space%s" % [after["cost"], "" if after["cost"] == 1 else "s"])
	if not boost.is_empty():
		parts.append("boosts to close the distance" if not ctx["enemies"].is_empty() else "boosts")
	var why := ""
	if pkg.has("reason"):
		why = pkg["reason"]
	elif ctx["hurt"] >= 0.5 and ctx["caution"] > 0.6:
		why = "it's badly damaged"
	elif pkg.get("target", "") != "" and pkg["target"] == ctx["focus_target"]:
		why = "focus target"
	elif ctx["stance"] != "":
		why = "%s stance" % ctx["stance"]
	elif ctx["intent"] != "":
		why = ctx["intent"]  # its job and the mission's objective (objective_priorities.json)
	elif notes.get("zone", false):
		why = "holding the objective"
	else:
		why = "%s: %s" % [ctx["role"], str(ctx["profile"].get("description", "")).to_lower().trim_suffix(".")]
	return "%s %s (%s)." % [_name(u), ", ".join(parts), why]
