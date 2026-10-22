class_name Interiors
extends RefCounted
## Insides of key buildings, walked through on foot and seen at eye height. One shared kit:
## data/game/interiors.json lays out each kind's rooms, doors, stairs and extra containers;
## the furniture comes from each room's `use` (FURNISH below), so a new kind is only data.
##
##   Interiors.layout(kind, culture, seed) -> Dictionary  (plain data for story, no nodes)
##     {kind, name, size, floors, floor_height,
##      rooms: {id: {name, floor, rect [x0, z0, w, d], use, public}},
##      doors: [{id, rooms [a, b], pos [x, y, z], axis "x"|"z", width, lock, kind}],
##      containers: [{id, room, kind, pos, lock, contents []}],
##      sleep: [{room, pos, kind}],   points: [{type stand|sit|work|hide, room, pos, facing}],
##      stairs: [...], furniture: [{kind, room, pos, size, yaw}]}
##   Interiors.build(layout, culture) -> Node3D   (walls with doorways, floors, ceilings named
##     "Ceiling" so a camera can hide them, stairs, furniture, doors "Door_<id>", lights)
##   Interiors.set_door(root, id, open)
## Meters; origin at the footprint center, front door toward +Z. Lock 0 a latch, 1 a key or a
## pick, 2 hard (Core p.26: Hack or Fix). Story fills `contents` and decides what's locked.

const FILE := "res://data/game/interiors.json"
const WALL := 0.16
const DOOR_H := 2.2
const CLEAR := 1.3  # kept free in front of every door

static var _data: Dictionary = {}


static func kinds() -> Array:
	return _load().keys().filter(func(k: String) -> bool: return not k.begins_with("_"))


static func _load() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		_data = d if d is Dictionary else {}
	return _data


# --- Layout (data) --------------------------------------------------------------------------

static func layout(kind: String, culture: String = "", seed_value: int = 0) -> Dictionary:
	var src: Dictionary = _load().get(kind, {})
	if src.is_empty():
		return {}
	var fh := float(src.get("floor_height", 3.2))
	var out := {"kind": kind, "name": src.get("name", kind), "size": src.get("size", [10.0, 8.0]), "floors": int(src.get("floors", 1)),
		"floor_height": fh, "ship": bool(src.get("ship", false)), "culture": culture,
		"rooms": (src.get("rooms", {}) as Dictionary).duplicate(true), "doors": [], "containers": [], "sleep": [], "points": [],
		"stairs": (src.get("stairs", []) as Array).duplicate(true), "furniture": []}
	var rooms: Dictionary = out["rooms"]
	for id: String in rooms:
		var r: Dictionary = rooms[id]
		r["public"] = bool(r.get("public", false))
		r["floor"] = int(r.get("floor", 0))
	var i := 0
	for d: Dictionary in src.get("doors", []):
		var rs: Array = d["rooms"]
		var inside: String = rs[1] if rs[0] == "outside" else rs[0]
		var y := float(int((rooms.get(inside, {}) as Dictionary).get("floor", 0))) * fh
		var axis := _door_axis(d, rooms.get(inside, {}))
		out["doors"].append({"id": "door_%d" % i, "rooms": rs.duplicate(), "pos": [float(d["at"][0]), y, float(d["at"][1])], "axis": axis,
			"width": float(d.get("width", 1.1)), "lock": int(d.get("lock", 0)), "kind": str(d.get("kind", "hatch" if out["ship"] else "door"))})
		i += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([kind, culture, seed_value])
	for id: String in rooms:
		_furnish(out, id, rng)
	for c: Dictionary in src.get("containers", []):
		var room: Dictionary = rooms.get(str(c["room"]), {})
		if room.is_empty():
			continue
		var at := _free_spot(out, str(c["room"]), Vector2(0.7, 0.6), rng, true)
		_piece(out, str(c["kind"]), str(c["room"]), at, Vector3(0.7, 0.9 if c["kind"] != "safe" else 1.0, 0.6), _wall_yaw(room, at))
		out["containers"].append({"id": str(c["id"]), "room": str(c["room"]), "kind": str(c["kind"]), "pos": _pos3(out, str(c["room"]), at),
			"lock": int(c.get("lock", 1)), "contents": []})
	return out


## Which way a door's wall runs: "x" if the doorway lies on a wall along x (z fixed).
static func _door_axis(d: Dictionary, room: Dictionary) -> String:
	if room.is_empty():
		return "x"
	var rc: Array = room["rect"]
	var z := float(d["at"][1])
	return "x" if absf(z - float(rc[1])) < 0.05 or absf(z - float(rc[1]) - float(rc[3])) < 0.05 else "z"


static func _pos3(out: Dictionary, room: String, at: Vector2) -> Array:
	var f := int((out["rooms"][room] as Dictionary)["floor"])
	return [at.x, f * float(out["floor_height"]), at.y]


## Facing away from the nearest wall of the room (radians about +Y; 0 faces +Z).
static func _wall_yaw(room: Dictionary, at: Vector2) -> float:
	var rc: Array = room["rect"]
	var d := [at.x - float(rc[0]), float(rc[0]) + float(rc[2]) - at.x, at.y - float(rc[1]), float(rc[1]) + float(rc[3]) - at.y]
	var m := d.find(d.min())
	return [PI * 0.5, -PI * 0.5, 0.0, PI][m]


static func _piece(out: Dictionary, kind: String, room: String, at: Vector2, size: Vector3, yaw: float = 0.0) -> void:
	out["furniture"].append({"kind": kind, "room": room, "pos": _pos3(out, room, at), "size": [size.x, size.y, size.z], "yaw": yaw})


static func _point(out: Dictionary, type: String, room: String, at: Vector2, facing: float = 0.0) -> void:
	out["points"].append({"type": type, "room": room, "pos": _pos3(out, room, at), "facing": facing})


