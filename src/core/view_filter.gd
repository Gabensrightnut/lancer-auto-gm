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
	var units := {}
	for id: String in state.units:
		var u: Unit = state.units[id]
		var d := u.to_dict()
		if u.side == seat_side or _is_gm(state, seat) or knows_stats(seat_side, id, state):
			units[id] = d
			continue
		if u.has_status("Hidden"):
			# Statuses, Hidden: enemies only know their approximate location.
			units[id] = {"id": id, "side": u.side, "hidden": true}
			continue
		var visible := {}
		for key: String in PUBLIC_FIELDS:
			visible[key] = d[key]
		units[id] = visible
	full["units"] = units
	return full


## The events `seat` may see: hostile Hidden units' movement is dropped, and unscanned
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
		var copy := e.duplicate(true)
		if hostile and not knows_stats(seat_side, uid, state):
			for key in ["hp", "overshield", "total"]:
				if e.get("type", "") in ["hp_changed", "heat_changed"]:
					copy.erase(key)
		out.append(copy)
	return out


func _side(state: GameState, seat: String) -> String:
	return state.seats.get(seat, {}).get("side", "")


func _is_gm(state: GameState, seat: String) -> bool:
	return seat == "gm" or state.seats.get(seat, {}).get("gm", false)
