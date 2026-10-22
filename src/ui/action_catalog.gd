class_name ActionCatalog
extends RefCounted
## Builds the action bar's buttons for a unit from the real game: availability and the
## reason it's greyed come from RulesEngine.validate / TurnRules.can_spend; previews, hit
## chances and cover from RulesQueries; warnings are worked out from the unit's state.
## Host-side only (it reads the full GameState). Output format: src/render/FORMATS.md.
##
## Wanted from the rules session (marked TODO(rules) below): queries for weapon/system
## lockouts with a fixed length (turns left), Recharge state, core power uses, reactions
## used this round, and the Danger Zone threshold.

## Pegasus (and anything else with the option): Skirmish and Barrage may use average damage.
const AVERAGE_NOTE := "You may deal average damage instead of rolling (Pegasus)."

const OVERCHARGE := ["1", "1d3", "1d6", "1d6+4"]
const OVERCHARGE_MAX := [1, 3, 6, 10]


static func danger_zone(u: Unit) -> int:
	# Glossary, Danger Zone: heat at or above half the heat cap. TODO(rules): expose this.
	return int(ceil(u.heat_cap / 2.0))


## The resource HUD / cluster dictionary for a unit (ResourceHUD format).
static func resources(state: GameState, u: Unit) -> Dictionary:
	var t := u.turn
	var full_used: bool = t.get("full", false)
	var quick := 0 if full_used else 2 - int(t.get("quick", 0))
	return {
		"name": u.name, "frame": u.content_id, "hp": [u.hp, u.max_hp], "overshield": u.overshield,
		"heat": [u.heat, u.heat_cap], "danger_zone": danger_zone(u), "structure": [u.structure, u.max_structure],
		"stress": [u.stress, u.max_stress], "repairs": [u.repairs, maxi(u.repairs, int(u.counters.get("max_repairs", u.repairs)))],
		"burn": u.burn, "core_power": "used" if u.counters.get("core_used", false) else "available",
		"economy": {
			"quick": [maxi(0, quick), 2], "full": [0 if (full_used or int(t.get("quick", 0)) > 0) else 1, 1],
			"move": [maxi(0, u.speed - int(t.get("move_spent", 0))), u.speed],
			"reaction": [0 if u.counters.get("reaction_used", false) else 1, 1],  # TODO(rules): reactions used this round
			"overcharge_next": OVERCHARGE[mini(u.overcharge_count, 3)],
		},
	}


