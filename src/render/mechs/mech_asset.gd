class_name MechAsset
extends RefCounted
## Frames modeled in Blender (tools/blender/<frame>.py -> assets/mechs/<frame_id>.glb).
## The glb carries named empties for the rig (Pelvis, Torso, Head, Eye, Hip_r/Knee_r/Ankle_r,
## Shoulder_r/Elbow_r/Hand_r, Pad_r, Slot_*), so walking, aiming and loadout mounts work
## like the code-built frames. Materials are named by paint role and are replaced with the
## game's paint shader (edge wear and grime from the baked vertex colors; outline pass).

const DIR := "res://assets/mechs/"

static var _mat_cache: Dictionary = {}


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
	return true


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
	_mat_cache[key] = m
	return m
