class_name Campaign
extends RefCounted
## A campaign: the squad's pilots and their progression, story flags, the table's rulings,
## the content packs it uses and GM settings. Saved by SaveStore; old saves are upgraded by
## migrate() so they keep loading after updates.
##
## Pilot records use the Compcon layout (src/content/compcon.gd), so a COMP/CON import drops
## straight in. Book default: new pilots start at License Level 0 with GMS gear only (the
## Everest and GMS weapons and systems); the "start_ll" option starts them higher, as the book
## lets GMs do.

## Bump when the saved layout changes, and add a step to migrate().
const SAVE_VERSION := 1
const STARTER_FRAME := "mf_standard_pattern_i_everest"
const SQUADS_FILE := "res://data/game/gm/squads.json"

var id := ""
var name := ""
var created_at := 0
var updated_at := 0
## {"start_ll": 0 (book default), "max_pilots": 4}
var options: Dictionary = {"start_ll": 0, "max_pilots": 4}
## Content packs turned on for this campaign: [ContentPack.summary()].
var packs: Array = []
## pilot id -> pilot record (Compcon layout)
var pilots: Dictionary = {}
## Story flags set by choices and missions (DESIGN.md section 10).
var story_flags: Dictionary = {}
## Grey-area rulings the table made; every mission starts with them.
var rulings: Dictionary = {}
var gm_settings: Dictionary = {}
## Finished missions: [{"number", "sitrep", "outcome", "reason", "operation"}]
var history: Array = []


static func create(campaign_name: String, opts: Dictionary = {}) -> Campaign:
	var c := Campaign.new()
	c.id = "c_" + Crypto.new().generate_random_bytes(6).hex_encode()
	c.name = campaign_name
	c.created_at = int(Time.get_unix_time_from_system())
	c.updated_at = c.created_at
	c.options.merge(opts, true)
	c.options["start_ll"] = clampi(int(c.options["start_ll"]), 0, 12)
	c.gm_settings = GmSettings.from_preset(str(opts.get("gm_preset", "Standard"))).to_dict()
	return c


# --- Pilots ------------------------------------------------------------------------------

## A new pilot at the campaign's starting License Level, flying a GMS Everest with starter gear.
func new_pilot(pilot_name: String, callsign: String) -> Dictionary:
	var builds: Array = GmSettings.load_json(SQUADS_FILE).get("lancers", [])
	var loadout: Dictionary = builds[0]["loadout"].duplicate(true) if not builds.is_empty() else {"mounts": [], "systems": []}
	var mech_id := "mech_" + Crypto.new().generate_random_bytes(4).hex_encode()
	var p := {
		"id": "pilot_" + Crypto.new().generate_random_bytes(4).hex_encode(), "compcon_id": "",
		"name": pilot_name, "callsign": callsign, "player_name": "", "background": "", "notes": "", "history": "",
		"ll": int(options.get("start_ll", 0)), "hull": 0, "agility": 0, "systems": 0, "engineering": 0,
		"skills": {}, "talents": {}, "licenses": {}, "core_bonuses": [], "reserves": [], "pilot_gear": [],
		"mechs": [{"id": mech_id, "name": callsign + "'s Everest", "frame": STARTER_FRAME, "loadout": loadout}],
		"active_mech": mech_id,
	}
	# A starting look (PortraitSpec v2; the builder's look creator changes it).
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(p["id"])
	p["portrait"] = PortraitSpec.randomize(rng)
	pilots[p["id"]] = p
	return p


## Adds a pilot (e.g. from a COMP/CON import). Returns the problems that make it not legal in
## this campaign (it's still added so the player can fix it in the builder).
func add_pilot(p: Dictionary, db: ContentDB) -> Array:
	pilots[p["id"]] = p
	return validate_pilot(p, db)


## Everything that isn't legal about a pilot and their mechs, in plain words.
func validate_pilot(p: Dictionary, db: ContentDB) -> Array:
	var problems: Array = []
	for pr: Dictionary in UnitFactory.check_pilot(db, p):
		problems.append(pr["reason"])
	for m: Dictionary in p.get("mechs", []):
		var r := UnitFactory.check_loadout(db, str(m.get("frame", "")), m.get("loadout", {}), p)
		if not r.ok:
			for pr: Dictionary in (r.details if not r.details.is_empty() else [{"reason": r.reason}]):
				var why := str(pr["reason"])
				var line := "%s: %s" % [m.get("name", "Mech"), why]
				if not problems.has(why) and not problems.has(line):  # pilot problems repeat per mech
					problems.append(line)
	return problems


