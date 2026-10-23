class_name Deployment
extends RefCounted
## Deploying before the fight (setup phase), by the sitreps' deployment rules (lancer-data
## sitreps.json "deployment", Core p.266-279):
## - Escort, Extraction, Holdout, Recon: the PCs deploy first, then the GM.
## - Gauntlet: the GM deploys first, then the PCs.
## - Control: the GM and a player each roll 1d6; the lower roll deploys first (ties re-roll,
##   PROVISIONAL: the book doesn't say).
## - Standard combat: no order (PROVISIONAL: both sides place freely).
## - Holdout: the PCs deploy in the Allied Deployment Zone or the Control Zone.
## Zones: state.objectives["deployment"][side] (Mission), else map cells tagged "deploy_<side>".
## A unit's whole footprint must be inside its side's zone (a Squad's too); footing as for
## placement (Spread Out squads: Soldiers.spread_ok). Re-deploying is the same action until
## combat starts (start_combat closes deployment).
##
## state.objectives keys: "deploying" (the side whose turn it is to deploy, "" = anyone),
## "deployed_sides" (sides that said they're done), "deployment_closed".

const REF := "sitreps: deployment"
const PLAYERS := "players"
const ENEMIES := "enemies"
const PLAYERS_FIRST := ["sitrep_escort", "sitrep_extraction", "sitrep_holdout", "sitrep_recon"]


static func sitrep(state: GameState) -> String:
	return String(state.objectives.get("sitrep", ""))


static func ref(state: GameState) -> String:
	var s := sitrep(state)
	return "sitreps: %s (deployment)" % s.trim_prefix("sitrep_").capitalize() if s != "" else REF


## The order sides deploy in ([] = no order). Control rolls for it through state.dice.
static func order(state: GameState) -> Array:
	var s := sitrep(state)
	if s in PLAYERS_FIRST:
		return [PLAYERS, ENEMIES]
	if s == "sitrep_gauntlet":
		return [ENEMIES, PLAYERS]
	if s == "sitrep_control":
		for i in range(10):
			var gm := state.dice.die(6)
			var pc := state.dice.die(6)
			if gm != pc:
				return [ENEMIES, PLAYERS] if gm < pc else [PLAYERS, ENEMIES]
		return [PLAYERS, ENEMIES]
	return []


## The cells a side may deploy in.
static func zone(state: GameState, side: String) -> Dictionary:
	var out := {}
	var dep: Dictionary = state.objectives.get("deployment", {})
	for c: Variant in dep.get(side, []):
		out[Vector2i(int(c[0]), int(c[1]))] = true
	if out.is_empty():
		for c in state.map.cells():
			if state.map.column(c).has_tag("deploy_" + side):
				out[c] = true
	if side == PLAYERS and sitrep(state) == "sitrep_holdout":
		# Holdout: the PCs may also deploy in the Control Zone.
		for name: String in state.objectives.get("zones", {}):
			for c: Variant in state.objectives["zones"][name]:
				out[Vector2i(int(c[0]), int(c[1]))] = true
	return out


## Starts the deployment order if it hasn't started (called by the first deploy).
static func begin(state: GameState) -> void:
	if state.objectives.has("deploy_order"):
		return
	var o := order(state)
	state.objectives["deploy_order"] = o
	state.objectives["deploying"] = String(o[0]) if not o.is_empty() else ""
	state.objectives["deployed_sides"] = []


