class_name MechPaint
extends RefCounted
## Cosmetic paint for a built MechModel: primary, secondary and glow colors plus decals
## (markings). Purely visual; the model always shows the real loadout.
##
## Paint format (stored with a mech, e.g. mech["paint"]; every key optional, missing = factory):
##   {"primary": "#rrggbb", "secondary": "#rrggbb", "glow": "#rrggbb", "markings": "#rrggbb",
##    "decals": {"chest": "chevron", "shoulder_l": "roundel", "shoulder_r": "number:07",
##               "leg_l": "stripes", "leg_r": ""}}
##
## How colors are found: every paint surface is sorted into roles. Imported frames name their
## materials (primary, secondary, glow...); for code-built and sculpted frames the two biggest
## color groups by surface area are primary and secondary, emissive parts are glow, and dark
## or bare-metal parts stay as they are. Repainting keeps each part's shade relative to its
## group, so panel variation survives a new color.

const DECAL_SLOTS := ["chest", "shoulder_l", "shoulder_r", "leg_l", "leg_r"]
const DECALS := ["", "chevron", "stripes", "roundel", "star", "hazard", "bars", "diamond", "number"]
const DECAL_NAMES := {
	"": "None", "chevron": "Chevron", "stripes": "Stripes", "roundel": "Roundel", "star": "Star",
	"hazard": "Hazard bars", "bars": "Rank bars", "diamond": "Diamond", "number": "Number",
}
const SLOT_NAMES := {"chest": "Chest", "shoulder_l": "Left shoulder", "shoulder_r": "Right shoulder", "leg_l": "Left leg", "leg_r": "Right leg"}

static var _decal_tex: Dictionary = {}


## The factory scheme for a frame (its manufacturer's colors, no decals).
static func factory(frame: Dictionary) -> Dictionary:
	var pal := MechStyles.palette(String(frame.get("source", "GMS")))
	return {"primary": "#" + (pal["primary"] as Color).to_html(false), "secondary": "#" + (pal["secondary"] as Color).to_html(false),
		"glow": "#" + (pal["glow"] as Color).to_html(false), "markings": "#e8e4da", "decals": {}}


## The model's own (factory) colors as paint hex strings: primary, secondary, glow.
static func model_colors(model: MechModel) -> Dictionary:
	_slots(model)
	var out := {}
	var refs: Dictionary = model.get_meta("paint_refs", {})
	for k: String in refs:
		out[k] = "#" + (refs[k] as Color).to_html(false)
	return out


## Repaints `model` (must be inside the tree for decals to find their places). An empty
## paint restores the factory look.
static func apply(model: MechModel, paint: Dictionary) -> void:
	var slots := _slots(model)
	var refs: Dictionary = model.get_meta("paint_refs", {})
	for s: Dictionary in slots:
		var orig: ShaderMaterial = s["mat"]
		var role := String(s["role"])
		var mat: Material = orig
		if role in ["primary", "secondary"] and paint.has(role) and refs.has(role):
			mat = orig.duplicate()
			mat.set_shader_parameter("base_color", _tint(orig.get_shader_parameter("base_color"), refs[role], Color(String(paint[role]))))
		elif role == "glow" and paint.has("glow"):
			mat = orig.duplicate()
			var e: Color = orig.get_shader_parameter("emission_color")
			var strength := maxf(maxf(e.r, e.g), e.b)
			var g := Color(String(paint["glow"]))
			mat.set_shader_parameter("emission_color", g * maxf(strength, 0.3))
		var mi: MeshInstance3D = s["mi"]
		if int(s["surface"]) < 0:
			mi.material_override = mat
		else:
			mi.set_surface_override_material(int(s["surface"]), mat)
	_apply_decals(model, paint)


