class_name WorldKits
extends RefCounted
## Culture/era kits at walking (human) scale, for on-foot hubs. Same cultures, palettes and
## facade shader as the battle maps, sized in meters: a person is about 1.8 m.
##
## Public API (all static; every culture argument takes story ids or map ids):
##   culture_id(id) -> String                    map id: "medieval", "old_west", "retro", "cyberpunk",
##                                                "east_asian", "union", or "" (plain frontier)
##   build_hub_building(culture, spot, seed) -> Node3D
##       spot: {kind, size: [w, d, h]} (HubLayout). Origin at the footprint's center on the
##       ground, front (door) toward +Z. Walls stay inside w x d; roofs and porches stick out at
##       most ROOF_OVERHANG. kind "landing" / "plaza" return an empty node.
##   build_hub_prop(culture, kind, seed) -> Node3D
##       kind: "lamp", "crate", "barrel", "bench", "planter", "cart". Origin on the ground.
##       Footprint radius: PROP_RADIUS[kind].
##   hub_prop_kinds(culture) -> Array            the kinds that suit this culture, most common first
##   build_hub_centerpiece(culture, seed) -> Node3D   for the middle of the plaza (radius 1.6 m)
##   hub_ground(culture) -> {"ground": Color, "pave": Color}
##   apply_hub_environment(culture, env, sun)    sky, sun and fog to match (WorldAtmosphere)
## Nothing here carries text or lore: signs are blank panels; the caller adds names.

## Meters per facade "level" (one floor).
const FLOOR := 3.0
const ROOF_OVERHANG := 0.6
## Meta on lights that only burn after dark (lamps, lanterns, fires): set_hub_time turns them.
const NIGHT_LIGHT := "hub_night_light"
## The clock's times of day over a culture's own look (its kit is its daytime): sun angle and
## color, sky, ambient light, fog, and how many windows are lit. The neon city's own kit is
## its night; by day it is a grey smoggy overcast with the signs still burning.
const TIMES := {
	"dawn": {"sun_pitch": -9.0, "sun_yaw": -100.0, "sun_color": "#ffb48a", "sun_scale": 0.55, "ambient_scale": 0.65,
		"top": "#4a5a8a", "horizon": "#ffb898", "haze_color": "#ffb090", "fog_color": "#b8a0a0", "exposure": 0.95, "lit": 0.3},
	"day": {},
	"evening": {"sun_pitch": -8.0, "sun_yaw": 80.0, "sun_color": "#ff9858", "sun_scale": 0.6, "ambient_scale": 0.6,
		"top": "#34446e", "horizon": "#ff9a64", "haze_color": "#ff8a50", "fog_color": "#a07868", "exposure": 1.0, "lit": 0.5},
	"night": {"sun_pitch": -42.0, "sun_yaw": 30.0, "sun_color": "#8aa4ff", "sun_scale": 0.12, "ambient_scale": 0.35,
		"top": "#04060e", "horizon": "#141c30", "haze_color": "#1a2440", "fog_color": "#0e1420", "exposure": 1.3, "lit": 0.75, "stars": 1.3},
}
const NEON_DAY := {"sun_pitch": -40.0, "sun_color": "#d8d4e0", "sun_energy": 1.3, "ambient": 0.6, "ambient_color": "#8a8498",
	"top": "#6a6a7c", "horizon": "#a8a0ac", "haze_color": "#9a90a0", "fog_color": "#7a7484", "exposure": 1.0, "stars": 0.0}

const PROP_RADIUS := {"lamp": 0.25, "crate": 0.6, "barrel": 0.4, "bench": 0.8, "planter": 0.6, "cart": 1.0}
## Story's hub culture ids -> map culture ids.
const ALIASES := {"medieval_tech": "medieval", "retrofuturistic": "retro", "union_core": "union", "frontier_colony": ""}
## Landscape whose sky and light fit a culture's hub.
const HUB_LANDSCAPE := {"medieval": "grassy_hills", "old_west": "desert_mesas", "retro": "grassy_hills",
	"cyberpunk": "city", "east_asian": "grassy_hills", "union": "grassy_hills", "": "desert_mesas"}
## The plain frontier look when no culture is given: prefab metal and concrete.
const FRONTIER := {
	"materials": ["metal", "concrete", "metal"],
	"walls": ["#8a8478", "#7a7e80", "#9a8e78", "#6e7478"],
	"trim": "#4a4a48", "glass": "#1e2428", "window_light": "#ffc890", "lit_windows": 0.15,
	"roof": "#5a5a58", "roof_surface": "metal", "roof_edge": "parapet", "floors": 1, "bay": 0.4,
	"window_w": 0.5, "window_h": 0.45, "storefront": 1, "awning_colors": ["#6a5a40", "#4a5a6a"],
	"street": {"lamp_style": "post", "lamp_color": "#ffd8a0"}}
## Roof shape per culture.
const ROOFS := {"medieval": "gable", "old_west": "false_front", "retro": "flat", "cyberpunk": "flat",
	"east_asian": "hip", "union": "flat", "": "flat"}


static func culture_id(id: String) -> String:
	id = str(ALIASES.get(id, id))
	if id == "" or WorldStyle.cultures().has(id):
		return id
	return ""


static func _arch(culture: String) -> Dictionary:
	var c := culture_id(culture)
	if c == "":
		return FRONTIER.duplicate(true)
	var style := WorldStyle.resolve("%s/%s" % [HUB_LANDSCAPE.get(c, "grassy_hills"), c])
	var a: Dictionary = (style.get("architecture", {}) as Dictionary).duplicate(true)
	# Hub buildings are small and whole: one floor per level, no war damage, no skyline.
	a["floors"] = 1
	a["ruined"] = 0.0
	a["burning"] = 0.0
	a["bay"] = clampf(float(a.get("bay", 0.35)) * 1.2, 0.35, 0.5)
	return a


