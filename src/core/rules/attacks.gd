class_name Attacks
extends RefCounted
## Attack rolls: who can be attacked with what, every Accuracy/Difficulty source with its
## label, hit/miss/crit, damage, and on-hit tags. preview() is a pure query for the targeting
## UI (hit chance breakdown, cover highlight); attack() rolls and applies it.
##
## Book rules used (lancer-data text): Skirmish, Barrage, Fight (ranged attacks get cover and
## +1 Difficulty while Engaged), Critical Hits, Lock On, Invisible, Hidden, Prone, Impaired,
## Stunned, Brace, Jammed, and the tags Accurate, Inaccurate, AP, Reliable, Knockback, Loading,
## Limited, Ordnance, Smart, Seeking, Arcing, Thrown, Threat, Overkill, Heat (Self/Target), Burn.
## PROVISIONAL (docs/RULES_TODO.md): cover doesn't apply to tech attacks or melee; Reliable
## damage uses the weapon's first damage type; tech attacks can't crit.

const REF_SKIRMISH := "actions: Skirmish"
const REF_BARRAGE := "actions: Barrage"
const REF_FIGHT := "actions: Fight"
const REF_CRIT := "glossary: Critical Hits"
const KIND_MELEE := "melee"
const KIND_RANGED := "ranged"
const KIND_TECH := "tech"


static func _src(label: String, kind: String, ref: String, value: int = 1) -> Dictionary:
	return {"label": label, "kind": kind, "type": kind, "value": value, "rule_ref": ref}