## A spot inside the room clear of doors, stairs and furniture; against a wall if asked.
static func _free_spot(out: Dictionary, room: String, half: Vector2, rng: RandomNumberGenerator, by_wall: bool) -> Vector2:
	var rc: Array = (out["rooms"][room] as Dictionary)["rect"]
	var x0 := float(rc[0]) + half.x + WALL
	var x1 := float(rc[0]) + float(rc[2]) - half.x - WALL
	var z0 := float(rc[1]) + half.y + WALL
	var z1 := float(rc[1]) + float(rc[3]) - half.y - WALL
	for t in range(120):
		var p := Vector2(rng.randf_range(x0, x1), rng.randf_range(z0, z1))
		if by_wall and t < 80:  # against a wall if there's room, else anywhere free
			match rng.randi_range(0, 3):
				0: p.x = x0
				1: p.x = x1
				2: p.y = z0
				_: p.y = z1
		if _clear(out, room, p, half):
			return p
	return Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5)


static func _clear(out: Dictionary, room: String, p: Vector2, half: Vector2) -> bool:
	var f := int((out["rooms"][room] as Dictionary)["floor"])
	var me := Rect2(p - half, half * 2.0)
	for d: Dictionary in out["doors"]:
		var dp: Array = d["pos"]
		if absf(float(dp[1]) - f * float(out["floor_height"])) > 0.1:
			continue
		if me.intersects(Rect2(Vector2(float(dp[0]), float(dp[2])) - Vector2.ONE * CLEAR, Vector2.ONE * CLEAR * 2.0)):
			return false
	for s: Dictionary in out["stairs"]:
		if me.intersects(_stair_rect(s).grow(0.4)):
			return false
	for fu: Dictionary in out["furniture"]:
		if fu["room"] != room:
			continue
		var fp: Array = fu["pos"]
		var fs: Array = fu["size"]
		if me.intersects(Rect2(Vector2(float(fp[0]) - float(fs[0]) * 0.5, float(fp[2]) - float(fs[2]) * 0.5), Vector2(float(fs[0]), float(fs[2]))).grow(0.25)):
			return false
	return true


static func _stair_rect(s: Dictionary) -> Rect2:
	var a := Vector2(float(s["start"][0]), float(s["start"][1]))
	var b := Vector2(float(s["end"][0]), float(s["end"][1]))
	var half := float(s.get("width", 1.2)) * 0.5
	var r := Rect2(a, Vector2.ZERO).expand(b)
	# Widen across the run: along x the stair spans z +-half, along z it spans x +-half.
	return r.grow_individual(0.0, half, 0.0, half) if absf(b.x - a.x) > absf(b.y - a.y) else r.grow_individual(half, 0.0, half, 0.0)


