class_name FrameSystems
extends RefCounted
## Core systems and traits that keep their own state or targets (data in
## data/game/frame_effects.json: "core" effects, "core_target", "core_ops", "core_passive",
## "core_actions"). Effect kinds handled here:
##   start_turn_heat {value}      heat at the start of each of its turns (Lancaster Supercharger)
##   soft_cover_aura {self_only?} it (and adjacent allies) count as in soft cover (Balor Hive
##                                Frenzy; Sherman Vent Heat: self only)
##   always_hard_cover            hard cover even in the open (Drake Fortress)
##   immovable                    immune to knockback, pulls and other involuntary movement
##   fortress_brace               after Bracing, a full action next turn instead of a quick one
##   frenzy_structure             before structure damage roll 1d6: on 6, none, back to 1 HP and
##                                immune to damage until the end of the turn (Balor)
##   aegis                        Napoleon Trueblack Aegis (damage to 1, no tech, limited actions)
##   charge_die {burst, damage, save}  Manticore core: +1 per heat or energy taken; at 6, burst
##   heat_lash {damage, range}    Manticore: 1/round when it takes heat, energy to a character
##   coreburn                     Sherman: Stabilize gives 2 ZF4 charges; objects take 10 AP per charge
##   apocalypse                   Barbarossa Apocalypse Die (counters.apocalypse)
##   assault_launcher {range}     Iskander: 1/round, plant a mine as though it had that range
##   mine_deployers               Iskander: 1/round, two more mines next to it for free

const ZF4 := "mw_sherman_integrated"
const RAIL := "mw_barbarossa_integrated"
## Napoleon's Aegis allows only these actions (plus free actions, protocols and Shield systems).
const AEGIS_ALLOWED := ["move", "boost", "grapple", "ram", "improvised_attack", "activate", "end_turn",
	"start_turn", "end_grapple", "break_free", "stand_up", "set_reaction_policy", "set_ruling", "react"]


static func _sorted(state: GameState) -> Array[Unit]:
	var out: Array[Unit] = []
	var ids: Array = state.units.keys()
	ids.sort()
	for id: String in ids:
		out.append(state.unit(id))
	return out


# --- Core targets ---------------------------------------------------------------------

## The core's target spec: {who: ally|other, range: n|"sensors", mech?, los?, counter?,
## effects? (put on the target while linked), ops? (maze), ends_on_stun?}.
static func target_spec(u: Unit) -> Dictionary:
	return u.loadout.get("core", {}).get("target", {})


