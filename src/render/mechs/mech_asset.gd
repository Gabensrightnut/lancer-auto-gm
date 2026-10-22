class_name MechAsset
extends RefCounted
## Frames modeled in Blender (tools/blender/<frame>.py -> assets/mechs/<frame_id>.glb).
## The glb carries named empties for the rig (Pelvis, Torso, Head, Eye, Hip_r/Knee_r/Ankle_r,
## Shoulder_r/Elbow_r/Hand_r, Pad_r, Slot_*), so walking, aiming and loadout mounts work
## like the code-built frames. Materials are named by paint role and are replaced with the
## game's paint shader (edge wear and grime from the baked vertex colors; outline pass).

const DIR := "res://assets/mechs/"

static var _mat_cache: Dictionary = {}
## Merged part meshes per frame and joint ("frame|path" -> ArrayMesh), built once.
static var _merged: Dictionary = {}


static func path(frame_id: String) -> String:
	return DIR + frame_id + ".glb"


static func has(frame_id: String) -> bool:
	return frame_id != "" and ResourceLoader.exists(path(frame_id))


## Fills `m` from the frame's glb under `body`. Returns false if it couldn't be loaded.
static func build(frame_id: String, m: MechModel, body: Node3D) -> bool:
	var scene := load(path(frame_id)) as PackedScene
	if scene == null:
		return false
	var root := scene.instantiate() as Node3D
	body.add_child(root)
	var find := func(n: String) -> Node3D: return root.find_child(n, true, false) as Node3D
	m.pelvis = find.call("Pelvis")
	m.torso = find.call("Torso")
	m.head = find.call("Head")
	if m.pelvis == null or m.torso == null:
		push_error("MechAsset: %s has no Pelvis/Torso empties" % frame_id)
		return false
	m.pelvis.set_meta("rest_y", m.pelvis.position.y)
	m.set_meta("custom_pose", true)
	var eye: Node3D = find.call("Eye")
	m.eye = Marker3D.new()
	m.eye.name = "EyeMarker"
	(eye if eye else (m.head if m.head else m.torso)).add_child(m.eye)
	for side: String in ["r", "l", "fr", "fl", "rr", "rl", "mr", "ml"]:
		var hip: Node3D = find.call("Hip_" + side)
		if hip == null:
			continue
		var knee: Node3D = find.call("Knee_" + side)
		var ankle: Node3D = find.call("Ankle_" + side)
		m.legs.append({"hip": hip, "knee": knee, "ankle": ankle,
			"base": Vector3(hip.rotation_degrees.x, knee.rotation_degrees.x if knee else 0.0, ankle.rotation_degrees.x if ankle else 0.0)})
	for side: String in ["r", "l"]:
		var sh: Node3D = find.call("Shoulder_" + side)
		if sh == null:
			continue
		var el: Node3D = find.call("Elbow_" + side)
		m.arms[side] = {"shoulder": sh, "elbow": el, "hand": find.call("Hand_" + side),
			"rest_shoulder": sh.rotation_degrees, "rest_elbow": el.rotation_degrees if el else Vector3.ZERO}
	for n in root.find_children("Slot_*", "Node3D", true, false):
		m.slots[String(n.name).substr(5)] = n
	_repaint(root, frame_id)
	_merge(root, frame_id)
	return true


## Draw-call diet: the parts that move together (all mesh children of one joint) become a
## single mesh with one surface per material, with LODs generated for distance. Built once
## per frame and shared by every copy; paint still works per model (surface overrides).
## A Blender frame goes from ~200 draw calls (and as many shadow draws) to a few dozen.
static func _merge(root: Node3D, frame_id: String) -> void:
	var groups := {}
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.get_child_count() > 0 or mi.skin != null:
			continue
		var parent := mi.get_parent() as Node3D
		if parent == null:
			continue
		if not groups.has(parent):
			groups[parent] = []
		(groups[parent] as Array).append(mi)
	for parent: Node3D in groups:
		var list: Array = groups[parent]
		if list.size() < 2:
			continue
		var key := frame_id + "|" + str(root.get_path_to(parent))
		var mesh: ArrayMesh = _merged.get(key)
		if mesh == null:
			mesh = _merged_mesh(list)
			_merged[key] = mesh
		var merged := MeshInstance3D.new()
		merged.name = "Merged"
		merged.mesh = mesh
		merged.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		parent.add_child(merged)
		for mi: MeshInstance3D in list:
			parent.remove_child(mi)
			mi.free()


static func _merged_mesh(list: Array) -> ArrayMesh:
	var buckets := {}  # material -> SurfaceTool
	var order: Array = []
	for mi: MeshInstance3D in list:
		for s in range(mi.mesh.get_surface_count()):
			var mat: Material = mi.material_override
			if mat == null:
				mat = mi.get_surface_override_material(s)
			if mat == null:
				mat = mi.mesh.surface_get_material(s)
			if not buckets.has(mat):
				buckets[mat] = SurfaceTool.new()
				order.append(mat)
			(buckets[mat] as SurfaceTool).append_from(mi.mesh, s, mi.transform)
	var im := ImporterMesh.new()
	for mat: Material in order:
		var arrays := (buckets[mat] as SurfaceTool).commit_to_arrays()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, mat)
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()


static func _repaint(root: Node, frame_id: String) -> void:
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i in range(mi.mesh.get_surface_count()):
			var src := mi.mesh.surface_get_material(i)
			if src:
				mi.set_surface_override_material(i, _paint(src, frame_id))


## The game's paint material for an imported role material (cached per frame and role).
static func _paint(src: Material, frame_id: String) -> Material:
	var key := frame_id + "|" + src.resource_name
	if _mat_cache.has(key):
		return _mat_cache[key]
	var color := Color(0.6, 0.6, 0.6)
	var metal := 0.4
	var rough := 0.6
	var emit := Color.BLACK
	if src is BaseMaterial3D:
		var b := src as BaseMaterial3D
		color = b.albedo_color
		metal = b.metallic
		rough = b.roughness
		if b.emission_enabled:
			emit = b.emission * b.emission_energy_multiplier
	var role := src.resource_name
	var m := ShaderMaterial.new()
	m.shader = MeshKit.MECH_SHADER
	# Godot's glTF import already converted the colors to sRGB.
	m.set_shader_parameter("base_color", color)
	m.set_shader_parameter("metallic_value", metal)
	m.set_shader_parameter("roughness_value", rough)
	m.set_shader_parameter("emission_color", emit * (0.5 if role == "glow" else 0.0))
	m.set_shader_parameter("panel_strength", 0.0)
	m.set_shader_parameter("vertex_wear", 0.0 if role in ["glow", "rope", "hose", "cloth"] else 1.0)
	if MeshKit.outlines:
		m.next_pass = MeshKit.paint(Color.WHITE).next_pass
	m.set_meta("paint_role", role)
	_mat_cache[key] = m
	return m
