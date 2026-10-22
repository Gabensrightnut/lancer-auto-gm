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
## Melee and tech attacks ignore cover; crits are for melee and ranged attacks (Core p.64).
## Reliable damage on a miss uses the weapon's first damage type.

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
	if Effects.has(attacker, "no_attacks"):
		return fail.call("You can't make attacks of any kind right now (Retractable Profile).", "systems: Retractable Profile")
	if Effects.has(attacker, "melee_only") and not Weapons.is_melee(w):
		return fail.call("SEKHMET can't make ranged attacks.", "systems: SEKHMET-Class NHP")
	if GearSystems.in_stasis(target):
		return fail.call("In stasis: it can't be targeted.", "systems: Stasis Generator")
	var area_origin: Variant = opts.get("area_origin")
	if Weapons.area(w) != "" and area_origin == null:
		return fail.call("%s is an area weapon (%s): aim it at a space instead of a target." % [w.get("name", ""), Weapons.area(w)], Areas.REF)
	if target.has_status("Hidden") and target.side != attacker.side and area_origin == null and not GearSystems.sees_through(state, attacker, target):
		return fail.call("Hidden characters can't be targeted by attacks.", "statuses: Hidden")
	if not Combat.is_present(target):
		return fail.call("No valid target.", REF_SKIRMISH)
	if w.get("no_attack", false) and not opts.get("fired_by_rule", false):
		return fail.call("%s can't make normal attacks; it's fired through its own rule." % w.get("name", ""), "weapons: " + String(w.get("name", "")))
	if not opts.get("skip_spend", false):
		var ready := weapon_ready(attacker, w, opts.get("improvised", false))
		if not ready.ok:
			return fail.call(ready.reason, ready.rule_ref)
	var a_body := Sight.body_of(state, attacker)
	if opts.get("origin_cell") is Vector2i:
		# Throughbolt: range, cover and line of sight from the end of its path.
		var oc: Vector2i = opts["origin_cell"]
		a_body = Sight.make_body(state, oc, state.map.ground_height(oc), 0.5)
	var t_body := Sight.body_of(state, target)
	var dist := Sight.distance(state, a_body, t_body)
	out["distance"] = dist
	var kind := KIND_RANGED
	var reach := Weapons.range_for(attacker, w)
	if Weapons.is_melee(w):
		kind = KIND_MELEE
		reach = Weapons.threat_for(attacker, w)
		var thrown := Weapons.tag_value(w, "tg_thrown")
		if dist > reach and thrown > 0:
			reach = thrown
			out["thrown"] = true
	out["kind"] = kind
	out["reach"] = reach
	if Weapons.is_melee(w) and Effects.has(attacker, "no_melee"):
		return fail.call("With Siege Stabilizers extended you can't make melee attacks.", "systems: Siege Stabilizers")
	if not Weapons.is_melee(w) and dist <= Effects.value(attacker, "min_attack_range") and Effects.value(attacker, "min_attack_range") > 0:
		return fail.call("With Siege Stabilizers extended you can't attack within range %d." % Effects.value(attacker, "min_attack_range"), "systems: Siege Stabilizers")
	var in_reach := Sight.within(state, a_body, t_body, reach)
	if area_origin == null and in_reach["grey_area"] != "":
		out["grey_area"] = in_reach["grey_area"]
		return fail.call("Whether that's in reach depends on how your table measures range up and down.", "Core p.64 Range")
	if area_origin == null and not in_reach["ok"]:
		return fail.call("Out of %s: %d spaces away, %s reaches %d." % ["Threat" if kind == KIND_MELEE and not out.has("thrown") else "Range", dist, w.get("name", "the weapon"), reach], "glossary: Range" if kind == KIND_RANGED else "glossary: Threat")
	var seeking := Weapons.has_tag(w, "tg_seeking")
	if seeking_payload(attacker, w, target, opts):
		# Monarch Seeking Payload: a Launcher against a Locked On target attacks as if it had
		# Seeking, consumes the Lock On, and its damage can't be reduced.
		seeking = true
		out["seeking_payload"] = true
	var phase: bool = opts.get("phase", false) and WeaponRules.rules(w).get("phase_ready", false)
	if phase:
		out["phase"] = true  # Phase-Ready: through walls, no line of sight, no cover; target counts as Invisible
	var ignores_los := Weapons.has_tag(w, "tg_arcing") or seeking or phase
	# Area attacks take cover and line of sight from the area's origin (glossary: Blast, Burst).
	var cover := FrameSystems.extra_cover(state, target, Sight.cover(state, area_origin if area_origin != null else a_body, t_body, Effects.guardians(state, target)), attacker)
	if not Zones.barrier_between(state, attacker, target).is_empty():
		return fail.call("No attack can cross that barrier.", "systems: Hardlight Defense System / Blinkshield")
	if area_origin == null and Zones.blocks_sight(state, attacker, target):
		cover = cover.duplicate()
		cover["los"] = false
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
	for e: Dictionary in Effects.of(target, "defense_difficulty"):
		if e.has("vs") and not (e["vs"] as Array).has(kind):
			continue
		sources.append(_src(String(e.get("label", "")), "difficulty", Effects.REF, int(e.get("value", 1))))
		diff += int(e.get("value", 1))
	for e: Dictionary in Effects.of(attacker, "mount_accuracy"):
		if int(w.get("mount", -9)) == int(e.get("mount", -1)):
			sources.append(_src("Auto-Stabilizing Hardpoints", "accuracy", "Core p.118", int(e.get("value", 1))))
			acc += int(e.get("value", 1))
	if kind == KIND_MELEE and String(attacker.counters.get("tomorrow", "")) == target.id:
		sources.append(_src("Thinking Tomorrow's Thought", "accuracy", "Core p.191"))
		acc += 1
		out["tomorrow"] = true
	for src: Dictionary in TalentRules.sources(state, attacker, w, target, kind, opts):
		sources.append(src)
		if src["kind"] == "accuracy":
			acc += int(src["value"])
		else:
			diff += int(src["value"])
	for src: Dictionary in GearSystems.attack_sources(attacker, kind):
		sources.append(src)
		if src["kind"] == "accuracy":
			acc += int(src["value"])
		else:
			diff += int(src["value"])
	var enc := GearSystems.enclave_difficulty(state, attacker, target)
	if enc > 0:
		sources.append(_src("Enclave dome", "difficulty", "systems: Enclave-Pattern Support Shield", enc))
		diff += enc
	var shield := GearSystems.shield_difficulty(attacker, target)
	if shield > 0:
		sources.append(_src("Projected Shield", "difficulty", "systems: Type-3 Projected Shield", shield))
		diff += shield
	var roll_kinds := ["attack", "melee_attack" if kind == KIND_MELEE else "ranged_attack"]
	for src: Dictionary in Effects.accuracy_sources(attacker, roll_kinds, "", opts.get("reaction", false), String(w.get("type", ""))):
		sources.append(src)
		if src["kind"] == "accuracy":
			acc += int(src["value"])
		else:
			diff += int(src["value"])
	var ranged_like := kind == KIND_RANGED or out.has("thrown")
	if kind == KIND_RANGED and attacker.has_status("Engaged") and not WeaponRules.rules(w).get("ignore_engaged", false) and not Effects.has(attacker, "ignore_engaged"):
		sources.append(_src("Engaged", "difficulty", "statuses: Engaged"))
		diff += 1
	if TalentRules.ignores_cover(state, attacker, w, target) or AISystems.exposed_to(state, attacker, target):
		cover = cover.duplicate()
		cover["cover"] = "none"  # Vanguard See-Through Seeker
		cover["difficulty"] = 0
	if cover.get("cover", "none") == "soft" and target.counters.has("marked_by"):
		cover = cover.duplicate()
		cover["cover"] = "none"  # Markerlight: no soft cover while Locked On
		cover["difficulty"] = 0
	if phase:
		cover = cover.duplicate()
		cover["cover"] = "none"
		cover["difficulty"] = 0
	if int(opts.get("extra_difficulty", 0)) > 0:
		sources.append(_src(String(opts.get("extra_label", "")), "difficulty", Effects.REF, int(opts["extra_difficulty"])))
		diff += int(opts["extra_difficulty"])
	if ranged_like and not seeking and int(cover["difficulty"]) > 0:
		sources.append(_src("Hard cover" if cover["cover"] == "hard" else "Soft cover", "difficulty", Sight.REF_COVER, cover["difficulty"]))
		diff += int(cover["difficulty"])
		var plus := Effects.value(target, "soft_cover_plus")
		if cover["cover"] == "soft" and plus > 0:
			sources.append(_src(String(Effects.of(target, "soft_cover_plus")[0].get("label", "Soft cover")), "difficulty", Effects.REF, plus))
			diff += plus
		out["cover"] = cover
	elif ranged_like:
		out["cover"] = cover
	if WeaponRules.rules(w).get("ignore_difficulty", false):
		diff = 0  # Shatterhead: the final roll is never affected by Difficulty
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
	for b: Dictionary in Effects.attack_bonus(attacker, roll_kinds):
		(out["bonus_sources"] as Array).append(b)
		out["bonus"] = int(out["bonus"]) + int(b["value"])
	if area_origin != null:
		out["kind"] = KIND_RANGED if not Weapons.is_melee(w) else KIND_MELEE
	_defense(out, target, Weapons.has_tag(w, "tg_smart"))
	out["ok"] = true
	out["rule_ref"] = REF_FIGHT
	return out