static func check_target(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
	var spec := target_spec(u)
	if spec.is_empty():
		return RuleResult.allow()
	var ref := "frames: %s core system" % u.loadout.get("core", {}).get("name", "")
	var t := state.unit(String(params.get("target", "")))
	if t == null or not Combat.is_present(t) or t == u or t.kind == Unit.KIND_DEPLOYABLE:
		return RuleResult.deny("Choose a target character (params.target).", ref)
	if spec.get("who", "other") == "ally" and t.side != u.side:
		return RuleResult.deny("Choose an allied character.", ref)
	if spec.get("mech", false) and t.kind != Unit.KIND_MECH:
		return RuleResult.deny("Choose a mech.", ref)
	var reach: int = u.sensors if str(spec.get("range", "sensors")) == "sensors" else int(spec["range"])
	if Sight.unit_distance(state, u, t) > reach:
		return RuleResult.deny("It must be within range %d." % reach, ref)
	if spec.get("los", false) and not Sight.unit_line_of_sight(state, u, t):
		return RuleResult.deny("No line of sight to the target.", Sight.REF_LOS)
	return RuleResult.allow()


static func apply_target(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var spec := target_spec(u)
	var t := state.unit(String(params.get("target", "")))
	if spec.is_empty() or t == null:
		return events
	var label := String(u.loadout["core"].get("name", ""))
	if spec.has("counter"):
		u.counters[String(spec["counter"])] = t.id
	if spec.has("effects"):
		var active: Array = t.counters.get("active_effects", [])
		for e: Dictionary in spec["effects"]:
			var c := e.duplicate(true)
			c["label"] = label
			c["link"] = u.id
			active.append(c)
		t.counters["active_effects"] = active
		u.counters["core_link"] = {"target": t.id, "label": label, "ends_on_stun": spec.get("ends_on_stun", false)}
	for op: Dictionary in spec.get("ops", []):
		if op.get("op", "") == "maze":
			# Minotaur Metafold Maze: Stunned; Systems save at +3 Difficulty at the end of each of
			# its turns, +1 Accuracy per failed try.
			events.append_array(Combat.add_status(state, t, "Stunned", label))
			t.counters["maze"] = {"by": u.id, "tries": 0, "save_target": u.save_target, "label": label}
	events.append({"type": "effect_triggered", "unit": u.id, "effect": label, "target": t.id, "rule_ref": "frames: core_system"})
	return events


static func end_link(state: GameState, u: Unit, why: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var link: Dictionary = u.counters.get("core_link", {})
	if link.is_empty():
		return events
	u.counters.erase("core_link")
	var t := state.unit(String(link["target"]))
	if t != null:
		t.counters["active_effects"] = (t.counters.get("active_effects", []) as Array).filter(func(e: Dictionary) -> bool: return e.get("link", "") != u.id)
	u.counters["active_effects"] = (u.counters.get("active_effects", []) as Array).filter(func(e: Dictionary) -> bool: return e.get("label", "") != link["label"])
	events.append({"type": "effect_ended", "unit": u.id, "effect": link["label"], "reason": why})
	return events


## After a status is added to `u` (called by Combat.add_status).
static func on_status(state: GameState, u: Unit, status: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if status == "Stunned":
		# Lancaster Supercharger ends if either character becomes Stunned.
		for x: Unit in _sorted(state):
			var link: Dictionary = x.counters.get("core_link", {})
			if link.get("ends_on_stun", false) and (x == u or String(link.get("target", "")) == u.id):
				events.append_array(end_link(state, x, "Stunned"))
	if (status == "Stunned" or status == "Jammed") and u.counters.has("apocalypse"):
		u.counters["apocalypse_reset"] = true
	return events


# --- Core power hooks -----------------------------------------------------------------

static func on_core(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var core: Dictionary = u.loadout.get("core", {})
	events.append_array(apply_target(state, u, params))
	for e: Dictionary in core.get("effects", []):
		match String(e.get("kind", "")):
			"aegis":
				# Any current tech effects or conditions end.
				for s: String in u.statuses.keys():
					if s == "Lock On" or String(u.statuses[s].get("source", "")) == "Fragment Signal":
						events.append_array(Combat.remove_status(u, s, "Trueblack Aegis"))
			"charge_die":
				u.counters["charge_die"] = 1
			"coreburn":
				events.append_array(set_charges(u, zf4_charges(u) + 3))
			"apocalypse":
				u.counters["apocalypse"] = 4
				u.counters["apocalypse_at"] = [u.cell.x, u.cell.y, u.level]
				events.append_array(_rail_profile(u))
	if core.has("sections"):
		events.append_array(_fortress_sections(state, u, params))
	return events


## Drake Fortress: two Line 2 sections of hard cover from the mech, Immunity to all damage.
## params.sections: [[[x, y], [x, y]], ...] (up to two; first space adjacent to the mech).
static func check_sections(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
	var secs: Variant = params.get("sections", [])
	if not secs is Array or (secs as Array).size() > 2:
		return RuleResult.deny("Up to two cover sections (params.sections), each two spaces in a line.", "frames: Drake core system")
	var me := Sight.body_of(state, u)
	var used := {}
	for sec: Variant in secs:
		if not sec is Array or (sec as Array).size() != 2:
			return RuleResult.deny("Each section is two spaces in a line.", "frames: Drake core system")
		var a := Vector2i(int(sec[0][0]), int(sec[0][1]))
		var b := Vector2i(int(sec[1][0]), int(sec[1][1]))
		if Sight.distance(state, me, Sight.make_body(state, a, state.map.ground_height(a), 1.0)) > 1 or state.map.grid.distance(a, b) != 1:
			return RuleResult.deny("Sections unfold from the mech: the first space adjacent to it, the second next to the first.", "frames: Drake core system")
		for c: Vector2i in [a, b]:
			if used.has(c):
				return RuleResult.deny("Sections can't overlap.", "frames: Drake core system")
			used[c] = true
			var ok := Abilities.check_spot(state, u, {"type": "Deployable", "size": 1, "range": [{"type": "Range", "val": 3}]}, c)
			if not ok.ok:
				return ok
	return RuleResult.allow()


static func _fortress_sections(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var a := {"key": "core/fortress", "deployable": {"name": "Fortress cover", "type": "Deployable", "size": 1, "hp": 10}}
	for sec: Array in params.get("sections", []):
		for c: Array in sec:
			events.append_array(Abilities.deploy(state, u, a, Vector2i(int(c[0]), int(c[1]))))
			var obj := state.unit(String(events.back()["object"]["id"]))
			obj.loadout["effects"] = [{"kind": "immune", "damage": "All", "label": "Fortress"}]
	return events


## "core_off" (Drake Fortress deactivated as a protocol): the core's effects, statuses and
## deployed pieces go away.
static func core_off(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var label := String(u.loadout.get("core", {}).get("name", ""))
	u.counters["active_effects"] = (u.counters.get("active_effects", []) as Array).filter(func(e: Dictionary) -> bool: return e.get("label", "") != label)
	for s: String in u.statuses.keys():
		if String(u.statuses[s].get("source", "")) == label:
			events.append_array(Combat.remove_status(u, s, "deactivated"))
	for id: String in state.units.keys():
		var o: Unit = state.units[id]
		if o.kind == Unit.KIND_DEPLOYABLE and o.counters.get("owner", "") == u.id and String(o.counters.get("ability", "")) == "core/fortress":
			state.units.erase(id)
			events.append({"type": "recalled", "unit": u.id, "object": id})
	u.counters["core_active"] = false
	events.append({"type": "effect_ended", "unit": u.id, "effect": label, "reason": "deactivated"})
	return events


# --- Action limits --------------------------------------------------------------------

## Limits on what `u` may do from frame systems (Napoleon Aegis, Barbarossa after firing).
static func action_allowed(state: GameState, u: Unit, type: String) -> RuleResult:
	if u.turn.get("rail_fired", false) and state.active_unit == u.id and not type in ["end_turn", "react", "set_reaction_policy", "set_ruling"]:
		return RuleResult.deny("After firing the Apocalypse Rail you can't move or take any other actions this turn.", "frames: Barbarossa core system")
	if Effects.has(u, "aegis") and not AEGIS_ALLOWED.has(type):
		var h: Variant = RulesEngine.registry.get(type)
		if h is TurnAction and (h as TurnAction).cost() in [TurnRules.QUICK, TurnRules.FULL]:
			return RuleResult.deny("Inside the Trueblack Aegis you can only move, Boost, Grapple, Ram, make Improvised Attacks, make skill checks and activate Shield systems.", "frames: Napoleon core system")
		if type == "overcharge":
			return RuleResult.deny("Inside the Trueblack Aegis you can't Overcharge.", "frames: Napoleon core system")
	return RuleResult.allow()


# --- Cover ----------------------------------------------------------------------------

## Cover that comes from frame systems rather than terrain.
static func extra_cover(state: GameState, target: Unit, cover: Dictionary) -> Dictionary:
	if cover.get("cover", "none") == "hard":
		return cover
	var give := ""
	if Effects.has(target, "always_hard_cover"):
		give = "hard"
	elif cover.get("cover", "none") == "none":
		if Effects.has(target, "soft_cover_aura"):
			give = "soft"
		else:
			for o: Unit in state.units.values():
				if o != target and o.side == target.side and Combat.is_present(o) and Sight.unit_distance(state, o, target) <= 1:
					for e: Dictionary in Effects.of(o, "soft_cover_aura"):
						if not e.get("self_only", false):
							give = "soft"
	if give == "":
		return cover
	var c := cover.duplicate()
	c["cover"] = give
	c["difficulty"] = 2 if give == "hard" else 1
	c["from_system"] = true
	return c


# --- Turn hooks -----------------------------------------------------------------------

static func turn_started(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for e: Dictionary in Effects.of(u, "start_turn_heat"):
		events.append_array(Combat.apply_heat(state, u, int(e.get("value", 1)), String(e.get("label", ""))))
	if u.counters.has("apocalypse"):
		var at: Array = u.counters.get("apocalypse_at", [])
		var die := int(u.counters["apocalypse"])
		if u.counters.get("apocalypse_reset", false) or at != [u.cell.x, u.cell.y, u.level]:
			die = 4  # moved (even involuntarily), Stunned or Jammed: the die resets
		u.counters.erase("apocalypse_reset")
		u.counters["apocalypse"] = maxi(1, die - 1)
		u.counters["apocalypse_at"] = [u.cell.x, u.cell.y, u.level]
		events.append({"type": "effect_triggered", "unit": u.id, "effect": "Apocalypse Die", "target": u.id, "value": u.counters["apocalypse"], "rule_ref": "frames: Barbarossa core system"})
		events.append_array(_rail_profile(u))
	return events


static func turn_ending(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var maze: Dictionary = u.counters.get("maze", {})
	if not maze.is_empty():
		var tries := int(maze.get("tries", 0))
		var save := Combat.skill_check(state, u, "systems", "Save vs %s" % maze.get("label", "Maze"), int(maze.get("save_target", 10)), tries, 3, [], true)
		events.append({"type": "skill_check", "unit": u.id, "check": save, "rule_ref": "frames: Minotaur core system"})
		if save["success"]:
			u.counters.erase("maze")
			events.append_array(Combat.remove_status(u, "Stunned", "escaped the Maze"))
		else:
			maze["tries"] = tries + 1
	return events


# --- Damage hooks ---------------------------------------------------------------------

## Balor Hive Frenzy: instead of structure damage, maybe pull itself together.
static func frenzy_saves(state: GameState, u: Unit) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not Effects.has(u, "frenzy_structure"):
		return events
	var roll := state.dice.die(6)
	events.append({"type": "effect_triggered", "unit": u.id, "effect": Effects.of(u, "frenzy_structure")[0].get("label", ""), "target": u.id, "roll": roll, "saved": roll == 6, "rule_ref": "frames: Balor core system"})
	if roll == 6:
		u.hp = 1
		var exp := {"unit": state.active_unit if state.active_unit != "" else u.id, "when": "end", "count": 1}
		var active: Array = u.counters.get("active_effects", [])
		active.append({"kind": "immune", "damage": "All", "label": "Hive Frenzy", "expires": exp})
		u.counters["active_effects"] = active
		events.append({"type": "hp_changed", "unit": u.id, "hp": 1, "overshield": u.overshield, "source": "Hive Frenzy"})
	return events


## `u` took heat (`kind` "heat") or energy damage: Manticore charge die and lash.
static func took_heat_or_energy(state: GameState, u: Unit, kind: String) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if u.destroyed:
		return events
	var cd := Effects.of(u, "charge_die")
	if not cd.is_empty() and u.counters.has("charge_die"):
		u.counters["charge_die"] = int(u.counters["charge_die"]) + 1
		events.append({"type": "effect_triggered", "unit": u.id, "effect": "Charge Die", "target": u.id, "value": u.counters["charge_die"], "rule_ref": "frames: Manticore core system"})
		if int(u.counters["charge_die"]) >= 6:
			events.append_array(_discharge(state, u, cd[0]))
	if kind == "heat":
		for e: Dictionary in Effects.of(u, "heat_lash"):
			if int(u.counters.get("lash_round", -1)) == state.round_number:
				break
			var ids: Array = []
			var best := ""
			for o: Unit in _sorted(state):
				if o != u and Combat.is_present(o) and o.kind != Unit.KIND_DEPLOYABLE and Sight.unit_distance(state, u, o) <= int(e.get("range", 3)):
					ids.append(o.id)
					if best == "" and o.side != u.side:
						best = o.id
			if ids.is_empty():
				break
			var auto := {"take": best != "", "target": best}
			var d := Reactions.offer(state, u, "heat_lash", {"targets": ids, "suggested": auto}, auto)
			var t := state.unit(String(d.get("target", "")))
			if d.get("take", false) and t != null and ids.has(t.id):
				u.counters["lash_round"] = state.round_number
				events.append({"type": "effect_triggered", "unit": u.id, "effect": e.get("label", ""), "target": t.id, "rule_ref": "frames: Manticore core system"})
				events.append_array(Combat.deal_damage(state, t, [{"type": "Energy", "amount": int(e.get("damage", 2))}], {"ap": true, "source": u.id}))
			break
	return events


static func _discharge(state: GameState, u: Unit, e: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	u.counters.erase("charge_die")
	var label := String(e.get("label", ""))
	u.counters["active_effects"] = (u.counters.get("active_effects", []) as Array).filter(func(x: Dictionary) -> bool: return x.get("label", "") != label)
	events.append({"type": "effect_ended", "unit": u.id, "effect": label, "reason": "discharged"})
	var ids: Array = []
	var burst := int(e.get("burst", 2))
	var me_too := Rulings.ask(state, "manticore_inferno_self") == "includes"
	for o: Unit in _sorted(state):
		if Combat.is_present(o) and (o != u or me_too) and Sight.unit_distance(state, u, o) <= burst:
			ids.append(o.id)
	var op := {"op": "save_damage", "save": String(e.get("save", "engineering")), "damage": String(e.get("damage", "6d6")), "type": "Energy",
		"half": true, "ap": true, "label": label, "objects_hit": true}
	events.append_array(AbilityActions.apply_target_ops(state, u, [op], ids))
	return events


# --- Sherman ZF4 SOLIDCORE ------------------------------------------------------------

static func zf4_charges(u: Unit) -> int:
	return int(u.counters.get("zf4_charges", 1))


static func set_charges(u: Unit, n: int) -> Array[Dictionary]:
	var w := _weapon(u, ZF4)
	if w.is_empty():
		return [] as Array[Dictionary]
	n = clampi(n, 1, 4)
	u.counters["zf4_charges"] = n
	Weapons.set_profile(w, n - 1)
	return [{"type": "effect_triggered", "unit": u.id, "effect": "ZF4 SOLIDCORE", "target": u.id, "charges": n, "rule_ref": "frames: Sherman core system"}] as Array[Dictionary]


static func _weapon(u: Unit, id: String) -> Dictionary:
	for w: Dictionary in u.loadout.get("weapons", []):
		if w.get("id", "") == id:
			return w
	return {}


## Stabilize: ZF4 charges, Vent Heat soft cover, Mathur Stop.
static func on_stabilize(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not _weapon(u, ZF4).is_empty():
		events.append_array(set_charges(u, zf4_charges(u) + (2 if Effects.has(u, "coreburn") else 1)))
	events.append_array(vent_heat(state, u))
	if params.get("mathur_stop", false) and Effects.has(u, "mathur_stop") and params.get("main", "") == "cool":
		events.append_array(Combat.apply_heat(state, u, u.heat_cap - u.heat_cap / 2, "Mathur Stop"))
	return events


static func vent_heat(state: GameState, u: Unit) -> Array[Dictionary]:
	if not Effects.has(u, "vent_heat"):
		return [] as Array[Dictionary]
	return Effects.activate(state, u, [{"kind": "soft_cover_aura", "self_only": true}], "Vent Heat", "start_next_turn")


## Damage dealt to objects and deployables by frame weapons (ZF4 with COREBURN; Apocalypse
## Rail objects in the area). Returns [] to keep the weapon's own damage.
static func object_damage(attacker: Unit, w: Dictionary, target: Unit) -> Array:
	if target.kind != Unit.KIND_DEPLOYABLE:
		return []
	if w.get("id", "") == ZF4 and Effects.has(attacker, "coreburn"):
		return [{"type": "Energy", "val": str(10 * int(w.get("fired_charges", 1)))}]
	return []


## Before/after an area attack with a frame weapon.
static func before_area(attacker: Unit, w: Dictionary) -> void:
	if w.get("id", "") == ZF4:
		w["fired_charges"] = zf4_charges(attacker)


static func after_area(state: GameState, attacker: Unit, w: Dictionary, events: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if w.get("id", "") == ZF4:
		out.append_array(set_charges(attacker, 1))  # resets to 1 Charge after each attack
	if w.get("id", "") == RAIL:
		var profile := int(w.get("profile", 0))
		var shred := profile >= 2
		var also := "Impaired" if profile == 2 else ("Stunned" if profile == 3 else "")
		for ev: Dictionary in events:
			if ev.get("type", "") != "attack_rolled" or ev.get("attacker", "") != attacker.id or ev.get("result", "miss") == "miss":
				continue
			var t := state.unit(String(ev["target"]))
			if t == null or not Combat.is_present(t):
				continue
			if shred:
				out.append_array(Combat.add_status(state, t, "Shredded", attacker.id, t.id))
			if also != "":
				out.append_array(Combat.add_status(state, t, also, attacker.id, t.id))
		attacker.counters["apocalypse"] = 4
		attacker.counters["apocalypse_at"] = [attacker.cell.x, attacker.cell.y, attacker.level]
		out.append_array(_rail_profile(attacker))
	return out


# --- Barbarossa Apocalypse Rail -------------------------------------------------------

static func _rail_profile(u: Unit) -> Array[Dictionary]:
	var w := _weapon(u, RAIL)
	if not w.is_empty():
		Weapons.set_profile(w, 4 - int(u.counters.get("apocalypse", 4)))
	return [] as Array[Dictionary]


static func check_rail(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
	var ref := "frames: Barbarossa core system"
	var w := _weapon(u, RAIL)
	if w.is_empty() or not u.counters.has("apocalypse"):
		return RuleResult.deny("The Apocalypse Rail must be charged first (Charge Rail core power).", ref)
	if int(u.counters["apocalypse"]) > 3:
		return RuleResult.deny("The Apocalypse Die must be at 3 or lower to fire.", ref)
	if u.turn.get("moved", false) or u.turn.get("acted", false):
		return RuleResult.deny("Firing the Apocalypse Rail must be the only thing you do this turn.", ref)
	var plan := Areas.plan(state, u, w, TurnAction.cell_param(params, "aim"), int(params.get("aim_level", -1)))
	if not plan["ok"]:
		return RuleResult.deny(plan["reason"], plan["rule_ref"])
	var aim: Vector2i = TurnAction.cell_param(params, "aim")
	if Sight.distance(state, Sight.body_of(state, u), Sight.make_body(state, aim, state.map.ground_height(aim), 0.5)) <= 5:
		return RuleResult.deny("The Apocalypse Rail can't be fired at targets within range 5.", ref)
	return RuleResult.allow()


static func fire_rail(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
	var w := _weapon(u, RAIL)
	u.turn["rail_fired"] = true
	return Areas.attack(state, u, w, params)


# --- Iskander -------------------------------------------------------------------------

## Extra reach for planting a mine (Assault Launcher), if unused this round.
static func mine_reach(state: GameState, u: Unit) -> int:
	for e: Dictionary in Effects.of(u, "assault_launcher"):
		if int(u.counters.get("launcher_round", -1)) != state.round_number:
			return int(e.get("range", 15))
	return 0
