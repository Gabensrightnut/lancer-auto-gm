class_name RestActions
extends RefCounted
## Resting (Core p.82): at least an hour of downtime outside combat. The character clears all
## heat and every status and condition on its mech, its pilot regains half their HP and
## clears Down and Out, and it may spend Repairs:
##   1 Repair: full HP, or one destroyed weapon or system
##   2 Repairs: 1 Structure or 1 Stress (Everest Replaceable Parts: 1 per Structure)
##   4 Repairs: a destroyed mech back to 1 Structure, 1 Stress and full HP; anyone may chip in
## Frame traits that act at a rest: Balor Self-Perpetuating (full HP for free), Manticore
## Castigation State (params.castigation), Hydra OROCHI drone choice (params.orochi).

const REF := "Core p.82 Repairs and Rest"


class Rest:
	extends ActionHandler
	## {"type": "rest", "actor": mech or pilot, "params": {"spend": [{"what": "hp" | "structure" |
	## "stress" | "weapon" | "system" | "mech", "key": weapon/system key, "target": wrecked mech,
	## "from": {unit id: Repairs} (others chipping in for a wreck)}], "castigation": bool,
	## "orochi": drone name}}

	func type() -> String:
		return "rest"

	func validate(state: GameState, action: Dictionary) -> RuleResult:
		var u := state.unit(action["actor"])
		var p: Dictionary = action.get("params", {})
		if state.phase == GameState.PHASE_COMBAT:
			return RuleResult.deny("You can only rest outside combat (an hour of downtime).", REF)
		var cost := {}
		for s: Variant in p.get("spend", []):
			if not s is Dictionary:
				return RuleResult.deny("Each spend is {what, ...}.", REF)
			var r := RestActions.check_spend(state, u, s, cost)
			if not r.ok:
				return r
		for id: String in cost:
			var payer := state.unit(id)
			if payer == null or payer.repairs < int(cost[id]):
				return RuleResult.deny("Not enough Repairs (needs %d)." % int(cost[id]), REF)
		if p.has("castigation") and not Effects.has(u, "castigation_state"):
			return RuleResult.deny("Only the Manticore has a Castigation State.", "frames: Manticore")
		if p.has("orochi") and RestActions._drone(u, String(p["orochi"])) == "":
			return RuleResult.deny("Choose one of your OROCHI drones.", "frames: Hydra core system")
		return RuleResult.allow()

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		var u := state.unit(action["actor"])
		var p: Dictionary = action.get("params", {})
		var events: Array[Dictionary] = [{"type": "rested", "unit": u.id, "rule_ref": REF}]
		var mech := u
		var pilot: Unit = null
		if u.kind == Unit.KIND_PILOT:
			pilot = u
			mech = state.unit(String(u.counters.get("mounted_in", ""))) if u.counters.has("mounted_in") else null
		elif u.kind == Unit.KIND_MECH:
			pilot = Pilots.pilot_of(state, u)
		if mech != null and mech.kind == Unit.KIND_MECH:
			mech.counters.erase("briareos_down")
			events.append_array(Combat.clear_heat(mech, "rest"))
			for st: String in mech.statuses.keys():
				events.append_array(Combat.remove_status(mech, st, "rest"))
			mech.burn = 0
			if Effects.has(mech, "self_perpetuating") and not mech.destroyed:
				mech.hp = mech.max_hp  # Balor: full HP without spending Repairs
				events.append({"type": "hp_changed", "unit": mech.id, "hp": mech.hp, "overshield": mech.overshield, "source": "Self-Perpetuating"})
		if pilot != null:
			pilot.hp = mini(pilot.max_hp, pilot.hp + ceili(pilot.max_hp / 2.0))  # half their HP, rounded up
			events.append_array(Combat.remove_status(pilot, "Down and Out", "rest"))
			events.append({"type": "hp_changed", "unit": pilot.id, "hp": pilot.hp, "overshield": pilot.overshield, "source": "rest"})
		for s: Dictionary in p.get("spend", []):
			events.append_array(RestActions.apply_spend(state, u, s))
		if p.has("castigation"):
			u.counters["castigation"] = bool(p["castigation"])
			events.append({"type": "effect_triggered", "unit": u.id, "effect": "Castigation State", "target": u.id, "on": bool(p["castigation"]), "rule_ref": "frames: Manticore"})
		if p.has("orochi"):
			u.counters["orochi"] = String(p["orochi"])
			events.append({"type": "effect_triggered", "unit": u.id, "effect": "OROCHI drone", "target": u.id, "choice": p["orochi"], "rule_ref": "frames: Hydra core system"})
		return events


static func structure_cost(u: Unit) -> int:
	return 1 if Effects.has(u, "replaceable_parts") else 2  # Everest Replaceable Parts


