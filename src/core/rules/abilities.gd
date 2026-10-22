class_name Abilities
extends RefCounted
## Activated abilities: actions from systems, core systems, frame traits, talents and weapons
## (lancer-data "actions"), plus deploying and recalling deployables and drones. UnitFactory
## copies them into Unit.loadout["abilities"]; the "activate" action uses them.
##
## An ability is {"key", "name", "source_key", "source_name", "kind": "action" | "deploy" |
## "recall", "activation", "frequency", "detail", "range", "deployable", "ops", "automated"}.
##
## Book rules (Core p.61, 68, 71, 73; tags.json): Quick/Full actions; you can Activate any
## number of times a turn but not the same system twice unless free; Protocols only at the
## start of your turn, once each; Quick Tech options differ each time; Jammed characters can't
## take tech actions; Limited N charges (+1 per 2 Engineering) until a Full Repair; X/turn,
## X/round (from the start of your turn to the start of the next), 1/scene; Recharge X+ (NPCs:
## roll 1d6 at the start of the turn); a destroyed system can't be used. Deployables: adjacent
## free space, 5 Evasion, 10 HP per Size; Drones: Size 1/2, 10 Evasion, 5 HP, deployed within
## Sensors and line of sight, recalled with the same action; Mines: adjacent, not next to
## another mine, armed at the end of your turn, triggered when a character enters an adjacent
## space, Hidden (tags: Deployable, Drone, Mine).
## Effects of an ability are applied only where data/game/activation_effects.json encodes them
## ("ops"); otherwise activating spends the action and uses and tells the table what it does.

const REF := "Core p.71 Activate"
const COSTS := {"Quick": "quick", "Full": "full", "Protocol": "free", "Free": "free",
	"Quick Tech": "quick", "Full Tech": "full", "Invade": "quick"}
const TECH := ["Quick Tech", "Full Tech", "Invade"]


static func all(u: Unit) -> Array:
	return u.loadout.get("abilities", [])


static func find(u: Unit, key: String) -> Dictionary:
	for a: Dictionary in all(u):
		if a.get("key", "") == key:
			return a
	return {}


## Per-battle state of a source (system, talent...): charges left and destroyed flag.
static func source_state(u: Unit, source_key: String) -> Dictionary:
	if not u.counters.has("sources"):
		u.counters["sources"] = {}
	var all_states: Dictionary = u.counters["sources"]
	if not all_states.has(source_key):
		all_states[source_key] = {"uses": max_uses(u, source_key), "destroyed": false}
	return all_states[source_key]


## Limited N (+1 per 2 Engineering, Core p.34) for a system; -1 = unlimited.
static func max_uses(u: Unit, source_key: String) -> int:
	for s: Dictionary in u.loadout.get("systems", []):
		if s.get("key", "") == source_key and Weapons.has_tag(s, "tg_limited"):
			return Weapons.tag_value(s, "tg_limited") + u.engineering / 2
	return -1


## "1/round" -> {"count": 1, "per": "round"}; "" -> {}.
static func frequency_of(a: Dictionary) -> Dictionary:
	var f := String(a.get("frequency", ""))
	var m := RegEx.create_from_string("(\\d+)\\s*/\\s*(turn|round|scene|mission)").search(f.to_lower())
	if m == null:
		return {}
	return {"count": int(m.get_string(1)), "per": m.get_string(2)}


static func _times_used(u: Unit, key: String, per: String) -> int:
	match per:
		"turn":
			return int(u.turn.get("ability_uses", {}).get(key, 0))
		"round":
			return int(u.counters.get("ability_round_uses", {}).get(key, 0))
	return int(u.counters.get("ability_scene_uses", {}).get(key, 0))


static func _count_use(u: Unit, key: String, per: String) -> void:
	var where := "ability_scene_uses"
	if per == "turn":
		var t: Dictionary = u.turn.get("ability_uses", {})
		t[key] = int(t.get(key, 0)) + 1
		u.turn["ability_uses"] = t
		return
	if per == "round":
		where = "ability_round_uses"
	var d: Dictionary = u.counters.get(where, {})
	d[key] = int(d.get(key, 0)) + 1
	u.counters[where] = d