## Furniture, sleep spots and NPC points by the room's use.
static func _furnish(out: Dictionary, id: String, rng: RandomNumberGenerator) -> void:
	var room: Dictionary = out["rooms"][id]
	var rc: Array = room["rect"]
	var r := Rect2(float(rc[0]), float(rc[1]), float(rc[2]), float(rc[3]))
	var c := r.get_center()
	match str(room.get("use", "")):
		"bar":
			# The counter along the left wall, a back shelf behind it, tables and chairs.
			var cx := r.position.x + 1.6
			var cz0 := r.position.y + 0.6
			var len := minf(r.size.y - 1.6, 4.4)
			_piece(out, "counter", id, Vector2(cx, cz0 + len * 0.5), Vector3(0.6, 1.1, len), PI * 0.5)
			_piece(out, "shelf", id, Vector2(r.position.x + 0.35, cz0 + len * 0.5), Vector3(0.4, 2.0, len), PI * 0.5)
			_point(out, "work", id, Vector2(cx - 0.8, cz0 + len * 0.5), PI * 0.5)
			_point(out, "hide", id, Vector2(cx - 0.55, cz0 + 0.5), PI * 0.5)
			for k in range(4):
				_point(out, "stand", id, Vector2(cx + 0.75, cz0 + 0.6 + k * len / 4.0), -PI * 0.5)
			var tx := r.position.x + 4.2
			while tx < r.end.x - 1.2:
				var tz := r.position.y + 1.4
				while tz < r.end.y - 1.2:
					var p := Vector2(tx, tz)
					if _clear(out, id, p, Vector2(1.0, 1.0)):
						_table(out, id, p)
					tz += 2.6
				tx += 2.8
		"bedroom":
			var bed := _free_spot(out, id, Vector2(0.55, 1.05), rng, true)
			_piece(out, "bed", id, bed, Vector3(1.1, 0.55, 2.0), _wall_yaw(room, bed))
			out["sleep"].append({"room": id, "pos": _pos3(out, id, bed), "kind": "bed"})
			var chest := _free_spot(out, id, Vector2(0.45, 0.3), rng, true)
			_piece(out, "chest", id, chest, Vector3(0.9, 0.55, 0.55), _wall_yaw(room, chest))
			out["containers"].append({"id": id + "_chest", "room": id, "kind": "chest", "pos": _pos3(out, id, chest), "lock": 1, "contents": []})
			var ward := _free_spot(out, id, Vector2(0.5, 0.3), rng, true)
			_piece(out, "wardrobe", id, ward, Vector3(1.0, 2.0, 0.6), _wall_yaw(room, ward))
			_point(out, "hide", id, ward, _wall_yaw(room, ward))  # inside the wardrobe
			var chair := _free_spot(out, id, Vector2(0.3, 0.3), rng, false)
			_piece(out, "chair", id, chair, Vector3(0.5, 0.9, 0.5), rng.randf() * TAU)
			_point(out, "sit", id, chair, 0.0)
		"storage":
			for k in range(int(r.get_area() / 4.0)):
				var p := _free_spot(out, id, Vector2(0.4, 0.4), rng, rng.randf() < 0.7)
				var kind := "crate" if rng.randf() < 0.55 else "barrel"
				_piece(out, kind, id, p, Vector3(0.8, 0.8, 0.8) if kind == "crate" else Vector3(0.6, 0.9, 0.6), rng.randf() * TAU)
				if k == 0:
					_point(out, "hide", id, p + Vector2(0.6, 0.0), 0.0)
			var t := _free_spot(out, id, Vector2(1.0, 1.0), rng, false)
			_table(out, id, t)
		"office", "study":
			var desk := _free_spot(out, id, Vector2(0.9, 0.45), rng, true)
			var yaw := _wall_yaw(room, desk)
			_piece(out, "desk", id, desk, Vector3(1.8, 0.78, 0.9), yaw)
			var front := desk + Vector2(sin(yaw), cos(yaw)) * 0.8
			_piece(out, "chair", id, front, Vector3(0.5, 0.9, 0.5), yaw + PI)
			_point(out, "work", id, front, yaw + PI)
			_point(out, "hide", id, desk - Vector2(sin(yaw), cos(yaw)) * 0.1, yaw)  # crouched behind the desk
			for k in range(2 if room["use"] == "office" else 1):
				var cab := _free_spot(out, id, Vector2(0.3, 0.3), rng, true)
				_piece(out, "cabinet", id, cab, Vector3(0.6, 1.3, 0.5), _wall_yaw(room, cab))
			if room["use"] == "office":
				var bench := _free_spot(out, id, Vector2(0.9, 0.25), rng, true)
				_piece(out, "bench", id, bench, Vector3(1.8, 0.45, 0.45), _wall_yaw(room, bench))
				_point(out, "sit", id, bench, _wall_yaw(room, bench))
				_point(out, "stand", id, c, 0.0)
		"cell":
			var cot := Vector2(r.position.x + 0.5, c.y - 0.4)
			_piece(out, "cot", id, cot, Vector3(0.8, 0.45, 1.9), PI * 0.5)
			out["sleep"].append({"room": id, "pos": _pos3(out, id, cot), "kind": "cot"})
			_piece(out, "bucket", id, Vector2(r.end.x - 0.4, r.position.y + 0.4), Vector3(0.35, 0.4, 0.35))
			_point(out, "sit", id, cot, PI * 0.5)
		"bridge":
			# Console banks facing forward (+X), the command chair behind them, a big screen.
			for k in range(3):
				var p := Vector2(r.end.x - 1.4, r.position.y + 2.5 + k * (r.size.y - 5.0) / 2.0)
				_piece(out, "console", id, p, Vector3(0.8, 1.0, 2.2), -PI * 0.5)
				_point(out, "work", id, p - Vector2(0.9, 0.0), -PI * 0.5)
			_piece(out, "screen", id, Vector2(r.end.x - 0.2, c.y), Vector3(0.1, 2.0, r.size.y - 3.0), -PI * 0.5)
			var chair := Vector2(c.x - 0.6, c.y)
			_piece(out, "command_chair", id, chair, Vector3(0.9, 1.3, 0.9), -PI * 0.5)
			_point(out, "sit", id, chair, -PI * 0.5)
			_point(out, "hide", id, Vector2(r.end.x - 2.1, r.position.y + 1.3), -PI * 0.5)
		"captain":
			_furnish_as(out, id, rng, "bedroom")
			var desk := _free_spot(out, id, Vector2(0.8, 0.4), rng, true)
			_piece(out, "desk", id, desk, Vector3(1.6, 0.78, 0.8), _wall_yaw(room, desk))
			_point(out, "work", id, desk + Vector2(sin(_wall_yaw(room, desk)), cos(_wall_yaw(room, desk))) * 0.8, _wall_yaw(room, desk) + PI)
		"bunks":
			var x := r.position.x + 0.7
			while x < r.end.x - 0.6:
				for zz: float in [r.position.y + 1.1, r.end.y - 1.1]:
					var p := Vector2(x, zz)
					if _clear(out, id, p, Vector2(0.5, 1.0)):
						_piece(out, "bunk", id, p, Vector3(0.95, 1.9, 2.0))
						out["sleep"].append({"room": id, "pos": _pos3(out, id, p), "kind": "bunk"})
						out["sleep"].append({"room": id, "pos": [p.x, float(_pos3(out, id, p)[1]) + 1.1, p.y], "kind": "bunk"})
						_piece(out, "locker", id, p + Vector2(0.75, 0.0), Vector3(0.45, 1.9, 0.5))
						out["containers"].append({"id": "%s_locker_%d" % [id, out["containers"].size()], "room": id, "kind": "locker",
							"pos": _pos3(out, id, p + Vector2(0.75, 0.0)), "lock": 1, "contents": []})
				x += 1.9
			_point(out, "stand", id, c, 0.0)
		"commons":
			# Market stalls along one wall, mess tables in the middle.
			var x := r.position.x + 1.4
			while x < r.end.x - 1.2:
				var p := Vector2(x, r.position.y + 0.8)
				if _clear(out, id, p, Vector2(0.9, 0.5)):
					_piece(out, "stall", id, p, Vector3(1.8, 1.0, 0.9))
					_point(out, "work", id, p, 0.0)
					_point(out, "stand", id, p + Vector2(0.0, 1.0), PI)
				x += 2.4
			var tx := r.position.x + 2.0
			while tx < r.end.x - 1.2:
				var p := Vector2(tx, c.y + 1.0)
				if _clear(out, id, p, Vector2(1.0, 1.0)):
					_table(out, id, p)
				tx += 3.0
		"engineering":
			# The reactor drum, and the ship's NHP casing in its cradle, consoles by both.
			var core := Vector2(r.position.x + 3.0, c.y)
			_piece(out, "reactor", id, core, Vector3(2.4, 2.8, 2.4))
			var nhp := Vector2(r.end.x - 2.6, c.y)
			_piece(out, "nhp_core", id, nhp, Vector3(1.4, 1.6, 1.4))
			for p: Vector2 in [core + Vector2(0.0, 2.0), nhp + Vector2(-1.6, 0.0)]:
				if _clear(out, id, p, Vector2(0.5, 0.4)):
					_piece(out, "console", id, p, Vector3(1.0, 1.0, 0.6))
					_point(out, "work", id, p + Vector2(0.0, 0.7), PI)
			_piece(out, "pipes", id, Vector2(c.x, r.end.y - 0.3), Vector3(r.size.x - 0.6, 0.5, 0.3))  # along the hull side
			_point(out, "hide", id, core + Vector2(0.0, -1.6), 0.0)
		"cargo":
			var x := r.position.x + 1.0
			while x < r.end.x - 1.0:
				for zz: float in [r.position.y + 1.0, r.end.y - 1.0]:
					var p := Vector2(x, zz)
					if _clear(out, id, p, Vector2(0.75, 0.75)) and rng.randf() < 0.8:
						var hi := 1.2 if rng.randf() < 0.6 else 2.4
						_piece(out, "cargo_crate", id, p, Vector3(1.5, hi, 1.5))
				x += 2.0
			_point(out, "hide", id, Vector2(r.position.x + 2.0, c.y), 0.0)
		"sleepers":
			# Rows of cryo pods with a walkway between, each pod a sleeper (a sleep spot).
			var x := r.position.x + 1.6
			while x < r.end.x - 1.2:
				for zz: float in [r.position.y + 1.6, c.y - 1.2, c.y + 2.2, r.end.y - 1.6]:
					var p := Vector2(x, zz)
					if _clear(out, id, p, Vector2(0.6, 1.1)):
						_piece(out, "cryo_pod", id, p, Vector3(1.0, 1.1, 2.1))
						out["sleep"].append({"room": id, "pos": _pos3(out, id, p), "kind": "pod"})
				x += 1.8
			_point(out, "hide", id, Vector2(r.position.x + 0.8, c.y), 0.0)
		"control":
			var x := r.position.x + 2.0
			while x < r.end.x - 1.5:
				var p := Vector2(x, r.position.y + 0.5)
				if _clear(out, id, p, Vector2(0.6, 0.3)):
					_piece(out, "console", id, p, Vector3(1.2, 1.0, 0.5))
					_point(out, "work", id, p + Vector2(0.0, 0.7), PI)
				x += 3.0
		"stairs", "landing", "corridor":
			pass


