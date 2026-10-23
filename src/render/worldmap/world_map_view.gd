class_name WorldMapView
extends Node3D
## The world map (DESIGN.md "Exploring vs. fighting"): a stylised overworld in the spirit of
## FF VII/X's maps (feel only), drawn from the region map (world's data via WorldMapSession):
## smooth terrain colored by tile, scattered props (instanced), a sea plane, town/job/outpost
## markers, and the squad's mechs or pilots walking on it at map scale with their gait.
## Driven only by what it's given: load_region(region), show_view(session.view_for(seat)),
## spring_ambush(...) when the rules spring one. Clicks come back as tile_clicked/site_clicked.
## Looks: data/game/world_map_look.json.

signal tile_clicked(t: Vector2i)
signal site_clicked(site_id: String)

const FILE := "res://data/game/world_map_look.json"

var content: ContentDB
var camera: Camera3D
## The seat whose token the camera follows.
var local_seat := ""
var region: Dictionary = {}
var tokens: Dictionary = {}  # seat -> MechModel
var sites: Dictionary = {}  # site id -> Node3D
var ambushers: Array[Node3D] = []

var _look: Dictionary = {}
var _heights: Dictionary = {}  # Vector2i -> float (tile surface)
var _targets: Dictionary = {}  # seat -> Vector3
var _terrain: Node3D
var _cam_dist := 9.0


func _init() -> void:
	name = "WorldMapView"
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE)) if FileAccess.file_exists(FILE) else null
	_look = d if d is Dictionary else {"terrains": {}, "sites": {}}
	camera = Camera3D.new()
	camera.name = "MapCamera"
	camera.fov = 50.0
	add_child(camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)


func terrain_of(t: Vector2i) -> Dictionary:
	var name_ := String((region.get("tiles", {}) as Dictionary).get("%d,%d" % [t.x, t.y], {}).get("terrain", "plains"))
	var all: Dictionary = _look.get("terrains", {})
	return all.get(name_, all.get("plains", {"color": "#7fa35a", "height": 0.15}))


## World position of a map point (tiles, may be fractional) on the terrain surface.
func to_world(p: Vector2) -> Vector3:
	var tile := float(_look.get("tile", 1.0))
	return Vector3(p.x * tile, height_at(p), p.y * tile)


func height_at(p: Vector2) -> float:
	var t := Vector2i(roundi(p.x), roundi(p.y))
	var h := float(_heights.get(t, 0.0))
	var sea := float(_look.get("sea_level", 0.0))
	return maxf(h, sea)


func load_region(r: Dictionary) -> void:
	region = r
	if _terrain:
		_terrain.queue_free()
	for s: Node3D in sites.values():
		s.queue_free()
	sites.clear()
	_heights.clear()
	_terrain = Node3D.new()
	_terrain.name = "Terrain"
	add_child(_terrain)
	var size: Array = r.get("size", [0, 0])
	var w := int(size[0])
	var h := int(size[1])
	for y in range(h):
		for x in range(w):
			_heights[Vector2i(x, y)] = float(terrain_of(Vector2i(x, y)).get("height", 0.15))
	_build_ground(w, h)
	_build_props(w, h)
	_build_sea(w, h)
	for site: Dictionary in r.get("sites", []):
		_add_site(site)


