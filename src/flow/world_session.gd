class_name WorldSession
extends RefCounted
## Real-time exploring (DESIGN.md "Exploring vs. fighting"), host side and headless: the
## places in play ("areas") and everyone in them. Outside combat there are no turns: pilots on
## foot and mechs move continuously; the host moves them toward where their players asked to
## go, at their speed, over ground they can walk. Players can be in different areas at once.
## A fight in an area turns it to "combat" (an encounter: the rules engine takes over there);
## other areas keep moving. An area can be set to "step" (turn-based exploring, off by
## default) for careful heists and stealth: moves are taken one at a time.
##
## Positions are world x/z (GridLayout.to_world space), so this stays grid-agnostic: the
## area's BattleMap answers which cell a point is in.
##
## Actor: {id, kind: "pilot"/"mech", seat, name, area, pos: Vector2, target: Vector2 or null,
##         speed (spaces per second), order: "follow"/"stay", leader: actor id, ai: bool}
## AI squadmates follow their human (DESIGN, the user: "AI players follow whatever choices
## you make") unless ordered to stay.

signal moved(area_id: String)
signal called(event: Dictionary)

const MODES := ["explore", "combat", "step"]
## Spaces per second while exploring (our pacing, not a rule: outside combat the book has no
## clock). A mech covers ground a little faster than a pilot on foot.
const SPEED := {"pilot": 3.0, "mech": 4.0}
## How close a follower keeps to its leader (spaces).
const FOLLOW_GAP := 1.6
## The most a walker can step up or down between neighboring spaces while exploring.
const MAX_STEP := 1

var areas: Dictionary = {}   # id -> {id, name, map: BattleMap, mode, encounter}
var actors: Dictionary = {}  # id -> actor


func add_area(id: String, map: BattleMap, name: String = "") -> void:
	areas[id] = {"id": id, "name": name if name != "" else id, "map": map, "mode": "explore", "encounter": ""}


func add_actor(d: Dictionary) -> Dictionary:
	var a := {"id": str(d["id"]), "kind": str(d.get("kind", "pilot")), "seat": str(d.get("seat", "")), "name": str(d.get("name", d["id"])),
		"area": str(d.get("area", "")), "pos": d.get("pos", Vector2.ZERO), "target": null,
		"speed": float(d.get("speed", SPEED.get(str(d.get("kind", "pilot")), 3.0))),
		"order": str(d.get("order", "follow")), "leader": str(d.get("leader", "")), "ai": bool(d.get("ai", false))}
	actors[a["id"]] = a
	return a


func actors_in(area_id: String) -> Array:
	return actors.values().filter(func(a: Dictionary) -> bool: return str(a["area"]) == area_id)


## Seats with someone (not AI) in an area: who gets that area's updates.
func seats_in(area_id: String) -> Array:
	var out: Array = []
	for a: Dictionary in actors_in(area_id):
		if not bool(a["ai"]) and str(a["seat"]) != "" and not out.has(a["seat"]):
			out.append(a["seat"])
	return out


## The area a seat's player is in ("" if none).
func area_of(seat: String) -> String:
	for a: Dictionary in actors.values():
		if str(a["seat"]) == seat and not bool(a["ai"]):
			return str(a["area"])
	return ""


## Why `seat` may not move `actor_id` to `to` ("" if it may).
func move_refusal(seat: String, actor_id: String, to: Vector2) -> String:
	var a: Dictionary = actors.get(actor_id, {})
	if a.is_empty():
		return "No one like that."
	if str(a["seat"]) != seat or bool(a["ai"]):
		return "That isn't yours to move."
	var area: Dictionary = areas.get(str(a["area"]), {})
	if area.is_empty():
		return "They aren't anywhere."
	if str(area["mode"]) == "combat":
		return "There's a fight here: moves take turns now."
	if not walkable(area, cell_at(area, to)):
		return "You can't go there."
	return ""


