class_name HubLayout
extends RefCounted
## Where things are in a hub: buildings ("spots") around a central plaza, in meters on the
## ground plane (x, z). Pure data so the host can save it and every player sees the same
## town. HubScene builds the 3D town from this.

const SPOT_NAMES := {
	"bar": ["The Rusty Coupling", "Last Light Cantina", "The Thirsty Frame", "Gravity Well", "The Long Shift", "Coolant & Rye", "The Broken Gyro", "Dust Devil"],
	"office": ["Contract Office", "Liaison Office", "Admin Block", "Comms Hall", "Corporate Annex"],
	"market": ["Night Market", "Salvage Yard", "Trade Hall", "Swap Meet", "The Bazaar"],
	"workshop": ["Hangar Two", "Repair Bay", "Machine Shop", "Rig Garage"],
	"printer": ["Printer Bay", "Fabrication Hall", "Union Printworks", "Supply Depot"],
	"plaza": ["Market Square", "The Commons", "Main Street", "Water Plaza"],
	"landing": ["Mech Gantries", "Landing Pad", "Hardpoint Row"],
}
## kind -> [width, depth, height, color]
const SPOT_LOOK := {
	"bar": [7.0, 6.0, 3.6, Color(0.55, 0.36, 0.24)], "office": [8.0, 6.0, 5.5, Color(0.62, 0.64, 0.66)],
	"market": [9.0, 6.0, 3.0, Color(0.58, 0.5, 0.32)], "workshop": [9.0, 8.0, 6.5, Color(0.46, 0.5, 0.52)],
	"printer": [8.0, 7.0, 7.0, Color(0.7, 0.68, 0.6)], "plaza": [12.0, 12.0, 0.0, Color(0.5, 0.48, 0.44)],
	"landing": [14.0, 10.0, 0.0, Color(0.36, 0.38, 0.4)],
}
const RING := ["bar", "office", "market", "workshop", "printer", "landing"]
const BOUNDS := 30.0


## The buildings for a hub kind, placed around the plaza with a little seeded jitter. `names`
## = a culture kit's building names (cultures.json "spots"), mixed in with the general ones.
## [{id, kind, name, pos: [x, z], size: [w, d, h], color: html, door: [x, z], facing}]
static func spots(kind: String, rng: RandomNumberGenerator, names: Dictionary = {}, door_gap: float = 1.6) -> Array:
	var out: Array = []
	var pool := func(k: String) -> Array: return (names.get(k, []) as Array) + (names.get(k, []) as Array) + (SPOT_NAMES[k] as Array) if names.has(k) else SPOT_NAMES[k]
	var plaza_name := _pick(rng, pool.call("plaza"))
	out.append(_spot("plaza", plaza_name, Vector2.ZERO, 0.0, door_gap))
	# No two towns alike: the buildings come in their own order around the square, unevenly
	# spaced (a wide gap where the road comes in), at their own distances and sizes.
	var order := RING.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: Variant = order[i]
		order[i] = order[j]
		order[j] = t
	if kind == "station":
		order.erase("landing")
		order.append("landing")
	var start := rng.randf_range(0.0, TAU)
	var gap := rng.randf_range(0.0, 0.9)  # extra room after one building: the way in
	var gap_at := rng.randi_range(0, order.size() - 1)
	var step := (TAU - gap) / order.size()
	var a := start
	for i in range(order.size()):
		var r := rng.randf_range(14.0, 21.0)
		var pos := Vector2(cos(a), sin(a)) * r
		var spot := _spot(order[i], _pick(rng, pool.call(order[i])), pos, a, door_gap)
		if order[i] != "landing":
			var sz: Array = spot["size"]
			var k := rng.randf_range(0.82, 1.22)
			spot["size"] = [snappedf(float(sz[0]) * k, 0.1), snappedf(float(sz[1]) * rng.randf_range(0.85, 1.15), 0.1), snappedf(float(sz[2]) * rng.randf_range(0.85, 1.3), 0.1)]
			# The door stays just outside the (resized) front.
			var inward := -Vector2(cos(a), sin(a))
			var door := pos + inward * (float(spot["size"][1]) / 2.0 + door_gap)
			spot["door"] = [door.x, door.y]
		out.append(spot)
		a += step + rng.randf_range(-0.12, 0.12) + (gap if i == gap_at else 0.0)
	return out


static func _spot(kind: String, name: String, pos: Vector2, angle: float, door_gap: float = 1.6) -> Dictionary:
	var look: Array = SPOT_LOOK[kind]
	# The door faces the plaza; NPCs stand just outside it.
	var inward := -Vector2(cos(angle), sin(angle)) if pos != Vector2.ZERO else Vector2.ZERO
	var door := pos + inward * (float(look[1]) / 2.0 + door_gap)
	return {"id": kind, "kind": kind, "name": name, "pos": [pos.x, pos.y], "size": [look[0], look[1], look[2]],
		"color": (look[3] as Color).to_html(false), "door": [door.x, door.y], "facing": angle}


## Where an NPC with this spot kind stands (by the door; a little spread when several share it).
static func npc_position(hub: Dictionary, spot_kind: String, index: int) -> Vector2:
	for s: Dictionary in hub.get("spots", []):
		if str(s["kind"]) == spot_kind and spot_kind != "plaza":
			var d := Vector2(float(s["door"][0]), float(s["door"][1]))
			var side := Vector2(-d.y, d.x).normalized() if d.length() > 0.01 else Vector2.RIGHT
			return d + side * [0.0, 2.2, -2.2, 4.4][index % 4]
	# The plaza, or no such building: stand around the plaza, between the roads.
	var a := 0.45 + index * 2.4
	return Vector2(cos(a), sin(a)) * 5.2


static func spot_named(hub: Dictionary, kind: String) -> Dictionary:
	for s: Dictionary in hub.get("spots", []):
		if str(s["kind"]) == kind:
			return s
	return {}


static func _pick(rng: RandomNumberGenerator, arr: Array) -> String:
	return str(arr[rng.randi_range(0, arr.size() - 1)])