## Can `u` activate ability `a` right now, ignoring targets? Returns RuleResult.
static func can_activate(state: GameState, u: Unit, a: Dictionary) -> RuleResult:
	if a.is_empty():
		return RuleResult.deny("No such ability.", REF)
	var act := String(a.get("activation", ""))
	if act == "Reaction":
		return RuleResult.deny("%s is a reaction: it's offered when its trigger happens." % a["name"], "Core p.73 Reactions")
	if not COSTS.has(act) and a.get("kind", "action") == "action":
		return RuleResult.deny("%s is always on; there's nothing to activate." % a["name"], REF)
	var src := source_state(u, String(a["source_key"]))
	if src["destroyed"]:
		return RuleResult.deny("%s has been destroyed." % a.get("source_name", "That system"), "Core p.80 System Trauma")
	if TECH.has(act) and u.has_status("Jammed"):
		return RuleResult.deny("Jammed: you can't take tech actions.", "Core p.78 Jammed")
	var limited := int(src["uses"])
	if limited == 0 and a.get("kind", "action") != "recall":
		return RuleResult.deny("%s is out of charges until a Full Repair." % a.get("source_name", "That system"), "tags: Limited")
	if not src.get("charged", true):
		return RuleResult.deny("%s is recharging (Recharge %d+)." % [a.get("source_name", ""), int(src.get("recharge", 6))], "tags: Recharge")
	if a.get("orochi", false) and not u.counters.get("core_active", false) and String(a.get("deployable", {}).get("name", "")) != orochi_choice(u):
		return RuleResult.deny("Only your chosen OROCHI drone (%s) until Full Deployment." % orochi_choice(u), "frames: Hydra core system")
	var f := frequency_of(a)
	for e: Dictionary in Effects.of(u, "frequency_override"):
		if String(e.get("ability", "")) == String(a.get("name", "")) and not f.is_empty():
			f["count"] = int(e.get("count", f["count"]))  # Pegasus Unshackle Ushabti: 3/round
	if not f.is_empty() and _times_used(u, String(a["key"]), f["per"]) >= int(f["count"]):
		return RuleResult.deny("%s can only be used %s." % [a["name"], a["frequency"]], "Core p.60 (1/round, 1/turn...)")
	if act == "Protocol" and (u.turn.get("acted", false) or u.turn.get("moved", false)):
		return RuleResult.deny("Protocols can only be activated at the start of your turn.", "Core p.73 Protocol")
	if act == "Quick Tech" and (u.turn.get("quick_tech", []) as Array).has(String(a["key"])) and int(u.turn.get("free_quick", 0)) <= 0:
		return RuleResult.deny("Pick a different Quick Tech option: each once per turn.", "Core p.69 Quick Tech")
	return RuleResult.allow()


## Heat (Self) of the system an ability comes from (tags: Heat X (Self)); dice are rolled.
static func heat_self(state: GameState, u: Unit, a: Dictionary) -> int:
	for s: Dictionary in u.loadout.get("systems", []):
		if String(s.get("key", "")) != String(a.get("source_key", "")):
			continue
		for t: Dictionary in s.get("tags", []):
			if t.get("id", "") == "tg_heat_self":
				var v := str(t.get("val", 1))
				return int(state.dice.roll(v)["total"]) if "d" in v else int(v)
	return 0


## Hydra: the OROCHI drone that accompanies it (chosen at creation or a rest).
static func orochi_choice(u: Unit) -> String:
	if u.counters.has("orochi"):
		return String(u.counters["orochi"])
	if u.loadout.has("orochi"):
		return String(u.loadout["orochi"])
	for a: Dictionary in all(u):
		if a.get("orochi", false):
			return String(a.get("deployable", {}).get("name", ""))
	return ""


