class_name BonusDamage
extends RefCounted
## Bonus damage (Core p.67): only on melee or ranged attacks, only kinetic, explosive or energy
## (kinetic unless the source names a type, or the attacker picks one of the weapon's types);
## halved when the attack targets more than one character; rolled twice on a critical hit,
## keeping the highest (Core p.64). Auxiliary follow-ups in a Barrage/Skirmish deal none.
##
## Sources are effects of kind "bonus_damage":
##   {value: "1d6" or 3, type?: Kinetic|Explosive|Energy, on: attack|melee|ranged,
##    per?: "round" (1/round), crit_only?, by_size?: {Auxiliary: "1d6", Main: ..., Heavy: ...},
##    when?: after_boost (Nelson Momentum: the next melee attack after a Boost)
##           | isolated (Mourning Cloak Hunter: no other character adjacent to the target)
##           | exposed (Tokugawa Limit Break) | focus (Death's Head Mark for Death target, not
##           in cover and beyond range 5)}
## Plasma Sheath ("bonus_to_burn"): in the Danger Zone, with a weapon that deals energy, all
## bonus damage becomes burn.

const REF := "Core p.67 Bonus Damage"
const TYPES := ["Kinetic", "Explosive", "Energy"]


## Bonus damage parts for one hit. `info`: {kind (melee/ranged), crit, cover, distance,
## targets (characters the attack targets), shared (area roll cache)}.
## Returns {"parts": [{type, amount}], "events": [...]}.
static func roll(state: GameState, attacker: Unit, w: Dictionary, target: Unit, info: Dictionary) -> Dictionary:
	var out := {"parts": [], "events": [] as Array[Dictionary]}
	var kind := String(info.get("kind", ""))
	if kind != Attacks.KIND_MELEE and kind != Attacks.KIND_RANGED:
		return out
	var weapon_types := Weapons.damage_types(attacker, w)
	var to_burn := false
	for e: Dictionary in Effects.of(attacker, "bonus_to_burn"):
		if attacker.has_status("Danger Zone") and weapon_types.has(String(e.get("weapon_damage", "Energy"))):
			to_burn = true
	var shared: Dictionary = info.get("shared", {})
	var halve := int(info.get("targets", 1)) > 1
	var i := 0
	for e: Dictionary in sources(state, attacker, w, target, info):
		var expr := _expr(e, w)
		if expr == "":
			continue
		var key := "bonus:%d:%s" % [i, "crit" if info.get("crit", false) else "base"]
		i += 1
		var r: Dictionary
		if info.get("max", false):
			r = Attacks.max_roll(expr)  # Brutal: Predator
		elif shared.has(key):
			r = shared[key]
		else:
			r = Attacks.roll_damage(state, expr, bool(info.get("crit", false)), false)
			shared[key] = r
		var amount := int(r["total"])
		if halve:
			amount = amount - amount / 2  # always round up (Core p.12)
		var dtype := String(e.get("type", ""))
		if dtype == "" or not TYPES.has(dtype):
			# Default kinetic, or one of the weapon's own types (Core p.67): we use the weapon's
			# first kinetic/explosive/energy type.
			dtype = "Kinetic"
			for t: String in weapon_types:
				if TYPES.has(t):
					dtype = t
					break
		dtype = Weapons.swapped_type(attacker, dtype)
		if to_burn:
			dtype = "Burn"
		_mark_used(state, attacker, e)
		out["events"].append({"type": "bonus_damage", "attacker": attacker.id, "target": target.id, "source": e.get("label", ""),
			"damage_type": dtype, "roll": r, "amount": amount, "halved": halve, "rule_ref": REF})
		if amount > 0:
			out["parts"].append({"type": dtype, "amount": amount})
	return out


## The bonus damage effects that apply to this hit.
static func sources(state: GameState, attacker: Unit, w: Dictionary, target: Unit, info: Dictionary) -> Array:
	var out: Array = []
	var kind := String(info.get("kind", ""))
	for e: Dictionary in Effects.of(attacker, "bonus_damage"):
		var on := String(e.get("on", "attack"))
		if on != "attack" and on != kind:
			continue
		if e.get("crit_only", false) and not info.get("crit", false):
			continue
		if e.get("per", "") == "round" and _used_this_round(state, attacker, e):
			continue
		match String(e.get("when", "")):
			"after_boost":
				if not info.get("momentum", false):
					continue
			"isolated":
				if not isolated(state, attacker, target):
					continue
			"exposed":
				if not attacker.has_status("Exposed"):
					continue
			"focus":
				if String(attacker.counters.get("focus", "")) != target.id or String(info.get("cover", "none")) != "none" \
						or int(info.get("distance", 0)) <= 5:
					continue
		out.append(e)
	if attacker.turn.has("lucifer") and Weapons.damage_types(attacker, w).has("Energy"):
		# LUCIFER: bonus damage equal to your heat just after activating it, once.
		out.append({"value": int(attacker.turn["lucifer"]), "label": "LUCIFER Protocol"})
		attacker.turn.erase("lucifer")
	var lock := {"value": 3, "label": "Hunter Lock", "per": "round"}
	if String(attacker.counters.get("hunter_lock", "")) == target.id and not _used_this_round(state, attacker, lock):
		out.append(lock)  # Hunter Lock: the first successful attack each round, +3
	out.append_array(TalentRules.bonus_sources(state, attacker, w, target, info))
	var crit_extra := WeaponRules.crit_bonus(w)
	if crit_extra != "" and info.get("crit", false):
		out.append({"value": crit_extra, "label": String(w.get("name", ""))})
	return out


## Mourning Cloak Hunter: the target has no adjacent characters, or only the attacker.
static func isolated(state: GameState, attacker: Unit, target: Unit) -> bool:
	for o: Unit in state.units.values():
		if o == attacker or o == target or not Combat.is_present(o) or o.kind == Unit.KIND_DEPLOYABLE:
			continue
		if Sight.unit_distance(state, o, target) <= 1:
			return false
	return true


static func _expr(e: Dictionary, w: Dictionary) -> String:
	if e.has("by_size"):
		var by: Dictionary = e["by_size"]
		return String(by.get(String(w.get("size", "")), by.get("Heavy", "") if String(w.get("size", "")) == "Superheavy" else ""))
	return str(e.get("value", ""))


static func _used_this_round(state: GameState, u: Unit, e: Dictionary) -> bool:
	return int((u.counters.get("bonus_used", {}) as Dictionary).get(String(e.get("label", "")), -1)) == state.round_number


static func _mark_used(state: GameState, u: Unit, e: Dictionary) -> void:
	if e.get("per", "") != "round":
		return
	var used: Dictionary = u.counters.get("bonus_used", {})
	used[String(e.get("label", ""))] = state.round_number
	u.counters["bonus_used"] = used
