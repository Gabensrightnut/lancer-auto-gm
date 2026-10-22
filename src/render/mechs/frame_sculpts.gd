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
	"mf_blackbeard": "_blackbeard",
	"mf_goblin": "_goblin",
	"mf_lancaster": "_lancaster",
	"mf_nelson": "_nelson",
	"mf_raleigh": "_raleigh",
	"mf_tortuga": "_tortuga",
	"mf_vlad": "_vlad",
	"mf_black_witch": "_black_witch",
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
	# GMS Everest, the LL0 starter. Built from reusable GmsParts so basic GMS variants can
	# share it. Reference (user-provided fan illustration, described): a big rounded
	# barrel/egg chest in dark teal with a G.M.S. stencil and logo, no head (a glowing green
	# sensor cluster low on the chest), red spherical armored pods at shoulders, hips and
	# knees, dark open-truss limbs over pistons, chunky boxy truss-paneled forearms and shins,
	# big four-fingered hands with red plates, blocky segmented feet, a harness strap with
	# shells across the chest, hoses under the torso, and a heavy, slightly hunched stance.
	m.set_meta("custom_pose", true)
	var TEAL := MeshKit.paint(Color(0.12, 0.26, 0.28), 0.4, 0.5, 0.25)
	var TEAL2 := MeshKit.paint(Color(0.17, 0.33, 0.35), 0.4, 0.5, 0.15)
	var RED := MeshKit.paint(Color(0.62, 0.1, 0.08), 0.35, 0.45, 0.1)
	var FRAME := MeshKit.paint(Color(0.16, 0.17, 0.18), 0.75, 0.45, 0.0)
	var STEEL := MeshKit.paint(Color(0.38, 0.4, 0.42), 0.85, 0.3, 0.0)
	var DARK := MeshKit.paint(Color(0.07, 0.07, 0.08), 0.6, 0.5, 0.0)
	var STRAP := MeshKit.paint(Color(0.2, 0.17, 0.13), 0.1, 0.8, 0.0)
	var SHELL := MeshKit.paint(Color(0.62, 0.12, 0.08), 0.3, 0.5, 0.0)
	var BRASS := MeshKit.paint(Color(0.7, 0.55, 0.25), 0.9, 0.35, 0.0)
	var GREEN := MeshKit.paint(Color(0.05, 0.2, 0.05), 0.2, 0.2, 0.0, Color(0.35, 1.0, 0.35))
	var hip_y := 0.36
	var torso_origin := Vector3(0, hip_y + 0.04, 0)
	var B := func(v: Vector3) -> Vector3: return v - torso_origin
	# Pelvis: a dark block under the chest; hip pods carry the legs.
	m.pelvis = _p(body, "Pelvis", Vector3(0, hip_y, 0))
	m.pelvis.set_meta("rest_y", hip_y)
	_add(m.pelvis, SmoothKit.rounded_box(Vector3(0.2, 0.08, 0.15), 0.025), FRAME)
	_add(m.pelvis, SmoothKit.rounded_box(Vector3(0.12, 0.06, 0.05), 0.015), TEAL, Vector3(0, -0.01, -0.07))
	for s: float in [1.0, -1.0]:
		var side := "r" if s > 0 else "l"
		var leg := _rig_leg(side, Vector3(s * 0.13, -0.01, 0), 0.15, 0.15)
		var hip: Node3D = leg["hip"]
		var knee: Node3D = leg["knee"]
		var ankle: Node3D = leg["ankle"]
		hip.rotation_degrees = Vector3(-14, 0, s * 4)
		knee.rotation_degrees = Vector3(26, 0, 0)
		ankle.rotation_degrees = Vector3(-12, 0, s * -4)
		leg["base"] = Vector3(-14, 26, -12)
		GmsParts.pod(hip, RED, DARK, Vector3(s * 0.015, 0, 0), 0.05, Vector3(s, 0, -0.4))
		var thigh := _p(hip, "Thigh", Vector3(0, -0.04, 0))
		GmsParts.truss(thigh, FRAME, STEEL, 0.1, 0.07, 0.07, 1)
		GmsParts.pod(knee, RED, DARK, Vector3.ZERO, 0.05, Vector3(0, 0, -1))
		var shin := _p(knee, "Shin", Vector3(0, -0.035, 0))
		GmsParts.armored_box(shin, TEAL2, FRAME, 0.12, 0.09, 0.1, 0.9)
		GmsParts.foot(ankle, TEAL2, DARK, 0.11)
	# Torso: the big rounded barrel chest, leaning forward a little.
	m.torso = _p(m.pelvis, "Torso", Vector3(0, 0.04, 0), Vector3(-8, 0, 0))
	_add(m.torso, MeshKit.cylinder(0.07, 0.06, 14), FRAME, Vector3(0, 0.02, 0.0))
	_add(m.torso, SmoothKit.loft([
		{"y": 0.03, "w": 0.2, "d": 0.18, "n": 2.2},
		{"y": 0.1, "w": 0.36, "d": 0.3, "n": 2.3},
		{"y": 0.22, "w": 0.46, "d": 0.38, "n": 2.4},
		{"y": 0.34, "w": 0.48, "d": 0.4, "n": 2.4},
		{"y": 0.44, "w": 0.43, "d": 0.36, "n": 2.3},
		{"y": 0.5, "w": 0.32, "d": 0.28, "n": 2.2},
		{"y": 0.53, "w": 0.16, "d": 0.14, "n": 2.0},
	], 32), TEAL)
	# Armor seams: a horizontal belt and a vertical centre seam.
	_add(m.torso, SmoothKit.loft([{"y": 0.15, "w": 0.415, "d": 0.345, "n": 2.35}, {"y": 0.17, "w": 0.43, "d": 0.355, "n": 2.35}], 32, false), DARK)
	_add(m.torso, SmoothKit.blob(Vector3(0.012, 0.36, 0.4), 0.5, 0.9), DARK, Vector3(0, 0.3, -0.005), Vector3.ZERO, Vector3(1, 1, 0.97))
	# Upper chest plate with the stencil and logo.
	_add(m.torso, SmoothKit.blob(Vector3(0.36, 0.16, 0.1), 0.5, 0.7), TEAL2, Vector3(0, 0.36, -0.15), Vector3(-22, 0, 0))
	var stencil := Label3D.new()
	stencil.text = "G.M.S."
	stencil.font_size = 64
	stencil.pixel_size = 0.0009
	stencil.modulate = Color(0.85, 0.85, 0.8, 0.9)
	stencil.outline_size = 0
	stencil.position = Vector3(-0.06, 0.39, -0.232)
	stencil.rotation_degrees = Vector3(20, 180 + 12, 0)
	stencil.double_sided = false
	m.torso.add_child(stencil)
	_add(m.torso, MeshKit.cylinder(0.022, 0.006, 16), RED, Vector3(0.11, 0.41, -0.195), Vector3(-70, 0, -12))
	_add(m.torso, MeshKit.cylinder(0.012, 0.008, 16), DARK, Vector3(0.11, 0.41, -0.197), Vector3(-70, 0, -12))
	# The "face": a recessed sensor cluster low in the chest centre.
	m.head = _p(m.torso, "Head", Vector3(0, 0.17, -0.19))
	_add(m.head, SmoothKit.blob(Vector3(0.11, 0.07, 0.04), 0.5, 0.6), DARK)
	for p: Vector3 in [Vector3(0, 0.008, -0.018), Vector3(-0.025, -0.008, -0.014), Vector3(0.025, -0.008, -0.014), Vector3(0, -0.02, -0.012)]:
		_add(m.head, MeshKit.sphere(0.011 if p.x == 0 and p.y > 0 else 0.007, 10), GREEN, p)
	_add(m.head, SmoothKit.blob(Vector3(0.13, 0.025, 0.05), 0.4, 0.6), TEAL2, Vector3(0, 0.04, 0.005))
	_eye(m.head, Vector3(0, 0.0, -0.03))
	# Back: a reactor/exhaust block with two stacks (inferred: GMS utility style).
	_add(m.torso, SmoothKit.rounded_box(Vector3(0.28, 0.26, 0.12), 0.04), FRAME, Vector3(0, 0.3, 0.2))
	for s: float in [1.0, -1.0]:
		_add(m.torso, MeshKit.cylinder(0.035, 0.12, 14), STEEL, Vector3(s * 0.08, 0.46, 0.22))
		_add(m.torso, MeshKit.cylinder(0.026, 0.13, 14), DARK, Vector3(s * 0.08, 0.465, 0.22))
		for k in range(3):
			_add(m.torso, MeshKit.chamfer_box(Vector3(0.22, 0.012, 0.02), 0.003), STEEL, Vector3(0, 0.22 + k * 0.05, 0.265))
	# Harness strap across the chest (right shoulder to left hip) with shells.
	var strap_pts := SmoothKit.bezier(Vector3(0.2, 0.47, -0.08), Vector3(0.14, 0.38, -0.25), Vector3(-0.1, 0.17, -0.24), Vector3(-0.2, 0.08, -0.1), 18)
	_add(m.torso, SmoothKit.tube(strap_pts, 0.012, 6), STRAP, Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 1))
	for i in range(3, 15, 2):
		var p: Vector3 = strap_pts[i]
		var nxt: Vector3 = strap_pts[i + 1]
		var shell := MeshKit.part(m.torso, MeshKit.cylinder(0.009, 0.035, 8), SHELL, p + Vector3(0, 0, -0.01))
		shell.basis = basis_down((nxt - p).cross(Vector3.FORWARD))
		MeshKit.part(shell, MeshKit.cylinder(0.0095, 0.008, 8), BRASS, Vector3(0, -0.016, 0))
	# Hoses from under the chest to the hips.
	for s: float in [1.0, -1.0]:
		for k in range(2):
			var a := Vector3(s * (0.06 + k * 0.04), 0.06, -0.06 + k * 0.08)
			var b: Vector3 = B.call(Vector3(s * 0.13, hip_y + 0.0, -0.03 + k * 0.05))
			_add(m.torso, SmoothKit.tube(SmoothKit.bezier(a, a + Vector3(s * 0.03, -0.06, 0), b + Vector3(0, 0.05, 0), b, 10), 0.01, 8), DARK)
	# Shoulders: red pods; arms of truss uppers and boxy forearms; big hands.
	var arm_r := _rig_arm("r", Vector3.ZERO, 0.17, 0.2, 0.0, 0.05)
	var arm_l := _rig_arm("l", Vector3.ZERO, 0.17, 0.2, 0.0, 0.05)
	# Right: shotgun resting on the shoulder. Left: hanging low with the knife.
	var sh_r := Vector3(0.265, 0.79, 0.0)
	var sh_l := Vector3(-0.265, 0.79, 0.0)
	_pose_arm(arm_r, B.call(sh_r), B.call(Vector3(0.34, 0.62, -0.1)), B.call(Vector3(0.3, 0.77, -0.22)), Vector3(-0.08, 0.6, 0.8))
	_pose_arm(arm_l, B.call(sh_l), B.call(Vector3(-0.34, 0.61, -0.03)), B.call(Vector3(-0.33, 0.41, -0.1)), Vector3(0.0, -0.25, -1))
	for pair: Array in [[arm_r, 1.0], [arm_l, -1.0]]:
		var arm: Dictionary = pair[0]
		var s: float = pair[1]
		var up: float = (arm["elbow"] as Node3D).position.length()
		var fore: float = (arm["hand"] as Node3D).position.length()
		var pad := _p(m.torso, "Pad_" + ("r" if s > 0 else "l"), (arm["shoulder"] as Node3D).position)
		GmsParts.pod(pad, RED, DARK, Vector3(s * 0.005, 0.0, 0), 0.07, Vector3(s, 0.3, -0.3))
		m.slots["shoulder_" + ("r" if s > 0 else "l")] = _p(pad, "Slot_shoulder", Vector3(s * 0.01, 0.08, 0.02))
		m.slots["back_" + ("r" if s > 0 else "l")] = _p(m.torso, "Slot_back", Vector3(s * 0.1, 0.5, 0.24))
		var upper := _p(arm["shoulder"], "Upper", Vector3(0, -0.05, 0))
		GmsParts.truss(upper, FRAME, STEEL, up - 0.08, 0.06, 0.06, 1)
		GmsParts.pod(arm["elbow"], DARK, FRAME, Vector3.ZERO, 0.04, Vector3(s, 0, 0), 2)
		var fa := _p(arm["elbow"], "Forearm", Vector3(0, -0.02, 0))
		GmsParts.armored_box(fa, TEAL2, FRAME, fore - 0.04, 0.09, 0.1, 1.05)
		_add(fa, SmoothKit.rounded_box(Vector3(0.03, (fore - 0.04) * 0.7, 0.09), 0.01), RED, Vector3(s * 0.05, -(fore - 0.04) * 0.5, 0))
		var hand := _p(arm["hand"], "Hand", Vector3.ZERO)
		GmsParts.hand(hand, FRAME, RED, 0.08, s, 0.9)


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


# --- pose helpers ------------------------------------------------------------------------

## A basis whose -Y axis points along `d` (limbs hang along -Y).
static func basis_down(d: Vector3) -> Basis:
	var y := -d.normalized()
	var hint := Vector3.BACK if absf(y.dot(Vector3.BACK)) < 0.95 else Vector3.RIGHT
	var x := y.cross(hint).normalized()
	return Basis(x, y, x.cross(y))