static func _furnish_as(out: Dictionary, id: String, rng: RandomNumberGenerator, use: String) -> void:
	var room: Dictionary = out["rooms"][id]
	var keep := str(room["use"])
	room["use"] = use
	_furnish(out, id, rng)
	room["use"] = keep


static func _table(out: Dictionary, id: String, p: Vector2) -> void:
	_piece(out, "table", id, p, Vector3(1.0, 0.76, 1.0))
	for k in range(4):
		var a := k * PI * 0.5
		var q := p + Vector2(sin(a), cos(a)) * 0.75
		_piece(out, "chair", id, q, Vector3(0.45, 0.9, 0.45), a + PI)
		_point(out, "sit", id, q, a + PI)


# --- Build (nodes) --------------------------------------------------------------------------

## Materials by culture: walls, floor, trim, and the light color.
static func _look(lay: Dictionary) -> Dictionary:
	if bool(lay.get("ship", false)):
		return {"wall": Color(0.42, 0.44, 0.47), "floor": Color(0.24, 0.25, 0.27), "trim": Color(0.6, 0.62, 0.65), "wood": Color(0.35, 0.36, 0.38),
			"cloth": Color(0.3, 0.36, 0.42), "light": Color(0.85, 0.92, 1.0), "metal": 0.6}
	var c := WorldKits.culture_id(str(lay.get("culture", "")))
	match c:
		"medieval":
			return {"wall": Color(0.62, 0.58, 0.52), "floor": Color(0.38, 0.28, 0.2), "trim": Color(0.3, 0.22, 0.15), "wood": Color(0.4, 0.28, 0.18),
				"cloth": Color(0.5, 0.18, 0.15), "light": Color(1.0, 0.72, 0.42), "metal": 0.0}
		"cyberpunk":
			return {"wall": Color(0.18, 0.18, 0.22), "floor": Color(0.12, 0.12, 0.14), "trim": Color(0.9, 0.2, 0.6), "wood": Color(0.2, 0.2, 0.24),
				"cloth": Color(0.25, 0.1, 0.3), "light": Color(0.9, 0.5, 1.0), "metal": 0.5}
		"union", "retro":
			return {"wall": Color(0.86, 0.86, 0.84), "floor": Color(0.55, 0.56, 0.58), "trim": Color(0.4, 0.75, 0.8), "wood": Color(0.6, 0.6, 0.62),
				"cloth": Color(0.3, 0.5, 0.6), "light": Color(1.0, 0.96, 0.9), "metal": 0.3}
		"east_asian":
			return {"wall": Color(0.85, 0.8, 0.7), "floor": Color(0.5, 0.36, 0.24), "trim": Color(0.55, 0.12, 0.1), "wood": Color(0.45, 0.3, 0.2),
				"cloth": Color(0.6, 0.2, 0.2), "light": Color(1.0, 0.75, 0.5), "metal": 0.0}
		_:
			# Old West and frontier: planks and plaster.
			return {"wall": Color(0.62, 0.48, 0.34), "floor": Color(0.42, 0.3, 0.2), "trim": Color(0.28, 0.2, 0.13), "wood": Color(0.45, 0.31, 0.2),
				"cloth": Color(0.5, 0.2, 0.15), "light": Color(1.0, 0.76, 0.45), "metal": 0.0}