static func seeking_payload(attacker: Unit, w: Dictionary, target: Unit, opts: Dictionary) -> bool:
	return Effects.has(attacker, "seeking_payload") and w.get("type", "") == "Launcher" and target != null 		and target.has_status("Lock On") and target.side != attacker.side and opts.get("use_lock_on", true)


## Can this weapon be fired at all right now (Jammed, destroyed, Loading, Limited)?
static func weapon_ready(attacker: Unit, w: Dictionary, improvised: bool = false) -> RuleResult:
	if Weapons.state_of(attacker, w).get("uncle_lock", false):
		return RuleResult.deny("UNCLE used %s: it can't be used again until the start of your next turn." % w.get("name", ""), "mods: UNCLE-Class COMP/CON")
	if attacker.has_status("Jammed") and not improvised and not (Effects.has(attacker, "jammed_ranged") and not Weapons.is_melee(w)):
		return RuleResult.deny("Jammed: you can only make Improvised Attacks, Grapple or Ram.", "statuses: Jammed")
	var ws := Weapons.state_of(attacker, w)
	if ws["destroyed"]:
		return RuleResult.deny("%s has been destroyed." % w.get("name", "That weapon"), Combat.REF_STRUCTURE)
	if Weapons.has_tag(w, "tg_loading") and not ws["loaded"]:
		return RuleResult.deny("%s needs reloading (Stabilize reloads it)." % w.get("name", "That weapon"), "tags: Loading")
	if Weapons.has_tag(w, "tg_limited") and int(ws["uses"]) <= 0:
		return RuleResult.deny("%s is out of charges until a Full Repair." % w.get("name", "That weapon"), "tags: Limited")
	if not ws.get("charged", true):
		return RuleResult.deny("%s is recharging (Recharge %d+)." % [w.get("name", "That weapon"), int(ws.get("recharge", 6))], "tags: Recharge")
	return RuleResult.allow()


