class_name Combat
extends RefCounted
## Damage, heat, structure and stress, statuses, checks, falling, engagement and Hidden upkeep.
## Called by action handlers; every function returns the events it caused.
##
## Book rules used (lancer-data text): Harm/Calculating Damage order, Armor, Resistance,
## Exposed, Shredded, Overshield, Burn, Heat Capacity, HP, Structure, Stress, the Structure
## Damage and Overheating tables (tables.json), Falling, Flight, Engaged, Hidden, Stunned.
## PROVISIONAL (docs/RULES_TODO.md): halving rounds up; Armor applies once per hit across its
## damage types; excess damage past 0 HP is lost; checks and saves with no one forcing them
## succeed on 10+; a whole fall happens at the end of the current turn; reactor meltdown
## destroys the mech (the explosion isn't modelled yet); System Trauma picks the first valid
## mount/system until the UI offers the choice.

const REF_HARM := "glossary: Harm/Calculating Damage"
const REF_STRUCTURE := "tables: Structure Damage"
const REF_OVERHEAT := "tables: Overheating"
const REF_HEAT := "glossary: Heat Capacity"
const REF_FALL := "glossary: Falling/Fall Damage"
const REF_BURN := "glossary: Burn"
const REF_PROVISIONAL := "PROVISIONAL (docs/RULES_TODO.md)"
const CHECK_TARGET := 10
const SKILLS := ["hull", "agility", "systems", "engineering"]
const DOUBLED_BY_EXPOSED := ["Kinetic", "Explosive", "Energy"]


# --- Statuses -------------------------------------------------------------------------

## Adds a status. `next_turn_end_of` = a unit whose "end of next turn" ends it ("" = lasts).
static func add_status(state: GameState, u: Unit, status: String, source: String, next_turn_end_of: String = "") -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if status == "Prone" and u.flying:
		return events  # Flying characters have IMMUNITY to PRONE (glossary: Flight/Hover).
	var entry := {"source": source}
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
	if u.flying and (status == "Immobilized" or status == "Stunned"):
		events.append_array(begin_falling(u, "Flying characters begin falling if Immobilized or Stunned."))
	return events


static func remove_status(u: Unit, status: String, source: String = "") -> Array[Dictionary]:
	if not u.statuses.has(status):
		return [] as Array[Dictionary]
	u.statuses.erase(status)
	return [{"type": "status_removed", "unit": u.id, "status": status, "source": source}] as Array[Dictionary]


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
static func skill_check(state: GameState, u: Unit, skill: String, label: String, target: int = CHECK_TARGET, accuracy: int = 0, difficulty: int = 0, sources: Array = []) -> Dictionary:
	var all_sources := sources.duplicate()
	var diff := difficulty
	if u.has_status("Impaired"):
		diff += 1
		all_sources.append({"label": "Impaired", "kind": "difficulty", "type": "difficulty", "value": 1, "rule_ref": "statuses: Impaired"})
	var bonus := int(u.get(skill)) if SKILLS.has(skill) else 0
	var record := state.dice.check(bonus, accuracy, diff, target, all_sources)
	record["bonus_sources"] = [{"label": skill.capitalize(), "value": bonus}]
	record["bonuses"] = record["bonus_sources"]
	record["target_label"] = "Save Target" if target != CHECK_TARGET else "Check (10+)"
	record["skill"] = skill
	record["label"] = label
	if u.has_status("Stunned") and (skill == "hull" or skill == "agility"):
		record["success"] = false
		record["auto_fail"] = "Stunned mechs automatically fail Hull and Agility checks and saves."
	return record


# --- Damage ---------------------------------------------------------------------------