static func _pick(list: Array, f: float) -> Variant:
	return list[int(f * list.size()) % list.size()]


# --- Buildings ---------------------------------------------------------------------------

static func build_hub_building(culture: String, spot: Dictionary, seed_value: int = 0) -> Node3D:
	var root := Node3D.new()
	root.name = "HubBuilding"
	var kind := str(spot.get("kind", "bar"))
	if kind in ["landing", "plaza"]:
		return root
	var c := culture_id(culture)
	var arch := _arch(c)
	var key := "hb%d%s" % [seed_value, kind]
	var sz: Array = spot.get("size", [8.0, 6.0, 4.0])
	var w := float(sz[0])
	var d := float(sz[1])
	var h := maxf(float(sz[2]), 2.8)
	# The facade shader works in levels: build at 1/FLOOR scale and scale the body up.
	var body := Node3D.new()
	body.name = "Body"
	body.scale = Vector3.ONE * FLOOR
	root.add_child(body)
	var mats: Array = arch.get("materials", ["concrete"])
	var walls: Array = arch.get("walls", ["#9a948a"])
	var type: int = CityBuilder.TYPES.get(str(_pick(mats, WorldRand.f(key, 1))), 0)
	var wall_col := WorldStyle.color(_pick(walls, WorldRand.f(key, 2)))
	wall_col.a = WorldRand.f(key, 3)
	var u := Vector3(w, h, d) / FLOOR
	var roof_shape := str(ROOFS.get(c, "flat"))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA_FLOAT)
	var corners := [Vector3(-u.x, 0, -u.z) * 0.5, Vector3(u.x, 0, -u.z) * 0.5, Vector3(u.x, 0, u.z) * 0.5, Vector3(-u.x, 0, u.z) * 0.5]
	for i in range(4):
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		var out := ((a + b) * 0.5).normalized()
		CityBuilder._wall(st, a, b, 0.0, u.y, out, wall_col, Color(a.distance_to(b), u.y, 0.0, type))
	CityBuilder._cap(st, corners[0], corners[1], corners[2], corners[3], u.y, wall_col, Color(1.0, u.y, 0.0, type))
	if roof_shape == "flat":
		var edge := str(arch.get("roof_edge", "parapet"))
		var rim_col := Color(0.85, 0.87, 0.9, wall_col.a) if edge == "chrome" else wall_col
		var rim_type := 3 if edge == "chrome" else type
		for i in range(4):
			var a: Vector3 = corners[i]
			var b: Vector3 = corners[(i + 1) % 4]
			var out := ((a + b) * 0.5).normalized()
			CityBuilder._wall(st, a, b, u.y, u.y + 0.06, out, rim_col, Color(a.distance_to(b), u.y + 0.06, 0.0, rim_type))
			CityBuilder._cap(st, a, b, a - out * 0.04, b - out * 0.04, u.y + 0.06, rim_col, Color(1.0, u.y + 0.06, 0.0, rim_type))
	elif roof_shape == "false_front":
		# A tall square front facade hiding a low roof: the frontier boomtown look.
		var a: Vector3 = corners[2]
		var b: Vector3 = corners[3]
		var top := u.y + 0.35
		CityBuilder._wall(st, a, b, u.y, top, Vector3.BACK, wall_col, Color(a.distance_to(b), top, 0.0, type))
		CityBuilder._wall(st, b - Vector3(0, 0, 0.03), a - Vector3(0, 0, 0.03), u.y, top, Vector3.FORWARD, wall_col, Color(a.distance_to(b), top, 0.0, type))
		CityBuilder._cap(st, a, b, b - Vector3(0, 0, 0.03), a - Vector3(0, 0, 0.03), top, wall_col, Color(1.0, top, 0.0, type))
	var mi := MeshInstance3D.new()
	mi.name = "Walls"
	mi.mesh = st.commit()
	mi.material_override = CityBuilder.make_material(arch)
	body.add_child(mi)
	match roof_shape:
		"gable":
			_gable_roof(root, w, d, h, arch, key)
		"hip":
			_hip_roof(root, w, d, h, arch)
	_front(root, c, arch, kind, w, d, h, key)
	return root


## A pitched roof with the ridge running side to side, gable ends on the left and right.
static func _gable_roof(root: Node3D, w: float, d: float, h: float, arch: Dictionary, key: String) -> void:
	var roof_col := WorldStyle.color(arch.get("roof", "#6a3a2a"))
	var wall_col := WorldStyle.color(_pick(arch.get("walls", ["#a89c88"]), WorldRand.f(key, 2)))
	var o := ROOF_OVERHANG * 0.7
	var rise := minf(d * 0.45, 2.6)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := w * 0.5 + o
	var hd := d * 0.5 + o
	var ridge := h + rise
	for s: float in [-1.0, 1.0]:
		var eave := Vector3(0, h - o * rise / (d * 0.5), s * hd)
		var a := Vector3(-hw, eave.y, eave.z)
		var b := Vector3(hw, eave.y, eave.z)
		var c := Vector3(hw, ridge, 0)
		var dd := Vector3(-hw, ridge, 0)
		var n := Vector3(0, d * 0.5, s * rise).normalized()
		st.set_color(roof_col)
		MeshKit.add_quad(st, a, b, c, dd, n)
		MeshKit.add_quad(st, a + Vector3(0, -0.12, 0), b + Vector3(0, -0.12, 0), c + Vector3(0, -0.12, 0), dd + Vector3(0, -0.12, 0), -n)
	var mi := MeshInstance3D.new()
	mi.name = "Roof"
	mi.mesh = st.commit()
	mi.material_override = _tiled(roof_col)
	root.add_child(mi)
	# Gable walls (triangles above the side walls).
	var gt := SurfaceTool.new()
	gt.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s: float in [-1.0, 1.0]:
		var x := s * w * 0.5
		MeshKit.add_tri(gt, Vector3(x, h, -d * 0.5), Vector3(x, h, d * 0.5), Vector3(x, ridge - 0.05, 0), Vector3(s, 0, 0))
	var gm := MeshInstance3D.new()
	gm.name = "Gables"
	gm.mesh = gt.commit()
	gm.material_override = MeshKit.paint(wall_col, 0.0, 0.9, 0.2)
	root.add_child(gm)


