class_name FrameSculpts
extends RefCounted
## Individually modeled frames, shaped to match their official art (viewed for reference
## only, never stored). Built from smooth lofts and superellipsoids on the same rig as the
## generic MechBuilder (pelvis, torso, head, arms, legs, mount slots), so walking, aiming
## and weapon mounting work unchanged. Frames without a sculpt use the generic generator.
## Interim pipeline until Blender is available: shapes will move to Blender scripts -> glTF.

const BUILDERS := {
	"mf_standard_pattern_i_everest": "_everest",
	"mf_drake": "_drake",
	"mf_mourning_cloak": "_mourning_cloak",
}
const CLOTH_SHADER := preload("res://src/render/shaders/cloth.gdshader")

var m: MechModel
var body: Node3D


static func has(frame_id: String) -> bool:
	return BUILDERS.has(frame_id)


static func sculpt(frame_id: String, model: MechModel, body_node: Node3D) -> void:
	var s := FrameSculpts.new()
	s.m = model
	s.body = body_node
	s.call(BUILDERS[frame_id])


# --- helpers -----------------------------------------------------------------------------

func _p(parent: Node3D, name: String, pos: Vector3, rot := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = pos
	n.rotation_degrees = rot
	parent.add_child(n)
	return n


func _add(parent: Node3D, mesh: Mesh, mat: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	return MeshKit.part(parent, mesh, mat, pos, rot, scl)


## A limb segment hanging down from its pivot: radius r0 at the top, r1 at the bottom,
## `bulge` swells the middle (muscle-like armor), d_scale flattens front-to-back.
func _limb(length: float, r0: float, r1: float, bulge: float = 0.0, d_scale: float = 1.0, n: float = 2.2) -> ArrayMesh:
	var mid := (r0 + r1) * 0.5 * (1.0 + bulge)
	return SmoothKit.loft([
		{"y": -length - r1 * 0.35, "w": r1 * 1.1, "d": r1 * 1.1 * d_scale, "n": n},
		{"y": -length, "w": r1 * 2.0, "d": r1 * 2.0 * d_scale, "n": n},
		{"y": -length * 0.5, "w": mid * 2.0, "d": mid * 2.0 * d_scale, "n": n},
		{"y": 0.0, "w": r0 * 2.0, "d": r0 * 2.0 * d_scale, "n": n},
		{"y": r0 * 0.35, "w": r0 * 1.1, "d": r0 * 1.1 * d_scale, "n": n},
	], 18)


## A curved plate (shields, cowls): width x height, bent around the vertical axis.
static func curved_plate(width: float, height: float, thickness: float, bend: float, taper: float = 1.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nu := 12
	var nv := 6
	for side in [0, 1]:
		var t := -thickness * 0.5 if side == 0 else thickness * 0.5
		for i in range(nv + 1):
			for j in range(nu + 1):
				var u := float(j) / nu - 0.5
				var v := float(i) / nv
				var w := width * lerpf(1.0, taper, v)
				st.set_uv(Vector2(u, v))
				st.add_vertex(Vector3(u * w, v * height, bend * (u * u * 4.0) + t))
	var row := nu + 1
	var off := (nv + 1) * row
	for i in range(nv):
		for j in range(nu):
			var a := i * row + j
			# back (side 0) faces +z, front (side 1) faces -z... both wound outward.
			for q: Array in [[a, a + 1, a + row, a + 1, a + row + 1, a + row], [off + a, off + a + row, off + a + 1, off + a + 1, off + a + row, off + a + row + 1]]:
				for k: int in q:
					st.add_index(k)
	st.generate_normals()
	var mesh := st.commit()
	# Rim around the edge so the plate reads as thick.
	var rim := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edge: Array[Vector2i] = []
	for j in range(nu + 1):
		edge.append(Vector2i(j, 0))
	for i in range(1, nv + 1):
		edge.append(Vector2i(nu, i))
	for j in range(nu - 1, -1, -1):
		edge.append(Vector2i(j, nv))
	for i in range(nv - 1, 0, -1):
		edge.append(Vector2i(0, i))
	var pos := func(e: Vector2i, t: float) -> Vector3:
		var u := float(e.x) / nu - 0.5
		var v := float(e.y) / nv
		var w := width * lerpf(1.0, taper, v)
		return Vector3(u * w, v * height, bend * (u * u * 4.0) + t)
	var center := Vector3(0, height * 0.5, 0)
	for k in range(edge.size()):
		var e0 := edge[k]
		var e1 := edge[(k + 1) % edge.size()]
		var a0: Vector3 = pos.call(e0, -thickness * 0.5)
		var a1: Vector3 = pos.call(e1, -thickness * 0.5)
		var b0: Vector3 = pos.call(e0, thickness * 0.5)
		var b1: Vector3 = pos.call(e1, thickness * 0.5)
		var out := (a0 + a1) * 0.5 - center
		out.z = 0.0
		MeshKit.add_quad(rim, a0, a1, b1, b0, out)
	rim.commit(mesh)
	return mesh


## Ribbon along a list of points (cloth strips). UV.y = 0 at the root, 1 at the tip.
static func ribbon(points: Array, widths: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := points.size()
	for i in range(n):
		var p: Vector3 = points[i]
		var d: Vector3 = (points[mini(i + 1, n - 1)] - points[maxi(i - 1, 0)]).normalized()
		var side := d.cross(Vector3.FORWARD).normalized()
		if side.length() < 0.1:
			side = Vector3.RIGHT
		var w: float = widths[i]
		for k in [-1.0, 1.0]:
			st.set_uv(Vector2(0.5 + k * 0.5, float(i) / (n - 1)))
			st.set_normal(d.cross(side).normalized())
			st.add_vertex(p + side * w * 0.5 * k)
	for i in range(n - 1):
		var a := i * 2
		for k: int in [a, a + 1, a + 2, a + 1, a + 3, a + 2]:
			st.add_index(k)
	return st.commit()


## Rig: an arm hanging from `pos` on the torso. Meshes are added by the frame.
func _rig_arm(side: String, pos: Vector3, upper: float, fore: float, hand_off: float, fore_r: float) -> Dictionary:
	var s := 1.0 if side == "r" else -1.0
	var shoulder := _p(m.torso, "Shoulder_" + side, pos)
	var elbow := _p(shoulder, "Elbow", Vector3(0, -upper, 0))
	var hand := _p(elbow, "Hand", Vector3(0, -fore - hand_off, 0))
	m.slots["hand_" + side] = _p(hand, "Slot_hand_" + side, Vector3(0, -hand_off * 0.3, 0), Vector3(-90, 0, 0))
	m.slots["forearm_" + side] = _p(elbow, "Slot_forearm_" + side, Vector3(s * fore_r * 1.1, -fore * 0.6, 0), Vector3(-90, 0, 0))
	var rest_sh := Vector3(4, 0, s * 6)
	var rest_el := Vector3(18, 0, 0)
	shoulder.rotation_degrees = rest_sh
	elbow.rotation_degrees = rest_el
	var arm := {"shoulder": shoulder, "elbow": elbow, "hand": hand, "rest_shoulder": rest_sh, "rest_elbow": rest_el}
	m.arms[side] = arm
	return arm


## Rig: a leg from the pelvis. Plantigrade unless `digi` (thigh fwd, shin back, foot level).
func _rig_leg(side: String, hip_pos: Vector3, thigh: float, shin: float, digi: bool = false, meta: float = 0.0) -> Dictionary:
	var hip := _p(m.pelvis, "Hip_" + side, hip_pos)
	var knee := _p(hip, "Knee", Vector3(0, -thigh, 0))
	var ankle := _p(knee, "Ankle", Vector3(0, -shin, 0))
	var base := Vector3.ZERO
	var foot := ankle
	if digi:
		hip.rotation_degrees.x = 32.0
		knee.rotation_degrees.x = -70.0
		ankle.rotation_degrees.x = 38.0
		foot = _p(ankle, "Foot", Vector3(0, -meta, 0))
		base = Vector3(32, -70, 38)
	var leg := {"hip": hip, "knee": knee, "ankle": ankle, "base": base, "foot": foot}
	m.legs.append(leg)
	return leg


func _eye(parent: Node3D, pos: Vector3) -> void:
	m.eye = Marker3D.new()
	m.eye.name = "Eye"
	m.eye.position = pos
	parent.add_child(m.eye)


# --- Everest (GMS) -----------------------------------------------------------------------
# Upright, balanced humanoid: broad rounded chest with a cockpit hatch, round pauldrons,
# a helmet with a single visor band and a short crest, armored gauntlets and sturdy boots.

func _everest() -> void:
	var W := MeshKit.paint(Color(0.80, 0.81, 0.82), 0.35, 0.38, 0.35)
	var B := MeshKit.paint(Color(0.18, 0.25, 0.36), 0.45, 0.4, 0.3)
	var D := MeshKit.paint(Color(0.15, 0.16, 0.17), 0.75, 0.5, 0.0)
	var Y := MeshKit.paint(Color(0.92, 0.66, 0.16), 0.3, 0.45, 0.0)
	var G := MeshKit.paint(Color(0.05, 0.05, 0.05), 0.2, 0.2, 0.0, Color(0.35, 0.85, 1.0))
	var L := 0.46
	m.pelvis = _p(body, "Pelvis", Vector3(0, L, 0))
	m.pelvis.set_meta("rest_y", L)
	_add(m.pelvis, SmoothKit.loft([{"y": -0.06, "w": 0.2, "d": 0.16, "n": 3}, {"y": 0.0, "w": 0.26, "d": 0.19, "n": 3}, {"y": 0.05, "w": 0.22, "d": 0.17, "n": 3}]), D)
	_add(m.pelvis, SmoothKit.blob(Vector3(0.12, 0.1, 0.05), 0.5, 0.5), B, Vector3(0, -0.02, -0.1), Vector3(-10, 0, 0))
	for s: float in [-1.0, 1.0]:
		var side := "r" if s > 0 else "l"
		var leg := _rig_leg(side, Vector3(s * 0.09, -0.02, 0), 0.21, 0.19)
		_add(leg["hip"], SmoothKit.blob(Vector3(0.09, 0.09, 0.09), 1.0, 1.0), D)
		_add(leg["hip"], _limb(0.2, 0.055, 0.045, 0.15), W, Vector3(0, -0.01, 0))
		_add(leg["hip"], SmoothKit.blob(Vector3(0.09, 0.14, 0.05), 0.5, 0.6), B, Vector3(s * 0.01, -0.1, -0.045), Vector3(-4, 0, 0))
		_add(leg["knee"], SmoothKit.blob(Vector3(0.09, 0.08, 0.08), 0.6, 0.6), D)
		_add(leg["knee"], SmoothKit.blob(Vector3(0.08, 0.08, 0.05), 0.5, 0.5), Y, Vector3(0, 0.0, -0.05))
		_add(leg["knee"], _limb(0.17, 0.05, 0.062, 0.25), W, Vector3(0, -0.02, 0.005))
		_add(leg["knee"], SmoothKit.blob(Vector3(0.1, 0.13, 0.05), 0.5, 0.6), W, Vector3(0, -0.1, -0.055), Vector3(5, 0, 0))
		_add(leg["ankle"], SmoothKit.blob(Vector3(0.12, 0.06, 0.2), 0.45, 0.5, 0.0), D, Vector3(0, -0.035, -0.03))
		_add(leg["ankle"], SmoothKit.blob(Vector3(0.11, 0.05, 0.12), 0.5, 0.5, 0.0), W, Vector3(0, -0.01, -0.07))
	m.torso = _p(m.pelvis, "Torso", Vector3(0, 0.04, 0))
	_add(m.torso, SmoothKit.loft([
		{"y": 0.0, "w": 0.18, "d": 0.14, "n": 3.0},
		{"y": 0.08, "w": 0.22, "d": 0.17, "n": 3.0},
		{"y": 0.17, "w": 0.36, "d": 0.25, "n": 3.2, "z": -0.01},
		{"y": 0.27, "w": 0.4, "d": 0.27, "n": 3.4, "z": -0.015},
		{"y": 0.33, "w": 0.34, "d": 0.24, "n": 3.0},
		{"y": 0.36, "w": 0.22, "d": 0.16, "n": 3.0},
	], 28), W)
	# Cockpit hatch and chest plates.
	_add(m.torso, SmoothKit.blob(Vector3(0.22, 0.15, 0.08), 0.45, 0.5), B, Vector3(0, 0.25, -0.12), Vector3(-8, 0, 0))
	_add(m.torso, SmoothKit.blob(Vector3(0.14, 0.035, 0.02), 0.3, 0.3), Y, Vector3(0, 0.2, -0.15), Vector3(-8, 0, 0))
	_add(m.torso, SmoothKit.blob(Vector3(0.16, 0.08, 0.06), 0.5, 0.5), D, Vector3(0, 0.08, -0.08))
	# Back pack with two thrusters.
	_add(m.torso, SmoothKit.rounded_box(Vector3(0.24, 0.2, 0.1), 0.03), D, Vector3(0, 0.24, 0.14))
	for s: float in [-1.0, 1.0]:
		_add(m.torso, SmoothKit.lathe([Vector2(0.03, 0.0), Vector2(0.04, 0.03), Vector2(0.032, 0.07)], 14, false), D, Vector3(s * 0.07, 0.13, 0.18), Vector3(180, 0, 0))
	# Head: helmet with visor band, crest and antenna.
	m.head = _p(m.torso, "Head", Vector3(0, 0.37, -0.02))
	_add(m.head, SmoothKit.blob(Vector3(0.06, 0.05, 0.06), 1.0, 1.0), D, Vector3(0, 0.0, 0))
	_add(m.head, SmoothKit.blob(Vector3(0.11, 0.1, 0.12), 0.55, 0.6), W, Vector3(0, 0.05, 0))
	_add(m.head, SmoothKit.blob(Vector3(0.1, 0.025, 0.04), 0.3, 0.6), G, Vector3(0, 0.055, -0.05))
	_add(m.head, SmoothKit.blob(Vector3(0.015, 0.05, 0.1), 0.6, 0.6), B, Vector3(0, 0.1, 0.005))
	_add(m.head, MeshKit.cylinder(0.004, 0.14, 5), D, Vector3(0.045, 0.14, 0.03), Vector3(0, 0, -8))
	_eye(m.head, Vector3(0, 0.055, -0.07))
	# Arms with round pauldrons and gauntlets.
	for s: float in [-1.0, 1.0]:
		var side := "r" if s > 0 else "l"
		var arm := _rig_arm(side, Vector3(s * 0.24, 0.29, 0), 0.17, 0.16, 0.05, 0.05)
		var pad := _p(m.torso, "Pad_" + side, Vector3(s * 0.25, 0.31, 0))
		_add(pad, SmoothKit.blob(Vector3(0.15, 0.13, 0.16), 0.5, 0.55, 0.15), W, Vector3(s * 0.01, 0.0, 0), Vector3(0, 0, -s * 12))
		_add(pad, SmoothKit.blob(Vector3(0.16, 0.03, 0.15), 0.4, 0.55, 0.0), B, Vector3(s * 0.015, -0.01, 0), Vector3(0, 0, -s * 12))
		m.slots["shoulder_" + side] = _p(pad, "Slot_shoulder_" + side, Vector3(s * 0.02, 0.08, 0))
		m.slots["back_" + side] = _p(m.torso, "Slot_back_" + side, Vector3(s * 0.08, 0.36, 0.14))
		_add(arm["shoulder"], SmoothKit.blob(Vector3(0.07, 0.07, 0.07), 1.0, 1.0), D)
		_add(arm["shoulder"], _limb(0.15, 0.04, 0.036, 0.1), D, Vector3(0, -0.01, 0))
		_add(arm["shoulder"], SmoothKit.blob(Vector3(0.075, 0.11, 0.075), 0.6, 0.6), W, Vector3(0, -0.07, 0))
		_add(arm["elbow"], SmoothKit.blob(Vector3(0.065, 0.065, 0.065), 1.0, 1.0), D)
		_add(arm["elbow"], _limb(0.15, 0.045, 0.055, 0.2, 1.05), W, Vector3(0, -0.01, 0))
		_add(arm["elbow"], SmoothKit.blob(Vector3(0.03, 0.1, 0.07), 0.5, 0.5), B, Vector3(s * 0.05, -0.09, 0))
		_add(arm["hand"], SmoothKit.rounded_box(Vector3(0.06, 0.06, 0.06), 0.015), D)


# --- Drake (IPS-N) -----------------------------------------------------------------------
# Hulking siege frame: a rounded barrel torso with the small domed head sunk low between
# huge round shoulders covered in red reactive armor bricks, a segmented collar, thick limbs,
# big round knees and boots, a drum and sensor on the back, and a tall curved tower shield.

func _drake() -> void:
	var O := MeshKit.paint(Color(0.30, 0.32, 0.19), 0.3, 0.6, 0.25)
	var R := MeshKit.paint(Color(0.47, 0.17, 0.12), 0.25, 0.6, 0.0)
	var D := MeshKit.paint(Color(0.18, 0.19, 0.18), 0.7, 0.5, 0.0)
	var M := MeshKit.paint(Color(0.45, 0.5, 0.5), 0.8, 0.35, 0.0)
	var SH := MeshKit.paint(Color(0.14, 0.27, 0.3), 0.55, 0.45, 0.15)
	var V := MeshKit.paint(Color(0.12, 0.14, 0.16), 0.6, 0.15, 0.0)
	var G := MeshKit.paint(Color(0.05, 0.02, 0.02), 0.2, 0.2, 0.0, Color(1.0, 0.15, 0.1))
	var L := 0.36
	m.pelvis = _p(body, "Pelvis", Vector3(0, L, 0))
	m.pelvis.set_meta("rest_y", L)
	_add(m.pelvis, SmoothKit.blob(Vector3(0.36, 0.14, 0.3), 0.6, 0.6), D)
	_add(m.pelvis, SmoothKit.blob(Vector3(0.18, 0.12, 0.08), 0.5, 0.5), O, Vector3(0, -0.02, -0.15), Vector3(-12, 0, 0))
	for s: float in [-1.0, 1.0]:
		var side := "r" if s > 0 else "l"
		var leg := _rig_leg(side, Vector3(s * 0.13, -0.03, 0), 0.15, 0.15)
		_add(leg["hip"], _limb(0.15, 0.09, 0.08, 0.3), O)
		_add(leg["knee"], SmoothKit.blob(Vector3(0.16, 0.14, 0.15), 0.7, 0.7), O, Vector3(0, 0.0, -0.03))
		_add(leg["knee"], SmoothKit.blob(Vector3(0.1, 0.1, 0.06), 0.6, 0.6), D, Vector3(0, -0.01, -0.09))
		_add(leg["knee"], _limb(0.13, 0.08, 0.1, 0.15), O, Vector3(0, -0.02, 0.01))
		_add(leg["ankle"], SmoothKit.blob(Vector3(0.22, 0.11, 0.3), 0.55, 0.6, 0.0), O, Vector3(0, -0.06, -0.04))
		_add(leg["ankle"], SmoothKit.blob(Vector3(0.23, 0.03, 0.31), 0.3, 0.6), D, Vector3(0, -0.055, -0.04))
	m.torso = _p(m.pelvis, "Torso", Vector3(0, 0.05, 0), Vector3(-8, 0, 0))
	_add(m.torso, SmoothKit.loft([
		{"y": 0.0, "w": 0.3, "d": 0.26, "n": 2.4},
		{"y": 0.08, "w": 0.44, "d": 0.36, "n": 2.4, "z": -0.01},
		{"y": 0.19, "w": 0.56, "d": 0.44, "n": 2.6, "z": -0.02},
		{"y": 0.3, "w": 0.6, "d": 0.46, "n": 2.6, "z": -0.02},
		{"y": 0.38, "w": 0.52, "d": 0.4, "n": 2.4, "z": -0.01},
		{"y": 0.43, "w": 0.32, "d": 0.26, "n": 2.2},
	], 30), O)
	# Belly plates and chest seam.
	for i in range(3):
		_add(m.torso, SmoothKit.blob(Vector3(0.22 - i * 0.02, 0.06, 0.05), 0.5, 0.5), O, Vector3(0, 0.05 + i * 0.065, -0.2 + i * 0.012), Vector3(-10, 0, 0))
	_add(m.torso, SmoothKit.rounded_box(Vector3(0.12, 0.04, 0.02), 0.01), D, Vector3(0, 0.28, -0.235))
	# Segmented collar around the neck.
	for i in range(14):
		var a := PI + PI * i / 13.0
		_add(m.torso, SmoothKit.blob(Vector3(0.05, 0.045, 0.05), 0.8, 0.8), D, Vector3(cos(a) * 0.15, 0.38, sin(a) * 0.1 - 0.1))
	# Head: small dome sunk low and forward, dark visor, red eye.
	m.head = _p(m.torso, "Head", Vector3(0, 0.36, -0.12))
	_add(m.head, SmoothKit.blob(Vector3(0.2, 0.16, 0.2), 0.6, 0.7, 0.0), O, Vector3(0, 0.05, 0))
	_add(m.head, SmoothKit.blob(Vector3(0.17, 0.07, 0.12), 0.4, 0.6), V, Vector3(0, 0.035, -0.06))
	_add(m.head, MeshKit.sphere(0.015, 8), G, Vector3(0.03, 0.045, -0.12))
	_eye(m.head, Vector3(0, 0.05, -0.12))
	# Back: drum and sensor mast.
	_add(m.torso, SmoothKit.lathe([Vector2(0.09, 0.0), Vector2(0.1, 0.02), Vector2(0.1, 0.14), Vector2(0.09, 0.16)], 18), M, Vector3(-0.13, 0.42, 0.13), Vector3(0, 0, 90))
	_add(m.torso, SmoothKit.rounded_box(Vector3(0.05, 0.06, 0.05), 0.01), D, Vector3(0.17, 0.46, 0.1))
	_add(m.torso, MeshKit.cylinder(0.006, 0.12, 5), D, Vector3(0.17, 0.53, 0.1))
	_add(m.torso, SmoothKit.rounded_box(Vector3(0.36, 0.26, 0.14), 0.05), D, Vector3(0, 0.26, 0.2))
	# Arms: huge domed shoulders with reactive bricks, thick limbs.
	for s: float in [-1.0, 1.0]:
		var side := "r" if s > 0 else "l"
		var arm := _rig_arm(side, Vector3(s * 0.33, 0.3, 0), 0.15, 0.15, 0.06, 0.08)
		var pad := _p(m.torso, "Pad_" + side, Vector3(s * 0.33, 0.33, 0))
		_add(pad, SmoothKit.blob(Vector3(0.26, 0.22, 0.28), 0.65, 0.7, 0.3), O, Vector3(s * 0.02, 0, 0))
		# Reactive armor bricks over the front and outer side of the dome.
		for row in range(3):
			for col in range(4):
				var a := deg_to_rad(5.0 + col * 30.0 + row * 8.0)
				var el := deg_to_rad(5.0 + row * 25.0)
				var pos := Vector3(s * 0.02 + s * 0.135 * cos(el) * sin(a), 0.115 * sin(el), -0.145 * cos(el) * cos(a))
				_add(pad, SmoothKit.rounded_box(Vector3(0.06, 0.04, 0.035), 0.008), R, pos, Vector3(rad_to_deg(el), -s * rad_to_deg(a), 0))
		m.slots["shoulder_" + side] = _p(pad, "Slot_shoulder_" + side, Vector3(s * 0.02, 0.13, 0))
		m.slots["back_" + side] = _p(m.torso, "Slot_back_" + side, Vector3(s * 0.12, 0.44, 0.18))
		_add(arm["shoulder"], _limb(0.14, 0.075, 0.07, 0.2), O, Vector3(0, -0.04, 0))
		_add(arm["elbow"], SmoothKit.blob(Vector3(0.12, 0.11, 0.12), 0.8, 0.8), D)
		_add(arm["elbow"], _limb(0.14, 0.08, 0.085, 0.2), O, Vector3(0, -0.01, 0))
		for i in range(2):
			_add(arm["elbow"], SmoothKit.rounded_box(Vector3(0.06, 0.04, 0.035), 0.008), R, Vector3(s * 0.07, -0.05 - i * 0.05, -0.02), Vector3(0, 0, -s * 70))
		_add(arm["hand"], SmoothKit.rounded_box(Vector3(0.1, 0.09, 0.1), 0.025), D)
	# Tower shield on the left forearm, curved, with a view slot.
	var shield := _p(m.arms["l"]["elbow"], "Shield", Vector3(-0.08, -0.45, -0.14), Vector3(0, 55, 0))
	_add(shield, curved_plate(0.5, 0.8, 0.025, 0.05, 0.92), SH)
	_add(shield, SmoothKit.rounded_box(Vector3(0.16, 0.012, 0.03), 0.005), D, Vector3(0.0, 0.62, 0.05))


# --- Mourning Cloak (SSC) ------------------------------------------------------------------
# Hunched, insectile stalker: an egg-shaped ivory carapace with vent holes and a red spine,
# a small beaked head hanging forward, long spindly digitigrade legs and arms ending in
# red-tipped claws, and a mantle of translucent teal cloth streaming up from its back.

func _mourning_cloak() -> void:
	var I := MeshKit.paint(Color(0.86, 0.83, 0.76), 0.25, 0.35, 0.2)
	var R := MeshKit.paint(Color(0.62, 0.16, 0.13), 0.3, 0.45, 0.0)
	var D := MeshKit.paint(Color(0.22, 0.22, 0.24), 0.7, 0.45, 0.0)
	var G := MeshKit.paint(Color(0.1, 0.02, 0.02), 0.2, 0.2, 0.0, Color(1.0, 0.25, 0.2))
	var L := 0.5
	m.pelvis = _p(body, "Pelvis", Vector3(0, L, 0.06))
	m.pelvis.set_meta("rest_y", L)
	_add(m.pelvis, SmoothKit.blob(Vector3(0.15, 0.08, 0.12), 0.7, 0.7), D)
	_add(m.pelvis, SmoothKit.blob(Vector3(0.12, 0.06, 0.08), 0.6, 0.6), R, Vector3(0, 0.02, 0.04))
	for s: float in [-1.0, 1.0]:
		var side := "r" if s > 0 else "l"
		var leg := _rig_leg(side, Vector3(s * 0.08, -0.01, 0), 0.22, 0.26, true, 0.15)
		_add(leg["hip"], SmoothKit.blob(Vector3(0.06, 0.06, 0.06), 1.0, 1.0), R)
		_add(leg["hip"], _limb(0.21, 0.045, 0.03, 0.35, 0.9), I)
		_add(leg["knee"], SmoothKit.blob(Vector3(0.05, 0.05, 0.05), 1.0, 1.0), R)
		_add(leg["knee"], _limb(0.25, 0.025, 0.02, 0.1), D)
		_add(leg["knee"], SmoothKit.blob(Vector3(0.04, 0.16, 0.035), 0.5, 0.6), I, Vector3(0, -0.1, 0.02))
		_add(leg["ankle"], SmoothKit.blob(Vector3(0.04, 0.04, 0.04), 1.0, 1.0), R)
		_add(leg["ankle"], _limb(0.15, 0.02, 0.016), I)
		var foot: Node3D = leg["foot"]
		foot.rotation_degrees.x = 0.0
		for k in range(3):
			var a := (k - 1) * 22.0
			_add(foot, SmoothKit.loft([{"y": 0.0, "w": 0.004, "d": 0.004}, {"y": 0.06, "w": 0.016, "d": 0.012}, {"y": 0.075, "w": 0.008, "d": 0.008}], 8), R if k == 1 else D,
				Vector3(0, -0.005, 0), Vector3(-80, a, 0))
	m.torso = _p(m.pelvis, "Torso", Vector3(0, 0.02, 0), Vector3(-42, 0, 0))
	# Segmented waist.
	for i in range(3):
		_add(m.torso, SmoothKit.blob(Vector3(0.07 - i * 0.005, 0.045, 0.06), 0.8, 0.8), D, Vector3(0, 0.03 + i * 0.04, 0.0))
	# Egg-shaped carapace.
	_add(m.torso, SmoothKit.blob(Vector3(0.23, 0.4, 0.2), 0.95, 0.75), I, Vector3(0, 0.29, 0.04))
	_add(m.torso, SmoothKit.blob(Vector3(0.045, 0.32, 0.05), 0.8, 0.8), R, Vector3(0, 0.3, 0.13))
	_add(m.torso, SmoothKit.blob(Vector3(0.16, 0.12, 0.08), 0.6, 0.6), R, Vector3(0, 0.2, -0.1))
	for i in range(6):
		var a := deg_to_rad(-50.0 + 20.0 * i)
		_add(m.torso, SmoothKit.blob(Vector3(0.03, 0.045, 0.012), 0.8, 0.8), D, Vector3(sin(a) * 0.12, 0.33 + 0.04 * (i % 2), cos(a) * 0.11 + 0.01), Vector3(0, rad_to_deg(a), 0))
	# Small beaked head, hanging forward and down from the top of the carapace.
	m.head = _p(m.torso, "Head", Vector3(0, 0.3, -0.1), Vector3(95, 0, 0))
	_add(m.head, SmoothKit.loft([
		{"y": -0.02, "w": 0.05, "d": 0.05},
		{"y": 0.03, "w": 0.075, "d": 0.07},
		{"y": 0.09, "w": 0.06, "d": 0.055},
		{"y": 0.14, "w": 0.02, "d": 0.025},
	], 16), I)
	_add(m.head, SmoothKit.blob(Vector3(0.05, 0.012, 0.012), 0.4, 0.4), G, Vector3(0, 0.07, -0.032))
	_eye(m.head, Vector3(0, 0.07, -0.04))
	# Long spindly arms with clawed hands.
	for s: float in [-1.0, 1.0]:
		var side := "r" if s > 0 else "l"
		var arm := _rig_arm(side, Vector3(s * 0.12, 0.36, -0.04), 0.26, 0.28, 0.05, 0.03)
		_add(m.torso, SmoothKit.blob(Vector3(0.1, 0.08, 0.1), 0.7, 0.7), I, Vector3(s * 0.12, 0.38, -0.02))
		m.slots["shoulder_" + side] = _p(m.torso, "Slot_shoulder_" + side, Vector3(s * 0.12, 0.44, 0.0))
		m.slots["back_" + side] = _p(m.torso, "Slot_back_" + side, Vector3(s * 0.07, 0.42, 0.12))
		_add(arm["shoulder"], SmoothKit.blob(Vector3(0.045, 0.045, 0.045), 1.0, 1.0), R)
		_add(arm["shoulder"], _limb(0.25, 0.022, 0.018), D)
		_add(arm["shoulder"], SmoothKit.blob(Vector3(0.04, 0.13, 0.04), 0.5, 0.6), I, Vector3(s * 0.008, -0.09, 0))
		_add(arm["elbow"], SmoothKit.blob(Vector3(0.04, 0.04, 0.04), 1.0, 1.0), R)
		_add(arm["elbow"], _limb(0.27, 0.022, 0.026, 0.25), I)
		_add(arm["hand"], SmoothKit.blob(Vector3(0.04, 0.035, 0.03), 0.7, 0.7), D)
		for k in range(4):
			var fa := (k - 1.5) * 14.0
			var finger := _p(arm["hand"], "Claw", Vector3((k - 1.5) * 0.012, -0.015, 0), Vector3(0, 0, fa))
			_add(finger, _limb(0.07, 0.006, 0.004), D)
			_add(finger, SmoothKit.loft([{"y": -0.1, "w": 0.002, "d": 0.002}, {"y": -0.07, "w": 0.009, "d": 0.008}], 6, false), R)
	# Mantle: translucent teal ribbons streaming up and back from the shoulders.
	var cloth := ShaderMaterial.new()
	cloth.shader = CLOTH_SHADER
	for i in range(10):
		var t := float(i) / 9.0 - 0.5
		var pts: Array = []
		var widths: Array = []
		var start := Vector3(t * 0.2, 0.36 + 0.06 * (1.0 - absf(t) * 2.0), 0.12)
		var reach := 0.45 + 0.2 * MeshKit.hash01("mc", i)
		for k in range(12):
			var f := float(k) / 11.0
			var curl := sin(f * 5.0 + i * 1.7) * 0.08 * f
			pts.append(start + Vector3(t * f * 0.6 + curl, f * reach * 0.8, f * reach * 0.7 + f * f * 0.15))
			widths.append(lerpf(0.06, 0.2, sin(f * PI * 0.9) * 0.85 + 0.15))
		var r := _add(m.torso, ribbon(pts, widths), cloth)
		r.set_meta("no_height", true)  # the mantle doesn't count toward the frame's Size height