static func _enemies(state: GameState, u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for o: Unit in state.units.values():
		if o.side != u.side and not o.destroyed:
			out.append(o)
	return out


## Enabled if the action validates against any enemy; else the first reason.
static func _vs_enemies(state: GameState, engine: RulesEngine, u: Unit, type: String, params: Dictionary) -> Dictionary:
	var reason := ""
	for o in _enemies(state, u):
		var p := params.duplicate()
		p["target"] = o.id
		var r := engine.validate(state, {"type": type, "actor": u.id, "params": p})
		if r.ok:
			return {"enabled": true}
		if reason == "":
			reason = r.reason
	return {"enabled": false, "reason": reason if reason != "" else "No valid target."}


static func _spend(u: Unit, cost: String, action: String) -> Dictionary:
	var r := TurnRules.can_spend(u, cost, action)
	return {"enabled": r.ok, "reason": r.reason}


static func _strip(html: String) -> String:
	return RegEx.create_from_string("<[^>]+>").sub(html.replace("<br>", "\n"), "", true).strip_edges()


static func _from_data(db: ContentDB, id: String, extra: Dictionary) -> Dictionary:
	var e := db.get_entry("actions", id)
	var a := {"id": id, "name": e.get("name", id), "desc": _strip(e.get("terse", "")), "text": _strip(e.get("detail", "")),
		"rule_ref": "Core rules, actions: %s" % e.get("name", id)}
	a.merge(extra, true)
	return a


static func for_unit(state: GameState, engine: RulesEngine, db: ContentDB, unit_id: String) -> Array:
	var u := state.unit(unit_id)
	var out: Array = []
	if u == null:
		return out
	var heat_room := u.heat_cap - u.heat
	# Weapons (Skirmish with each).
	for w: Dictionary in u.loadout.get("weapons", []):
		var key := String(w.get("key", ""))
		var dmg: Array = w.get("damage", [])
		var dtype := String(dmg[0].get("type", "Kinetic")) if not dmg.is_empty() else "Kinetic"
		var dval := String(dmg[0].get("val", "")) if not dmg.is_empty() else ""
		var stats := ""
		for r: Dictionary in w.get("range", []):
			stats += "%s %s {icon:%s}   " % [r.get("type", ""), str(int(r.get("val", 0))) if r.get("val") is float else str(r.get("val", "")), Icons.RANGE.get(r.get("type", ""), "range")]
		if dval != "":
			stats += "%s {icon:%s}" % [dval, Icons.damage(dtype)]
		var a := {"id": "w:" + key, "group": "weapons", "cost": "quick", "name": w.get("name", key),
			"short": String(w.get("name", key)).split(" ")[0], "icon": "melee" if Weapons.is_melee(w) else Icons.damage(dtype),
			"stats": stats, "text": "Skirmish: attack with this weapon (quick action).",
			"rule_ref": "Core rules, actions: Skirmish", "kind": "attack", "weapon": key, "preview": {"quick": 1}}
		a.merge(_vs_enemies(state, engine, u, "skirmish", {"weapon": key}), true)
		var ws := Weapons.state_of(u, w)
		var extras: Array = []
		var warns: Array = []
		if Weapons.has_tag(w, "tg_loading"):
			extras.append({"icon": "ammo", "value": "1" if ws.get("loaded", true) else "0"})
			if not ws.get("loaded", true):
				a["enabled"] = false
				a["reason"] = "Loading: reload it (Stabilize) before firing again."
				a["lockout"] = {"kind": "loading"}
		if int(ws.get("uses", -1)) >= 0:
			extras.append({"icon": "generic_item", "value": str(ws["uses"])})
			if int(ws["uses"]) == 0:
				a["enabled"] = false
				a["reason"] = "Limited: no uses left this mission."
				a["lockout"] = {"kind": "uses", "left": 0, "total": Weapons.tag_value(w, "tg_limited")}
			elif int(ws["uses"]) == 1:
				warns.append({"text": "Last charge."})
		if Effects.has(u, "average_damage_option"):
			warns.append({"text": AVERAGE_NOTE})
		if w.get("mod") is Dictionary:
			# The weapon mod: its name and what it does (lancer-data effect text).
			var md: Dictionary = w["mod"]
			var mentry := db.get_entry("mods", String(md.get("id", "")))
			a["mod"] = {"name": String(md.get("name", "")), "text": _strip(String(mentry.get("effect", mentry.get("description", "")))).left(260)}
			if w.has("mod_uses"):
				a["mod"]["uses"] = int(ws.get("mod_uses", w["mod_uses"]))
				extras.append({"icon": "generic_item", "value": "M%d" % int(a["mod"]["uses"])})
		var self_heat := Weapons.tag_value(w, "tg_heat_self")
		if self_heat > 0:
			extras.append({"icon": "heat", "value": "+%d" % self_heat})
			a["preview"]["heat"] = self_heat
			warns.append_array(heat_warnings(u, self_heat, self_heat))
		if u.has_status("Engaged") and not Weapons.is_melee(w):
			warns.append({"text": "You're Engaged: ranged attacks take +1 Difficulty {icon:difficulty}."})
		a["extras"] = extras
		a["warnings"] = warns
		if not ActionInputs.is_simple_attack(ActionInputs.weapon_steps(u, w)):
			a["kind"] = "pick"  # area, several targets or a fold-to space: the step-by-step picker
		out.append(a)
	# Quick actions.
	var boost := _from_data(db, "act_boost", {"group": "quick", "cost": "quick", "icon": "activation_quick", "short": "Boost", "kind": "move_boost", "preview": {"quick": 1}})
	boost.merge(_spend(u, "quick", "boost"), true)
	var threats: Array = RulesQueries.threatened_by(state, u.id) if u.has_status("Engaged") else []
	if not threats.is_empty():
		boost["warnings"] = [{"text": "Moving away provokes from %d %s." % [threats.size(), "enemy" if threats.size() == 1 else "enemies"], "level": "danger"}]
	out.append(boost)
	out.append(_from_data(db, "act_hide", {"group": "quick", "cost": "quick", "icon": "status_hidden", "short": "Hide", "kind": "self", "type": "hide", "preview": {"quick": 1}}).merged(_validate_self(state, engine, u, "hide"), true))
	# Full actions.
	var barrage := _from_data(db, "act_barrage", {"group": "full", "cost": "full", "icon": "barrage", "short": "Barrage", "kind": "barrage", "preview": {"full": 1, "quick": 2}}).merged(_spend(u, "full", "barrage"), true)
	if Effects.has(u, "average_damage_option"):
		var bw: Array = barrage.get("warnings", [])
		bw.append({"text": AVERAGE_NOTE})
		barrage["warnings"] = bw
	out.append(barrage)
	out.append(_from_data(db, "act_stabilize", {"group": "full", "cost": "full", "icon": "repair", "short": "Stabilize", "kind": "self", "type": "stabilize", "params": {"main": "cool", "extra": "reload"}, "preview": {"full": 1}}).merged(_spend(u, "full", "stabilize"), true))
	# Tech.
	for t: Array in [["act_lockon", "lock_on", "condition_lockon", "Lock On"], ["act_scan", "scan", "sensor", "Scan"], ["act_invade", "invade", "tech_quick", "Invade"]]:
		var ta := _from_data(db, t[0], {"group": "tech", "cost": "quick", "icon": t[2], "short": t[3], "kind": "tech", "type": t[1], "preview": {"quick": 1}})
		ta.merge(_vs_enemies(state, engine, u, t[1], {}), true)
		if u.has_status("Jammed"):
			ta["lockout"] = {"kind": "status", "status": "Jammed", "turns": int((u.statuses.get("Jammed", {}) as Dictionary).get("turns", 1))}
		out.append(ta)
	# Overcharge.
	var oc := mini(u.overcharge_count, 3)
	var oca := _from_data(db, "act_overcharge", {"group": "quick", "cost": "free", "icon": "overcharge", "short": "Overcharge", "kind": "self", "type": "overcharge",
		"extras": [{"icon": "heat", "value": "+" + OVERCHARGE[oc]}], "preview": {"heat": [1 if oc == 0 else 1, OVERCHARGE_MAX[oc]], "overcharge": 1}})
	oca.merge(_validate_self(state, engine, u, "overcharge"), true)
	oca["warnings"] = heat_warnings(u, 1, OVERCHARGE_MAX[oc])
	out.append(oca)
	# Reactions (chosen ahead of time; they trigger on others' turns).
	out.append(_from_data(db, "act_brace", {"group": "reactions", "cost": "reaction", "icon": "reaction", "short": "Brace", "kind": "policy", "preview": {"reaction": 1}, "enabled": true}))
	out.append(_from_data(db, "act_overwatch", {"group": "reactions", "cost": "reaction", "icon": "threat", "short": "Overwatch", "kind": "policy", "preview": {"reaction": 1}, "enabled": true}))
	# Everything else the engine lists: other basic actions, systems, talents, traits, core.
	var listing := RulesQueries.available_actions(state, u.id)
	out.append_array(_from_listing(state, engine, db, u, listing))
	var core_entry: Dictionary = {}
	for e: Dictionary in listing:
		if String(e.get("type", "")) == "core_power":
			core_entry = e
	# Core power (from the frame).
	var core: Dictionary = db.frame(u.content_id).get("core_system", {})
	if not core.is_empty() and not core_entry.is_empty():
		var ca := {"id": "core", "group": "core", "cost": String(core.get("activation", "Quick")).to_lower(), "icon": "corebonus",
			"name": String(core.get("active_name", "Core Power")), "short": "Core", "kind": "pick", "type": "core_power",
			"text": _strip(core.get("active_effect", "")), "rule_ref": "Core system: %s (%s)" % [core.get("name", ""), core.get("use", "")],
			"extras": [{"icon": "generic_item", "value": "%d/1" % int(u.counters.get("core_power", 0))}], "preview": {"core_power": 1},
			"enabled": bool(core_entry.get("available", false)), "reason": String(core_entry.get("reason", "")),
			"lockout": {"kind": "uses", "left": 0, "total": 1} if int(u.counters.get("core_power", 1)) <= 0 else {},
			"warnings": [{"text": "Once per mission: this is your only use."}]}
		_table(ca, core_entry)
		out.append(ca)
	elif not core.is_empty():
		var used: bool = u.counters.get("core_used", false)
		out.append({"id": "core", "group": "core", "cost": String(core.get("activation", "Protocol")).to_lower(), "icon": "corebonus",
			"name": String(core.get("active_name", "Core Power")), "short": "Core", "kind": "core",
			"text": _strip(core.get("active_effect", "")), "rule_ref": "Core system: %s (%s)" % [core.get("name", ""), core.get("use", "")],
			"extras": [{"icon": "generic_item", "value": "0/1" if used else "1/1"}], "preview": {"core_power": 1},
			"enabled": not used, "reason": "Core power is used (1/mission)." if used else "",
			"lockout": {"kind": "uses", "left": 0, "total": 1} if used else {},
			"warnings": [{"text": "Once per mission: this is your only use."}]})
	return out


## Basic actions this catalog builds itself (with richer previews); the rest come from the
## engine's listing.
const OWN_TYPES := ["move", "boost", "skirmish", "barrage", "hide", "stabilize", "scan", "lock_on", "invade", "overcharge", "core_power"]
## Situational basic actions: on the More tab (not on All).
const MORE := ["jump", "stand_up", "bonus_move", "disengage", "improvised_attack", "ram", "grapple", "fight", "bolster", "full_tech",
	"search", "prepare", "shut_down", "boot_up", "eject", "dismount", "mount", "self_destruct", "end_grapple", "break_free",
	"grapple_contest", "pull_stake", "use_object", "climb_on", "board", "disembark", "cut_cable"]
## Basic actions that are about moving: shown on the Quick tab.
const GROUP_OF_BASIC := {"move": "quick", "attack": "quick", "tech": "tech", "other": "quick"}


## Bar entries for the engine's listing (RulesQueries.available_actions) that aren't built
## above: other basic actions, system/talent/trait abilities and trait reactions.
static func _from_listing(state: GameState, engine: RulesEngine, db: ContentDB, u: Unit, listing: Array) -> Array:
	var out: Array = []
	for e: Dictionary in listing:
		var id := String(e.get("id", ""))
		var type := String(e.get("type", ""))
		if type == "" or id.begins_with("weapon:") or OWN_TYPES.has(type) or id in ["reaction:brace", "reaction:overwatch"]:
			continue
		var group := String(e.get("group", "other"))
		var cost := String(e.get("cost", "quick"))
		var a: Dictionary
		if id.begins_with("ability:") or id.begins_with("reaction:"):
			var act := String(e.get("activation", "Reaction" if id.begins_with("reaction:") else "Quick"))
			cost = _cost_of_activation(act)
			a = {"id": id, "name": e.get("name", id), "short": _short(String(e.get("name", id))), "text": _strip(String(e.get("detail", ""))),
				"rule_ref": "%s: %s" % [e.get("source", "system"), e.get("name", "")] if e.has("source") else String(e.get("rule_ref", "")),
				"group": {"core": "core", "reaction": "reactions"}.get(group, "systems"), "cost": cost, "type": type,
				"params": (e.get("params", {}) as Dictionary).duplicate(), "kind": "policy" if type == "react" else "pick",
				"icon": "reaction" if type == "react" else ("tech_quick" if "Tech" in act or act == "Invade" else Icons.cost(cost))}
			if e.get("source", "") != "":
				a["desc"] = String(e["source"])
		else:
			a = _from_data(db, "act_" + type, {"short": _short(String(e.get("name", type)))})
			if String(a.get("name", "")) == "act_" + type:
				a["name"] = e.get("name", type)
			a.merge({"id": id, "group": "full" if cost == "full" else GROUP_OF_BASIC.get(group, "quick"), "cost": cost, "type": type,
				"params": (e.get("params", {}) as Dictionary).duplicate(), "kind": "pick", "icon": Icons.cost(cost)}, true)
		a["enabled"] = bool(e.get("available", false))
		a["reason"] = String(e.get("reason", ""))
		if type == "ai_control":
			# One button: hand the controls over, or take them back (Core p.107).
			var back := AISystems.controlled(u)
			a["params"] = {"take_back": back}
			a["name"] = "Take Back Control" if back else "Hand Control to AI"
			a["short"] = "Take back" if back else "AI control"
			a["text"] = "Protocol: %s" % ("take the controls back from your AI." if back else "your AI flies the mech until you take control back at the start of a later turn. NHPs may cascade (a 1 on a d20 after taking control).")
			var r2: RuleResult = engine.validate(state, {"type": type, "actor": u.id, "params": a["params"]})
			a["enabled"] = r2.ok
			a["reason"] = r2.reason
			a["group"] = "quick" if AISystems.has_ai(u) else "more"
		# Situational extras live on More; the ones that only work in a pinch (Prone, grappled,
		# shut down) come forward when they can be used.
		if MORE.has(type) and not (a["enabled"] and type in ["stand_up", "break_free", "boot_up", "end_grapple", "pull_stake"]):
			a["group"] = "more"
		var extras: Array = []
		var umax := int(e.get("uses_max", 0))
		if umax > 0:
			extras.append({"icon": "generic_item", "value": "%d/%d" % [int(e.get("uses_left", 0)), umax]})
			if int(e.get("uses_left", 0)) <= 0:
				a["lockout"] = {"kind": "uses", "left": 0, "total": umax}
		var rc: Dictionary = e.get("recharge", {}) if e.get("recharge") is Dictionary else {}
		if int(rc.get("value", 0)) > 0 and not rc.get("charged", true):
			a["lockout"] = {"kind": "recharge", "target": int(rc["value"])}
		if e.get("destroyed", false):
			a["lockout"] = {"kind": "status", "status": "Destroyed"}
			a["reason"] = "Destroyed: repair it first."
		if String(e.get("frequency", "")) != "" and int(e.get("used", 0)) > 0 and not a.has("lockout"):
			a["warnings"] = [{"text": "Used %d time%s already (%s)." % [int(e["used"]), "" if int(e["used"]) == 1 else "s", e["frequency"]]}]
		a["extras"] = extras
		_table(a, e)
		out.append(a)
	return out


## Marks entries the table resolves by hand: a "table" badge and the note in the hover card.
static func _table(a: Dictionary, e: Dictionary) -> void:
	var status := String(e.get("automation", "automated" if e.get("automated", true) else "manual"))
	if status in ["manual", "partial"]:
		a["table"] = status
		var note := String(e.get("table_note", ""))
		if note == "":
			note = "The game doesn't apply this one: your table does (read the text and apply it)." if status == "manual" 				else "The game applies most of this; your table handles the rest."
		a["table_note"] = note


static func _cost_of_activation(act: String) -> String:
	match act:
		"Full", "Full Action":
			return "full"
		"Protocol":
			return "protocol"
		"Free", "Free Action":
			return "free"
		"Reaction":
			return "reaction"
		"Quick Tech", "Invade":
			return "quick_tech"
		"Full Tech":
			return "full_tech"
	return "quick"


static func _short(name: String) -> String:
	for drop: String in ["Deploy ", "Recall ", "Deactivate ", "Detonate "]:
		if name.begins_with(drop):
			return drop.strip_edges() + " " + name.trim_prefix(drop).split(" ")[0]
	return name.split(" ")[0] if name.length() > 12 else name


static func _validate_self(state: GameState, engine: RulesEngine, u: Unit, type: String, params: Dictionary = {}) -> Dictionary:
	var r := engine.validate(state, {"type": type, "actor": u.id, "params": params})
	return {"enabled": r.ok, "reason": r.reason}


## Plain-language heat warnings for gaining between lo and hi heat.
static func heat_warnings(u: Unit, lo: int, hi: int) -> Array:
	var out: Array = []
	var after := u.heat + hi
	if after > u.heat_cap:
		var sure := u.heat + lo > u.heat_cap
		out.append({"level": "danger", "text": "This %s overheat you (%d/%d {icon:heat} → %d): you'll take stress damage and roll an overheating check." % ["will" if sure else "can", u.heat, u.heat_cap, after]})
	elif after >= danger_zone(u) and u.heat < danger_zone(u):
		out.append({"text": "This %s put you in the Danger Zone {icon:status_dangerzone} (%d+ heat)." % ["will" if u.heat + lo >= danger_zone(u) else "can", danger_zone(u)]})
	return out


## Expected outcome of attacking `target_id` with the weapon `key` (for the hover card).
static func attack_outcome(state: GameState, attacker_id: String, key: String, target_id: String) -> Dictionary:
	var p := RulesQueries.attack_preview(state, attacker_id, key, target_id)
	var t := state.unit(target_id)
	if not p.get("ok", false):
		return {"target": t.name if t else target_id, "error": p.get("reason", "")}
	var w := Weapons.find(state.unit(attacker_id), key)
	var dmg: Array = w.get("damage", [])
	var out := {"target": t.name, "hit_chance": p.get("hit_chance", 0.0), "cover": (p.get("cover", {}) as Dictionary).get("cover", "none")}
	if not dmg.is_empty():
		out["damage"] = _expected_damage(String(dmg[0].get("val", "0")), t.armor, Weapons.has_tag(w, "tg_ap"))
		out["damage_type"] = String(dmg[0].get("type", "Kinetic"))
		if t.armor > 0 and not Weapons.has_tag(w, "tg_ap"):
			out["armor"] = t.armor
	return out


## "a–b" damage range after Armor for an expression like "1d6+2".
static func _expected_damage(expr: String, armor: int, ap: bool) -> String:
	var lo := 0
	var hi := 0
	for term in expr.replace(" ", "").replace("-", "+-").split("+", false):
		if "d" in term:
			var parts := term.split("d")
			var n := int(parts[0]) if parts[0] != "" else 1
			lo += n
			hi += n * int(parts[1])
		else:
			lo += int(term)
			hi += int(term)
	var a := 0 if ap else armor
	return "%d–%d" % [maxi(0, lo - a), maxi(0, hi - a)]
