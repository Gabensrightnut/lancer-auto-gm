class_name Vehicles
extends RefCounted
## Ground vehicles made in code, one mesh each with vertex colors (sRGB). About 0.6 x 0.3
## board units: far smaller than a mech, so they never read as cover. Kinds: car, van, bike,
## fin_car (atomic-age, tail fins), pod (Union hover-pod), wreck (burned-out car), cart,
## wagon (covered), scooter, truck (cab and box). Lit parts (lights) use vertex alpha 0 (glow in foliage shader).

static var _cache := {}

const PAINTS := {
	"car": ["#2a3a5a", "#8a1e24", "#d8d8dc", "#1a1a1e", "#3a5a3a", "#c8a030"],
	"van": ["#d8d8d0", "#3a3a40", "#5a6a7a"],
	"bike": ["#1a1a1e", "#c81e4a"],
	"fin_car": ["#40c0b0", "#f08a6a", "#f0d060", "#f0ece0", "#c83a4a"],
	"pod": ["#f2f4f6", "#e4e8ec"],
	"wreck": ["#2a2422", "#3a2e28"],
	"cart": ["#6a4a2a"],
	"wagon": ["#6a4a2a", "#5a3e24"],
	"scooter": ["#c81e1e", "#f0f0f0", "#2a6ab0"],
	"truck": ["#c83a2a", "#2a4a7a", "#e8e4dc", "#3a5a3a", "#e8a020"],
}


static func paint_for(kind: String, h: float) -> Color:
	var list: Array = PAINTS.get(kind, ["#808080"])
	return Color.html(list[int(h * list.size()) % list.size()])


