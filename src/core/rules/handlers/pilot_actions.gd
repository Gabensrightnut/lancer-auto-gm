class_name PilotActions
extends RefCounted
## Eject, Mount, Dismount, Fight (pilots on foot), Self Destruct, Prepare.
## See Pilots for how pilots and mechs are linked.


## Hands the rest of the turn from one unit to the other (the same character) and marks the
## one left behind as having acted this round.
static func _hand_turn(state: GameState, from: Unit, to: Unit) -> void:
	to.turn = from.turn.duplicate(true)
	if not state.acted.has(from.id):
		state.acted.append(from.id)
	state.active_unit = to.id


class Eject:
	extends TurnAction
	## Quick action: the pilot flies 6 spaces in the direction of your choice; the mech is
	## Impaired, and you can't Eject again, until a Full Repair (Core p.71). Whether that means
	## exactly 6 in a line or anywhere within 6 is the table's "eject_distance" ruling.
	## params: {"to": [x, y]}

	func type() -> String:
		return "eject"

	func kinds() -> Array:
		return [Unit.KIND_MECH]

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		if u.counters.get("ejected", false):
			return RuleResult.deny("Eject is single-use until your next Full Repair.", "actions: Eject")
		if u.counters.get("empty", false):
			return RuleResult.deny("Nobody is inside.", "actions: Eject")
		var to: Variant = TurnAction.cell_param(params, "to")
		if to == null or not state.map.has_cell(to):
			return RuleResult.deny("Choose a space up to 6 away to land in.", "actions: Eject")
		var lv := state.map.ground_height(to)
		var dist := state.map.grid.distance(u.cell, to)
		match Rulings.choice(state, "eject_distance"):
			"":
				return Rulings.needed("eject_distance")
			"straight_six":
				if dist != 6:
					return RuleResult.deny("Ejecting flies you 6 spaces: pick a space exactly 6 away.", "Core p.71 Eject")
			_:
				if dist > 6:
					return RuleResult.deny("Ejecting flies you at most 6 spaces.", "Core p.71 Eject")
		if not Pilots._free_for_pilot(state, to, lv):
			return RuleResult.deny("That space isn't free.", "actions: Eject")
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var to: Vector2i = TurnAction.cell_param(params, "to")
		var pilot := Pilots.ensure_pilot(state, u)
		u.counters["ejected"] = true
		var events: Array[Dictionary] = [{"type": "ejected", "unit": u.id, "pilot": pilot.id, "rule_ref": "actions: Eject"}]
		if not Effects.has(u, "eject_no_impair"):
			events.append_array(Combat.add_status(state, u, "Impaired", "Eject"))
		events.append_array(Pilots.unseat(state, pilot, u, to, state.map.ground_height(to)))
		TurnRules.spend(u, cost(), type())
		PilotActions._hand_turn(state, u, pilot)
		pilot.turn["moved"] = true
		return events

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		return apply(state, state.unit(action["actor"]), action.get("params", {}))


class Dismount:
	extends TurnAction
	## Full action: the pilot climbs off into an adjacent free space (Core p.71). Actor: the mech,
	## or the pilot inside a destroyed mech (Core p.80). params: {"to": [x, y]} (optional)

	func type() -> String:
		return "dismount"

	func cost() -> String:
		return TurnRules.FULL

	func kinds() -> Array:
		return [Unit.KIND_MECH, Unit.KIND_PILOT]

	func _mech(state: GameState, u: Unit) -> Unit:
		return state.unit(String(u.counters.get("mounted_in", ""))) if u.kind == Unit.KIND_PILOT else u

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var m := _mech(state, u)
		if m == null:
			return RuleResult.deny("You aren't inside a mech.", "Core p.71 Dismount")
		if (m.counters.get("hacked", {}) as Dictionary).has("jam_cockpit"):
			return RuleResult.deny("The cockpit is jammed: fix it first (an Engineering check as a full action, `fix_hack`).", "talents: Hacker")
		if m.counters.get("empty", false):
			return RuleResult.deny("Nobody is inside.", "Core p.71 Dismount")
		if Pilots.free_adjacent(state, m, TurnAction.cell_param(params, "to")) == null:
			return RuleResult.deny("No free adjacent space to dismount into.", "Core p.71 Dismount")
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var m := _mech(state, u)
		var spot: Array = Pilots.free_adjacent(state, m, TurnAction.cell_param(params, "to"))
		var pilot := Pilots.ensure_pilot(state, m)
		var events := Pilots.unseat(state, pilot, m, spot[0], spot[1])
		TurnRules.spend(u, cost(), type())
		if u != pilot:
			PilotActions._hand_turn(state, u, pilot)
		return events

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		return apply(state, state.unit(action["actor"]), action.get("params", {}))


