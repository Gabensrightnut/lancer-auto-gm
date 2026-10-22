class_name ZoneLayer
extends Node3D
## Areas left on the field (state.zones, see src/core/rules/zones.gd): smoke, sealant,
## caltrops, bunker, javelin rockets, cloaking field, mag field, burning cloud, holograms,
## Enclave dome and the HORUS fields. Each is drawn as tinted spaces with an outline, a
## label, and a little dressing in its own style (smoke puffs, caltrop spikes, a bunker wall,
## target rings...). Zones that follow a unit (cells empty, a radius) are redrawn as it moves.
## Fed whole lists (set_zones) or by events (zone_created / zone_removed).

const STYLE := {
	"smoke": {"color": Color(0.7, 0.72, 0.75), "label": "SMOKE"},
	"smoke_cloud": {"color": Color(1.0, 0.45, 0.15), "label": "BURNING CLOUD"},
	"sealant": {"color": Color(0.92, 0.95, 0.98), "label": "SEALANT"},
	"caltrops": {"color": Color(0.85, 0.3, 0.2), "label": "CALTROPS"},
	"bunker": {"color": Color(0.35, 0.6, 1.0), "label": "BUNKER"},
	"javelin": {"color": Color(1.0, 0.25, 0.2), "label": "JAVELIN"},
	"cloak": {"color": Color(0.45, 0.75, 1.0), "label": "CLOAKING FIELD"},
	"mag_field": {"color": Color(0.7, 0.35, 1.0), "label": "MAG FIELD"},
	"hologram": {"color": Color(0.3, 1.0, 0.95), "label": "HOLOGRAM"},
	"enclave": {"color": Color(0.4, 0.9, 1.0), "label": "ENCLAVE"},
	"flash": {"color": Color(1.0, 0.95, 0.75), "label": "FLASH: can't see out"},
	"hardlight": {"color": Color(0.35, 0.8, 1.0), "label": "HARDLIGHT: blocks sight and attacks"},
	"blink": {"color": Color(0.7, 0.45, 1.0), "label": "BLINKSHIELD: nothing crosses"},
	"oasis": {"color": Color(0.35, 1.0, 0.7), "label": "OASIS WALL: hard cover beside it"},
}
## Barrier zones get walls on their outer edge: [height, alpha].
const WALLS := {"hardlight": [1.4, 0.32], "blink": [2.0, 0.4], "oasis": [0.45, 0.6], "enclave": [0.0, 0.0]}

var battle: BattleView
var zones: Dictionary = {}  # id -> zone dict
var _nodes: Dictionary = {}  # id -> Node3D


func _init(view: BattleView = null) -> void:
	battle = view
	name = "Zones"


func set_zones(list: Array) -> void:
	var keep := {}
	for z: Dictionary in list:
		keep[String(z.get("id", ""))] = true
		if not zones.has(String(z.get("id", ""))) or zones[String(z["id"])] != z:
			add_zone(z)
	for id: String in zones.keys():
		if not keep.has(id):
			remove_zone(id)


func add_zone(z: Dictionary) -> void:
	var id := String(z.get("id", str(zones.size())))
	remove_zone(id)
	zones[id] = z.duplicate(true)
	var n := Node3D.new()
	n.name = "Zone_" + id
	add_child(n)
	_nodes[id] = n
	_build(n, zones[id])


func remove_zone(id: String) -> void:
	if _nodes.has(id):
		(_nodes[id] as Node).queue_free()
	_nodes.erase(id)
	zones.erase(id)


