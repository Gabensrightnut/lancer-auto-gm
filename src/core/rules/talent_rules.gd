class_name TalentRules
extends RefCounted
## Pilot talents that change attacks (data: data/game/gear_effects.json, by talent id and
## rank). Effect kinds:
##   attack_mod {accuracy, on: melee|ranged|attack, when, weapon_type?, weapon_size?, per?}
##       when: vs_grappled (Brawler 1), first_main_melee (Duelist 1), first_aux_ranged
##       (Gunslinger 1), ally_engaged_target (Tactician 1), higher_elevation (Tactician 2),
##       cqb_within_3 (Vanguard 1)
##   ignore_engaged          no Difficulty for being Engaged (Combined Arms 2)
##   soft_cover_engaged      while Engaged, it and adjacent allies have soft cover (Combined Arms 1)
##   ignore_cover_cqb {range} CQB attacks ignore cover within range (Vanguard 2)
##   brutal_max              natural 20 crits deal maximum damage and bonus damage (Brutal 1)
##   crit_knockback {value}  critical hits gain Knockback (Brutal 2)
##   relentless              +1 Accuracy per miss in a row, until it hits (Brutal 3)
##   dz_heat {value}         first attack roll on its turn in the Danger Zone: +2 heat on a hit
##                           (Nuclear Cavalier 1)
##   dz_fusion               first ranged/melee attack on its turn in the Danger Zone: energy,
##                           +1d6 energy bonus damage (Nuclear Cavalier 2)
##   improvised_upgrade      Improvised Attacks: 2d6+2 kinetic and Knockback 2 (Brawler 2)
##   ram_momentum            after a Boost, the next Ram: +1 Accuracy, knocked back 2 more
##                           (Juggernaut 1)
##   chaff                   soft cover from the start of its turn until it attacks (Skirmisher 1)
##   weave                   the first reaction attack against it each round misses (Skirmisher 3)
##   knife_juggler           Auxiliary melee weapons gain Thrown 5 (Hunter 2)
##   zero_in                 1/round while steadying aim with a Rifle (params.zero_in): +1
##                           Difficulty, +1d6 bonus damage on a crit (Crack Shot 2)
##   nexus_crit              1/round, Nexus crit: Systems save or Impaired and Slowed (Centimane 1/3)
##   expose_weakness         Nexus/Drone crit consuming Lock On: Shredded (Centimane 2)
##   wide_arc                first crit each round with a Heavy+ melee weapon: 3 kinetic to the
##                           others within Threat (Executioner 2)
##   seismic_deluge          1/round, Launcher hit consuming Lock On: Prone (Stormbringer 1)
##   impact                  1/round before a Cannon attack, adjacent characters: Hull save or
##                           knocked back 1 and Prone (Siege Specialist 2)
##   machine_bond            Stabilize also clears Impaired, Jammed, Immobilized, Slowed and Lock
##                           On caused by others (Grease Monkey 2)
##   particularize           an adjacent ally consuming Lock On rolls twice, keeps the better
##                           (Spotter 1)
##   ambush                  starting its turn Hidden, the first attack that hits: Hull save or
##                           Slowed, Impaired and no reactions (Infiltrator 2)
##   snow_crash              a tech hit consuming Lock On also deals 2 heat (Hacker 1)

const REF := "talents"


static func _first(u: Unit, key: String) -> bool:
	return not u.turn.get("first_" + key, false)


static func _round_ok(state: GameState, u: Unit, key: String) -> bool:
	return int((u.counters.get("talent_round", {}) as Dictionary).get(key, -1)) != state.round_number


static func _use_round(state: GameState, u: Unit, key: String) -> void:
	var d: Dictionary = u.counters.get("talent_round", {})
	d[key] = state.round_number
	u.counters["talent_round"] = d


