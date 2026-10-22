class_name WeaponRules
extends RefCounted
## Weapon special rules beyond tags. Two sources, both copied onto the weapon by UnitFactory:
## - lancer-data's structured "on_hit" / "on_crit" (add_status with an optional save and
##   duration), e.g. Concussion Missiles, Catalytic Hammer;
## - our encodings in data/game/weapon_effects.json, under weapon["rules"]:
##     on_hit / on_crit  [{status, save?, until: end_next_turn|end_this_turn|""}]
##     ignore_engaged    no +1 Difficulty for being Engaged (Bristlecrown)
##     damage_vs         {grappled_or_biological: n}: that much kinetic instead (Bristlecrown)
##     object_damage     "10": AP energy to objects and deployables instead (Cutter torch)
##     overkill_bonus_vs [statuses]: each Overkill activation adds +1d6 bonus damage
##                       against a target with one of them (Combat Drill)
##     line_attack       also attacks every character on the line to the target, 1 heat per
##                       extra target (Impact Lance)
##     spin_up {profile, status, skirmish_only_standard?}: a Spin Up quick action switches to
##                       that profile and the status; a protocol ends it (Assault Cannon,
##                       Leviathan)

const STATUS_NAMES := {"impaired": "Impaired", "immobilized": "Immobilized", "prone": "Prone", "stunned": "Stunned",
	"slowed": "Slowed", "slow": "Slowed", "jammed": "Jammed", "shredded": "Shredded", "lock_on": "Lock On", "exposed": "Exposed"}
const SAVES := {"hull": "hull", "agi": "agility", "agility": "agility", "sys": "systems", "systems": "systems", "eng": "engineering", "engineering": "engineering"}


static func rules(w: Dictionary) -> Dictionary:
	return w.get("rules", {})


## The weapon as fired with a chosen profile or pattern (params.profile: index;
## params.pattern: "Cone"/"Line"... for weapons that list more than one). Never changes the
## loadout's own copy.
static func variant(w: Dictionary, params: Dictionary) -> Dictionary:
	var out := w
	if params.has("profile") and (w.get("profiles", []) as Array).size() > 1 and not rules(w).has("spin_up") and not w.get("integrated", false):
		out = w.duplicate(true)
		Weapons.set_profile(out, int(params["profile"]))
	if params.has("pattern"):
		var pat := String(params["pattern"])
		if Weapons.AREA_TYPES.has(pat) and Weapons.range_value(w, pat) > 0:
			out = out.duplicate(true)
			out["range"] = (out["range"] as Array).filter(func(r: Dictionary) -> bool: return not Weapons.AREA_TYPES.has(r.get("type", "")) or r["type"] == pat)
	return out


## The weapon's on-hit (and on-crit) conditions in one shape: [{status, save, until}].
static func hit_statuses(w: Dictionary, crit: bool) -> Array:
	var out: Array = []
	for field in (["on_hit", "on_crit"] if crit else ["on_hit"]):
		out.append_array(rules(w).get(field, []))
		var raw: Variant = w.get("data_" + field, {})
		if raw is Dictionary:
			for st: Dictionary in (raw as Dictionary).get("add_status", []):
				var name := String(STATUS_NAMES.get(String(st.get("id", "")), ""))
				if name == "":
					continue
				var until := "end_next_turn" if String(st.get("duration", "")).begins_with("next_turn_end") else ""
				out.append({"status": name, "save": String(SAVES.get(String(st.get("save", "")), "")), "until": until})
	return out


## Bonus damage a weapon itself deals on a crit (Variable Sword: +1d6), from lancer-data.
static func crit_bonus(w: Dictionary) -> String:
	var raw: Variant = w.get("data_on_crit", {})
	if raw is Dictionary and (raw as Dictionary).get("bonus_damage") is Dictionary:
		return str(raw["bonus_damage"].get("val", ""))
	return ""