## Random scheme: primary and secondary from the palette grid, a glow that contrasts, and
## a couple of markings.
static func random_paint(rng: RandomNumberGenerator) -> Dictionary:
	var pal := MechPaint.palette_grid()
	var p: Color = pal[rng.randi() % pal.size()]
	var s: Color = pal[rng.randi() % pal.size()]
	while s.is_equal_approx(p):
		s = pal[rng.randi() % pal.size()]
	var glows := [Color(0.35, 0.85, 1.0), Color(1.0, 0.6, 0.15), Color(0.35, 1.0, 0.45), Color(1.0, 0.25, 0.3), Color(0.95, 0.35, 0.9), Color(1.0, 0.9, 0.4)]
	var decals := {}
	for slot: String in DECAL_SLOTS:
		if rng.randf() < 0.35:
			var id: String = DECALS[1 + rng.randi() % (DECALS.size() - 1)]
			decals[slot] = id + (":%02d" % rng.randi_range(1, 99) if id == "number" else "")
	return {"primary": "#" + p.to_html(false), "secondary": "#" + s.to_html(false),
		"glow": "#" + (glows[rng.randi() % glows.size()] as Color).to_html(false),
		"markings": "#" + (Color(0.92, 0.9, 0.84) if p.get_luminance() < 0.45 else Color(0.08, 0.08, 0.09)).to_html(false),
		"decals": decals}


## The color grid paint is picked from: military, civilian and bright tones.
static func palette_grid() -> Array[Color]:
	var out: Array[Color] = []
	for h: String in [
		"f2f0ea", "c9c7c0", "8d8f93", "55585e", "2c2f35", "131417", "e8dcc0", "c2a878",
		"8a7350", "5b4a35", "6b7a4a", "45553a", "2e3a2a", "a3b18a", "b5523b", "8c2a22",
		"5a1714", "d9862b", "e6b422", "f0d75a", "2f6c8f", "1f4466", "142a44", "6fa4c8",
		"3d8f86", "1d5c57", "7e4fa0", "4a2d63", "c24f86", "e07aa8", "9ab0b8", "d4e2e6"]:
		out.append(Color(h))
	return out


# --- roles ---------------------------------------------------------------------------------

## [{mi, surface, mat, role}], computed once per model.
static func _slots(model: MechModel) -> Array:
	if model.has_meta("paint_slots"):
		return model.get_meta("paint_slots")
	var slots: Array = []
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		if mi.material_override is ShaderMaterial:
			_add_slot(slots, mi, -1, mi.material_override)
		else:
			for i in range(mi.mesh.get_surface_count()):
				var m := mi.get_surface_override_material(i)
				if m == null:
					m = mi.mesh.surface_get_material(i)
				if m is ShaderMaterial:
					_add_slot(slots, mi, i, m)
	# Area-weighted color groups for parts without a named role.
	var groups: Array = []  # [{color, area}]
	for s: Dictionary in slots:
		if s["role"] != "":
			continue
		var c: Color = s["mat"].get_shader_parameter("base_color")
		if _is_bare(s["mat"], c):
			s["role"] = "keep"
			continue
		var found := false
		for g: Dictionary in groups:
			if _dist(g["color"], c) < 0.16:
				g["area"] = float(g["area"]) + float(s["area"])
				s["group"] = g
				found = true
				break
		if not found:
			var g := {"color": c, "area": float(s["area"])}
			groups.append(g)
			s["group"] = g
	groups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["area"]) > float(b["area"]))
	var refs := {}
	for s: Dictionary in slots:
		if s.has("group"):
			var i := groups.find(s["group"])
			s["role"] = "primary" if i == 0 else ("secondary" if i == 1 else "keep")
			s.erase("group")
		if s["role"] in ["primary", "secondary"] and not refs.has(s["role"]):
			refs[s["role"]] = s["mat"].get_shader_parameter("base_color")
		if s["role"] == "glow" and not refs.has("glow"):
			var e: Color = s["mat"].get_shader_parameter("emission_color")
			var mx := maxf(maxf(e.r, e.g), maxf(e.b, 0.001))
			refs["glow"] = Color(e.r / mx, e.g / mx, e.b / mx)
	if groups.size() > 0 and not refs.has("primary"):
		refs["primary"] = groups[0]["color"]
	model.set_meta("paint_slots", slots)
	model.set_meta("paint_refs", refs)
	return slots