## Deals one hit's damage to `target`. `parts` = [{"type": "Kinetic", "amount": 7}, ...].
## opts: source (unit id), ap (ignores Armor), resist_all (Brace), no_mark_burn, roll.
static func deal_damage(state: GameState, target: Unit, parts: Array, opts: Dictionary = {}) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if target.destroyed:
		return events
	var source: String = opts.get("source", "")
	var shredded := target.has_status("Shredded")
	var armor_left := 0 if shredded or opts.get("ap", false) else target.armor
	for part: Dictionary in parts:
		var dtype: String = part.get("type", "Kinetic")
		var amount: int = part.get("amount", 0)
		if dtype == "Variable":
			dtype = "Kinetic"  # PROVISIONAL: weapons with a chosen damage type default to Kinetic.
		if dtype == "Heat":
			events.append_array(apply_heat(state, target, amount, source, opts.get("resist_all", false)))
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
		# 3) Resistance halves what's left. PROVISIONAL: rounds up.
		var resisted := 0
		if not shredded and amount > 0 and (opts.get("resist_all", false) or _resists(target, dtype)):
			resisted = amount / 2
			amount -= resisted
		var ev := {"type": "damage_dealt", "target": target.id, "source": source, "amount": amount,
			"damage_type": dtype, "roll": rolled, "exposed": exposed, "armor_reduced": armor_used,
			"resisted": resisted, "rule_ref": REF_HARM}
		events.append(ev)
		if dtype == "Burn" and not opts.get("no_mark_burn", false) and part.get("mark", true):
			target.burn += int(part.get("amount", 0))
			events.append({"type": "burn_marked", "unit": target.id, "amount": int(part.get("amount", 0)), "total": target.burn, "rule_ref": REF_BURN})
		events.append_array(lose_hp(state, target, amount, source))
		ev["hp"] = maxi(target.hp, 0)
		ev["overshield"] = target.overshield
		if target.destroyed:
			break
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
	u.hp -= amount
	events.append({"type": "hp_changed", "unit": u.id, "hp": maxi(u.hp, 0), "overshield": u.overshield, "source": source})
	if u.hp > 0:
		return events
	if u.kind == Unit.KIND_DEPLOYABLE or u.max_structure <= 0:
		events.append_array(destroy(state, u, "Reduced to 0 HP."))
		return events
	# PROVISIONAL: damage past 0 HP is lost; HP resets to full.
	u.structure -= 1
	u.hp = u.max_hp
	events.append({"type": "structure_lost", "unit": u.id, "structure": u.structure, "rule_ref": "glossary: HP"})
	if u.structure <= 0:
		events.append_array(destroy(state, u, "Reached 0 Structure."))
		return events
	events.append_array(structure_check(state, u))
	if not u.destroyed:
		events.append_array(_flyer_save(state, u, "structure damage"))
	return events


static func structure_check(state: GameState, u: Unit) -> Array[Dictionary]:
	var r := _damage_check_roll(state, u.max_structure - u.structure)
	var events: Array[Dictionary] = []
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
		events.append_array(add_status(state, u, "Stunned", "Direct Hit", u.id))
	elif u.structure == 2:
		var check := skill_check(state, u, "hull", "Direct Hit: Hull check")
		events.append({"type": "skill_check", "unit": u.id, "check": check, "rule_ref": REF_STRUCTURE})
		if check["success"]:
			events.append_array(add_status(state, u, "Stunned", "Direct Hit", u.id))
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
	if not u.has_status("Shredded") and (resist_all or _resists(u, "Heat")):
		amount -= amount / 2
	if u.heat_cap <= 0:
		return deal_damage(state, u, [{"type": "Energy", "amount": amount}], {"source": source})
	u.heat += amount
	events.append({"type": "heat_changed", "unit": u.id, "amount": amount, "total": u.heat, "source": source})
	if u.heat > u.heat_cap:
		u.heat = 0
		u.stress -= 1
		events.append({"type": "stress_lost", "unit": u.id, "stress": u.stress, "rule_ref": REF_HEAT})
		events.append({"type": "heat_changed", "unit": u.id, "amount": 0, "total": 0, "source": "overheat"})
		if u.stress <= 0:
			events.append_array(destroy(state, u, "Reached 0 Stress: reactor meltdown."))
			return events
		events.append_array(stress_check(state, u))
		if not u.destroyed:
			events.append_array(_flyer_save(state, u, "stress damage"))
	events.append_array(_danger_zone(u))
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
	var events: Array[Dictionary] = []
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
	return events


## Reactor meltdown after `turns` of the unit's turns; -1 = at the end of its next turn.
static func _start_meltdown(state: GameState, u: Unit, turns: int) -> Array[Dictionary]:
	if turns < 0:
		turns = 2 if state.active_unit == u.id else 1
	u.counters["meltdown"] = turns
	return [{"type": "meltdown_started", "unit": u.id, "turns": turns, "rule_ref": REF_OVERHEAT}] as Array[Dictionary]


