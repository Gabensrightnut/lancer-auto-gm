class_name ViewFilter
extends RefCounted
## Builds what one seat is allowed to know (DESIGN.md section 6). The host sends each client
## only its own view, so secrets never leave the host.
##
## The base filter hides what can be decided without rules knowledge:
## - Units with the Hidden status are left out of hostile views (approximate position only).
## - Enemy stats are reduced to what's visible on the field unless the seat's side has
##   intel on that unit (Scan etc.), recorded in `intel`.
## The rules engine work extends this (sensors, GM secrets, events filtering).

## side -> {unit_id -> true} for enemies whose full stats that side has learned.
var intel: Dictionary = {}

## Fields anyone can see on any unit standing in the open.
const PUBLIC_FIELDS := ["id", "name", "kind", "side", "content_id", "size", "cell", "level", "flying", "statuses"]


func knows_stats(side: String, unit_id: String) -> bool:
	return intel.get(side, {}).has(unit_id)


func reveal_stats(side: String, unit_id: String) -> void:
	if not intel.has(side):
		intel[side] = {}
	intel[side][unit_id] = true


## The state as `seat` may see it, as a Dictionary ready to send.
func view_for(state: GameState, seat: String) -> Dictionary:
	var seat_side: String = state.seats.get(seat, {}).get("side", "")
	var full := state.to_dict()
	full.erase("dice_state")
	full.erase("seed")
	var units := {}
	for id: String in state.units:
		var u: Unit = state.units[id]
		var d := u.to_dict()
		if u.side == seat_side or knows_stats(seat_side, id):
			units[id] = d
			continue
		if u.has_status("Hidden"):
			# Glossary, Hidden: enemies only know their approximate location.
			units[id] = {"id": id, "side": u.side, "hidden": true}
			continue
		var visible := {}
		for key: String in PUBLIC_FIELDS:
			visible[key] = d[key]
		units[id] = visible
	full["units"] = units
	return full