## Everything about an attack before it's rolled. Never changes the state.
## opts: use_lock_on (default true), improvised (Improvised Attack: allowed while Jammed),
## skip_ordnance (overwatch etc. are refused elsewhere).
## Returns {ok, reason, rule_ref, kind, distance, reach, los, cover (Sight.cover dict or {}),
## accuracy, difficulty, sources, bonus, bonus_sources, defense_name, target_number,
## lock_on (bool: Lock On will be consumed)}.
static func preview(state: GameState, attacker: Unit, w: Dictionary, target: Unit, opts: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "reason": "", "rule_ref": REF_SKIRMISH, "kind": "", "distance": 0,
		"reach": 0, "los": false, "cover": {}, "accuracy": 0, "difficulty": 0, "sources": [],
		"bonus": 0, "bonus_sources": [], "defense_name": "Evasion", "target_number": 0, "lock_on": false}
	var fail := func(why: String, ref: String) -> Dictionary:
		out["reason"] = why
		out["rule_ref"] = ref
		return out
	if w.is_empty():
		return fail.call("No such weapon.", REF_SKIRMISH)
	if target == null or target.destroyed:
		return fail.call("No valid target.", REF_SKIRMISH)
	if target == attacker:
		return fail.call("You can't attack yourself.", REF_SKIRMISH)
	var area_origin: Variant = opts.get("area_origin")
	if Weapons.area(w) != "" and area_origin == null:
		return fail.call("%s is an area weapon (%s): aim it at a space instead of a target." % [w.get("name", ""), Weapons.area(w)], Areas.REF)
	if target.has_status("Hidden") and target.side != attacker.side and area_origin == null:
		return fail.call("Hidden characters can't be targeted by attacks.", "statuses: Hidden")
	if not Combat.is_present(target):
		return fail.call("No valid target.", REF_SKIRMISH)
	if not opts.get("skip_spend", false):
		var ready := weapon_ready(attacker, w, opts.get("improvised", false))
		if not ready.ok:
			return fail.call(ready.reason, ready.rule_ref)
	var a_body := Sight.body_of(state, attacker)
	var t_body := Sight.body_of(state, target)
	var dist := Sight.distance(state, a_body, t_body)
	out["distance"] = dist
	var kind := KIND_RANGED
	var reach := Weapons.range_value(w, "Range")
	if Weapons.is_melee(w):
		kind = KIND_MELEE
		reach = Weapons.threat(w)
		var thrown := Weapons.tag_value(w, "tg_thrown")
		if dist > reach and thrown > 0:
			reach = thrown
			out["thrown"] = true
	out["kind"] = kind
	out["reach"] = reach
	if area_origin == null and dist > reach:
		return fail.call("Out of %s: %d spaces away, %s reaches %d." % ["Threat" if kind == KIND_MELEE and not out.has("thrown") else "Range", dist, w.get("name", "the weapon"), reach], "glossary: Range" if kind == KIND_RANGED else "glossary: Threat")
	var ignores_los := Weapons.has_tag(w, "tg_arcing") or Weapons.has_tag(w, "tg_seeking")
	# Area attacks take cover and line of sight from the area's origin (glossary: Blast, Burst).
	var cover := Sight.cover(state, area_origin if area_origin != null else a_body, t_body)
	out["los"] = cover["los"]
	if not cover["los"] and not ignores_los:
		return fail.call("No line of sight to the target.", Sight.REF_LOS)
	var turn := attacker.turn
	var engaged_with_target := dist <= 1 and target.side != attacker.side
	if Weapons.has_tag(w, "tg_ordnance"):
		if turn.get("acted", false) or turn.get("moved", false):
			return fail.call("Ordnance can only be fired before you move or take other actions this turn.", "tags: Ordnance")
		if engaged_with_target:
			return fail.call("Ordnance can't be used against a target in engagement with you.", "tags: Ordnance")
	# Accuracy and Difficulty, each with its source.
	var sources: Array = []
	var acc := 0
	var diff := 0
	var accurate := Weapons.tag_value(w, "tg_accurate") + int(w.get("accuracy", 0))
	if accurate > 0:
		sources.append(_src("Accurate", "accuracy", "tags: Accurate", accurate))
		acc += accurate
	var inaccurate := Weapons.tag_value(w, "tg_inaccurate")
	if inaccurate > 0:
		sources.append(_src("Inaccurate", "difficulty", "tags: Inaccurate", inaccurate))
		diff += inaccurate
	if target.has_status("Lock On") and target.side != attacker.side and opts.get("use_lock_on", true):
		sources.append(_src("Lock On", "accuracy", "statuses: Lock On"))
		acc += 1
		out["lock_on"] = true
	if target.has_status("Prone"):
		sources.append(_src("Target is Prone", "accuracy", "statuses: Prone"))
		acc += 1
	if attacker.has_status("Impaired"):
		sources.append(_src("Impaired", "difficulty", "statuses: Impaired"))
		diff += 1
	if target.has_status("Braced"):
		sources.append(_src("Target Braced", "difficulty", "actions: Brace"))
		diff += 1
	var ranged_like := kind == KIND_RANGED or out.has("thrown")
	if kind == KIND_RANGED and attacker.has_status("Engaged"):
		sources.append(_src("Engaged", "difficulty", "statuses: Engaged"))
		diff += 1
	if ranged_like and not Weapons.has_tag(w, "tg_seeking") and int(cover["difficulty"]) > 0:
		sources.append(_src("Hard cover" if cover["cover"] == "hard" else "Soft cover", "difficulty", Sight.REF_COVER, cover["difficulty"]))
		diff += int(cover["difficulty"])
		out["cover"] = cover
	elif ranged_like:
		out["cover"] = cover
	out["accuracy"] = acc
	out["difficulty"] = diff
	out["sources"] = sources
	# Flat bonus: NPC weapons have their own attack bonus, mechs add Grit.
	if w.has("attack_bonus"):
		out["bonus"] = int(w["attack_bonus"])
		out["bonus_sources"] = [{"label": "Attack bonus", "value": int(w["attack_bonus"])}]
	else:
		out["bonus"] = attacker.grit
		out["bonus_sources"] = [{"label": "Grit", "value": attacker.grit}]
	if area_origin != null:
		out["kind"] = KIND_RANGED if not Weapons.is_melee(w) else KIND_MELEE
	_defense(out, target, Weapons.has_tag(w, "tg_smart"))
	out["ok"] = true
	out["rule_ref"] = REF_FIGHT
	return out