## A hipped roof with upturned corners and wide eaves (East Asian style), plus a ridge cap.
static func _hip_roof(root: Node3D, w: float, d: float, h: float, arch: Dictionary) -> void:
	var roof_col := WorldStyle.color(arch.get("roof", "#3a4448"))
	var o := ROOF_OVERHANG
	var hw := w * 0.5 + o
	var hd := d * 0.5 + o
	var rise := minf(minf(w, d) * 0.35, 2.4)
	var ridge_half := maxf(hw - hd, 0.4)
	var lift := 0.35
	var y0 := h - 0.15
	var e := [Vector3(-hw, y0 + lift, -hd), Vector3(hw, y0 + lift, -hd), Vector3(hw, y0 + lift, hd), Vector3(-hw, y0 + lift, hd)]
	var mids := [Vector3(0, y0, -hd), Vector3(hw, y0, 0), Vector3(0, y0, hd), Vector3(-hw, y0, 0)]
	var r0 := Vector3(-ridge_half, h + rise, 0)
	var r1 := Vector3(ridge_half, h + rise, 0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(roof_col)
	# Each side: corner, sagging middle, corner, up to the ridge.
	var sides := [[e[0], mids[0], e[1], r1, r0], [e[1], mids[1], e[2], r1, r1], [e[2], mids[2], e[3], r0, r1], [e[3], mids[3], e[0], r0, r0]]
	for sd: Array in sides:
		var c0: Vector3 = sd[0]
		var m: Vector3 = sd[1]
		var c1: Vector3 = sd[2]
		var top_a: Vector3 = sd[4]
		var top_b: Vector3 = sd[3]
		var out := (m * Vector3(1, 0, 1)).normalized() + Vector3.UP
		MeshKit.add_tri(st, c0, m, top_a, out)
		MeshKit.add_tri(st, m, c1, top_b, out)
		MeshKit.add_tri(st, m, top_b, top_a, out)
		MeshKit.add_tri(st, c0, m, top_a, -out)
		MeshKit.add_tri(st, m, c1, top_b, -out)
		MeshKit.add_tri(st, m, top_b, top_a, -out)
	var mi := MeshInstance3D.new()
	mi.name = "Roof"
	mi.mesh = st.commit()
	mi.material_override = _tiled(roof_col)
	root.add_child(mi)
	var cap := MeshKit.part(root, MeshKit.chamfer_box(Vector3(ridge_half * 2.0 + 0.4, 0.22, 0.3), 0.04), MeshKit.paint(roof_col.darkened(0.3), 0.3, 0.6, 0.0), Vector3(0, h + rise + 0.08, 0))
	cap.name = "RidgeCap"


static func _tiled(col: Color) -> ShaderMaterial:
	return MeshKit.paint(col, 0.1, 0.75, 0.6)


## The plaza side: a door at human size, plus each culture's porch, awning, sign board,
## lanterns or neon. Sign boards are blank; the caller puts the building's name on them.
static func _front(root: Node3D, c: String, arch: Dictionary, kind: String, w: float, d: float, h: float, key: String) -> void:
	var z := d * 0.5
	var trim := WorldStyle.color(arch.get("trim", "#4a4a48"))
	var wood := MeshKit.paint(Color(0.32, 0.22, 0.14), 0.0, 0.85, 0.3)
	var dark := MeshKit.paint(Color(0.08, 0.07, 0.07), 0.2, 0.6, 0.0)
	var trim_m := MeshKit.paint(trim, 0.2, 0.7, 0.2)
	var big_door := kind in ["workshop", "printer"]
	var door_w := 3.2 if big_door else 1.3
	var door_h := 3.4 if big_door else 2.3
	# Door: a dark opening in a trim frame.
	MeshKit.part(root, MeshKit.chamfer_box(Vector3(door_w + 0.24, door_h + 0.12, 0.08), 0.02), trim_m, Vector3(0, (door_h + 0.12) * 0.5, z + 0.02))
	var door_mat := dark
	if c in ["medieval", "old_west", "east_asian"] and not big_door:
		door_mat = wood
	elif big_door:
		door_mat = MeshKit.paint(Color(0.32, 0.34, 0.36), 0.6, 0.5, 0.8)  # roll-up shutter
	MeshKit.part(root, MeshKit.chamfer_box(Vector3(door_w, door_h, 0.06), 0.01), door_mat, Vector3(0, door_h * 0.5, z + 0.05))
	var awn_cols: Array = arch.get("awning_colors", ["#6a5a40"])
	var awn := MeshKit.paint(WorldStyle.color(_pick(awn_cols, WorldRand.f(key, 7))), 0.05, 0.8, 0.0)
	var sign_y := minf(door_h + 0.8, h - 0.4)
	var board := MeshKit.paint(WorldStyle.color(_pick(arch.get("sign_colors", ["#d8c8a0"]), WorldRand.f(key, 8))), 0.1, 0.7, 0.0)
	match c:
		"old_west":
			# Covered boardwalk: plank deck, posts and a shed roof across the whole front.
			var porch := 1.8
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(w, 0.18, porch), 0.02), wood, Vector3(0, 0.09, z + porch * 0.5))
			for sx: float in [-0.46, -0.15, 0.15, 0.46]:
				MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.14, 2.8, 0.14), 0.02), wood, Vector3(sx * w, 1.5, z + porch - 0.12))
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(w + 0.2, 0.1, porch + 0.3), 0.02), wood, Vector3(0, 2.95, z + porch * 0.5), Vector3(-8, 0, 0))
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(w * 0.7, 0.8, 0.06), 0.02), board, Vector3(0, h + 0.5, z + 0.04))
			# Hitching rail.
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(2.2, 0.08, 0.08), 0.01), wood, Vector3(w * 0.3, 0.9, z + porch + 0.9))
			for sx: float in [-1.0, 1.0]:
				MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.1, 0.9, 0.1), 0.01), wood, Vector3(w * 0.3 + sx * 1.0, 0.45, z + porch + 0.9))
		"medieval":
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(1.6, 0.7, 0.06), 0.02), board, Vector3(door_w * 0.5 + 1.1, sign_y, z + 0.6), Vector3(0, 90, 0))
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.06, 0.06, 1.0), 0.01), wood, Vector3(door_w * 0.5 + 1.1, sign_y + 0.45, z + 0.5))
			_add_lantern(root, Vector3(-door_w * 0.5 - 0.5, 2.3, z + 0.2), WorldStyle.color(arch.get("street", {}).get("lamp_color", "#ffaa50")), true)
			# Banner down the wall.
			var banner := MeshKit.paint(WorldStyle.color(arch.get("banner", "#9a1e1e")), 0.0, 0.8, 0.0)
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.8, minf(2.2, h - 1.0), 0.03), 0.005), banner, Vector3(w * 0.32, h - minf(2.2, h - 1.0) * 0.5 - 0.3, z + 0.03))
		"east_asian":
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(door_w + 1.4, 0.1, 1.0), 0.02), awn, Vector3(0, door_h + 0.35, z + 0.5), Vector3(-12, 0, 0))
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.6, 1.6, 0.05), 0.01), board, Vector3(door_w * 0.5 + 0.7, 1.6, z + 0.04))
			for sx: float in [-1.0, 1.0]:
				_add_lantern(root, Vector3(sx * (door_w * 0.5 + 0.45), door_h + 0.05, z + 0.55), WorldStyle.color(arch.get("street", {}).get("lamp_color", "#ff7a40")), false)
		"cyberpunk":
			var neon_cols: Array = arch.get("neon_colors", ["#ff2aa8", "#20e8ff"])
			var nc := WorldStyle.color(_pick(neon_cols, WorldRand.f(key, 9)))
			var neon := MeshKit.mech_material(nc, 0.1, 0.5, nc * 2.2, false)
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(w * 0.9, 0.06, 0.06), 0.01), neon, Vector3(0, door_h + 0.2, z + 0.06))
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.12, minf(3.0, h - 0.8), 0.7), 0.02), MeshKit.paint(Color(0.08, 0.08, 0.1), 0.6, 0.4, 0.0), Vector3(w * 0.5 - 0.3, h * 0.5 + 0.6, z + 0.4))
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.14, minf(2.8, h - 1.0), 0.04), 0.01), neon, Vector3(w * 0.5 - 0.3, h * 0.5 + 0.6, z + 0.76))
			var holo := MeshInstance3D.new()
			var q := QuadMesh.new()
			q.size = Vector2(minf(w * 0.5, 3.0), 1.6)
			holo.mesh = q
			var hm := ShaderMaterial.new()
			hm.shader = CityProps.HOLO_SHADER
			hm.set_shader_parameter("tint", nc)
			hm.set_shader_parameter("seed", WorldRand.f(key, 10) * 10.0)
			holo.material_override = hm
			holo.position = Vector3(-w * 0.2, minf(h - 1.0, door_h + 1.3), z + 0.05)
			holo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(holo)
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(door_w + 1.2, 0.08, 1.2), 0.02), MeshKit.paint(Color(0.12, 0.12, 0.15), 0.7, 0.3, 0.0), Vector3(0, door_h + 0.45, z + 0.6))
		"retro":
			# Rounded canopy and a pylon sign with a ball on top.
			MeshKit.part(root, SmoothKit.rounded_box(Vector3(door_w + 2.4, 0.18, 1.4), 0.08), awn, Vector3(0, door_h + 0.35, z + 0.7))
			var chrome := MeshKit.paint(Color(0.85, 0.87, 0.9), 0.95, 0.15, 0.0)
			var accent := WorldStyle.color(arch.get("accent", "#40e0d0"))
			MeshKit.part(root, MeshKit.cylinder(0.08, h + 1.6, 10), chrome, Vector3(w * 0.5 - 0.4, (h + 1.6) * 0.5, z + 0.5))
			MeshKit.part(root, MeshKit.sphere(0.3, 12), MeshKit.mech_material(accent, 0.2, 0.3, accent * 1.5, false), Vector3(w * 0.5 - 0.4, h + 1.8, z + 0.5))
			MeshKit.part(root, SmoothKit.rounded_box(Vector3(0.12, 1.4, 0.9), 0.06), board, Vector3(w * 0.5 - 0.4, h * 0.7, z + 0.5))
		"union":
			var accent := WorldStyle.color(arch.get("accent", "#7ad8ff"))
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(door_w + 2.0, 0.12, 1.6), 0.04), MeshKit.paint(Color(0.92, 0.93, 0.95), 0.2, 0.3, 0.0), Vector3(0, door_h + 0.3, z + 0.8))
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(door_w + 1.8, 0.03, 0.06), 0.005), MeshKit.mech_material(accent, 0.0, 0.4, accent * 2.0, false), Vector3(0, door_h + 0.24, z + 1.58))
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(w * 0.5, 0.5, 0.05), 0.01), board, Vector3(0, minf(h - 0.5, door_h + 1.0), z + 0.04))
		_:
			# Frontier prefab: a flat awning on struts and a bolted sign board.
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(door_w + 1.8, 0.1, 1.3), 0.02), awn, Vector3(0, door_h + 0.35, z + 0.65), Vector3(-6, 0, 0))
			for sx: float in [-1.0, 1.0]:
				MeshKit.part(root, MeshKit.cylinder(0.04, 1.2, 6), trim_m, Vector3(sx * (door_w * 0.5 + 0.8), door_h + 0.05, z + 0.6), Vector3(55, 0, 0))
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(minf(w * 0.6, 4.0), 0.7, 0.06), 0.02), board, Vector3(0, minf(h - 0.45, door_h + 1.1), z + 0.04))


