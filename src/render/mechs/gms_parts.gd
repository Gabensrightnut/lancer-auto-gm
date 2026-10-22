class_name GmsParts
extends RefCounted
## Reusable GMS mech parts (the Everest and basic GMS variants): armored joint pods, open
## truss limbs over pistons, boxy truss-paneled forearms and shins, big four-fingered hands
## and flat segmented feet. Each builder adds meshes under `parent` and returns nothing;
## sizes are in body-height units (the mech is scaled to its Size afterwards).


## A spherical armored pod (shoulder/hip/knee) with round bolt holes facing `out`.
static func pod(parent: Node3D, mat: Material, dark: Material, pos: Vector3, r: float, out: Vector3 = Vector3.FORWARD, holes: int = 3) -> void:
	MeshKit.part(parent, SmoothKit.blob(Vector3(r, r, r) * 2.0, 0.85, 0.85, 1.0, 20), mat, pos)
	var o := out.normalized()
	var side := o.cross(Vector3.UP if absf(o.y) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(o).normalized()
	for i in range(holes):
		var a := TAU * i / holes + 0.5
		var d := (o * 0.82 + (side * cos(a) + up * sin(a)) * 0.45).normalized()
		var hole := MeshKit.part(parent, MeshKit.cylinder(r * 0.16, r * 0.1, 10), dark, pos + d * r * 0.97)
		hole.basis = Basis.looking_at(d, up if absf(d.dot(up)) < 0.95 else side) * Basis(Vector3.RIGHT, PI / 2.0)
	# Seam ring.
	var ring := TorusMesh.new()
	ring.inner_radius = r * 0.97
	ring.outer_radius = r * 1.03
	ring.rings = 28
	ring.ring_segments = 6
	var rm := MeshKit.part(parent, ring, dark, pos)
	rm.basis = Basis.looking_at(side, o) * Basis(Vector3.RIGHT, PI / 2.0)


## An open lattice limb hanging down from the origin: four corner rails, X-braced faces and
## an inner piston. `w` x `d` cross-section, `length` long.
static func truss(parent: Node3D, frame: Material, piston: Material, length: float, w: float, d: float, bays: int = 2, rail: float = 0.009) -> void:
	var h := Vector2(w, d) * 0.5
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			MeshKit.part(parent, MeshKit.chamfer_box(Vector3(rail * 2.0, length, rail * 2.0), rail * 0.4), frame, Vector3(sx * h.x, -length / 2.0, sz * h.y))
	var bay := length / bays
	for b in range(bays + 1):
		var y := -b * bay
		for face in range(4):
			var horiz := face % 2 == 0
			var size := Vector3(w + rail * 2.0, rail * 1.6, rail * 1.6) if horiz else Vector3(rail * 1.6, rail * 1.6, d + rail * 2.0)
			var off := Vector3(0, y, (h.y if face == 0 else -h.y)) if horiz else Vector3((h.x if face == 1 else -h.x), y, 0)
			MeshKit.part(parent, MeshKit.chamfer_box(size, rail * 0.3), frame, off)
	# X braces on the front/back (x-z faces at +-z) and the sides.
	for b in range(bays):
		var y0 := -b * bay
		var y1 := y0 - bay
		for sz: float in [-1.0, 1.0]:
			for diag: float in [-1.0, 1.0]:
				_strut(parent, frame, Vector3(-h.x * diag, y0, sz * h.y), Vector3(h.x * diag, y1, sz * h.y), rail * 0.75)
		for sx: float in [-1.0, 1.0]:
			for diag: float in [-1.0, 1.0]:
				_strut(parent, frame, Vector3(sx * h.x, y0, -h.y * diag), Vector3(sx * h.x, y1, h.y * diag), rail * 0.75)
	MeshKit.part(parent, MeshKit.cylinder(minf(w, d) * 0.22, length * 0.9, 12), piston, Vector3(0, -length / 2.0, 0))
	MeshKit.part(parent, MeshKit.cylinder(minf(w, d) * 0.3, length * 0.35, 12), piston, Vector3(0, -length * 0.25, 0))


static func _strut(parent: Node3D, mat: Material, a: Vector3, b: Vector3, r: float) -> void:
	var mi := MeshKit.part(parent, MeshKit.chamfer_box(Vector3(r * 2.0, 1.0, r * 2.0), r * 0.3), mat, (a + b) * 0.5)
	var dir := b - a
	var y := dir.normalized()
	var hint := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := y.cross(hint).normalized()
	mi.basis = Basis(x, y, x.cross(y)).scaled_local(Vector3(1, dir.length(), 1))


## A chunky boxy segment (forearm/shin) hanging down: an armored box with truss-panel
## windows on its sides showing the dark frame inside.
static func armored_box(parent: Node3D, shell: Material, frame: Material, length: float, w: float, d: float, taper: float = 0.85) -> void:
	MeshKit.part(parent, SmoothKit.loft([
		{"y": -length, "w": w * taper, "d": d * taper, "n": 5.0},
		{"y": -length * 0.5, "w": w, "d": d, "n": 5.0},
		{"y": 0.0, "w": w * 0.92, "d": d * 0.92, "n": 5.0},
	], 20), shell)
	# Truss windows on the outer and inner faces.
	for sx: float in [-1.0, 1.0]:
		var win := Node3D.new()
		win.position = Vector3(sx * w * 0.5, -length * 0.5, 0)
		parent.add_child(win)
		var ww := d * 0.6
		var wh := length * 0.55
		MeshKit.part(win, MeshKit.chamfer_box(Vector3(0.008, wh, ww), 0.002), frame, Vector3(sx * 0.002, 0, 0))
		for diag: float in [-1.0, 1.0]:
			_strut(win, shell, Vector3(sx * 0.006, wh * 0.45, -ww * 0.45 * diag), Vector3(sx * 0.006, -wh * 0.45, ww * 0.45 * diag), 0.004)
	# Front plate seam.
	MeshKit.part(parent, MeshKit.chamfer_box(Vector3(w * 0.7, 0.006, 0.006), 0.001), frame, Vector3(0, -length * 0.3, -d * 0.5))


## A big four-fingered hand curled to grip, palm facing -x (inside) for side "r".
## Red knuckle and finger plates. Origin at the wrist; the hand hangs down.
static func hand(parent: Node3D, dark: Material, plate: Material, size: float, side: float, grip: float = 0.7) -> void:
	MeshKit.part(parent, SmoothKit.rounded_box(Vector3(size * 0.75, size * 0.85, size * 0.95), size * 0.15), dark, Vector3(0, -size * 0.45, 0))
	MeshKit.part(parent, SmoothKit.rounded_box(Vector3(size * 0.25, size * 0.7, size * 0.8), size * 0.1), plate, Vector3(side * size * 0.38, -size * 0.45, 0))
	for i in range(4):
		var f := Node3D.new()
		f.position = Vector3(side * size * 0.1, -size * 0.85, (i - 1.5) * size * 0.24)
		f.rotation = Vector3(0, 0, -side * grip)
		parent.add_child(f)
		MeshKit.part(f, SmoothKit.rounded_box(Vector3(size * 0.2, size * 0.32, size * 0.2), size * 0.05), dark, Vector3(0, -size * 0.16, 0))
		MeshKit.part(f, SmoothKit.rounded_box(Vector3(size * 0.08, size * 0.3, size * 0.21), size * 0.03), plate, Vector3(side * size * 0.1, -size * 0.16, 0))
		var tip := Node3D.new()
		tip.position = Vector3(0, -size * 0.32, 0)
		tip.rotation = Vector3(0, 0, -side * grip * 0.9)
		f.add_child(tip)
		MeshKit.part(tip, SmoothKit.rounded_box(Vector3(size * 0.18, size * 0.26, size * 0.18), size * 0.05), dark, Vector3(0, -size * 0.13, 0))
	var thumb := Node3D.new()
	thumb.position = Vector3(-side * size * 0.3, -size * 0.35, -size * 0.45)
	thumb.rotation = Vector3(0.6, 0, side * 0.5)
	parent.add_child(thumb)
	MeshKit.part(thumb, SmoothKit.rounded_box(Vector3(size * 0.2, size * 0.4, size * 0.2), size * 0.06), dark, Vector3(0, -size * 0.2, 0))


## A flat, blocky, segmented foot under the ankle origin (toe toward -z).
static func foot(parent: Node3D, shell: Material, dark: Material, size: float) -> void:
	MeshKit.part(parent, SmoothKit.rounded_box(Vector3(size * 0.7, size * 0.35, size * 0.6), size * 0.08), dark, Vector3(0, -size * 0.12, 0))
	MeshKit.part(parent, SmoothKit.rounded_box(Vector3(size * 0.95, size * 0.28, size * 0.75), size * 0.07), shell, Vector3(0, -size * 0.36, size * 0.05))
	for i in range(3):
		MeshKit.part(parent, SmoothKit.rounded_box(Vector3(size * 0.9, size * 0.24, size * 0.26), size * 0.06), shell,
			Vector3(0, -size * 0.38, -size * (0.42 + i * 0.27)), Vector3(i * 4.0, 0, 0))
		MeshKit.part(parent, MeshKit.chamfer_box(Vector3(size * 0.92, size * 0.06, size * 0.03), size * 0.01), dark, Vector3(0, -size * 0.33, -size * (0.29 + i * 0.27)))
	MeshKit.part(parent, SmoothKit.rounded_box(Vector3(size * 0.6, size * 0.22, size * 0.3), size * 0.06), shell, Vector3(0, -size * 0.4, size * 0.48))