static func _defense(out: Dictionary, target: Unit, smart: bool) -> void:
	if smart:
		out["defense_name"] = "E-Defense"
		# Smart: targets with no E-Defense count as having 8 (tags: Smart).
		var edef := FrameSystems.shared_stat(TurnRules.state_of(target), target, "edef") if target.counters.has("hosting") else target.edef
		out["target_number"] = edef if edef > 0 else 8
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
	var afterimage: bool = target.counters.get("afterimage", false)
	if afterimage:
		target.counters.erase("afterimage")  # Flicker Field: Invisible the next time it's attacked
	var blocked := Zones.blocking_field(state, attacker, target, w, kind) if not opts.has("area_origin") else {}
	if not blocked.is_empty():
		# Black Witch Mag Field: the projectile stops at the edge; the field records it.
		blocked["blocked"] = int(blocked.get("blocked", 0)) + 1
		events.append({"type": "attack_blocked", "attacker": attacker.id, "target": target.id, "zone": blocked["id"], "rule_ref": Zones.REF_FIELD})
		attacker.turn["attacked"] = true
		if not opts.get("skip_spend", false):
			events.append_array(_spend_weapon(state, attacker, w))
		return events
	events.append_array(AISystems.harmed_by(state, target, attacker))  # attacking a Fourth Gate ally ends it
	events.append_array(GearSystems.sentinel_fire(state, attacker))
	if not Combat.is_present(attacker):
		return events
	var ark := AISystems.ark(state, attacker, target, w)
	events.append_array(ark["events"])
	if ark["miss"]:
		events.append({"type": "attack_rolled", "attacker": attacker.id, "target": target.id, "weapon": w.get("key", ""), "weapon_name": w.get("name", ""),
			"kind": kind, "check": {}, "result": "miss", "cover": "none", "cover_cells": [], "invisible_miss": false, "lock_on_consumed": false,
			"ark": true, "rule_ref": "systems: NOAH-Class NHP"})
		if not opts.get("skip_spend", false):
			events.append_array(_spend_weapon(state, attacker, w))
		events.append_array(AISystems.ark_backlash(state, attacker, target, w))
		return events
	if attacker.counters.has("shrike_code"):
		events.append_array(Combat.apply_heat(state, attacker, 2, "Shrike Code"))  # 2 heat whenever it attacks
	var invisible: bool = target.has_status("Invisible") or afterimage or opts.get("target_invisible", false) or p.get("phase", false) or Zones.hidden_by_smoke(state, target, attacker) \
		or GearSystems.seen_as_invisible(state, attacker, target) or GearSystems.cloaked(state, target)
	if invisible and GearSystems.sees_through(state, attacker, target):
		invisible = false  # Tracking Bug, Lotus Projector
	if invisible:
		# 50% chance to miss outright before the roll (statuses: Invisible).
		var coin := state.dice.die(2)
		invisible_miss = coin == 1
		events.append({"type": "invisible_roll", "attacker": attacker.id, "target": target.id, "roll": coin, "missed": invisible_miss, "rule_ref": "statuses: Invisible"})
	attacker.turn["attacked"] = true
	var thorns := Effects.value(target, "thorns")
	if thorns > 0 and Sight.unit_distance(state, attacker, target) <= Effects.value(target, "thorns", "range"):
		events.append({"type": "effect_triggered", "unit": target.id, "effect": Effects.of(target, "thorns")[0].get("label", ""), "target": attacker.id})
		events.append_array(Combat.deal_damage(state, attacker, [{"type": "Kinetic", "amount": thorns}], {"ap": true, "source": target.id}))
		if not Combat.is_present(attacker):
			return events
	var pre := TraitReactions.before_attack(state, attacker, target)
	events.append_array(pre["events"])
	if pre["cancel"]:
		return events
	var blink := GearSystems.blinkfield(state, attacker, target)
	events.append_array(blink["events"])
	if blink["resist"]:
		pre["resist_all"] = true
	for src: Dictionary in pre["sources"]:
		(p["sources"] as Array).append(src)
		p["difficulty"] = int(p["difficulty"]) + int(src["value"])
	var tb := TalentRules.before_roll(state, attacker, w, target, kind, opts)
	events.append_array(tb["events"])
	var dz_first: bool = state.active_unit == attacker.id and attacker.has_status("Danger Zone") and not attacker.turn.get("dz_used", false)
	if state.active_unit == attacker.id:
		attacker.turn["dz_used"] = true  # only the first attack roll on its turn
	var zero_in: bool = opts.get("zero_in", false) and Effects.has(attacker, "zero_in") and w.get("type", "") == "Rifle" \
		and TalentRules._steadying(attacker) and TalentRules._round_ok(state, attacker, "zero_in")
	if zero_in:
		TalentRules._use_round(state, attacker, "zero_in")
	var check := {}
	var result := "miss"
	var roland: bool = attacker.counters.get("roland", false) and Weapons.has_tag(w, "tg_loading")
	if roland:
		attacker.counters.erase("roland")  # the next attack with a Loading weapon after a reload
	var momentum: bool = kind == KIND_MELEE and attacker.counters.get("momentum", false)
	if momentum:
		attacker.counters.erase("momentum")  # Nelson Momentum: the next melee attack after a Boost
	var chambers := -1
	if Effects.has(attacker, "mjolnir_chambers") and w.get("id", "") == "mw_raleigh_integrated":
		# Raleigh Thunder God: every chamber fires at once, then they're empty.
		chambers = int(attacker.counters.get("chambers", 0))
		attacker.counters["chambers"] = 0
		attacker.turn["fired_mjolnir"] = true
	if tb["auto_miss"]:
		invisible_miss = true  # Skirmisher Weave: no roll, it just misses
	if not invisible_miss:
		check = state.dice.check(p["bonus"], p["accuracy"], p["difficulty"], p["target_number"], p["sources"])
		if TalentRules.particularize(state, attacker, p["lock_on"]):
			# Spotter Particularize: roll twice, keep the better.
			var again := state.dice.check(p["bonus"], p["accuracy"], p["difficulty"], p["target_number"], p["sources"])
			if int(again["total"]) > int(check["total"]):
				check = again
		TalentRules.used_sources(state, attacker, p["sources"])
		check["bonus_sources"] = p["bonus_sources"]
		check["bonuses"] = p["bonus_sources"]
		check["defense"] = p["defense_name"]
		check["target_label"] = p["defense_name"]
		if check["success"]:
			result = "crit" if check["crit"] else "hit"
		if result == "miss" and kind == KIND_RANGED and Effects.has(attacker, "reroll_first_ranged") 				and int(attacker.counters.get("neurolink_round", -1)) != state.round_number:
			# Death's Head Neurolink: may reroll its first ranged attack each round, keeping the
			# second result. The engine rerolls only a miss (a hit is never worth rerolling).
			events.append({"type": "attack_rerolled", "attacker": attacker.id, "target": target.id, "first": check,
				"source": Effects.of(attacker, "reroll_first_ranged")[0].get("label", ""), "rule_ref": "frames: Death's Head, Neurolink"})
			check = state.dice.check(p["bonus"], p["accuracy"], p["difficulty"], p["target_number"], p["sources"])
			check["bonus_sources"] = p["bonus_sources"]
			check["bonuses"] = p["bonus_sources"]
			check["defense"] = p["defense_name"]
			check["target_label"] = p["defense_name"]
			result = ("crit" if check["crit"] else "hit") if check["success"] else "miss"
		if Effects.has(target, "attack_paralysis") and int(check["d20"]) <= 2:
			# Gorgon Metastatic Paralysis: a 1-2 misses and Stuns the attacker.
			result = "miss"
			check["paralysis"] = true
	var ip_events: Array[Dictionary] = []
	if kind == KIND_RANGED and result != "miss":
		var ip := GearSystems.interdiction_point(state, attacker, target, int(check.get("total", 0)))
		ip_events = ip["events"]
		if ip["missed"]:
			result = "miss"  # Stasis Bolt: the attack automatically misses
	events.append({"type": "attack_rolled", "attacker": attacker.id, "target": target.id,
		"weapon": w.get("key", ""), "weapon_name": w.get("name", ""), "kind": kind, "check": check,
		"result": result, "cover": p["cover"].get("cover", "none") if p["cover"] is Dictionary else "none",
		"cover_cells": p["cover"].get("cover_cells", []), "invisible_miss": invisible_miss,
		"lock_on_consumed": p["lock_on"], "rule_ref": p["rule_ref"]})
	if not invisible_miss:
		GearSystems.attack_rolled(attacker, kind, result != "miss")
		TalentRules.after_roll(state, attacker, w, target, kind, result, p["lock_on"])
	if result == "hit" and GearSystems.markerlight_crit(state, attacker, target):
		result = "crit"  # Markerlight: a weak spot
		events[events.size() - 1]["result"] = "crit"
		events[events.size() - 1]["markerlight"] = true
	events.append_array(ip_events)
	if result != "miss":
		var par := TraitReactions.parry(state, attacker, w, target)
		events.append_array(par["events"])
		if par["missed"]:
			result = "miss"
			events[events.size() - 1 - (par["events"] as Array).size()]["result"] = "miss"
			events[events.size() - 1 - (par["events"] as Array).size()]["parried"] = true
	if kind == KIND_RANGED and not invisible_miss:
		attacker.counters["neurolink_round"] = state.round_number
	if state.active_unit == attacker.id:
		var fired: Array = attacker.turn.get("fired", [])
		fired.append(String(w.get("key", "")))
		attacker.turn["fired"] = fired
		if result != "miss":
			var hits: Dictionary = attacker.turn.get("hits", {})
			var list: Array = hits.get(String(w.get("key", "")), [])
			list.append(target.id)
			hits[String(w.get("key", ""))] = list
			attacker.turn["hits"] = hits
	if not opts.get("skip_spend", false):
		events.append_array(_spend_weapon(state, attacker, w))
	if check.get("paralysis", false):
		events.append_array(Combat.add_status(state, attacker, "Stunned", target.id, attacker.id))
	if result != "miss":
		var hit_opts := opts.duplicate()
		hit_opts["preview"] = p
		hit_opts["momentum"] = momentum
		hit_opts["chambers"] = chambers
		hit_opts["resist_all"] = pre["resist_all"]
		hit_opts["roland"] = roland
		hit_opts["d20"] = int(check.get("d20", 0))
		hit_opts["dz_heat"] = dz_first and Effects.has(attacker, "dz_heat")
		hit_opts["dz_fusion"] = dz_first and Effects.has(attacker, "dz_fusion") and kind != KIND_TECH
		hit_opts["zero_in"] = zero_in
		events.append_array(_hit(state, attacker, w, target, result == "crit", hit_opts))
		if result == "crit" and kind == KIND_RANGED:
			events.append_array(avenger_silos(state, attacker, target))
		if result == "crit" and WeaponRules.rules(w).has("on_crit_teleport") and opts.has("fold_to"):
			# Fold Knife: teleport up to 2 spaces after the attack resolves.
			var plan := Movement.plan_teleport(state, attacker, TurnAction.cell_param(opts, "fold_to"), -1, Movement.MODE_MOVE, int(WeaponRules.rules(w)["on_crit_teleport"]))
			if plan["ok"]:
				var last: Array = (plan["path"] as Array).back()
				attacker.cell = Vector2i(last[0], last[1])
				attacker.level = int(last[2])
				events.append({"type": "moved", "unit": attacker.id, "path": plan["path"], "mode": "teleport", "cost": 0, "rule_ref": "weapons: Fold Knife"})
				events.append_array(Combat.after_movement(state))
		events.append_array(GearSystems.turret_attacks(state, attacker, target))
	elif Weapons.tag_value(w, "tg_reliable") > 0:
		var dtype := String((w.get("damage", [{}]) as Array)[0].get("type", "Kinetic")) if not (w.get("damage", []) as Array).is_empty() else "Kinetic"
		var parts := [{"type": dtype, "amount": Weapons.tag_value(w, "tg_reliable")}]
		events.append({"type": "reliable_damage", "attacker": attacker.id, "target": target.id, "amount": Weapons.tag_value(w, "tg_reliable"), "rule_ref": "tags: Reliable"})
		events.append_array(_apply(state, attacker, target, parts, Weapons.has_tag(w, "tg_ap") or Environments.weapons_ap(state), opts.has("area_origin"), false, pre["resist_all"]))
	if p["lock_on"]:
		events.append_array(Combat.remove_status(target, "Lock On", "consumed by " + attacker.id))
	if attacker.has_status("Hidden"):
		events.append_array(Combat.remove_status(attacker, "Hidden", "attacked"))
		events.append_array(Combat.refresh_engagement(state))
	if result == "miss":
		events.append_array(AISystems.ark_backlash(state, attacker, target, w))
	if not opts.get("reaction", false):
		events.append_array(AISystems.scylla(state, attacker, target))
	Effects.attacked(state, attacker, String(opts.get("action", "attack")))
	return events