static func _add_lantern(root: Node3D, at: Vector3, color: Color, flame: bool) -> void:
	var node := Node3D.new()
	node.position = at
	root.add_child(node)
	var glow := MeshKit.mech_material(color, 0.0, 0.5, color * 2.5, false)
	if flame:
		MeshKit.part(node, MeshKit.chamfer_box(Vector3(0.22, 0.32, 0.22), 0.02), MeshKit.paint(Color(0.12, 0.1, 0.08), 0.6, 0.5, 0.0), Vector3.ZERO)
		MeshKit.part(node, MeshKit.chamfer_box(Vector3(0.16, 0.22, 0.16), 0.02), glow, Vector3.ZERO)
	else:
		MeshKit.part(node, SmoothKit.blob(Vector3(0.36, 0.48, 0.36), 1.0, 1.0, 1.0, 12), glow, Vector3.ZERO)
		MeshKit.part(node, MeshKit.cylinder(0.12, 0.06, 8), MeshKit.paint(Color(0.1, 0.08, 0.06), 0.3, 0.6, 0.0), Vector3(0, 0.26, 0))
	var light: OmniLight3D
	if flame:
		var fl := FlickerLight.new()
		fl.base_energy = 0.7
		light = fl
	else:
		light = OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.7
	light.omni_range = 4.0
	light.set_meta(NIGHT_LIGHT, true)
	node.add_child(light)


