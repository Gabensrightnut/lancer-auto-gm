class_name ViewFilter
extends RefCounted
## Builds what one seat is allowed to know (DESIGN.md section 6). The host sends each client
## only its own view, so secrets never leave the host.
##
## - Units with the Hidden status are left out of hostile views (approximate position only).
## - Enemy stats are reduced to what's visible on the field unless the seat's side has
##   intel on that unit: Scan writes it to `state.intel` (saved with the game); `reveal_stats`
##   on this object adds host-side extra intel (e.g. a GM reveal).
## - events_for() filters event lists the same way.

## side -> {unit_id -> true} for enemies whose full stats that side has learned (extra to
## state.intel).
var intel: Dictionary = {}

## Fields anyone can see on any unit standing in the open.
const PUBLIC_FIELDS := ["id", "name", "kind", "side", "content_id", "size", "cell", "level", "flying", "statuses", "destroyed"]


func knows_stats(side: String, unit_id: String, state: GameState = null) -> bool:
	if intel.get(side, {}).has(unit_id):
		return true
	return state != null and state.intel.get(side, {}).has(unit_id)


func reveal_stats(side: String, unit_id: String) -> void:
	if not intel.has(side):
		intel[side] = {}
	intel[side][unit_id] = true


## Records intel in the game state itself (used by the Scan action).
static func reveal_in_state(state: GameState, side: String, unit_id: String) -> void:
	if not state.intel.has(side):
		state.intel[side] = {}
	state.intel[side][unit_id] = true


## The state as `seat` may see it, as a Dictionary ready to send.
func view_for(state: GameState, seat: String) -> Dictionary:
	var seat_side := _side(state, seat)
	var full := state.to_dict()
	full.erase("dice_state")
	full.erase("seed")
	full["intel"] = {seat_side: state.intel.get(seat_side, {})} if seat_side != "" else {}
	if not state.pending.is_empty():
		# The rewind point and earlier answers stay on the host.
		full["pending"] = {"id": state.pending["id"], "unit": state.pending["unit"],
			"reaction": state.pending["reaction"], "ruling": state.pending.get("ruling", ""),
			"context": state.pending.get("context", {})}
	var units := {}
	for id: String in state.units:
		var u: Unit = state.units[id]
		var d := u.to_dict()
		if u.side == seat_side or _is_gm(state, seat) or knows_stats(seat_side, id, state):
			units[id] = d
			continue
		if u.has_status("Hidden") or setup_hides(state):
			# Statuses, Hidden: enemies only know their approximate location. Pre-battle setup:
			# the other side's placement stays secret until the fight starts.
			units[id] = {"id": id, "side": u.side, "hidden": true}
			continue
		var visible := {}
		for key: String in PUBLIC_FIELDS:
			visible[key] = d[key]
		for key: String in ["soldier", "men_left"]:
			if d.has(key):
				visible[key] = d[key]  # soldiers: what they are and how many are left, plain to see
		var lost := mounts_lost(u)
		if not lost.is_empty():
			visible["mounts_lost"] = lost  # torn off for everyone to see (no stats)
		if u.kind in [Unit.KIND_DEPLOYABLE, "drone"] and u.counters.has("owner"):
			visible["owner"] = str(u.counters["owner"])  # you see which mech a drone left
		units[id] = visible
	full["units"] = units
	full["objectives"] = objectives_for(state, seat)
	return full


## The sitrep objectives a seat may know: Recon's True Control Zone only once its side has
## found it (the GM always knows), and only its own side's surveys.
func objectives_for(state: GameState, seat: String) -> Dictionary:
	var o := state.objectives.duplicate(true)
	if _is_gm(state, seat):
		return o
	var side := _side(state, seat)
	var mine: Dictionary = (o.get("surveyed", {}) as Dictionary).get(side, {})
	o["surveyed"] = {side: mine} if side != "" else {}
	o.erase("true_zone")
	for z: String in mine:
		if bool(mine[z]):
			o["true_zone"] = z
	return o


## The events `seat` may see: hostile Hidden units' movement is dropped, events with a
## `seen_by` list of sides go only to those sides (and the GM), and unscanned
## enemies' HP and heat totals are removed (the amounts of damage and heat stay visible).
func events_for(state: GameState, seat: String, events: Array) -> Array:
	var seat_side := _side(state, seat)
	if _is_gm(state, seat):
		return events.duplicate(true)
	var out: Array = []
	for e: Dictionary in events:
		var uid: String = e.get("unit", "")
		var u := state.unit(uid) if uid != "" else null
		var hostile := u != null and u.side != seat_side
		if hostile and e.get("type", "") == "moved" and u.has_status("Hidden"):
			continue
		if hostile and e.get("type", "") == "unit_deployed" and setup_hides(state):
			continue  # where the other side deploys stays secret during setup
		var seen_by: Variant = e.get("seen_by")
		if seen_by is Array and not (seen_by as Array).has(seat_side):
			continue  # Meant for other sides only (e.g. the GM's twist for the squad).
		var copy := e.duplicate(true)
		if hostile and e.get("type", "") == "deployed" and e.get("object") is Dictionary:
			# A Hidden mine or snare (tags: Mine; Webjaw Snare): the other side sees it thrown,
			# not where it landed.
			var placed := state.unit(str(e["object"].get("id", "")))
			if placed != null and placed.has_status("Hidden"):
				(copy["object"] as Dictionary).erase("cells")
				(copy["object"] as Dictionary).erase("id")
		if hostile and not knows_stats(seat_side, uid, state):
			for key in ["hp", "overshield", "total"]:
				if e.get("type", "") in ["hp_changed", "heat_changed"]:
					copy.erase(key)
		out.append(copy)
	return out


## True while a pre-battle setup is open (BattleSession): sides can't see each other's units.
static func setup_hides(state: GameState) -> bool:
	return state.phase == GameState.PHASE_SETUP and bool((state.objectives.get("setup", {}) as Dictionary).get("open", false))


## Mounts whose weapons System Trauma destroyed (Core p.80): what anyone looking at the mech
## can see is missing, without its stats or gear. For the renderer (missing parts) on every
## seat, including enemies that haven't scanned it.
static func mounts_lost(u: Unit) -> Array:
	var out: Array = []
	var states: Dictionary = u.counters.get("weapons", {})
	for w: Dictionary in u.loadout.get("weapons", []):
		var m := int(w.get("mount", -1))
		if m >= 0 and bool((states.get(String(w.get("key", "")), {}) as Dictionary).get("destroyed", false)) and not out.has(m):
			out.append(m)
	out.sort()
	return out


func _side(state: GameState, seat: String) -> String:
	return state.seats.get(seat, {}).get("side", "")


func _is_gm(state: GameState, seat: String) -> bool:
	return seat == "gm" or state.seats.get(seat, {}).get("gm", false)
