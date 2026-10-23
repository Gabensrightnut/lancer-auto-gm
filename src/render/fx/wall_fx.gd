class_name WallFx
extends RefCounted
## Attacks and barriers meeting walls and cover (data/game/terrain_effects.json). Picks how a
## shot travels from what the engine and the content say (event flags, the weapon's mod, id
## and tags, the attacker's effects) and draws it against the board's real terrain: a phased
## shot ripples into the wall and comes out behind it, a Throughbolt punches straight through,
## Arcing lobs over, Seeking curves around, a cover-ignoring shot shows a line through the cover.
## Barriers shimmer where shots cross, flicker as they weaken and shatter when destroyed. Only
## what the rules did: holes that stay come from terrain_damaged (the terrain renderer).

const FILE := "res://data/game/terrain_effects.json"
const PATHS := ["phase", "throughbolt", "arc", "seek", "see_through", "teleport"]

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE)) if FileAccess.file_exists(FILE) else null
		_data = d if d is Dictionary else {"paths": {}, "looks": {}, "barriers": {}}
	return _data


## How this attack's shot travels ("" = straight, the normal way). `e` is the attack_rolled
## event, `w` the content weapon, `unit` the attacker's view dict.
static func path_for(e: Dictionary, w: Dictionary, unit: Dictionary) -> String:
	var p: Dictionary = data().get("paths", {})
	for k: String in (p.get("by_event", {}) as Dictionary):
		if k.begins_with("via_"):
			if String(e.get("via", "")) == k.substr(4):
				return String(p["by_event"][k])
		elif e.get(k, false) == true:
			return String(p["by_event"][k])
	var entry := _loadout_weapon(unit, String(e.get("weapon", "")))
	var mounts: Array = (unit.get("loadout", {}) as Dictionary).get("mounts", [])
	var mi := int(entry.get("mount", -1))
	if mi >= 0 and mi < mounts.size():
		var mod := String((mounts[mi] as Dictionary).get("mod", ""))
		if (p.get("by_mod", {}) as Dictionary).has(mod):
			return String(p["by_mod"][mod])
	var wid := String(w.get("id", entry.get("id", "")))
	if (p.get("by_weapon", {}) as Dictionary).has(wid):
		return String(p["by_weapon"][wid])
	var tags: Array = entry.get("tags", w.get("tags", []))
	for t: Variant in tags:
		var tid := String((t as Dictionary).get("id", "")) if t is Dictionary else ""
		if (p.get("by_tag", {}) as Dictionary).has(tid):
			return String(p["by_tag"][tid])
	return ""


static func _loadout_weapon(unit: Dictionary, key: String) -> Dictionary:
	for w: Dictionary in (unit.get("loadout", {}) as Dictionary).get("weapons", []):
		if String(w.get("key", "")) == key:
			return w
	return {}


static func _look(path: String, key: String, fallback: Variant) -> Variant:
	return (data().get("looks", {}) as Dictionary).get(path, {}).get(key, fallback)


static func _color(path: String, fallback: Color) -> Color:
	var c: Variant = _look(path, "color", "")
	return Color.html(String(c)) if String(c) != "" else fallback


## Where the straight line from `a` to `b` passes through terrain taller than it: [[entry,
## exit], ...] in world space, sampled every 0.12 m against each column's top.
static func blocks(battle: BattleView, a: Vector3, b: Vector3) -> Array:
	var out: Array = []
	if battle == null or battle.map == null:
		return out
	var n := maxi(2, int(a.distance_to(b) / 0.12))
	var inside := false
	var entry := Vector3.ZERO
	for i in range(1, n):
		var p := a.lerp(b, float(i) / n)
		var c := battle.map.grid.from_world(p)
		var solid := battle.map.has_cell(c) and battle.map.ground_height(c) * GridLayout.LEVEL_HEIGHT > p.y
		if solid and not inside:
			entry = p
			inside = true
		elif not solid and inside:
			out.append([entry, p])
			inside = false
	if inside:
		out.append([entry, b])
	return out