# --- Props -------------------------------------------------------------------------------

static func hub_prop_kinds(culture: String) -> Array:
	match culture_id(culture):
		"medieval":
			return ["barrel", "crate", "cart", "lamp", "bench"]
		"old_west":
			return ["barrel", "crate", "cart", "barrel", "lamp"]
		"east_asian":
			return ["planter", "lamp", "crate", "bench"]
		"union":
			return ["planter", "bench", "lamp"]
		"retro":
			return ["planter", "bench", "lamp", "crate"]
		"cyberpunk":
			return ["crate", "barrel", "lamp", "crate"]
	return ["crate", "barrel", "lamp", "crate"]


static func build_hub_prop(culture: String, kind: String, seed_value: int = 0) -> Node3D:
	var c := culture_id(culture)
	var arch := _arch(c)
	var root := Node3D.new()
	root.name = "HubProp_" + kind
	var key := "hp%d%s" % [seed_value, kind]
	var r := func(i: int) -> float: return WorldRand.f(key, i)
	var wood := MeshKit.paint(Color(0.4, 0.29, 0.18).darkened(0.15 * float(r.call(0))), 0.0, 0.85, 0.4)
	var metal := MeshKit.paint(Color(0.38, 0.4, 0.42), 0.7, 0.45, 0.5)
	var street: Dictionary = arch.get("street", {})
	var lamp_col := WorldStyle.color(street.get("lamp_color", "#ffd8a0"))
	match kind:
		"lamp":
			match c:
				"medieval":
					# Iron brazier on a stand.
					MeshKit.part(root, MeshKit.cylinder(0.05, 1.3, 6), metal, Vector3(0, 0.65, 0))
					MeshKit.part(root, MeshKit.cylinder(0.28, 0.25, 8, 0.18), MeshKit.paint(Color(0.15, 0.13, 0.12), 0.7, 0.5, 0.0), Vector3(0, 1.4, 0))
					_flames(root, Vector3(0, 1.55, 0), lamp_col)
				"east_asian":
					# Stone lantern.
					var stone := MeshKit.paint(Color(0.55, 0.53, 0.5), 0.0, 0.95, 0.6)
					MeshKit.part(root, MeshKit.cylinder(0.12, 0.9, 8), stone, Vector3(0, 0.45, 0))
					MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.45, 0.35, 0.45), 0.03), MeshKit.mech_material(lamp_col, 0.0, 0.6, lamp_col * 1.8, false), Vector3(0, 1.08, 0))
					MeshKit.part(root, MeshKit.cylinder(0.42, 0.25, 4, 0.05), stone, Vector3(0, 1.38, 0), Vector3(0, 45, 0))
					_light(root, Vector3(0, 1.1, 0), lamp_col, false)
				"cyberpunk":
					var nc := WorldStyle.color(_pick(arch.get("neon_colors", ["#20e8ff"]), float(r.call(1))))
					MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.12, 3.4, 0.12), 0.02), MeshKit.paint(Color(0.1, 0.1, 0.12), 0.7, 0.4, 0.0), Vector3(0, 1.7, 0))
					MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.05, 2.6, 0.14), 0.01), MeshKit.mech_material(nc, 0.0, 0.5, nc * 2.5, false), Vector3(0.07, 1.9, 0))
					_light(root, Vector3(0, 3.0, 0), nc, false)
				"retro":
					var chrome := MeshKit.paint(Color(0.85, 0.87, 0.9), 0.95, 0.15, 0.0)
					MeshKit.part(root, MeshKit.cylinder(0.06, 3.2, 10, 0.04), chrome, Vector3(0, 1.6, 0))
					MeshKit.part(root, SmoothKit.blob(Vector3(0.5, 0.5, 0.5), 1.0, 1.0, 1.0, 14), MeshKit.mech_material(lamp_col, 0.0, 0.3, lamp_col * 2.0, false), Vector3(0, 3.35, 0))
					_light(root, Vector3(0, 3.3, 0), lamp_col, false)
				"union":
					var white := MeshKit.paint(Color(0.92, 0.93, 0.95), 0.2, 0.3, 0.0)
					MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.16, 3.6, 0.16), 0.06), white, Vector3(0, 1.8, 0))
					MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.18, 0.9, 0.18), 0.06), MeshKit.mech_material(lamp_col, 0.0, 0.3, lamp_col * 2.0, false), Vector3(0, 3.2, 0))
					_light(root, Vector3(0, 3.2, 0), lamp_col, false)
				"old_west":
					MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.14, 2.4, 0.14), 0.02), wood, Vector3(0, 1.2, 0))
					MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.7, 0.08, 0.08), 0.01), wood, Vector3(0.3, 2.3, 0))
					_add_lantern(root, Vector3(0.55, 2.0, 0), lamp_col, true)
				_:
					MeshKit.part(root, MeshKit.cylinder(0.07, 3.6, 8), MeshKit.paint(Color(0.2, 0.2, 0.22), 0.8, 0.4, 0.0), Vector3(0, 1.8, 0))
					MeshKit.part(root, MeshKit.sphere(0.18), MeshKit.mech_material(lamp_col, 0.0, 0.3, lamp_col * 2.0, false), Vector3(0, 3.7, 0))
					_light(root, Vector3(0, 3.6, 0), lamp_col, false)
		"crate":
			var s := 0.6 + 0.5 * float(r.call(2))
			var mat := wood if c in ["medieval", "old_west", "east_asian", ""] else MeshKit.paint(WorldStyle.color(_pick(arch.get("walls", ["#6a6e72"]), float(r.call(3)))).darkened(0.2), 0.5, 0.5, 0.6)
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(s, s, s), 0.04), mat, Vector3(0, s * 0.5, 0), Vector3(0, float(r.call(4)) * 90.0, 0))
			if float(r.call(5)) < 0.5:
				var s2 := s * 0.6
				MeshKit.part(root, MeshKit.chamfer_box(Vector3(s2, s2, s2), 0.03), mat, Vector3(0.05, s + s2 * 0.5, 0.05), Vector3(0, float(r.call(6)) * 90.0, 0))
		"barrel":
			var col := Color(0.42, 0.3, 0.18) if c in ["medieval", "old_west", ""] else Color(0.25, 0.35, 0.4)
			var bm := MeshKit.paint(col, 0.3 if c in ["medieval", "old_west"] else 0.6, 0.6, 0.3)
			MeshKit.part(root, MeshKit.cylinder(0.32, 0.95, 12), bm, Vector3(0, 0.48, 0))
			for y in [0.2, 0.75]:
				MeshKit.part(root, MeshKit.cylinder(0.335, 0.05, 12), MeshKit.paint(Color(0.2, 0.2, 0.2), 0.7, 0.5, 0.0), Vector3(0, y, 0))
		"bench":
			var seat := wood
			var legs := metal
			if c == "union":
				seat = MeshKit.paint(Color(0.92, 0.93, 0.95), 0.2, 0.3, 0.0)
			elif c == "retro":
				seat = MeshKit.paint(WorldStyle.color(_pick(arch.get("awning_colors", ["#40c0b0"]), float(r.call(7)))), 0.2, 0.4, 0.0)
			elif c == "medieval":
				legs = wood
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(1.5, 0.08, 0.45), 0.02), seat, Vector3(0, 0.45, 0))
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(1.5, 0.4, 0.06), 0.02), seat, Vector3(0, 0.72, -0.2))
			for sx: float in [-0.6, 0.6]:
				MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.06, 0.45, 0.4), 0.01), legs, Vector3(sx, 0.22, 0))
		"planter":
			var pot := MeshKit.paint(Color(0.55, 0.5, 0.45) if c != "union" else Color(0.9, 0.91, 0.93), 0.1, 0.8, 0.3)
			MeshKit.part(root, MeshKit.cylinder(0.5, 0.6, 12, 0.45), pot, Vector3(0, 0.3, 0))
			var species := "cherry" if c == "east_asian" else ("bush" if c in ["union", "retro"] else "broadleaf")
			var leaf := Color(0.95, 0.68, 0.78) if c == "east_asian" else Color(0.3, 0.5, 0.2)
			var tree := MeshInstance3D.new()
			tree.mesh = Flora.plant(species, leaf, Color(0.3, 0.22, 0.15), int(float(r.call(8)) * 3.0))
			tree.material_override = WorldDressing.foliage_material(0.02, 2.5)
			tree.scale = Vector3.ONE * (1.4 if species != "bush" else 1.6)
			tree.position = Vector3(0, 0.55, 0)
			root.add_child(tree)
		"cart":
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(1.6, 0.5, 0.9), 0.03), wood, Vector3(0, 0.75, 0))
			for sx: float in [-1.0, 1.0]:
				var wheel := MeshKit.part(root, MeshKit.cylinder(0.42, 0.08, 12), MeshKit.paint(Color(0.25, 0.18, 0.12), 0.0, 0.9, 0.0), Vector3(0, 0.42, sx * 0.5))
				wheel.rotation_degrees = Vector3(90, 0, 0)
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(1.4, 0.06, 0.06), 0.01), wood, Vector3(1.4, 0.6, 0), Vector3(0, 0, 12))
			for i in range(3):
				MeshKit.part(root, MeshKit.sphere(0.2, 8), MeshKit.paint(Color(0.7, 0.55, 0.3).darkened(0.1 * i), 0.0, 0.9, 0.0), Vector3(-0.4 + 0.4 * i, 1.1, 0))
	return root