class Mount:
	extends TurnAction
	## Full action for a pilot adjacent to its (empty) mech (actions: Mount).
	## params: {"mech": unit id}

	func type() -> String:
		return "mount"

	func cost() -> String:
		return TurnRules.FULL

	func kinds() -> Array:
		return [Unit.KIND_PILOT]

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var m := state.unit(String(params.get("mech", "")))
		if m == null or m.kind != Unit.KIND_MECH or m.destroyed:
			return RuleResult.deny("Choose a mech that isn't destroyed.", "actions: Mount")
		if m.side != u.side:
			return RuleResult.deny("You can only mount your own or willing allied mechs.", "actions: Mount")
		if (m.counters.get("hacked", {}) as Dictionary).has("jam_cockpit"):
			return RuleResult.deny("The cockpit is jammed.", "talents: Hacker")
		if not m.counters.get("empty", false) or (m.counters.has("pilot") and m.counters["pilot"] != u.id):
			return RuleResult.deny("Someone is already piloting that mech.", "actions: Mount")
		if Sight.unit_distance(state, u, m) > 1:
			return RuleResult.deny("You must be adjacent to the mech.", "actions: Mount")
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var m := state.unit(String(params["mech"]))
		Pilots.seat(state, u, m)
		TurnRules.spend(u, cost(), type())
		PilotActions._hand_turn(state, u, m)
		var events: Array[Dictionary] = [{"type": "pilot_mounted", "unit": u.id, "mech": m.id, "rule_ref": "actions: Mount"}]
		events.append_array(Combat.after_movement(state))
		return events

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		return apply(state, state.unit(action["actor"]), action.get("params", {}))


class Fight:
	extends TurnAction
	## Pilots on foot: attack with one pilot weapon; a full action, or quick with a Sidearm
	## (actions: Fight; tags: Sidearm). Archaic weapons can't harm mechs (tags: Archaic).
	## params: {"weapon", "target"}

	func type() -> String:
		return "fight"

	func kinds() -> Array:
		return [Unit.KIND_PILOT]

	func cost_for(params: Dictionary) -> String:
		return TurnRules.QUICK if params.get("_sidearm", false) else TurnRules.FULL

	func validate(state: GameState, action: Dictionary) -> RuleResult:
		var u := state.unit(action["actor"])
		var params: Dictionary = action.get("params", {})
		params["_sidearm"] = Weapons.has_tag(Weapons.find(u, String(params.get("weapon", ""))), "tg_sidearm")
		return super(state, action)

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var w := Weapons.find(u, String(params.get("weapon", "")))
		var p := Attacks.preview(state, u, w, state.unit(String(params.get("target", ""))), params)
		return RuleResult.allow() if p["ok"] else RuleResult.deny(p["reason"], p["rule_ref"])

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var w := Weapons.find(u, String(params["weapon"]))
		return Attacks.attack(state, u, w, state.unit(String(params["target"])), params)