## The economy cost of an ability ("quick", "full", "free").
static func cost_of(a: Dictionary) -> String:
	var act := String(a.get("activation", "Quick"))
	return String(COSTS.get(act, "quick"))


## The name the turn records (Activate: once per system per turn unless free, Core p.71).
static func economy_name(a: Dictionary) -> String:
	if String(a.get("activation", "")) in ["Quick Tech", "Invade"]:
		return "quick_tech"
	return "activate:" + String(a["source_key"])


static func spend(state: GameState, u: Unit, a: Dictionary) -> void:
	var src := source_state(u, String(a["source_key"]))
	if int(src["uses"]) > 0 and a.get("kind", "action") != "recall":
		src["uses"] = int(src["uses"]) - 1
	if src.has("recharge"):
		src["charged"] = false
	var f := frequency_of(a)
	if not f.is_empty():
		_count_use(u, String(a["key"]), f["per"])
	if String(a.get("activation", "")) in ["Quick Tech", "Invade"]:
		var used: Array = u.turn.get("quick_tech", [])
		used.append(String(a["key"]))
		u.turn["quick_tech"] = used


## NPC Recharge: at the start of the NPC's turn roll 1d6 once; everything with Recharge X+
## where X <= roll is ready again (tags: Recharge).
static func recharge_roll(state: GameState, u: Unit) -> Array[Dictionary]:
	var waiting: Array = []
	for key: String in u.counters.get("sources", {}):
		var st: Dictionary = u.counters["sources"][key]
		if st.has("recharge") and not st.get("charged", true):
			waiting.append(key)
	for w: Dictionary in u.loadout.get("weapons", []):
		var ws := Weapons.state_of(u, w)
		if ws.has("recharge") and not ws.get("charged", true):
			waiting.append("w:" + String(w["key"]))
	if waiting.is_empty():
		return [] as Array[Dictionary]
	var roll := state.dice.die(6)
	var ready: Array = []
	for key: String in waiting:
		var st: Dictionary
		if key.begins_with("w:"):
			st = Weapons.state_of(u, Weapons.find(u, key.substr(2)))
		else:
			st = u.counters["sources"][key]
		if roll >= int(st["recharge"]):
			st["charged"] = true
			ready.append(key)
	return [{"type": "recharge_roll", "unit": u.id, "roll": roll, "ready": ready, "rule_ref": "tags: Recharge"}] as Array[Dictionary]