static func _light(root: Node3D, at: Vector3, color: Color, flicker: bool) -> void:
	var l: OmniLight3D
	if flicker:
		var fl := FlickerLight.new()
		fl.base_energy = 0.9
		l = fl
	else:
		l = OmniLight3D.new()
	l.light_color = color
	l.light_energy = 0.9
	l.omni_range = 6.0
	l.position = at
	l.set_meta(NIGHT_LIGHT, true)
	root.add_child(l)


static func _flames(root: Node3D, at: Vector3, color: Color) -> void:
	var p := WorldHazards._flames(PackedVector3Array([Vector3.ZERO]), color)
	p.position = at
	p.local_coords = true
	p.amount = 14
	p.scale_amount_min = 1.6
	p.scale_amount_max = 2.4
	root.add_child(p)
	_light(root, at + Vector3(0, 0.3, 0), color, true)


# --- Plaza, ground and sky ------------------------------------------------------------------

## The middle of the plaza (within 1.6 m): a well, a fountain, a stone lantern, a tree.
static func build_hub_centerpiece(culture: String, seed_value: int = 0) -> Node3D:
	var c := culture_id(culture)
	var root := Node3D.new()
	root.name = "HubCenterpiece"
	var stone := MeshKit.paint(Color(0.55, 0.52, 0.48), 0.05, 0.9, 0.5)
	var water := MeshKit.paint(Color(0.15, 0.3, 0.4), 0.6, 0.1, 0.0)
	match c:
		"medieval", "":
			MeshKit.part(root, MeshKit.cylinder(1.3, 0.8, 16), stone, Vector3(0, 0.4, 0))
			MeshKit.part(root, MeshKit.cylinder(1.05, 0.05, 16), water, Vector3(0, 0.78, 0))
			if c == "medieval":
				var wood := MeshKit.paint(Color(0.35, 0.25, 0.16), 0.0, 0.85, 0.3)
				for sx: float in [-1.0, 1.0]:
					MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.15, 2.0, 0.15), 0.02), wood, Vector3(sx * 1.1, 1.6, 0))
				MeshKit.part(root, MeshKit.cylinder(0.08, 2.4, 8), wood, Vector3(0, 2.4, 0), Vector3(0, 0, 90))
				MeshKit.part(root, MeshKit.cylinder(0.9, 0.5, 4, 0.05), MeshKit.paint(Color(0.42, 0.24, 0.18), 0.1, 0.75, 0.5), Vector3(0, 2.9, 0), Vector3(0, 45, 0))
		"old_west":
			# Water trough and a windpump.
			var wood := MeshKit.paint(Color(0.4, 0.29, 0.18), 0.0, 0.85, 0.4)
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(2.4, 0.6, 0.8), 0.04), wood, Vector3(0, 0.3, 0.6))
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(2.2, 0.04, 0.6), 0.01), water, Vector3(0, 0.56, 0.6))
			MeshKit.part(root, MeshKit.cylinder(0.5, 6.0, 4, 0.12), MeshKit.paint(Color(0.5, 0.5, 0.5), 0.6, 0.5, 0.0), Vector3(0, 3.0, -0.6))
			var hub := Spinner.new()
			hub.axis = Vector3.BACK
			hub.speed = 1.0
			hub.position = Vector3(0, 6.0, -0.2)
			root.add_child(hub)
			for k in range(10):
				var blade := Node3D.new()
				blade.rotation.z = TAU * k / 10.0
				hub.add_child(blade)
				MeshKit.part(blade, MeshKit.chamfer_box(Vector3(0.22, 1.0, 0.03), 0.01), MeshKit.paint(Color(0.6, 0.6, 0.6), 0.6, 0.5, 0.0), Vector3(0, 0.6, 0), Vector3(0, 20, 0))
		"east_asian":
			var tree := MeshInstance3D.new()
			tree.mesh = Flora.plant("cherry", Color(0.96, 0.7, 0.8), Color(0.3, 0.2, 0.15), seed_value % 3)
			tree.material_override = WorldDressing.foliage_material(0.02, 3.0)
			tree.scale = Vector3.ONE * 2.6
			root.add_child(tree)
			MeshKit.part(root, MeshKit.cylinder(1.5, 0.35, 8), stone, Vector3(0, 0.17, 0))
		"retro", "union":
			var white := MeshKit.paint(Color(0.92, 0.93, 0.95), 0.2, 0.3, 0.0)
			MeshKit.part(root, MeshKit.cylinder(1.5, 0.5, 24), white, Vector3(0, 0.25, 0))
			MeshKit.part(root, MeshKit.cylinder(1.3, 0.05, 24), water, Vector3(0, 0.48, 0))
			MeshKit.part(root, MeshKit.cylinder(0.12, 1.6, 10), MeshKit.paint(Color(0.85, 0.87, 0.9), 0.95, 0.15, 0.0), Vector3(0, 1.0, 0))
			var spray := CPUParticles3D.new()
			spray.amount = 60
			spray.lifetime = 1.2
			spray.direction = Vector3.UP
			spray.spread = 18.0
			spray.initial_velocity_min = 2.5
			spray.initial_velocity_max = 3.2
			spray.position = Vector3(0, 1.8, 0)
			var q := QuadMesh.new()
			q.size = Vector2(0.08, 0.08)
			q.material = WorldHazards._quad_material(Color(0.8, 0.9, 1.0, 0.7), false)
			spray.mesh = q
			root.add_child(spray)
		"cyberpunk":
			var nc := Color(0.15, 0.9, 1.0)
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.9, 3.0, 0.9), 0.08), MeshKit.paint(Color(0.1, 0.1, 0.12), 0.7, 0.4, 0.0), Vector3(0, 1.5, 0))
			for k in range(4):
				var holo := MeshInstance3D.new()
				var q := QuadMesh.new()
				q.size = Vector2(0.9, 1.3)
				holo.mesh = q
				var hm := ShaderMaterial.new()
				hm.shader = CityProps.HOLO_SHADER
				hm.set_shader_parameter("tint", nc if k % 2 == 0 else Color(1.0, 0.25, 0.7))
				hm.set_shader_parameter("seed", float(k) + seed_value)
				holo.material_override = hm
				holo.rotation.y = k * PI * 0.5
				holo.position = Vector3(sin(k * PI * 0.5), 0, cos(k * PI * 0.5)) * 0.47 + Vector3(0, 2.0, 0)
				root.add_child(holo)
	return root