static func tick_meltdown(state: GameState, u: Unit) -> Array[Dictionary]:
	if not u.counters.has("meltdown") or u.destroyed:
		return [] as Array[Dictionary]
	u.counters["meltdown"] = int(u.counters["meltdown"]) - 1
	if int(u.counters["meltdown"]) > 0:
		return [] as Array[Dictionary]
	u.counters.erase("meltdown")
	var events: Array[Dictionary] = [{"type": "reactor_meltdown", "unit": u.id,
		"note": "PROVISIONAL: the explosion isn't modelled yet.", "rule_ref": REF_OVERHEAT}]
	events.append_array(destroy(state, u, "Reactor meltdown."))
	return events


static func destroy(state: GameState, u: Unit, why: String) -> Array[Dictionary]:
	if u.destroyed:
		return [] as Array[Dictionary]
	u.destroyed = true
	u.hp = 0
	var events: Array[Dictionary] = [{"type": "unit_destroyed", "unit": u.id, "reason": why}]
	for status: String in u.statuses.keys():
		events.append_array(remove_status(u, status, "destroyed"))
	events.append_array(refresh_engagement(state))
	return events


# --- Flying and falling ---------------------------------------------------------------

static func begin_falling(u: Unit, why: String) -> Array[Dictionary]:
	if u.counters.get("falling", false):
		return [] as Array[Dictionary]
	u.counters["falling"] = true
	return [{"type": "falling", "unit": u.id, "reason": why, "rule_ref": REF_FALL}] as Array[Dictionary]


## Flying characters that take structure damage or stress must pass an AGILITY save or begin
## falling (glossary: Flight/Hover). PROVISIONAL: save target 10.
static func _flyer_save(state: GameState, u: Unit, what: String) -> Array[Dictionary]:
	if not u.flying:
		return [] as Array[Dictionary]
	var check := skill_check(state, u, "agility", "Agility save after %s while flying" % what)
	var events: Array[Dictionary] = [{"type": "skill_check", "unit": u.id, "check": check, "rule_ref": "glossary: Flight/Hover"}]
	if not check["success"]:
		events.append_array(begin_falling(u, "Failed the Agility save after %s." % what))
	return events


## Lands everyone who is falling, or unsupported without flight (e.g. knocked off a ledge).
## PROVISIONAL: the whole fall happens at once, at the end of the current turn.
static func fall_all(state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for u: Unit in state.units.values():
		if u.destroyed:
			continue
		var unsupported: bool = Movement.placement(state, u.size, u.cell, u.level)["airborne"]
		if not u.counters.get("falling", false) and not (unsupported and not u.flying):
			continue
		u.counters.erase("falling")
		var start := u.level
		var lv := u.level
		while lv > 0 and Movement.placement(state, u.size, u.cell, lv)["airborne"]:
			lv -= 1
		u.level = lv
		u.flying = false
		var dist := start - lv
		events.append({"type": "moved", "unit": u.id, "mode": "fall", "path": [[u.cell.x, u.cell.y, start], [u.cell.x, u.cell.y, lv]], "cost": 0})
		var dmg := mini(9, (dist / 3) * 3)
		if dmg > 0:
			events.append_array(deal_damage(state, u, [{"type": "Kinetic", "amount": dmg}], {"ap": true, "source": "fall"}))
	if not events.is_empty():
		events.append_array(refresh_engagement(state))
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
## (glossary: Dangerous Terrain). PROVISIONAL: the damage is Kinetic unless the column is
## tagged "dangerous_energy", "dangerous_explosive" or "dangerous_burn".
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
	return is_present(u) and u.kind != Unit.KIND_DEPLOYABLE


## On the battlefield: not destroyed, and not a pilot riding inside a mech.
static func is_present(u: Unit) -> bool:
	return u != null and not u.destroyed and String(u.counters.get("mounted_in", "")) == ""


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
	if u.has_status("Engaged"):
		return RuleResult.deny("You can't Hide while Engaged.", "actions: Hide")
	if u.has_status("Invisible"):
		return RuleResult.allow()
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


## Hidden characters lose HIDDEN if their cover disappears or an enemy gains line of sight
## (actions: Hide).
static func refresh_hidden(state: GameState) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for u: Unit in state.units.values():
		if not u.has_status("Hidden") or u.has_status("Invisible"):
			continue
		var me := Sight.body_of(state, u)
		if Sight.fully_in_soft_cover(state, me):
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


## After any movement: engagement, Hidden, falling flags.
static func after_movement(state: GameState) -> Array[Dictionary]:
	var events := refresh_hidden(state)
	events.append_array(refresh_engagement(state))
	return events
