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
##   bonded                  +1 Accuracy on mech checks and saves next to the bondmate
##                           (pilot "bondmate": unit id); +2 if both have it (Bonded 1)
##   backswing               1/round, a hit with a Heavy+ melee weapon grants a free half-damage
##                           attack on another character (action "backswing") (Executioner 1)
##   ammo_case {charges}     1/turn, a Main ranged attack may use params.ammo thumper|shock|mag
##                           (Walking Armory 1)
##   exemplar                the first attack on its turn on a hostile within 3 marks it (unless
##                           params.no_mark); allies who miss the mark may reroll (Valiant Aid
##                           reaction) (Exemplar 1)
##   covering_fire           the Covering Fire quick action and its reaction attack (Heavy Gunner 1)
##   lunge                   1/round, before an Auxiliary melee attack (params.lunge): fly up to 3
##                           spaces straight at the target, ignoring engagement (Hunter 1)
##   ammo_plus               Hellfire, Jager and Sabot ammo, 2 charges each (Walking Armory 2)
##   ammo_crit_free          a crit with special ammo costs no charges (Walking Armory 3)
##   covering_fire_pin       a Covering Fire reaction hit: Immobilized until the end of its next
##                           turn (Heavy Gunner 2)
##   covering_fire_two       Covering Fire on two targets (params.targets) (Heavy Gunner 3)
##   gunslinger_die          Gunslinger Die: aux ranged hits count it down; at 1 the next aux
##                           ranged attack gets +2d6 bonus damage, AP, ignores cover (Gunslinger 3)
##   called_shot             1/round, steadied Rifle crit: Hull save or headshot/leg/body
##                           (params.called_shot, default leg) (Crack Shot 3)
##   return_fire             1/round reaction: hit by a ranged attack, shoot back with an
##                           Auxiliary ranged weapon (Gunslinger 2)
##   intercede               1/round reaction: take the damage the adjacent bondmate would take
##                           from a source in line of sight (Bonded 2)
##   flank                   1/round reaction: an ally hits a character with no cover from you;
##                           attack it for half damage (Tactician 3)
##   melee_reroll            1/round, a missed melee attack is rerolled against another
##                           character in Threat (params.reroll_target, else the nearest) (Executioner 3)
##   hunter_throw            1/round, a melee hit on its turn allows a free thrown Auxiliary melee
##                           attack, no bonus damage (action "hunter_throw") (Hunter 3)
##   exemplar_overwatch      1/round, its mark attacks someone within 3 of it (not it): Overwatch
##                           against the mark (Exemplar 2)
##   spotter_lock            end of its turn, if it didn't move and took Lock On: a free Lock On
##                           (Spotter 2)
##   prowl                   on its own turn: Hidden isn't lost to line of sight or leaving cover,
##                           Hide in plain sight, pass through enemies (Infiltrator 1)

const REF := "talents"
## Walking Armory ammunition: damage type and added tag.
const AMMO := {
	"thumper": {"type": "Explosive", "tag": {"id": "tg_knockback", "val": 1}},
	"shock": {"type": "Energy"},
	"mag": {"type": "Kinetic", "tag": {"id": "tg_arcing"}},
	"hellfire": {"type": "Energy", "cost": 2, "rank": 2},
	"jager": {"type": "Explosive", "tag": {"id": "tg_knockback", "val": 2}, "cost": 2, "rank": 2},
	"sabot": {"type": "Kinetic", "tag": {"id": "tg_ap"}, "cost": 2, "rank": 2},
}
const RANGED_TYPES := ["CQB", "Rifle", "Launcher", "Cannon", "Nexus"]


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
	if gunslinger_ready(attacker, w) or attacker.counters.get("gunslinger_fire", false):
		return true  # Gunslinger 3
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
	if gunslinger_ready(attacker, w):
		# Gunslinger 3: reset the die; this attack gets +2d6, AP and ignores cover.
		attacker.counters["gunslinger_die"] = 6
		attacker.counters["gunslinger_fire"] = true
		out["events"].append({"type": "effect_triggered", "unit": attacker.id, "effect": "Gunslinger Die", "target": target.id, "rule_ref": REF})
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
	if result == "miss":
		attacker.counters.erase("gunslinger_fire")
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
	if attacker.counters.get("gunslinger_fire", false):
		out.append({"value": "2d6", "label": "Gunslinger Die"})
	return out