## The tallest terrain under the line, for lobbing over it.
static func max_top(battle: BattleView, a: Vector3, b: Vector3) -> float:
	var top := maxf(a.y, b.y)
	if battle == null or battle.map == null:
		return top
	for i in range(1, 12):
		var c := battle.map.grid.from_world(a.lerp(b, i / 12.0))
		if battle.map.has_cell(c):
			top = maxf(top, battle.map.ground_height(c) * GridLayout.LEVEL_HEIGHT)
	return top


## Plays the shot along its special path; returns once it reaches `to`.
static func play_path(owner: Node, battle: BattleView, path: String, from: Vector3, to: Vector3, glow: Color) -> void:
	var fx := battle.fx_root
	match path:
		"phase":
			var col := _color("phase", Color(0.7, 0.55, 1.0))
			var segs := blocks(battle, from, to)
			var start := from
			for s: Array in segs:
				await Fx.tracer(fx, start, s[0], col, 0.12)
				ripple(fx, s[0], col, (to - from).normalized())
				await Fx.wait(owner, 0.18)
				ripple(fx, s[1], col, (to - from).normalized())
				start = s[1]
			await Fx.tracer(fx, start, to, col, 0.12)
		"throughbolt":
			var col := _color("throughbolt", Color(1.0, 0.9, 0.6))
			for s: Array in blocks(battle, from, to):
				Fx.sparks(fx, s[0], col, 18, 3.0)
				Fx.dust(fx, s[1], 6, Color(0.55, 0.52, 0.48, 0.7), 0.35, 0.5, 0.9)
			await Fx.beam(fx, from, to, col, float(_look("throughbolt", "width", 0.07)))
		"arc":
			var apex := max_top(battle, from, to) - maxf(from.y, to.y) + float(_look("arc", "apex", 1.6))
			await Fx.projectile_arc(fx, from, to, maxf(apex, 1.0), 0.9, glow)
		"seek":
			await seek(owner, fx, from, to, glow, float(_look("seek", "bend", 1.4)))
		"see_through":
			var col := _color("see_through", Color(0.5, 0.9, 1.0))
			Fx.data_link(fx, from, to, col, 0.5)
			await Fx.wait(owner, 0.2)
			await Fx.tracer(fx, from, to, glow, 0.14)
		_:
			await Fx.tracer(fx, from, to, glow, 0.12)


## A missile that bends around what's in the way: out to the side, then in to the target.
static func seek(owner: Node, fx: Node3D, from: Vector3, to: Vector3, color: Color, bend: float) -> void:
	var d := to - from
	var side := d.cross(Vector3.UP).normalized() * bend * (1.0 if int(from.x * 10.0) % 2 == 0 else -1.0)
	var c1 := from + d * 0.3 + side + Vector3.UP * 0.6
	var c2 := from + d * 0.75 + side * 0.6
	var bolt := MeshKit.part(fx, MeshKit.sphere(0.05, 6), MeshKit.fx_material(color, 3.0), from)
	var last := from
	var tw := bolt.create_tween()
	tw.tween_method(func(t: float) -> void:
		if not is_instance_valid(bolt):
			return
		var u := 1.0 - t
		var p := from * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + to * t * t * t
		if p.distance_to(last) > 0.15:
			Fx.dust(fx, p, 1, Color(0.8, 0.8, 0.8, 0.5), 0.12, 0.1, 0.6)
			last = p
		bolt.global_position = p, 0.0, 1.0, Fx.t(0.8))
	await tw.finished
	bolt.queue_free()