static func build(lay: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Interior_" + str(lay.get("kind", ""))
	if lay.is_empty():
		return root
	var look := _look(lay)
	var metal := float(look["metal"])
	var wall_m := MeshKit.paint(look["wall"], metal, 0.75, 0.25 if metal > 0.0 else 0.0)
	var floor_m := MeshKit.paint(look["floor"], metal * 0.6, 0.7, 0.4 if metal > 0.0 else 0.1)
	var trim_m := MeshKit.paint(look["trim"], metal, 0.6, 0.0)
	var fh := float(lay["floor_height"])
	var rooms: Dictionary = lay["rooms"]
	var ceilings := Node3D.new()
	ceilings.name = "Ceiling"
	root.add_child(ceilings)
	# Floors (with an opening over each stair) and ceilings.
	for id: String in rooms:
		var r: Dictionary = rooms[id]
		var rc: Array = r["rect"]
		var rect := Rect2(float(rc[0]), float(rc[1]), float(rc[2]), float(rc[3]))
		var y := int(r["floor"]) * fh
		var holes: Array[Rect2] = []
		for s: Dictionary in lay["stairs"]:
			if str(s["to"]) == id:
				holes.append(_stair_rect(s))
		for piece: Rect2 in _subtract(rect, holes):
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(piece.size.x, 0.12, piece.size.y), 0.0), floor_m, Vector3(piece.get_center().x, y - 0.06, piece.get_center().y))
		var top := y + fh - 0.06
		var is_top := true
		for other: Dictionary in rooms.values():
			if int(other["floor"]) == int(r["floor"]) + 1:
				var oc: Array = other["rect"]
				if Rect2(float(oc[0]), float(oc[1]), float(oc[2]), float(oc[3])).intersects(rect.grow(-0.1)):
					is_top = false
		if is_top:
			MeshKit.part(ceilings, MeshKit.chamfer_box(Vector3(rect.size.x, 0.12, rect.size.y), 0.0), wall_m, Vector3(rect.get_center().x, top, rect.get_center().y))
		# A light per room: lamps in towns, strip lights aboard ship.
		var l := OmniLight3D.new()
		l.light_color = look["light"]
		l.light_energy = 1.1
		l.omni_range = maxf(rect.size.x, rect.size.y) * 0.8 + 2.0
		l.position = Vector3(rect.get_center().x, y + fh - 0.5, rect.get_center().y)
		l.shadow_enabled = false
		root.add_child(l)
		var fixture := MeshKit.part(root, MeshKit.sphere(0.14, 8) if not bool(lay["ship"]) else MeshKit.chamfer_box(Vector3(1.2, 0.05, 0.12), 0.0),
			MeshKit.mech_material(look["light"], 0.0, 0.4, (look["light"] as Color) * 2.5, false), l.position + Vector3.UP * 0.3)
		fixture.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_walls(root, lay, wall_m, trim_m, fh)
	for s: Dictionary in lay["stairs"]:
		_stair(root, s, fh, trim_m if not bool(lay["ship"]) else floor_m)
	for f: Dictionary in lay["furniture"]:
		_furniture(root, f, look)
	for d: Dictionary in lay["doors"]:
		_door(root, d, look)
	return root


## Splits a rectangle around holes (stair openings) into up to four pieces per hole.
static func _subtract(r: Rect2, holes: Array[Rect2]) -> Array[Rect2]:
	var pieces: Array[Rect2] = [r]
	for h in holes:
		var next: Array[Rect2] = []
		for p in pieces:
			var i := p.intersection(h)
			if not p.intersects(h) or i.get_area() <= 0.0:
				next.append(p)
				continue
			if i.position.y > p.position.y:
				next.append(Rect2(p.position.x, p.position.y, p.size.x, i.position.y - p.position.y))
			if i.end.y < p.end.y:
				next.append(Rect2(p.position.x, i.end.y, p.size.x, p.end.y - i.end.y))
			if i.position.x > p.position.x:
				next.append(Rect2(p.position.x, i.position.y, i.position.x - p.position.x, i.size.y))
			if i.end.x < p.end.x:
				next.append(Rect2(i.end.x, i.position.y, p.end.x - i.end.x, i.size.y))
		pieces = next
	return pieces


## Walls on every room edge: edges on one line are merged (no doubled walls), doorways are cut
## out (with a lintel above), stair openings left open between floors.
static func _walls(root: Node3D, lay: Dictionary, wall_m: Material, trim_m: Material, fh: float) -> void:
	var lines := {}  # "axis|floor|coord" -> [[a, b], ...]
	for r: Dictionary in (lay["rooms"] as Dictionary).values():
		var rc: Array = r["rect"]
		var x0 := float(rc[0])
		var z0 := float(rc[1])
		var x1 := x0 + float(rc[2])
		var z1 := z0 + float(rc[3])
		var f := int(r["floor"])
		for e: Array in [["x", f, z0, x0, x1], ["x", f, z1, x0, x1], ["z", f, x0, z0, z1], ["z", f, x1, z0, z1]]:
			var key := "%s|%d|%.2f" % [e[0], e[1], e[2]]
			if not lines.has(key):
				lines[key] = []
			(lines[key] as Array).append([float(e[3]), float(e[4])])
	for key: String in lines:
		var parts := key.split("|")
		var axis := parts[0]
		var f := int(parts[1])
		var coord := float(parts[2])
		var spans := _union(lines[key])
		# Doorways on this line.
		var gaps: Array = []
		for d: Dictionary in lay["doors"]:
			var dp: Array = d["pos"]
			if absf(float(dp[1]) - f * fh) > 0.1 or str(d["axis"]) != axis:
				continue
			var on := absf((float(dp[2]) if axis == "x" else float(dp[0])) - coord) < 0.05
			var along := float(dp[0]) if axis == "x" else float(dp[2])
			var within := spans.any(func(sp: Array) -> bool: return along > float(sp[0]) and along < float(sp[1]))
			if on and within:
				gaps.append([along - float(d["width"]) * 0.5, along + float(d["width"]) * 0.5])
		var y := f * fh
		for s: Array in spans:
			for seg: Array in _cut(s, gaps):
				_wall_box(root, axis, coord, float(seg[0]), float(seg[1]), y, y + fh, wall_m)
		for g: Array in gaps:
			_wall_box(root, axis, coord, float(g[0]), float(g[1]), y + DOOR_H, y + fh, wall_m)
			# Door frame.
			for side: float in [float(g[0]), float(g[1])]:
				_wall_box(root, axis, coord, side - 0.06, side + 0.06, y, y + DOOR_H + 0.08, trim_m, WALL + 0.05)
		# Skirting along solid walls.
		for s: Array in spans:
			for seg: Array in _cut(s, gaps):
				_wall_box(root, axis, coord, float(seg[0]), float(seg[1]), y, y + 0.12, trim_m, WALL + 0.04)


static func _wall_box(root: Node3D, axis: String, coord: float, a: float, b: float, y0: float, y1: float, mat: Material, thick: float = WALL) -> void:
	if b - a < 0.02 or y1 - y0 < 0.02:
		return
	var size := Vector3(b - a, y1 - y0, thick) if axis == "x" else Vector3(thick, y1 - y0, b - a)
	var pos := Vector3((a + b) * 0.5, (y0 + y1) * 0.5, coord) if axis == "x" else Vector3(coord, (y0 + y1) * 0.5, (a + b) * 0.5)
	MeshKit.part(root, MeshKit.chamfer_box(size, 0.0), mat, pos)


static func _union(spans: Array) -> Array:
	spans.sort_custom(func(p: Array, q: Array) -> bool: return float(p[0]) < float(q[0]))
	var out: Array = []
	for s: Array in spans:
		if not out.is_empty() and float(s[0]) <= float(out[-1][1]) + 0.01:
			out[-1][1] = maxf(float(out[-1][1]), float(s[1]))
		else:
			out.append([float(s[0]), float(s[1])])
	return out


