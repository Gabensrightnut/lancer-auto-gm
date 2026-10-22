class_name Combat
extends RefCounted
## Damage, heat, structure and stress, statuses, checks, falling, engagement and Hidden upkeep.
## Called by action handlers; every function returns the events it caused.
##
## Book rules used (lancer-data text): Harm/Calculating Damage order, Armor, Resistance,
## Exposed, Shredded, Overshield, Burn, Heat Capacity, HP, Structure, Stress, the Structure
## Damage and Overheating tables (tables.json), Falling, Flight, Engaged, Hidden, Stunned.
## Core p.12 (always round up), p.63 (falling), p.67 (damage order, Armor once per source),
## p.80-81 (structure, overheating, meltdown), p.13 (checks succeed on 10+).
## Table rulings (Rulings): heat overflow, unforced save targets. The map gives the dangerous
## terrain type. System Trauma picks the first valid mount/system until the UI offers the
## choice (a UI gap, not a rule).

const REF_HARM := "glossary: Harm/Calculating Damage"
const REF_STRUCTURE := "tables: Structure Damage"
const REF_OVERHEAT := "tables: Overheating"
const REF_HEAT := "glossary: Heat Capacity"
const REF_FALL := "Core p.63 Falling"
const REF_BURN := "glossary: Burn"
const REF_PROVISIONAL := "PROVISIONAL (docs/RULES_TODO.md)"
const CHECK_TARGET := 10
const SKILLS := ["hull", "agility", "systems", "engineering"]
const DOUBLED_BY_EXPOSED := ["Kinetic", "Explosive", "Energy"]


# --- Statuses -------------------------------------------------------------------------

## Adds a status. `next_turn_end_of` = a unit whose "end of next turn" ends it ("" = lasts).
static func add_status(state: GameState, u: Unit, status: String, source: String, next_turn_end_of: String = "", until_start_of: String = "") -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	status = Environments.slowed_becomes(state, u, status)  # high gravity
	if status == "Shut Down" and u.counters.has("hacked"):
		(u.counters["hacked"] as Dictionary).erase("hack_slash")  # Hack/Slash ends when it shuts down
	if status == "Prone" and u.flying:
		return events  # Flying characters have IMMUNITY to PRONE (glossary: Flight/Hover).
	if status == "Prone" and not u.has_status("Prone"):
		var fa := GearSystems.flash_anchor(state, u, "prone")
		if fa["prevented"]:
			return fa["events"]
	if Effects.immune_to_status(u, status):
		return [{"type": "status_blocked", "unit": u.id, "status": status, "reason": "Immune.", "rule_ref": "glossary: Immunity"}] as Array[Dictionary]
	var entry := {"source": source}
	if until_start_of != "":
		entry["turn_start_of"] = until_start_of
	if next_turn_end_of != "":
		entry["turn_of"] = next_turn_end_of
		# "Until the end of your next turn": if it's that unit's turn now, not this one.
		entry["turns"] = 2 if state.active_unit == next_turn_end_of else 1
	var had := u.has_status(status)
	if had:
		var old: Dictionary = u.statuses[status]
		if not old.has("turn_of") or (entry.has("turn_of") and int(old.get("turns", 0)) >= int(entry["turns"])):
			return events
	u.statuses[status] = entry
	if not had:
		events.append({"type": "status_added", "unit": u.id, "status": status, "source": source})
	if status == "Immobilized" and Effects.has(state.unit(source), "immobilize_shreds"):
		var shred := entry.duplicate()
		u.statuses["Shredded"] = shred
		events.append({"type": "status_added", "unit": u.id, "status": "Shredded", "source": source})
	if u.flying and (status == "Immobilized" or status == "Stunned"):
		events.append_array(begin_falling(u, "Flying characters begin falling if Immobilized or Stunned."))
	if not had:
		events.append_array(FrameSystems.on_status(state, u, status))
	return events


static func remove_status(u: Unit, status: String, source: String = "") -> Array[Dictionary]:
	if not u.statuses.has(status):
		return [] as Array[Dictionary]
	u.statuses.erase(status)
	GearSystems.status_ended(u, status)
	return [{"type": "status_removed", "unit": u.id, "status": status, "source": source}] as Array[Dictionary]