## A player asks their pilot or mech to head somewhere (exploring). In "step" mode the move is
## taken at once, one at a time; otherwise the actor walks there over the next ticks.
func move(seat: String, actor_id: String, to: Vector2) -> String:
	var why := move_refusal(seat, actor_id, to)
	if why != "":
		return why
	var a: Dictionary = actors[actor_id]
	if str(areas[a["area"]]["mode"]) == "step":
		a["pos"] = to
		moved.emit(str(a["area"]))
	else:
		a["target"] = to
	return ""


## Follow (the actor's leader) or stay put: an AI squadmate's standing order.
func set_order(seat: String, actor_id: String, order: String) -> String:
	var a: Dictionary = actors.get(actor_id, {})
	if a.is_empty() or not order in ["follow", "stay"]:
		return "Follow or stay."
	var leader: Dictionary = actors.get(str(a["leader"]), {})
	if str(a["seat"]) != seat and str(leader.get("seat", "")) != seat:
		return "That isn't yours to order."
	a["order"] = order
	if order == "stay":
		a["target"] = null
	return ""


## Moves everyone in exploring areas toward where they're headed (`delta` seconds). Walkers
## stop at ground they can't walk; followers keep near their leader, and change area with it.
func tick(delta: float) -> void:
	var touched := {}
	for a: Dictionary in actors.values():
		var area: Dictionary = areas.get(str(a["area"]), {})
		if area.is_empty() or str(area["mode"]) != "explore":
			continue
		if bool(a["ai"]) and str(a["order"]) == "follow" and actors.has(str(a["leader"])):
			var lead: Dictionary = actors[a["leader"]]
			if str(lead["area"]) != str(a["area"]):
				continue  # travel() brings followers along
			var gap: Vector2 = (lead["pos"] as Vector2) - (a["pos"] as Vector2)
			a["target"] = (a["pos"] as Vector2) + gap.normalized() * (gap.length() - FOLLOW_GAP) if gap.length() > FOLLOW_GAP else null
		if a["target"] == null:
			continue
		var pos: Vector2 = a["pos"]
		var to: Vector2 = a["target"]
		var step := minf(float(a["speed"]) * GridLayout.SPACE * delta, pos.distance_to(to))
		var next := pos + (to - pos).normalized() * step if step > 0.0 else pos
		if not _can_step(area, pos, next):
			a["target"] = null
			continue
		a["pos"] = next
		if next.distance_to(to) < 0.01:
			a["target"] = null
		touched[a["area"]] = true
	for id: String in touched:
		moved.emit(id)


## Puts an actor (and its followers) in another area at `pos`: travel, or being pulled to a
## story event.
func travel(actor_id: String, area_id: String, pos: Vector2) -> String:
	if not actors.has(actor_id) or not areas.has(area_id):
		return "No such place."
	var a: Dictionary = actors[actor_id]
	var from := str(a["area"])
	a["area"] = area_id
	a["pos"] = pos
	a["target"] = null
	var i := 0
	for f: Dictionary in actors.values():
		if bool(f["ai"]) and str(f["leader"]) == actor_id and str(f["order"]) == "follow":
			i += 1
			f["area"] = area_id
			f["pos"] = pos + Vector2(FOLLOW_GAP, 0).rotated(TAU * i / 5.0)
			f["target"] = null
	moved.emit(from)
	moved.emit(area_id)
	return ""


## A major story event pulls everyone to it (story raises it): a prompt for each player
## ("You're being called to X"). They go with go_to_call(); `forced` moves them now.
func call_to(area_id: String, pos: Vector2, reason: String, forced: bool = false) -> Dictionary:
	var e := {"type": "called_to", "area": area_id, "place": str(areas.get(area_id, {}).get("name", area_id)), "pos": pos, "reason": reason,
		"text": "You're being called to %s: %s" % [areas.get(area_id, {}).get("name", area_id), reason]}
	called.emit(e)
	if forced:
		for a: Dictionary in actors.values():
			if not bool(a["ai"]) and str(a["area"]) != area_id:
				travel(str(a["id"]), area_id, pos)
	return e