static func _cut(span: Array, gaps: Array) -> Array:
	var segs: Array = [span.duplicate()]
	for g: Array in gaps:
		var next: Array = []
		for s: Array in segs:
			if float(g[1]) <= float(s[0]) or float(g[0]) >= float(s[1]):
				next.append(s)
				continue
			if float(g[0]) > float(s[0]):
				next.append([float(s[0]), float(g[0])])
			if float(g[1]) < float(s[1]):
				next.append([float(g[1]), float(s[1])])
		segs = next
	return segs


static func _stair(root: Node3D, s: Dictionary, fh: float, mat: Material) -> void:
	var a := Vector3(float(s["start"][0]), 0, float(s["start"][1]))
	var b := Vector3(float(s["end"][0]), 0, float(s["end"][1]))
	var w := float(s.get("width", 1.2))
	var n := int(ceil(fh / 0.2))
	var step := (b - a) / n
	var along_x := absf(b.x - a.x) > absf(b.z - a.z)
	for i in range(n):
		var p := a + step * (i + 0.5)
		var hgt := fh * (i + 1) / n
		var size := Vector3(absf(step.x) + 0.01, hgt, w) if along_x else Vector3(w, hgt, absf(step.z) + 0.01)
		MeshKit.part(root, MeshKit.chamfer_box(size, 0.0), mat, Vector3(p.x, hgt * 0.5, p.z))


