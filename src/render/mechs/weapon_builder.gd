class_name WeaponBuilder
extends RefCounted
## Builds a model for one weapon from its lancer-data entry: mount size sets the scale,
## weapon type the shape, damage type the markings (energy coils, explosive bands, burners)
## and manufacturer the styling, with a per-weapon seed so two rifles never look alike.
## The model points along -Z with its grip at the origin; a "Muzzle" Marker3D marks where
## shots leave (or the blade tip for melee). Sizes are in mech-height units (mech = 1).

const SIZE_SCALE := {"Auxiliary": 0.62, "Main": 1.0, "Heavy": 1.25, "Superheavy": 1.45, "Ship-class": 2.0}

## Attack animation styles chosen from weapon data.
const STYLE_KINETIC := "kinetic"
const STYLE_ENERGY := "energy"
const STYLE_EXPLOSIVE := "explosive"
const STYLE_MISSILE := "missile"
const STYLE_MELEE := "melee"
const STYLE_FLAME := "flame"
const STYLE_SWARM := "swarm"


static func damage_types(w: Dictionary) -> Array:
	var out: Array = []
	for d: Dictionary in w.get("damage", []):
		out.append(d.get("type", ""))
	return out


static func range_types(w: Dictionary) -> Array:
	var out: Array = []
	for r: Dictionary in w.get("range", []):
		out.append(r.get("type", ""))
	return out


## Which attack animation a weapon uses.
static func attack_style(w: Dictionary) -> String:
	var type: String = w.get("type", "")
	var dmg := damage_types(w)
	var rng := range_types(w)
	if type == "Melee":
		return STYLE_MELEE
	if type == "Nexus":
		return STYLE_SWARM
	if "Burn" in dmg and "Cone" in rng:
		return STYLE_FLAME
	if type == "Launcher":
		return STYLE_MISSILE
	if "Explosive" in dmg:
		return STYLE_EXPLOSIVE
	if "Energy" in dmg:
		return STYLE_ENERGY
	return STYLE_KINETIC


## Glow color for a weapon's energy parts.
static func glow_color(w: Dictionary) -> Color:
	var mfr: String = w.get("source", "GMS") if w.get("source") != null else "GMS"
	var dmg := damage_types(w)
	if "Burn" in dmg or mfr == "HA":
		return Color(1.0, 0.45, 0.12)
	if mfr == "HORUS":
		return Color(0.35, 1.0, 0.45)
	if mfr == "SSC":
		return Color(0.95, 0.4, 0.9)
	return Color(0.35, 0.8, 1.0)