## Can this weapon be fired at all right now (Jammed, destroyed, Loading, Limited)?
static func weapon_ready(attacker: Unit, w: Dictionary, improvised: bool = false) -> RuleResult:
	if attacker.has_status("Jammed") and not improvised:
		return RuleResult.deny("Jammed: you can only make Improvised Attacks, Grapple or Ram.", "statuses: Jammed")
	var ws := Weapons.state_of(attacker, w)
	if ws["destroyed"]:
		return RuleResult.deny("%s has been destroyed." % w.get("name", "That weapon"), Combat.REF_STRUCTURE)
	if Weapons.has_tag(w, "tg_loading") and not ws["loaded"]:
		return RuleResult.deny("%s needs reloading (Stabilize reloads it)." % w.get("name", "That weapon"), "tags: Loading")
	if Weapons.has_tag(w, "tg_limited") and int(ws["uses"]) <= 0:
		return RuleResult.deny("%s is out of charges until a Full Repair." % w.get("name", "That weapon"), "tags: Limited")
	return RuleResult.allow()


static func _defense(out: Dictionary, target: Unit, smart: bool) -> void:
	if smart:
		out["defense_name"] = "E-Defense"
		# Smart: targets with no E-Defense count as having 8 (tags: Smart).
		out["target_number"] = target.edef if target.edef > 0 else 8
		return
	out["defense_name"] = "Evasion"
	var ev := target.evasion
	if target.has_status("Stunned"):
		ev = mini(ev, 5)  # STUNNED mechs have a maximum of 5 EVASION.
		out["defense_note"] = "Stunned: Evasion 5 at most"
	out["target_number"] = ev


## Makes one attack with weapon `w` and applies everything that follows from it.
## opts: as preview(), plus no_bonus_damage (auxiliary follow-up), knockback (bool or int:
## spaces to use, the attacker "may choose").
static func attack(state: GameState, attacker: Unit, w: Dictionary, target: Unit, opts: Dictionary = {}) -> Array[Dictionary]:
	var p := preview(state, attacker, w, target, opts)
	var events: Array[Dictionary] = []
	var kind: String = p["kind"]
	var invisible_miss := false
	if target.has_status("Invisible"):
		# 50% chance to miss outright before the roll (statuses: Invisible).
		var coin := state.dice.die(2)
		invisible_miss = coin == 1
		events.append({"type": "invisible_roll", "attacker": attacker.id, "target": target.id, "roll": coin, "missed": invisible_miss, "rule_ref": "statuses: Invisible"})
	var check := {}
	var result := "miss"
	if not invisible_miss:
		check = state.dice.check(p["bonus"], p["accuracy"], p["difficulty"], p["target_number"], p["sources"])
		check["bonus_sources"] = p["bonus_sources"]
		check["bonuses"] = p["bonus_sources"]
		check["defense"] = p["defense_name"]
		check["target_label"] = p["defense_name"]
		if check["success"]:
			result = "crit" if check["crit"] else "hit"
	events.append({"type": "attack_rolled", "attacker": attacker.id, "target": target.id,
		"weapon": w.get("key", ""), "weapon_name": w.get("name", ""), "kind": kind, "check": check,
		"result": result, "cover": p["cover"].get("cover", "none") if p["cover"] is Dictionary else "none",
		"cover_cells": p["cover"].get("cover_cells", []), "invisible_miss": invisible_miss,
		"lock_on_consumed": p["lock_on"], "rule_ref": p["rule_ref"]})
	if not opts.get("skip_spend", false):
		events.append_array(_spend_weapon(state, attacker, w))
	if result != "miss":
		events.append_array(_hit(state, attacker, w, target, result == "crit", opts))
	elif Weapons.tag_value(w, "tg_reliable") > 0:
		var dtype := String((w.get("damage", [{}]) as Array)[0].get("type", "Kinetic")) if not (w.get("damage", []) as Array).is_empty() else "Kinetic"
		var parts := [{"type": dtype, "amount": Weapons.tag_value(w, "tg_reliable")}]
		events.append({"type": "reliable_damage", "attacker": attacker.id, "target": target.id, "amount": Weapons.tag_value(w, "tg_reliable"), "rule_ref": "tags: Reliable"})
		events.append_array(_apply(state, attacker, target, parts, Weapons.has_tag(w, "tg_ap")))
	if p["lock_on"]:
		events.append_array(Combat.remove_status(target, "Lock On", "consumed by " + attacker.id))
	if attacker.has_status("Hidden"):
		events.append_array(Combat.remove_status(attacker, "Hidden", "attacked"))
		events.append_array(Combat.refresh_engagement(state))
	return events