## License Level up after a mission, success or failure (Core p.18 "Leveling Up"). What the
## pilot had spent so far is recorded as spent (`locked`), and one reallocation is offered.
func level_up(pilot_id: String) -> bool:
	var p: Dictionary = pilots.get(pilot_id, {})
	if p.is_empty() or int(p["ll"]) >= 12:
		return false
	var hase := {}
	for k in ["hull", "agility", "systems", "engineering"]:
		hase[k] = int(p.get(k, 0))
	p["locked"] = {"skills": (p.get("skills", {}) as Dictionary).duplicate(), "talents": (p.get("talents", {}) as Dictionary).duplicate(),
		"licenses": (p.get("licenses", {}) as Dictionary).duplicate(), "core_bonuses": (p.get("core_bonuses", []) as Array).duplicate(),
		"hase": hase}
	p["realloc_pending"] = true
	p["ll"] = int(p["ll"]) + 1
	return true


## The squad for MissionGenerator (opts.squad): one entry per pilot, in seat order.
func squad() -> Array:
	var out: Array = []
	var ids := pilots.keys()
	ids.sort()
	for i in range(mini(ids.size(), int(options.get("max_pilots", 4)))):
		var p: Dictionary = pilots[ids[i]]
		var mech: Dictionary = {}
		for m: Dictionary in p.get("mechs", []):
			if m["id"] == p.get("active_mech", "") or mech.is_empty():
				mech = m
		out.append({"seat": "p%d" % (i + 1), "pilot": p, "mech": mech})
	return out


# --- Missions ----------------------------------------------------------------------------

## Before a mission starts: the table's rulings and the campaign's packs go into the battle.
func prepare_mission(state: GameState) -> void:
	state.rulings = rulings.duplicate(true)
	state.packs = packs.duplicate(true)


## After a mission: keep any new rulings and record the result.
func record_mission(state: GameState, mission: Mission) -> void:
	rulings.merge(state.rulings, true)
	history.append({"number": history.size() + 1, "sitrep": mission.sitrep_name, "outcome": mission.outcome,
		"reason": mission.outcome_reason, "operation": mission.flavor.get("operation", "")})
	updated_at = int(Time.get_unix_time_from_system())


# --- Saving ------------------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"save_version": SAVE_VERSION, "kind": "campaign", "id": id, "name": name,
		"created_at": created_at, "updated_at": updated_at, "options": options.duplicate(true),
		"packs": packs.duplicate(true), "pilots": pilots.duplicate(true), "story_flags": story_flags.duplicate(true),
		"rulings": rulings.duplicate(true), "gm_settings": gm_settings.duplicate(true), "history": history.duplicate(true),
	}


## {"campaign": Campaign or null, "error": ""}. Older saves are upgraded first.
static func from_dict(raw: Dictionary) -> Dictionary:
	var m := migrate(raw)
	if m["error"] != "":
		return {"campaign": null, "error": m["error"]}
	var d: Dictionary = m["data"]
	var c := Campaign.new()
	c.id = str(d.get("id", ""))
	c.name = str(d.get("name", ""))
	c.created_at = int(d.get("created_at", 0))
	c.updated_at = int(d.get("updated_at", 0))
	c.options.merge(d.get("options", {}), true)
	for key in ["start_ll", "max_pilots"]:
		c.options[key] = int(c.options[key])
	c.packs = (d.get("packs", []) as Array).duplicate(true)
	c.pilots = _ints((d.get("pilots", {}) as Dictionary).duplicate(true))
	c.story_flags = (d.get("story_flags", {}) as Dictionary).duplicate(true)
	c.rulings = (d.get("rulings", {}) as Dictionary).duplicate(true)
	c.gm_settings = (d.get("gm_settings", {}) as Dictionary).duplicate(true)
	c.history = (d.get("history", []) as Array).duplicate(true)
	return {"campaign": c, "error": ""}


## Brings an older save up to SAVE_VERSION. {"data": Dictionary, "error": ""}.
## Version 0 = saves from before versioning (none shipped, kept as the pattern for later steps).
static func migrate(raw: Dictionary) -> Dictionary:
	var d := raw.duplicate(true)
	var v := int(d.get("save_version", 0))
	if v > SAVE_VERSION:
		return {"data": {}, "error": "This save was made by a newer version of the game. Update the game to load it."}
	if v < 1:
		# 0 -> 1: options and history added.
		d["options"] = d.get("options", {"start_ll": 0, "max_pilots": 4})
		d["history"] = d.get("history", [])
		v = 1
	d["save_version"] = v
	return {"data": d, "error": ""}


## JSON numbers come back as floats; pilot ranks and levels are ints.
static func _ints(pilot_map: Dictionary) -> Dictionary:
	for pid: String in pilot_map:
		var p: Dictionary = pilot_map[pid]
		for key in ["ll", "hull", "agility", "systems", "engineering"]:
			p[key] = int(p.get(key, 0))
		for key in ["skills", "talents", "licenses"]:
			var ranks: Dictionary = p.get(key, {})
			for k: String in ranks:
				ranks[k] = int(ranks[k])
	return pilot_map