static func _furniture(root: Node3D, f: Dictionary, look: Dictionary) -> void:
	var node := Node3D.new()
	node.name = str(f["kind"]).capitalize().replace(" ", "")
	node.position = Vector3(float(f["pos"][0]), float(f["pos"][1]), float(f["pos"][2]))
	node.rotation.y = float(f["yaw"])
	root.add_child(node)
	var s := Vector3(float(f["size"][0]), float(f["size"][1]), float(f["size"][2]))
	var wood := MeshKit.paint(look["wood"], float(look["metal"]), 0.7, 0.0)
	var dark := MeshKit.paint(Color(0.12, 0.12, 0.13), 0.6, 0.5, 0.0)
	var cloth := MeshKit.paint(look["cloth"], 0.0, 0.9, 0.0)
	var steel := MeshKit.paint(Color(0.45, 0.47, 0.5), 0.8, 0.35, 0.3)
	var glow := func(c: Color) -> Material: return MeshKit.mech_material(c, 0.0, 0.4, c * 2.2, false)
	match str(f["kind"]):
		"table":
			MeshKit.part(node, MeshKit.chamfer_box(Vector3(s.x, 0.06, s.z), 0.01), wood, Vector3(0, s.y - 0.03, 0))
			MeshKit.part(node, MeshKit.cylinder(0.06, s.y - 0.06, 8), wood, Vector3(0, (s.y - 0.06) * 0.5, 0))
		"chair":
			MeshKit.part(node, MeshKit.chamfer_box(Vector3(s.x, 0.05, s.z), 0.01), wood, Vector3(0, 0.46, 0))
			MeshKit.part(node, MeshKit.chamfer_box(Vector3(s.x, 0.45, 0.05), 0.01), wood, Vector3(0, 0.7, -s.z * 0.45))
			for k in range(4):
				MeshKit.part(node, MeshKit.chamfer_box(Vector3(0.04, 0.44, 0.04), 0.0), wood, Vector3((k % 2 - 0.5) * (s.x - 0.08), 0.22, (k / 2 - 0.5) * (s.z - 0.08)))
		"counter", "stall":
			MeshKit.part(node, MeshKit.chamfer_box(Vector3(s.z, s.y - 0.06, s.x), 0.01), wood, Vector3(0, (s.y - 0.06) * 0.5, 0))
			MeshKit.part(node, MeshKit.chamfer_box(Vector3(s.z + 0.1, 0.06, s.x + 0.12), 0.01), MeshKit.paint((look["wood"] as Color).darkened(0.3), 0.1, 0.4, 0.0), Vector3(0, s.y - 0.03, 0))
			if f["kind"] == "stall":
				MeshKit.part(node, MeshKit.chamfer_box(Vector3(s.z + 0.3, 0.05, s.x + 0.4), 0.0), cloth, Vector3(0, 2.1, 0.1))
		"shelf":
			MeshKit.part(node, MeshKit.chamfer_box(Vector3(s.z, s.y, s.x * 0.5), 0.01), wood, Vector3(0, s.y * 0.5, -s.x * 0.25))
			for k in range(3):
				MeshKit.part(node, MeshKit.chamfer_box(Vector3(s.z, 0.04, s.x), 0.0), wood, Vector3(0, 0.6 + k * 0.5, 0))
				for b in range(int(s.z / 0.18)):
					var bottle := Color(0.2, 0.35, 0.18) if (b + k) % 3 else Color(0.45, 0.25, 0.1)
					MeshKit.part(node, MeshKit.cylinder(0.04, 0.26, 6), MeshKit.paint(bottle, 0.1, 0.15, 0.0), Vector3(-s.z * 0.5 + 0.1 + b * 0.18, 0.75 + k * 0.5, 0.05))
		"bed", "cot":
			MeshKit.part(node, MeshKit.chamfer_box(Vector3(s.x, 0.3, s.z), 0.02), wood if f["kind"] == "bed" else steel, Vector3(0, 0.25, 0))
			MeshKit.part(node, MeshKit.chamfer_box(Vector3(s.x - 0.08, 0.14, s.z - 0.1), 0.04), cloth, Vector3(0, 0.46, 0.02))
			MeshKit.part(node, MeshKit.chamfer_box(Vector3(s.x - 0.3, 0.12, 0.35), 0.05), MeshKit.paint(Color(0.85, 0.82, 0.75), 0.0, 0.9, 0.0), Vector3(0, 0.58, -s.z * 0.38))
			if f["kind"] == "bed":
				MeshKit.part(node, MeshKit.chamfer_box(Vector3(s.x, 0.9, 0.08), 0.01), wood, Vector3(0, 0.45, -s.z * 0.5))
		"chest":
			MeshKit.part(node, MeshKit.chamfer_box(s, 0.03), wood, Vector3(0, s.y * 0.5, 0))
			MeshKit.part(node, MeshKit.chamfer_box(Vector3(s.x + 0.02, 0.05, s.z + 0.02), 0.0), steel, Vector3(0, s.y * 0.75, 0))
			MeshKit.part(node, MeshKit.chamfer_box(Vector3(0.1, 0.12, 0.04), 0.0), steel, Vector3(0, s.y * 0.6, s.z * 0.5))
		"wardrobe", "cabinet", "locker", "rack":
			var m: Material = wood if not (f["kind"] in ["locker"]) else steel
			MeshKit.part(node, MeshKit.chamfer_box(s, 0.02), m, Vector3(0, s.y * 0.5, 0))
			MeshKit.part(node, MeshKit.chamfer_box(Vector3(0.02, s.y - 0.1, 0.01), 0.0), dark, Vector3(0, s.y * 0.5, s.z * 0.5 + 0.005))
			MeshKit.part(node, MeshKit.chamfer_box(Vector3(0.04, 0.12, 0.03), 0.0), steel, Vector3(0.08, s.y * 0.55, s.z * 0.5 + 0.01))
		"safe", "till":
			MeshKit.part(node, MeshKit.chamfer_box(s if f["kind"] == "safe" else Vector3(0.45, 0.3, 0.4), 0.03), dark if f["kind"] == "safe" else steel, Vector3(0, (s.y if f["kind"] == "safe" else 0.3) * 0.5 + (0.0 if f["kind"] == "safe" else 1.1), 0))
			if f["kind"] == "safe":
				var dial := MeshKit.part(node, MeshKit.cylinder(0.12, 0.05, 16), steel, Vector3(0.1, s.y * 0.55, s.z * 0.5 + 0.02))
				dial.rotation_degrees.x = 90
				MeshKit.part(node, MeshKit.chamfer_box(Vector3(0.05, 0.25, 0.05), 0.0), steel, Vector3(-0.2, s.y * 0.55, s.z * 0.5 + 0.03))
		"desk":
			MeshKit.part(node, MeshKit.chamfer_box(Vector3(s.x, 0.05, s.z), 0.01), wood, Vector3(0, s.y, 0))
			MeshKit.part(node, MeshKit.chamfer_box(Vector3(0.45, s.y, s.z - 0.05), 0.01), wood, Vector3(s.x * 0.5 - 0.25, s.y * 0.5, 0))
			MeshKit.part(node, MeshKit.chamfer_box(Vector3(0.05, s.y, s.z - 0.05), 0.0), wood, Vector3(-s.x * 0.5 + 0.03, s.y * 0.5, 0))
			MeshKit.part(node, MeshKit.chamfer_box(Vector3(0.4, 0.03, 0.3), 0.0), MeshKit.paint(Color(0.9, 0.88, 0.8), 0.0, 0.9, 0.0), Vector3(-0.2, s.y + 0.04, 0.05))
		"bench":
			MeshKit.part(node, MeshKit.chamfer_box(Vector3(s.x, 0.06, s.z), 0.01), wood, Vector3(0, s.y, 0))
			for sx: float in [-1.0, 1.0]:
				MeshKit.part(node, MeshKit.chamfer_box(Vector3(0.06, s.y, s.z - 0.05), 0.0), wood, Vector3(sx * (s.x * 0.5 - 0.1), s.y * 0.5, 0))
		"bucket":
			MeshKit.part(node, MeshKit.cylinder(0.16, 0.36, 10, 0.19), steel, Vector3(0, 0.18, 0))
		"crate", "cargo_crate":
			MeshKit.part(node, MeshKit.chamfer_box(s, 0.03), wood if f["kind"] == "crate" else MeshKit.paint(Color(0.55, 0.35, 0.18).lerp(Color(0.25, 0.35, 0.5), fposmod(s.y, 1.0)), 0.5, 0.6, 0.6), Vector3(0, s.y * 0.5, 0))
		"barrel":
			MeshKit.part(node, MeshKit.cylinder(s.x * 0.5, s.y, 12), wood, Vector3(0, s.y * 0.5, 0))
			for y: float in [0.15, s.y - 0.15]:
				MeshKit.part(node, MeshKit.cylinder(s.x * 0.5 + 0.01, 0.04, 12), dark, Vector3(0, y, 0))
		"console":
			MeshKit.part(node, MeshKit.chamfer_box(Vector3(s.x, s.y * 0.75, s.z), 0.03), steel, Vector3(0, s.y * 0.375, 0))
			var top := MeshKit.part(node, MeshKit.chamfer_box(Vector3(s.x, 0.06, s.z * 0.8), 0.01), glow.call(Color(0.3, 0.8, 1.0)), Vector3(0, s.y * 0.8, 0.05))
			top.rotation_degrees.x = -20
		"screen":
			MeshKit.part(node, MeshKit.chamfer_box(Vector3(s.z, s.y, 0.06), 0.01), glow.call(Color(0.1, 0.25, 0.4)), Vector3(0, 1.5, 0))
		"command_chair":
			MeshKit.part(node, MeshKit.cylinder(0.25, 0.4, 10), steel, Vector3(0, 0.2, 0))
			MeshKit.part(node, MeshKit.chamfer_box(Vector3(0.7, 0.12, 0.7), 0.04), cloth, Vector3(0, 0.5, 0))
			MeshKit.part(node, MeshKit.chamfer_box(Vector3(0.7, 0.8, 0.12), 0.04), cloth, Vector3(0, 0.95, -0.3))
			for sx: float in [-1.0, 1.0]:
				MeshKit.part(node, MeshKit.chamfer_box(Vector3(0.1, 0.1, 0.6), 0.02), steel, Vector3(sx * 0.4, 0.75, 0))
		"bunk":
			for y: float in [0.25, 1.35]:
				MeshKit.part(node, MeshKit.chamfer_box(Vector3(s.x, 0.12, s.z), 0.02), steel, Vector3(0, y, 0))
				MeshKit.part(node, MeshKit.chamfer_box(Vector3(s.x - 0.08, 0.12, s.z - 0.08), 0.04), cloth, Vector3(0, y + 0.12, 0))
			for k in range(4):
				MeshKit.part(node, MeshKit.chamfer_box(Vector3(0.05, s.y, 0.05), 0.0), steel, Vector3((k % 2 - 0.5) * s.x, s.y * 0.5, (k / 2 - 0.5) * s.z))
		"reactor":
			MeshKit.part(node, MeshKit.cylinder(s.x * 0.5, s.y, 20), steel, Vector3(0, s.y * 0.5, 0))
			for y: float in [0.6, 1.4, 2.2]:
				MeshKit.part(node, MeshKit.cylinder(s.x * 0.5 + 0.03, 0.12, 20), glow.call(Color(0.4, 0.8, 1.0)), Vector3(0, y, 0))
		"nhp_core":
			MeshKit.part(node, MeshKit.chamfer_box(Vector3(s.x, 0.4, s.z), 0.04), steel, Vector3(0, 0.2, 0))
			MeshKit.part(node, SmoothKit.blob(Vector3(0.6, 1.0, 0.6), 1.0, 1.0, 1.0, 16), glow.call(Color(0.6, 0.85, 1.0)), Vector3(0, 1.0, 0))
			for k in range(4):
				var a := k * PI * 0.5 + PI * 0.25
				MeshKit.part(node, MeshKit.chamfer_box(Vector3(0.08, 1.4, 0.08), 0.0), steel, Vector3(cos(a) * 0.55, 1.0, sin(a) * 0.55))
		"pipes":
			for k in range(3):
				var p := MeshKit.part(node, MeshKit.cylinder(0.08, s.x, 10), steel, Vector3(0, 0.3 + k * 0.6, 0))
				p.rotation_degrees.z = 90
		"cryo_pod":
			MeshKit.part(node, MeshKit.chamfer_box(Vector3(s.x, 0.5, s.z), 0.06), steel, Vector3(0, 0.25, 0))
			MeshKit.part(node, SmoothKit.rounded_box(Vector3(s.x - 0.1, 0.55, s.z - 0.15), 0.2), MeshKit.paint(Color(0.16, 0.26, 0.32), 0.3, 0.04, 0.0, Color(0.1, 0.3, 0.4) * 0.6), Vector3(0, 0.72, 0))
			MeshKit.part(node, MeshKit.chamfer_box(Vector3(0.3, 0.12, 0.05), 0.0), glow.call(Color(0.3, 1.0, 0.6)), Vector3(0, 0.4, s.z * 0.5 + 0.01))
		_:
			MeshKit.part(node, MeshKit.chamfer_box(s, 0.02), wood, Vector3(0, s.y * 0.5, 0))