## Spaces a zone covers now: its own cells, or a radius around its owner/center.
func cells_of(z: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Variant in z.get("cells", []):
		out.append(Vector2i(int(c[0]), int(c[1])))
	if out.is_empty() and z.has("radius"):
		var center := Vector2i(int(z.get("center", [0, 0])[0]), int(z.get("center", [0, 0])[1]))
		var owner: MechView = battle.units.get(String(z.get("owner", "")))
		if owner and String(z.get("kind", "")) in ["cloak", "enclave"]:
			center = owner.cell
		for c: Vector2i in battle.map.grid.cells_within(center, int(z["radius"])):
			if battle.map.has_cell(c):
				out.append(c)
	return out


func _process(_delta: float) -> void:
	# Zones that follow their owner: redraw when the owner has moved.
	for id: String in zones.keys():
		var z: Dictionary = zones[id]
		if (z.get("cells", []) as Array).is_empty() and z.has("radius"):
			var owner: MechView = battle.units.get(String(z.get("owner", "")))
			if owner and (_nodes[id] as Node3D).get_meta("at", Vector2i(-999, -999)) != owner.cell:
				add_zone(z)


func _build(n: Node3D, z: Dictionary) -> void:
	var kind := String(z.get("kind", ""))
	var st: Dictionary = STYLE.get(kind, {"color": Color(0.8, 0.8, 0.5), "label": String(z.get("label", kind)).to_upper()})
	var col: Color = st["color"]
	var cells := cells_of(z)
	var owner: MechView = battle.units.get(String(z.get("owner", "")))
	if owner:
		n.set_meta("at", owner.cell)
	if cells.is_empty():
		return
	var fill := SurfaceTool.new()
	fill.begin(Mesh.PRIMITIVE_TRIANGLES)
	fill.set_color(Color.WHITE)
	var line := SurfaceTool.new()
	line.begin(Mesh.PRIMITIVE_TRIANGLES)
	line.set_color(Color.WHITE)
	var sum := Vector3.ZERO
	for c in cells:
		var y := battle.map.ground_height(c) * GridLayout.LEVEL_HEIGHT + 0.025
		battle.terrain.add_cell_fill(fill, c, y, 0.04)
		battle.terrain.add_outline(line, c, y + 0.004, 0.02, 0.03)
		sum += battle.cell_pos(c, battle.map.ground_height(c))
	_mesh(n, fill, Color(col.r, col.g, col.b, 0.22))
	_mesh(n, line, Color(col.r, col.g, col.b, 0.75))
	var center := sum / cells.size()
	match kind:
		"smoke", "smoke_cloud":
			var pts: Array = []
			for c in cells:
				pts.append(battle.cell_pos(c, battle.map.ground_height(c)))
			Fx.smoke_cloud(n, pts, 1.0)
			if kind == "smoke_cloud":
				for c in cells.slice(0, 6):
					Fx.fire(n, battle.cell_pos(c, battle.map.ground_height(c)), 0.35)
		"caltrops":
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(String(z.get("id", "")))
			var spike := MeshKit.cylinder(0.035, 0.12, 4, 0.0)
			var m := MeshKit.paint(Color(0.25, 0.24, 0.23), 0.7, 0.4, 0.0)
			for c in cells:
				var p := battle.cell_pos(c, battle.map.ground_height(c))
				for i in range(7):
					MeshKit.part(n, spike, m, p + Vector3(rng.randf_range(-0.4, 0.4), 0.06, rng.randf_range(-0.4, 0.4)), Vector3(rng.randf_range(-30, 30), 0, rng.randf_range(-30, 30)))
		"sealant":
			var foam := MeshKit.paint(Color(0.93, 0.95, 0.97), 0.0, 0.95, 0.0)
			var rng2 := RandomNumberGenerator.new()
			rng2.seed = hash(String(z.get("id", "")))
			for c in cells:
				var p := battle.cell_pos(c, battle.map.ground_height(c))
				for i in range(4):
					MeshKit.part(n, MeshKit.sphere(rng2.randf_range(0.12, 0.22), 8), foam, p + Vector3(rng2.randf_range(-0.3, 0.3), 0.02, rng2.randf_range(-0.3, 0.3)), Vector3.ZERO, Vector3(1, 0.35, 1))
		"bunker":
			var wall := MeshKit.paint(Color(0.45, 0.47, 0.42), 0.4, 0.6, 0.2)
			for c in cells:
				var p := battle.cell_pos(c, battle.map.ground_height(c))
				MeshKit.part(n, MeshKit.chamfer_box(Vector3(0.8, 0.5, 0.8), 0.05), wall, p + Vector3.UP * 0.25)
		"javelin":
			for c in cells:
				var p := battle.cell_pos(c, battle.map.ground_height(c))
				for r: float in [0.35, 0.2]:
					var ring := MeshInstance3D.new()
					var tor := TorusMesh.new()
					tor.inner_radius = r - 0.025
					tor.outer_radius = r
					tor.rings = 24
					ring.mesh = tor
					ring.material_override = MeshKit.fx_material(col, 2.0)
					ring.position = p + Vector3.UP * 0.05
					n.add_child(ring)
		"cloak", "enclave":
			var dome := MeshInstance3D.new()
			var sph := SphereMesh.new()
			var r := float(z.get("radius", 2)) + 0.5
			sph.radius = r
			sph.height = r * 2.0
			dome.mesh = sph
			var dm := MeshKit.overlay_material(Color(col.r, col.g, col.b, 0.1), false, false)
			dome.material_override = dm
			dome.scale = Vector3(1, 0.55, 1)
			dome.position = center
			n.add_child(dome)
	if WALLS.has(kind) and float(WALLS[kind][0]) > 0.0:
		_edge_walls(n, cells, col, float(WALLS[kind][0]), float(WALLS[kind][1]), kind == "oasis")
	if kind == "flash":
		var haze := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 1.0
		sph.height = 2.0
		haze.mesh = sph
		haze.material_override = MeshKit.overlay_material(Color(1.0, 0.97, 0.85, 0.22), false, false)
		var r := sqrt(float(cells.size())) * 0.55 + 0.4
		haze.scale = Vector3(r, r * 0.45, r)
		haze.position = center
		n.add_child(haze)
		Fx.light_flash(n, center + Vector3.UP * 0.6, Color(1.0, 0.95, 0.8), 2.5, r * 2.5, 99999.0)
	var l := Label3D.new()
	l.text = String(st["label"])
	l.font_size = 16
	l.outline_size = 6
	l.modulate = col.lightened(0.2)
	l.outline_modulate = Color(0, 0, 0, 0.9)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0008
	l.position = center + Vector3.UP * 0.35
	l.add_to_group(LabelDeclutter.GROUP_SCREEN_SIZED)
	n.add_child(l)


## Walls along the outside edge of a set of spaces: a translucent glowing panel per edge
## that faces a space outside the set (each cell's edges come from MeshKit.cell_shape, so
## no hex/square knowledge here). `segments` breaks low walls into blocks (Oasis Wall).
func _edge_walls(n: Node3D, cells: Array[Vector2i], col: Color, height: float, alpha: float, segments: bool) -> void:
	var shape := MeshKit.cell_shape(battle.map.grid)
	var corners: PackedVector2Array = shape["corners"]
	var inside := {}
	for c in cells:
		inside[c] = true
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color.WHITE)
	var rim := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	rim.set_color(Color.WHITE)
	for c in cells:
		var lv := battle.map.ground_height(c)
		var ctr := battle.cell_pos(c, lv)
		for i in range(corners.size()):
			var a2 := corners[i]
			var b2 := corners[(i + 1) % corners.size()]
			var mid := (a2 + b2) * 0.5
			var across := battle.map.grid.from_world(ctr + Vector3(mid.x, 0, mid.y) * 2.0)
			if inside.has(across):
				continue
			var a := ctr + Vector3(a2.x, 0.02, a2.y)
			var b := ctr + Vector3(b2.x, 0.02, b2.y)
			if segments:
				a = a.lerp(b, 0.08)
				b = b.lerp(ctr + Vector3(a2.x, 0.02, a2.y), 0.08)
			var up := Vector3.UP * height
			var out := Vector3(mid.x, 0, mid.y).normalized()
			MeshKit.add_quad(st, a, b, b + up, a + up, out)
			MeshKit.add_quad(st, b, a, a + up, b + up, -out)
			var t := Vector3.UP * 0.03
			MeshKit.add_quad(rim, a + up - t, b + up - t, b + up + t, a + up + t, out)
	var wall := MeshInstance3D.new()
	wall.mesh = st.commit()
	wall.material_override = MeshKit.overlay_material(Color(col.r, col.g, col.b, alpha), false, false)
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(wall)
	var top := MeshInstance3D.new()
	top.mesh = rim.commit()
	top.material_override = MeshKit.fx_material(col, 2.2)
	n.add_child(top)


func _mesh(n: Node3D, st: SurfaceTool, c: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = MeshKit.overlay_material(c, false, false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
