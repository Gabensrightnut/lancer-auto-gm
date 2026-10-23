class_name DeployableBuilder
extends RefCounted
## Models for deployables and drones (looks from data/game/visible_parts.json), built in code
## at world scale (a Size 1 mech stands ~0.95 tall). The same shape is used three ways: the
## unit on the board (`build`, a MechModel so MechView can carry it), the part docked on its
## owner's body (`shape`), and the piece flying out or back during deploy/recall events.

const BASE := Color(0.36, 0.38, 0.41)
const DARK := Color(0.12, 0.13, 0.15)


## A deployable unit on the board. `unit` is its view dict (name, size, counters.deploy_type).
static func build(unit: Dictionary, palette: Dictionary = {}) -> MechModel:
	var dtype := String((unit.get("counters", {}) as Dictionary).get("deploy_type", ""))
	var s := VisibleParts.spec(String(unit.get("name", "")), dtype)
	var m := MechModel.new()
	m.name = "Deployable_" + String(unit.get("id", ""))
	m.size = maxf(0.5, float(unit.get("size", 0.5)))
	var flying := String(s["launch"]) == "fly"
	m.gait = "hover" if flying else "tracked"
	var body := Node3D.new()
	body.name = "Body"
	m.add_child(body)
	m.pelvis = body
	m.torso = body
	var top := shape(body, s, palette, m.size, m)
	if flying:
		body.position.y = 0.32 * clampf(m.size, 0.5, 1.0)  # hovers
	body.set_meta("rest_y", body.position.y)
	m.height = top + body.position.y
	var eye := Marker3D.new()
	eye.position = Vector3(0, top * 0.6, -0.05)
	body.add_child(eye)
	m.eye = eye
	m.collect_meshes()
	return m