## A basis whose -Z axis points along `d` (weapons point along -Z).
static func basis_fwd(d: Vector3) -> Basis:
	var z := -d.normalized()
	var hint := Vector3.UP if absf(z.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := hint.cross(z).normalized()
	return Basis(x, z.cross(x), z)


## Poses an arm rigged with _rig_arm so the shoulder sits at `s`, the elbow at `e` and the
## hand at `h` (all in torso space), and the hand slot points weapons along `weapon_dir`.
func _pose_arm(arm: Dictionary, s: Vector3, e: Vector3, h: Vector3, weapon_dir: Vector3) -> void:
	var sh: Node3D = arm["shoulder"]
	var el: Node3D = arm["elbow"]
	var hand: Node3D = arm["hand"]
	var bs := basis_down(e - s)
	var be := basis_down(h - e)
	sh.position = s
	sh.basis = bs
	el.position = Vector3(0, -(e - s).length(), 0)
	el.basis = bs.inverse() * be
	hand.position = Vector3(0, -(h - e).length(), 0)
	hand.basis = Basis()
	for slot_name in ["hand_r", "hand_l"]:
		var slot: Node3D = m.slots.get(slot_name)
		if slot and slot.get_parent() == hand:
			slot.position = Vector3.ZERO
			slot.basis = be.inverse() * basis_fwd(weapon_dir)
	arm["rest_shoulder"] = sh.rotation_degrees
	arm["rest_elbow"] = el.rotation_degrees


# --- Blackbeard (IPS-N) -------------------------------------------------------------------
# From the core book art: a headless shield-shaped hull with an orange sensor wedge in a nest
# of coiled red rope; two huge raised shoulder boxes with glowing fan vents on top and
# orange coil drums on their outer faces; red hydraulic hoses arcing up from the shoulders
# and down to the arms; thin slate-and-tan arms (axe hanging in one, a long war pike held
# upright in the other); a rod across the shoulders; narrow dark waist; long legs with
# perforated plates, wheel-like knees and clawed feet. Worn tan paint, rust-red hoses.

func _blackbeard() -> void:
	m.set_meta("custom_pose", true)
	var T := MeshKit.paint(Color(0.55, 0.5, 0.38), 0.2, 0.7, 0.12)
	var T2 := MeshKit.paint(Color(0.68, 0.64, 0.52), 0.2, 0.65, 0.08)
	var S := MeshKit.paint(Color(0.22, 0.27, 0.29), 0.5, 0.55, 0.1)
	var D := MeshKit.paint(Color(0.1, 0.11, 0.12), 0.65, 0.5, 0.0)
	var R := MeshKit.paint(Color(0.42, 0.16, 0.11), 0.05, 0.85, 0.0)
	var RED := MeshKit.paint(Color(0.66, 0.13, 0.08), 0.15, 0.6, 0.0)
	var OR := MeshKit.paint(Color(0.85, 0.34, 0.12), 0.1, 0.5, 0.0, Color(0.35, 0.1, 0.02))
	var GLOW := MeshKit.paint(Color(0.75, 0.28, 0.08), 0.1, 0.45, 0.0, Color(0.45, 0.14, 0.03))
	var hip_y := 0.52
	var torso_origin := Vector3(0, hip_y + 0.05, 0)
	var B := func(v: Vector3) -> Vector3: return v - torso_origin
	# Pelvis and long knock-kneed legs with claw feet.
	m.pelvis = _p(body, "Pelvis", Vector3(0, hip_y, 0))
	m.pelvis.set_meta("rest_y", hip_y)
	_add(m.pelvis, SmoothKit.rounded_box(Vector3(0.22, 0.06, 0.12), 0.02), S)
	_add(m.pelvis, SmoothKit.rounded_box(Vector3(0.12, 0.07, 0.05), 0.015), T, Vector3(0, -0.015, -0.06))
	_add(m.pelvis, MeshKit.cylinder(0.012, 0.2, 6), D, Vector3(0, -0.035, -0.02), Vector3(0, 0, 90))
	for s: float in [1.0, -1.0]:
		var side := "r" if s > 0 else "l"
		var leg := _rig_leg(side, Vector3(s * 0.1, -0.01, 0), 0.2, 0.25)
		var hip: Node3D = leg["hip"]
		var knee: Node3D = leg["knee"]
		var ankle: Node3D = leg["ankle"]
		hip.rotation_degrees = Vector3(8, 0, s * 5)
		knee.rotation_degrees = Vector3(-14, 0, s * -8)
		ankle.rotation_degrees = Vector3(6, 0, s * 3)
		leg["base"] = Vector3(8, -14, 6)
		# Hip: dark wheel joint; thigh: dark strut inside a tan outer plate.
		_add(hip, MeshKit.cylinder(0.042, 0.06, 16), D, Vector3(s * 0.01, 0, 0), Vector3(0, 0, 90))
		_add(hip, MeshKit.cylinder(0.026, 0.065, 12), T2, Vector3(s * 0.012, 0, 0), Vector3(0, 0, 90))
		_add(hip, SmoothKit.rounded_box(Vector3(0.05, 0.2, 0.06), 0.012), S, Vector3(0, -0.1, 0.005))
		_add(hip, MeshKit.cylinder(0.012, 0.18, 8), D, Vector3(s * -0.03, -0.1, 0.02))
		_add(hip, SmoothKit.rounded_box(Vector3(0.05, 0.15, 0.1), 0.016), T, Vector3(s * 0.03, -0.09, 0))
		_add(hip, SmoothKit.rounded_box(Vector3(0.05, 0.06, 0.04), 0.012), T, Vector3(s * -0.012, -0.04, -0.04))
		for i in range(3):
			for j in range(2):
				_add(hip, MeshKit.cylinder(0.0065, 0.012, 8), D, Vector3(s * 0.056, -0.04 - i * 0.035, (j - 0.5) * 0.04), Vector3(0, 0, 90))
		_add(hip, _torus(0.05, 0.009), R, Vector3(s * 0.01, -0.165, 0), Vector3(0, 0, 10))
		_add(hip, _torus(0.05, 0.009), R, Vector3(s * 0.01, -0.148, 0), Vector3(0, 0, -6))
		# Knee: big side wheels and a tan cap.
		for k: float in [1.0, -1.0]:
			_add(knee, MeshKit.cylinder(0.042, 0.018, 18), D, Vector3(k * 0.04, 0, 0), Vector3(0, 0, 90))
			_add(knee, MeshKit.cylinder(0.02, 0.022, 10), T2, Vector3(k * 0.042, 0, 0), Vector3(0, 0, 90))
		_add(knee, SmoothKit.rounded_box(Vector3(0.075, 0.06, 0.04), 0.012), T2, Vector3(0, -0.005, -0.045), Vector3(-12, 0, 0))
		# Shin: long tan plate with a perforated strip, dark piston behind.
		_add(knee, SmoothKit.rounded_box(Vector3(0.045, 0.23, 0.05), 0.012), S, Vector3(0, -0.13, 0.02))
		_add(knee, MeshKit.cylinder(0.011, 0.2, 8), D, Vector3(s * 0.025, -0.13, 0.04))
		_add(knee, SmoothKit.loft([
			{"y": -0.24, "w": 0.058, "d": 0.045, "n": 3.0},
			{"y": -0.14, "w": 0.072, "d": 0.055, "n": 3.0},
			{"y": -0.035, "w": 0.066, "d": 0.05, "n": 3.0},
		], 16), T, Vector3(0, 0, -0.03))
		for i in range(5):
			for j in range(2):
				_add(knee, MeshKit.cylinder(0.0055, 0.012, 8), D, Vector3((j - 0.5) * 0.03, -0.06 - i * 0.034, -0.054), Vector3(90, 0, 0))
		_add(knee, _torus(0.045, 0.008), R, Vector3(0, -0.04, -0.005))
		# Ankle and claw foot: three long toes forward, a spur back.
		_add(ankle, MeshKit.cylinder(0.03, 0.06, 14), D, Vector3.ZERO, Vector3(0, 0, 90))
		_add(ankle, SmoothKit.loft([{"y": -0.075, "w": 0.1, "d": 0.12, "n": 3.0}, {"y": -0.03, "w": 0.095, "d": 0.11, "n": 3.0}, {"y": 0.0, "w": 0.07, "d": 0.08, "n": 3.0}], 16), T, Vector3(0, 0, -0.025))
		_add(ankle, SmoothKit.rounded_box(Vector3(0.07, 0.03, 0.02), 0.006), S, Vector3(0, -0.04, -0.087))
		for k in range(3):
			var toe := _p(ankle, "Toe", Vector3((k - 1) * 0.03, -0.06, -0.08), Vector3(-150, 0, (k - 1) * 10))
			_add(toe, SmoothKit.loft([{"y": 0.0, "w": 0.026, "d": 0.024}, {"y": 0.035, "w": 0.024, "d": 0.022}, {"y": 0.055, "w": 0.016, "d": 0.014}, {"y": 0.065, "w": 0.005, "d": 0.005}], 10), S)
		var heel := _p(ankle, "Heel", Vector3(0, -0.05, 0.03), Vector3(100, 0, 0))
		_add(heel, SmoothKit.loft([{"y": 0.0, "w": 0.022, "d": 0.02}, {"y": 0.05, "w": 0.008, "d": 0.008}], 8), S)
	# Torso: a bell-shaped hull, wide at the shoulders, pinched at the waist.
	m.torso = _p(m.pelvis, "Torso", Vector3(0, 0.05, 0))
	for i in range(3):
		_add(m.torso, _torus(0.055 - i * 0.004, 0.012), D, Vector3(0, -0.015 + i * 0.018, 0))
	_add(m.torso, MeshKit.cylinder(0.035, 0.06, 12), S, Vector3(0, 0.0, 0))
	_add(m.torso, SmoothKit.loft([
		{"y": 0.025, "w": 0.1, "d": 0.09, "n": 2.6},
		{"y": 0.07, "w": 0.15, "d": 0.14, "n": 2.8},
		{"y": 0.14, "w": 0.2, "d": 0.19, "n": 3.0},
		{"y": 0.2, "w": 0.235, "d": 0.21, "n": 3.2},
	], 30), S)
	_add(m.torso, SmoothKit.loft([
		{"y": 0.15, "w": 0.21, "d": 0.2, "n": 3.0},
		{"y": 0.22, "w": 0.25, "d": 0.225, "n": 3.2},
		{"y": 0.3, "w": 0.26, "d": 0.235, "n": 3.2},
		{"y": 0.355, "w": 0.235, "d": 0.215, "n": 3.0},
		{"y": 0.39, "w": 0.15, "d": 0.14, "n": 2.6},
	], 30), T)
	for s: float in [1.0, -1.0]:
		_add(m.torso, SmoothKit.rounded_box(Vector3(0.05, 0.12, 0.13), 0.02), T, Vector3(s * 0.1, 0.11, 0.0), Vector3(0, 0, s * 12))
	# Dark ribbed belly bands and the front plates.
	for i in range(5):
		var y := 0.07 + i * 0.03
		var w := 0.12 + i * 0.028
		_add(m.torso, SmoothKit.blob(Vector3(w, 0.018, 0.03), 0.35, 0.6), S, Vector3(0, y, -0.055 - i * 0.012), Vector3(-14, 0, 0))
	_add(m.torso, SmoothKit.rounded_box(Vector3(0.09, 0.14, 0.03), 0.012), S, Vector3(0, 0.23, -0.108), Vector3(-6, 0, 0))
	_add(m.torso, SmoothKit.rounded_box(Vector3(0.045, 0.035, 0.012), 0.004), T2, Vector3(0, 0.255, -0.125), Vector3(-6, 0, 0))
	_add(m.torso, SmoothKit.rounded_box(Vector3(0.06, 0.02, 0.02), 0.005), D, Vector3(0, 0.185, -0.125), Vector3(-6, 0, 0))
	for s: float in [1.0, -1.0]:
		_add(m.torso, SmoothKit.rounded_box(Vector3(0.07, 0.035, 0.02), 0.006), D, Vector3(s * 0.08, 0.22, -0.112), Vector3(-6, s * 18, 0))
		for k in range(3):
			_add(m.torso, MeshKit.chamfer_box(Vector3(0.055, 0.004, 0.006), 0.001), GLOW, Vector3(s * 0.08, 0.21 + k * 0.01, -0.122), Vector3(-6, s * 18, 0))
		_add(m.torso, SmoothKit.blob(Vector3(0.03, 0.022, 0.02), 0.5, 0.5), GLOW, Vector3(s * 0.12, 0.11, -0.08), Vector3(0, s * 30, 0))
		_add(m.torso, SmoothKit.rounded_box(Vector3(0.05, 0.03, 0.012), 0.004), T2, Vector3(s * 0.1, 0.29, -0.105), Vector3(-8, s * 22, 0))
	_add(m.torso, MeshKit.cylinder(0.02, 0.045, 12), RED, Vector3(0, 0.05, -0.055), Vector3(0, 0, 90))
	# Sensor wedge in thick coils of red rope.
	m.head = _p(m.torso, "Head", Vector3(0, 0.39, -0.04), Vector3(-18, 0, 0))
	_add(m.head, MeshKit.chamfer_box(Vector3(0.13, 0.085, 0.1), 0.014, 0.3), OR, Vector3(0, 0.035, 0))
	_add(m.head, SmoothKit.lathe([Vector2(0.085, -0.02), Vector2(0.09, 0.02), Vector2(0.08, 0.03)], 24, false), D, Vector3(0, 0.0, 0.01))
	_add(m.head, SmoothKit.blob(Vector3(0.025, 0.015, 0.01), 0.5, 0.5), GLOW, Vector3(0, 0.035, -0.045))
	for i in range(4):
		_add(m.torso, _torus(0.085 + i * 0.012, 0.015), R, Vector3(0, 0.345 + i * 0.01, -0.025 + i * 0.006), Vector3(-10 + i * 5, i * 20, 0))
	_eye(m.head, Vector3(0, 0.035, -0.06))
	# Rope ends hanging down the chest and sides.
	for i in range(9):
		var x := -0.16 + i * 0.04
		var top := Vector3(x * 0.8, 0.35, -0.09 + absf(x) * 0.3)
		var drop := 0.12 + 0.06 * ((i * 7) % 3)
		_add(m.torso, SmoothKit.tube(SmoothKit.bezier(top, top + Vector3(x * 0.1, -0.04, -0.04), top + Vector3(x * 0.25, -drop * 0.6, -0.04), top + Vector3(x * 0.3, -drop, -0.02), 8), 0.0075, 6), R)
	# Shoulder boxes, tilted back, with big fan vents and coil drums.
	for s: float in [1.0, -1.0]:
		var side := "r" if s > 0 else "l"
		var box := _p(m.torso, "Pad_" + side, B.call(Vector3(s * 0.165, 0.83, 0.03)), Vector3(-12, s * 6, s * -8))
		_add(box, SmoothKit.rounded_box(Vector3(0.165, 0.24, 0.2), 0.032), T, Vector3.ZERO)
		_add(box, SmoothKit.rounded_box(Vector3(0.15, 0.09, 0.02), 0.01), S, Vector3(s * -0.01, -0.075, -0.105))
		for k in range(4):
			var dial := Vector3(s * (-0.045 + 0.03 * (k % 2)), -0.05 - 0.036 * (k / 2), -0.117)
			_add(box, MeshKit.cylinder(0.011, 0.01, 12), T2, dial, Vector3(90, 0, 0))
			_add(box, MeshKit.cylinder(0.005, 0.012, 8), D, dial, Vector3(90, 0, 0))
		for k in range(8):
			_add(box, MeshKit.cylinder(0.005, 0.01, 6), D, Vector3(s * (0.02 + 0.015 * (k % 4)), -0.095 - 0.016 * (k / 4), -0.112), Vector3(90, 0, 0))
		var vent := _p(box, "Vent", Vector3(0, 0.1, -0.06), Vector3(-38, 0, 0))
		_add(vent, SmoothKit.lathe([Vector2(0.074, -0.03), Vector2(0.08, 0.0), Vector2(0.074, 0.02), Vector2(0.06, 0.022), Vector2(0.056, 0.0)], 28, false), T2)
		_add(vent, MeshKit.cylinder(0.058, 0.01, 28), GLOW, Vector3(0, 0.0, 0))
		for k in range(14):
			_add(vent, MeshKit.chamfer_box(Vector3(0.008, 0.01, 0.056), 0.001), D, Vector3(0, 0.008, 0), Vector3(0, k * 12.86, 0))
		_add(vent, MeshKit.cylinder(0.016, 0.014, 12), D, Vector3(0, 0.012, 0))
		_add(vent, MeshKit.cylinder(0.01, 0.05, 10, 0.0), D, Vector3(0, 0.04, 0))
		var drum := _p(box, "Drum", Vector3(s * 0.105, 0.0, 0.0))
		_add(drum, MeshKit.cylinder(0.042, 0.065, 18), GLOW, Vector3.ZERO, Vector3(0, 0, 90))
		for k in range(5):
			_add(drum, MeshKit.cylinder(0.045, 0.006, 18), S, Vector3(s * (-0.03 + k * 0.015), 0, 0), Vector3(0, 0, 90))
		_add(drum, MeshKit.cylinder(0.03, 0.01, 14), D, Vector3(s * 0.036, 0, 0), Vector3(0, 0, 90))
		_add(box, SmoothKit.rounded_box(Vector3(0.17, 0.03, 0.19), 0.008), S, Vector3(0, -0.135, 0))
		_add(box, SmoothKit.rounded_box(Vector3(0.05, 0.05, 0.05), 0.01), T2, Vector3(s * 0.06, 0.12, 0.06))
		m.slots["shoulder_" + side] = _p(box, "Slot_shoulder_" + side, Vector3(0, 0.14, 0.06))
		m.slots["back_" + side] = _p(m.torso, "Slot_back_" + side, B.call(Vector3(s * 0.1, 0.9, 0.14)))
	_add(m.torso, MeshKit.cylinder(0.007, 0.66, 6), S, B.call(Vector3(-0.06, 0.73, -0.09)), Vector3(0, 0, 90))
	# Arms: the right hangs with the axe, the left reaches out and up to hold the pike.
	var arm_r := _rig_arm("r", Vector3.ZERO, 0.2, 0.21, 0.0, 0.04)
	var arm_l := _rig_arm("l", Vector3.ZERO, 0.14, 0.15, 0.0, 0.04)
	_pose_arm(arm_r, B.call(Vector3(0.23, 0.71, -0.02)), B.call(Vector3(0.28, 0.53, -0.05)), B.call(Vector3(0.26, 0.31, -0.04)), Vector3(0.35, -1, 0.05))
	_pose_arm(arm_l, B.call(Vector3(-0.23, 0.73, -0.02)), B.call(Vector3(-0.38, 0.72, -0.07)), B.call(Vector3(-0.35, 0.88, -0.09)), Vector3(-0.12, 1, 0))
	for arm: Dictionary in [arm_r, arm_l]:
		var up: float = (arm["elbow"] as Node3D).position.length()
		var fore: float = (arm["hand"] as Node3D).position.length()
		_add(arm["shoulder"], SmoothKit.blob(Vector3(0.06, 0.06, 0.06), 1.0, 1.0), D)
		_add(arm["shoulder"], MeshKit.cylinder(0.014, up, 8), S, Vector3(0, -up / 2.0, 0))
		_add(arm["shoulder"], MeshKit.cylinder(0.01, up * 0.9, 6), D, Vector3(0.018, -up / 2.0, 0.01))
		_add(arm["shoulder"], SmoothKit.rounded_box(Vector3(0.045, up * 0.3, 0.045), 0.012), T2, Vector3(0, -up * 0.2, 0))
		_add(arm["elbow"], MeshKit.cylinder(0.036, 0.04, 18), D, Vector3.ZERO, Vector3(0, 0, 90))
		_add(arm["elbow"], MeshKit.cylinder(0.022, 0.046, 12), T2, Vector3.ZERO, Vector3(0, 0, 90))
		_add(arm["elbow"], MeshKit.cylinder(0.013, fore, 8), S, Vector3(0, -fore / 2.0, 0))
		_add(arm["elbow"], SmoothKit.loft([{"y": -fore * 0.95, "w": 0.06, "d": 0.06, "n": 3.0}, {"y": -fore * 0.5, "w": 0.055, "d": 0.055, "n": 3.0}, {"y": -fore * 0.15, "w": 0.04, "d": 0.04, "n": 3.0}], 14), T)
		_add(arm["hand"], SmoothKit.rounded_box(Vector3(0.05, 0.065, 0.05), 0.012), RED)
		for k in range(3):
			_add(arm["hand"], MeshKit.cylinder(0.009, 0.04, 8), D, Vector3((k - 1) * 0.016, -0.04, -0.012))
	# Red hydraulic hoses: big loops up and out from the shoulder boxes, down to the arms.
	var hoses := [
		[Vector3(0.17, 0.94, 0.06), Vector3(0.17, 1.03, 0.06), Vector3(0.36, 1.02, 0.03), Vector3(0.345, 0.8, -0.0), Vector3(0.285, 0.55, -0.04)],
		[Vector3(-0.13, 0.95, 0.06), Vector3(-0.13, 1.03, 0.06), Vector3(-0.33, 1.03, 0.02), Vector3(-0.35, 0.95, -0.04), Vector3(-0.35, 0.89, -0.08)],
	]
	for hp: Array in hoses:
		var a := SmoothKit.bezier(B.call(hp[0]), B.call(hp[1]), B.call(hp[2]), B.call(hp[3]), 16)
		var b := SmoothKit.bezier(B.call(hp[3]), B.call(hp[3]) + (B.call(hp[3]) - B.call(hp[2])).normalized() * 0.06, B.call(hp[4]) + Vector3(0, 0.08, 0), B.call(hp[4]), 10)
		var pts: Array = a + b.slice(1)
		_add(m.torso, SmoothKit.tube(pts, 0.02, 12), R)
		for idx in [0, 5, 10, 16, 21]:
			var c: Vector3 = pts[mini(idx, pts.size() - 1)]
			var nxt: Vector3 = pts[mini(idx + 1, pts.size() - 1)]
			var cuff := MeshKit.part(m.torso, MeshKit.cylinder(0.026, 0.03, 12), T2, c)
			cuff.basis = basis_down(nxt - c if nxt != c else Vector3.DOWN)
			MeshKit.part(cuff, MeshKit.cylinder(0.012, 0.06, 8), D, Vector3.ZERO, Vector3(0, 0, 90))


func _torus(radius: float, thickness: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = radius - thickness
	t.outer_radius = radius + thickness
	t.rings = 32
	t.ring_segments = 8
	return t


# --- Goblin (HORUS) -------------------------------------------------------------------------
# From the core book art: a lanky teal crouching thing. Wide-set bent legs ending in long
# splayed toes, a narrow waist over a red core band, hunched shoulder humps bristling with
# red-tipped spikes, a crest plate with two long antenna rods over a sunken goggle face, and
# long arms with big clawed hands hanging low. Smooth rounded teal plates over dark innards.

func _goblin() -> void:
	m.set_meta("custom_pose", true)
	var TL := MeshKit.paint(Color(0.24, 0.48, 0.5), 0.3, 0.45, 0.15)
	var TL2 := MeshKit.paint(Color(0.36, 0.62, 0.62), 0.3, 0.45, 0.1)
	var DK := MeshKit.paint(Color(0.18, 0.13, 0.16), 0.5, 0.55, 0.0)
	var RD := MeshKit.paint(Color(0.72, 0.16, 0.14), 0.2, 0.5, 0.0)
	var GL := MeshKit.paint(Color(0.3, 0.05, 0.03), 0.2, 0.2, 0.0, Color(1.0, 0.35, 0.15))
	var hip_y := 0.42
	m.pelvis = _p(body, "Pelvis", Vector3(0, hip_y, 0))
	m.pelvis.set_meta("rest_y", hip_y)
	_add(m.pelvis, SmoothKit.blob(Vector3(0.2, 0.09, 0.12), 0.7, 0.7), TL)
	_add(m.pelvis, SmoothKit.loft([{"y": -0.1, "w": 0.05, "d": 0.03}, {"y": -0.02, "w": 0.09, "d": 0.05}, {"y": 0.03, "w": 0.1, "d": 0.05}], 14), TL2, Vector3(0, 0, -0.06), Vector3(10, 0, 0))
	for s: float in [1.0, -1.0]:
		var side := "r" if s > 0 else "l"
		var leg := _rig_leg(side, Vector3(s * 0.1, -0.01, 0), 0.22, 0.27)
		var hip: Node3D = leg["hip"]
		var knee: Node3D = leg["knee"]
		var ankle: Node3D = leg["ankle"]
		# Splayed, bent legs: thigh out and forward, shin back down and out.
		hip.rotation_degrees = Vector3(30, 0, s * 28)
		knee.rotation_degrees = Vector3(-45, 0, s * -18)
		ankle.rotation_degrees = Vector3(15, 0, s * -10)
		leg["base"] = Vector3(30, -45, 15)
		_add(hip, SmoothKit.blob(Vector3(0.07, 0.07, 0.07), 1.0, 1.0), DK)
		_add(hip, _limb(0.21, 0.055, 0.045, 0.25), TL)
		_add(knee, SmoothKit.blob(Vector3(0.1, 0.09, 0.09), 0.8, 0.8), TL, Vector3(0, 0, -0.01))
		_add(knee, MeshKit.sphere(0.012, 8), RD, Vector3(0, 0.0, -0.055))
		_add(knee, _limb(0.26, 0.035, 0.026, 0.15), TL)
		_add(knee, MeshKit.cylinder(0.01, 0.22, 6), DK, Vector3(0, -0.12, 0.03))
		_add(ankle, SmoothKit.blob(Vector3(0.05, 0.05, 0.05), 1.0, 1.0), TL2)
		# Long splayed toes.
		for k in range(4):
			var a := (k - 1.5) * 32.0 + (180.0 if k == 3 else 0.0) * 0.0
			var toe := _p(ankle, "Toe", Vector3(0, -0.02, 0), Vector3(0, a + (150.0 if k == 3 else 0.0), 0))
			var seg := _p(toe, "Seg", Vector3.ZERO, Vector3(-115, 0, 0))
			_add(seg, SmoothKit.loft([{"y": 0.0, "w": 0.022, "d": 0.02}, {"y": 0.06, "w": 0.018, "d": 0.016}, {"y": 0.1, "w": 0.012, "d": 0.01}], 10), TL)
			_add(seg, SmoothKit.loft([{"y": 0.1, "w": 0.014, "d": 0.012}, {"y": 0.125, "w": 0.004, "d": 0.004}], 8), DK)
	# Torso: narrow waist with a red core band, chest rising to hunched shoulder humps.
	m.torso = _p(m.pelvis, "Torso", Vector3(0, 0.04, 0), Vector3(-14, 0, 0))
	_add(m.torso, MeshKit.cylinder(0.045, 0.08, 14), DK, Vector3(0, 0.04, 0))
	_add(m.torso, MeshKit.cylinder(0.05, 0.03, 14), RD, Vector3(0, 0.06, 0))
	_add(m.torso, SmoothKit.loft([
		{"y": 0.07, "w": 0.13, "d": 0.11, "n": 2.4},
		{"y": 0.15, "w": 0.2, "d": 0.14, "n": 2.6},
		{"y": 0.23, "w": 0.22, "d": 0.15, "n": 2.6},
		{"y": 0.28, "w": 0.16, "d": 0.12, "n": 2.4},
	], 22), TL)
	_add(m.torso, SmoothKit.blob(Vector3(0.12, 0.08, 0.04), 0.6, 0.6), TL2, Vector3(0, 0.2, -0.07))
	_add(m.torso, MeshKit.sphere(0.012, 8), GL, Vector3(0.06, 0.17, -0.075))
	_add(m.torso, MeshKit.sphere(0.009, 8), GL, Vector3(0.075, 0.15, -0.07))
	# Shoulder humps with red-tipped spikes.
	for s: float in [1.0, -1.0]:
		var hump := _p(m.torso, "Pad_" + ("r" if s > 0 else "l"), Vector3(s * 0.12, 0.27, 0.0))
		_add(hump, SmoothKit.blob(Vector3(0.15, 0.11, 0.14), 0.75, 0.7), TL)
		for k in range(4):
			var a := deg_to_rad(20.0 + k * 35.0)
			var spike := _p(hump, "Spike", Vector3(s * cos(a) * 0.06, 0.03 + sin(a) * 0.04, -0.02 + (k % 2) * 0.03), Vector3(-20, 0, s * -(70 - k * 30)))
			_add(spike, MeshKit.cylinder(0.005, 0.07, 5), DK, Vector3(0, 0.035, 0))
			_add(spike, MeshKit.cylinder(0.006, 0.02, 5, 0.0), RD, Vector3(0, 0.08, 0))
		m.slots["shoulder_" + ("r" if s > 0 else "l")] = _p(hump, "Slot_shoulder", Vector3(0, 0.06, 0.03))
		m.slots["back_" + ("r" if s > 0 else "l")] = _p(m.torso, "Slot_back", Vector3(s * 0.06, 0.26, 0.08))
	# Head: sunken goggle face under a crest plate with two long antenna rods.
	m.head = _p(m.torso, "Head", Vector3(0, 0.26, -0.05), Vector3(18, 0, 0))
	_add(m.head, SmoothKit.blob(Vector3(0.09, 0.06, 0.07), 0.7, 0.7), DK, Vector3(0, 0.0, 0))
	_add(m.head, SmoothKit.blob(Vector3(0.075, 0.035, 0.03), 0.4, 0.5), GL, Vector3(0, 0.005, -0.03))
	for s: float in [1.0, -1.0]:
		_add(m.head, _torus(0.015, 0.004), TL2, Vector3(s * 0.02, 0.006, -0.046), Vector3(90, 0, 0))
	var crest := _p(m.head, "Crest", Vector3(0, 0.07, -0.01), Vector3(-30, 0, 0))
	_add(crest, SmoothKit.blob(Vector3(0.13, 0.03, 0.09), 0.6, 0.7), TL)
	for k in range(5):
		_add(crest, MeshKit.sphere(0.008, 6), RD, Vector3((k - 2) * 0.02, 0.012, -0.02 + (k % 2) * 0.02))
	for s: float in [1.0, -1.0]:
		var ant := _p(crest, "Antenna", Vector3(s * 0.05, 0.01, 0.0), Vector3(-10, 0, s * -55))
		_add(ant, MeshKit.cylinder(0.009, 0.28, 8), TL, Vector3(0, 0.14, 0))
		_add(ant, MeshKit.cylinder(0.01, 0.03, 8), DK, Vector3(0, 0.02, 0))
		_add(ant, MeshKit.cylinder(0.009, 0.025, 8, 0.004), RD, Vector3(0, 0.29, 0))
		var short := _p(crest, "Spine", Vector3(s * 0.015, 0.01, 0.0), Vector3(0, 0, s * -10))
		_add(short, MeshKit.cylinder(0.006, 0.08, 6, 0.002), TL2, Vector3(0, 0.04, 0))
	_eye(m.head, Vector3(0, 0.005, -0.05))
	# Long arms hanging low and out, big clawed hands.
	var arm_r := _rig_arm("r", Vector3.ZERO, 0.2, 0.22, 0.0, 0.03)
	var arm_l := _rig_arm("l", Vector3.ZERO, 0.2, 0.22, 0.0, 0.03)
	_pose_arm(arm_r, Vector3(0.17, 0.22, 0.0), Vector3(0.28, 0.06, -0.06), Vector3(0.34, -0.13, -0.08), Vector3(0, -1, -0.3))
	_pose_arm(arm_l, Vector3(-0.17, 0.22, 0.0), Vector3(-0.3, 0.07, -0.02), Vector3(-0.36, -0.12, -0.06), Vector3(0, -1, -0.3))
	for arm: Dictionary in [arm_r, arm_l]:
		_add(arm["shoulder"], SmoothKit.blob(Vector3(0.06, 0.06, 0.06), 1.0, 1.0), DK)
		_add(arm["shoulder"], _limb(0.2, 0.032, 0.028, 0.2), TL)
		_add(arm["elbow"], SmoothKit.blob(Vector3(0.05, 0.05, 0.05), 1.0, 1.0), DK)
		_add(arm["elbow"], _limb(0.22, 0.03, 0.04, 0.35), TL)
		_add(arm["hand"], SmoothKit.blob(Vector3(0.06, 0.05, 0.035), 0.7, 0.7), TL2)
		for k in range(4):
			var f := _p(arm["hand"], "Claw", Vector3((k - 1.5) * 0.016, -0.02, 0), Vector3(-20, 0, (k - 1.5) * 12))
			_add(f, _limb(0.07, 0.008, 0.006), TL)
			var tip := _p(f, "Tip", Vector3(0, -0.07, 0), Vector3(-35, 0, 0))
			_add(tip, SmoothKit.loft([{"y": -0.04, "w": 0.002, "d": 0.002}, {"y": 0.0, "w": 0.008, "d": 0.007}], 6, false), DK)


# --- Lancaster (IPS-N) --------------------------------------------------------------------
# From the core book art: a four-legged olive utility walker. A tall boxy cab at the front
# (window slit, name plate, round lamps) wrapped in a red pipe roll cage; a long body behind
# it carrying dark cargo trunks with red handles and big barrel tanks, red pipes along the
# flanks; four legs with olive armored thighs and long ribbed, cloth-wrapped lower legs on
# round pads. Small manipulator claws hang under the cab.

func _lancaster() -> void:
	m.set_meta("custom_pose", true)
	var OL := MeshKit.paint(Color(0.33, 0.37, 0.2), 0.25, 0.65, 0.2)
	var OL2 := MeshKit.paint(Color(0.4, 0.44, 0.26), 0.25, 0.6, 0.12)
	var DK := MeshKit.paint(Color(0.13, 0.13, 0.13), 0.6, 0.5, 0.0)
	var WR := MeshKit.paint(Color(0.26, 0.21, 0.17), 0.1, 0.85, 0.0)
	var RP := MeshKit.paint(Color(0.82, 0.3, 0.2), 0.3, 0.5, 0.0)
	var TR := MeshKit.paint(Color(0.2, 0.15, 0.12), 0.2, 0.7, 0.0)
	var RU := MeshKit.paint(Color(0.42, 0.3, 0.2), 0.4, 0.6, 0.0)
	var LAMP := MeshKit.paint(Color(0.3, 0.25, 0.05), 0.2, 0.2, 0.0, Color(1.0, 0.85, 0.35))
	var body_y := 0.66
	m.pelvis = _p(body, "Pelvis", Vector3(0, body_y, 0))
	m.pelvis.set_meta("rest_y", body_y)
	m.torso = _p(m.pelvis, "Torso", Vector3.ZERO)
	var t := m.torso
	# Long body behind the cab.
	_add(t, SmoothKit.rounded_box(Vector3(0.44, 0.3, 0.72), 0.05), OL, Vector3(0, 0.02, 0.22))
	_add(t, SmoothKit.rounded_box(Vector3(0.36, 0.08, 0.66), 0.03), DK, Vector3(0, -0.15, 0.22))
	# Cab: tall box at the front, slightly raked.
	var cab := _p(t, "Cab", Vector3(0, 0.08, -0.25), Vector3(-4, 0, 0))
	_add(cab, SmoothKit.rounded_box(Vector3(0.48, 0.44, 0.36), 0.06), OL)
	_add(cab, SmoothKit.rounded_box(Vector3(0.3, 0.06, 0.02), 0.012), DK, Vector3(-0.02, 0.1, -0.18))
	_add(cab, SmoothKit.rounded_box(Vector3(0.36, 0.1, 0.02), 0.02), OL2, Vector3(-0.02, 0.13, -0.183))
	_add(cab, SmoothKit.rounded_box(Vector3(0.14, 0.05, 0.012), 0.008), DK, Vector3(-0.04, 0.02, -0.184))
	var plate := Label3D.new()
	plate.text = "BESS"
	plate.font_size = 64
	plate.pixel_size = 0.0008
	plate.modulate = Color(0.85, 0.85, 0.8)
	plate.position = Vector3(-0.04, 0.02, -0.192)
	plate.rotation_degrees = Vector3(0, 180, 0)
	cab.add_child(plate)
	_add(cab, MeshKit.cylinder(0.018, 0.012, 14), LAMP, Vector3(-0.17, 0.12, -0.186), Vector3(90, 0, 0))
	for k in range(2):
		_add(cab, MeshKit.cylinder(0.011, 0.012, 12), LAMP, Vector3(0.12, 0.02 - k * 0.03, -0.186), Vector3(90, 0, 0))
	_add(cab, SmoothKit.rounded_box(Vector3(0.12, 0.06, 0.03), 0.008), DK, Vector3(-0.02, -0.1, -0.18))
	for k in range(4):
		_add(cab, MeshKit.cylinder(0.008, 0.06, 8), DK, Vector3(-0.08 + k * 0.035, -0.17, -0.17), Vector3(0, 0, 90))
	# Side door with a vent on the cab's flanks.
	for s: float in [1.0, -1.0]:
		_add(cab, SmoothKit.rounded_box(Vector3(0.012, 0.3, 0.22), 0.01), OL2, Vector3(s * 0.243, 0.0, 0.0))
		_add(cab, SmoothKit.rounded_box(Vector3(0.01, 0.08, 0.1), 0.006), DK, Vector3(s * 0.25, 0.1, 0.03))
		for k in range(4):
			_add(cab, MeshKit.chamfer_box(Vector3(0.006, 0.006, 0.09), 0.001), RU, Vector3(s * 0.255, 0.075 + k * 0.016, 0.03))
	m.head = _p(cab, "Head", Vector3(-0.02, 0.1, -0.19))
	_eye(m.head, Vector3(0, 0, -0.01))
	# Red pipe roll cage over the cab.
	var cage := _p(cab, "Cage", Vector3.ZERO)
	var cx := 0.29
	var cy0 := -0.16
	var cy1 := 0.3
	var cz0 := -0.24
	var cz1 := 0.2
	var rails := [
		[Vector3(-cx, cy1, cz0), Vector3(cx, cy1, cz0)], [Vector3(-cx, cy1, cz1), Vector3(cx, cy1, cz1)],
		[Vector3(-cx, cy1, cz0), Vector3(-cx, cy1, cz1)], [Vector3(cx, cy1, cz0), Vector3(cx, cy1, cz1)],
		[Vector3(-cx, cy1, cz0), Vector3(-cx, cy0, cz0)], [Vector3(cx, cy1, cz0), Vector3(cx, cy0, cz0)],
		[Vector3(-cx, cy0, cz0), Vector3(cx, cy0, cz0)], [Vector3(-cx, 0.07, cz0), Vector3(cx, 0.07, cz0)],
		[Vector3(0.0, cy1, cz0), Vector3(0.0, cy0, cz0)], [Vector3(0.0, cy1, cz0), Vector3(0.0, cy1, cz1)],
		[Vector3(-cx, cy1, cz1), Vector3(-cx, 0.0, cz1)], [Vector3(cx, cy1, cz1), Vector3(cx, 0.0, cz1)],
		[Vector3(-cx, 0.07, cz0), Vector3(-cx, 0.07, cz1)], [Vector3(cx, 0.07, cz0), Vector3(cx, 0.07, cz1)],
	]
	for r: Array in rails:
		_add(cage, SmoothKit.tube([r[0], r[1]], 0.011, 8), RP)
	for c: Vector3 in [Vector3(-cx, cy1, cz0), Vector3(cx, cy1, cz0), Vector3(-cx, cy1, cz1), Vector3(cx, cy1, cz1), Vector3(0, cy1, cz0), Vector3(-cx, 0.07, cz0), Vector3(cx, 0.07, cz0), Vector3(0, 0.07, cz0)]:
		_add(cage, SmoothKit.rounded_box(Vector3(0.03, 0.03, 0.03), 0.008), RP, c)
	# Cargo: dark trunks with red handles along the left flank, barrel tanks on top.
	for k in range(2):
		var z := 0.12 + k * 0.24
		for s: float in [1.0, -1.0]:
			_add(t, SmoothKit.rounded_box(Vector3(0.1, 0.2, 0.22), 0.02), TR, Vector3(s * 0.26, 0.0, z))
			_add(t, SmoothKit.tube(SmoothKit.bezier(Vector3(s * 0.315, 0.03, z - 0.05), Vector3(s * 0.34, 0.03, z - 0.05), Vector3(s * 0.34, 0.03, z + 0.05), Vector3(s * 0.315, 0.03, z + 0.05), 6), 0.006, 6), RP)
	for k in range(2):
		_add(t, MeshKit.cylinder(0.07, 0.3, 18), RU, Vector3(-0.08 + k * 0.17, 0.24, 0.32), Vector3(90, 0, 0))
		for b in range(3):
			_add(t, MeshKit.cylinder(0.073, 0.012, 18), DK, Vector3(-0.08 + k * 0.17, 0.24, 0.2 + b * 0.12), Vector3(90, 0, 0))
	# Red pipes along the flanks.
	for s: float in [1.0, -1.0]:
		_add(t, SmoothKit.tube([Vector3(s * 0.235, 0.17, -0.05), Vector3(s * 0.235, 0.17, 0.55)], 0.009, 8), RP)
		_add(t, SmoothKit.tube([Vector3(s * 0.235, -0.12, -0.05), Vector3(s * 0.235, -0.12, 0.55)], 0.009, 8), RP)
		for k in range(4):
			_add(t, SmoothKit.tube([Vector3(s * 0.235, 0.17, k * 0.17), Vector3(s * 0.235, 0.24, k * 0.17), Vector3(s * 0.2, 0.24, k * 0.17)], 0.008, 8), RP)
	# Manipulator claws under the cab.
	for s: float in [1.0, -1.0]:
		var arm := _p(cab, "Claw", Vector3(s * 0.08, -0.2, -0.12), Vector3(-20, 0, 0))
		_add(arm, SmoothKit.rounded_box(Vector3(0.04, 0.12, 0.04), 0.01), OL2, Vector3(0, -0.06, 0))
		for k: float in [-1.0, 1.0]:
			_add(arm, SmoothKit.loft([{"y": -0.06, "w": 0.006, "d": 0.008}, {"y": 0.0, "w": 0.012, "d": 0.014}], 6), DK, Vector3(k * 0.012, -0.12, 0), Vector3(0, 0, k * 25))
	# Weapon mounts: under the cab's front corners and on top.
	m.slots["hand_r"] = _p(cab, "Slot_hand_r", Vector3(0.26, -0.06, -0.1), Vector3.ZERO)
	m.slots["hand_l"] = _p(cab, "Slot_hand_l", Vector3(-0.26, -0.06, -0.1), Vector3.ZERO)
	m.slots["forearm_r"] = m.slots["hand_r"]
	m.slots["forearm_l"] = m.slots["hand_l"]
	m.slots["shoulder_r"] = _p(t, "Slot_shoulder_r", Vector3(0.12, 0.17, 0.05))
	m.slots["shoulder_l"] = _p(t, "Slot_shoulder_l", Vector3(-0.12, 0.17, 0.05))
	m.slots["back_r"] = _p(t, "Slot_back_r", Vector3(0.12, 0.17, 0.5))
	m.slots["back_l"] = _p(t, "Slot_back_l", Vector3(-0.12, 0.17, 0.5))
	# Four legs: front pair reaching forward, rear pair trailing back.
	# Order: front-right, front-left, rear-right, rear-left (diagonal pairs 0+3 and 1+2).
	var corners := [[1.0, -0.3, true], [-1.0, -0.3, true], [1.0, 0.48, false], [-1.0, 0.48, false]]
	for c: Array in corners:
		var s: float = c[0]
		var front: bool = c[2]
		var leg := _rig_leg("r" if s > 0 else "l", Vector3(s * 0.25, -0.1, c[1]), 0.24, 0.5)
		var hip: Node3D = leg["hip"]
		var knee: Node3D = leg["knee"]
		var ankle: Node3D = leg["ankle"]
		var base := Vector3(70, -95, 25) if front else Vector3(-62, 80, -18)
		hip.rotation_degrees = Vector3(base.x, 0, s * 28)
		knee.rotation_degrees.z = s * -26
		knee.rotation_degrees.x = base.y
		ankle.rotation_degrees.x = base.z
		leg["base"] = base
		_add(hip, MeshKit.cylinder(0.05, 0.08, 16), DK, Vector3.ZERO, Vector3(0, 0, 90))
		_add(hip, SmoothKit.rounded_box(Vector3(0.12, 0.28, 0.13), 0.025), OL, Vector3(0, -0.12, 0))
		_add(hip, SmoothKit.rounded_box(Vector3(0.105, 0.05, 0.1), 0.012), OL2, Vector3(0, -0.24, 0.0))
		_add(hip, MeshKit.cylinder(0.012, 0.02, 10), DK, Vector3(0, -0.15, -0.062), Vector3(90, 0, 0))
		_add(knee, MeshKit.cylinder(0.045, 0.09, 16), DK, Vector3.ZERO, Vector3(0, 0, 90))
		# Ribbed, wrapped lower leg.
		var secs: Array = []
		for k in range(18):
			var y := -k * 0.0295
			var r := (0.15 if k % 2 == 0 else 0.13) - k * 0.0025
			secs.append({"y": y, "w": r, "d": r})
		var rev: Array = secs.duplicate()
		rev.reverse()
		_add(knee, SmoothKit.loft(rev, 14), WR)
		for k in range(4):
			_add(knee, MeshKit.cylinder(0.064, 0.012, 14), DK, Vector3(0, -0.36 - k * 0.022, 0))
		_add(ankle, MeshKit.cylinder(0.034, 0.05, 14), DK, Vector3(0, -0.02, 0))
		_add(ankle, MeshKit.cylinder(0.055, 0.025, 18), DK, Vector3(0, -0.05, 0))


# --- Nelson (IPS-N) ------------------------------------------------------------------------
# From the core book art: a knightly brawler in worn brown armor. A rounded helm split red
# and white with a dark T visor, set low and forward between the shoulders; a barrel chest
# with a red/white heater shield and a round target badge; a red tabard with a gold crest
# hanging to the knees and a long red cape; one huge boxy armored arm (left), one lighter arm
# gripping the war pike; long legs with big knee guards and wrapped boots.

func _nelson() -> void:
	m.set_meta("custom_pose", true)
	var BR := MeshKit.paint(Color(0.45, 0.32, 0.26), 0.3, 0.6, 0.2)
	var BR2 := MeshKit.paint(Color(0.55, 0.4, 0.33), 0.3, 0.55, 0.12)
	var SL := MeshKit.paint(Color(0.24, 0.3, 0.33), 0.6, 0.45, 0.1)
	var DK := MeshKit.paint(Color(0.12, 0.11, 0.11), 0.6, 0.5, 0.0)
	var RD := MeshKit.paint(Color(0.68, 0.15, 0.12), 0.15, 0.6, 0.0)
	var WH := MeshKit.paint(Color(0.86, 0.82, 0.76), 0.2, 0.5, 0.0)
	var GOLD := MeshKit.paint(Color(0.85, 0.65, 0.3), 0.8, 0.35, 0.0)
	var EYE := MeshKit.paint(Color(0.3, 0.25, 0.05), 0.2, 0.2, 0.0, Color(1.0, 0.85, 0.3))
	var cloth := ShaderMaterial.new()
	cloth.shader = CLOTH_SHADER
	cloth.set_shader_parameter("color", Color(0.62, 0.12, 0.1, 1.0))
	cloth.set_shader_parameter("tip_color", Color(0.5, 0.1, 0.08, 1.0))
	cloth.set_shader_parameter("wave", 0.03)
	var hip_y := 0.4
	var torso_origin := Vector3(0, hip_y + 0.04, 0)
	var B := func(v: Vector3) -> Vector3: return Basis(Vector3.RIGHT, deg_to_rad(30.0)) * (v - torso_origin)
	m.pelvis = _p(body, "Pelvis", Vector3(0, hip_y, 0))
	m.pelvis.set_meta("rest_y", hip_y)
	_add(m.pelvis, SmoothKit.rounded_box(Vector3(0.22, 0.08, 0.14), 0.025), SL)
	for s: float in [1.0, -1.0]:
		var side := "r" if s > 0 else "l"
		var leg := _rig_leg(side, Vector3(s * 0.11, -0.01, 0), 0.21, 0.22)
		var hip: Node3D = leg["hip"]
		var knee: Node3D = leg["knee"]
		var ankle: Node3D = leg["ankle"]
		hip.rotation_degrees = Vector3(-22, 0, s * 18)
		knee.rotation_degrees = Vector3(38, 0, s * -12)
		ankle.rotation_degrees = Vector3(-16, 0, s * -6)
		leg["base"] = Vector3(-22, 38, -16)
		_add(hip, SmoothKit.blob(Vector3(0.08, 0.08, 0.08), 1.0, 1.0), DK)
		_add(hip, _limb(0.2, 0.055, 0.047, 0.15), BR)
		_add(hip, SmoothKit.rounded_box(Vector3(0.06, 0.12, 0.02), 0.008), SL, Vector3(s * 0.01, -0.09, -0.05))
		# Big rounded knee guard.
		_add(knee, SmoothKit.blob(Vector3(0.1, 0.09, 0.08), 0.6, 0.7), BR2, Vector3(0, 0.0, -0.035))
		_add(knee, SmoothKit.blob(Vector3(0.08, 0.04, 0.05), 0.5, 0.6), WH, Vector3(0, 0.03, -0.065), Vector3(-30, 0, 0))
		_add(knee, _limb(0.21, 0.045, 0.055, 0.1), BR)
		for k in range(4):
			_add(knee, MeshKit.cylinder(0.058 - k * 0.002, 0.014, 14), DK, Vector3(0, -0.11 - k * 0.025, 0))
		_add(ankle, SmoothKit.rounded_box(Vector3(0.1, 0.06, 0.17), 0.025), BR, Vector3(0, -0.03, -0.035))
		_add(ankle, SmoothKit.rounded_box(Vector3(0.11, 0.03, 0.18), 0.012), DK, Vector3(0, -0.058, -0.035))
		_add(ankle, SmoothKit.rounded_box(Vector3(0.08, 0.05, 0.05), 0.012), BR2, Vector3(0, 0.0, 0.03))
	# Torso: barrel chest leaning forward, with a backpack and a pole socket on top.
	m.torso = _p(m.pelvis, "Torso", Vector3(0, 0.04, 0), Vector3(-30, 0, 0))
	_add(m.torso, MeshKit.cylinder(0.06, 0.08, 14), DK, Vector3(0, 0.03, 0))
	_add(m.torso, SmoothKit.loft([
		{"y": 0.05, "w": 0.18, "d": 0.15, "n": 2.5},
		{"y": 0.14, "w": 0.27, "d": 0.21, "n": 2.6},
		{"y": 0.26, "w": 0.33, "d": 0.25, "n": 2.7},
		{"y": 0.35, "w": 0.32, "d": 0.25, "n": 2.6},
		{"y": 0.41, "w": 0.22, "d": 0.2, "n": 2.4},
	], 28), BR)
	_add(m.torso, SmoothKit.rounded_box(Vector3(0.24, 0.24, 0.13), 0.04), BR2, Vector3(0, 0.3, 0.12))
	_add(m.torso, SmoothKit.rounded_box(Vector3(0.14, 0.02, 0.06), 0.006), SL, Vector3(0, 0.43, 0.12))
	# Chest: heater shield (red/white quartered), round target, pouches, harness straps.
	var shield := _p(m.torso, "Badge", Vector3(0.07, 0.27, -0.128), Vector3(-10, 10, 0))
	_add(shield, SmoothKit.loft([{"y": -0.05, "w": 0.008, "d": 0.008}, {"y": -0.01, "w": 0.06, "d": 0.01}, {"y": 0.03, "w": 0.06, "d": 0.01}], 4), RD, Vector3.ZERO, Vector3(0, 45, 0))
	_add(shield, SmoothKit.rounded_box(Vector3(0.025, 0.035, 0.012), 0.004), WH, Vector3(-0.012, 0.012, -0.004))
	_add(m.torso, MeshKit.cylinder(0.03, 0.01, 18), RD, Vector3(-0.08, 0.26, -0.128), Vector3(-80, -10, 0))
	_add(m.torso, MeshKit.cylinder(0.02, 0.012, 4), WH, Vector3(-0.08, 0.26, -0.13), Vector3(-80, -10, 0))
	_add(m.torso, SmoothKit.rounded_box(Vector3(0.12, 0.06, 0.04), 0.01), SL, Vector3(0, 0.17, -0.12))
	for s: float in [1.0, -1.0]:
		_add(m.torso, SmoothKit.tube([Vector3(s * 0.04, 0.33, -0.11), Vector3(s * 0.05, 0.22, -0.13), Vector3(s * 0.06, 0.1, -0.11)], 0.006, 6), GOLD)
	# Tabard: a red cloth panel hanging from the chest to the knees, with a gold crest.
	var tabard := _p(m.torso, "Tabard", Vector3(0, 0.16, -0.12))
	var tpts: Array = []
	var tw: Array = []
	for k in range(9):
		var f := k / 8.0
		tpts.append(Vector3(0, -f * 0.36, -0.01 - f * 0.08))
		tw.append(0.16 + 0.02 * f)
	var tab := _add(tabard, ribbon(tpts, tw), cloth)
	tab.set_meta("no_height", true)
	var crest := Label3D.new()
	crest.text = "✠"
	crest.font_size = 96
	crest.pixel_size = 0.0007
	crest.modulate = Color(0.9, 0.7, 0.35)
	crest.position = Vector3(0, -0.2, -0.07)
	crest.rotation_degrees = Vector3(-15, 180, 0)
	tabard.add_child(crest)
	# Helm: rounded, split red/white, dark T visor, set low and forward.
	m.head = _p(m.torso, "Head", Vector3(0, 0.3, -0.14), Vector3(24, 0, 0))
	_add(m.head, SmoothKit.blob(Vector3(0.05, 0.06, 0.05), 1.0, 1.0), DK)
	var helm := SmoothKit.loft([
		{"y": 0.0, "w": 0.1, "d": 0.11, "n": 2.2},
		{"y": 0.06, "w": 0.12, "d": 0.13, "n": 2.3},
		{"y": 0.12, "w": 0.11, "d": 0.12, "n": 2.2},
		{"y": 0.16, "w": 0.06, "d": 0.08, "n": 2.0},
	], 20)
	_add(m.head, helm, RD, Vector3(0, 0.02, 0))
	# White right half: a plate over that side of the helm.
	_add(m.head, SmoothKit.blob(Vector3(0.062, 0.15, 0.125), 0.5, 0.9, 1.0, 16), WH, Vector3(0.03, 0.09, 0.0))
	_add(m.head, SmoothKit.rounded_box(Vector3(0.06, 0.012, 0.01), 0.003), DK, Vector3(0, 0.1, -0.064))
	_add(m.head, SmoothKit.rounded_box(Vector3(0.014, 0.06, 0.01), 0.003), DK, Vector3(0, 0.075, -0.064))
	_add(m.head, MeshKit.sphere(0.006, 8), EYE, Vector3(0.016, 0.1, -0.07))
	_eye(m.head, Vector3(0, 0.1, -0.07))
	# Cape: red cloth from the shoulders streaming back and to the right.
	for i in range(7):
		var u := float(i) / 6.0 - 0.5
		var pts: Array = []
		var ws: Array = []
		var start := Vector3(u * 0.34, 0.38, 0.06)
		for k in range(10):
			var f := k / 9.0
			pts.append(start + Vector3(u * f * 0.2 - f * f * 0.22, -f * 0.55 + f * f * 0.12, 0.08 + f * 0.25))
			ws.append(0.08 + 0.04 * sin(f * PI))
		var cape := _add(m.torso, ribbon(pts, ws), cloth)
		cape.set_meta("no_height", true)
	# Arms: the left is huge and boxy, the right lighter and holding the pike.
	var arm_r := _rig_arm("r", Vector3.ZERO, 0.2, 0.2, 0.0, 0.05)
	var arm_l := _rig_arm("l", Vector3.ZERO, 0.18, 0.2, 0.0, 0.07)
	_pose_arm(arm_r, B.call(Vector3(0.22, 0.74, -0.12)), B.call(Vector3(0.32, 0.56, -0.12)), B.call(Vector3(0.36, 0.38, -0.16)), Vector3(0.5, -0.7, -0.4))
	_pose_arm(arm_l, B.call(Vector3(-0.23, 0.74, -0.12)), B.call(Vector3(-0.36, 0.6, -0.26)), B.call(Vector3(-0.31, 0.46, -0.33)), Vector3(0, -1, -0.2))
	_add(arm_r["shoulder"], SmoothKit.blob(Vector3(0.11, 0.1, 0.11), 0.7, 0.7), BR2)
	_add(arm_r["shoulder"], _limb(0.19, 0.035, 0.032), SL)
	_add(arm_r["elbow"], SmoothKit.blob(Vector3(0.05, 0.05, 0.05), 1.0, 1.0), DK)
	_add(arm_r["elbow"], _limb(0.19, 0.04, 0.042, 0.2), BR)
	_add(arm_r["hand"], SmoothKit.rounded_box(Vector3(0.05, 0.06, 0.05), 0.012), BR2)
	# Big left arm: a boxy pauldron and a heavy gauntlet with a cylinder bracer.
	_add(arm_l["shoulder"], SmoothKit.rounded_box(Vector3(0.17, 0.15, 0.17), 0.03), BR, Vector3(-0.02, -0.02, 0))
	_add(arm_l["shoulder"], SmoothKit.rounded_box(Vector3(0.12, 0.03, 0.18), 0.01), SL, Vector3(-0.03, 0.04, 0))
	_add(arm_l["shoulder"], _limb(0.18, 0.05, 0.05), SL)
	_add(arm_l["elbow"], SmoothKit.blob(Vector3(0.08, 0.08, 0.08), 1.0, 1.0), DK)
	_add(arm_l["elbow"], SmoothKit.rounded_box(Vector3(0.12, 0.18, 0.12), 0.025), BR2, Vector3(0, -0.1, 0))
	_add(arm_l["elbow"], MeshKit.cylinder(0.02, 0.08, 12), SL, Vector3(-0.07, -0.08, 0), Vector3(0, 0, 0))
	_add(arm_l["elbow"], MeshKit.sphere(0.012, 8), RD, Vector3(-0.065, -0.14, -0.04))
	_add(arm_l["hand"], SmoothKit.rounded_box(Vector3(0.1, 0.07, 0.09), 0.018), SL, Vector3(0, -0.02, 0))
	for k in range(4):
		_add(arm_l["hand"], SmoothKit.rounded_box(Vector3(0.022, 0.06, 0.022), 0.006), BR2, Vector3((k - 1.5) * 0.024, -0.08, -0.02), Vector3(-25, 0, 0))
	for s: float in [1.0, -1.0]:
		var side := "r" if s > 0 else "l"
		m.slots["shoulder_" + side] = _p(m.torso, "Slot_shoulder_" + side, Vector3(s * 0.2, 0.42, 0.04))
		m.slots["back_" + side] = _p(m.torso, "Slot_back_" + side, Vector3(s * 0.08, 0.44, 0.14))


## Common biped scaffold for sculpted frames: pelvis, two legs and a torso. Returns the
## leg dictionaries. `stance` = [hip_x, hip_z_out, knee_x, ankle_x] degrees.
func _biped(hip_y: float, hip_w: float, thigh: float, shin: float, stance: Array, lean: float) -> Array:
	m.pelvis = _p(body, "Pelvis", Vector3(0, hip_y, 0))
	m.pelvis.set_meta("rest_y", hip_y)
	var legs: Array = []
	for s: float in [1.0, -1.0]:
		var leg := _rig_leg("r" if s > 0 else "l", Vector3(s * hip_w, -0.01, 0), thigh, shin)
		(leg["hip"] as Node3D).rotation_degrees = Vector3(stance[0], 0, s * stance[1])
		(leg["knee"] as Node3D).rotation_degrees = Vector3(stance[2], 0, s * -stance[1] * 0.6)
		(leg["ankle"] as Node3D).rotation_degrees = Vector3(stance[3], 0, s * -stance[1] * 0.4)
		leg["base"] = Vector3(stance[0], stance[2], stance[3])
		leg["s"] = s
		legs.append(leg)
	m.torso = _p(m.pelvis, "Torso", Vector3(0, 0.04, 0), Vector3(-lean, 0, 0))
	return legs


func _slots(shoulder_y: float, x: float, back_z: float) -> void:
	for s: float in [1.0, -1.0]:
		var side := "r" if s > 0 else "l"
		if not m.slots.has("shoulder_" + side):
			m.slots["shoulder_" + side] = _p(m.torso, "Slot_shoulder_" + side, Vector3(s * x, shoulder_y, 0.02))
		if not m.slots.has("back_" + side):
			m.slots["back_" + side] = _p(m.torso, "Slot_back_" + side, Vector3(s * x * 0.5, shoulder_y, back_z))


# --- Raleigh (IPS-N) -------------------------------------------------------------------------
# From the core book art: a rust-red gunslinger. A wide flat disc "hat" over a small sensor
# head; big drum-shaped shoulders lying sideways with round vents at their ends; a rounded
# chest with a recessed lens; a ribbed slate belly and a blue belt; long arms with round
# elbow and wrist pods; long legs with round knee pods, wrapped shins and chunky boots with
# slate toe caps; a ragged brown poncho over one shoulder. Revolver in the right hand.

func _raleigh() -> void:
	m.set_meta("custom_pose", true)
	var RR := MeshKit.paint(Color(0.55, 0.24, 0.19), 0.3, 0.55, 0.2)
	var RR2 := MeshKit.paint(Color(0.62, 0.3, 0.25), 0.3, 0.5, 0.1)
	var SL := MeshKit.paint(Color(0.2, 0.33, 0.38), 0.55, 0.45, 0.15)
	var BL := MeshKit.paint(Color(0.15, 0.32, 0.5), 0.4, 0.45, 0.0)
	var DK := MeshKit.paint(Color(0.12, 0.12, 0.13), 0.6, 0.5, 0.0)
	var WRAP := MeshKit.paint(Color(0.6, 0.48, 0.38), 0.05, 0.85, 0.0)
	var EYE := MeshKit.paint(Color(0.3, 0.1, 0.05), 0.2, 0.2, 0.0, Color(1.0, 0.45, 0.2))
	var cloth := ShaderMaterial.new()
	cloth.shader = CLOTH_SHADER
	cloth.set_shader_parameter("color", Color(0.45, 0.33, 0.25, 1.0))
	cloth.set_shader_parameter("tip_color", Color(0.4, 0.29, 0.22, 1.0))
	cloth.set_shader_parameter("wave", 0.02)
	var legs := _biped(0.47, 0.1, 0.22, 0.23, [-6, 8, 14, -8], 10)
	for leg: Dictionary in legs:
		var s: float = leg["s"]
		_add(leg["hip"], SmoothKit.blob(Vector3(0.07, 0.07, 0.07), 1.0, 1.0), DK)
		_add(leg["hip"], SmoothKit.rounded_box(Vector3(0.085, 0.2, 0.1), 0.025), RR, Vector3(0, -0.1, 0))
		_add(leg["hip"], SmoothKit.rounded_box(Vector3(0.04, 0.15, 0.03), 0.01), SL, Vector3(s * 0.02, -0.11, -0.05))
		_add(leg["knee"], MeshKit.cylinder(0.05, 0.1, 18), RR2, Vector3.ZERO, Vector3(0, 0, 90))
		_add(leg["knee"], MeshKit.cylinder(0.03, 0.104, 14), DK, Vector3.ZERO, Vector3(0, 0, 90))
		_add(leg["knee"], _limb(0.22, 0.045, 0.05, 0.1), RR)
		for k in range(5):
			_add(leg["knee"], MeshKit.cylinder(0.053, 0.012, 14), WRAP, Vector3(0, -0.04 - k * 0.022, 0), Vector3(k * 4.0 - 8.0, 0, 0))
		_add(leg["ankle"], SmoothKit.rounded_box(Vector3(0.11, 0.07, 0.19), 0.03), RR, Vector3(0, -0.03, -0.04))
		_add(leg["ankle"], SmoothKit.blob(Vector3(0.1, 0.05, 0.07), 0.6, 0.7), SL, Vector3(0, -0.04, -0.12))
		_add(leg["ankle"], MeshKit.cylinder(0.03, 0.12, 14), RR2, Vector3(0, 0.0, 0.02), Vector3(0, 0, 90))
	var t := m.torso
	_add(t, MeshKit.cylinder(0.08, 0.04, 18), BL, Vector3(0, 0.0, 0))
	for k in range(4):
		_add(t, SmoothKit.blob(Vector3(0.17 + k * 0.012, 0.035, 0.14), 0.4, 0.6), SL, Vector3(0, 0.04 + k * 0.032, -0.005))
	_add(t, SmoothKit.loft([
		{"y": 0.15, "w": 0.2, "d": 0.17, "n": 2.1},
		{"y": 0.24, "w": 0.26, "d": 0.22, "n": 2.1},
		{"y": 0.33, "w": 0.27, "d": 0.23, "n": 2.1},
		{"y": 0.4, "w": 0.18, "d": 0.16, "n": 2.0},
	], 26), RR)
	_add(t, SmoothKit.blob(Vector3(0.1, 0.09, 0.05), 0.7, 0.7), SL, Vector3(0, 0.25, -0.11))
	_add(t, MeshKit.cylinder(0.024, 0.03, 16), DK, Vector3(0, 0.25, -0.135), Vector3(90, 0, 0))
	_add(t, MeshKit.cylinder(0.012, 0.032, 12), EYE, Vector3(0, 0.25, -0.14), Vector3(90, 0, 0))
	_add(t, MeshKit.cylinder(0.014, 0.01, 12), EYE, Vector3(-0.09, 0.33, -0.1), Vector3(70, 0, 0))
	# Head: small sensor block under a wide flat disc.
	m.head = _p(t, "Head", Vector3(0, 0.4, -0.02), Vector3(-8, 0, 6))
	_add(m.head, SmoothKit.rounded_box(Vector3(0.08, 0.06, 0.07), 0.015), RR2, Vector3(0, 0.03, 0))
	_add(m.head, SmoothKit.lathe([Vector2(0.17, 0.065), Vector2(0.175, 0.072), Vector2(0.06, 0.09), Vector2(0.03, 0.095)], 32), RR)
	_add(m.head, MeshKit.cylinder(0.012, 0.01, 12), EYE, Vector3(0.0, 0.06, -0.15), Vector3(80, 0, 0))
	_eye(m.head, Vector3(0, 0.03, -0.04))
	# Drum shoulders lying sideways, vents on the outer ends.
	for s: float in [1.0, -1.0]:
		var drum := _p(t, "Pad_" + ("r" if s > 0 else "l"), Vector3(s * 0.19, 0.36, 0.0), Vector3(0, s * 12, 0))
		_add(drum, SmoothKit.loft([{"y": -0.09, "w": 0.12, "d": 0.12, "n": 2.2}, {"y": 0.0, "w": 0.14, "d": 0.14, "n": 2.2}, {"y": 0.09, "w": 0.12, "d": 0.12, "n": 2.2}], 22), RR, Vector3.ZERO, Vector3(0, 0, 90))
		_add(drum, _torus(0.045, 0.012), SL, Vector3(s * 0.09, 0, 0), Vector3(0, 0, 90))
		_add(drum, MeshKit.cylinder(0.035, 0.01, 16), DK, Vector3(s * 0.088, 0, 0), Vector3(0, 0, 90))
		_add(drum, SmoothKit.rounded_box(Vector3(0.12, 0.05, 0.02), 0.008), SL, Vector3(0, -0.03, -0.085))
	# Poncho over the left shoulder, hanging down the back.
	for i in range(6):
		var u := float(i) / 5.0
		var pts: Array = []
		var ws: Array = []
		var start := Vector3(-0.08 - u * 0.2, 0.42, 0.02 + u * 0.05)
		for k in range(8):
			var f := k / 7.0
			pts.append(start + Vector3(-f * 0.08, -f * 0.5, 0.1 + f * 0.1))
			ws.append(0.08 * (1.0 - 0.3 * f))
		var pc := _add(t, ribbon(pts, ws), cloth)
		pc.set_meta("no_height", true)
	# Long arms with round pods; revolver in the right hand.
	var arm_r := _rig_arm("r", Vector3.ZERO, 0.21, 0.21, 0.0, 0.04)
	var arm_l := _rig_arm("l", Vector3.ZERO, 0.21, 0.21, 0.0, 0.04)
	_pose_arm(arm_r, Vector3(0.24, 0.3, -0.02), Vector3(0.32, 0.1, -0.04), Vector3(0.33, -0.1, -0.08), Vector3(0.0, -0.6, -1.0))
	_pose_arm(arm_l, Vector3(-0.24, 0.3, -0.02), Vector3(-0.31, 0.1, -0.02), Vector3(-0.28, -0.1, -0.06), Vector3(0.0, -1.0, -0.3))
	for arm: Dictionary in [arm_r, arm_l]:
		_add(arm["shoulder"], MeshKit.cylinder(0.04, 0.09, 16), DK, Vector3.ZERO, Vector3(0, 0, 90))
		_add(arm["shoulder"], _limb(0.2, 0.038, 0.035, 0.1), RR)
		_add(arm["elbow"], MeshKit.cylinder(0.042, 0.085, 16), RR2, Vector3.ZERO, Vector3(0, 0, 90))
		_add(arm["elbow"], _limb(0.2, 0.04, 0.045, 0.15), RR)
		_add(arm["elbow"], MeshKit.cylinder(0.046, 0.03, 16), BL, Vector3(0, -0.17, 0))
		_add(arm["hand"], SmoothKit.rounded_box(Vector3(0.06, 0.07, 0.06), 0.015), RR2)
	_slots(0.42, 0.2, 0.12)


# --- Tortuga (IPS-N) -------------------------------------------------------------------------
# From the core book art: a hulking slab of dark slate armor. The torso is a huge rounded box
# hunched forward with a red domed hatch (sensor) set into its front-top; a tall boxy
# shoulder block on the right carrying cable reels lashed with rope; stacked rectangular
# shield plates on the left side; short thick legs with big rounded boots; arms tucked in,
# holding a long rifle across the body.

func _tortuga() -> void:
	m.set_meta("custom_pose", true)
	var SL := MeshKit.paint(Color(0.24, 0.27, 0.28), 0.45, 0.5, 0.25)
	var SL2 := MeshKit.paint(Color(0.3, 0.34, 0.35), 0.45, 0.5, 0.15)
	var DK := MeshKit.paint(Color(0.1, 0.1, 0.11), 0.6, 0.5, 0.0)
	var BRN := MeshKit.paint(Color(0.3, 0.2, 0.15), 0.1, 0.8, 0.0)
	var RED := MeshKit.paint(Color(0.62, 0.1, 0.08), 0.3, 0.4, 0.0)
	var ROPE := MeshKit.paint(Color(0.55, 0.42, 0.3), 0.0, 0.9, 0.0)
	var AMB := MeshKit.paint(Color(0.4, 0.2, 0.0), 0.2, 0.2, 0.0, Color(1.0, 0.6, 0.15))
	var legs := _biped(0.3, 0.12, 0.14, 0.15, [-10, 8, 22, -12], 32)
	for leg: Dictionary in legs:
		var s: float = leg["s"]
		_add(leg["hip"], SmoothKit.rounded_box(Vector3(0.13, 0.17, 0.15), 0.03), SL, Vector3(0, -0.07, 0))
		_add(leg["knee"], SmoothKit.blob(Vector3(0.11, 0.09, 0.1), 0.7, 0.7), SL2, Vector3(0, 0, -0.03))
		_add(leg["knee"], SmoothKit.rounded_box(Vector3(0.12, 0.16, 0.14), 0.03), SL, Vector3(0, -0.08, 0))
		_add(leg["knee"], SmoothKit.rounded_box(Vector3(0.05, 0.06, 0.02), 0.008), DK, Vector3(0, -0.07, -0.072))
		_add(leg["ankle"], SmoothKit.blob(Vector3(0.17, 0.09, 0.26), 0.55, 0.65, 0.0), SL, Vector3(0, -0.05, -0.05))
		_add(leg["ankle"], SmoothKit.rounded_box(Vector3(0.08, 0.02, 0.04), 0.006), DK, Vector3(0, -0.02, -0.16))
	var t := m.torso
	# Huge rounded torso box, hunched forward.
	_add(t, SmoothKit.rounded_box(Vector3(0.44, 0.46, 0.4), 0.1), SL, Vector3(0, 0.26, -0.02))
	_add(t, SmoothKit.blob(Vector3(0.4, 0.2, 0.36), 0.7, 0.6, 0.0), SL2, Vector3(0, 0.46, -0.02))
	_add(t, SmoothKit.rounded_box(Vector3(0.36, 0.14, 0.12), 0.03), BRN, Vector3(0, 0.07, -0.18))
	_add(t, SmoothKit.rounded_box(Vector3(0.3, 0.1, 0.03), 0.02), SL2, Vector3(0, 0.36, -0.23), Vector3(-15, 0, 0))
	# Red domed hatch with an amber lens.
	m.head = _p(t, "Head", Vector3(-0.06, 0.48, -0.12), Vector3(-10, 0, 0))
	_add(m.head, MeshKit.cylinder(0.09, 0.03, 24), DK)
	_add(m.head, SmoothKit.blob(Vector3(0.16, 0.08, 0.16), 0.7, 0.8, 0.0, 20), RED, Vector3(0, 0.01, 0))
	_add(m.head, MeshKit.sphere(0.012, 8), AMB, Vector3(0, 0.05, -0.04))
	_eye(m.head, Vector3(0, 0.05, -0.06))
	for p: Vector3 in [Vector3(-0.17, 0.28, -0.232), Vector3(0.05, 0.2, -0.232)]:
		_add(t, SmoothKit.rounded_box(Vector3(0.04, 0.025, 0.01), 0.004), AMB, p)
	_add(t, SmoothKit.rounded_box(Vector3(0.08, 0.04, 0.02), 0.008), DK, Vector3(-0.08, 0.12, -0.24))
	# Right shoulder: a tall box with cable reels lashed with rope.
	var box := _p(t, "Pad_l", Vector3(-0.26, 0.3, 0.0))
	_add(box, SmoothKit.rounded_box(Vector3(0.18, 0.32, 0.3), 0.04), SL2)
	for k in range(3):
		var reel := _p(box, "Reel", Vector3(-0.04 + k * 0.06, 0.13, -0.08 + (k % 2) * 0.04))
		_add(reel, MeshKit.cylinder(0.045, 0.04, 20), DK, Vector3.ZERO, Vector3(90, 0, 0))
		_add(reel, MeshKit.cylinder(0.05, 0.008, 20), RED, Vector3(0, 0, -0.02), Vector3(90, 0, 0))
	for k in range(4):
		var y := 0.05 + k * 0.05
		_add(box, SmoothKit.tube([Vector3(-0.09, y, -0.16), Vector3(0.0, y + 0.03, -0.17), Vector3(0.09, y - 0.02, -0.16)], 0.004, 5), ROPE)
	_add(box, MeshKit.cylinder(0.025, 0.02, 14), DK, Vector3(0, -0.02, -0.155), Vector3(90, 0, 0))
	# Ropes trailing off the back.
	for k in range(3):
		var a := Vector3(-0.1, 0.15 - k * 0.04, 0.14)
		_add(box, SmoothKit.tube(SmoothKit.bezier(a, a + Vector3(-0.1, -0.05, 0.05), a + Vector3(-0.2, -0.15, 0.0), a + Vector3(-0.3, -0.25, 0.05), 10), 0.005, 5), ROPE)
	# Left side: stacked rectangular shield plates.
	var shield := _p(t, "Pad_r", Vector3(0.3, 0.24, -0.04), Vector3(0, 0, -8))
	for k in range(2):
		var plate := _p(shield, "Plate", Vector3(0.02 + k * 0.04, 0.12 - k * 0.24, -0.04 * k), Vector3(10 - k * 5, 0, 0))
		_add(plate, SmoothKit.rounded_box(Vector3(0.04, 0.2, 0.28), 0.012), SL2)
		for j in range(3):
			_add(plate, SmoothKit.rounded_box(Vector3(0.046, 0.16, 0.075), 0.01), SL, Vector3(-0.004, 0, -0.09 + j * 0.09))
	# Arms tucked in, holding the rifle across the body.
	var arm_r := _rig_arm("r", Vector3.ZERO, 0.14, 0.15, 0.0, 0.05)
	var arm_l := _rig_arm("l", Vector3.ZERO, 0.14, 0.15, 0.0, 0.05)
	_pose_arm(arm_r, Vector3(0.24, 0.24, -0.04), Vector3(0.2, 0.1, -0.16), Vector3(0.06, 0.05, -0.27), Vector3(-0.9, -0.35, -0.2))
	_pose_arm(arm_l, Vector3(-0.26, 0.24, -0.04), Vector3(-0.22, 0.12, -0.18), Vector3(-0.12, 0.13, -0.3), Vector3(-0.9, -0.35, -0.2))
	for arm: Dictionary in [arm_r, arm_l]:
		_add(arm["shoulder"], SmoothKit.blob(Vector3(0.08, 0.08, 0.08), 1.0, 1.0), DK)
		_add(arm["shoulder"], SmoothKit.rounded_box(Vector3(0.09, 0.15, 0.09), 0.02), SL, Vector3(0, -0.07, 0))
		_add(arm["elbow"], SmoothKit.rounded_box(Vector3(0.1, 0.15, 0.1), 0.02), SL2, Vector3(0, -0.07, 0))
		_add(arm["hand"], SmoothKit.rounded_box(Vector3(0.07, 0.07, 0.07), 0.016), SL)
	_slots(0.45, 0.2, 0.2)


# --- Vlad (IPS-N) ---------------------------------------------------------------------------
# From the core book art: a towering khaki-grey brute studded with bone-white spikes. Huge
# round drum shoulders, a narrow head with an orange-and-white chevron face, a stacked
# segmented torso with a white loin plate, long arms with spiked forearm guards and heavy
# clawed hands, thick legs with spiked plates and big boots. A tall spear in one hand.

func _vlad() -> void:
	m.set_meta("custom_pose", true)
	m.set_meta("melee_hand", "l")
	var KH := MeshKit.paint(Color(0.45, 0.42, 0.35), 0.25, 0.65, 0.2)
	var KH2 := MeshKit.paint(Color(0.52, 0.49, 0.41), 0.25, 0.6, 0.1)
	var BONE := MeshKit.paint(Color(0.88, 0.85, 0.76), 0.1, 0.5, 0.0)
	var DK := MeshKit.paint(Color(0.14, 0.15, 0.17), 0.6, 0.5, 0.0)
	var RUST := MeshKit.paint(Color(0.38, 0.2, 0.14), 0.3, 0.6, 0.0)
	var OR := MeshKit.paint(Color(0.88, 0.55, 0.12), 0.2, 0.45, 0.0)
	var GL := MeshKit.paint(Color(0.2, 0.3, 0.2), 0.2, 0.2, 0.0, Color(0.5, 1.0, 0.6))
	var spike := func(parent: Node3D, pos: Vector3, dir: Vector3, length: float) -> void:
		var sp := MeshKit.part(parent, MeshKit.cylinder(length * 0.13, length, 7, 0.0), BONE, pos + dir.normalized() * length * 0.5)
		sp.basis = basis_down(-dir)
	var legs := _biped(0.44, 0.13, 0.2, 0.22, [-4, 6, 10, -6], 4)
	for leg: Dictionary in legs:
		var s: float = leg["s"]
		_add(leg["hip"], SmoothKit.blob(Vector3(0.08, 0.08, 0.08), 1.0, 1.0), DK)
		_add(leg["hip"], SmoothKit.loft([{"y": -0.2, "w": 0.13, "d": 0.14, "n": 2.6}, {"y": -0.1, "w": 0.15, "d": 0.15, "n": 2.6}, {"y": 0.0, "w": 0.12, "d": 0.13, "n": 2.6}], 18), KH)
		for k in range(3):
			spike.call(leg["hip"], Vector3(s * 0.07, -0.05 - k * 0.05, -0.02), Vector3(s, 0.3, -0.2), 0.06)
		_add(leg["knee"], MeshKit.cylinder(0.055, 0.12, 18), KH2, Vector3.ZERO, Vector3(0, 0, 90))
		_add(leg["knee"], MeshKit.cylinder(0.025, 0.124, 12), DK, Vector3.ZERO, Vector3(0, 0, 90))
		_add(leg["knee"], SmoothKit.loft([{"y": -0.22, "w": 0.13, "d": 0.14, "n": 2.6}, {"y": -0.1, "w": 0.15, "d": 0.15, "n": 2.6}, {"y": -0.02, "w": 0.12, "d": 0.12, "n": 2.6}], 18), KH)
		for k in range(4):
			_add(leg["knee"], SmoothKit.rounded_box(Vector3(0.012, 0.12, 0.01), 0.004), BONE, Vector3((k - 1.5) * 0.028, -0.12, -0.077))
		spike.call(leg["knee"], Vector3(s * 0.06, 0.0, -0.03), Vector3(s, 0.4, -0.3), 0.08)
		_add(leg["ankle"], SmoothKit.rounded_box(Vector3(0.15, 0.08, 0.24), 0.035), KH, Vector3(0, -0.035, -0.05))
		for k in range(3):
			_add(leg["ankle"], SmoothKit.rounded_box(Vector3(0.012, 0.03, 0.08), 0.004), BONE, Vector3((k - 1) * 0.04, -0.0, -0.12), Vector3(-30, 0, 0))
	var t := m.torso
	for k in range(4):
		_add(t, SmoothKit.blob(Vector3(0.22 + k * 0.03, 0.06, 0.18 + k * 0.01), 0.45, 0.6), KH if k % 2 else KH2, Vector3(0, 0.05 + k * 0.055, 0))
		if k > 0:
			for j in range(3):
				spike.call(t, Vector3((j - 1) * 0.06, 0.05 + k * 0.055, -0.1 - k * 0.005), Vector3((j - 1) * 0.2, 0.6, -1), 0.05)
	_add(t, SmoothKit.loft([
		{"y": 0.22, "w": 0.3, "d": 0.22, "n": 2.6},
		{"y": 0.32, "w": 0.34, "d": 0.24, "n": 2.6},
		{"y": 0.4, "w": 0.26, "d": 0.2, "n": 2.4},
	], 24), KH)
	_add(t, SmoothKit.rounded_box(Vector3(0.1, 0.12, 0.03), 0.015), KH2, Vector3(0, 0.33, -0.12))
	_add(t, SmoothKit.rounded_box(Vector3(0.07, 0.015, 0.012), 0.004), DK, Vector3(0, 0.36, -0.137))
	_add(m.pelvis, SmoothKit.rounded_box(Vector3(0.1, 0.12, 0.03), 0.02), BONE, Vector3(0, -0.04, -0.07))
	_add(m.pelvis, SmoothKit.rounded_box(Vector3(0.24, 0.07, 0.15), 0.02), DK, Vector3(0, 0.0, 0))
	# Narrow chevron-faced head.
	m.head = _p(t, "Head", Vector3(0, 0.4, -0.05))
	_add(m.head, SmoothKit.loft([{"y": 0.0, "w": 0.06, "d": 0.08}, {"y": 0.06, "w": 0.07, "d": 0.08}, {"y": 0.11, "w": 0.04, "d": 0.06}, {"y": 0.13, "w": 0.01, "d": 0.03}], 4), BONE, Vector3(0, 0, 0), Vector3(0, 45, 0))
	_add(m.head, SmoothKit.loft([{"y": 0.02, "w": 0.05, "d": 0.01}, {"y": 0.07, "w": 0.06, "d": 0.01}, {"y": 0.12, "w": 0.01, "d": 0.01}], 4), OR, Vector3(0, 0, -0.04), Vector3(0, 45, 0))
	for k in range(3):
		_add(m.head, MeshKit.chamfer_box(Vector3(0.03, 0.005, 0.005), 0.001), DK, Vector3(0, 0.035 + k * 0.015, -0.046), Vector3(0, 0, 0))
	_add(m.head, MeshKit.sphere(0.007, 8), GL, Vector3(0.012, 0.08, -0.045))
	_eye(m.head, Vector3(0, 0.07, -0.05))
	for s: float in [1.0, -1.0]:
		_add(t, SmoothKit.rounded_box(Vector3(0.05, 0.1, 0.06), 0.015), KH2, Vector3(s * 0.07, 0.42, -0.02))
	# Huge drum shoulders with spikes.
	for s: float in [1.0, -1.0]:
		var drum := _p(t, "Pad_" + ("r" if s > 0 else "l"), Vector3(s * 0.28, 0.4, 0.04), Vector3(0, s * -38, 0))
		_add(drum, SmoothKit.loft([{"y": -0.1, "w": 0.26, "d": 0.26, "n": 2.2}, {"y": 0.0, "w": 0.29, "d": 0.29, "n": 2.2}, {"y": 0.09, "w": 0.24, "d": 0.24, "n": 2.2}], 24), KH, Vector3.ZERO, Vector3(-90, 0, 0))
		_add(drum, _torus(0.1, 0.014), RUST, Vector3(0, 0, -0.095), Vector3(90, 0, 0))
		_add(drum, MeshKit.cylinder(0.1, 0.01, 24), KH2, Vector3(0, 0, -0.098), Vector3(90, 0, 0))
		for k in range(7):
			var a := deg_to_rad(-60.0 + k * 30.0)
			var p := Vector3(cos(a) * 0.14 * s, sin(a) * 0.14, -0.02 + (k % 2) * 0.05)
			spike.call(drum, p, Vector3(cos(a) * s, sin(a), -0.3), 0.07)
			_add(drum, SmoothKit.rounded_box(Vector3(0.012, 0.07, 0.012), 0.004), BONE, Vector3(cos(a) * 0.09 * s, sin(a) * 0.09, -0.104), Vector3(0, 0, rad_to_deg(a) * s + 90.0))
	# Long arms with spiked forearm guards and big clawed hands.
	var arm_r := _rig_arm("r", Vector3.ZERO, 0.21, 0.24, 0.0, 0.06)
	var arm_l := _rig_arm("l", Vector3.ZERO, 0.21, 0.24, 0.0, 0.06)
	_pose_arm(arm_r, Vector3(0.3, 0.3, -0.02), Vector3(0.36, 0.1, -0.06), Vector3(0.37, -0.14, -0.04), Vector3(0.0, -1.0, -0.15))
	_pose_arm(arm_l, Vector3(-0.3, 0.3, -0.02), Vector3(-0.38, 0.12, -0.12), Vector3(-0.32, 0.16, -0.26), Vector3(0.0, 1.0, 0.0))
	for arm: Dictionary in [arm_r, arm_l]:
		_add(arm["shoulder"], SmoothKit.blob(Vector3(0.08, 0.08, 0.08), 1.0, 1.0), DK)
		_add(arm["shoulder"], SmoothKit.loft([{"y": -0.2, "w": 0.1, "d": 0.1, "n": 2.6}, {"y": -0.1, "w": 0.12, "d": 0.12, "n": 2.6}, {"y": 0.0, "w": 0.1, "d": 0.1, "n": 2.6}], 16), KH)
		_add(arm["elbow"], MeshKit.cylinder(0.05, 0.11, 16), KH2, Vector3.ZERO, Vector3(0, 0, 90))
		_add(arm["elbow"], SmoothKit.loft([{"y": -0.23, "w": 0.13, "d": 0.12, "n": 2.6}, {"y": -0.12, "w": 0.14, "d": 0.13, "n": 2.6}, {"y": -0.02, "w": 0.1, "d": 0.1, "n": 2.6}], 16), KH)
		for k in range(5):
			_add(arm["elbow"], MeshKit.cylinder(0.072, 0.012, 16), DK, Vector3(0, -0.06 - k * 0.03, 0))
		for k in range(3):
			spike.call(arm["elbow"], Vector3(0.06, -0.06 - k * 0.06, 0.0), Vector3(1, 0.3, 0), 0.06)
		_add(arm["hand"], SmoothKit.rounded_box(Vector3(0.1, 0.09, 0.1), 0.02), KH2)
		for k in range(4):
			var f := _p(arm["hand"], "Claw", Vector3((k - 1.5) * 0.024, -0.05, -0.02), Vector3(-15, 0, 0))
			_add(f, _limb(0.07, 0.012, 0.009), KH)
			_add(f, SmoothKit.loft([{"y": -0.1, "w": 0.003, "d": 0.003}, {"y": -0.07, "w": 0.014, "d": 0.012}], 6, false), BONE)
	_slots(0.48, 0.27, 0.12)


# --- Black Witch (SSC) ------------------------------------------------------------------------
# From the core book art: a slender, elegant figure in dark slate armor over a red ribbed
# body suit. A tall halo ring behind a smooth white egg faceplate; rounded shoulder caps with
# hooked fins and red joint balls; a red domed chest emitter; long pale cloth streamers
# falling from the shoulders; narrow waist, long legs with knee plates and slim clawed feet;
# a red disc on the left forearm. Red magnetic ring weapons.

func _black_witch() -> void:
	m.set_meta("custom_pose", true)
	var SL := MeshKit.paint(Color(0.17, 0.25, 0.3), 0.45, 0.4, 0.2)
	var SL2 := MeshKit.paint(Color(0.22, 0.31, 0.36), 0.45, 0.4, 0.1)
	var RD := MeshKit.paint(Color(0.55, 0.16, 0.14), 0.2, 0.5, 0.15)
	var RD2 := MeshKit.paint(Color(0.72, 0.25, 0.2), 0.25, 0.45, 0.0)
	var WH := MeshKit.paint(Color(0.85, 0.83, 0.76), 0.2, 0.3, 0.0)
	var OR := MeshKit.paint(Color(0.4, 0.15, 0.02), 0.2, 0.3, 0.0, Color(1.0, 0.55, 0.2))
	var cloth := ShaderMaterial.new()
	cloth.shader = CLOTH_SHADER
	cloth.set_shader_parameter("color", Color(0.78, 0.8, 0.78, 0.92))
	cloth.set_shader_parameter("tip_color", Color(0.55, 0.6, 0.6, 0.75))
	cloth.set_shader_parameter("wave", 0.025)
	var legs := _biped(0.5, 0.075, 0.23, 0.25, [-4, 4, 8, -4], -2)
	for leg: Dictionary in legs:
		var s: float = leg["s"]
		_add(leg["hip"], SmoothKit.blob(Vector3(0.07, 0.07, 0.07), 1.0, 1.0), RD)
		_add(leg["hip"], _limb(0.22, 0.05, 0.038, 0.2), SL)
		_add(leg["hip"], SmoothKit.rounded_box(Vector3(0.07, 0.03, 0.08), 0.01), SL2, Vector3(0, -0.04, 0))
		for k in range(2):
			_add(leg["hip"], MeshKit.sphere(0.008, 8), OR, Vector3(s * 0.03, -0.08 - k * 0.05, -0.04))
		_add(leg["knee"], SmoothKit.blob(Vector3(0.07, 0.08, 0.07), 0.6, 0.7), SL2, Vector3(0, 0, -0.02))
		_add(leg["knee"], _limb(0.24, 0.036, 0.026, 0.15), SL)
		_add(leg["knee"], _limb(0.2, 0.015, 0.012), RD, Vector3(0, -0.02, 0.02))
		_add(leg["ankle"], SmoothKit.blob(Vector3(0.05, 0.04, 0.05), 0.8, 0.8), SL2)
		for k in range(3):
			var toe := _p(leg["ankle"], "Toe", Vector3((k - 1) * 0.018, -0.02, -0.01), Vector3(-100, 0, (k - 1) * 14))
			_add(toe, SmoothKit.loft([{"y": 0.0, "w": 0.018, "d": 0.015}, {"y": 0.05, "w": 0.014, "d": 0.012}, {"y": 0.07, "w": 0.005, "d": 0.005}], 8), SL)
	var t := m.torso
	# Narrow red ribbed body suit with straps; wider slate chest shell.
	var secs: Array = []
	for k in range(10):
		var y := k * 0.03
		# Hips flare, waist pinches, chest widens.
		var w := 0.15 - 0.07 * sin(clampf(y / 0.2, 0.0, 1.0) * PI) + 0.06 * clampf((y - 0.12) / 0.15, 0.0, 1.0) + (0.006 if k % 2 == 0 else 0.0)
		secs.append({"y": y, "w": w, "d": w * 0.85})
	_add(t, SmoothKit.loft(secs, 20), RD)
	for k in range(3):
		_add(t, _torus(0.05 + k * 0.006, 0.005), SL2, Vector3(0, 0.1 + k * 0.045, 0), Vector3.ZERO, Vector3(1, 1, 0.85))
	for s: float in [1.0, -1.0]:
		_add(t, SmoothKit.blob(Vector3(0.06, 0.1, 0.11), 0.7, 0.7), SL, Vector3(s * 0.08, 0.0, 0.0))
	_add(t, SmoothKit.loft([
		{"y": 0.24, "w": 0.15, "d": 0.13, "n": 2.0},
		{"y": 0.31, "w": 0.21, "d": 0.17, "n": 2.0},
		{"y": 0.37, "w": 0.21, "d": 0.17, "n": 2.0},
		{"y": 0.41, "w": 0.12, "d": 0.11, "n": 2.0},
	], 24), SL)
	_add(t, SmoothKit.blob(Vector3(0.08, 0.1, 0.05), 0.7, 0.7), RD2, Vector3(0, 0.3, -0.095))
	for p: Vector3 in [Vector3(-0.015, 0.32, -0.12), Vector3(0.015, 0.31, -0.12), Vector3(0, 0.28, -0.118)]:
		_add(t, MeshKit.sphere(0.006, 8), OR, p)
	# Head: white egg faceplate, dark collar, halo ring behind.
	m.head = _p(t, "Head", Vector3(0, 0.41, -0.02))
	_add(m.head, SmoothKit.lathe([Vector2(0.05, 0.0), Vector2(0.06, 0.02)], 16, false), SL2)
	_add(m.head, SmoothKit.blob(Vector3(0.075, 0.12, 0.08), 0.8, 0.8), WH, Vector3(0, 0.07, -0.01))
	_add(m.head, SmoothKit.rounded_box(Vector3(0.012, 0.09, 0.03), 0.004), RD, Vector3(0.025, 0.08, -0.04))
	_add(m.head, MeshKit.sphere(0.007, 8), OR, Vector3(0, 0.035, -0.045))
	_eye(m.head, Vector3(0, 0.05, -0.05))
	var halo := _p(t, "Halo", Vector3(0, 0.55, 0.04), Vector3(80, 0, 0))
	_add(halo, _torus(0.1, 0.014), SL)
	_add(halo, _torus(0.088, 0.004), RD2)
	m.spinners.append({"node": halo, "axis": Vector3.UP, "speed": 0.0})
	_add(t, MeshKit.cylinder(0.01, 0.12, 8), SL, Vector3(0, 0.47, 0.05), Vector3(10, 0, 0))
	# Shoulder caps with hooked fins and red joint balls; streamers hanging from them.
	for s: float in [1.0, -1.0]:
		var cap := _p(t, "Pad_" + ("r" if s > 0 else "l"), Vector3(s * 0.135, 0.37, 0.0))
		_add(cap, SmoothKit.blob(Vector3(0.1, 0.09, 0.11), 0.75, 0.75), SL)
		_add(cap, SmoothKit.blob(Vector3(0.05, 0.05, 0.05), 1.0, 1.0), RD2, Vector3(s * 0.035, -0.05, -0.03))
		var fin := _p(cap, "Fin", Vector3(s * 0.02, 0.05, 0.0))
		_add(fin, SmoothKit.tube(SmoothKit.bezier(Vector3.ZERO, Vector3(0, 0.07, 0), Vector3(s * 0.05, 0.08, 0), Vector3(s * 0.05, 0.04, 0), 8), 0.009, 6), SL2)
		var pts: Array = []
		var ws: Array = []
		for k in range(10):
			var f := k / 9.0
			pts.append(Vector3(s * (0.035 + f * 0.03), -0.06 - f * 0.62, -0.03 + f * 0.04))
			ws.append(0.05 + 0.04 * f)
		var str_ := _add(cap, ribbon(pts, ws), cloth)
		str_.set_meta("no_height", true)
	# Arms: left forearm with a red disc, both holding ring weapons low.
	var arm_r := _rig_arm("r", Vector3.ZERO, 0.19, 0.2, 0.0, 0.03)
	var arm_l := _rig_arm("l", Vector3.ZERO, 0.19, 0.2, 0.0, 0.03)
	_pose_arm(arm_r, Vector3(0.19, 0.33, -0.01), Vector3(0.26, 0.15, -0.02), Vector3(0.3, -0.03, -0.08), Vector3(0.3, -0.5, -1))
	_pose_arm(arm_l, Vector3(-0.19, 0.33, -0.01), Vector3(-0.29, 0.17, -0.03), Vector3(-0.27, -0.02, -0.06), Vector3(0, -1, -0.2))
	for arm: Dictionary in [arm_r, arm_l]:
		_add(arm["shoulder"], _limb(0.18, 0.032, 0.028, 0.15), RD)
		_add(arm["shoulder"], SmoothKit.rounded_box(Vector3(0.05, 0.1, 0.05), 0.014), SL, Vector3(0, -0.07, 0))
		_add(arm["elbow"], SmoothKit.blob(Vector3(0.05, 0.05, 0.05), 1.0, 1.0), SL2)
		_add(arm["elbow"], _limb(0.19, 0.026, 0.022, 0.25), SL)
		_add(arm["hand"], SmoothKit.rounded_box(Vector3(0.045, 0.055, 0.04), 0.012), SL2)
	var disc := _p(arm_l["elbow"], "Disc", Vector3(-0.04, -0.1, -0.02), Vector3(0, 0, 90))
	_add(disc, MeshKit.cylinder(0.075, 0.012, 24), RD2)
	for k in range(3):
		_add(disc, MeshKit.sphere(0.008, 8), OR, Vector3(-0.02 + k * 0.02, 0.008, (k % 2) * 0.02))
	_slots(0.44, 0.15, 0.1)
