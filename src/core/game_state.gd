class_name GameState
extends RefCounted
## The complete, authoritative state of one battle. Lives on the host only.
## Clients receive filtered copies made by ViewFilter, never this object.

const PHASE_SETUP := "setup"
const PHASE_COMBAT := "combat"
const PHASE_ENDED := "ended"

var game_seed: int = 0
var map: BattleMap
var units: Dictionary = {}  # id -> Unit
var round_number: int = 0
var phase: String = PHASE_SETUP
## Unit whose turn it is ("" between turns).
var active_unit: String = ""
## Units that have already acted this round.
var acted: PackedStringArray = PackedStringArray()
## Side that picks the next unit to act; sides alternate (src/core/rules/turn_rules.gd).
var turn_side: String = ""
## Side that acts first each round.
var first_side: String = ""
## side -> {unit_id: true}: enemies whose full stats that side has learned (Scan...).
## ViewFilter reads it.
var intel: Dictionary = {}
## A reaction the engine is waiting for (src/core/rules/reactions.gd): {id, unit, reaction,
## context, action, decisions, snapshot}. While set, only that unit's "react" is accepted.
var pending: Dictionary = {}
## Runtime only (not saved): bookkeeping while the engine resolves one action.
var reaction_run: Dictionary = {}
## Player seats: seat id -> {"name": String, "side": String}.
var seats: Dictionary = {}
## Rulings made on grey areas this campaign: ruling id -> {choice, rule_ref, note}.
var rulings: Dictionary = {}
## Content packs this battle uses: [{"id", "name", "version"}] (see src/content/content_pack.gd).
## Everyone in the game must have the same packs.
var packs: Array = []
## Areas left on the field by frame systems (Mag Field, smoke clouds, holograms): see Zones.
var zones: Array = []
## Rules environments for the whole battle (lancer-data environments.json ids, e.g.
## "env_particulatestorms"), set by the mission generator from the world's weather.
var environments: Array = []
## Damage on the top section of destructible terrain columns: {"x,y": damage}. See
## TerrainDamage (Core p.68).
var terrain_damage: Dictionary = {}
var dice: Dice


func _init(seed_value: int = 0, grid_shape: GridLayout.Shape = GridLayout.Shape.HEX) -> void:
	game_seed = seed_value
	dice = Dice.new(seed_value)
	map = BattleMap.new(grid_shape)


func add_unit(unit: Unit) -> void:
	assert(unit.id != "" and not units.has(unit.id), "unit needs a unique id")
	units[unit.id] = unit


func unit(id: String) -> Unit:
	return units.get(id)


func units_on_side(side: String) -> Array[Unit]:
	var out: Array[Unit] = []
	for u: Unit in units.values():
		if u.side == side:
			out.append(u)
	return out


func are_allies(a: Unit, b: Unit) -> bool:
	return a.side == b.side


func to_dict() -> Dictionary:
	var unit_dicts := {}
	for id: String in units:
		unit_dicts[id] = (units[id] as Unit).to_dict()
	return {
		"seed": str(game_seed), "map": map.to_dict(), "units": unit_dicts,
		"round": round_number, "phase": phase, "active_unit": active_unit,
		"acted": Array(acted), "turn_side": turn_side, "first_side": first_side,
		"intel": intel.duplicate(true), "pending": pending.duplicate(true), "seats": seats.duplicate(true),
		"rulings": rulings.duplicate(true), "packs": packs.duplicate(true), "dice_state": str(dice.get_state()),
		"zones": zones.duplicate(true), "environments": environments.duplicate(), "terrain_damage": terrain_damage.duplicate(),
	}


static func from_dict(d: Dictionary) -> GameState:
	# Seed and dice state are strings: 64-bit ints don't survive JSON's float numbers.
	var s := GameState.new(str(d.get("seed", "0")).to_int())
	s.map = BattleMap.from_dict(d.get("map", {}))
	for id: String in d.get("units", {}):
		s.units[id] = Unit.from_dict(d["units"][id])
	s.round_number = int(d.get("round", 0))
	s.phase = d.get("phase", PHASE_SETUP)
	s.active_unit = d.get("active_unit", "")
	s.acted = PackedStringArray(d.get("acted", []))
	s.turn_side = d.get("turn_side", "")
	s.first_side = d.get("first_side", "")
	s.intel = (d.get("intel", {}) as Dictionary).duplicate(true)
	s.pending = (d.get("pending", {}) as Dictionary).duplicate(true)
	s.seats = (d.get("seats", {}) as Dictionary).duplicate(true)
	s.rulings = (d.get("rulings", {}) as Dictionary).duplicate(true)
	s.packs = (d.get("packs", []) as Array).duplicate(true)
	s.zones = (d.get("zones", []) as Array).duplicate(true)
	s.terrain_damage = (d.get("terrain_damage", {}) as Dictionary).duplicate()
	s.environments = (d.get("environments", []) as Array).duplicate()
	if d.has("dice_state"):
		s.dice.set_state(String(d["dice_state"]).to_int())
	return s
