class_name HubInterior
extends RefCounted
## Inside a hub's buildings (world's Interiors kit, our story's rooms). Plain data, no nodes:
## hub_scene builds the 3D room from `plan.layout` with Interiors.build and walks the squad
## through it, and every move between rooms still goes through the StoryEngine's town
## actions (go, sneak, pick_lock, break_in, take: TownLife), so schedules, locks, witnesses and
## sneaking work the same inside as out.
##
## Which interior a building has, and how its rooms map onto TownLife's (spot, room), comes
## from town_life.json "interiors" (by spot kind, with a different kind per culture: an old-west
## office is the marshal's), overridden per hub by story.hub["interiors"] (a campaign world's
## own: the Saint Cadence is one ship's deck behind every door; the Long Arrival's dock has the
## sleeper vault). A room maps to a room of the same building ("back") or to [spot, room] (a
## ship's deck spans the bridge, the mess and engineering).
##
##   plan(story, spot_id) -> {spot, kind, layout, rooms: {iroom: [spot, room]}, entry,
##     npcs: [{id, room, pos, facing, asleep}], items: [{id, room, container, pos}],
##     doors: [{id, rooms, pos, outside, locked, lock}]}

static func defaults() -> Dictionary:
	return TownLife.data().get("interiors", {})


## The interior spec for the building at `spot_id`, or {} if it has none.
static func spec(story: StoryState, spot_id: String) -> Dictionary:
	var kind := TownLife.spot_kind(story, spot_id)
	var own: Dictionary = story.hub.get("interiors", {})
	var s: Dictionary = own.get(kind, {})
	if s.has("same_as"):
		s = own.get(str(s["same_as"]), {})
	if s.is_empty():
		s = defaults().get("spots", {}).get(kind, {})
	if s.is_empty():
		return {}
	s = s.duplicate(true)
	var culture := str(story.hub.get("culture", ""))
	if s.get("kinds_by_culture", {}).has(culture):
		s["kind"] = str(s["kinds_by_culture"][culture])
	return s


static func has_interior(story: StoryState, spot_id: String) -> bool:
	return not spec(story, spot_id).is_empty()


## [spot, room] in TownLife terms for one interior room.
static func _story_room(spot_id: String, v: Variant) -> Array:
	if v is Array:
		return [str(v[0]), str(v[1])]
	return [spot_id, str(v)]


static func plan(story: StoryState, spot_id: String) -> Dictionary:
	var s := spec(story, spot_id)
	if s.is_empty():
		return {}
	var lay := Interiors.layout(str(s["kind"]), str(story.hub.get("culture", "")), int(story.hub.get("seed", 0)))
	if lay.is_empty():
		return {}
	var rooms := {}
	for ir: String in lay["rooms"]:
		if (s.get("rooms", {}) as Dictionary).has(ir):
			rooms[ir] = _story_room(spot_id, s["rooms"][ir])
	var out := {"spot": spot_id, "kind": s["kind"], "layout": lay, "rooms": rooms, "npcs": [], "items": [], "doors": []}
	# The way in from outside.
	for d: Dictionary in lay["doors"]:
		var rs: Array = d["rooms"]
		var outside: bool = rs.has("outside")
		var rec := {"id": d["id"], "rooms": rs.duplicate(), "pos": d["pos"], "outside": outside, "lock": int(d.get("lock", 0)), "width": float(d.get("width", 1.1))}
		out["doors"].append(rec)
		if outside and not out.has("entry"):
			out["entry"] = str(rs[1] if rs[0] == "outside" else rs[0])
	refresh(story, out)
	return out


## Who's where and what's locked, from the story as it is now (call again after time passes).
static func refresh(story: StoryState, p: Dictionary) -> void:
	var lay: Dictionary = p["layout"]
	# Doors: one into a private story room that's locked and not yet opened is shut to you.
	for d: Dictionary in p["doors"]:
		d["locked"] = false
		for r: String in d["rooms"]:
			if r == "outside" or not p["rooms"].has(r):
				continue
			if door_locked(story, p, d, r):
				d["locked"] = true
	# People: in the interior room their schedule puts them in (sleeping in a bed if asleep).
	p["npcs"] = []
	var used := {}
	for id: String in story.hub.get("npcs", []):
		var npc: Dictionary = story.npcs.get(id, {})
		if npc.is_empty() or bool(npc.get("dead", false)):
			continue
		var w := TownLife.where_npc(story, id)
		if bool(w["out"]):
			continue
		var ir := room_for(p, str(w["spot"]), str(w["room"]))
		if ir == "":
			continue
		var asleep := bool(w["asleep"])
		var spot_pos := _free_point(lay, ir, "sleep" if asleep else "stand", used)
		p["npcs"].append({"id": id, "room": ir, "pos": spot_pos["pos"], "facing": float(spot_pos.get("facing", 0.0)), "asleep": asleep})
	# Things kept here: in the room's container if it has one, else on a surface in the room.
	p["items"] = []
	for it: Dictionary in (story.flags.get("_items", {}) as Dictionary).values():
		if str(it.get("kept", "")) != "room" or str(it.get("holder", "")) != "":
			continue
		var ir := room_for(p, str(it.get("spot", "")), str(it.get("room", "")))
		var container := ""
		for c: String in (spec(story, str(p["spot"])).get("containers", {}) as Dictionary):
			var cr := _story_room(str(p["spot"]), spec(story, str(p["spot"]))["containers"][c])
			if cr[0] == str(it.get("spot", "")) and cr[1] == str(it.get("room", "")):
				container = c
		var pos: Variant = null
		for c: Dictionary in lay["containers"]:
			if str(c["id"]) == container:
				pos = c["pos"]
				ir = str(c["room"])
		if ir == "":
			continue
		if pos == null:
			pos = _free_point(lay, ir, "work", used)["pos"]
		p["items"].append({"id": it["id"], "name": it["name"], "room": ir, "container": container, "pos": pos})