## Extra Accuracy/Difficulty sources for an attack roll (preview and roll).
static func sources(state: GameState, attacker: Unit, w: Dictionary, target: Unit, kind: String, opts: Dictionary) -> Array:
	var out: Array = []
	var own := state.active_unit == attacker.id
	for e: Dictionary in Effects.of(attacker, "attack_mod"):
		var on := String(e.get("on", "attack"))
		if on != "attack" and on != kind:
			continue
		if e.has("weapon_type") and String(w.get("type", "")) != e["weapon_type"]:
			continue
		if e.has("weapon_size") and String(w.get("size", "")) != e["weapon_size"]:
			continue
		if e.get("per", "") == "round" and not _round_ok(state, attacker, String(e.get("label", ""))):
			continue
		var ok := true
		match String(e.get("when", "")):
			"vs_grappled":
				ok = String(attacker.counters.get("grapple", {}).get("with", "")) == target.id
			"first_main_melee":
				ok = own and _first(attacker, "main_melee") and kind == Attacks.KIND_MELEE and w.get("size", "") == "Main"
			"first_aux_ranged":
				ok = own and _first(attacker, "aux_ranged") and kind == Attacks.KIND_RANGED and w.get("size", "") == "Auxiliary"
			"ally_engaged_target":
				ok = false
				for o: Unit in state.units.values():
					if o != attacker and o.side == attacker.side and Combat.is_present(o) and Sight.unit_distance(state, o, target) <= 1:
						ok = true
			"higher_elevation":
				ok = attacker.level > target.level + int(target.size)  - 1
			"cqb_within_3":
				ok = w.get("type", "") == "CQB" and Sight.unit_distance(state, attacker, target) <= 3
		if ok:
			out.append({"label": String(e.get("label", "Talent")), "kind": "accuracy", "type": "accuracy", "value": int(e.get("accuracy", 1)), "rule_ref": REF, "talent": e})
	var miss := int(attacker.counters.get("relentless", 0))
	if miss > 0 and Effects.has(attacker, "relentless"):
		out.append({"label": "Relentless", "kind": "accuracy", "type": "accuracy", "value": miss, "rule_ref": REF})
	if w.get("key", "") == "ram" and attacker.counters.get("ram_momentum", false):
		out.append({"label": "Juggernaut: Momentum", "kind": "accuracy", "type": "accuracy", "value": 1, "rule_ref": REF})
	if opts.get("zero_in", false) and Effects.has(attacker, "zero_in") and w.get("type", "") == "Rifle" and _steadying(attacker):
		out.append({"label": "Zero In", "kind": "difficulty", "type": "difficulty", "value": 1, "rule_ref": REF})
	return out


static func _steadying(u: Unit) -> bool:
	for e: Dictionary in u.counters.get("active_effects", []):
		if e.get("label", "") == "Steady Aim":
			return true
	return false


## Combined Arms Shield of Blades / Skirmisher chaff: soft cover.
static func soft_cover(state: GameState, target: Unit) -> bool:
	if target.counters.get("chaff", false):
		return true
	for o: Unit in state.units.values():
		if o.side == target.side and Effects.has(o, "soft_cover_engaged") and o.has_status("Engaged") and Combat.is_present(o) and Sight.unit_distance(state, o, target) <= (0 if o == target else 1):
			return true
	return false


static func ignores_cover(state: GameState, attacker: Unit, w: Dictionary, target: Unit) -> bool:
	for e: Dictionary in Effects.of(attacker, "ignore_cover_cqb"):
		if w.get("type", "") == "CQB" and Sight.unit_distance(state, attacker, target) <= int(e.get("range", 3)):
			return true
	return false


## Weapon changes from talents at build time (Hunter Knife Juggler).
static func adjust_weapons(u: Unit) -> void:
	if not Effects.has(u, "knife_juggler"):
		return
	for w: Dictionary in u.loadout.get("weapons", []):
		if w.get("size", "") == "Auxiliary" and w.get("type", "") == "Melee":
			var tags: Array = (w.get("tags", []) as Array).filter(func(t: Dictionary) -> bool: return t.get("id", "") != "tg_thrown")
			tags.append({"id": "tg_thrown", "val": 5})
			w["tags"] = tags


## The Improvised Attack as this unit makes it (Brawler Sledgehammer).
static func improvised(u: Unit, base: Dictionary) -> Dictionary:
	if not Effects.has(u, "improvised_upgrade"):
		return base
	var w := base.duplicate(true)
	w["damage"] = [{"type": "Kinetic", "val": "2d6+2"}]
	w["tags"] = [{"id": "tg_knockback", "val": 2}]
	return w