static func check(state: GameState, u: Unit, to: Variant, level: int) -> RuleResult:
	var r := ref(state)
	if state.phase != GameState.PHASE_SETUP or state.objectives.get("deployment_closed", false):
		return RuleResult.deny("Deployment is over: the fight has started (latecomers arrive with join_combat).", r)
	if u == null or u.destroyed or u.kind == Unit.KIND_DEPLOYABLE:
		return RuleResult.deny("Choose one of your units to place.", r)
	if to == null or not state.map.has_cell(to):
		return RuleResult.deny("Choose a space on the map (params.to).", r)
	begin(state)
	var turn := String(state.objectives.get("deploying", ""))
	if turn != "" and turn != u.side:
		return RuleResult.deny("It's the %s's turn to deploy first, by this sitrep's rules." % ("squad" if turn == PLAYERS else "GM"), r)
	var zone_cells := zone(state, u.side)
	if zone_cells.is_empty():
		return RuleResult.deny("This map has no deployment zone for your side.", r)
	var body := Sight.make_body(state, to, level, u.size)
	for c in body.cells:
		if not zone_cells.has(c):
			return RuleResult.deny("Deploy inside your side's deployment zone (all of the unit's spaces).", r)
	if Soldiers.spreads(u):
		if not Soldiers.spread_ok(state, u, to, level, u.size):
			return RuleResult.deny("A squad needs at least 2 free spaces to stand in (Spread Out).", Soldiers.REF_SQUAD)
		return RuleResult.allow()
	var place := Movement.placement(state, u.size, to, level)
	if not place["ok"] or not (place["standing"] or u.flying):
		return RuleResult.deny("It can't stand there: %s" % String(place.get("reason", "no footing")), String(place.get("rule_ref", r)))
	for o: Unit in state.units.values():
		if o != u and Combat.is_present(o) and not Soldiers.spreads(o) and Movement._overlaps(body, Sight.body_of(state, o)):
			return RuleResult.deny("That space is taken.", "Core p.62")
	return RuleResult.allow()


static func done(state: GameState, side: String) -> Array[Dictionary]:
	begin(state)
	var sides: Array = state.objectives["deployed_sides"]
	if not sides.has(side):
		sides.append(side)
	var next := ""
	for s: Variant in state.objectives.get("deploy_order", []):
		if not sides.has(s):
			next = String(s)
			break
	state.objectives["deploying"] = next
	return [{"type": "deployment_done", "side": side, "next": next, "rule_ref": ref(state)}] as Array[Dictionary]


class Deploy:
	extends ActionHandler
	## {"type": "deploy", "actor": unit, "params": {"to": [x, y], "level"?}}: places (or moves
	## again) one of your units before the fight. Setup phase only.

	func type() -> String:
		return "deploy"

	func validate(state: GameState, action: Dictionary) -> RuleResult:
		var u := state.unit(String(action.get("actor", "")))
		var params: Dictionary = action.get("params", {})
		var to: Variant = TurnAction.cell_param(params, "to")
		var lv := int(params.get("level", state.map.ground_height(to) if to != null and state.map.has_cell(to) else 0))
		return Deployment.check(state, u, to, lv)

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		var u := state.unit(String(action["actor"]))
		var to: Vector2i = TurnAction.cell_param(action["params"], "to")
		var from := [u.cell.x, u.cell.y, u.level]
		u.cell = to
		u.level = int(action["params"].get("level", state.map.ground_height(to)))
		return [{"type": "unit_deployed", "unit": u.id, "cell": [to.x, to.y, u.level], "from": from, "rule_ref": Deployment.ref(state)}] as Array[Dictionary]


class DeploymentDone:
	extends ActionHandler
	## {"type": "deployment_done", "params": {"side"}} (host): that side has placed its units;
	## the next side in the sitrep's order deploys.

	func type() -> String:
		return "deployment_done"

	func needs_actor() -> bool:
		return false

	func validate(state: GameState, action: Dictionary) -> RuleResult:
		if state.phase != GameState.PHASE_SETUP or state.objectives.get("deployment_closed", false):
			return RuleResult.deny("Deployment is over.", Deployment.ref(state))
		var side := String(action.get("params", {}).get("side", ""))
		if side not in [Deployment.PLAYERS, Deployment.ENEMIES]:
			return RuleResult.deny("Say which side is done (players or enemies).", Deployment.ref(state))
		return RuleResult.allow()

	func resolve(state: GameState, action: Dictionary) -> Array[Dictionary]:
		return Deployment.done(state, String(action["params"]["side"]))