static func _add_slot(slots: Array, mi: MeshInstance3D, surface: int, mat: ShaderMaterial) -> void:
	if mat.shader != MeshKit.MECH_SHADER:
		return
	var role := ""
	if mat.has_meta("paint_role"):
		role = String(mat.get_meta("paint_role"))
	var e: Color = mat.get_shader_parameter("emission_color")
	if role == "" and maxf(maxf(e.r, e.g), e.b) > 0.05:
		role = "glow"
	if role not in ["", "primary", "secondary", "glow"]:
		role = "keep"
	var size := mi.get_aabb().size
	if surface >= 0 and mi.mesh.get_surface_count() > 1:
		# Merged meshes: each surface (material) has its own extent.
		var verts: PackedVector3Array = mi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		if not verts.is_empty():
			var box := AABB(verts[0], Vector3.ZERO)
			for v in verts:
				box = box.expand(v)
			size = box.size
	if mi.is_inside_tree():
		size *= mi.global_transform.basis.get_scale()
	var area := size.x * size.y + size.y * size.z + size.x * size.z
	slots.append({"mi": mi, "surface": surface, "mat": mat, "role": role, "area": area})


## Dark trim, bare metal and near-black parts keep their color.
static func _is_bare(mat: ShaderMaterial, c: Color) -> bool:
	var metal := float(mat.get_shader_parameter("metallic_value"))
	return c.get_luminance() < 0.07 or (metal >= 0.75 and c.s < 0.15)


static func _dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


## The new color with the part's original shade relative to its group.
static func _tint(orig: Color, ref: Color, new_color: Color) -> Color:
	var ratio := clampf((orig.get_luminance() + 0.02) / (ref.get_luminance() + 0.02), 0.45, 1.6)
	var c := new_color * ratio
	return Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0))


# --- decals --------------------------------------------------------------------------------

static func _apply_decals(model: MechModel, paint: Dictionary) -> void:
	for d: Node in model.find_children("Decal_*", "Decal", true, false):
		d.free()
	var decals: Dictionary = paint.get("decals", {})
	if decals.is_empty() or not model.is_inside_tree():
		return
	var col := Color(String(paint.get("markings", "#e8e4da")))
	for slot: String in decals:
		var id := String(decals[slot])
		if id == "":
			continue
		var place := _decal_place(model, slot)
		if place.is_empty():
			continue
		var d := Decal.new()
		d.name = "Decal_" + slot
		d.texture_albedo = decal_texture(id)
		d.modulate = col
		d.albedo_mix = 1.0
		d.upper_fade = 0.0
		d.lower_fade = 0.0
		var w: float = place["size"]
		d.size = Vector3(w, w * 0.9, w)
		var host: Node3D = place["host"]
		host.add_child(d)
		d.global_transform = place["xf"]


## Where a slot's decal goes: {host, xf (global), size}, from the rest pose.
static func _decal_place(model: MechModel, slot: String) -> Dictionary:
	var host: Node3D
	var out_dir := Vector3.FORWARD
	match slot:
		"chest":
			host = model.torso
		"shoulder_l", "shoulder_r":
			var arm: Dictionary = model.arms.get("l" if slot == "shoulder_l" else "r", {})
			host = arm.get("shoulder")
			out_dir = Vector3.LEFT if slot == "shoulder_l" else Vector3.RIGHT
		"leg_l", "leg_r":
			var side := "l" if slot == "leg_l" else "r"
			for leg: Dictionary in model.legs:
				var k: Node3D = leg.get("knee")
				if k and String(k.name).to_lower().ends_with("_" + side):
					host = k
			if host == null and model.legs.size() >= 2:
				host = (model.legs[1 if slot == "leg_l" else 0] as Dictionary).get("knee")
	if host == null:
		return {}
	var skip: Array = [model.head]
	for a: Dictionary in model.arms.values():
		skip.append(a.get("shoulder"))
	skip.erase(host)
	var box := _aabb_under(host, skip)
	if box.size == Vector3.ZERO:
		return {}
	var mb := model.global_transform.basis.orthonormalized()
	var dir := (mb * out_dir).normalized()
	var center := box.get_center()
	var extent := absf(dir.dot(box.size)) * 0.5
	var w := clampf(minf(box.size.y, maxf(box.size.x, box.size.z)) * 0.55, 0.12, 0.8)
	# A decal projects along its -Y: point it at the surface from just outside.
	var pos := center + dir * extent
	var x := mb.y.cross(dir).normalized()
	var basis := Basis(x, dir, x.cross(dir)).orthonormalized()
	return {"host": host, "xf": Transform3D(basis, pos), "size": w}