static func _arr(m: Mesh) -> Array:
	var a := m.surface_get_arrays(0)
	var idx: Variant = a[Mesh.ARRAY_INDEX]
	if idx == null:  # unindexed mesh (chamfer boxes): every vertex in order
		var seq := PackedInt32Array()
		seq.resize((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
		for i in range(seq.size()):
			seq[i] = i
		idx = seq
	return [a[Mesh.ARRAY_VERTEX], a[Mesh.ARRAY_NORMAL], idx]


static func _box(st: SurfaceTool, size: Vector3, pos: Vector3, col: Color, bevel: float = 0.02) -> void:
	Flora.add(st, _arr(MeshKit.chamfer_box(size, bevel)), Transform3D(Basis(), pos), col, 0.35)


static func _wheel(st: SurfaceTool, r: float, pos: Vector3, col: Color) -> void:
	Flora.add(st, _arr(MeshKit.cylinder(r, r * 0.6, 10)), Transform3D(Basis(Vector3.FORWARD, PI * 0.5), pos), col, 0.2)


## Mesh for a vehicle kind and paint; faces +X (its length runs along x).
static func mesh(kind: String, paint: Color) -> ArrayMesh:
	var key := "%s|%s" % [kind, paint.to_html()]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var p := Color(paint.r, paint.g, paint.b, 1.0)
	var dark := Color(0.08, 0.08, 0.09, 1.0)
	var glass := Color(0.12, 0.16, 0.2, 1.0)
	var head := Color(1.0, 0.92, 0.75, 0.0)
	var tail := Color(1.0, 0.15, 0.1, 0.0)
	var wood := Color(0.42, 0.3, 0.18, 1.0)
	match kind:
		"van":
			_box(st, Vector3(0.66, 0.24, 0.28), Vector3(0, 0.16, 0), p)
			_box(st, Vector3(0.12, 0.1, 0.26), Vector3(0.28, 0.2, 0), glass, 0.01)
			for x: float in [-0.2, 0.2]:
				for z: float in [-0.13, 0.13]:
					_wheel(st, 0.055, Vector3(x, 0.055, z), dark)
			_box(st, Vector3(0.01, 0.03, 0.2), Vector3(0.335, 0.12, 0), head, 0.0)
		"bike":
			_box(st, Vector3(0.28, 0.06, 0.05), Vector3(0, 0.1, 0), p)
			_wheel(st, 0.05, Vector3(0.12, 0.05, 0), dark)
			_wheel(st, 0.05, Vector3(-0.12, 0.05, 0), dark)
			_box(st, Vector3(0.01, 0.02, 0.03), Vector3(0.15, 0.12, 0), head, 0.0)
		"fin_car":
			_box(st, Vector3(0.66, 0.1, 0.27), Vector3(0, 0.1, 0), p, 0.04)
			_box(st, Vector3(0.3, 0.08, 0.24), Vector3(-0.02, 0.19, 0), glass, 0.04)
			for z: float in [-0.12, 0.12]:
				_box(st, Vector3(0.16, 0.08, 0.02), Vector3(-0.27, 0.17, z), p, 0.01)  # tail fins
				_box(st, Vector3(0.02, 0.03, 0.04), Vector3(-0.33, 0.12, z), tail, 0.0)
			_box(st, Vector3(0.62, 0.02, 0.28), Vector3(0, 0.07, 0), Color(0.85, 0.87, 0.9, 1.0), 0.005)  # chrome trim
			for x: float in [-0.2, 0.2]:
				for z: float in [-0.13, 0.13]:
					_wheel(st, 0.045, Vector3(x, 0.045, z), dark)
		"pod":
			Flora.add(st, Flora.blob(0.18, "pod", 0.0, 0.55, 12), Transform3D(Basis.from_scale(Vector3(1.8, 1.0, 0.85)), Vector3(0, 0.16, 0)), p, 0.25)
			_box(st, Vector3(0.24, 0.06, 0.2), Vector3(0.08, 0.2, 0), glass, 0.03)
			_box(st, Vector3(0.5, 0.015, 0.22), Vector3(0, 0.05, 0), Color(0.5, 0.85, 1.0, 0.0), 0.005)  # hover glow
		"wreck":
			_box(st, Vector3(0.6, 0.12, 0.27), Vector3(0, 0.1, 0), p, 0.03)
			_box(st, Vector3(0.26, 0.07, 0.24), Vector3(-0.02, 0.19, 0), Color(0.05, 0.04, 0.04, 1.0), 0.02)
			_wheel(st, 0.05, Vector3(0.2, 0.05, 0.13), dark)
			_wheel(st, 0.05, Vector3(-0.2, 0.05, -0.13), dark)
		"cart":
			_box(st, Vector3(0.36, 0.1, 0.24), Vector3(0, 0.13, 0), wood, 0.01)
			_wheel(st, 0.09, Vector3(0, 0.09, 0.14), Color(0.3, 0.22, 0.14, 1.0))
			_wheel(st, 0.09, Vector3(0, 0.09, -0.14), Color(0.3, 0.22, 0.14, 1.0))
			_box(st, Vector3(0.3, 0.02, 0.02), Vector3(0.32, 0.1, 0), wood, 0.0)
		"wagon":
			_box(st, Vector3(0.56, 0.08, 0.26), Vector3(0, 0.12, 0), wood, 0.01)
			Flora.add(st, Flora.blob(0.16, "canvas", 0.0, 0.8, 10), Transform3D(Basis.from_scale(Vector3(1.6, 0.8, 0.8)), Vector3(-0.02, 0.18, 0)), Color(0.88, 0.84, 0.74, 1.0), 0.3)
			for x: float in [-0.18, 0.18]:
				for z: float in [-0.15, 0.15]:
					_wheel(st, 0.08, Vector3(x, 0.08, z), Color(0.3, 0.22, 0.14, 1.0))
			_box(st, Vector3(0.3, 0.02, 0.02), Vector3(0.42, 0.1, 0), wood, 0.0)
		"truck":
			_box(st, Vector3(0.2, 0.22, 0.28), Vector3(0.32, 0.17, 0), p, 0.03)
			_box(st, Vector3(0.02, 0.09, 0.24), Vector3(0.42, 0.21, 0), glass, 0.01)
			_box(st, Vector3(0.52, 0.3, 0.3), Vector3(-0.08, 0.21, 0), Color(0.82, 0.8, 0.76, 1.0), 0.02)
			for x: float in [-0.26, -0.1, 0.3]:
				for z: float in [-0.14, 0.14]:
					_wheel(st, 0.055, Vector3(x, 0.055, z), dark)
			_box(st, Vector3(0.01, 0.03, 0.22), Vector3(0.425, 0.11, 0), head, 0.0)
			_box(st, Vector3(0.01, 0.03, 0.24), Vector3(-0.345, 0.1, 0), tail, 0.0)
		"scooter":
			_box(st, Vector3(0.24, 0.05, 0.08), Vector3(0, 0.08, 0), p, 0.02)
			_box(st, Vector3(0.02, 0.12, 0.02), Vector3(0.1, 0.14, 0), dark, 0.0)
			_wheel(st, 0.04, Vector3(0.1, 0.04, 0), dark)
			_wheel(st, 0.04, Vector3(-0.1, 0.04, 0), dark)
		_:
			# Car: body, cabin, wheels, lights.
			_box(st, Vector3(0.6, 0.11, 0.27), Vector3(0, 0.1, 0), p, 0.03)
			_box(st, Vector3(0.3, 0.09, 0.24), Vector3(-0.03, 0.19, 0), glass, 0.03)
			for x: float in [-0.19, 0.19]:
				for z: float in [-0.13, 0.13]:
					_wheel(st, 0.05, Vector3(x, 0.05, z), dark)
			_box(st, Vector3(0.01, 0.03, 0.22), Vector3(0.305, 0.11, 0), head, 0.0)
			_box(st, Vector3(0.01, 0.03, 0.22), Vector3(-0.305, 0.11, 0), tail, 0.0)
	var m := st.commit()
	_cache[key] = m
	return m