## Whether the door into interior room `r` is locked to the squad right now: the story's room
## has a lock and hasn't been opened (picked, forced, or a key used). Public rooms never are.
static func door_locked(story: StoryState, p: Dictionary, d: Dictionary, r: String) -> bool:
	if int(d.get("lock", 0)) <= 0 or not p["rooms"].has(r):
		return false
	var sr: Array = p["rooms"][r]
	var info := TownLife.room_info(TownLife.spot_kind(story, str(sr[0])), str(sr[1]))
	if bool(info.get("public", false)) or int(info.get("lock", 0)) <= 0:
		return false
	# Going deeper into a building you're already allowed in (the owner's upstairs from the
	# landing): only the story room's own door is locked.
	for other: String in d["rooms"]:
		if other != r and other != "outside" and p["rooms"].get(other, []) == sr:
			return false
	return not TownLife.is_open(story, str(sr[0]), str(sr[1]))


## The interior room for a story (spot, room): the first that maps to it, else the first room
## of the same spot (a room the interior doesn't draw separately), else "".
static func room_for(p: Dictionary, spot: String, room: String) -> String:
	var fallback := ""
	var order: Array = (p["layout"]["rooms"] as Dictionary).keys()
	for ir: String in order:
		if not p["rooms"].has(ir):
			continue
		var sr: Array = p["rooms"][ir]
		if sr[0] == spot and sr[1] == room:
			return ir
		if sr[0] == spot and fallback == "":
			fallback = ir
	return fallback


static func _free_point(lay: Dictionary, room: String, want: String, used: Dictionary) -> Dictionary:
	var list: Array = lay.get("sleep", []) if want == "sleep" else lay.get("points", [])
	for i in range(list.size()):
		var pt: Dictionary = list[i]
		var key := "%s:%d" % [want, i]
		if str(pt.get("room", "")) != room or used.has(key):
			continue
		if want != "sleep" and str(pt.get("type", "")) == "hide":
			continue
		used[key] = true
		return pt
	var r: Dictionary = lay["rooms"][room]
	var rc: Array = r["rect"]
	var n := int(used.get(room, 0))
	used[room] = n + 1
	var y := float(int(r.get("floor", 0))) * float(lay.get("floor_height", 3.2))
	return {"pos": [float(rc[0]) + float(rc[2]) * (0.3 + 0.2 * (n % 3)), y, float(rc[1]) + float(rc[3]) * 0.5], "facing": 0.0}


# --- Walking inside ------------------------------------------------------------------------

## The interior room at a point on a floor ("" if it's in a wall or outside).
static func room_at(p: Dictionary, at: Vector2, floor_i: int, margin: float = 0.25) -> String:
	var rooms: Dictionary = p["layout"]["rooms"]
	for id: String in rooms:
		var r: Dictionary = rooms[id]
		if int(r.get("floor", 0)) != floor_i:
			continue
		var rc: Array = r["rect"]
		var rect := Rect2(float(rc[0]) + margin, float(rc[1]) + margin, float(rc[2]) - margin * 2.0, float(rc[3]) - margin * 2.0)
		if rect.has_point(at):
			return id
	return ""


## The door between two rooms (or a room and outside) near a point, or {}.
static func door_near(p: Dictionary, at: Vector2, floor_y: float, reach: float = 1.0) -> Dictionary:
	var best := {}
	var best_d := reach
	for d: Dictionary in p["doors"]:
		var dp := Vector2(float(d["pos"][0]), float(d["pos"][2]))
		if absf(float(d["pos"][1]) - floor_y) > 1.0:
			continue
		var dist := dp.distance_to(at)
		if dist < best_d:
			best_d = dist
			best = d
	return best


## The stair a point stands on, and how far up it is (0..1), or {}.
static func on_stair(p: Dictionary, at: Vector2) -> Dictionary:
	for s: Dictionary in p["layout"].get("stairs", []):
		var a := Vector2(float(s["start"][0]), float(s["start"][1]))
		var b := Vector2(float(s["end"][0]), float(s["end"][1]))
		var ab := b - a
		var t := (at - a).dot(ab) / maxf(ab.length_squared(), 0.01)
		var side := absf((at - a).cross(ab.normalized()))
		if t >= -0.05 and t <= 1.05 and side <= float(s.get("width", 1.2)) * 0.5 + 0.1:
			return {"stair": s, "t": clampf(t, 0.0, 1.0)}
	return {}


## The TownLife action that walking from interior room `from` into `to` means: nothing (same
## story room), "go" (a public room, or one already opened), "sneak" while sneaking, or
## "locked" when the door is shut to you.
static func step_action(story: StoryState, p: Dictionary, from: String, to: String, door: Dictionary, sneaking: bool) -> String:
	if to == "" or from == to:
		return ""
	var a: Array = p["rooms"].get(from, [])
	var b: Array = p["rooms"].get(to, [])
	if b.is_empty() or a == b:
		return ""
	if not door.is_empty() and bool(door.get("locked", false)):
		return "locked"
	var info := TownLife.room_info(TownLife.spot_kind(story, str(b[0])), str(b[1]))
	return "sneak" if sneaking and not bool(info.get("public", false)) else "go"