static func hub_ground(culture: String) -> Dictionary:
	var c := culture_id(culture)
	var style := WorldStyle.resolve(str(HUB_LANDSCAPE.get(c, "desert_mesas")))
	var g: Dictionary = style.get("ground", {})
	var ground := WorldStyle.color(g.get("top_b", "#8a7a5a"))
	if c == "cyberpunk":
		ground = Color(0.2, 0.2, 0.24)
	var pave: Color = {"medieval": Color(0.55, 0.52, 0.48), "old_west": Color(0.62, 0.5, 0.36), "retro": Color(0.82, 0.8, 0.76),
		"cyberpunk": Color(0.3, 0.3, 0.36), "east_asian": Color(0.6, 0.58, 0.54), "union": Color(0.88, 0.89, 0.9)}.get(c, Color(0.58, 0.54, 0.48))
	return {"ground": ground, "pave": pave}


## Sky, sun and fog to match the culture (fog thinned for a small town seen up close), at the
## story clock's time of day (TownLife.period: dawn, day, evening, night).
static func apply_hub_environment(culture: String, env: Environment, sun: DirectionalLight3D, period: String = "day") -> void:
	var c := culture_id(culture)
	var kit := str(HUB_LANDSCAPE.get(c, "desert_mesas"))
	if c != "":
		kit += "/" + c
	var shadow := sun.directional_shadow_max_distance
	var style := WorldStyle.resolve(kit)
	time_of_day(style, period)
	WorldAtmosphere.apply(style, env, sun)
	env.fog_density *= 0.35
	env.volumetric_fog_density *= 0.35
	sun.directional_shadow_max_distance = maxf(shadow, sun.directional_shadow_max_distance)