## Ends statuses that last "until the start of <u>'s next turn".
static func expire_at_turn_start(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for x: Unit in state.units.values():
		for status: String in x.statuses.keys():
			if x.statuses[status].get("turn_start_of", "") == u.id:
				events.append_array(remove_status(x, status, "expired"))
	return events


## Ends statuses that last "until the end of <ended>'s next turn".
static func expire_statuses(state: GameState, ended: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for u: Unit in state.units.values():
		for status: String in u.statuses.keys():
			var e: Dictionary = u.statuses[status]
			if e.get("turn_of", "") != ended.id:
				continue
			e["turns"] = int(e.get("turns", 1)) - 1
			if int(e["turns"]) <= 0:
				events.append_array(remove_status(u, status, "expired"))
	return events


# --- Checks ---------------------------------------------------------------------------

## A mech skill check or save: d20 + skill vs `target`, with Impaired as +1 Difficulty.
## STUNNED mechs automatically fail HULL and AGILITY checks and saves (statuses: Stunned).
static func skill_check(state: GameState, u: Unit, skill: String, label: String, target: int = CHECK_TARGET, accuracy: int = 0, difficulty: int = 0, sources: Array = [], is_save: bool = false) -> Dictionary:
	var all_sources := sources.duplicate()
	var diff := difficulty
	var bonus_acc := 0
	for src: Dictionary in Effects.accuracy_sources(u, ["save" if is_save else "check"], skill) + TalentRules.bond_sources(state, u):
		all_sources.append(src)
		if src["kind"] == "accuracy":
			bonus_acc += int(src["value"])
		else:
			diff += int(src["value"])
	if is_save and (u.counters.get("hacked", {}) as Dictionary).has("life_support"):
		diff += 1  # Hacker Disable Life Support
		all_sources.append({"label": "Life support disabled", "kind": "difficulty", "type": "difficulty", "value": 1, "rule_ref": "talents: Hacker"})
	if u.has_status("Impaired"):
		diff += 1
		all_sources.append({"label": "Impaired", "kind": "difficulty", "type": "difficulty", "value": 1, "rule_ref": "statuses: Impaired"})
	var acc := accuracy + bonus_acc
	if u.has_status("Bolstered"):
		# +2 Accuracy on the next skill check or save (actions: Bolster), then it's used up.
		acc += 2
		all_sources.append({"label": "Bolstered", "kind": "accuracy", "type": "accuracy", "value": 2, "rule_ref": "actions: Bolster"})
		u.statuses.erase("Bolstered")
	var bonus := int(u.get(skill)) if SKILLS.has(skill) else 0
	if skill == "systems" and u.counters.has("hosting"):
		bonus = FrameSystems.shared_stat(state, u, "systems")  # Goblin Symbiosis
	if u.kind == Unit.KIND_PILOT:
		bonus = u.grit  # unmounted characters add GRIT to attacks and saves (Core p.74)
	var record := state.dice.check(bonus, acc, diff, target, all_sources)
	if u.kind == Unit.KIND_MECH:
		record = TalentRules.nhp_reroll(state, u, record, func() -> Dictionary: return state.dice.check(bonus, acc, diff, target, all_sources))
	record["bonus_sources"] = [{"label": "Grit" if u.kind == Unit.KIND_PILOT else skill.capitalize(), "value": bonus}]
	record["bonuses"] = record["bonus_sources"]
	record["target_label"] = "Save Target" if target != CHECK_TARGET else "Check (10+)"
	record["skill"] = skill
	record["label"] = label
	if u.has_status("Stunned") and (skill == "hull" or skill == "agility"):
		record["success"] = false
		record["auto_fail"] = "Stunned mechs automatically fail Hull and Agility checks and saves."
	for e: Dictionary in Effects.of(u, "auto_save"):
		if (e.get("skills", []) as Array).has(skill):
			record["success"] = true  # Armor-Lock Plating: can't fail these
			record["auto_success"] = String(e.get("label", ""))
	return record


# --- Damage ---------------------------------------------------------------------------

## Deals one hit's damage to `target`. `parts` = [{"type": "Kinetic", "amount": 7}, ...].
## opts: source (unit id), ap (ignores Armor), resist_all (Brace), no_mark_burn, roll.
static func deal_damage(state: GameState, target: Unit, parts: Array, opts: Dictionary = {}) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if target.destroyed:
		return events
	if GearSystems.intangible(target) or GearSystems.intangible(state.unit(String(opts.get("source", "")))):
		return events  # FADE Cloak: no damage taken or dealt while intangible
	var source: String = opts.get("source", "")
	if not opts.get("interceded", false):
		var mate := TalentRules.intercede(state, target, state.unit(source), parts)
		if mate != null:
			# Bonded Intercede: the bondmate takes the damage instead.
			var o2 := opts.duplicate()
			o2["interceded"] = true
			var moved: Array[Dictionary] = [{"type": "effect_triggered", "unit": mate.id, "effect": "Intercede", "target": target.id, "rule_ref": "talents: Bonded"}]
			moved.append_array(deal_damage(state, mate, parts, o2))
			return moved
	TalentRules.damaged_by(target, state.unit(source))  # Heavy Gunner: Covering Fire ends
	var shredded := target.has_status("Shredded")
	# "Can't be reduced in any way" (Monarch Seeking Payload, Pegasus Omnigun): no Armor,
	# Resistance or other reduction; "bypasses Immunity" (Omnigun) skips Immunity too.
	var unreducible: bool = opts.get("unreducible", false)
	if Effects.has(target, "aegis") and not unreducible:
		opts["damage_to_one"] = true  # Napoleon Trueblack Aegis: all damage is reduced to 1
	var armor_left := 0 if shredded or unreducible or opts.get("ap", false) else target.armor
	for part: Dictionary in parts:
		var dtype: String = part.get("type", "Kinetic")
		var amount: int = part.get("amount", 0)
		if dtype == "Variable":
			dtype = "Kinetic"  # PROVISIONAL: weapons with a chosen damage type default to Kinetic.
		if Effects.immune_to_damage(target, dtype) and not opts.get("bypass_immunity", false):
			events.append({"type": "damage_dealt", "target": target.id, "source": source, "amount": 0, "damage_type": dtype,
				"roll": amount, "immune": true, "hp": target.hp, "rule_ref": "glossary: Immunity"})
			continue
		var resist_here: bool = opts.get("resist_all", false) or (opts.get("resist_types", []) as Array).has(dtype) or Effects.resists(target, dtype, opts.get("area", false), int(opts.get("distance", -1))) or Effects.shepherded(state, target)
		if dtype == "Heat":
			if state.unit(source) != null:
				amount = Environments.gear_heat(state, amount)  # extreme heat: heat from a character's weapons and systems
			events.append_array(apply_heat(state, target, amount, source, resist_here))
			continue
		var rolled := amount
		# 1) Increases: Exposed doubles kinetic, explosive and energy damage.
		var exposed := target.has_status("Exposed") and DOUBLED_BY_EXPOSED.has(dtype)
		if exposed:
			amount *= 2
		# 2) Armor (Burn ignores Armor).
		var armor_used := 0
		if dtype != "Burn":
			armor_used = mini(armor_left, amount)
			armor_left -= armor_used
			amount -= armor_used
		# 3) Resistance halves what's left, rounding the damage taken up (Core p.12).
		var resisted := 0
		if not shredded and not unreducible and amount > 0 and (resist_here or _resists(target, dtype) or CoreBonuses.briareos_resists(target)):
			resisted = amount / 2
			amount -= resisted
		var ev := {"type": "damage_dealt", "target": target.id, "source": source, "amount": amount,
			"damage_type": dtype, "roll": rolled, "exposed": exposed, "armor_reduced": armor_used,
			"resisted": resisted, "rule_ref": REF_HARM}
		if opts.get("damage_to_one", false) and amount > 0 and not unreducible:
			# Napoleon Flash Aegis: Bracing reduces the incoming damage to 1 (instead of Resistance).
			ev["reduced_to_one"] = true
			ev["resisted"] = int(ev["resisted"]) + amount - (0 if opts.get("one_used", false) else 1)
			amount = 0 if opts.get("one_used", false) else 1
			opts["one_used"] = true
			ev["amount"] = amount
		events.append(ev)
		if dtype == "Burn" and not opts.get("no_mark_burn", false) and part.get("mark", true):
			target.burn += int(part.get("amount", 0))
			events.append({"type": "burn_marked", "unit": target.id, "amount": int(part.get("amount", 0)), "total": target.burn, "rule_ref": REF_BURN})
		events.append_array(lose_hp(state, target, amount, source))
		if dtype == "Energy" and amount > 0:
			events.append_array(FrameSystems.took_heat_or_energy(state, target, "energy"))
		ev["hp"] = maxi(target.hp, 0)
		ev["overshield"] = target.overshield
		if target.destroyed:
			break
	var took := false
	for ev: Dictionary in events:
		took = took or (ev.get("type", "") == "damage_dealt" and int(ev.get("amount", 0)) > 0 and ev.get("target", "") == target.id)
	if took and not target.destroyed:
		events.append_array(GearSystems.took_damage(state, target, source))
		events.append_array(GearSystems.singularity(state, target))
	return events


static func _resists(u: Unit, dtype: String) -> bool:
	return u.resistances.has(dtype) or u.resistances.has("All")


## Takes HP (overshield first). At 0 HP a mech marks structure damage (glossary: HP).
static func lose_hp(state: GameState, u: Unit, amount: int, source: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if amount <= 0 or u.destroyed:
		return events
	var from_shield := mini(u.overshield, amount)
	u.overshield -= from_shield
	amount -= from_shield
	if u.counters.get("briareos_down", false) and not u.destroyed:
		# Briareos Frame at 0 Structure: every hit is a structure damage check.
		events.append({"type": "hp_changed", "unit": u.id, "hp": 0, "overshield": u.overshield, "source": source})
		events.append_array(structure_check(state, u))
		return events
	u.hp -= amount
	events.append({"type": "hp_changed", "unit": u.id, "hp": maxi(u.hp, 0), "overshield": u.overshield, "source": source})
	if u.hp > 0:
		return events
	if u.kind == Unit.KIND_PILOT:
		events.append_array(Pilots.pilot_hit_zero(state, u, source))
		return events
	if u.kind == Unit.KIND_DEPLOYABLE or u.max_structure <= 0:
		events.append_array(destroy(state, u, "Reduced to 0 HP."))
		return events
	# At 0 HP: 1 structure damage, a structure check, HP back to full, then the excess
	# damage, which can cost more structure (Core p.80).
	while u.hp <= 0 and not u.destroyed:
		var excess := -u.hp
		var frenzy := FrameSystems.frenzy_saves(state, u)
		events.append_array(frenzy)
		if not frenzy.is_empty() and frenzy[0].get("saved", false):
			break
		var paint := GearSystems.paint_job(state, u)
		events.append_array(paint)
		if not paint.is_empty() and paint[0].get("saved", false):
			break
		u.structure -= 1
		events.append({"type": "structure_lost", "unit": u.id, "structure": u.structure, "rule_ref": "Core p.80 Structure"})
		events.append_array(GearSystems.batteries_blow(state, u))
		if u.structure <= 0 and CoreBonuses.briareos_holds(u):
			# Briareos Frame: at 0 HP and 0 Structure it isn't destroyed; it makes a structure
			# damage check each time it takes damage, and gets no HP back until it rests.
			u.structure = 0
			u.hp = 0
			u.counters["briareos_down"] = true
			events.append_array(structure_check(state, u))
			return events
		events.append_array(CoreBonuses.structure_lost(state, u))
		events.append_array(_on_structure_or_stress(state, u, true))
		if u.structure <= 0:
			events.append_array(destroy(state, u, "Reached 0 Structure."))
			return events
		events.append_array(structure_check(state, u))
		if u.destroyed:
			return events
		u.hp = u.max_hp - excess
		events.append({"type": "hp_changed", "unit": u.id, "hp": maxi(u.hp, 0), "overshield": u.overshield, "source": "structure reset"})
		events.append_array(_flyer_save(state, u, "structure damage", source))
	return events


## Trait hooks: Emergency Vent (clear heat on structure damage), Regeneration stops.
static func _on_structure_or_stress(state: GameState, u: Unit, structure: bool) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if structure and Effects.has(u, "vent_on_structure"):
		events.append_array(clear_heat(u, String(Effects.of(u, "vent_on_structure")[0].get("label", ""))))
	if Effects.has(u, "regenerate"):
		events.append_array(add_status(state, u, "Regeneration Suppressed", String(Effects.of(u, "regenerate")[0].get("label", "")), u.id))
	return events


static func structure_check(state: GameState, u: Unit) -> Array[Dictionary]:
	var r := _damage_check_roll(state, u.max_structure - u.structure)
	var events: Array[Dictionary] = AISystems.cascade_check(state, u)
	var lowest: int = r["lowest"]
	var outcome := ""
	if r["ones"] >= 2:
		outcome = "Crushing Hit"
	elif lowest >= 5:
		outcome = "Glancing Blow"
	elif lowest >= 2:
		outcome = "System Trauma"
	else:
		outcome = "Direct Hit"
	var ev := {"type": "structure_check", "unit": u.id, "roll": r, "outcome": outcome, "rule_ref": REF_STRUCTURE}
	events.append(ev)
	match outcome:
		"Glancing Blow":
			events.append_array(add_status(state, u, "Impaired", "Glancing Blow", u.id))
		"System Trauma":
			events.append_array(_system_trauma(state, u))
		"Direct Hit":
			events.append_array(_direct_hit(state, u))
		"Crushing Hit":
			events.append_array(destroy(state, u, "Crushing Hit: destroyed beyond repair."))
	return events


static func _direct_hit(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if u.structure >= 3:
		events.append_array(_direct_hit_stun(state, u))
	elif u.structure == 2:
		var check := skill_check(state, u, "hull", "Direct Hit: Hull check")
		events.append({"type": "skill_check", "unit": u.id, "check": check, "rule_ref": REF_STRUCTURE})
		if check["success"]:
			events.append_array(_direct_hit_stun(state, u))
		else:
			events.append_array(destroy(state, u, "Direct Hit: failed the Hull check."))
	else:
		events.append_array(destroy(state, u, "Direct Hit with 1 Structure left."))
	return events


static func _system_trauma(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var sub := state.dice.die(6)
	var mount := _trauma_mount(u)
	var system := _trauma_system(u)
	var want_mount := sub <= 3
	var choice := ""
	if want_mount and mount >= 0:
		choice = "mount"
	elif not want_mount and system != "":
		choice = "system"
	elif mount >= 0:
		choice = "mount"
	elif system != "":
		choice = "system"
	events.append({"type": "system_trauma", "unit": u.id, "roll": sub, "destroys": choice,
		"note": "PROVISIONAL: first valid choice picked until the player can choose.", "rule_ref": REF_STRUCTURE})
	match choice:
		"mount":
			for w: Dictionary in u.loadout.get("weapons", []):
				if int(w.get("mount", -1)) == mount:
					Weapons.state_of(u, w)["destroyed"] = true
					events.append({"type": "equipment_destroyed", "unit": u.id, "weapon": w.get("key", ""), "name": w.get("name", "")})
		"system":
			var sys: Dictionary = u.counters.get("systems", {})
			sys[system] = {"destroyed": true}
			u.counters["systems"] = sys
			Abilities.source_state(u, system)["destroyed"] = true
			events.append({"type": "equipment_destroyed", "unit": u.id, "system": system})
		_:
			events.append_array(_direct_hit(state, u))
	return events


## First mount with a weapon that can still be destroyed (not Limited and out of charges).
static func _trauma_mount(u: Unit) -> int:
	for w: Dictionary in u.loadout.get("weapons", []):
		var st := Weapons.state_of(u, w)
		if st["destroyed"] or int(w.get("mount", -1)) < 0:
			continue
		if Weapons.has_tag(w, "tg_limited") and int(st["uses"]) <= 0:
			continue
		return int(w["mount"])
	return -1


static func _trauma_system(u: Unit) -> String:
	var destroyed: Dictionary = u.counters.get("systems", {})
	for s: Dictionary in u.loadout.get("systems", []):
		var key := String(s.get("key", ""))
		if destroyed.has(key) or Weapons.has_tag(s, "tg_indestructible"):
			continue
		return key
	return ""


## Roll 1d6 per point of structure/stress damage marked; the lowest counts; two or more 1s
## is the worst result (tables: Structure Damage / Overheating).
static func _damage_check_roll(state: GameState, marked: int) -> Dictionary:
	var dice: Array[int] = []
	for i in range(maxi(1, marked)):
		dice.append(state.dice.die(6))
	var ones := dice.count(1)
	return {"dice": dice, "lowest": dice.min(), "ones": ones}


# --- Heat -----------------------------------------------------------------------------

## Adds heat. Over HEAT CAP: 1 stress, clear all heat, overheating check (glossary: Heat
## Capacity). Characters without a heat cap take energy damage instead.
static func apply_heat(state: GameState, u: Unit, amount: int, source: String, resist_all: bool = false) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if amount <= 0 or u.destroyed:
		return events
	if not u.has_status("Shredded") and (resist_all or _resists(u, "Heat") or Effects.resists(u, "Heat", false, -1)):
		amount -= amount / 2
	if u.heat_cap <= 0:
		return deal_damage(state, u, [{"type": "Energy", "amount": amount}], {"source": source})
	u.heat += amount
	events.append({"type": "heat_changed", "unit": u.id, "amount": amount, "total": u.heat, "source": source})
	if u.heat > u.heat_cap:
		events.append_array(FrameSystems.vent_heat(state, u))  # Sherman Vent Heat
		GearSystems.spoil_cooler(u)
	var goblin := FrameSystems.symbiont_of(state, u)
	if goblin != null and not goblin.destroyed:
		events.append_array(apply_heat(state, goblin, amount, source))  # the Goblin takes its host's heat
	# Over HEAT CAP: 1 stress, an overheating check, clear all heat, then take the heat beyond
	# what it took to exceed the cap, which can overheat again (Core p.81).
	# How much carries over is the table's "heat_overflow" ruling.
	if u.heat > u.heat_cap and u.counters.get("expose_armed", false):
		# Genghis Expose Power Cells: instead of overheating, clear all heat and vent a cloud.
		u.counters.erase("expose_armed")
		u.heat = 0
		events.append({"type": "heat_changed", "unit": u.id, "amount": 0, "total": 0, "source": "Expose Power Cells"})
		events.append_array(Zones.make_cloud(state, u))
	while u.heat > u.heat_cap and not u.destroyed:
		var excess := u.heat - u.heat_cap - 1
		if Rulings.ask(state, "heat_overflow") == "beyond_cap":
			excess = u.heat - u.heat_cap
		u.heat = 0
		u.stress -= 1
		events.append({"type": "stress_lost", "unit": u.id, "stress": u.stress, "rule_ref": "Core p.81 Overheating"})
		events.append_array(CoreBonuses.stress_lost(state, u))
		events.append_array(GearSystems.vents(state, u))  # Explosive Vents: took stress
		events.append_array(_on_structure_or_stress(state, u, false))
		events.append({"type": "heat_changed", "unit": u.id, "amount": 0, "total": 0, "source": "overheat"})
		if u.stress <= 0:
			# Reaching 0 STRESS: reactor meltdown at the end of its next turn (Core p.81).
			if not u.counters.has("meltdown"):
				events.append_array(_start_meltdown(state, u, -1))
			break
		events.append_array(stress_check(state, u))
		if u.destroyed:
			return events
		events.append_array(_flyer_save(state, u, "stress damage"))
		u.heat = excess
		if excess > 0:
			events.append({"type": "heat_changed", "unit": u.id, "amount": excess, "total": u.heat, "source": "overheat excess"})
	events.append_array(_danger_zone(u))
	events.append_array(FrameSystems.took_heat_or_energy(state, u, "heat"))
	return events


static func clear_heat(u: Unit, source: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if u.heat > 0:
		events.append({"type": "heat_changed", "unit": u.id, "amount": -u.heat, "total": 0, "source": source})
		u.heat = 0
	events.append_array(_danger_zone(u))
	return events


## Danger Zone: half or more of heat cap filled (statuses: Danger Zone).
static func _danger_zone(u: Unit) -> Array[Dictionary]:
	var hot := u.heat_cap > 0 and u.heat * 2 >= u.heat_cap
	if hot and not u.has_status("Danger Zone"):
		u.statuses["Danger Zone"] = {"source": "heat"}
		return [{"type": "status_added", "unit": u.id, "status": "Danger Zone", "source": "heat"}] as Array[Dictionary]
	if not hot:
		return remove_status(u, "Danger Zone", "heat")
	return [] as Array[Dictionary]


static func stress_check(state: GameState, u: Unit) -> Array[Dictionary]:
	var r := _damage_check_roll(state, u.max_stress - u.stress)
	var events: Array[Dictionary] = AISystems.cascade_check(state, u)
	if Effects.has(u, "reactor_stabilizer") and int(r["lowest"]) < 5:
		# Reactor Stabilizer: may reroll, keeping the second result (rerolled unless the first
		# was already the best outcome).
		events.append({"type": "effect_triggered", "unit": u.id, "effect": "Reactor Stabilizer", "target": u.id, "first": r, "rule_ref": "systems: Reactor Stabilizer"})
		r = _damage_check_roll(state, u.max_stress - u.stress)
	var lowest: int = r["lowest"]
	var outcome := ""
	if r["ones"] >= 2:
		outcome = "Irreversible Meltdown"
	elif lowest >= 5:
		outcome = "Emergency Shunt"
	elif lowest >= 2:
		outcome = "Destabilized Power Plant"
	else:
		outcome = "Meltdown"
	events.append({"type": "stress_check", "unit": u.id, "roll": r, "outcome": outcome, "rule_ref": REF_OVERHEAT})
	match outcome:
		"Emergency Shunt":
			events.append_array(add_status(state, u, "Impaired", "Emergency Shunt", u.id))
		"Destabilized Power Plant":
			events.append_array(add_status(state, u, "Exposed", "Destabilized Power Plant"))
		"Meltdown":
			if u.stress >= 3:
				events.append_array(add_status(state, u, "Exposed", "Meltdown"))
			elif u.stress == 2:
				var check := skill_check(state, u, "engineering", "Meltdown: Engineering check")
				events.append({"type": "skill_check", "unit": u.id, "check": check, "rule_ref": REF_OVERHEAT})
				if check["success"]:
					events.append_array(add_status(state, u, "Exposed", "Meltdown"))
				else:
					events.append_array(_start_meltdown(state, u, state.dice.die(6)))
			else:
				events.append_array(_start_meltdown(state, u, -1))
		"Irreversible Meltdown":
			events.append_array(_start_meltdown(state, u, -1))
	overheated_check(state, u)  # house rule: Overheated
	return events


## A Direct Hit's Stun, or with the "hr_structure_no_stun" house rule Brace's penalties instead:
## no reactions and one quick action until the end of its next turn.
static func _direct_hit_stun(state: GameState, u: Unit) -> Array[Dictionary]:
	if not HouseRuleSwitches.on(state, "hr_structure_no_stun"):
		return add_status(state, u, "Stunned", "Direct Hit", u.id)
	u.counters["brace_next_turn"] = true
	var events: Array[Dictionary] = Effects.activate(state, u, [{"kind": "no_reactions", "label": "Direct Hit"}], "Direct Hit (house rule)", "end_next_turn")
	events.append({"type": "effect_triggered", "unit": u.id, "effect": "Direct Hit: shaken (house rule)", "target": u.id,
		"text": "No reactions and only one quick action until the end of your next turn.", "rule_ref": "House rule: No Stun from a Direct Hit"})
	return events


## House rule "hr_overheated" (community): Exposed from overheating also makes it Overheated:
## no Heat (Self) weapons or systems and no Overkill until it cools down with Stabilize.
static func overheated_check(state: GameState, u: Unit) -> void:
	if HouseRuleSwitches.on(state, "hr_overheated") and u.has_status("Exposed"):
		u.counters["overheated"] = true


## Reactor meltdown after `turns` of the unit's turns; -1 = at the end of its next turn.
static func _start_meltdown(state: GameState, u: Unit, turns: int) -> Array[Dictionary]:
	if turns < 0:
		turns = 2 if state.active_unit == u.id else 1
	u.counters["meltdown"] = turns
	return [{"type": "meltdown_started", "unit": u.id, "turns": turns, "rule_ref": REF_OVERHEAT}] as Array[Dictionary]


static func tick_meltdown(state: GameState, u: Unit) -> Array[Dictionary]:
	if u.counters.has("self_destruct") and not u.destroyed:
		u.counters["self_destruct"] = int(u.counters["self_destruct"]) - 1
		if int(u.counters["self_destruct"]) <= 0:
			u.counters.erase("self_destruct")
			return Pilots.explode(state, u, "Self Destruct.")
	if not u.counters.has("meltdown") or u.destroyed:
		return [] as Array[Dictionary]
	u.counters["meltdown"] = int(u.counters["meltdown"]) - 1
	if int(u.counters["meltdown"]) > 0:
		return [] as Array[Dictionary]
	u.counters.erase("meltdown")
	var events: Array[Dictionary] = [{"type": "reactor_meltdown", "unit": u.id, "rule_ref": REF_OVERHEAT}]
	events.append_array(Pilots.explode(state, u, "Reactor meltdown."))
	return events


static func destroy(state: GameState, u: Unit, why: String) -> Array[Dictionary]:
	if u.destroyed:
		return [] as Array[Dictionary]
	u.destroyed = true
	u.hp = 0
	TalentRules.end_duel(state, u)  # Exemplar To The Death
	var events: Array[Dictionary] = [{"type": "unit_destroyed", "unit": u.id, "reason": why}]
	if u.counters.get("snare", false):
		events.append_array(GearSystems.snare_gone(state, u))
	events.append_array(Riders.on_destroyed(state, u))
	if Pilots.castigating(state, u) and not u.counters.get("vaporized", false) and why != "Self Destruct.":
		# Manticore Castigate the Enemies of the Godhead: it explodes at once (burst 2, 8d6).
		events.append_array(Pilots.explode(state, u, "Castigation: " + why))
	if Effects.has(u, "unstable_system") and not u.counters.get("vaporized", false):
		# Manticore Unstable System: explodes as a reactor meltdown at the end of its next turn
		# (its pilot's turn inside the wreck).
		var pilot := Pilots.ensure_pilot(state, u)
		u.counters["unstable_explosion"] = 2 if state.active_unit in [u.id, pilot.id] else 1
		events.append({"type": "meltdown_started", "unit": u.id, "turns": u.counters["unstable_explosion"], "rule_ref": "frames: Manticore, Unstable System"})
	for status: String in u.statuses.keys():
		events.append_array(remove_status(u, status, "destroyed"))
	# The pilot stays in the wreck, no longer protected by it, and "may still exit it as normal"
	# (Core p.74, 80): it takes its own turns and can Dismount.
	events.append_array(refresh_engagement(state))
	return events


# --- Flying and falling ---------------------------------------------------------------

static func begin_falling(u: Unit, why: String) -> Array[Dictionary]:
	if u.counters.get("falling", false):
		return [] as Array[Dictionary]
	u.counters["falling"] = true
	return [{"type": "falling", "unit": u.id, "reason": why, "rule_ref": REF_FALL}] as Array[Dictionary]


## Flying characters that take structure damage or stress must pass an AGILITY save or begin
## falling (Core p.63). Target: the table's "unforced_save_target" ruling.
static func _flyer_save(state: GameState, u: Unit, what: String, source: String = "") -> Array[Dictionary]:
	if not u.flying:
		return [] as Array[Dictionary]
	var target := CHECK_TARGET
	var by := state.unit(source)
	if by != null and by.save_target != CHECK_TARGET and Rulings.ask(state, "unforced_save_target") == "attacker":
		target = by.save_target
	var check := skill_check(state, u, "agility", "Agility save after %s while flying" % what, target, 0, 0, [], true)
	var events: Array[Dictionary] = [{"type": "skill_check", "unit": u.id, "check": check, "rule_ref": "glossary: Flight/Hover"}]
	if not check["success"]:
		events.append_array(begin_falling(u, "Failed the Agility save after %s." % what))
	return events


## Moves everyone who is falling, or unsupported without flight (e.g. knocked off a ledge).
## Falling starts at the end of the current turn and continues at the end of each of the
## faller's own turns, 10 spaces per round (Core p.63). `ended` = whose turn just ended.
static func fall_all(state: GameState, ended: Unit = null) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for u: Unit in state.units.values():
		if u.destroyed:
			continue
		var unsupported: bool = Movement.placement(state, u.size, u.cell, u.level)["airborne"]
		if not u.counters.get("falling", false) and not (unsupported and not u.flying):
			continue
		if u.counters.get("fall_started", false) and u != ended:
			continue
		events.append_array(fall_unit(state, u, 10))
	if not events.is_empty():
		events.append_array(refresh_engagement(state))
	return events


## Drops `u` up to `max_drop` spaces (-1: all the way). On landing: 3 AP kinetic for every
## 3 spaces of the whole fall, at most 9 (Core p.63).
static func fall_unit(state: GameState, u: Unit, max_drop: int = -1) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var start := u.level
	var lv := u.level
	while lv > 0 and Movement.placement(state, u.size, u.cell, lv)["airborne"] and (max_drop < 0 or start - lv < max_drop):
		lv -= 1
	u.level = lv
	u.flying = false
	var dist := start - lv
	var total := int(u.counters.get("fallen", 0)) + dist
	if dist > 0:
		events.append({"type": "moved", "unit": u.id, "mode": "fall", "path": [[u.cell.x, u.cell.y, start], [u.cell.x, u.cell.y, lv]], "cost": 0, "rule_ref": REF_FALL})
		events.append_array(Effects.punish_movement(state, u))  # falling is involuntary movement
	if Movement.placement(state, u.size, u.cell, lv)["airborne"]:
		u.counters["falling"] = true
		u.counters["fall_started"] = true
		u.counters["fallen"] = total
		return events
	u.counters.erase("falling")
	u.counters.erase("fall_started")
	u.counters.erase("fallen")
	var dmg := mini(9, (total / 3) * 3)
	if Environments.no_fall_damage(state):
		dmg = 0  # low gravity
	if dmg > 0 and HouseRuleSwitches.on(state, "hr_brace_fall") and Reactions.can_react(u, "brace_fall", state).ok:
		# House rule (your idea): brace for the fall with your reaction, taking half.
		var d := Reactions.offer(state, u, "brace_fall", {"damage": dmg, "suggested": {"take": true}}, {"take": true})
		if d.get("take", false):
			Reactions._mark_used(u, "brace_fall", state)
			dmg -= dmg / 2
			events.append({"type": "effect_triggered", "unit": u.id, "effect": "Brace for the fall", "target": u.id, "rule_ref": "House rule: Brace for the fall"})
	if dmg > 0:
		events.append_array(deal_damage(state, u, [{"type": "Kinetic", "amount": dmg}], {"ap": true, "source": "fall"}))
		if HouseRuleSwitches.on(state, "hr_fall_stun") and not u.destroyed:
			# House rule (your idea): Hull save or Stunned until the end of its next turn.
			var save := skill_check(state, u, "hull", "Hard fall: Hull save", CHECK_TARGET, 0, 0, [], true)
			events.append({"type": "skill_check", "unit": u.id, "check": save, "rule_ref": "House rule: Stunned by a hard fall"})
			if not save["success"]:
				events.append_array(add_status(state, u, "Stunned", "fall", u.id))
	return events


# --- End of turn ----------------------------------------------------------------------

static func end_of_turn_checks(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	# Burn: Engineering check; success clears it, failure deals the marked burn (glossary: Burn).
	if u.burn > 0:
		var check := skill_check(state, u, "engineering", "Burn: Engineering check")
		events.append({"type": "skill_check", "unit": u.id, "check": check, "rule_ref": REF_BURN})
		if check["success"]:
			u.burn = 0
			events.append({"type": "burn_cleared", "unit": u.id})
		else:
			events.append_array(deal_damage(state, u, [{"type": "Burn", "amount": u.burn, "mark": false}], {"source": "burn"}))
	if u.destroyed:
		return events
	events.append_array(dangerous_terrain_check(state, u))
	# Flying characters must move at least 1 space on their turn or begin falling.
	if u.flying and u.flight != "hover" and not u.turn.get("moved", false):
		events.append_array(begin_falling(u, "Didn't move this turn while flying."))
	return events


## Dangerous terrain: Engineering check or 5 damage, once per round per character
## (Core p.62). The map says which hazard: Kinetic unless the column is also tagged
## "dangerous_energy", "dangerous_explosive" or "dangerous_burn".
static func dangerous_terrain_check(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if u.counters.get("dangerous_checked", false) or u.flying:
		return events
	var dtype := ""
	for c in state.map.grid.footprint(u.cell, u.size):
		var col := state.map.column(c)
		if col != null and col.has_tag(BattleMap.TAG_DANGEROUS) and u.level <= col.ground:
			dtype = "Kinetic"
			for t in ["Energy", "Explosive", "Burn"]:
				if col.has_tag("dangerous_" + t.to_lower()):
					dtype = t
	if dtype == "":
		return events
	return dangerous_roll(state, u, dtype)


## The Engineering check for dangerous terrain, once per round.
static func dangerous_roll(state: GameState, u: Unit, dtype: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if u.counters.get("dangerous_checked", false):
		return events
	u.counters["dangerous_checked"] = true
	var check := skill_check(state, u, "engineering", "Dangerous terrain: Engineering check")
	events.append({"type": "skill_check", "unit": u.id, "check": check, "rule_ref": "glossary: Dangerous Terrain"})
	if not check["success"]:
		events.append_array(deal_damage(state, u, [{"type": dtype, "amount": 5}], {"source": "dangerous terrain"}))
	return events


# --- Engagement and Hidden ------------------------------------------------------------

static func _is_character(u: Unit) -> bool:
	return is_present(u) and u.kind != Unit.KIND_DEPLOYABLE and not GearSystems.intangible(u)


## On the battlefield: not destroyed, and not a pilot riding inside a mech.
static func is_present(u: Unit) -> bool:
	if u != null and u.counters.has("extracted"):
		return false  # Escort/Extraction sitreps: extracted, off the battlefield for good
	if u != null and u.counters.has("folded"):
		return false  # Fold Space: off the battlefield until the start of its next turn
	if u == null or u.destroyed:
		return false
	var inside := String(u.counters.get("mounted_in", u.counters.get("passenger_in", "")))
	if inside == "":
		return true
	# A pilot inside a destroyed mech can be targeted and affected (Core p.74).
	var mech: Unit = state_for_presence.get_ref().unit(inside) if state_for_presence != null and state_for_presence.get_ref() != null else null
	return mech != null and mech.destroyed


## Set by the engine so presence checks can see a pilot's mech.
static var state_for_presence: WeakRef = null


## Recomputes ENGAGED for everyone: adjacent to a hostile character, neither Hidden
## (statuses: Engaged, Hidden).
static func refresh_engagement(state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var units: Array = state.units.values()
	for u: Unit in units:
		if not _is_character(u):
			continue
		var by := ""
		if not u.has_status("Hidden"):
			for o: Unit in units:
				if o.side == u.side or not _is_character(o) or o.has_status("Hidden"):
					continue
				if o.kind == Unit.KIND_PILOT and u.kind != Unit.KIND_PILOT:
					continue  # pilots don't cause mechs to become Engaged (Core p.74)
				if Sight.unit_distance(state, u, o) <= 1:
					by = o.id
					break
		if by != "" and not u.has_status("Engaged"):
			u.statuses["Engaged"] = {"source": by}
			events.append({"type": "status_added", "unit": u.id, "status": "Engaged", "source": by})
		elif by == "" and u.has_status("Engaged"):
			events.append_array(remove_status(u, "Engaged"))
	return events


## Could `u` HIDE right now? Not Engaged, and every enemy either has no line of sight or
## the unit is entirely inside soft cover; INVISIBLE can always hide (actions: Hide).
static func can_hide(state: GameState, u: Unit) -> RuleResult:
	for z: Dictionary in Zones.of_kind(state, "athena"):
		var o := state.unit(String(z.get("owner", "")))
		if o != null and o.side != u.side and Zones.contains(state, z, u):
			return RuleResult.deny("Inside an ATHENA model you can't Hide.", "systems: ATHENA-Class NHP")
	if not (u.counters.get("tracked_by", []) as Array).is_empty():
		return RuleResult.deny("A tracking bug is on you: you can't Hide.", "systems: Tracking Bug")
	for o: Unit in state.units.values():
		if o.counters.get("aura", "") == "lotus" and not o.destroyed and o.side != u.side and Sight.unit_distance(state, o, u) <= 2:
			return RuleResult.deny("Inside a Lotus Projector field you can't Hide.", "systems: Lotus Projector")
	if u.has_status("Engaged"):
		return RuleResult.deny("You can't Hide while Engaged.", "actions: Hide")
	if u.has_status("Invisible") or TalentRules.prowling(state, u):
		return RuleResult.allow()  # Infiltrator Prowl: Hide even in plain sight on its turn
	if HouseRuleSwitches.on(state, "hr_hide_hard_cover") and hard_covered(state, u):
		return RuleResult.allow()  # house rule: hard cover from everyone who can see you
	var me := Sight.body_of(state, u)
	if Sight.fully_in_soft_cover(state, me):
		return RuleResult.allow()
	for o: Unit in state.units.values():
		if o.side == u.side or not _is_character(o):
			continue
		if Sight.line_of_sight(state, Sight.body_of(state, o), me):
			var who := o.name if o.name != "" else o.id
			return RuleResult.deny("%s can see you: you need to be out of every enemy's line of sight, fully behind hard cover, or inside soft cover." % who, "actions: Hide")
	return RuleResult.allow()


## Every hostile that can see `u` sees it in hard cover (house rule "hr_hide_hard_cover").
static func hard_covered(state: GameState, u: Unit) -> bool:
	for o: Unit in state.units.values():
		if o.side == u.side or not _is_character(o):
			continue
		var cov := Sight.unit_cover(state, o, u)
		if cov["los"] and cov["cover"] != "hard":
			return false
	return true


## Hidden characters lose HIDDEN if their cover disappears or an enemy gains line of sight
## (actions: Hide).
static func refresh_hidden(state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for u: Unit in state.units.values():
		if not u.has_status("Hidden") or u.has_status("Invisible") or TalentRules.prowling(state, u):
			continue  # Infiltrator Prowl: checked again when its turn ends
		var me := Sight.body_of(state, u)
		if Sight.fully_in_soft_cover(state, me):
			continue
		if HouseRuleSwitches.on(state, "hr_hide_hard_cover") and hard_covered(state, u):
			continue
		for o: Unit in state.units.values():
			if o.side == u.side or not _is_character(o):
				continue
			if Sight.line_of_sight(state, Sight.body_of(state, o), me):
				events.append_array(remove_status(u, "Hidden", "line of sight from " + o.id))
				break
	if not events.is_empty():
		events.append_array(refresh_engagement(state))
	return events


## After any movement: engagement, Hidden, grapples.
static func after_movement(state: GameState) -> Array[Dictionary]:
	FrameSystems.follow_hosts(state)
	Riders.follow(state)
	var events := refresh_hidden(state)
	events.append_array(refresh_engagement(state))
	events.append_array(CloseCombat.check_grapples(state))
	return events