## Siege Specialist 1, Jackhammer Round: a Size 1 section of an object within a Cannon's Range
## (a deployable, or "terrain:x,y") takes 10 AP kinetic automatically.
static func check_jackhammer(state: GameState, u: Unit, t: Unit) -> RuleResult:
	var ref := "talents: Siege Specialist"
	if t == null or t.destroyed or t.kind != Unit.KIND_DEPLOYABLE:
		return RuleResult.deny("Choose an object: cover, a deployable, a building or terrain (params.target).", ref)
	var reach := -1
	for w: Dictionary in u.loadout.get("weapons", []):
		if String(w.get("type", "")) == "Cannon" and not Weapons.state_of(u, w).get("destroyed", false):
			reach = maxi(reach, Weapons.range_for(u, w))
	if reach < 0:
		return RuleResult.deny("You need a Cannon.", ref)
	if Sight.unit_distance(state, u, t) > reach:
		return RuleResult.deny("It must be within your Cannon's Range (%d)." % reach, ref)
	return RuleResult.allow()


## Characters next to the target are knocked back 2 spaces from it and take 2 kinetic.
static func jackhammer(state: GameState, u: Unit, t: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = [{"type": "effect_triggered", "unit": u.id, "effect": "Jackhammer Round", "target": t.id,
		"rule_ref": "talents: Siege Specialist"}]
	var near: Array[Unit] = []
	for o: Unit in state.units.values():
		if o != t and Combat.is_present(o) and o.kind != Unit.KIND_DEPLOYABLE and Sight.unit_distance(state, o, t) <= 1:
			near.append(o)
	near.sort_custom(func(a: Unit, b: Unit) -> bool: return a.id < b.id)
	events.append_array(Combat.deal_damage(state, t, [{"type": "Kinetic", "amount": 10}], {"ap": true, "source": u.id}))
	for o in near:
		events.append_array(Combat.deal_damage(state, o, [{"type": "Kinetic", "amount": 2}], {"source": u.id}))
		if Combat.is_present(o):
			events.append_array(Attacks.knock_back(state, o, t.cell, 2, u))
	return events


## Juggernaut 2, Kinetic Mass Transfer (1/round): a Ram's knockback stopped by another
## character makes it Hull save or be knocked Prone; stopped by an obstruction (terrain, a
## wall), the target takes 1d6 kinetic. `from`: where the target was; `spaces`: the knockback.
static func kinetic_mass_transfer(state: GameState, u: Unit, t: Unit, origin: Vector2i, from: Vector2i, spaces: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not Effects.has(u, "kinetic_mass_transfer") or int(u.counters.get("kmt_round", -1)) == state.round_number:
		return events
	if spaces <= 0 or t.destroyed or Effects.has(t, "immovable"):
		return events
	var moved := state.map.grid.distance(from, t.cell)
	if moved >= spaces:
		return events
	# The next space along the push line: what stopped it.
	var dir := from - origin
	if dir == Vector2i.ZERO:
		return events
	var d := maxi(1, state.map.grid.distance(origin, from))
	var line := state.map.grid.line(from, from + dir * (spaces / d + 2))
	if moved + 1 >= line.size():
		return events
	var next: Vector2i = line[moved + 1]
	var blocker: Unit = null
	for o: Unit in state.units.values():
		if o != t and o != u and Combat.is_present(o) and o.kind != Unit.KIND_DEPLOYABLE and state.map.grid.footprint(o.cell, o.size).has(next):
			blocker = o
	u.counters["kmt_round"] = state.round_number
	var ref := "talents: Juggernaut"
	if blocker != null:
		var save := Combat.skill_check(state, blocker, "hull", "Kinetic Mass Transfer: Hull save", u.save_target, 0, 0, [], true)
		events.append({"type": "skill_check", "unit": blocker.id, "check": save, "rule_ref": ref})
		if not save["success"]:
			events.append_array(Combat.add_status(state, blocker, "Prone", u.id))
	else:
		var roll := state.dice.roll("1d6")
		events.append({"type": "effect_triggered", "unit": u.id, "effect": "Kinetic Mass Transfer", "target": t.id,
			"text": "Rammed into an obstruction: 1d6 kinetic.", "rule_ref": ref})
		events.append_array(Combat.deal_damage(state, t, [{"type": "Kinetic", "amount": int(roll["total"]), "roll": roll}], {"source": u.id}))
	return events


## Before an attack roll: Weave, Siege Specialist Impact, first-attack bookkeeping.
## Returns {events, auto_miss}.
static func before_roll(state: GameState, attacker: Unit, w: Dictionary, target: Unit, kind: String, opts: Dictionary) -> Dictionary:
	var out := {"events": [] as Array[Dictionary], "auto_miss": false}
	if opts.get("reaction", false) and Effects.has(target, "weave") and _round_ok(state, target, "weave"):
		_use_round(state, target, "weave")
		out["auto_miss"] = true
		out["events"].append({"type": "effect_triggered", "unit": target.id, "effect": "Weave", "target": attacker.id, "rule_ref": REF})
	if Effects.has(attacker, "impact") and w.get("type", "") == "Cannon" and _round_ok(state, attacker, "impact"):
		_use_round(state, attacker, "impact")
		var ids: Array = state.units.keys()
		ids.sort()
		for id: String in ids:
			var o := state.unit(id)
			if o == attacker or not Combat.is_present(o) or o.kind == Unit.KIND_DEPLOYABLE or Sight.unit_distance(state, attacker, o) > 1:
				continue
			var save := Combat.skill_check(state, o, "hull", "Save vs Impact", attacker.save_target, 0, 0, GearSystems.prone_save_sources(o), true)
			out["events"].append({"type": "skill_check", "unit": o.id, "check": save, "rule_ref": REF})
			if not save["success"]:
				out["events"].append_array(Attacks.knock_back(state, o, attacker.cell, 1, attacker))
				out["events"].append_array(Combat.add_status(state, o, "Prone", attacker.id))
	attacker.counters.erase("chaff")  # Skirmisher chaff is lost when it attacks
	return out


## After the attack roll is known. Returns events; may change `result` through the returned
## "result" key (Particularize rerolls). Called with the check for bookkeeping.
static func after_roll(state: GameState, attacker: Unit, w: Dictionary, target: Unit, kind: String, result: String, lock_on: bool) -> void:
	if state.active_unit == attacker.id:
		if kind == Attacks.KIND_MELEE and w.get("size", "") == "Main":
			attacker.turn["first_main_melee"] = true
		if kind == Attacks.KIND_RANGED and w.get("size", "") == "Auxiliary":
			attacker.turn["first_aux_ranged"] = true
	for e: Dictionary in Effects.of(attacker, "attack_mod"):
		if e.get("per", "") == "round":
			pass  # marked when the source was used (see used_sources)
	if Effects.has(attacker, "relentless"):
		if result == "miss":
			attacker.counters["relentless"] = int(attacker.counters.get("relentless", 0)) + 1
		else:
			attacker.counters.erase("relentless")
	if w.get("key", "") == "ram":
		attacker.counters.erase("ram_momentum")


## Marks 1/round talent Accuracy that was used.
static func used_sources(state: GameState, attacker: Unit, srcs: Array) -> void:
	for s: Dictionary in srcs:
		var e: Dictionary = s.get("talent", {})
		if e.get("per", "") == "round":
			_use_round(state, attacker, String(e.get("label", "")))


## Particularize: an ally adjacent to a Spotter that consumes Lock On rolls twice.
static func particularize(state: GameState, attacker: Unit, lock_on: bool) -> bool:
	if not lock_on:
		return false
	for o: Unit in state.units.values():
		if o != attacker and o.side == attacker.side and Effects.has(o, "particularize") and Combat.is_present(o) and Sight.unit_distance(state, o, attacker) <= 1:
			return true
	return false


## The damage roll for a hit (Brutal Predator: natural 20 crits deal maximum damage).
static func max_damage(attacker: Unit, crit: bool, d20: int) -> bool:
	return crit and d20 == 20 and Effects.has(attacker, "brutal_max")


## Bonus damage from talents for this hit (Nuclear Cavalier Fusion Hemorrhage, Crack Shot
## Zero In). Returned as BonusDamage source dicts.
static func bonus_sources(state: GameState, attacker: Unit, w: Dictionary, target: Unit, info: Dictionary) -> Array:
	var out: Array = []
	if info.get("dz_fusion", false):
		out.append({"value": "1d6", "type": "Energy", "label": "Fusion Hemorrhage"})
	if info.get("zero_in", false) and info.get("crit", false):
		out.append({"value": "1d6", "label": "Zero In"})
	return out


## After a hit: talents that add conditions or damage.
static func on_hit(state: GameState, attacker: Unit, w: Dictionary, target: Unit, crit: bool, kind: String, lock_on: bool, opts: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not Combat.is_present(target):
		return events
	if opts.get("dz_heat", false):
		events.append_array(Combat.apply_heat(state, target, 2, attacker.id))  # Aggressive Heat Bleed
	if crit and w.get("type", "") == "Nexus" and Effects.has(attacker, "nexus_crit") and _round_ok(state, attacker, "nexus_crit"):
		_use_round(state, attacker, "nexus_crit")
		var save := Combat.skill_check(state, target, "systems", "Save vs Ten Thousand Teeth", attacker.save_target, 0, 0, [], true)
		events.append({"type": "skill_check", "unit": target.id, "check": save, "rule_ref": REF})
		if not save["success"]:
			events.append_array(Combat.add_status(state, target, "Impaired", attacker.id, target.id))
			events.append_array(Combat.add_status(state, target, "Slowed", attacker.id, target.id))
	if crit and lock_on and w.get("type", "") == "Nexus" and Effects.has(attacker, "expose_weakness"):
		events.append_array(Combat.add_status(state, target, "Shredded", attacker.id, "", attacker.id))
	if crit and kind == Attacks.KIND_MELEE and w.get("size", "") in ["Heavy", "Superheavy"] and Effects.has(attacker, "wide_arc") and _round_ok(state, attacker, "wide_arc"):
		_use_round(state, attacker, "wide_arc")
		var reach := Weapons.threat_for(attacker, w)
		for o: Unit in state.units.values():
			if o != target and o != attacker and o.side != attacker.side and Combat.is_present(o) and Sight.unit_distance(state, attacker, o) <= reach:
				events.append_array(Combat.deal_damage(state, o, [{"type": "Kinetic", "amount": 3}], {"source": attacker.id}))
	if lock_on and w.get("type", "") == "Launcher" and Effects.has(attacker, "seismic_deluge") and _round_ok(state, attacker, "seismic_deluge"):
		_use_round(state, attacker, "seismic_deluge")
		events.append_array(Combat.add_status(state, target, "Prone", attacker.id))
	if attacker.turn.get("ambush", false):
		attacker.turn.erase("ambush")
		var save := Combat.skill_check(state, target, "hull", "Save vs Ambush", attacker.save_target, 0, 0, [], true)
		events.append({"type": "skill_check", "unit": target.id, "check": save, "rule_ref": REF})
		if not save["success"]:
			for st in ["Slowed", "Impaired", "Reeling"]:
				events.append_array(Combat.add_status(state, target, st, attacker.id, target.id))
	return events


## Start of a turn: chaff, ambush.
static func turn_started(state: GameState, u: Unit) -> void:
	if Effects.has(u, "chaff"):
		u.counters["chaff"] = true
	if Effects.has(u, "ambush") and u.has_status("Hidden"):
		u.turn["ambush"] = true


## Grease Monkey Machine Bond: Stabilize also clears these conditions caused by others.
static func machine_bond(u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not Effects.has(u, "machine_bond"):
		return events
	for st in ["Impaired", "Jammed", "Immobilized", "Slowed", "Lock On"]:
		if u.has_status(st) and String(u.statuses[st].get("source", "")) != u.id:
			events.append_array(Combat.remove_status(u, st, "Machine Bond"))
	return events