static func _spend_weapon(state: GameState, attacker: Unit, w: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var ws := Weapons.state_of(attacker, w)
	if Weapons.has_tag(w, "tg_loading"):
		ws["loaded"] = false
	if Weapons.has_tag(w, "tg_limited"):
		ws["uses"] = int(ws["uses"]) - 1
	var self_heat := Weapons.tag_value(w, "tg_heat_self")
	if self_heat > 0:
		events.append_array(Combat.apply_heat(state, attacker, self_heat, "Heat (Self): " + String(w.get("name", ""))))
	return events


static func _hit(state: GameState, attacker: Unit, w: Dictionary, target: Unit, crit: bool, opts: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var parts: Array = []
	var overkill_heat := 0
	var total := 0
	var shared: Dictionary = opts.get("shared_damage", {})
	var damage: Array = w.get("damage", [])
	for i in range(damage.size()):
		var d: Dictionary = damage[i]
		var r := _shared_roll(state, shared, i, String(d.get("val", "0")), crit, Weapons.has_tag(w, "tg_overkill"))
		overkill_heat += int(r["overkill_heat"])
		events.append({"type": "damage_rolled", "attacker": attacker.id, "target": target.id, "damage_type": d.get("type", "Kinetic"), "roll": r, "crit": crit, "rule_ref": REF_CRIT if crit else Combat.REF_HARM})
		parts.append({"type": d.get("type", "Kinetic"), "amount": int(r["total"])})
		total += int(r["total"])
	var reliable := Weapons.tag_value(w, "tg_reliable")
	if reliable > 0 and total < reliable and not parts.is_empty():
		parts[0]["amount"] = int(parts[0]["amount"]) + reliable - total
		events.append({"type": "reliable_damage", "attacker": attacker.id, "target": target.id, "amount": reliable, "rule_ref": "tags: Reliable"})
	var burn := Weapons.tag_value(w, "tg_burn")
	if burn > 0:
		parts.append({"type": "Burn", "amount": burn})
	var heat := Weapons.tag_value(w, "tg_heat_target")
	if heat > 0:
		parts.append({"type": "Heat", "amount": heat})
	if overkill_heat > 0 and not shared.get("overkill_paid", false):
		shared["overkill_paid"] = true
		events.append_array(Combat.apply_heat(state, attacker, overkill_heat, "Overkill"))
	events.append_array(_apply(state, attacker, target, parts, Weapons.has_tag(w, "tg_ap")))
	var kb := Weapons.tag_value(w, "tg_knockback")
	var want: Variant = opts.get("knockback", false)
	if kb > 0 and not target.destroyed and want != null and (want is int or bool(want)):
		var spaces: int = mini(kb, int(want)) if want is int else kb
		events.append_array(knock_back(state, target, opts.get("knockback_from", attacker.cell), spaces))
	return events


## Applies a hit's damage parts, letting the target Brace if its reaction policy says so.
static func _apply(state: GameState, attacker: Unit, target: Unit, parts: Array, ap: bool) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var brace := false
	if Reactions.can_react(target, "brace").ok and not parts.is_empty():
		var d := Reactions.offer(state, target, "brace", {"attacker": attacker.id, "damage": parts, "ap": ap},
			{"take": _wants_brace(target, parts, ap)})
		brace = d.get("take", false)
	if brace:
		events.append_array(Reactions.brace(state, target, attacker.id))
	events.append_array(Combat.deal_damage(state, target, parts, {"source": attacker.id, "ap": ap, "resist_all": brace}))
	return events


## Brace policy "on_structure": brace when this hit would take the last of the target's HP.
## (A choice the player makes ahead of time; see Reactions.)
static func _wants_brace(target: Unit, parts: Array, ap: bool) -> bool:
	if Reactions.policy(target, "brace") != "on_structure":
		return false
	var dmg := 0
	for p: Dictionary in parts:
		var t: String = p.get("type", "Kinetic")
		if t == "Heat":
			continue
		var amt: int = p.get("amount", 0)
		if target.has_status("Exposed") and Combat.DOUBLED_BY_EXPOSED.has(t):
			amt *= 2
		dmg += amt
	if not ap and not target.has_status("Shredded"):
		dmg -= target.armor
	return dmg >= target.hp + target.overshield


## Damage for area attacks is rolled once and shared by every target (glossary: Blast etc.);
## a critical hit on one target rolls the extra dice once too. `shared` caches the rolls.
static func _shared_roll(state: GameState, shared: Dictionary, index: int, expr: String, crit: bool, overkill: bool) -> Dictionary:
	if not shared.has("base"):
		shared["base"] = {}
		shared["crit"] = {}
	var base: Dictionary = shared["base"]
	if not base.has(index):
		base[index] = roll_damage(state, expr, false, overkill)
	if not crit:
		return base[index]
	var crits: Dictionary = shared["crit"]
	if not crits.has(index):
		var b: Dictionary = base[index]
		var extra := roll_damage(state, expr, false, overkill)
		var count: int = (b["kept"] as Array).size()
		var all: Array = (b["dice"] as Array) + (extra["dice"] as Array)
		var kept := all.duplicate()
		kept.sort()
		kept.reverse()
		kept = kept.slice(0, count)
		var total: int = int(b["bonus"])
		for v: int in kept:
			total += v
		crits[index] = {"expr": expr, "dice": all, "kept": kept, "bonus": b["bonus"], "total": maxi(0, total),
			"crit": true, "overkill_heat": int(b["overkill_heat"]) + int(extra["overkill_heat"])}
	return crits[index]


## Rolls a damage expression. Critical hits roll every die twice and keep the highest results
## (glossary: Critical Hits). Overkill: each 1 gives the attacker 1 heat and is rerolled.
## Returns {expr, dice: [int], kept: [int], bonus, total, crit, overkill_heat}.
static func roll_damage(state: GameState, expr: String, crit: bool, overkill: bool) -> Dictionary:
	var first := state.dice.roll(expr)
	var values: Array[int] = []
	var sides: Array[int] = []
	for r: Dictionary in first["rolls"]:
		values.append(int(r["value"]))
		sides.append(int(r["sides"]))
	var count := values.size()
	if crit:
		for r: Dictionary in state.dice.roll(expr)["rolls"]:
			values.append(int(r["value"]))
			sides.append(int(r["sides"]))
	var heat := 0
	if overkill:
		for i in range(values.size()):
			while values[i] == 1:
				heat += 1
				values[i] = state.dice.die(sides[i])
	var kept := values.duplicate()
	kept.sort()
	kept.reverse()
	kept = kept.slice(0, count)
	var total: int = int(first["bonus"])
	for v in kept:
		total += v
	return {"expr": expr, "dice": values, "kept": kept, "bonus": first["bonus"], "total": maxi(0, total), "crit": crit, "overkill_heat": heat}


## Knockback / pushes: involuntary straight-line movement (glossary: Involuntary Movement).
static func knock_back(state: GameState, target: Unit, origin: Vector2i, spaces: int) -> Array[Dictionary]:
	var path := Movement.push_path(state, target, origin, spaces)
	if path.size() < 2:
		return [{"type": "knockback_blocked", "unit": target.id, "rule_ref": "tags: Knockback"}] as Array[Dictionary]
	var last: Array = path.back()
	target.cell = Vector2i(last[0], last[1])
	var events: Array[Dictionary] = [{"type": "moved", "unit": target.id, "path": path, "mode": "involuntary", "cost": 0, "rule_ref": "tags: Knockback"}]
	if Movement.placement(state, target.size, target.cell, target.level)["airborne"] and not target.flying:
		events.append_array(Combat.begin_falling(target, "Knocked off a ledge."))
	events.append_array(Combat.after_movement(state))
	return events


## A tech attack: d20 + Tech Attack vs E-Defense. Range is SENSORS and needs line of sight
## (actions: Invade). PROVISIONAL: no cover, no crits.
static func tech_preview(state: GameState, attacker: Unit, target: Unit, opts: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "reason": "", "rule_ref": "actions: Invade", "kind": KIND_TECH, "accuracy": 0,
		"difficulty": 0, "sources": [], "bonus": attacker.tech_attack,
		"bonus_sources": [{"label": "Tech Attack", "value": attacker.tech_attack}],
		"defense_name": "E-Defense", "target_number": target.edef if target else 0, "lock_on": false}
	var r := tech_target_check(state, attacker, target)
	if not r.ok:
		out["reason"] = r.reason
		out["rule_ref"] = r.rule_ref
		return out
	var sources: Array = []
	if target.has_status("Lock On") and target.side != attacker.side and opts.get("use_lock_on", true):
		sources.append(_src("Lock On", "accuracy", "statuses: Lock On"))
		out["accuracy"] = 1
		out["lock_on"] = true
	if target.has_status("Prone"):
		sources.append(_src("Target is Prone", "accuracy", "statuses: Prone"))
		out["accuracy"] = int(out["accuracy"]) + 1
	if attacker.has_status("Impaired"):
		sources.append(_src("Impaired", "difficulty", "statuses: Impaired"))
		out["difficulty"] = 1
	if target.has_status("Braced"):
		sources.append(_src("Target Braced", "difficulty", "actions: Brace"))
		out["difficulty"] = int(out["difficulty"]) + 1
	out["sources"] = sources
	out["ok"] = true
	return out


## Shared checks for any tech action at a target: within SENSORS and line of sight, not
## Hidden, not Shut Down, and the user not Jammed.
static func tech_target_check(state: GameState, user: Unit, target: Unit) -> RuleResult:
	if user.has_status("Jammed"):
		return RuleResult.deny("Jammed: you can't take tech actions.", "statuses: Jammed")
	if target == null or target.destroyed:
		return RuleResult.deny("No valid target.", "actions: Quick Tech")
	if target.has_status("Hidden") and target.side != user.side:
		return RuleResult.deny("Hidden characters can't be targeted.", "statuses: Hidden")
	if target.has_status("Shut Down"):
		return RuleResult.deny("Shut Down mechs are immune to tech actions.", "statuses: Shut Down")
	if Sight.unit_distance(state, user, target) > user.sensors:
		return RuleResult.deny("Out of Sensors range (%d)." % user.sensors, "glossary: Sensors")
	if not Sight.unit_line_of_sight(state, user, target):
		return RuleResult.deny("No line of sight to the target.", Sight.REF_LOS)
	return RuleResult.allow()


## Rolls a tech attack. Returns {"events": [...], "hit": bool}.
static func tech_attack(state: GameState, attacker: Unit, target: Unit, label: String, opts: Dictionary = {}) -> Dictionary:
	var p := tech_preview(state, attacker, target, opts)
	var events: Array[Dictionary] = []
	var hit := false
	var check := {}
	var invisible_miss := false
	if target.has_status("Invisible"):
		var coin := state.dice.die(2)
		invisible_miss = coin == 1
		events.append({"type": "invisible_roll", "attacker": attacker.id, "target": target.id, "roll": coin, "missed": invisible_miss, "rule_ref": "statuses: Invisible"})
	if not invisible_miss:
		check = state.dice.check(p["bonus"], p["accuracy"], p["difficulty"], p["target_number"], p["sources"])
		check["bonus_sources"] = p["bonus_sources"]
		check["defense"] = "E-Defense"
		hit = check["success"]
	events.append({"type": "tech_attack", "attacker": attacker.id, "target": target.id, "check": check,
		"result": "hit" if hit else "miss", "effect": label, "invisible_miss": invisible_miss,
		"lock_on_consumed": p["lock_on"], "rule_ref": "actions: Invade"})
	if p["lock_on"]:
		events.append_array(Combat.remove_status(target, "Lock On", "consumed by " + attacker.id))
	if attacker.has_status("Hidden"):
		events.append_array(Combat.remove_status(attacker, "Hidden", "attacked"))
		events.append_array(Combat.refresh_engagement(state))
	return {"events": events, "hit": hit}