## Global AABB of the meshes under `node`, leaving out the subtrees in `skip`.
static func _aabb_under(node: Node3D, skip: Array) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var skipped := false
		for k: Variant in skip:
			if k is Node and (k as Node).is_ancestor_of(mi):
				skipped = true
		if skipped:
			continue
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


## White-on-clear marking textures, drawn here (our own art).
static func decal_texture(id: String) -> Texture2D:
	if _decal_tex.has(id):
		return _decal_tex[id]
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var kind := id.get_slice(":", 0)
	match kind:
		"chevron":
			for y in range(n):
				for x in range(n):
					var u := absf(x - n * 0.5) / (n * 0.5)
					var v := float(y) / n
					var k := v - 0.25 - u * 0.45
					if (k > 0.0 and k < 0.2) or (k > 0.3 and k < 0.5):
						img.set_pixel(x, y, Color.WHITE)
		"stripes":
			for y in range(n):
				for x in range(n):
					if int((x + y) / 18.0) % 2 == 0 and absf(y - n * 0.5) < n * 0.42:
						img.set_pixel(x, y, Color.WHITE)
		"roundel":
			for y in range(n):
				for x in range(n):
					var r := Vector2(x - n * 0.5, y - n * 0.5).length() / (n * 0.5)
					if r < 0.95 and (r > 0.72 or r < 0.38):
						img.set_pixel(x, y, Color.WHITE)
		"star":
			for y in range(n):
				for x in range(n):
					var p := Vector2(x - n * 0.5, y - n * 0.5) / (n * 0.46)
					var a := atan2(p.x, -p.y)
					var spoke := 0.45 + 0.55 * pow(absf(cos(a * 2.5)), 6.0)
					if p.length() < spoke:
						img.set_pixel(x, y, Color.WHITE)
		"hazard":
			for y in range(int(n * 0.3), int(n * 0.7)):
				for x in range(n):
					if int((x + y) / 14.0) % 2 == 0:
						img.set_pixel(x, y, Color.WHITE)
		"bars":
			for i in range(3):
				img.fill_rect(Rect2i(int(n * 0.15), int(n * (0.2 + i * 0.22)), int(n * 0.7), int(n * 0.13)), Color.WHITE)
		"diamond":
			for y in range(n):
				for x in range(n):
					var d := absf(x - n * 0.5) + absf(y - n * 0.5)
					if d < n * 0.45 and d > n * 0.28 or d < n * 0.16:
						img.set_pixel(x, y, Color.WHITE)
		"number":
			_draw_number(img, id.get_slice(":", 1) if ":" in id else "01")
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_decal_tex[id] = t
	return t


## Seven-segment digits, so numbers need no font.
static func _draw_number(img: Image, text: String) -> void:
	const SEG := {"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd",
		"6": "afgedc", "7": "abc", "8": "abcdefg", "9": "abcdfg"}
	var n := img.get_width()
	var digits := text.substr(0, 2)
	var w := n * 0.36
	var h := n * 0.7
	var t := int(n * 0.07)
	for i in range(digits.length()):
		var x0 := int(n * 0.1 + i * (w + n * 0.08))
		var y0 := int(n * 0.15)
		var segs: String = SEG.get(digits[i], "")
		var r := {
			"a": Rect2i(x0, y0, int(w), t), "g": Rect2i(x0, y0 + int(h * 0.5) - t / 2, int(w), t),
			"d": Rect2i(x0, y0 + int(h) - t, int(w), t),
			"f": Rect2i(x0, y0, t, int(h * 0.5)), "b": Rect2i(x0 + int(w) - t, y0, t, int(h * 0.5)),
			"e": Rect2i(x0, y0 + int(h * 0.5), t, int(h * 0.5)), "c": Rect2i(x0 + int(w) - t, y0 + int(h * 0.5), t, int(h * 0.5)),
		}
		for s in segs:
			img.fill_rect(r[s], Color.WHITE)