## One mesh: each tile a quad whose corners average the tiles around them (smooth hills),
## colored by terrain, snow on high mountain corners.
func _build_ground(w: int, h: int) -> void:
	var tile := float(_look.get("tile", 1.0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corner := func(cx: int, cy: int) -> float:
		var sum := 0.0
		var n := 0
		for d: Vector2i in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
			var t := Vector2i(cx, cy) + d
			if _heights.has(t):
				sum += float(_heights[t])
				n += 1
		return sum / maxf(1, n)
	for y in range(h):
		for x in range(w):
			var t := Vector2i(x, y)
			var spec := terrain_of(t)
			var col := Color(String(spec.get("color", "#7fa35a")))
			col = col.lightened((MeshKit.hash01("g", x * 131 + y) - 0.5) * 0.08)
			var p: Array[Vector3] = []
			for c: Vector2i in [Vector2i(x, y), Vector2i(x + 1, y), Vector2i(x + 1, y + 1), Vector2i(x, y + 1)]:
				p.append(Vector3((c.x - 0.5) * tile, corner.call(c.x, c.y), (c.y - 0.5) * tile))
			var cols: Array[Color] = []
			for v in p:
				var snow := float(spec.get("snow_above", 99.0))
				cols.append(Color(0.93, 0.95, 0.97) if v.y > snow else col)
			for tri: Array in [[0, 2, 1], [0, 3, 2]]:
				var n := (p[tri[1]] - p[tri[0]]).cross(p[tri[2]] - p[tri[0]]).normalized()
				for i: int in tri:
					st.set_color(cols[i])
					st.set_normal(-n if n.y < 0.0 else n)
					st.add_vertex(p[i])
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mi.material_override = mat
	_terrain.add_child(mi)


## Props per terrain (trees, pines, palms, rocks, cacti, reeds, ruins), one MultiMesh each.
func _build_props(w: int, h: int) -> void:
	var tile := float(_look.get("tile", 1.0))
	var spots: Dictionary = {}  # prop kind -> [Transform3D]
	for y in range(h):
		for x in range(w):
			var spec := terrain_of(Vector2i(x, y))
			var kind := String(spec.get("props", "none"))
			if kind == "none":
				continue
			for i in range(int(spec.get("count", 1))):
				var k := x * 7919 + y * 104729 + i * 31
				var p := Vector2(x + (MeshKit.hash01(kind, k) - 0.5) * 0.85, y + (MeshKit.hash01(kind, k + 1) - 0.5) * 0.85)
				var s := 0.7 + MeshKit.hash01(kind, k + 2) * 0.6
				var xf := Transform3D(Basis(Vector3.UP, MeshKit.hash01(kind, k + 3) * TAU).scaled(Vector3.ONE * s * tile), Vector3(p.x * tile, height_at(p), p.y * tile))
				if not spots.has(kind):
					spots[kind] = []
				(spots[kind] as Array).append(xf)
	for kind: String in spots:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = prop_mesh(kind)
		mm.instance_count = (spots[kind] as Array).size()
		for i in range(mm.instance_count):
			mm.set_instance_transform(i, spots[kind][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Props_" + kind
		mmi.multimesh = mm
		_terrain.add_child(mmi)


## A small prop mesh (one surface per material) for instancing.
static func prop_mesh(kind: String) -> ArrayMesh:
	var am := ArrayMesh.new()
	var add := func(m: Mesh, xf: Transform3D, color: Color) -> void:
		var st := SurfaceTool.new()
		st.append_from(m, 0, xf)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 0.9
		st.set_material(mat)
		st.commit(am)
	var trunk := Color(0.36, 0.26, 0.18)
	match kind:
		"trees":
			add.call(MeshKit.cylinder(0.03, 0.18, 6), Transform3D(Basis(), Vector3(0, 0.09, 0)), trunk)
			add.call(MeshKit.sphere(0.14, 8), Transform3D(Basis().scaled(Vector3(1, 1.1, 1)), Vector3(0, 0.28, 0)), Color(0.24, 0.45, 0.2))
		"pines":
			add.call(MeshKit.cylinder(0.025, 0.12, 6), Transform3D(Basis(), Vector3(0, 0.06, 0)), trunk)
			add.call(MeshKit.cylinder(0.14, 0.4, 7, 0.0), Transform3D(Basis(), Vector3(0, 0.3, 0)), Color(0.18, 0.36, 0.25))
		"palms":
			add.call(MeshKit.cylinder(0.025, 0.36, 6, 0.018), Transform3D(Basis(Vector3.FORWARD, 0.15), Vector3(0, 0.18, 0)), trunk)
			add.call(MeshKit.sphere(0.13, 6), Transform3D(Basis().scaled(Vector3(1.4, 0.35, 1.4)), Vector3(0.03, 0.38, 0)), Color(0.2, 0.5, 0.22))
		"rocks":
			add.call(MeshKit.sphere(0.12, 5), Transform3D(Basis().scaled(Vector3(1.2, 0.7, 1.0)), Vector3(0, 0.05, 0)), Color(0.48, 0.46, 0.43))
		"cacti":
			add.call(MeshKit.cylinder(0.03, 0.22, 6), Transform3D(Basis(), Vector3(0, 0.11, 0)), Color(0.3, 0.52, 0.3))
		"reeds":
			for i in range(3):
				add.call(MeshKit.cylinder(0.006, 0.16, 4), Transform3D(Basis(Vector3.RIGHT, 0.1 * (i - 1)), Vector3(0.03 * (i - 1), 0.08, 0)), Color(0.45, 0.5, 0.3))
		"ruins":
			add.call(MeshKit.chamfer_box(Vector3(0.18, 0.22, 0.14), 0.01), Transform3D(Basis(), Vector3(0, 0.11, 0)), Color(0.55, 0.53, 0.5))
			add.call(MeshKit.chamfer_box(Vector3(0.1, 0.12, 0.1), 0.01), Transform3D(Basis(), Vector3(0.12, 0.06, 0.08)), Color(0.45, 0.44, 0.42))
	return am


func _build_sea(w: int, h: int) -> void:
	var tile := float(_look.get("tile", 1.0))
	var any := false
	for t: Vector2i in _heights:
		any = any or bool(terrain_of(t).get("water", false))
	if not any:
		return
	var sea := MeshInstance3D.new()
	sea.name = "Sea"
	var pm := PlaneMesh.new()
	pm.size = Vector2(w * tile + 2.0, h * tile + 2.0)
	sea.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.42, 0.62, 0.78)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.15
	mat.metallic = 0.2
	sea.material_override = mat
	sea.position = Vector3((w - 1) * tile * 0.5, float(_look.get("sea_level", 0.0)) + 0.01, (h - 1) * tile * 0.5)
	_terrain.add_child(sea)


## A site marker by kind: a few buildings, a tower, a job beacon, a tent, an obelisk; its
## name floats above.
func _add_site(site: Dictionary) -> void:
	var at: Array = site.get("at", [0, 0])
	var spec: Dictionary = (_look.get("sites", {}) as Dictionary).get(String(site.get("kind", "")), {"look": "obelisk", "color": "#ffffff"})
	var col := Color(String(spec.get("color", "#ffffff")))
	var n := Node3D.new()
	n.name = "Site_" + String(site.get("id", ""))
	add_child(n)
	n.position = to_world(Vector2(float(at[0]), float(at[1])))
	var wall := MeshKit.mech_material(Color(0.78, 0.74, 0.66), 0.1, 0.8, Color.BLACK, false)
	var roof := MeshKit.mech_material(col.darkened(0.35), 0.1, 0.7, Color.BLACK, false)
	var glow := MeshKit.fx_material(col, 2.0)
	match String(spec.get("look", "obelisk")):
		"buildings":
			for i in range(4):
				var p := Vector3((MeshKit.hash01(n.name, i) - 0.5) * 0.6, 0, (MeshKit.hash01(n.name, i + 9) - 0.5) * 0.6)
				var bh := 0.12 + MeshKit.hash01(n.name, i + 3) * 0.16
				MeshKit.part(n, MeshKit.chamfer_box(Vector3(0.16, bh, 0.16), 0.01), wall, p + Vector3.UP * bh * 0.5)
				MeshKit.part(n, MeshKit.cylinder(0.13, 0.07, 4, 0.0), roof, p + Vector3.UP * (bh + 0.035), Vector3(0, 45, 0))
		"tower":
			MeshKit.part(n, MeshKit.cylinder(0.07, 0.5, 8, 0.05), wall, Vector3(0, 0.25, 0))
			MeshKit.part(n, MeshKit.sphere(0.05, 8), glow, Vector3(0, 0.53, 0))
		"beacon":
			MeshKit.part(n, MeshKit.cylinder(0.04, 0.9, 8, 0.04), MeshKit.overlay_material(Color(col, 0.45)), Vector3(0, 0.45, 0))
			MeshKit.part(n, MeshKit.chamfer_box(Vector3(0.18, 0.06, 0.18), 0.01), roof, Vector3(0, 0.03, 0))
		"tent":
			MeshKit.part(n, MeshKit.cylinder(0.16, 0.18, 4, 0.0), roof, Vector3(0, 0.09, 0), Vector3(0, 45, 0))
			MeshKit.part(n, MeshKit.sphere(0.03, 6), glow, Vector3(0.18, 0.05, 0))
		_:
			MeshKit.part(n, MeshKit.chamfer_box(Vector3(0.1, 0.5, 0.1), 0.01, 0.5), wall, Vector3(0, 0.25, 0))
			MeshKit.part(n, MeshKit.sphere(0.04, 6), glow, Vector3(0, 0.54, 0))
	var label := Label3D.new()
	label.text = String(site.get("name", site.get("id", "")))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.0009
	label.font_size = 26
	label.outline_size = 8
	label.position = Vector3(0, 0.75, 0)
	n.add_child(label)
	sites[String(site.get("id", ""))] = n


## The squad from WorldMapSession.view_for(seat): tokens walk to where the session says,
## hidden while inside a site. A view member may say its frame ("frame": content id).
func show_view(v: Dictionary) -> void:
	var squad: Dictionary = v.get("squad", {})
	for seat: String in tokens.keys():
		if not squad.has(seat):
			(tokens[seat] as Node3D).queue_free()
			tokens.erase(seat)
			_targets.erase(seat)
	for seat: String in squad:
		var s: Dictionary = squad[seat]
		var on := String(s.get("on", "mech"))
		if tokens.has(seat) and String((tokens[seat] as Node3D).get_meta("on", "")) != on:
			(tokens[seat] as Node3D).queue_free()
			tokens.erase(seat)
		if not tokens.has(seat):
			var tok := _token(String(s.get("frame", "mf_standard_pattern_i_everest")), on)
			tok.set_meta("on", on)
			add_child(tok)
			tokens[seat] = tok
			tok.position = to_world(Vector2(float(s["at"][0]), float(s["at"][1])))
		var at: Array = s.get("at", [0, 0])
		_targets[seat] = to_world(Vector2(float(at[0]), float(at[1])))
		(tokens[seat] as Node3D).visible = String(s.get("in_area", "")) == ""
	_show_ambushers(v.get("ambushers", []))


var _ambush_marks: Dictionary = {}  # ambush id -> marker
var _ambush_sprung: Dictionary = {}  # ambush ids already sprung


## Ambushers in the view (net's WorldMapSession): "spotted" (only the pilot who spotted them
## sees it) draws a marker in their cover; the first time one turns "charging" they burst out
## and charge (spring_ambush); "sprung" leaves them where they are (the fight takes over);
## once out of the view ("gone") everything of theirs is cleared.
func _show_ambushers(list: Array) -> void:
	var seen := {}
	for amb: Dictionary in list:
		var id := String(amb.get("id", ""))
		seen[id] = true
		var at: Array = amb.get("at", [0, 0])
		var state := String(amb.get("state", ""))
		if state == "spotted" and not _ambush_marks.has(id):
			var mark := Node3D.new()
			mark.name = "Spotted_" + id
			add_child(mark)
			mark.position = to_world(Vector2(float(at[0]), float(at[1])))
			var ring := MeshKit.part(mark, MeshKit.cylinder(0.45, 0.02, 20), MeshKit.overlay_material(Color(1.0, 0.75, 0.2, 0.35)), Vector3(0, 0.04, 0))
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var q := Label3D.new()
			q.text = "?"
			q.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			q.fixed_size = true
			q.pixel_size = 0.0012
			q.font_size = 40
			q.modulate = Color(1.0, 0.8, 0.3)
			q.outline_size = 10
			q.position = Vector3(0, 0.7, 0)
			mark.add_child(q)
			_ambush_marks[id] = mark
		elif state == "charging" and not _ambush_sprung.has(id):
			_ambush_sprung[id] = true
			if _ambush_marks.has(id):
				(_ambush_marks[id] as Node).queue_free()
				_ambush_marks.erase(id)
			var units: Array = amb.get("units", [])
			if units.is_empty():
				units = [{"id": id, "kind": "npc", "at": at}]
			var toward: Array = amb.get("toward", units[0].get("toward", at) if units[0] is Dictionary else at)
			spring_ambush(units, toward)
	for id: String in _ambush_marks.keys():
		if not seen.has(id):
			(_ambush_marks[id] as Node).queue_free()
			_ambush_marks.erase(id)
	var live := false
	for amb: Dictionary in list:
		live = live or String(amb.get("state", "")) in ["charging", "sprung"]
	if not live and not _ambush_sprung.is_empty():
		clear_ambush()  # they fell back ("gone") or the fight took over
		_ambush_sprung.clear()


## A mech (its frame and gait) or a pilot token at map scale.
func _token(frame_id: String, on: String) -> MechModel:
	var h := float(_look.get("token_height", 0.75))
	var m: MechModel
	if on == "mech" and content and not content.frame(frame_id).is_empty():
		m = MechBuilder.build(content.frame(frame_id), {}, content)
	else:
		m = MechView.pilot_model({"id": "map_pilot"})
	m.scale = Vector3.ONE * (h / maxf(0.1, m.height)) * (1.0 if on == "mech" else 0.6)
	return m


func _process(delta: float) -> void:
	for seat: String in tokens:
		var tok: MechModel = tokens[seat]
		var to: Vector3 = _targets.get(seat, tok.position)
		var d := Vector2(to.x - tok.position.x, to.z - tok.position.z)
		var dist := d.length()
		if dist > 0.005:
			var step := minf(dist, 2.5 * delta * float(_look.get("tile", 1.0)))
			var dir := d / dist
			tok.position.x += dir.x * step
			tok.position.z += dir.y * step
			tok.rotation.y = lerp_angle(tok.rotation.y, atan2(-dir.x, -dir.y), clampf(delta * 8.0, 0.0, 1.0))
			tok.walk_phase += step / maxf(0.01, tok.scale.x) * tok.steps_per_cell() * PI / maxf(0.5, GridLayout.SPACE)
			tok.set_walk(1.0)
		else:
			tok.set_walk(0.0)
		tok.position.y = lerpf(tok.position.y, height_at(Vector2(tok.position.x, tok.position.z) / float(_look.get("tile", 1.0))), clampf(delta * 6.0, 0.0, 1.0))
	var follow: Node3D = tokens.get(local_seat)
	if follow and camera:
		var aim := follow.position + Vector3.UP * 0.3
		var want := aim + Vector3(0, _cam_dist * 0.8, _cam_dist * 0.62)
		camera.position = camera.position.lerp(want, clampf(delta * 4.0, 0.0, 1.0)) if camera.position.length() > 0.01 else want
		camera.look_at(aim, Vector3.UP)


## Mouse: click a tile or a site; wheel zooms.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_dist = maxf(4.0, _cam_dist - 0.6)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_dist = minf(22.0, _cam_dist + 0.6)
		elif mb.button_index == MOUSE_BUTTON_LEFT and camera:
			var t := tile_under(camera.project_ray_origin(mb.position), camera.project_ray_normal(mb.position))
			if t != Vector2i(-1, -1):
				var site := site_at(t)
				if site != "":
					site_clicked.emit(site)
				else:
					tile_clicked.emit(t)


## The tile a ray hits (marching over the terrain), or (-1, -1).
func tile_under(origin: Vector3, dir: Vector3) -> Vector2i:
	var tile := float(_look.get("tile", 1.0))
	var p := origin
	for i in range(600):
		p += dir * 0.05
		var mp := Vector2(p.x, p.z) / tile
		if p.y <= height_at(mp):
			var t := Vector2i(roundi(mp.x), roundi(mp.y))
			return t if _heights.has(t) else Vector2i(-1, -1)
	return Vector2i(-1, -1)


func site_at(t: Vector2i) -> String:
	for site: Dictionary in region.get("sites", []):
		var at: Array = site.get("at", [0, 0])
		if Vector2i(int(at[0]), int(at[1])) == t:
			return String(site.get("id", ""))
	return ""


## An ambush the rules sprang: each ambusher rises out of cover where it hid (dust) and
## charges toward `toward`. units: [{id, content_id or kind, at: [x, y]}].
func spring_ambush(units: Array, toward: Array) -> void:
	var goal := to_world(Vector2(float(toward[0]), float(toward[1])))
	var last: Tween
	for u: Dictionary in units:
		var at: Array = u.get("at", [0, 0])
		var start := to_world(Vector2(float(at[0]), float(at[1])))
		var tok := _token(String(u.get("content_id", "mf_standard_pattern_i_everest")), "mech" if String(u.get("kind", "mech")) != "pilot" else "foot")
		tok.name = "Ambusher_" + String(u.get("id", ""))
		add_child(tok)
		ambushers.append(tok)
		tok.position = start + Vector3.DOWN * 0.5
		tok.rotation.y = atan2(-(goal.x - start.x), -(goal.z - start.z))
		Fx.dust(self, start, 10, Color(0.55, 0.5, 0.42, 0.7), 0.35, 0.6, 1.0)
		var stop := start.lerp(goal, 0.55)
		stop.y = height_at(Vector2(stop.x, stop.z) / float(_look.get("tile", 1.0)))
		var tw := tok.create_tween()
		tw.tween_property(tok, "position", start, Fx.t(0.45)).set_ease(Tween.EASE_OUT)
		tw.tween_callback(func() -> void: tok.set_walk(1.0))
		tw.tween_method(func(k: float) -> void:
			tok.position = start.lerp(stop, k)
			tok.walk_phase += 0.25, 0.0, 1.0, Fx.t(1.1))
		tw.tween_callback(func() -> void: tok.set_walk(0.0))
		last = tw
	if last:
		await last.finished


func clear_ambush() -> void:
	for a in ambushers:
		if is_instance_valid(a):
			a.queue_free()
	ambushers.clear()