## After a hit: talents that add conditions or damage.
static func on_hit(state: GameState, attacker: Unit, w: Dictionary, target: Unit, crit: bool, kind: String, lock_on: bool, opts: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not Combat.is_present(target):
		return events
	if opts.get("dz_heat", false):
		events.append_array(Combat.apply_heat(state, target, 2, attacker.id))  # Aggressive Heat Bleed
	if Effects.has(attacker, "gunslinger_die") and String(w.get("size", "")) == "Auxiliary" and RANGED_TYPES.has(String(w.get("type", ""))):
		if attacker.counters.get("gunslinger_fire", false):
			attacker.counters.erase("gunslinger_fire")
		else:
			attacker.counters["gunslinger_die"] = maxi(1, int(attacker.counters.get("gunslinger_die", 6)) - 1)
	if crit and Effects.has(attacker, "called_shot") and w.get("type", "") == "Rifle" and _steadying(attacker) and _round_ok(state, attacker, "called_shot"):
		# Crack Shot 3: Hull save, or the attacker's called shot (default: leg).
		_use_round(state, attacker, "called_shot")
		var save := Combat.skill_check(state, target, "hull", "Save vs called shot", attacker.save_target, 0, 0, [], true)
		events.append({"type": "skill_check", "unit": target.id, "check": save, "rule_ref": REF})
		if not save["success"]:
			match String(opts.get("called_shot", "leg")):
				"head":
					events.append_array(Combat.add_status(state, target, "Blinded", attacker.id, target.id))  # sight only to adjacent spaces
				"body":
					events.append_array(Combat.add_status(state, target, "Prone", attacker.id))
				_:
					events.append_array(Combat.add_status(state, target, "Immobilized", attacker.id, target.id))
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
	if kind == Attacks.KIND_MELEE and Effects.has(attacker, "hunter_throw") and _round_ok(state, attacker, "hunter_throw") and state.active_unit == attacker.id \
			and not opts.get("hunter_throw", false):
		attacker.turn["hunter_throw"] = true
		events.append({"type": "follow_up_available", "unit": attacker.id, "action": "hunter_throw",
			"text": "Hunter: throw an Auxiliary melee weapon at any character in Range as a free action.", "rule_ref": REF})
	if kind == Attacks.KIND_MELEE and w.get("size", "") in ["Heavy", "Superheavy"] and Effects.has(attacker, "backswing") \
			and _round_ok(state, attacker, "backswing") and state.active_unit == attacker.id and not opts.get("backswing", false):
		# Executioner Backswing Cut: a free follow-up attack is available (action "backswing").
		attacker.turn["backswing"] = {"weapon": String(w.get("key", "")), "not": target.id}
		events.append({"type": "follow_up_available", "unit": attacker.id, "action": "backswing", "weapon": w.get("key", ""),
			"text": "Backswing Cut: a free melee attack with the same weapon on a different character, for half damage.", "rule_ref": REF})
	if attacker.turn.get("ambush", false):
		attacker.turn.erase("ambush")
		var save := Combat.skill_check(state, target, "hull", "Save vs Ambush", attacker.save_target, 0, 0, [], true)
		events.append({"type": "skill_check", "unit": target.id, "check": save, "rule_ref": REF})
		if not save["success"]:
			for st in ["Slowed", "Impaired", "Reeling"]:
				events.append_array(Combat.add_status(state, target, st, attacker.id, target.id))
	return events


## Bonded: Accuracy on a mech's skill checks and saves next to its bondmate (+1, +2 if both
## have the talent and chose each other).
static func bond_sources(state: GameState, u: Unit) -> Array:
	if state == null or u.kind != Unit.KIND_MECH:
		return []
	var best := 0
	for o: Unit in state.units.values():
		if o == u or not Combat.is_present(o) or Sight.unit_distance(state, u, o) > 1:
			continue
		var n := 0
		if Effects.has(u, "bonded") and String(u.counters.get("bondmate", "")) == o.id:
			n += 1
		if Effects.has(o, "bonded") and String(o.counters.get("bondmate", "")) == u.id:
			n += 1
		best = maxi(best, n)
	if best == 0:
		return []
	return [{"label": "Bondmate", "kind": "accuracy", "type": "accuracy", "value": mini(2, best), "rule_ref": "talents: Bonded"}]


## Walking Armory: can this attack use that ammo?
static func check_ammo(u: Unit, w: Dictionary, ammo: String) -> RuleResult:
	var ref := "talents: Walking Armory"
	if not AMMO.has(ammo):
		return RuleResult.deny("Ammo is thumper, shock, mag (or hellfire, jager, sabot at rank 2).", ref)
	if not Effects.has(u, "ammo_case"):
		return RuleResult.deny("Special ammunition needs the Walking Armory talent.", ref)
	if int(AMMO[ammo].get("rank", 1)) > 1 and not Effects.has(u, "ammo_plus"):
		return RuleResult.deny("%s ammunition needs Walking Armory rank 2." % ammo.capitalize(), ref)
	if String(w.get("size", "")) != "Main" or not RANGED_TYPES.has(String(w.get("type", ""))):
		return RuleResult.deny("Special ammunition is for Main ranged weapons.", ref)
	if u.turn.get("ammo_used", false):
		return RuleResult.deny("Special ammunition only once per turn.", ref)
	if ammo_left(u) < int(AMMO[ammo].get("cost", 1)):
		return RuleResult.deny("Not enough charges left in the Ammo Case.", ref)
	return RuleResult.allow()


static func ammo_left(u: Unit) -> int:
	if not u.counters.has("ammo_case"):
		u.counters["ammo_case"] = Effects.value(u, "ammo_case", "charges") + Effects.value(u, "limited_bonus")
	return int(u.counters["ammo_case"])


## Spends a charge; returns the event (empty if no ammo was used).
static func spend_ammo(u: Unit, ammo: String) -> Dictionary:
	if not AMMO.has(ammo) or not Effects.has(u, "ammo_case"):
		return {}
	u.counters["ammo_case"] = ammo_left(u) - int(AMMO[ammo].get("cost", 1))
	u.turn["ammo_used"] = true
	return {"type": "effect_triggered", "unit": u.id, "effect": "Ammo Case: " + ammo.capitalize(), "target": u.id,
		"charges": u.counters["ammo_case"], "rule_ref": "talents: Walking Armory"}


## After the attack: Shock's splash, Jager's Hull save, Walking Armory 3's free crit.
## PROVISIONAL: Jager's save falls on the attack's target; Hellfire's bonus damage as burn is
## the table's.
static func shock_ammo(state: GameState, u: Unit, ammo: String, target: Unit, fired: Array[Dictionary] = []) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not AMMO.has(ammo) or target == null:
		return events
	var first: Dictionary = {}
	for ev: Dictionary in fired:
		if ev.get("type", "") == "attack_rolled" and ev.get("attacker", "") == u.id:
			first = ev
			break
	if Effects.has(u, "ammo_crit_free") and first.get("result", "") == "crit":
		u.counters["ammo_case"] = ammo_left(u) + int(AMMO[ammo].get("cost", 1))
		events.append({"type": "effect_triggered", "unit": u.id, "effect": "Ammo Case: critical hit, no charges spent", "target": u.id, "rule_ref": "talents: Walking Armory"})
	if ammo == "jager" and first.get("result", "miss") != "miss" and Combat.is_present(target):
		var save := Combat.skill_check(state, target, "hull", "Save vs Jager round", u.save_target, 0, 0, GearSystems.prone_save_sources(target), true)
		events.append({"type": "skill_check", "unit": target.id, "check": save, "rule_ref": "talents: Walking Armory"})
		if not save["success"]:
			events.append_array(Combat.add_status(state, target, "Prone", u.id))
	if ammo != "shock":
		return events
	var ids: Array = state.units.keys()
	ids.sort()
	for id: String in ids:
		var o := state.unit(id)
		if o != target and o != u and Combat.is_present(o) and o.kind != Unit.KIND_DEPLOYABLE and Sight.unit_distance(state, o, target) <= 1:
			events.append_array(Combat.deal_damage(state, o, [{"type": "Energy", "amount": 1}], {"ap": true, "source": u.id}))
	return events


## Exemplar's Mark (Honorable Challenge): after the first attack on its turn against a hostile
## within Range 3, hit or miss. One mark per character; it lasts until the start of the
## Exemplar's next turn.
static func exemplar_mark(state: GameState, attacker: Unit, target: Unit, opts: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not Effects.has(attacker, "exemplar") or state.active_unit != attacker.id or attacker.turn.get("exemplar_attacked", false):
		return events
	if target.side == attacker.side or target.kind == Unit.KIND_DEPLOYABLE or opts.get("reaction", false):
		return events
	attacker.turn["exemplar_attacked"] = true
	if opts.get("no_mark", false) or Sight.unit_distance(state, attacker, target) > 3 or not Combat.is_present(target):
		return events
	target.counters["exemplar_mark"] = attacker.id  # replaces any other mark
	events.append({"type": "effect_triggered", "unit": attacker.id, "effect": "Exemplar's Mark", "target": target.id,
		"text": "Marked until the start of its next turn: allies who miss it may reroll (Valiant Aid).", "rule_ref": "talents: Exemplar"})
	return events


## Valiant Aid (1/round reaction): an ally attacked the Exemplar's mark and missed. Returns the
## Exemplar who lets them reroll, or null.
static func valiant_aid(state: GameState, attacker: Unit, target: Unit) -> Unit:
	var ex := state.unit(String(target.counters.get("exemplar_mark", "")))
	if ex == null or ex == attacker or ex.side != attacker.side or not Effects.has(ex, "exemplar") or not _round_ok(state, ex, "valiant_aid"):
		return null
	if not Reactions.can_react(ex, "valiant_aid", state).ok:
		return null
	var d := Reactions.offer(state, ex, "valiant_aid", {"attacker": attacker.id, "target": target.id, "suggested": {"take": true}}, {"take": true})
	if not d.get("take", false):
		return null
	_use_round(state, ex, "valiant_aid")
	Reactions._mark_used(ex, "valiant_aid", state)
	return ex


## Heavy Gunner Covering Fire: a character within 10, in line of sight and in Range of one of
## your Heavy ranged weapons.
static func check_covering_fire(state: GameState, u: Unit, t: Unit) -> RuleResult:
	var ref := "talents: Heavy Gunner"
	if t == null or not Combat.is_present(t) or t.kind == Unit.KIND_DEPLOYABLE or t == u:
		return RuleResult.deny("Choose a character (params.target).", ref)
	if Sight.unit_distance(state, u, t) > 10 or not Sight.unit_line_of_sight(state, u, t):
		return RuleResult.deny("It must be within 10 spaces and in line of sight.", ref)
	if _heavy_ranged(state, u, t).is_empty():
		return RuleResult.deny("It must be in Range of one of your Heavy ranged weapons.", ref)
	return RuleResult.allow()


static func _heavy_ranged(state: GameState, u: Unit, t: Unit) -> Dictionary:
	for w: Dictionary in u.loadout.get("weapons", []):
		if String(w.get("size", "")) == "Heavy" and String(w.get("type", "")) != "Melee" and Attacks.preview(state, u, w, t, {"reaction": true})["ok"]:
			return w
	return {}


## Impaired until the start of your next turn; one target at a time.
static func covering_fire(state: GameState, u: Unit, targets: Array) -> Array[Dictionary]:
	for o: Unit in state.units.values():
		if String(o.counters.get("covering_fire", "")) == u.id:
			o.counters.erase("covering_fire")
			o.counters.erase("cf_moved")
	var events: Array[Dictionary] = []
	for t: Unit in targets:
		t.counters["covering_fire"] = u.id
		t.counters["cf_moved"] = 0
		events.append({"type": "effect_triggered", "unit": u.id, "effect": "Covering Fire", "target": t.id,
			"text": "Impaired until the start of your next turn; if it moves more than 1 space it shakes that off, but you may shoot it (half damage).", "rule_ref": "talents: Heavy Gunner"})
		events.append_array(Combat.add_status(state, t, "Impaired", u.id, "", u.id))
	return events


## The Covering Fire targets an action names: params.targets (2 with Heavy Gunner 3) or target.
static func covering_targets(state: GameState, u: Unit, params: Dictionary) -> Array:
	var ids: Array = params.get("targets", [params.get("target", "")]) if Effects.has(u, "covering_fire_two") else [params.get("target", "")]
	var out: Array = []
	for id: Variant in ids.slice(0, 2):
		out.append(state.unit(str(id)))
	return out


## The covered character moved: past 1 space it clears Impaired and the gunner may attack it
## as a reaction with a Heavy ranged weapon for half damage, heat and burn; then it ends.
## PROVISIONAL: the attack comes after the move that took it past 1 space.
static func covered_moved(state: GameState, t: Unit, spaces: int) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var g := state.unit(String(t.counters.get("covering_fire", "")))
	if g == null:
		return events
	t.counters["cf_moved"] = int(t.counters.get("cf_moved", 0)) + spaces
	if int(t.counters["cf_moved"]) <= 1:
		return events
	t.counters.erase("covering_fire")
	t.counters.erase("cf_moved")
	if t.has_status("Impaired") and String(t.statuses["Impaired"].get("source", "")) == g.id:
		events.append_array(Combat.remove_status(t, "Impaired", "moved out of the covering fire"))
	if not Combat.is_present(g) or not Combat.is_present(t) or not _round_ok(state, g, "covering_fire_attack") or not Reactions.can_react(g, "covering_fire_attack", state).ok:
		return events
	var w := _heavy_ranged(state, g, t)
	if w.is_empty():
		return events
	var d := Reactions.offer(state, g, "covering_fire_attack", {"target": t.id, "weapon": w.get("key", ""), "suggested": {"take": true}}, {"take": true})
	if not d.get("take", false):
		return events
	_use_round(state, g, "covering_fire_attack")
	Reactions._mark_used(g, "covering_fire_attack", state)
	var shot := Attacks.attack(state, g, w, t, {"reaction": true, "half_damage": true})
	events.append_array(shot)
	if Effects.has(g, "covering_fire_pin") and Combat.is_present(t) and shot.any(func(ev: Dictionary) -> bool: return ev.get("type", "") == "attack_rolled" and ev.get("result", "miss") != "miss"):
		events.append_array(Combat.add_status(state, t, "Immobilized", g.id, t.id))  # Heavy Gunner 2
	return events


## Covering Fire ends at once if its target damages the gunner.
static func damaged_by(target: Unit, source: Unit) -> void:
	if source != null and String(source.counters.get("covering_fire", "")) == target.id:
		source.counters.erase("covering_fire")
		source.counters.erase("cf_moved")


## Gunslinger 3: is this attack the charged one (die at 1, Auxiliary ranged weapon)?
static func gunslinger_ready(u: Unit, w: Dictionary) -> bool:
	return Effects.has(u, "gunslinger_die") and int(u.counters.get("gunslinger_die", 6)) <= 1 \
		and String(w.get("size", "")) == "Auxiliary" and RANGED_TYPES.has(String(w.get("type", "")))


## Reactions and follow-ups after an attack resolves: Return Fire, Flank, Executioner 3.
static func after_attack(state: GameState, attacker: Unit, w: Dictionary, target: Unit, kind: String, result: String, opts: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if target.kind == Unit.KIND_DEPLOYABLE or attacker.destroyed:
		return events
	if result == "miss" and kind == Attacks.KIND_MELEE and Effects.has(attacker, "melee_reroll") and _round_ok(state, attacker, "melee_reroll") and not opts.get("reroll", false):
		var other := state.unit(String(opts.get("reroll_target", "")))
		if other == null:
			var best := 1000
			for o: Unit in state.units.values():
				if o != target and o.side != attacker.side and Combat.is_present(o) and o.kind != Unit.KIND_DEPLOYABLE \
						and Attacks.preview(state, attacker, w, o, {"fired_by_rule": true})["ok"] and Sight.unit_distance(state, attacker, o) < best:
					best = Sight.unit_distance(state, attacker, o)
					other = o
		if other != null and other != target and Attacks.preview(state, attacker, w, other, {"fired_by_rule": true})["ok"]:
			_use_round(state, attacker, "melee_reroll")
			events.append({"type": "attack_rerolled", "attacker": attacker.id, "target": other.id, "source": "Executioner", "rule_ref": REF})
			events.append_array(Attacks.attack(state, attacker, w, other, {"fired_by_rule": true, "skip_spend": true, "reroll": true}))
	events.append_array(_exemplar_overwatch(state, attacker, target))
	if result == "miss" or not Combat.is_present(target):
		return events
	if kind == Attacks.KIND_RANGED and Effects.has(target, "return_fire") and _round_ok(state, target, "return_fire") and Combat.is_present(attacker) \
			and Reactions.can_react(target, "return_fire", state).ok:
		for rw: Dictionary in target.loadout.get("weapons", []):
			if String(rw.get("size", "")) == "Auxiliary" and RANGED_TYPES.has(String(rw.get("type", ""))) and Attacks.preview(state, target, rw, attacker, {"reaction": true})["ok"]:
				var d := Reactions.offer(state, target, "return_fire", {"attacker": attacker.id, "weapon": rw.get("key", ""), "suggested": {"take": true}}, {"take": true})
				if d.get("take", false):
					_use_round(state, target, "return_fire")
					Reactions._mark_used(target, "return_fire", state)
					events.append_array(Attacks.attack(state, target, rw, attacker, {"reaction": true}))
				break
	var ids: Array = state.units.keys()
	ids.sort()
	for id: String in ids:
		var o := state.unit(id)
		if o == attacker or o.side != attacker.side or not Effects.has(o, "flank") or not Combat.is_present(o) or not Combat.is_present(target):
			continue
		if not _round_ok(state, o, "flank") or not Reactions.can_react(o, "flank", state).ok:
			continue
		if String(Sight.unit_cover(state, o, target).get("cover", "none")) != "none":
			continue
		for fw: Dictionary in o.loadout.get("weapons", []):
			if Attacks.preview(state, o, fw, target, {"reaction": true})["ok"]:
				var d := Reactions.offer(state, o, "flank", {"target": target.id, "weapon": fw.get("key", ""), "suggested": {"take": true}}, {"take": true})
				if d.get("take", false):
					_use_round(state, o, "flank")
					Reactions._mark_used(o, "flank", state)
					events.append_array(Attacks.attack(state, o, fw, target, {"reaction": true, "half_damage": true}))
				break
	return events


## Exemplar 2: the mark attacked a character within Range 3 of its Exemplar (not the
## Exemplar): Overwatch against it. PROVISIONAL: after that attack resolves.
static func _exemplar_overwatch(state: GameState, attacker: Unit, target: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var ex := state.unit(String(attacker.counters.get("exemplar_mark", "")))
	if ex == null or ex == target or not Effects.has(ex, "exemplar_overwatch") or not Combat.is_present(ex) or not Combat.is_present(attacker):
		return events
	if Sight.unit_distance(state, ex, target) > 3 or not _round_ok(state, ex, "exemplar_overwatch") or not Reactions.can_react(ex, "overwatch", state).ok:
		return events
	for w: Dictionary in ex.loadout.get("weapons", []):
		if Attacks.preview(state, ex, w, attacker, {"reaction": true})["ok"]:
			var d := Reactions.offer(state, ex, "overwatch", {"target": attacker.id, "weapon": w.get("key", ""), "trigger": "exemplar", "suggested": {"take": true, "weapon": w.get("key", "")}}, {"take": true})
			if d.get("take", false):
				_use_round(state, ex, "exemplar_overwatch")
				Reactions._mark_used(ex, "overwatch", state)
				events.append_array(Attacks.attack(state, ex, w, attacker, {"reaction": true}))
			break
	return events


## Spotter 2: end of turn, didn't move and took Lock On: a free Lock On. PROVISIONAL: on the
## character it Locked On this turn if that was consumed, else the nearest hostile in Sensors
## and line of sight without Lock On.
static func turn_ending(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not Effects.has(u, "spotter_lock") or u.turn.get("moved", false) or not (u.turn.get("quick_tech", []) as Array).has("lock_on"):
		return events
	var pick: Unit = state.unit(String(u.turn.get("locked_on", "")))
	if pick == null or pick.has_status("Lock On") or not Combat.is_present(pick):
		pick = null
		var best := 1000
		for o: Unit in state.units.values():
			if o.side == u.side or not Combat.is_present(o) or o.kind == Unit.KIND_DEPLOYABLE or o.has_status("Lock On") or o.has_status("Hidden"):
				continue
			var dist := Sight.unit_distance(state, u, o)
			if dist <= u.sensors and dist < best and Sight.unit_line_of_sight(state, u, o):
				best = dist
				pick = o
	if pick != null:
		events.append({"type": "effect_triggered", "unit": u.id, "effect": "Spotter: free Lock On", "target": pick.id, "rule_ref": REF})
		events.append_array(Combat.add_status(state, pick, "Lock On", u.id))
	return events


## Bonded Intercede: the bondmate next to `target` (who has the talent and chose it) takes the
## damage instead, if it can see the source. Returns that bondmate, or null.
static func intercede(state: GameState, target: Unit, source: Unit, parts: Array) -> Unit:
	if source == null or parts.all(func(p: Dictionary) -> bool: return String(p.get("type", "")) == "Heat"):
		return null
	for o: Unit in state.units.values():
		if o == target or not Effects.has(o, "intercede") or String(o.counters.get("bondmate", "")) != target.id:
			continue
		if not Combat.is_present(o) or Sight.unit_distance(state, o, target) > 1 or not Sight.unit_line_of_sight(state, o, source):
			continue
		if not _round_ok(state, o, "intercede") or not Reactions.can_react(o, "intercede", state).ok:
			continue
		# Suggested only when the hit would take the bondmate down and the interceder can take it.
		var total := 0
		for p: Dictionary in parts:
			total += int(p.get("amount", 0))
		var d := Reactions.offer(state, o, "intercede", {"target": target.id, "source": source.id, "suggested": {"take": total >= target.hp and o.hp > total}},
			{"take": total >= target.hp and o.hp > total})
		if d.get("take", false):
			_use_round(state, o, "intercede")
			Reactions._mark_used(o, "intercede", state)
			return o
	return null


## Infiltrator Prowl is active (its own turn).
static func prowling(state: GameState, u: Unit) -> bool:
	return state != null and u != null and state.active_unit == u.id and Effects.has(u, "prowl")


static func check_lunge(state: GameState, u: Unit, w: Dictionary, t: Unit) -> RuleResult:
	var ref := "talents: Hunter"
	if not Effects.has(u, "lunge"):
		return RuleResult.deny("Lunge needs the Hunter talent.", ref)
	if String(w.get("size", "")) != "Auxiliary" or String(w.get("type", "")) != "Melee":
		return RuleResult.deny("Lunge is for Auxiliary melee weapons.", ref)
	if not _round_ok(state, u, "lunge"):
		return RuleResult.deny("Lunge only once per round.", ref)
	if t == null or not Combat.is_present(t):
		return RuleResult.deny("Choose the target first.", ref)
	if u.has_status("Immobilized"):
		return RuleResult.deny("You can't move while Immobilized.", "statuses: Immobilized")
	return RuleResult.allow()


## Up to 3 spaces straight toward the target. PROVISIONAL: along the ground path that gets
## closest (flight over obstacles isn't modelled).
static func lunge_path(state: GameState, u: Unit, t: Unit) -> Array:
	return Movement.pull_path_to(state, u, Sight.body_of(state, t), 1, 3)


## The lunge: no engagement stop and no reactions (so not involuntary movement either).
static func lunge(state: GameState, u: Unit, t: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	_use_round(state, u, "lunge")
	var path := lunge_path(state, u, t)
	if path.size() < 2:
		return events
	var last: Array = path.back()
	u.cell = Vector2i(last[0], last[1])
	u.level = int(last[2])
	events.append({"type": "moved", "unit": u.id, "path": path, "mode": "fly", "cost": 0, "rule_ref": "talents: Hunter"})
	events.append_array(Combat.refresh_engagement(state))
	return events


## Start of a turn: chaff, ambush.
static func turn_started(state: GameState, u: Unit) -> void:
	for o: Unit in state.units.values():
		if String(o.counters.get("exemplar_mark", "")) == u.id:
			o.counters.erase("exemplar_mark")  # until the start of the Exemplar's next turn
		if String(o.counters.get("covering_fire", "")) == u.id:
			o.counters.erase("covering_fire")
			o.counters.erase("cf_moved")
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
