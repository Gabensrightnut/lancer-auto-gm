class_name CockpitShell
extends RefCounted
## The inside of a cockpit around the first-person camera (a child of it, camera space: -z
## forward): canopy pillars and a top strut at the edges of the view, and a dash below with two
## lit screens, in the frame manufacturer's trim and glow colors. Kept to the edges so the
## battlefield stays readable. Drone-bodied frames don't get one (VisibleParts.first_person).


static func build(palette: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "CockpitShell"
	var trim := MeshKit.mech_material(Color(palette.get("trim", Color(0.12, 0.13, 0.15))).darkened(0.3), 0.7, 0.5, Color.BLACK, false)
	var panel := MeshKit.mech_material(Color(palette.get("secondary", Color(0.3, 0.32, 0.35))).darkened(0.45), 0.4, 0.6, Color.BLACK, false)
	var glow := MeshKit.fx_material(Color(palette.get("glow", Color(0.4, 1.0, 0.7))), 1.6)
	# Dash: a sloped panel across the bottom of the view, with two screens.
	_part(root, MeshKit.chamfer_box(Vector3(0.62, 0.07, 0.16), 0.01), panel, Vector3(0, -0.2, -0.24), Vector3(28, 0, 0))
	for sx in [-1.0, 1.0]:
		_part(root, MeshKit.chamfer_box(Vector3(0.11, 0.005, 0.065), 0.002), glow, Vector3(sx * 0.12, -0.163, -0.245), Vector3(28, 0, 0))
	# Canopy pillars at the sides and a strut across the top.
	for sx in [-1.0, 1.0]:
		_part(root, MeshKit.chamfer_box(Vector3(0.035, 0.5, 0.04), 0.008), trim, Vector3(sx * 0.34, 0.0, -0.24), Vector3(0, 0, sx * 12.0))
	_part(root, MeshKit.chamfer_box(Vector3(0.75, 0.03, 0.05), 0.008), trim, Vector3(0, 0.215, -0.24))
	return root


static func _part(root: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> void:
	var mi := MeshKit.part(root, mesh, mat, pos, rot)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