## Starts or ends a fight in an area (an encounter id from the battle) or switches it to
## turn-based exploring ("step") and back.
func set_mode(area_id: String, mode: String, encounter: String = "") -> void:
	if areas.has(area_id) and mode in MODES:
		areas[area_id]["mode"] = mode
		areas[area_id]["encounter"] = encounter if mode == "combat" else ""
		if mode != "explore":
			for a: Dictionary in actors_in(area_id):
				a["target"] = null
		moved.emit(area_id)


## What a seat sees: its own area and everyone in it (positions only). Other areas stay
## unknown (secrets on the host): only their names and how many of the squad are there.
func view_for(seat: String) -> Dictionary:
	var here := area_of(seat)
	var area: Dictionary = areas.get(here, {})
	var list: Array = []
	for a: Dictionary in actors_in(here):
		list.append({"id": a["id"], "kind": a["kind"], "name": a["name"], "seat": a["seat"], "pos": [snappedf((a["pos"] as Vector2).x, 0.01), snappedf((a["pos"] as Vector2).y, 0.01)],
			"ai": a["ai"], "order": a["order"]})
	var elsewhere := {}
	for a: Dictionary in actors.values():
		if str(a["area"]) != here and not bool(a["ai"]):
			elsewhere[areas.get(str(a["area"]), {}).get("name", a["area"])] = int(elsewhere.get(areas.get(str(a["area"]), {}).get("name", a["area"]), 0)) + 1
	return {"area": here, "name": str(area.get("name", "")), "mode": str(area.get("mode", "")), "encounter": str(area.get("encounter", "")),
		"actors": list, "squad_elsewhere": elsewhere}


static func cell_at(area: Dictionary, p: Vector2) -> Vector2i:
	return (area["map"] as BattleMap).grid.from_world(Vector3(p.x, 0.0, p.y))


static func walkable(area: Dictionary, cell: Vector2i) -> bool:
	var map: BattleMap = area["map"]
	return map.has_cell(cell) and not map.column(cell).has_tag(BattleMap.TAG_IMPASSABLE)


static func _can_step(area: Dictionary, from: Vector2, to: Vector2) -> bool:
	var a := cell_at(area, from)
	var b := cell_at(area, to)
	if a == b:
		return true
	if not walkable(area, b):
		return false
	var map: BattleMap = area["map"]
	return absi(map.ground_height(b) - map.ground_height(a)) <= MAX_STEP


func to_dict() -> Dictionary:
	var ar := {}
	for id: String in areas:
		ar[id] = {"id": id, "name": areas[id]["name"], "map": (areas[id]["map"] as BattleMap).to_dict(), "mode": areas[id]["mode"], "encounter": areas[id]["encounter"]}
	var ac := {}
	for id: String in actors:
		var a: Dictionary = actors[id].duplicate()
		a["pos"] = [(a["pos"] as Vector2).x, (a["pos"] as Vector2).y]
		a["target"] = null
		ac[id] = a
	return {"areas": ar, "actors": ac}


static func from_dict(d: Dictionary) -> WorldSession:
	var w := WorldSession.new()
	for id: String in d.get("areas", {}):
		var a: Dictionary = d["areas"][id]
		w.add_area(id, BattleMap.from_dict(a["map"]), str(a.get("name", id)))
		w.areas[id]["mode"] = str(a.get("mode", "explore"))
		w.areas[id]["encounter"] = str(a.get("encounter", ""))
	for id: String in d.get("actors", {}):
		var a: Dictionary = (d["actors"][id] as Dictionary).duplicate()
		var p: Array = a.get("pos", [0, 0])
		a["pos"] = Vector2(float(p[0]), float(p[1]))
		w.add_actor(a)
	return w