static func _spend_weapon(state: GameState, attacker: Unit, w: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var ws := Weapons.state_of(attacker, w)
	if Weapons.has_tag(w, "tg_loading"):
		ws["loaded"] = false
	if Weapons.has_tag(w, "tg_limited"):
		ws["uses"] = int(ws["uses"]) - 1
	if ws.has("recharge"):
		ws["charged"] = false
	var self_heat := Weapons.tag_value(w, "tg_heat_self")
	if self_heat > 0:
		events.append_array(Combat.apply_heat(state, attacker, Environments.gear_heat(state, self_heat), "Heat (Self): " + String(w.get("name", ""))))
	return events


static func _hit(state: GameState, attacker: Unit, w: Dictionary, target: Unit, crit: bool, opts: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var parts: Array = []
	var overkill_heat := 0
	var total := 0
	var shared: Dictionary = opts.get("shared_damage", {})
	var damage: Array = w.get("damage", [])
	var ap := Weapons.has_tag(w, "tg_ap") or Environments.weapons_ap(state)  # corrosive atmosphere
	var obj := FrameSystems.object_damage(attacker, w, target)
	if not obj.is_empty():
		damage = obj  # Sherman COREBURN against objects and deployables
		ap = true
	var instead := WeaponRules.damage_override(attacker, w, target)
	if not instead.is_empty():
		damage = instead
		ap = ap or instead[0].get("ap", false)
	var chambers := int(opts.get("chambers", -1))
	if chambers >= 0:
		# Raleigh Thunder God: 4 kinetic per loaded round; four or more gain AP and Shred.
		damage = [{"type": "Kinetic", "val": str(4 * chambers)}]
		ap = ap or chambers >= 4
	var roland: bool = opts.get("roland", false)
	if Weapons.has_tag(w, "tg_archaic") and target.kind != Unit.KIND_PILOT:
		damage = []  # Archaic weapons can't harm mechs (tags: Archaic).
		events.append({"type": "no_effect", "target": target.id, "reason": "Archaic weapons can't harm mechs.", "rule_ref": "tags: Archaic"})
	# Pegasus "By the Way, I Know Everything": average damage instead of rolling, decided first.
	var average: bool = opts.get("average_damage", false) and Effects.has(attacker, "average_damage_option")
	var maximum := TalentRules.max_damage(attacker, crit, int(opts.get("d20", 0)))  # Brutal: Predator
	for i in range(damage.size()):
		var d: Dictionary = damage[i]
		var dtype := Weapons.swapped_type(attacker, String(d.get("type", "Kinetic")))
		if opts.get("dz_fusion", false) and dtype in ["Kinetic", "Explosive"]:
			dtype = "Energy"  # Nuclear Cavalier Fusion Hemorrhage
		if dtype == "Variable" and String(opts.get("damage_type", "")) in ["Kinetic", "Explosive", "Energy"]:
			dtype = String(opts["damage_type"])  # you set its damage type (tags: Set Damage Type)
		var r := average_roll(str(d.get("val", "0"))) if average else _shared_roll(state, shared, i, str(d.get("val", "0")), crit, Weapons.has_tag(w, "tg_overkill"))
		if maximum:
			r = max_roll(str(d.get("val", "0")))
		overkill_heat += int(r["overkill_heat"])
		events.append({"type": "damage_rolled", "attacker": attacker.id, "target": target.id, "damage_type": dtype, "roll": r, "crit": crit, "rule_ref": REF_CRIT if crit else Combat.REF_HARM})
		parts.append({"type": dtype, "amount": int(r["total"])})
		total += int(r["total"])
	var reliable := Weapons.tag_value(w, "tg_reliable")
	if reliable > 0 and total < reliable and not parts.is_empty():
		parts[0]["amount"] = int(parts[0]["amount"]) + reliable - total
		events.append({"type": "reliable_damage", "attacker": attacker.id, "target": target.id, "amount": reliable, "rule_ref": "tags: Reliable"})
	if roland and not opts.get("no_bonus_damage", false):
		# Roland Chamber: +1d6 explosive bonus damage (Core p.67 rules apply).
		var rr := roll_damage(state, "1d6", crit, false)
		var amount := int(rr["total"])
		if int(opts.get("area_targets", 1)) > 1:
			amount -= amount / 2
		events.append({"type": "bonus_damage", "attacker": attacker.id, "target": target.id, "source": "Roland Chamber", "damage_type": "Explosive", "roll": rr, "amount": amount, "halved": int(opts.get("area_targets", 1)) > 1, "rule_ref": "systems: Roland Chamber"})
		parts.append({"type": "Explosive", "amount": amount})
	var drill := WeaponRules.drill_bonus(state, attacker, w, target, overkill_heat)
	if int(drill["total"]) > 0 or int(drill["heat"]) > 0:
		events.append_array(drill["events"])
		parts.append({"type": "Kinetic", "amount": int(drill["total"])})
		overkill_heat += int(drill["heat"])
	if String(w.get("npc_on_hit", "")) != "":
		# An NPC weapon's on-hit rule the game doesn't encode: the table applies it.
		events.append({"type": "manual_effect", "unit": attacker.id, "source": String(w.get("name", "")), "text": String(w["npc_on_hit"]),
			"note": "On hit (not automated): the table applies this.", "guidance": Automation.MANUAL_GUIDANCE})
	var pv: Dictionary = opts.get("preview", {})
	if not opts.get("no_bonus_damage", false) and not damage.is_empty():
		# PROVISIONAL (docs/RULES_TODO.md): bonus damage only on attacks that deal damage.
		var cover: Variant = pv.get("cover", {})
		var b := BonusDamage.roll(state, attacker, w, target, {"kind": pv.get("kind", ""), "crit": crit,
			"cover": (cover as Dictionary).get("cover", "none") if cover is Dictionary else "none",
			"distance": int(pv.get("distance", 0)), "targets": int(opts.get("area_targets", 1)), "shared": shared,
			"momentum": opts.get("momentum", false), "dz_fusion": opts.get("dz_fusion", false), "zero_in": opts.get("zero_in", false), "max": maximum,
			"thermal_charge": opts.get("thermal_charge", false)})
		events.append_array(b["events"])
		parts.append_array(b["parts"])
	var burn := Weapons.tag_value(w, "tg_burn")
	if burn > 0:
		parts.append({"type": "Burn", "amount": burn})
	var heat := Weapons.tag_value(w, "tg_heat_target")
	if heat > 0:
		parts.append({"type": "Heat", "amount": heat})
	if overkill_heat > 0 and not shared.get("overkill_paid", false):
		shared["overkill_paid"] = true
		events.append_array(Combat.apply_heat(state, attacker, Environments.gear_heat(state, overkill_heat), "Overkill"))
	if pv.get("tomorrow", false):
		attacker.counters.erase("tomorrow")
	events.append_array(_apply(state, attacker, target, parts, ap, opts.has("area_origin"), pv.get("seeking_payload", false) or Weapons.has_tag(w, "tg_irreducible") or pv.get("tomorrow", false), opts.get("resist_all", false), opts.get("half_damage", false)))
	if chambers >= 4 and Combat.is_present(target):
		events.append_array(Combat.add_status(state, target, "Shredded", attacker.id, target.id))
	events.append_array(WeaponRules.on_hit(state, attacker, w, target, crit))
	var pvk := String(pv.get("kind", ""))
	events.append_array(TalentRules.on_hit(state, attacker, w, target, crit, pvk, pv.get("lock_on", false), opts))
	if roland and Combat.is_present(target):
		var save := Combat.skill_check(state, target, "hull", "Save vs Roland Chamber", attacker.save_target, 0, 0, GearSystems.prone_save_sources(target), true)
		events.append({"type": "skill_check", "unit": target.id, "check": save, "rule_ref": "systems: Roland Chamber"})
		if not save["success"]:
			events.append_array(Combat.add_status(state, target, "Prone", attacker.id))
	var kb := Weapons.tag_value(w, "tg_knockback")
	if Weapons.is_melee(w):
		kb = maxi(kb, Effects.value(attacker, "melee_knockback"))  # Ramjet
	if crit:
		kb = maxi(kb, Effects.value(attacker, "crit_knockback"))  # Brutal: Cull the Herd
	if Weapons.is_melee(w) and kb > 0 and Effects.has(attacker, "titanomachy"):
		kb += 1  # Titanomachy Mesh: one more space
	var want: Variant = opts.get("knockback", false)
	if kb > 0 and not target.destroyed and want != null and (want is int or bool(want)):
		var spaces: int = mini(kb, int(want)) if want is int else kb
		events.append_array(knock_back(state, target, opts.get("knockback_from", attacker.cell), spaces, attacker))
	return events


## Maximum damage for a dice expression (Brutal: Predator).
static func max_roll(expr: String) -> Dictionary:
	var total := 0
	var clean := expr.replace(" ", "").to_lower()
	for term in clean.replace("-", "+-").split("+", false):
		var sign := -1 if term.begins_with("-") else 1
		var t := term.trim_prefix("-")
		if "d" in t:
			var nd := t.split("d")
			total += sign * (int(nd[0]) if nd[0] != "" else 1) * int(nd[1])
		else:
			total += sign * int(t)
	return {"expr": expr, "dice": [], "kept": [], "bonus": 0, "total": maxi(0, total), "crit": true, "overkill_heat": 0, "maximum": true}


## Average damage for a dice expression: each die counts as (sides + 1) / 2 rounded up, so
## 1d3 = 2, 1d6 = 4, 2d6 = 7, 3d6 = 11, 4d6 = 14 (Pegasus trait table), plus flat bonuses.
static func average_roll(expr: String) -> Dictionary:
	var total := 0
	var clean := expr.replace(" ", "").to_lower()
	for term in clean.replace("-", "+-").split("+", false):
		var sign := -1 if term.begins_with("-") else 1
		var t := term.trim_prefix("-")
		if "d" in t:
			var nd := t.split("d")
			var n := int(nd[0]) if nd[0] != "" else 1
			total += sign * ceili(n * (int(nd[1]) + 1) / 2.0)
		else:
			total += sign * int(t)
	return {"expr": expr, "dice": [], "kept": [], "bonus": 0, "total": maxi(0, total), "crit": false, "overkill_heat": 0, "average": true}


## Monarch Avenger Silos: 1/round, on a ranged critical hit, 3 explosive to a different
## character of the Monarch's choice within range 15 and line of sight. The player picks the
## target (a `reaction_offered` with reaction "avenger_silos" and context.targets).
static func avenger_silos(state: GameState, attacker: Unit, target: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var effs := Effects.of(attacker, "avenger_silos")
	if effs.is_empty() or int(attacker.counters.get("avenger_round", -1)) == state.round_number:
		return events
	var e: Dictionary = effs[0]
	var ids: Array = []
	var best := ""
	var best_d := 999
	var keys: Array = state.units.keys()
	keys.sort()
	for id: String in keys:
		var o := state.unit(id)
		if o == attacker or o == target or not Combat.is_present(o) or o.kind == Unit.KIND_DEPLOYABLE or o.has_status("Hidden"):
			continue
		var d := Sight.unit_distance(state, attacker, o)
		if d > int(e.get("range", 15)) or not Sight.unit_line_of_sight(state, attacker, o):
			continue
		ids.append(id)
		if o.side != attacker.side and d < best_d:
			best = id
			best_d = d
	if ids.is_empty():
		return events
	var auto := {"take": best != "", "target": best}
	var choice := Reactions.offer(state, attacker, "avenger_silos", {"targets": ids, "trigger": target.id, "suggested": auto}, auto)
	var pick := state.unit(String(choice.get("target", "")))
	if not choice.get("take", false) or pick == null or not ids.has(pick.id):
		return events
	attacker.counters["avenger_round"] = state.round_number
	events.append({"type": "effect_triggered", "unit": attacker.id, "effect": e.get("label", "Avenger Silos"), "target": pick.id, "rule_ref": "frames: Monarch, Avenger Silos"})
	events.append_array(Combat.deal_damage(state, pick, [{"type": "Explosive", "amount": int(e.get("damage", 3))}], {"source": attacker.id}))
	return events


## Applies a hit's damage parts, letting the target Brace if its reaction policy says so.
## `unreducible`: the damage can't be reduced in any way (Monarch Seeking Payload).
## `resist_all`: Resistance to all of it from another rule (Saladin Defensive Pulse).
static func _apply(state: GameState, attacker: Unit, target: Unit, parts: Array, ap: bool, area: bool = false, unreducible: bool = false, resist_all: bool = false, half: bool = false) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var sim := TraitReactions.before_damage(state, attacker, target) if not parts.is_empty() else {"events": [], "resist_all": false, "teleport": {}}
	events.append_array(sim["events"])
	resist_all = resist_all or sim["resist_all"]
	var brace := false
	if not unreducible and Reactions.can_react(target, "brace", state).ok and not parts.is_empty():
		var d := Reactions.offer(state, target, "brace", {"attacker": attacker.id, "damage": parts, "ap": ap},
			{"take": _wants_brace(target, parts, ap)})
		brace = d.get("take", false)
	if brace:
		events.append_array(Reactions.brace(state, target, attacker.id))
	var aegis := brace and Effects.has(target, "flash_aegis")
	if half:
		var halved_parts: Array = []
		for p: Dictionary in parts:
			var c := p.duplicate()
			c["amount"] = int(c.get("amount", 0)) - int(c.get("amount", 0)) / 2
			halved_parts.append(c)
		parts = halved_parts  # SCYLLA reactions: half damage, heat and burn
	# HyperDense Armor: half damage, heat and burn to characters beyond its range.
	var dist := Sight.unit_distance(state, attacker, target)
	for e: Dictionary in Effects.of(attacker, "half_damage_beyond"):
		if dist > int(e.get("value", 3)):
			var halved: Array = []
			for p: Dictionary in parts:
				var c := p.duplicate()
				c["amount"] = int(c.get("amount", 0)) - int(c.get("amount", 0)) / 2
				halved.append(c)
			parts = halved
			break
	var gen := GearSystems.aegis_reduce(state, target, parts)
	events.append_array(gen["events"])
	parts = gen["parts"]
	var energy_resist := Zones.oasis_cover(state, target)  # Oasis Wall: Resistance to energy
	var guard := GearSystems.argonaut_for(state, target)
	if guard != null and guard != attacker:
		# Argonaut Shield: Resistance for the target; the shield-bearer takes half the damage
		# before Armor and Resistance.
		resist_all = true
		var share: Array = []
		for p: Dictionary in parts:
			if p.get("type", "") != "Heat" and int(p.get("amount", 0)) > 0:
				share.append({"type": p["type"], "amount": int(p["amount"]) - int(p["amount"]) / 2, "mark": false})
		events.append({"type": "effect_triggered", "unit": guard.id, "effect": "Argonaut Shield", "target": target.id, "rule_ref": "systems: Argonaut Shield"})
		events.append_array(Combat.deal_damage(state, guard, share, {"source": attacker.id}))
	if area and Zones.bunker_protects(state, target, attacker):
		resist_all = true  # Portable Bunker: Resistance to area attacks from outside
	events.append_array(Combat.deal_damage(state, target, parts, {"source": attacker.id, "ap": ap, "resist_all": (brace and not aegis) or resist_all,
		"damage_to_one": aegis, "area": area, "distance": Sight.unit_distance(state, attacker, target), "unreducible": unreducible,
		"resist_types": ["Energy"] if energy_resist else []}))
	events.append_array(TraitReactions.teleport(state, target, sim["teleport"]))
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
static func knock_back(state: GameState, target: Unit, origin: Vector2i, spaces: int, by: Unit = null) -> Array[Dictionary]:
	var anchor := GearSystems.flash_anchor(state, target, "knockback")
	if anchor["prevented"]:
		return anchor["events"]
	if Effects.has(target, "immovable"):
		return [{"type": "knockback_blocked", "unit": target.id, "reason": "Immune to involuntary movement.", "rule_ref": Effects.REF}] as Array[Dictionary]
	if by != null and by.size < target.size and Effects.has(target, "heavy_frame"):
		return [{"type": "knockback_blocked", "unit": target.id, "reason": "Heavy Frame: smaller characters can't knock it back.", "rule_ref": Effects.REF}] as Array[Dictionary]
	var path := Movement.push_path(state, target, origin, spaces)
	if path.size() < 2:
		return [{"type": "knockback_blocked", "unit": target.id, "rule_ref": "tags: Knockback"}] as Array[Dictionary]
	var last: Array = path.back()
	target.cell = Vector2i(last[0], last[1])
	var events: Array[Dictionary] = [{"type": "moved", "unit": target.id, "path": path, "mode": "involuntary", "cost": 0, "rule_ref": "tags: Knockback"}]
	events.append_array(Effects.punish_movement(state, target))
	events.append_array(Abilities.check_mines(state, target, path))
	events.append_array(Zones.check_path(state, target, path))
	if Movement.placement(state, target.size, target.cell, target.level)["airborne"] and not target.flying:
		events.append_array(Combat.begin_falling(target, "Knocked off a ledge."))
	events.append_array(Combat.after_movement(state))
	return events


## Pulled toward `by` until adjacent, or as close as possible (Blackbeard Omni-harpoon):
## involuntary movement, one space at a time to the free space nearest `by`.
static func pull(state: GameState, target: Unit, by: Unit) -> Array[Dictionary]:
	if Effects.has(target, "heavy_frame") and by.size < target.size:
		return [{"type": "knockback_blocked", "unit": target.id, "reason": "Heavy Frame: smaller characters can't move it.", "rule_ref": Effects.REF}] as Array[Dictionary]
	return pull_to(state, target, Sight.body_of(state, by), 1)


## Involuntary movement toward `goal` until within `reach` (0: onto it) or no closer.
static func pull_to(state: GameState, target: Unit, goal: Sight.Body, reach: int, max_steps: int = 100) -> Array[Dictionary]:
	var anchor := GearSystems.flash_anchor(state, target, "pull")
	if anchor["prevented"]:
		return anchor["events"]
	if Effects.has(target, "immovable"):
		return [{"type": "knockback_blocked", "unit": target.id, "reason": "Immune to involuntary movement.", "rule_ref": Effects.REF}] as Array[Dictionary]
	var path := Movement.pull_path_to(state, target, goal, reach, max_steps)
	if path.size() < 2:
		return [] as Array[Dictionary]
	var last: Array = path.back()
	target.cell = Vector2i(last[0], last[1])
	target.level = int(last[2])
	var events: Array[Dictionary] = [{"type": "moved", "unit": target.id, "path": path, "mode": "involuntary", "cost": 0, "rule_ref": "glossary: Involuntary Movement"}]
	events.append_array(Effects.punish_movement(state, target))
	events.append_array(Abilities.check_mines(state, target, path))
	events.append_array(Zones.check_path(state, target, path))
	events.append_array(Combat.after_movement(state))
	return events


## A tech attack: d20 + Tech Attack vs E-Defense. Range is SENSORS and needs line of sight
## (Core p.64): tech attacks ignore cover and can't crit.
static func tech_preview(state: GameState, attacker: Unit, target: Unit, opts: Dictionary = {}) -> Dictionary:
	var tech_bonus: int = int(opts["tech_bonus"]) if opts.has("tech_bonus") else FrameSystems.shared_stat(state, attacker, "tech_attack")
	var out := {"ok": false, "reason": "", "rule_ref": "actions: Invade", "kind": KIND_TECH, "accuracy": int(opts.get("tech_accuracy", 0)),
		"difficulty": 0, "sources": [], "bonus": tech_bonus,
		"bonus_sources": [{"label": "Tech Attack", "value": tech_bonus}],
		"defense_name": "E-Defense", "target_number": FrameSystems.shared_stat(state, target, "edef") if target else 0, "lock_on": false}
	var r := tech_target_check(state, attacker, target)
	if not r.ok:
		out["reason"] = r.reason
		out["rule_ref"] = r.rule_ref
		return out
	if Effects.has(attacker, "no_attacks"):
		out["reason"] = "You can't make attacks of any kind right now (Retractable Profile)."
		return out
	var sources: Array = []
	if target.has_status("Lock On") and target.side != attacker.side and opts.get("use_lock_on", true):
		sources.append(_src("Lock On", "accuracy", "statuses: Lock On"))
		out["accuracy"] = int(out["accuracy"]) + 1
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
	var ice := GearSystems.black_ice(state, target)
	if not ice.is_empty():
		sources.append(_src("Black ICE", "difficulty", "systems: Black ICE Module", int(ice["value"])))
		out["difficulty"] = int(out["difficulty"]) + int(ice["value"])
		out["black_ice"] = ice["unit"].id
	for e: Dictionary in Effects.of(target, "defense_difficulty"):
		if e.has("vs") and not (e["vs"] as Array).has("tech"):
			continue
		sources.append(_src(String(e.get("label", "")), "difficulty", Effects.REF, int(e.get("value", 1))))
		out["difficulty"] = int(out["difficulty"]) + int(e.get("value", 1))
	if Effects.has(attacker, "adjacent_tech_accuracy") and Sight.unit_distance(state, attacker, target) <= 1:
		sources.append(_src("Scanner Swarm", "accuracy", "systems: Scanner Swarm"))
		out["accuracy"] = int(out["accuracy"]) + 1
	for src: Dictionary in Effects.accuracy_sources(attacker, ["attack", "tech_attack"]):
		sources.append(src)
		var key := "accuracy" if src["kind"] == "accuracy" else "difficulty"
		out[key] = int(out[key]) + int(src["value"])
	out["sources"] = sources
	out["ok"] = true
	return out


## Shared checks for any tech action at a target: within SENSORS and line of sight, not
## Hidden, not Shut Down, and the user not Jammed.
static func tech_target_check(state: GameState, user: Unit, target: Unit, action: String = "") -> RuleResult:
	if user.has_status("Jammed"):
		return RuleResult.deny("Jammed: you can't take tech actions.", "statuses: Jammed")
	if target == null or target.destroyed:
		return RuleResult.deny("No valid target.", "actions: Quick Tech")
	if Effects.has(target, "aegis"):
		return RuleResult.deny("Inside the Trueblack Aegis it's immune to all tech actions.", "frames: Napoleon core system")
	if GearSystems.in_stasis(target):
		return RuleResult.deny("In stasis: it can't be targeted.", "systems: Stasis Generator")
	if GearSystems.iceout(state, target) or GearSystems.iceout(state, user):
		return RuleResult.deny("Inside an ICEOUT field: immune to tech actions, and none can be taken.", "systems: ICEOUT Drone")
	if target.has_status("Hidden") and target.side != user.side:
		return RuleResult.deny("Hidden characters can't be targeted.", "statuses: Hidden")
	if target.has_status("Shut Down"):
		return RuleResult.deny("Shut Down mechs are immune to tech actions.", "statuses: Shut Down")
	if target.kind == Unit.KIND_PILOT and action != "scan" and action != "lock_on":
		return RuleResult.deny("Pilots on foot are BIOLOGICAL: immune to tech actions except Lock On and Scan.", "Core p.74 Fighting on the Ground")
	var in_sensors := Sight.within(state, Sight.body_of(state, user), Sight.body_of(state, target), user.sensors)
	if in_sensors["grey_area"] != "":
		return Rulings.needed(in_sensors["grey_area"])
	if not in_sensors["ok"]:
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
	var unseen: bool = (target.has_status("Invisible") or Zones.hidden_by_smoke(state, target, attacker) or GearSystems.seen_as_invisible(state, attacker, target) 		or GearSystems.cloaked(state, target)) and not GearSystems.sees_through(state, attacker, target)
	if unseen:
		var coin := state.dice.die(2)
		invisible_miss = coin == 1
		events.append({"type": "invisible_roll", "attacker": attacker.id, "target": target.id, "roll": coin, "missed": invisible_miss, "rule_ref": "statuses: Invisible"})
	var pre := TraitReactions.before_attack(state, attacker, target)
	events.append_array(pre["events"])
	if pre["cancel"]:
		return {"events": events, "hit": false}
	events.append_array(GearSystems.sentinel_fire(state, attacker))
	if attacker.counters.has("shrike_code"):
		events.append_array(Combat.apply_heat(state, attacker, 2, "Shrike Code"))
	if p.has("black_ice"):
		GearSystems.black_ice_used(state.unit(String(p["black_ice"])))
	for src: Dictionary in pre["sources"]:
		(p["sources"] as Array).append(src)
		p["difficulty"] = int(p["difficulty"]) + int(src["value"])
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
	Effects.attacked(state, attacker, "tech")
	if hit and Effects.has(attacker, "tomorrows_thought"):
		attacker.counters["tomorrow"] = target.id  # the next melee attack on it: +1 Accuracy, unreducible
	if hit and p["lock_on"] and Effects.has(attacker, "snow_crash"):
		events.append_array(Combat.apply_heat(state, target, 2, attacker.id))  # Hacker SNOW_CRASH
	if hit:
		events.append_array(TraitReactions.tech_hit(state, attacker, target))
	else:
		events.append_array(GearSystems.scorpion(state, attacker, target))
	return {"events": events, "hit": hit}