## A shimmer where something passes through a barrier or into a phased wall: an expanding,
## fading ring facing along `dir`, with a soft flash.
static func ripple(fx: Node3D, at: Vector3, color: Color, dir: Vector3 = Vector3.FORWARD) -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.16
	tm.outer_radius = 0.2
	ring.mesh = tm
	ring.material_override = MeshKit.fx_material(color, 2.0)
	fx.add_child(ring)
	ring.global_position = at
	var up := dir.normalized() if dir.length() > 0.01 else Vector3.UP
	if up.dot(Vector3.UP) > -0.999:
		ring.quaternion = Quaternion(Vector3.UP, up)  # the ring faces along the shot
	ring.scale = Vector3.ONE * 0.4
	var tw := ring.create_tween()
	tw.tween_property(ring, "scale", Vector3.ONE * 2.2, Fx.t(0.45)).set_ease(Tween.EASE_OUT)
	tw.tween_callback(ring.queue_free)
	Fx.light_flash(fx, at, color, 2.5, 1.5, 0.2)


## Barrier colors and HP by zone kind (or {} if the kind isn't a barrier).
static func barrier_zone(kind: String) -> Dictionary:
	return ((data().get("barriers", {}) as Dictionary).get("zones", {}) as Dictionary).get(kind, {})


static func is_barrier_deployable(name: String) -> bool:
	return String(name) in ((data().get("barriers", {}) as Dictionary).get("deployables", []) as Array)


## Where a shot's line crosses barrier zones on the board: [{point, color, id}].
static func barrier_crossings(battle: BattleView, a: Vector3, b: Vector3) -> Array:
	var out: Array = []
	if battle == null or battle.zones == null or battle.map == null:
		return out
	for id: String in battle.zones.zones:
		var z: Dictionary = battle.zones.zones[id]
		var bz := barrier_zone(String(z.get("kind", "")))
		if bz.is_empty():
			continue
		var cells := {}
		for c in battle.zones.cells_of(z):
			cells[c] = true
		var n := maxi(2, int(a.distance_to(b) / 0.15))
		var was := cells.has(battle.map.grid.from_world(a))
		for i in range(1, n + 1):
			var p := a.lerp(b, float(i) / n)
			var now := cells.has(battle.map.grid.from_world(p))
			if now != was:
				out.append({"point": p, "color": Color.html(String(bz.get("color", "#80d0ff"))), "id": id})
			was = now
	return out


## A barrier deployable (or any model) losing strength: it flickers, more the weaker it is.
static func flicker(model: Node3D, strength_left: float) -> void:
	if model == null:
		return
	var tw := model.create_tween()
	var flickers := 2 + int((1.0 - clampf(strength_left, 0.0, 1.0)) * 5.0)
	for i in range(flickers):
		tw.tween_property(model, "visible", false, Fx.t(0.04))
		tw.tween_property(model, "visible", true, Fx.t(0.06 + 0.04 * strength_left))


## A barrier breaking apart: shards fly out and fade.
static func shatter(fx: Node3D, at: Vector3, color: Color, size: float = 1.0) -> void:
	var mat := MeshKit.fx_material(color, 1.6)
	for i in range(14):
		var shard := MeshKit.part(fx, MeshKit.chamfer_box(Vector3(0.12, 0.18, 0.02) * size, 0.005), mat, at + Vector3(MeshKit.hash01("sh", i) - 0.5, MeshKit.hash01("sh", i + 20) * 0.8, MeshKit.hash01("sh", i + 40) - 0.5) * size)
		var dir := (shard.position - at).normalized() + Vector3.UP * 0.3
		var tw := shard.create_tween()
		tw.tween_property(shard, "position", shard.position + dir * 1.2 * size + Vector3.DOWN * 0.4, Fx.t(0.7)).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(shard, "rotation_degrees", Vector3(200, 90 * i, 140), Fx.t(0.7))
		tw.parallel().tween_property(shard, "scale", Vector3.ONE * 0.05, Fx.t(0.7)).set_delay(Fx.t(0.3))
		tw.tween_callback(shard.queue_free)
	Fx.light_flash(fx, at, color, 4.0, 2.5 * size, 0.3)