## Ends temporary self effects whose time is up (`when`: "start" or "end" of `u`'s turn).
static func expire(state: GameState, u: Unit, when: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for owner: Unit in state.units.values():
		var active: Array = owner.counters.get("active_effects", [])
		var keep: Array = []
		for e: Dictionary in active:
			var exp: Dictionary = e.get("expires", {})
			if exp.is_empty() or exp.get("unit", "") != u.id or exp.get("when", "") != when:
				keep.append(e)
				continue
			exp["count"] = int(exp.get("count", 1)) - 1
			if int(exp["count"]) > 0:
				keep.append(e)
			else:
				events.append({"type": "effect_ended", "unit": owner.id, "effect": e.get("label", "")})
		owner.counters["active_effects"] = keep
	return events


# --- Deployables ----------------------------------------------------------------------

## Defaults by type (tags: Deployable, Drone).
static func deploy_stats(owner: Unit, d: Dictionary) -> Dictionary:
	var type := String(d.get("type", "Deployable"))
	var drone := type == "Drone"
	var size := float(d.get("size", 0.5 if drone or type == "Mine" else 1.0))
	var bonus := Effects.value(owner, "deployable_hp_bonus") if (drone or type == "Deployable") else 0  # Hydra System Link
	return {
		"size": size,
		"hp": _stat(owner, d.get("hp"), 5 if drone else 10 * maxi(1, int(size))) + bonus,
		"evasion": _stat(owner, d.get("evasion"), 10 if drone else 5),
		"edef": _stat(owner, d.get("edef"), 10 if drone else 0),
		"armor": _stat(owner, d.get("armor"), 0),
		"speed": _stat(owner, d.get("speed"), 0),
	}


## Numbers or lancer-data formulas like "5 + {grit}" or "{evasion}".
static func _stat(owner: Unit, v: Variant, fallback: int) -> int:
	if v == null:
		return fallback
	if v is int or v is float:
		return int(v)
	var text := String(v)
	for k in ["grit", "evasion", "edef", "speed", "sensors", "tech_attack", "save_target", "hp", "armor"]:
		text = text.replace("{%s}" % k, str(int(owner.get(k))))
	text = text.replace("{save}", str(owner.save_target))
	var expr := Expression.new()
	if expr.parse(text) != OK:
		return fallback
	var r: Variant = expr.execute()
	return int(r) if r != null else fallback


## Where a deployable can go (tags: Deployable, Drone, Mine; or the deployable's own Range).
static func check_spot(state: GameState, owner: Unit, d: Dictionary, cell: Vector2i) -> RuleResult:
	var stats := deploy_stats(owner, d)
	var type := String(d.get("type", "Deployable"))
	var lv := state.map.ground_height(cell)
	var place := Movement.placement(state, stats["size"], cell, lv)
	if not place["ok"] or not place["standing"]:
		return RuleResult.deny("Can't place it there: %s" % place.get("reason", "no ground"), REF)
	var body := Sight.make_body(state, cell, lv, stats["size"])
	for o: Unit in state.units.values():
		if Combat.is_present(o) and Movement._overlaps(body, Sight.body_of(state, o)):
			return RuleResult.deny("That space isn't free.", REF)
	var me := Sight.body_of(state, owner)
	var reach := Weapons.range_value(d, "Range")
	if type == "Mine":
		reach = maxi(reach, FrameSystems.mine_reach(state, owner))  # Iskander Assault Launcher
	var dist := Sight.distance(state, me, body)
	if type == "Drone" and reach == 0:
		if dist > owner.sensors or not Sight.line_of_sight(state, me, body):
			return RuleResult.deny("Drones deploy within Sensors and line of sight.", "tags: Drone")
	elif reach > 0:
		if dist > reach or not Sight.line_of_sight(state, me, body):
			return RuleResult.deny("Deploy within Range %d and line of sight." % reach, REF)
	elif dist > 1:
		return RuleResult.deny("Deploy it in an adjacent space.", "tags: Deployable")
	if type == "Mine":
		for o: Unit in state.units.values():
			if o.counters.get("deploy_type", "") == "Mine" and not o.destroyed and Sight.distance(state, body, Sight.body_of(state, o)) <= 1:
				return RuleResult.deny("Mines can't be planted next to another mine.", "tags: Mine")
	return RuleResult.allow()


static func deploy(state: GameState, owner: Unit, a: Dictionary, cell: Vector2i) -> Array[Dictionary]:
	var d: Dictionary = a["deployable"]
	if d.has("zone"):
		return Zones.from_deployable(state, owner, d, cell)  # an area, not an object
	var stats := deploy_stats(owner, d)
	var n := int(owner.counters.get("deployed_count", 0)) + 1
	owner.counters["deployed_count"] = n
	var u := Unit.new()
	u.id = "%s_dep%d" % [owner.id, n]
	u.name = String(d.get("name", "Deployable"))
	u.kind = Unit.KIND_DEPLOYABLE
	u.side = owner.side
	u.controller = owner.controller
	u.size = stats["size"]
	u.cell = cell
	u.level = state.map.ground_height(cell)
	u.max_hp = stats["hp"]
	u.hp = u.max_hp
	u.evasion = stats["evasion"]
	u.edef = stats["edef"]
	u.armor = stats["armor"]
	u.speed = stats["speed"]
	u.heat_cap = 0
	u.max_structure = 0
	u.structure = 0
	u.max_stress = 0
	u.stress = 0
	u.counters = {"owner": owner.id, "ability": a["key"], "deploy_type": d.get("type", "Deployable"),
		"turret": d.get("turret", false), "trigger": d.get("trigger", ""),
		"pattern": (d.get("range", []) as Array).duplicate(true), "damage": (d.get("damage", []) as Array).duplicate(true),
		"text": d.get("detail", "")}
	u.loadout = {"weapons": [], "systems": [], "effects": []}
	var events: Array[Dictionary] = []
	state.add_unit(u)
	if d.has("anchored_zone"):
		var spec: Dictionary = d["anchored_zone"]
		events.append_array(Zones.add(state, {"kind": spec["kind"], "owner": owner.id, "anchor": u.id, "radius": int(spec.get("radius", 1)),
			"label": u.name, "cells": [], "center": [cell.x, cell.y], "rule_ref": "systems: " + u.name}))
	if d.has("zone_size"):
		u.counters["zone_size"] = int(d["zone_size"])
	if d.has("aegis_dice"):
		u.counters["aegis_dice"] = int(d["aegis_dice"])
	if d.get("snare", false):
		u.counters["snare"] = true  # Webjaw Snare: hidden, armed at the end of the turn
		u.counters["armed"] = false
		u.statuses["Hidden"] = {"source": owner.id}
	if d.has("aura"):
		u.counters["aura"] = String(d["aura"])  # ICEOUT Drone, Lotus Projector, Sentinel Drone
	if d.has("fail_status"):
		u.counters["fail_status"] = (d["fail_status"] as Dictionary).duplicate()  # Mesmer Mine
	if d.has("interact"):
		u.counters["interact"] = (d["interact"] as Array).duplicate(true)
	if not u.counters["turret"]:
		u.counters.erase("turret")
	if u.counters["trigger"] == "":
		u.counters.erase("trigger")
	if u.counters["deploy_type"] == "Mine":
		u.statuses["Hidden"] = {"source": owner.id}  # undetected mines are Hidden (tags: Mine)
		u.counters["armed"] = false
		if Sight.unit_distance(state, owner, u) > maxi(1, Weapons.range_value(d, "Range")) and FrameSystems.mine_reach(state, owner) > 0:
			owner.counters["launcher_round"] = state.round_number
	events.append({"type": "deployed", "unit": owner.id, "object": {"id": u.id, "kind": String(u.counters["deploy_type"]).to_lower(),
		"name": u.name, "cells": [[cell.x, cell.y, u.level]], "height": GridLayout.spaces_per_side(u.size), "hp": u.hp}, "rule_ref": REF})
	return events


static func recall(state: GameState, owner: Unit, a: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var target := String(a.get("recalls", ""))
	for id: String in state.units.keys():
		var u: Unit = state.units[id]
		if u.kind == Unit.KIND_DEPLOYABLE and u.counters.get("owner", "") == owner.id and u.counters.get("ability", "") == target and not u.destroyed:
			state.units.erase(id)
			events.append({"type": "recalled", "unit": owner.id, "object": id})
	return events


## Mines arm at the end of their owner's turn (tags: Mine).
static func arm_mines(state: GameState, owner: Unit) -> void:
	for sn: Unit in state.units.values():
		if sn.counters.get("snare", false) and sn.counters.get("owner", "") == owner.id:
			sn.counters["armed"] = true
	for u: Unit in state.units.values():
		if u.counters.get("deploy_type", "") == "Mine" and u.counters.get("owner", "") == owner.id:
			u.counters["armed"] = true


## A character moved through `path`: armed mines next to a space it entered go off (tags: Mine).
## PROVISIONAL (RULES_TODO "Mines"): the mine goes off after the move resolves.
static func check_mines(state: GameState, mover: Unit, path: Array) -> Array[Dictionary]:
	var events: Array[Dictionary] = GearSystems.check_snares(state, mover, path)
	if mover.kind == Unit.KIND_DEPLOYABLE or Effects.has(mover, "mine_immune"):
		return events  # Iskander Skeleton Key: never sets off mines unless it chooses to
	for m: Unit in state.units.values():
		if m.destroyed or m.counters.get("deploy_type", "") != "Mine" or not m.counters.get("armed", false):
			continue
		if m.counters.get("trigger", "") == "ally" and mover.side != m.side:
			continue  # Smoke Mine: only allied characters set it off
		if m.counters.get("trigger", "") == "manual":
			continue  # Breaching Charge: detonated with a quick action
		var mb := Sight.body_of(state, m)
		var was_adjacent := true
		for i in range(path.size()):
			var p: Array = path[i]
			var body := Sight.make_body(state, Vector2i(p[0], p[1]), int(p[2]), mover.size)
			var adjacent := Sight.distance(state, body, mb) <= 1
			if adjacent and (i > 0 and not was_adjacent):
				events.append_array(detonate(state, m, mover))
				break
			was_adjacent = adjacent
	return events


## A mine creates a Burst attack from its space (tags: Mine). lancer-data gives the damage and
## save for most mines: everyone in the pattern saves against the owner's Save Target.
static func detonate(state: GameState, m: Unit, trigger: Unit) -> Array[Dictionary]:
	var owner := state.unit(String(m.counters.get("owner", "")))
	var events: Array[Dictionary] = [{"type": "mine_triggered", "mine": m.id, "unit": trigger.id, "text": m.counters.get("text", ""), "rule_ref": "tags: Mine"}]
	var radius := 1
	for r: Dictionary in m.counters.get("pattern", []):
		if r.get("type", "") == "Burst":
			radius = int(r.get("val", 1))
	var center := Sight.body_of(state, m)
	m.destroyed = true
	var fs: Dictionary = m.counters.get("fail_status", {})
	if not fs.is_empty() and owner != null:
		var r := int(fs.get("burst", 1))
		var ids: Array = state.units.keys()
		ids.sort()
		for id: String in ids:
			var o := state.unit(id)
			if o == m or not Combat.is_present(o) or o.kind == Unit.KIND_DEPLOYABLE or Sight.distance(state, center, Sight.body_of(state, o)) > r:
				continue
			var save := Combat.skill_check(state, o, String(fs.get("save", "systems")), "Save vs %s" % m.name, owner.save_target, 0, 0, [], true)
			events.append({"type": "skill_check", "unit": o.id, "check": save, "rule_ref": "tags: Mine"})
			if not save["success"]:
				events.append_array(Combat.add_status(state, o, String(fs["status"]), owner.id, o.id))
		return events
	if m.counters.has("zone_size"):
		events.append_array(GearSystems.smoke_mine(state, m, trigger))
		return events
	var damage: Array = m.counters.get("damage", [])
	if damage.is_empty() or owner == null:
		events.append({"type": "manual_effect", "source": m.name, "text": m.counters.get("text", "")})
		return events
	var skill_of := {"agi": "agility", "hull": "hull", "sys": "systems", "eng": "engineering"}
	var hit: Array = []
	for u: Unit in state.units.values():
		if u != m and Combat.is_present(u) and u.kind != Unit.KIND_DEPLOYABLE and Sight.distance(state, center, Sight.body_of(state, u)) <= radius:
			hit.append(u)
	for d: Dictionary in damage:
		var roll := state.dice.roll(str(d.get("val", "0")))
		for u: Unit in hit:
			var amount := int(roll["total"])
			if d.has("save"):
				var save := Combat.skill_check(state, u, String(skill_of.get(d["save"], "agility")), "Save vs %s" % m.name, owner.save_target, 0, 0, [], true)
				events.append({"type": "skill_check", "unit": u.id, "check": save, "rule_ref": "tags: Mine"})
				if save["success"]:
					amount = amount - amount / 2 if d.get("save_half", false) else 0
					if d.get("save_half", false) and Effects.has(u, "heavy_shielding"):
						amount = mini(amount, 1)
			if amount > 0:
				events.append_array(Combat.deal_damage(state, u, [{"type": d.get("type", "Kinetic"), "amount": amount}], {"source": owner.id, "ap": d.get("ap", false), "area": true}))
	return events