static func build(w: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = String(w.get("id", "weapon"))
	var id: String = w.get("id", "")
	var mfr: String = w.get("source", "GMS") if w.get("source") != null else "GMS"
	var k: float = SIZE_SCALE.get(w.get("mount", "Main"), 1.0)
	var pal := MechStyles.palette(mfr)
	var ctx := {
		"root": root, "id": id, "mfr": mfr, "k": k, "w": w,
		"body": MeshKit.mech_material(Color(0.2, 0.21, 0.22).lerp(pal["trim"], 0.5), 0.7, 0.4),
		"paint": MeshKit.mech_material(pal["secondary"] if mfr != "HORUS" else pal["secondary"], pal["metal"], pal["rough"]),
		"light": MeshKit.mech_material(pal["primary"], pal["metal"], pal["rough"]),
		"glow": MeshKit.mech_material(Color(0.1, 0.1, 0.1), 0.2, 0.3, glow_color(w), false),
		"hazard": MeshKit.mech_material(Color(0.9, 0.5, 0.08), 0.2, 0.6, Color.BLACK, false),
		"bevel": 0.012 if mfr == "HORUS" or mfr == "SSC" else 0.02,
		"taper": 0.8 if mfr == "SSC" else 1.0,
		"blade": MeshKit.mech_material(Color(0.24, 0.27, 0.28), 0.75, 0.4),
		"rust": MeshKit.mech_material(Color(0.32, 0.14, 0.11), 0.5, 0.6),
		"wrap": MeshKit.mech_material(Color(0.7, 0.14, 0.09), 0.1, 0.7, Color.BLACK, false),
	}
	var muzzle := Vector3(0, 0, -0.3 * k)
	var signature := {"mw_assault_cannon": _gatling, "mw_variable_sword": _katana, "mw_chain_axe": _chain_axe, "mw_war_pike": _war_pike,
		"mw_shotgun": _pump_shotgun, "mw_tactical_knife": _combat_knife}
	var type := String(w.get("type", "")) if not signature.has(id) else "signature"
	match type:
		"signature":
			muzzle = (signature[id] as Callable).call(ctx)
		"Rifle":
			muzzle = _rifle(ctx)
		"Cannon":
			muzzle = _cannon(ctx)
		"Launcher":
			muzzle = _launcher(ctx)
		"CQB":
			muzzle = _cqb(ctx)
		"Melee":
			muzzle = _melee(ctx)
		"Nexus":
			muzzle = _nexus(ctx)
		_:
			muzzle = _special(ctx)
	_manufacturer_details(ctx, muzzle)
	var m := Marker3D.new()
	m.name = "Muzzle"
	m.position = muzzle * k
	root.add_child(m)
	root.set_meta("style", attack_style(w))
	root.set_meta("glow", glow_color(w))
	return root


static func _r(ctx: Dictionary, i: int) -> float:
	return MeshKit.hash01(ctx["id"], i)


static func _box(ctx: Dictionary, size: Vector3, pos: Vector3, mat_key: String = "body", rot: Vector3 = Vector3.ZERO, taper: float = 1.0) -> MeshInstance3D:
	var k: float = ctx["k"]
	return MeshKit.part(ctx["root"], MeshKit.chamfer_box(size * k, ctx["bevel"] * k, taper), ctx[mat_key], pos * k, rot)


static func _barrel(ctx: Dictionary, radius: float, length: float, pos: Vector3, mat_key: String = "body", sides: int = 10, tip_radius: float = -1.0) -> MeshInstance3D:
	var k: float = ctx["k"]
	return MeshKit.part(ctx["root"], MeshKit.cylinder(radius * k, length * k, sides, tip_radius * k if tip_radius > 0 else -1.0), ctx[mat_key], pos * k, Vector3(-90, 0, 0))


## Energy coils along a barrel for energy weapons; a warning band for explosives.
static func _damage_marks(ctx: Dictionary, z_from: float, z_to: float, radius: float) -> void:
	var dmg := damage_types(ctx["w"])
	if "Energy" in dmg or "Burn" in dmg:
		var n := 3 + int(_r(ctx, 40) * 3)
		for i in range(n):
			var z := lerpf(z_from, z_to, (i + 0.5) / n)
			_barrel(ctx, radius * 1.35, 0.018, Vector3(0, 0, z), "glow", 10)
	elif "Explosive" in dmg:
		_barrel(ctx, radius * 1.3, 0.04, Vector3(0, 0, lerpf(z_from, z_to, 0.3)), "hazard", 10)


static func _rifle(ctx: Dictionary) -> Vector3:
	var len := 0.32 + 0.12 * _r(ctx, 1)
	var line := "Line" in range_types(ctx["w"])
	_box(ctx, Vector3(0.06, 0.08, 0.2), Vector3(0, 0.0, -0.05), "body", Vector3.ZERO, ctx["taper"])
	_box(ctx, Vector3(0.05, 0.06, 0.12), Vector3(0, -0.01, 0.1), "paint")  # stock
	if line:
		# Rail weapons: two parallel rails with a glowing gap.
		for s: float in [-1.0, 1.0]:
			_box(ctx, Vector3(0.016, 0.03, len), Vector3(s * 0.022, 0.0, -0.15 - len / 2.0), "paint")
		_box(ctx, Vector3(0.012, 0.012, len * 0.9), Vector3(0, 0, -0.15 - len / 2.0), "glow")
	else:
		_barrel(ctx, 0.016, len, Vector3(0, 0.01, -0.15 - len / 2.0))
		_box(ctx, Vector3(0.045, 0.05, len * 0.45), Vector3(0, 0.01, -0.17 - len * 0.22), "paint", Vector3.ZERO, ctx["taper"])
		_damage_marks(ctx, -0.2, -0.15 - len * 0.8, 0.016)
	if _r(ctx, 2) > 0.35:
		_box(ctx, Vector3(0.03, 0.035, 0.1), Vector3(0, 0.06, -0.05), "body")  # scope
		_barrel(ctx, 0.013, 0.02, Vector3(0, 0.06, -0.105), "glow", 8)
	if _r(ctx, 3) > 0.3:
		_box(ctx, Vector3(0.035, 0.08, 0.05), Vector3(0, -0.07, -0.04), "body", Vector3(-12, 0, 0))  # magazine
	return Vector3(0, 0.01, -0.15 - len)


static func _cannon(ctx: Dictionary) -> Vector3:
	var len := 0.3 + 0.1 * _r(ctx, 1)
	var rad := 0.032 + 0.012 * _r(ctx, 2)
	var line := "Line" in range_types(ctx["w"])
	_box(ctx, Vector3(0.11, 0.12, 0.2), Vector3(0, 0, 0.0), "paint", Vector3.ZERO, ctx["taper"])  # breech
	_box(ctx, Vector3(0.06, 0.05, 0.08), Vector3(0, -0.08, 0.04), "body")
	if line:
		# Lances and magnetic cannons: a long emitter with a lens.
		_barrel(ctx, rad * 1.1, len, Vector3(0, 0, -0.1 - len / 2.0), "body", 8, rad * 0.8)
		_barrel(ctx, rad * 0.9, 0.03, Vector3(0, 0, -0.1 - len), "glow", 8)
	else:
		_barrel(ctx, rad, len, Vector3(0, 0, -0.1 - len / 2.0), "body", 12)
		_barrel(ctx, rad * 1.45, 0.06, Vector3(0, 0, -0.08 - len), "body", 8)  # muzzle brake
		var twin := _r(ctx, 3) > 0.7
		if twin:
			_barrel(ctx, rad * 0.7, len * 0.8, Vector3(0, rad * 2.2, -0.1 - len * 0.4), "body", 10)
	_damage_marks(ctx, -0.14, -0.1 - len * 0.85, rad)
	return Vector3(0, 0, -0.12 - len)


static func _launcher(ctx: Dictionary) -> Vector3:
	# A pod of tubes; more tubes on bigger mounts.
	var k: float = ctx["k"]
	var cols := 2 + int(_r(ctx, 1) * 2.0) + (1 if k > 1.2 else 0)
	var rows := 2 + int(_r(ctx, 2) * 1.5)
	var cell := 0.045
	var depth := 0.16 + 0.06 * _r(ctx, 3)
	var size := Vector3(cols * cell + 0.03, rows * cell + 0.03, depth)
	_box(ctx, size, Vector3(0, 0, -depth / 2.0), "paint", Vector3.ZERO, ctx["taper"])
	for cx in range(cols):
		for cy in range(rows):
			var p := Vector3((cx - (cols - 1) / 2.0) * cell, (cy - (rows - 1) / 2.0) * cell, -depth - 0.002)
			_barrel(ctx, cell * 0.36, 0.01, p, "body", 8)
			_barrel(ctx, cell * 0.22, 0.012, p + Vector3(0, 0, -0.002), "hazard", 6)
	_box(ctx, Vector3(size.x * 0.9, 0.025, depth * 0.7), Vector3(0, size.y / 2.0 + 0.012, -depth / 2.0), "body")
	return Vector3(0, 0, -depth - 0.02)


static func _cqb(ctx: Dictionary) -> Vector3:
	var len := 0.14 + 0.08 * _r(ctx, 1)
	var aux: bool = ctx["w"].get("mount", "") == "Auxiliary"
	if aux:
		# Sidearm.
		_box(ctx, Vector3(0.045, 0.06, 0.13), Vector3(0, 0.0, -0.06), "body", Vector3.ZERO, ctx["taper"])
		_box(ctx, Vector3(0.035, 0.08, 0.04), Vector3(0, -0.05, 0.0), "paint", Vector3(15, 0, 0))
		_barrel(ctx, 0.016, len * 0.6, Vector3(0, 0.01, -0.13 - len * 0.3), "body")
		_damage_marks(ctx, -0.13, -0.13 - len * 0.5, 0.016)
		return Vector3(0, 0.01, -0.13 - len * 0.6)
	# Shotgun-style: wide body, short fat barrel(s).
	_box(ctx, Vector3(0.08, 0.09, 0.2), Vector3(0, 0, -0.04), "paint", Vector3.ZERO, ctx["taper"])
	var barrels := 1 + int(_r(ctx, 2) * 2.0)
	for i in range(barrels):
		var x := (i - (barrels - 1) / 2.0) * 0.045
		_barrel(ctx, 0.022, len, Vector3(x, 0.01, -0.14 - len / 2.0), "body", 10)
	_box(ctx, Vector3(0.05, 0.04, 0.1), Vector3(0, -0.06, -0.12), "body")  # pump / grip
	_damage_marks(ctx, -0.15, -0.14 - len * 0.8, 0.022)
	return Vector3(0, 0.01, -0.14 - len)


static func _melee(ctx: Dictionary) -> Vector3:
	var name := String(ctx["w"].get("name", "")).to_lower()
	var energy := "Energy" in damage_types(ctx["w"])
	var edge_key := "glow" if energy else "light"
	# Grip and guard, held along -Z (the arm swings it).
	_box(ctx, Vector3(0.03, 0.03, 0.1), Vector3(0, 0, 0.02), "body")
	if "hammer" in name or "knuckle" in name:
		_box(ctx, Vector3(0.025, 0.025, 0.28), Vector3(0, 0, -0.14), "body")
		_box(ctx, Vector3(0.12, 0.1, 0.1), Vector3(0, 0, -0.3), "paint", Vector3.ZERO, ctx["taper"])
		_box(ctx, Vector3(0.13, 0.03, 0.03), Vector3(0, 0, -0.3), "hazard" if "Explosive" in damage_types(ctx["w"]) else "body")
		return Vector3(0, 0, -0.35)
	if "axe" in name:
		_box(ctx, Vector3(0.025, 0.025, 0.32), Vector3(0, 0, -0.16), "body")
		_box(ctx, Vector3(0.02, 0.15, 0.12), Vector3(0, 0.06, -0.3), "paint", Vector3.ZERO, 0.6)
		_box(ctx, Vector3(0.012, 0.15, 0.02), Vector3(0, 0.06, -0.36), edge_key)
		return Vector3(0, 0.06, -0.36)
	if "pike" in name or "lance" in name or "spear" in name:
		_box(ctx, Vector3(0.022, 0.022, 0.62), Vector3(0, 0, -0.26), "body")
		_box(ctx, Vector3(0.05, 0.03, 0.14), Vector3(0, 0, -0.62), edge_key, Vector3.ZERO, 0.2)
		return Vector3(0, 0, -0.69)
	if "drill" in name:
		_box(ctx, Vector3(0.12, 0.12, 0.14), Vector3(0, 0, -0.05), "paint")
		_barrel(ctx, 0.07, 0.3, Vector3(0, 0, -0.27), "light", 8, 0.006)
		return Vector3(0, 0, -0.42)
	if "whip" in name:
		for i in range(8):
			_box(ctx, Vector3(0.025, 0.025, 0.05), Vector3(0, -i * i * 0.004, -0.05 - i * 0.05), "glow" if i % 2 else "body", Vector3(-i * 5, 0, 0))
		return Vector3(0, -0.25, -0.45)
	if "torch" in name:
		_box(ctx, Vector3(0.06, 0.06, 0.14), Vector3(0, 0, -0.08), "paint")
		_barrel(ctx, 0.022, 0.06, Vector3(0, 0, -0.18), "glow", 8, 0.012)
		return Vector3(0, 0, -0.22)
	# Blades: knives are short, swords long; energy blades glow.
	var len := 0.16 if ("knife" in name or ctx["w"].get("mount") == "Auxiliary") else 0.42 + 0.08 * _r(ctx, 1)
	_box(ctx, Vector3(0.09, 0.02, 0.025), Vector3(0, 0, -0.03), "paint")  # guard
	_box(ctx, Vector3(0.012, 0.055, len), Vector3(0, 0, -0.04 - len / 2.0), "light", Vector3.ZERO, 0.7)
	_box(ctx, Vector3(0.006, 0.012, len * 0.95), Vector3(0, 0.028, -0.04 - len / 2.0), edge_key)
	return Vector3(0, 0, -0.04 - len)


## Signature: IPS-N assault cannon as a six-barrel rotary gun with a hanging ammo belt.
static func _gatling(ctx: Dictionary) -> Vector3:
	var len := 0.34
	_box(ctx, Vector3(0.1, 0.11, 0.18), Vector3(0, 0, 0.0), "paint")
	_box(ctx, Vector3(0.05, 0.06, 0.1), Vector3(0, -0.07, 0.05), "body")
	for i in range(6):
		var a := TAU * i / 6.0
		_barrel(ctx, 0.011, len, Vector3(cos(a) * 0.028, sin(a) * 0.028, -0.09 - len / 2.0), "body", 8)
	for z in [-0.14, -0.3, -0.4]:
		_barrel(ctx, 0.045, 0.02, Vector3(0, 0, z), "light", 12)
	for i in range(9):
		_box(ctx, Vector3(0.03, 0.012, 0.02), Vector3(-0.04, -0.06 - i * 0.022, -0.02 + sin(i * 0.7) * 0.02), "hazard" if i % 2 else "body")
	return Vector3(0, 0, -0.09 - len)


## Signature: IPS-N chain axe as in the Blackbeard art: a long dark haft with a red-wrapped
## grip and a big hooked axe head.
static func _chain_axe(ctx: Dictionary) -> Vector3:
	_box(ctx, Vector3(0.022, 0.022, 0.42), Vector3(0, 0, -0.1), "body")
	_box(ctx, Vector3(0.03, 0.03, 0.09), Vector3(0, 0, 0.0), "wrap")
	# Axe head: a wide blade flaring to one side with a hook at the back.
	var head := Node3D.new()
	head.position = Vector3(0, 0, -0.27) * float(ctx["k"])
	(ctx["root"] as Node3D).add_child(head)
	var k: float = ctx["k"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector2(0.0, 0.07), Vector2(0.06, 0.09), Vector2(0.17, 0.16), Vector2(0.15, -0.06), Vector2(0.06, -0.04), Vector2(0.0, -0.05)]
	var th := 0.008
	var c := Vector2(0.08, 0.03)
	for i in range(pts.size()):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		for sgn: float in [-1.0, 1.0]:
			MeshKit.add_tri(st, Vector3(c.x, sgn * th, c.y) * k, Vector3(a.x, sgn * th, a.y) * k, Vector3(b.x, sgn * th, b.y) * k, Vector3(0, sgn, 0))
		MeshKit.add_quad(st, Vector3(a.x, -th, a.y) * k, Vector3(b.x, -th, b.y) * k, Vector3(b.x, th, b.y) * k, Vector3(a.x, th, a.y) * k, Vector3((a + b).x * 0.5 - c.x, 0, (a + b).y * 0.5 - c.y))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = ctx["blade"]
	head.add_child(mi)
	head.rotation_degrees = Vector3(0, 0, 90)
	_box(ctx, Vector3(0.04, 0.012, 0.05), Vector3(0.0, 0.0, -0.06), "blade", Vector3(0, 0, 0), 0.4)
	return Vector3(0.12, 0, -0.33)


## Signature: IPS-N war pike as in the Blackbeard art: a very long, slightly tapering dark
## red-brown blade-staff with a thin spike and a ragged pennant at the top, held mid-shaft.
static func _war_pike(ctx: Dictionary) -> Vector3:
	_box(ctx, Vector3(0.012, 0.045, 0.74), Vector3(0, 0, 0.43), "rust", Vector3.ZERO, 0.85)
	_box(ctx, Vector3(0.016, 0.016, 0.26), Vector3(0, 0, -0.07), "body")
	_box(ctx, Vector3(0.03, 0.03, 0.07), Vector3(0, 0, 0.02), "wrap")
	_box(ctx, Vector3(0.006, 0.028, 0.06), Vector3(0, 0, -0.22), "blade", Vector3.ZERO, 0.2)
	_box(ctx, Vector3(0.004, 0.06, 0.07), Vector3(0, 0.035, -0.16), "body", Vector3(0, 0, 0), 0.6)
	return Vector3(0, 0, -0.25)


## Signature: GMS shotgun as a long, boxy pump shotgun (Everest reference): a slab receiver,
## long rectangular barrel shroud over a tube magazine, a ribbed pump and a short stock.
static func _pump_shotgun(ctx: Dictionary) -> Vector3:
	var len := 0.42
	_box(ctx, Vector3(0.05, 0.075, 0.2), Vector3(0, 0, -0.02), "body")          # receiver
	_box(ctx, Vector3(0.035, 0.07, 0.03), Vector3(0, -0.06, 0.02), "body", Vector3(-15, 0, 0))  # grip
	_box(ctx, Vector3(0.04, 0.06, 0.12), Vector3(0, -0.005, 0.13), "body", Vector3(4, 0, 0), 0.9)  # stock
	_box(ctx, Vector3(0.042, 0.042, len), Vector3(0, 0.012, -0.12 - len / 2.0), "body")  # barrel shroud
	_box(ctx, Vector3(0.026, 0.026, len * 0.8), Vector3(0, -0.028, -0.12 - len * 0.4), "body")  # magazine tube
	for i in range(5):
		_box(ctx, Vector3(0.05, 0.04, 0.012), Vector3(0, -0.028, -0.2 - i * 0.02), "body")  # pump ribs
	for i in range(4):
		_box(ctx, Vector3(0.044, 0.008, 0.03), Vector3(0, 0.036, -0.17 - i * 0.08), "body")  # vent rib
	_box(ctx, Vector3(0.05, 0.05, 0.03), Vector3(0, 0.012, -0.12 - len), "body")  # muzzle block
	return Vector3(0, 0.012, -0.14 - len)


## Signature: GMS tactical knife as a big serrated combat knife (Everest reference).
static func _combat_knife(ctx: Dictionary) -> Vector3:
	var len := 0.26
	_box(ctx, Vector3(0.03, 0.035, 0.09), Vector3(0, 0, 0.03), "body")   # handle
	_box(ctx, Vector3(0.06, 0.014, 0.02), Vector3(0, 0, -0.02), "paint")  # guard
	_box(ctx, Vector3(0.008, 0.055, len), Vector3(0, -0.005, -0.03 - len / 2.0), "light", Vector3.ZERO, 0.75)
	# Serrated spine.
	for i in range(7):
		_box(ctx, Vector3(0.007, 0.014, 0.014), Vector3(0, 0.026, -0.05 - i * 0.022), "blade", Vector3(45, 0, 0))
	_box(ctx, Vector3(0.006, 0.03, 0.05), Vector3(0, -0.012, -0.03 - len + 0.012), "light", Vector3(-25, 0, 0), 0.3)  # point
	return Vector3(0, 0, -0.03 - len)


## Signature: SSC variable sword as a long slender katana with a wrapped hilt.
static func _katana(ctx: Dictionary) -> Vector3:
	var len := 0.62
	_box(ctx, Vector3(0.022, 0.022, 0.12), Vector3(0, 0, 0.03), "glow")
	_box(ctx, Vector3(0.05, 0.012, 0.05), Vector3(0, 0, -0.035), "paint")
	_box(ctx, Vector3(0.006, 0.028, len), Vector3(0, 0.004, -0.04 - len / 2.0), "light", Vector3(-2, 0, 0), 0.6)
	_box(ctx, Vector3(0.004, 0.006, len * 0.95), Vector3(0, 0.018, -0.04 - len / 2.0), "body", Vector3(-2, 0, 0))
	return Vector3(0, 0.02, -0.04 - len)


static func _nexus(ctx: Dictionary) -> Vector3:
	# A hive: a box with rows of glowing launch ports and an antenna.
	_box(ctx, Vector3(0.12, 0.1, 0.18), Vector3(0, 0, -0.07), "paint", Vector3.ZERO, 0.85)
	for i in range(3):
		for j in range(2):
			_barrel(ctx, 0.014, 0.01, Vector3((i - 1) * 0.035, (j - 0.5) * 0.04, -0.162), "glow", 6)
	_barrel(ctx, 0.004, 0.12, Vector3(0.04, 0.1, -0.02), "body", 4)
	return Vector3(0, 0, -0.17)


static func _special(ctx: Dictionary) -> Vector3:
	_box(ctx, Vector3(0.1, 0.1, 0.22), Vector3(0, 0, -0.08), "paint", Vector3(0, 0, 45))
	MeshKit.part(ctx["root"], MeshKit.sphere(0.05 * float(ctx["k"])), ctx["glow"], Vector3(0, 0, -0.22) * float(ctx["k"]))
	return Vector3(0, 0, -0.26)


## Manufacturer touches on any weapon type.
static func _manufacturer_details(ctx: Dictionary, muzzle: Vector3) -> void:
	var type: String = ctx["w"].get("type", "")
	if type == "Melee":
		return
	match String(ctx["mfr"]):
		"IPS-N":
			# Bolted armor collar.
			_box(ctx, Vector3(0.1, 0.03, 0.06), Vector3(0, 0.055, -0.02), "light")
		"HA":
			# Heat sink fins along the top.
			for i in range(4):
				_box(ctx, Vector3(0.07, 0.035, 0.008), Vector3(0, 0.06, -0.02 - i * 0.03), "body")
			_box(ctx, Vector3(0.04, 0.012, 0.1), Vector3(0, 0.045, -0.065), "glow")
		"HORUS":
			# Off-center prongs with a green core.
			_box(ctx, Vector3(0.012, 0.05, 0.14), Vector3(0.05, 0.03, muzzle.z * 0.6), "body", Vector3(0, 0, 25), 0.3)
			_box(ctx, Vector3(0.012, 0.012, 0.1), Vector3(-0.035, -0.02, -0.05), "glow")
		"SSC":
			_box(ctx, Vector3(0.006, 0.05, 0.12), Vector3(0, 0.05, -0.05), "light", Vector3.ZERO, 0.4)
		_:
			pass