static func on_hit(state: GameState, attacker: Unit, w: Dictionary, target: Unit, crit: bool) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if crit and rules(w).get("on_crit_pull", false) and Combat.is_present(target):
		events.append_array(Attacks.pull(state, target, attacker))  # Nanobot Whip
	var pull: Dictionary = rules(w).get("on_hit_pull", {})
	if not pull.is_empty() and Combat.is_present(target):
		# Magnetic Cannon: Hull save or pulled toward the attacker.
		var save := Combat.skill_check(state, target, String(pull.get("save", "hull")), "Save vs %s" % w.get("name", ""), attacker.save_target, 0, 0, [], true)
		events.append({"type": "skill_check", "unit": target.id, "check": save, "rule_ref": "weapons: " + String(w.get("name", ""))})
		if not save["success"]:
			var n := int(state.dice.roll(String(pull.get("spaces", "1")))["total"])
			events.append_array(Attacks.pull_to(state, target, Sight.body_of(state, attacker), 1, n))
	for st: Dictionary in hit_statuses(w, crit):
		if not Combat.is_present(target):
			break
		var save := String(st.get("save", ""))
		if save != "":
			var check := Combat.skill_check(state, target, save, "Save vs %s" % w.get("name", ""), attacker.save_target, 0, 0, [], true)
			events.append({"type": "skill_check", "unit": target.id, "check": check, "rule_ref": "weapons: " + String(w.get("name", ""))})
			if check["success"]:
				continue
		match String(st.get("until", "")):
			"end_next_turn":
				events.append_array(Combat.add_status(state, target, String(st["status"]), attacker.id, target.id))
			"end_this_turn":
				var who := state.active_unit if state.active_unit != "" else attacker.id
				events.append_array(Combat.add_status(state, target, String(st["status"]), attacker.id, who))
				if target.statuses.has(String(st["status"])):
					target.statuses[String(st["status"])]["turns"] = 1
			_:
				events.append_array(Combat.add_status(state, target, String(st["status"]), attacker.id))
	return events


## Damage to use instead of the weapon's own against this target, or [] (Bristlecrown, Cutter).
static func damage_override(attacker: Unit, w: Dictionary, target: Unit) -> Array:
	var r := rules(w)
	if r.has("object_damage") and target.kind == Unit.KIND_DEPLOYABLE:
		return [{"type": "Energy", "val": str(r["object_damage"]), "ap": true}]
	var vs: Dictionary = r.get("damage_vs", {})
	if vs.has("grappled_or_biological") and (target.counters.has("grapple") or target.kind == Unit.KIND_PILOT):
		return [{"type": "Kinetic", "val": str(vs["grappled_or_biological"])}]
	return []


## Combat Drill: each Overkill activation against a Prone, Immobilized or Stunned target adds
## +1d6 bonus damage, which can trigger Overkill again. Returns {total, heat, events}.
static func drill_bonus(state: GameState, attacker: Unit, w: Dictionary, target: Unit, activations: int) -> Dictionary:
	var out := {"total": 0, "heat": 0, "events": [] as Array[Dictionary]}
	var vs: Array = rules(w).get("overkill_bonus_vs", [])
	if vs.is_empty() or activations <= 0 or not vs.any(func(s: String) -> bool: return target.has_status(s)):
		return out
	var n := activations
	while n > 0:
		var r := Attacks.roll_damage(state, "%dd6" % n, false, true)
		out["total"] = int(out["total"]) + int(r["total"])
		out["heat"] = int(out["heat"]) + int(r["overkill_heat"])
		n = int(r["overkill_heat"])
		out["events"].append({"type": "bonus_damage", "attacker": attacker.id, "target": target.id, "source": w.get("name", ""),
			"damage_type": "Kinetic", "roll": r, "amount": int(r["total"]), "halved": false, "rule_ref": "weapons: Combat Drill"})
	return out


## Impact Lance: every other character on the line from the attacker to the target.
static func line_targets(state: GameState, attacker: Unit, target: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	var cells := state.map.grid.line(attacker.cell, target.cell)
	for o: Unit in state.units.values():
		if o == attacker or o == target or not Combat.is_present(o) or o.kind == Unit.KIND_DEPLOYABLE:
			continue
		for c in state.map.grid.footprint(o.cell, o.size):
			if cells.has(c):
				out.append(o)
				break
	out.sort_custom(func(a: Unit, b: Unit) -> bool: return Sight.unit_distance(state, attacker, a) < Sight.unit_distance(state, attacker, b))
	return out


## Spin Up / Spin Down (ops "spin_up", "spin_down" with the weapon key).
static func spin(state: GameState, u: Unit, key: String, up: bool) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var w := Weapons.find(u, key)
	var spec: Dictionary = rules(w).get("spin_up", {})
	if spec.is_empty():
		return events
	var label := "Spin-Up: %s" % w.get("name", "")
	if up:
		Weapons.set_profile(w, int(spec.get("profile", 1)))
		w["spun"] = true
		if spec.has("status"):
			events.append_array(Combat.add_status(state, u, String(spec["status"]), label))
	else:
		Weapons.set_profile(w, 0)
		w.erase("spun")
		if spec.has("status") and u.has_status(String(spec["status"])) and u.statuses[String(spec["status"])].get("source", "") == label:
			events.append_array(Combat.remove_status(u, String(spec["status"]), "spun down"))
	events.append({"type": "weapon_profile", "unit": u.id, "weapon": key, "profile": w.get("profile_name", ""), "rule_ref": "weapons: " + String(w.get("name", ""))})
	return events
