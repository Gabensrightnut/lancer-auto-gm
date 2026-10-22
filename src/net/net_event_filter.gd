class_name NetEventFilter
extends RefCounted
## Which events one seat may see. The host runs this before sending events, the same way it
## sends ViewFilter.view_for() instead of the state.
##
## If ViewFilter has an `events_for(state, seat, events)` method (owned by the rules work),
## that decides. Until then this fallback applies the same secrets as the view:
## - events about a unit this seat can't see (Hidden, or not in its view at all) are dropped,
##   except the Hidden status being added/removed, which happens in the open;
## - stat totals of units whose stats this seat doesn't know are removed;
## - dice state and seeds are stripped everywhere.

## Event fields that name a unit.
const UNIT_FIELDS := ["unit", "attacker", "target"]
## Per event type: fields that reveal a stat the seat may not know.
const STAT_FIELDS := {"heat_changed": ["total"]}
## Never sent to anyone, at any depth.
const NEVER_SENT := ["dice_state", "seed", "rng_state"]


static func events_for(filter: ViewFilter, state: GameState, seat: String, events: Array, view: Dictionary) -> Array:
	var out: Array = []
	if filter.has_method("events_for"):
		out = filter.call("events_for", state, seat, events)
	else:
		for e: Dictionary in events:
			var seen := _fallback(e, view)
			if not seen.is_empty():
				out.append(seen)
	var clean: Array = []
	for e: Dictionary in out:
		clean.append(_strip(e))
	return clean


static func _fallback(event: Dictionary, view: Dictionary) -> Dictionary:
	var units: Dictionary = view.get("units", {})
	var e := event.duplicate(true)
	for field: String in UNIT_FIELDS:
		var id: Variant = e.get(field)
		if not id is String:
			continue
		var seen: Dictionary = units.get(id, {})
		var hidden: bool = seen.is_empty() or seen.get("hidden", false)
		if hidden and not _is_hidden_status_change(e):
			return {}
		if not seen.has("hp"):
			# Stats unknown to this seat (unscanned enemy).
			for key: String in STAT_FIELDS.get(e.get("type", ""), []):
				e.erase(key)
	return e


static func _is_hidden_status_change(e: Dictionary) -> bool:
	return e.get("type") in ["status_added", "status_removed"] and e.get("status") == "Hidden"


static func _strip(value: Variant) -> Variant:
	if value is Dictionary:
		var d := {}
		for key: Variant in value:
			if not key in NEVER_SENT:
				d[key] = _strip(value[key])
		return d
	if value is Array:
		var a: Array = []
		for v: Variant in value:
			a.append(_strip(v))
		return a
	return value