static func check_spend(state: GameState, u: Unit, s: Dictionary, cost: Dictionary) -> RuleResult:
	var add := func(id: String, n: int) -> void:
		cost[id] = int(cost.get(id, 0)) + n
	match String(s.get("what", "")):
		"hp":
			add.call(u.id, 1)
		"limited":
			if not Effects.has(u, "unsanctioned_capacity"):
				return RuleResult.deny("Only with Grease Monkey (Unsanctioned Capacity Upgrade).", "talents: Grease Monkey")
			add.call(u.id, 2)
		"structure":
			if u.structure >= u.max_structure:
				return RuleResult.deny("Structure is already full.", REF)
			add.call(u.id, structure_cost(u))
		"stress":
			if u.stress >= u.max_stress:
				return RuleResult.deny("Stress is already full.", REF)
			add.call(u.id, 2)
		"weapon":
			var w := Weapons.find(u, String(s.get("key", "")))
			if w.is_empty() or not Weapons.state_of(u, w)["destroyed"]:
				return RuleResult.deny("Choose a destroyed weapon.", REF)
			add.call(u.id, 1)
		"system":
			if not Abilities.source_state(u, String(s.get("key", "")))["destroyed"]:
				return RuleResult.deny("Choose a destroyed system.", REF)
			add.call(u.id, 1)
		"mech":
			var t := state.unit(String(s.get("target", "")))
			if t == null or not t.destroyed or t.kind != Unit.KIND_MECH or t.counters.get("vaporized", false):
				return RuleResult.deny("Choose a wrecked mech whose wreckage is still there.", REF)
			var from: Dictionary = s.get("from", {u.id: 4})
			var total := 0
			for id: String in from:
				add.call(id, int(from[id]))
				total += int(from[id])
			if total != 4:
				return RuleResult.deny("Repairing a destroyed mech takes 4 Repairs (anyone may chip in).", REF)
		_:
			return RuleResult.deny("Spend Repairs on: hp, structure, stress, weapon, system or mech.", REF)
	return RuleResult.allow()


static func apply_spend(state: GameState, u: Unit, s: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	match String(s["what"]):
		"hp":
			u.repairs -= 1
			u.hp = u.max_hp
			events.append({"type": "hp_changed", "unit": u.id, "hp": u.hp, "overshield": u.overshield, "source": "rest"})
		"limited":
			# Grease Monkey: 2 Repairs replenish 1 use of every Limited weapon and system.
			u.repairs -= 2
			for w: Dictionary in u.loadout.get("weapons", []):
				if Weapons.has_tag(w, "tg_limited"):
					Weapons.state_of(u, w)["uses"] = int(Weapons.state_of(u, w)["uses"]) + 1
			var seen := {}
			for ab: Dictionary in Abilities.all(u):
				var key := String(ab["source_key"])
				if seen.has(key):
					continue
				seen[key] = true
				var st := Abilities.source_state(u, key)
				if int(st.get("uses", -1)) >= 0:
					st["uses"] = int(st["uses"]) + 1
			events.append({"type": "repaired", "unit": u.id, "what": "limited", "rule_ref": "talents: Grease Monkey"})
		"structure":
			u.repairs -= structure_cost(u)
			u.structure += 1
			events.append({"type": "repaired", "unit": u.id, "what": "structure", "structure": u.structure, "rule_ref": REF})
		"stress":
			u.repairs -= 2
			u.stress += 1
			events.append({"type": "repaired", "unit": u.id, "what": "stress", "stress": u.stress, "rule_ref": REF})
		"weapon":
			u.repairs -= 1
			Weapons.state_of(u, Weapons.find(u, String(s["key"])))["destroyed"] = false
			events.append({"type": "repaired", "unit": u.id, "what": "weapon", "key": s["key"], "rule_ref": REF})
		"system":
			u.repairs -= 1
			Abilities.source_state(u, String(s["key"]))["destroyed"] = false
			(u.counters.get("systems", {}) as Dictionary).erase(String(s["key"]))
			events.append({"type": "repaired", "unit": u.id, "what": "system", "key": s["key"], "rule_ref": REF})
		"mech":
			var t := state.unit(String(s["target"]))
			var from: Dictionary = s.get("from", {u.id: 4})
			for id: String in from:
				state.unit(id).repairs -= int(from[id])
			t.destroyed = false
			t.structure = 1
			t.stress = 1
			t.hp = t.max_hp
			events.append({"type": "revived", "unit": t.id, "by": u.id, "rule_ref": REF})
	return events


static func _drone(u: Unit, name: String) -> String:
	for a: Dictionary in Abilities.all(u):
		if a.get("kind", "") == "deploy" and String(a.get("deployable", {}).get("name", "")) == name:
			return name
	return ""
