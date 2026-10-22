class_name AiKnowledge
extends RefCounted
## What one side knows, as a GameState the AI can plan on. Built with the same rules as
## ViewFilter.view_for: the side's own units in full, enemies it has scanned in full, other
## enemies only as seen on the field (stats unknown), and Hidden enemies left out entirely.
## The AI runs RulesQueries on this copy, so it can never use a secret, and never touches
## the real state (it only submits actions).

var side := ""
## The side's picture of the battle. Safe to change while planning (it's a copy).
var state: GameState
## Enemy unit ids whose stats this side doesn't know (their numbers are defaults).
var unknown: Dictionary = {}


static func for_side(real: GameState, filter: ViewFilter, side_id: String) -> AiKnowledge:
	var k := AiKnowledge.new()
	k.side = side_id
	var units := {}
	for id: String in real.units:
		var u: Unit = real.units[id]
		if u.side == side_id or filter.knows_stats(side_id, id, real):
			units[id] = u.to_dict()
		elif u.has_status("Hidden"):
			continue  # Statuses, Hidden: enemies can't target what they can't find.
		else:
			var full := u.to_dict()
			var seen := {}
			for key: String in ViewFilter.PUBLIC_FIELDS:
				seen[key] = full[key]
			units[id] = seen
			k.unknown[id] = true
	var s := GameState.new(0, real.map.grid.shape)
	s.map = real.map  # Shared, read-only: planning never edits terrain.
	for id: String in units:
		s.units[id] = Unit.from_dict(units[id])
	s.round_number = real.round_number
	s.phase = real.phase
	s.active_unit = real.active_unit
	s.acted = real.acted.duplicate()
	s.turn_side = real.turn_side
	s.first_side = real.first_side
	s.intel = {side_id: real.intel.get(side_id, {}).duplicate()}
	s.seats = real.seats.duplicate(true)
	s.rulings = real.rulings.duplicate(true)
	k.state = s
	return k


func knows_stats(unit_id: String) -> bool:
	return not unknown.has(unit_id)


func enemies_of(u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for o: Unit in state.units.values():
		if o.side != u.side and not o.destroyed and o.kind != Unit.KIND_DEPLOYABLE:
			out.append(o)
	return out


func allies_of(u: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for o: Unit in state.units.values():
		if o.side == u.side and o.id != u.id and not o.destroyed and o.kind != Unit.KIND_DEPLOYABLE:
			out.append(o)
	return out