## A door in its doorway, hinged at one side so it can swing open (bars and hatches slide).
static func _door(root: Node3D, d: Dictionary, look: Dictionary) -> void:
	if d["kind"] == "arch":
		return
	var hinge := Node3D.new()
	hinge.name = "Door_" + str(d["id"])
	var w := float(d["width"])
	var p := Vector3(float(d["pos"][0]), float(d["pos"][1]), float(d["pos"][2]))
	var along := Vector3(1, 0, 0) if d["axis"] == "x" else Vector3(0, 0, 1)
	hinge.position = p - along * w * 0.5
	hinge.rotation.y = 0.0 if d["axis"] == "x" else -PI * 0.5
	hinge.set_meta("kind", d["kind"])
	hinge.set_meta("width", w)
	root.add_child(hinge)
	match str(d["kind"]):
		"bars":
			for k in range(int(w / 0.14) + 1):
				MeshKit.part(hinge, MeshKit.cylinder(0.02, DOOR_H, 6), MeshKit.paint(Color(0.2, 0.2, 0.22), 0.8, 0.4, 0.0), Vector3(k * 0.14 + 0.02, DOOR_H * 0.5, 0))
			for y: float in [0.1, DOOR_H * 0.5, DOOR_H - 0.05]:
				MeshKit.part(hinge, MeshKit.chamfer_box(Vector3(w, 0.05, 0.05), 0.0), MeshKit.paint(Color(0.2, 0.2, 0.22), 0.8, 0.4, 0.0), Vector3(w * 0.5, y, 0))
		"hatch":
			MeshKit.part(hinge, MeshKit.chamfer_box(Vector3(w, DOOR_H, 0.1), 0.04), MeshKit.paint(Color(0.38, 0.4, 0.43), 0.7, 0.45, 0.6), Vector3(w * 0.5, DOOR_H * 0.5, 0))
			MeshKit.part(hinge, MeshKit.chamfer_box(Vector3(w * 0.8, 0.08, 0.12), 0.0), MeshKit.paint(Color(0.85, 0.65, 0.1), 0.2, 0.6, 0.0), Vector3(w * 0.5, DOOR_H * 0.85, 0))
		_:
			MeshKit.part(hinge, MeshKit.chamfer_box(Vector3(w - 0.04, DOOR_H - 0.02, 0.06), 0.01), MeshKit.paint((look["wood"] as Color).darkened(0.15), 0.0, 0.75, 0.0), Vector3(w * 0.5, DOOR_H * 0.5, 0))
			MeshKit.part(hinge, MeshKit.sphere(0.04, 8), MeshKit.paint(Color(0.7, 0.6, 0.3), 0.9, 0.3, 0.0), Vector3(w - 0.12, 1.0, 0.05))


## Opens or shuts a built door: doors swing 100 degrees, bars and hatches slide aside.
static func set_door(root: Node, id: String, open: bool) -> void:
	var hinge := root.get_node_or_null("Door_" + id) as Node3D
	if hinge == null or bool(hinge.get_meta("open", false)) == open:
		return
	if not hinge.has_meta("base_yaw"):
		hinge.set_meta("base_yaw", hinge.rotation.y)
	if str(hinge.get_meta("kind", "door")) in ["hatch", "bars"]:
		var shift := float(hinge.get_meta("width", 1.0)) * (-1.0 if open else 1.0)
		for ch in hinge.get_children():
			(ch as Node3D).position.x += shift
	else:
		hinge.rotation.y = float(hinge.get_meta("base_yaw")) + (deg_to_rad(100.0) if open else 0.0)
	hinge.set_meta("open", open)