## Builds the look under `root` (origin at its base) and returns its height.
static func shape(root: Node3D, s: Dictionary, palette: Dictionary = {}, size: float = 0.5, model: MechModel = null) -> float:
	var col := color_of(s, palette)
	var glow := col if String(s.get("color", "")).begins_with("#") else Color(palette.get("glow", Color(0.4, 1.0, 0.7)))
	var mat := MeshKit.mech_material(col.lerp(BASE, 0.35) if String(s.get("color", "")).begins_with("#") else col)
	var dark := MeshKit.mech_material(DARK, 0.7, 0.4, Color.BLACK, false)
	var lit := MeshKit.fx_material(glow, 2.5)
	var v := String(s.get("variant", ""))
	var k := clampf(size, 0.5, 1.0)  # drones and small pieces
	match String(s.get("look", "block")):
		"drone", "turret_drone", "projector":
			var r := 0.13 * k
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(r * 1.6, r * 0.8, r * 1.6), r * 0.2), mat, Vector3(0, r * 0.4, 0))
			MeshKit.part(root, MeshKit.sphere(r * 0.22, 8), lit, Vector3(0, r * 0.45, -r * 0.8))
			for i in range(4):
				var a := PI * 0.25 + i * PI * 0.5
				var p := Vector3(cos(a), 0, sin(a)) * r * 1.25 + Vector3(0, r * 0.55, 0)
				MeshKit.part(root, MeshKit.cylinder(r * 0.06, r * 0.5), dark, (p + Vector3(0, r * 0.4, 0)) * 0.5, Vector3(0, -rad_to_deg(a), 90))
				var ring := MeshKit.part(root, MeshKit.cylinder(r * 0.42, r * 0.04, 14), MeshKit.fx_material(glow, 0.8), p)
				if model:
					model.spinners.append({"node": ring, "axis": Vector3.UP, "speed": 18.0})
			match String(s["look"]):
				"turret_drone":
					MeshKit.part(root, MeshKit.cylinder(r * 0.12, r * 1.4), dark, Vector3(0, r * 0.2, -r * 1.1), Vector3(90, 0, 0))
				"projector":
					MeshKit.part(root, MeshKit.cylinder(r * 0.5, r * 0.08, 6), lit, Vector3(0, r * 1.0, 0))
			match v:
				"crate":
					MeshKit.part(root, MeshKit.chamfer_box(Vector3(r * 1.0, r * 0.7, r * 1.0), r * 0.08), dark, Vector3(0, -r * 0.3, 0))
				"blade":
					MeshKit.part(root, MeshKit.chamfer_box(Vector3(r * 0.08, r * 0.3, r * 1.8), r * 0.03, 0.4), lit, Vector3(0, r * 0.1, -r * 0.6))
				"coil":
					MeshKit.part(root, MeshKit.cylinder(r * 0.3, r * 0.9, 8), lit, Vector3(0, r * 1.1, 0))
				"swarm", "nexus":
					for i in range(5):
						MeshKit.part(root, MeshKit.sphere(r * 0.12, 6), lit, Vector3((MeshKit.hash01(v, i) - 0.5) * r * 3.0, r * (0.9 + MeshKit.hash01(v, i + 9)), (MeshKit.hash01(v, i + 4) - 0.5) * r * 3.0))
			return r * 1.2
		"orochi":
			# Angular wedge drones that lock together into the Hydra's body.
			var r := 0.17 * k
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(r * 1.3, r * 0.9, r * 2.0), r * 0.15, 0.55), mat, Vector3(0, r * 0.45, 0))
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(r * 0.9, r * 0.12, r * 0.5), r * 0.05), lit, Vector3(0, r * 0.75, -r * 0.6))
			for sx in [-1.0, 1.0]:
				MeshKit.part(root, MeshKit.chamfer_box(Vector3(r * 0.12, r * 0.6, r * 1.2), r * 0.04, 0.5), dark, Vector3(sx * r * 0.75, r * 0.4, r * 0.2), Vector3(0, 0, sx * 18.0))
			match v:
				"guardian":
					MeshKit.part(root, MeshKit.cylinder(r * 0.55, r * 0.06, 6), lit, Vector3(0, r * 0.45, -r * 1.05), Vector3(90, 0, 0))
				"snare":
					for i in range(3):
						MeshKit.part(root, MeshKit.cylinder(r * 0.04, r * 0.7), dark, Vector3((i - 1) * r * 0.35, r * 0.1, -r * 1.0), Vector3(60, 0, (i - 1) * 25.0))
				"shredder":
					for sx in [-1.0, 1.0]:
						MeshKit.part(root, MeshKit.chamfer_box(Vector3(r * 0.06, r * 0.2, r * 0.9), r * 0.02, 0.3), lit, Vector3(sx * r * 0.45, r * 0.2, -r * 1.1))
				"hunter":
					MeshKit.part(root, MeshKit.cylinder(r * 0.09, r * 1.6), dark, Vector3(0, r * 0.5, -r * 1.4), Vector3(90, 0, 0))
			return r * 0.9
		"mine":
			var r := 0.16
			MeshKit.part(root, MeshKit.cylinder(r, r * 0.25, 10, r * 0.8), dark, Vector3(0, r * 0.12, 0))
			MeshKit.part(root, MeshKit.sphere(r * 0.18, 8), lit, Vector3(0, r * 0.28, 0))
			if v == "charge":
				MeshKit.part(root, MeshKit.chamfer_box(Vector3(r * 1.2, r * 0.4, r * 0.7), r * 0.05), mat, Vector3(0, r * 0.35, 0))
			elif v == "spring":
				MeshKit.part(root, MeshKit.cylinder(r * 0.35, r * 0.5, 8), mat, Vector3(0, r * 0.45, 0))
			return r * 0.5
		"rocket":
			MeshKit.part(root, MeshKit.cylinder(0.05, 0.42, 8), mat, Vector3(0, 0.25, 0))
			MeshKit.part(root, MeshKit.cylinder(0.0, 0.1, 8, 0.05), dark, Vector3(0, 0.51, 0))
			for i in range(3):
				MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.02, 0.1, 0.1), 0.005), dark, Vector3(0, 0.06, 0).rotated(Vector3.UP, i * TAU / 3.0) + Vector3(cos(i * TAU / 3.0), 0, sin(i * TAU / 3.0)) * 0.05, Vector3(0, -rad_to_deg(i * TAU / 3.0), 0))
			return 0.56
		"bomb":
			MeshKit.part(root, MeshKit.cylinder(0.07, 0.18, 10), dark, Vector3(0, 0.09, 0))
			MeshKit.part(root, MeshKit.sphere(0.025, 6), lit, Vector3(0, 0.2, 0))
			return 0.22
		"cover", "block":
			var w := 0.85 * maxf(1.0, size)
			var h := 0.55 if v != "heavy" else 0.75
			for i in range(3):
				MeshKit.part(root, MeshKit.chamfer_box(Vector3(w / 3.0 - 0.02, h, 0.14), 0.02, 0.92), mat, Vector3((i - 1) * w / 3.0, h * 0.5, 0), Vector3(-6, 0, 0))
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(w, 0.05, 0.3), 0.01), dark, Vector3(0, 0.025, 0.05))
			return h
		"bunker":
			var w := 0.9 * maxf(1.0, size * 0.5)
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(w, 0.8, w), 0.06, 0.85), mat, Vector3(0, 0.4, 0))
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(w * 0.7, 0.06, 0.02), 0.01), lit, Vector3(0, 0.55, -w * 0.43))
			return 0.8
		"shield_generator":
			MeshKit.part(root, MeshKit.cylinder(0.12, 0.5, 8, 0.07), mat, Vector3(0, 0.25, 0))
			MeshKit.part(root, MeshKit.sphere(0.08, 10), lit, Vector3(0, 0.55, 0))
			var dome := MeshKit.part(root, MeshKit.sphere(0.6, 16), MeshKit.overlay_material(Color(glow, 0.12)), Vector3(0, 0.1, 0))
			dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			return 0.65
		"snare":
			for sx in [-1.0, 1.0]:
				MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.36, 0.05, 0.12), 0.01), dark, Vector3(0, 0.06, sx * 0.08), Vector3(sx * 35.0, 0, 0))
			MeshKit.part(root, MeshKit.cylinder(0.06, 0.04, 8), mat, Vector3(0, 0.02, 0))
			return 0.12
		"caltrops":
			var span := 0.45 * maxf(1.0, size * 0.6)
			for i in range(14):
				var p := Vector3((MeshKit.hash01("cal", i) - 0.5) * 2.0 * span, 0.03, (MeshKit.hash01("cal", i + 30) - 0.5) * 2.0 * span)
				MeshKit.part(root, MeshKit.cylinder(0.0, 0.07, 4, 0.02), dark, p, Vector3(MeshKit.hash01("cal", i + 60) * 40.0, i * 37.0, 0))
			return 0.07
		"plate":
			var w := 0.75 * maxf(1.0, size * 0.7)
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(w, 0.06, w), 0.02), mat, Vector3(0, 0.03, 0))
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(w * 0.6, 0.02, w * 0.6), 0.005), lit, Vector3(0, 0.07, 0))
			return 0.08
		"pylon":
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.18, 0.7, 0.18), 0.03, 0.45), mat if v != "emblem" else dark, Vector3(0, 0.35, 0))
			MeshKit.part(root, MeshKit.sphere(0.06, 8), lit, Vector3(0, 0.78, 0))
			return 0.82
		"decoy":
			# A hologram of a mech (False Idol): translucent, glowing.
			var holo := MeshKit.overlay_material(Color(glow, 0.35))
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.3, 0.35, 0.2), 0.04), holo, Vector3(0, 0.6, 0))
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.14, 0.12, 0.14), 0.03), holo, Vector3(0, 0.86, 0))
			for sx in [-1.0, 1.0]:
				MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.1, 0.42, 0.1), 0.02), holo, Vector3(sx * 0.09, 0.21, 0))
			return 0.92
		"barrier":
			var w := 0.9 * maxf(1.0, size)
			var wall := MeshKit.part(root, MeshKit.chamfer_box(Vector3(w, 0.8, 0.05), 0.01), MeshKit.overlay_material(Color(glow, 0.3)), Vector3(0, 0.4, 0))
			wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			MeshKit.part(root, MeshKit.chamfer_box(Vector3(w, 0.04, 0.1), 0.01), dark, Vector3(0, 0.02, 0))
			return 0.8
	MeshKit.part(root, MeshKit.chamfer_box(Vector3(0.3, 0.3, 0.3), 0.03), mat, Vector3(0, 0.15, 0))
	return 0.3


## The spec's color: a palette key (primary/secondary/trim/glow), a hex, or the frame primary.
static func color_of(s: Dictionary, palette: Dictionary) -> Color:
	var c := String(s.get("color", ""))
	if c.begins_with("#"):
		return Color.html(c)
	if c != "" and palette.has(c):
		return Color(palette[c])
	return Color(palette.get("primary", BASE))