class SelfDestruct:
	extends TurnAction
	## Quick action: the reactor explodes at the end of your next turn (delay 1) or the one
	## after (delay 2): Burst 2, 4d6 explosive, Agility save for half; the mech and anyone
	## inside are destroyed (actions: Self Destruct). params: {"delay": 1 | 2}
	## PROVISIONAL: "within the following two rounds" read as your next or following turn,
	## chosen when you start it.

	func type() -> String:
		return "self_destruct"

	func kinds() -> Array:
		return [Unit.KIND_MECH]

	func check(_state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		if u.counters.has("self_destruct"):
			return RuleResult.deny("Already counting down.", "actions: Self Destruct")
		var d := int(params.get("delay", 1))
		if d < 1 or d > 2:
			return RuleResult.deny("Delay is 1 (end of your next turn) or 2 (the turn after).", "actions: Self Destruct")
		return RuleResult.allow()

	func apply(state: GameState, u: Unit, params: Dictionary) -> Array[Dictionary]:
		var turns := (2 if state.active_unit == u.id else 1) + int(params.get("delay", 1)) - 1
		u.counters["self_destruct"] = turns
		return [{"type": "self_destruct_started", "unit": u.id, "turns": turns, "rule_ref": "actions: Self Destruct"}] as Array[Dictionary]


class Prepare:
	extends TurnAction
	## Quick action: ready another quick action with a trigger; take it as a reaction when
	## the trigger happens, before the start of your next turn. Until then you can't move,
	## act or react (actions: Prepare). Counts as taking the prepared action.
	## params: {"action": {"type": "skirmish", "params": {"weapon": "0:0", "target": "trigger"}},
	##  "trigger": {"event": "moves_adjacent" | "moves_within" | "acts" | "attacks", "who": "hostile" |
	##  "ally" | "any", "range": n, "actions": [types] (acts), "target": "me" | "ally" | "any"
	##  (attacks)}, "text": "When a hostile moves adjacent to me, I skirmish it"}
	## A params value "trigger" means the character that set it off.
	## PROVISIONAL (RULES_TODO "Prepare"): action triggers go off after that action resolves.

	func type() -> String:
		return "prepare"

	func kinds() -> Array:
		return [Unit.KIND_MECH, Unit.KIND_NPC, Unit.KIND_PILOT]

	func economy_name_for(params: Dictionary) -> String:
		return String(params.get("action", {}).get("type", ""))

	func check(state: GameState, u: Unit, params: Dictionary) -> RuleResult:
		var a: Variant = params.get("action")
		var trig: Variant = params.get("trigger")
		if not a is Dictionary or not trig is Dictionary:
			return RuleResult.deny("Give the action to prepare and its trigger.", "actions: Prepare")
		var h: Variant = RulesEngine.registry.get(String(a.get("type", "")))
		if not h is TurnAction or (h as TurnAction).cost() != TurnRules.QUICK or a["type"] == "prepare":
			return RuleResult.deny("You can only Prepare a quick action.", "actions: Prepare")
		if not ["moves_adjacent", "moves_within", "acts", "attacks"].has(trig.get("event", "")):
			return RuleResult.deny("Triggers: a character moves adjacent to you or within a range, takes an action (optionally which), or attacks (you, an ally, or anyone).", "actions: Prepare")
		var r := TurnRules.can_spend(u, TurnRules.QUICK, String(a["type"]))
		if not r.ok:
			return r
		var w := Weapons.find(u, String(a.get("params", {}).get("weapon", "")))
		if Weapons.has_tag(w, "tg_ordnance") and (u.turn.get("acted", false) or u.turn.get("moved", false)):
			return RuleResult.deny("You can't move or act and then Prepare an Ordnance attack.", "actions: Prepare")
		return RuleResult.allow()

	func validate(state: GameState, action: Dictionary) -> RuleResult:
		var u := state.unit(action["actor"])
		var r := TurnRules.check_own_turn(state, u)
		if not r.ok:
			return r
		if not kinds().has(u.kind):
			return RuleResult.deny("This unit can't Prepare.", "actions: Prepare")
		return check(state, u, action.get("params", {}))

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		var u := state.unit(action["actor"])
		var params: Dictionary = action["params"]
		TurnRules.spend(u, TurnRules.QUICK, String(params["action"]["type"]))
		u.counters["prepared"] = params.duplicate(true)
		u.turn["prepared_lock"] = true
		return [{"type": "prepared", "unit": u.id, "action": params["action"]["type"], "trigger": params["trigger"],
			"text": params.get("text", ""), "rule_ref": "actions: Prepare"}] as Array[Dictionary]


class DropPrepared:
	extends ActionHandler
	## Drop a prepared action so you can take reactions again (actions: Prepare). Any time.

	func type() -> String:
		return "drop_prepared"

	func validate(state: GameState, action: Dictionary) -> RuleResult:
		if not state.unit(action["actor"]).counters.has("prepared"):
			return RuleResult.deny("No prepared action.", "actions: Prepare")
		return RuleResult.allow()

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		var u := state.unit(action["actor"])
		u.counters.erase("prepared")
		return [{"type": "prepared_lost", "unit": u.id, "reason": "dropped", "rule_ref": "actions: Prepare"}] as Array[Dictionary]
