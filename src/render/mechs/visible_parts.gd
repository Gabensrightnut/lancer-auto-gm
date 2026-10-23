class_name VisibleParts
extends RefCounted
## What visibly leaves or changes on a mech (data/game/visible_parts.json): the look of every
## deployable, where it docks on its owner's body, how it leaves (flies or is lobbed), which
## frames have no cockpit view (their body is what you see), and how gear breaks. Visual only:
## the board shows these parts from GameState (deployed units, destroyed weapons) and the
## engine's events, never on its own.

const FILE := "res://data/game/visible_parts.json"
## Looks DeployableBuilder knows how to build.
const LOOKS := ["drone", "orochi", "turret_drone", "projector", "mine", "block", "cover", "bunker",
	"shield_generator", "snare", "caltrops", "plate", "rocket", "bomb", "pylon", "decoy", "barrier"]

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE)) if FileAccess.file_exists(FILE) else null
		_data = d if d is Dictionary else {"types": {}, "deployables": {}, "frames": {}}
	return _data


## The full spec for a deployable: its own entry over its type's default.
## {look, variant, dock, launch, color}
static func spec(deploy_name: String, deploy_type: String = "") -> Dictionary:
	var own: Dictionary = (data().get("deployables", {}) as Dictionary).get(deploy_name, {})
	var type_def: Dictionary = (data().get("types", {}) as Dictionary).get(deploy_type, {})
	if deploy_type == "" and own.is_empty():
		type_def = (data().get("types", {}) as Dictionary).get("Deployable", {})
	var out := {"look": "block", "variant": "", "dock": "", "launch": "throw", "color": ""}
	out.merge(type_def, true)
	out.merge(own, true)
	if deploy_type == "" and not own.has("launch") and String(out["look"]) in ["drone", "orochi", "turret_drone", "projector"]:
		out["launch"] = "fly"
	return out


## How the pilot sees out: "cockpit" (default) or "body" (drone-bodied frames: no cockpit,
## you see your own remaining body).
static func first_person(frame_id: String) -> String:
	return String((data().get("frames", {}) as Dictionary).get(frame_id, {}).get("first_person", "cockpit"))


## Docked parts a unit carries: one per deploy ability whose deployable docks on the body.
## [{name, dock, spec}] from the unit's loadout abilities (UnitFactory).
static func docks_for(loadout: Dictionary) -> Array:
	var out: Array = []
	var seen := {}
	for a: Dictionary in loadout.get("abilities", []):
		if String(a.get("kind", "")) != "deploy":
			continue
		var d: Dictionary = a.get("deployable", {})
		var n := String(d.get("name", ""))
		if n == "" or seen.has(n):
			continue
		var s := spec(n, String(d.get("type", "")))
		if String(s["dock"]) == "":
			continue
		seen[n] = true
		out.append({"name": n, "dock": String(s["dock"]), "spec": s})
	return out


## A frame's own part that attaches to another unit (Lancaster's Latch Drone):
## {name, dock, counter, spec} or {}.
static func frame_attach(frame_id: String) -> Dictionary:
	var a: Dictionary = (data().get("frames", {}) as Dictionary).get(frame_id, {}).get("attach", {})
	if a.is_empty():
		return {}
	var s := spec(String(a.get("name", "")), "Drone")
	s.merge(a, true)
	return {"name": String(a.get("name", "")), "dock": String(a.get("dock", "back_l")), "counter": String(a.get("counter", "")), "spec": s}


## What a frame shows while its core is active ("swarm" for the Balor's Hellswarm), or "".
static func core_active_look(frame_id: String) -> String:
	return String((data().get("frames", {}) as Dictionary).get(frame_id, {}).get("core_active", ""))


## How many of each deployable have left `owner_id`'s body, from a view's units: every
## deployable of that name the owner has in the state, live or destroyed (a destroyed drone
## doesn't come back; a recall removes it from the state and the part returns).
static func out_counts(units: Dictionary, owner_id: String) -> Dictionary:
	var out := {}
	for id: String in units:
		var u: Dictionary = units[id]
		if not is_deployable(u):
			continue
		if owner_of(u) != owner_id:
			continue
		var n := String(u.get("name", ""))
		out[n] = int(out.get(n, 0)) + 1
	return out


## Drones and deployables are units of kind "deployable" or "drone" (the net view contract).
static func is_deployable(u: Dictionary) -> bool:
	return String(u.get("kind", "")) in ["deployable", "drone"]


## Owners seen launching a deployable ("deployed" events reach every seat that sees it), for
## enemies whose view has no counters: {deployable id: owner id}.
static var known_owners: Dictionary = {}


## Who a deployable came from: its counters (own side), an "owner" field, or the deploy event.
static func owner_of(u: Dictionary) -> String:
	var o := String((u.get("counters", {}) as Dictionary).get("owner", u.get("owner", "")))
	return o if o != "" else String(known_owners.get(String(u.get("id", "")), ""))


## Weapon ids on a unit that are off the body because they're destroyed: own side from
## counters.weapons[key].destroyed, unscanned enemies from "mounts_lost" (mount indexes; network
## numbers arrive as floats).
static func destroyed_weapons(u: Dictionary) -> Array:
	var states: Dictionary = (u.get("counters", {}) as Dictionary).get("weapons", {})
	var lost := {}
	for m: Variant in u.get("mounts_lost", []):
		lost[int(m)] = true
	var out: Array = []
	for w: Dictionary in (u.get("loadout", {}) as Dictionary).get("weapons", []):
		var st: Variant = states.get(String(w.get("key", "")))
		if (st is Dictionary and bool((st as Dictionary).get("destroyed", false))) or lost.has(int(w.get("mount", -1))):
			out.append(String(w.get("id", "")))
	return out


## Weapons lying on the board after being thrown: {weapon id: [x, y, level]}
## (counters.weapons[key].thrown_at, once the engine tracks Thrown).
static func thrown_weapons(u: Dictionary) -> Dictionary:
	var states: Dictionary = (u.get("counters", {}) as Dictionary).get("weapons", {})
	var out := {}
	for w: Dictionary in (u.get("loadout", {}) as Dictionary).get("weapons", []):
		var st: Variant = states.get(String(w.get("key", "")))
		if st is Dictionary and (st as Dictionary).get("thrown_at") is Array:
			out[String(w.get("id", ""))] = (st as Dictionary)["thrown_at"]
	return out