## Lays the clock's time of day over a resolved style (in place). Day is the kit as it is.
static func time_of_day(style: Dictionary, period: String) -> void:
	var neon := str(style.get("culture", "")) == "cyberpunk"
	var t: Dictionary = TIMES.get(period, {})
	var light: Dictionary = style.get("light", {})
	var sky: Dictionary = style.get("sky", {})
	style["light"] = light
	style["sky"] = sky
	if neon:
		# The neon city's kit is its night: only the daylight hours change it.
		if period == "night":
			return
		t = NEON_DAY.duplicate()
		if period != "day":
			t["sun_color"] = TIMES[period]["sun_color"]
			t["sun_pitch"] = TIMES[period]["sun_pitch"]
			t["horizon"] = TIMES[period]["horizon"]
	if t.is_empty():
		return
	for k: String in ["sun_pitch", "sun_yaw", "sun_color", "sun_energy", "ambient", "ambient_color", "fog_color", "exposure"]:
		if t.has(k):
			light[k] = t[k]
	if t.has("sun_scale"):
		light["sun_energy"] = float(light.get("sun_energy", 2.2)) * float(t["sun_scale"])
	if t.has("ambient_scale"):
		light["ambient"] = float(light.get("ambient", 0.5)) * float(t["ambient_scale"])
	for k: String in ["top", "horizon", "haze_color", "stars"]:
		if t.has(k):
			sky[k] = t[k]
	if t.has("top"):
		sky["clouds"] = float(sky.get("clouds", 0.3)) * (0.5 if period == "night" else 1.0)


## Switches a built hub to the clock's time: lamps, lanterns and fires burn after dark (and at
## dawn), and more windows are lit the later it gets. `root` is the hub's world node.
static func set_hub_time(root: Node, period: String) -> void:
	var dark := period in ["dawn", "evening", "night"]
	var lit := float((TIMES.get(period, {}) as Dictionary).get("lit", 0.0))
	_set_time(root, dark, lit)


static func _set_time(n: Node, dark: bool, lit: float) -> void:
	if n is Light3D and n.has_meta(NIGHT_LIGHT):
		(n as Light3D).visible = dark
	if n is MeshInstance3D and n.name == "Walls" and (n as MeshInstance3D).material_override is ShaderMaterial:
		var m := (n as MeshInstance3D).material_override as ShaderMaterial
		if not m.has_meta("base_lit"):
			m.set_meta("base_lit", float(m.get_shader_parameter("lit") if m.get_shader_parameter("lit") != null else 0.05))
		m.set_shader_parameter("lit", maxf(float(m.get_meta("base_lit")), lit))
	for ch in n.get_children():
		_set_time(ch, dark, lit)
