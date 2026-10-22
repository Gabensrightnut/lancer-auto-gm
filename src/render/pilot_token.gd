class_name PilotToken
extends Node3D
## The pilot on foot, built from the same v2 portrait as their portrait (PortraitSpec format):
## build, skin, hair, inner and outer outfit, hats, glasses, scarves. Our own simple figure
## art, about 1.8 m tall, facing -Z. Used for the creator's Token tab and for pilots out of
## their mech on the battlefield.

var look: Dictionary = {}
var _body: Node3D


func build(portrait: Dictionary) -> PilotToken:
	look = PortraitSpec.normalize(portrait)
	for c in get_children():
		c.queue_free()
	_body = Node3D.new()
	add_child(_body)
	var skin := _c("face", "primary", "#c68d66")
	var inner := _c("inner_outfit", "primary", "#3b4c5e")
	var inner2 := _c("inner_outfit", "secondary", "#d8a23a")
	var outer_opt := _o("outer_outfit")
	var outer := _c("outer_outfit", "primary", "#4a5a6a") if outer_opt != "none" else inner
	var outer2 := _c("outer_outfit", "secondary", "#3a8ac8") if outer_opt != "none" else inner2
	var m_skin := MeshKit.paint(skin, 0.0, 0.7, 0.0)
	var m_in := MeshKit.paint(inner, 0.05, 0.85, 0.15)
	var m_in2 := MeshKit.paint(inner2, 0.1, 0.7, 0.0)
	var m_out := MeshKit.paint(outer, 0.08, 0.8, 0.2)
	var m_out2 := MeshKit.paint(outer2, 0.2, 0.6, 0.0)
	var m_boot := MeshKit.paint(Color(0.12, 0.12, 0.13), 0.3, 0.6, 0.0)
	var wide := {"slim": 0.88, "broad": 1.12, "heavy": 1.22}.get(_o("body", "average"), 1.0) as float
	# Legs and boots.
	for sx: float in [-1.0, 1.0]:
		MeshKit.part(_body, MeshKit.chamfer_box(Vector3(0.16, 0.48, 0.18) * Vector3(wide, 1, wide), 0.03), m_in, Vector3(sx * 0.11 * wide, 0.68, 0))
		MeshKit.part(_body, MeshKit.chamfer_box(Vector3(0.15, 0.4, 0.16), 0.03), m_in, Vector3(sx * 0.11 * wide, 0.3, 0))
		MeshKit.part(_body, MeshKit.chamfer_box(Vector3(0.17, 0.12, 0.27), 0.02), m_boot, Vector3(sx * 0.11 * wide, 0.06, -0.04))
	# Torso, belt, shoulders, arms.
	MeshKit.part(_body, MeshKit.chamfer_box(Vector3(0.42 * wide, 0.56, 0.25 * wide), 0.05, 0.86), m_out if outer_opt in ["uniform", "hardsuit_collar", "coat", "jacket"] else m_in, Vector3(0, 1.22, 0))
	MeshKit.part(_body, MeshKit.chamfer_box(Vector3(0.44 * wide, 0.07, 0.27 * wide), 0.02), m_in2, Vector3(0, 0.96, 0))
	if outer_opt == "jacket":
		MeshKit.part(_body, MeshKit.chamfer_box(Vector3(0.14, 0.5, 0.02), 0.01), m_in, Vector3(0, 1.22, -0.13 * wide))
		for sx: float in [-1.0, 1.0]:
			MeshKit.part(_body, MeshKit.chamfer_box(Vector3(0.05, 0.3, 0.02), 0.01), m_out2, Vector3(sx * 0.09, 1.34, -0.135 * wide), Vector3(0, 0, sx * 12.0))
	elif outer_opt == "coat":
		MeshKit.part(_body, MeshKit.cylinder(0.25 * wide, 0.5, 14, 0.2 * wide), m_out, Vector3(0, 0.72, 0))
		MeshKit.part(_body, MeshKit.cylinder(0.11, 0.12, 12, 0.13), m_out2, Vector3(0, 1.55, 0))
	elif outer_opt == "poncho":
		MeshKit.part(_body, MeshKit.cylinder(0.42 * wide, 0.5, 16, 0.12), m_out, Vector3(0, 1.25, 0))
		MeshKit.part(_body, MeshKit.cylinder(0.425 * wide, 0.05, 16, 0.42 * wide), m_out2, Vector3(0, 1.02, 0))
	elif outer_opt == "hardsuit_collar":
		MeshKit.part(_body, MeshKit.cylinder(0.14, 0.1, 12, 0.18), m_out2, Vector3(0, 1.5, 0))
	elif outer_opt == "uniform":
		for i in range(3):
			MeshKit.part(_body, MeshKit.sphere(0.018, 6), m_out2, Vector3(0, 1.1 + i * 0.12, -0.13 * wide))
	for sx: float in [-1.0, 1.0]:
		var sh := Node3D.new()
		sh.position = Vector3(sx * 0.27 * wide, 1.45, 0)
		_body.add_child(sh)
		var prosthetic := _o("body_detail") == "prosthetic_arm" and sx < 0.0
		var arm_m := MeshKit.paint(Color(0.55, 0.57, 0.6), 0.7, 0.35, 0.3) if prosthetic else (m_out if outer_opt not in ["none", "poncho"] else m_in)
		MeshKit.part(sh, MeshKit.chamfer_box(Vector3(0.12, 0.34, 0.13) * Vector3(wide, 1, wide), 0.03), arm_m, Vector3(0, -0.17, 0))
		MeshKit.part(sh, MeshKit.chamfer_box(Vector3(0.1, 0.3, 0.11), 0.03), arm_m, Vector3(0, -0.47, 0))
		MeshKit.part(sh, MeshKit.sphere(0.06), m_skin if not prosthetic else arm_m, Vector3(0, -0.65, 0))
		if outer_opt in ["uniform", "hardsuit_collar"]:
			MeshKit.part(sh, MeshKit.chamfer_box(Vector3(0.16, 0.05, 0.16) * wide, 0.02), m_out2, Vector3(0, 0.02, 0))
	# Neck and head.
	MeshKit.part(_body, MeshKit.cylinder(0.06, 0.1), m_skin, Vector3(0, 1.54, 0))
	var face_scale := {"round": Vector3(1.0, 1.02, 1.0), "long": Vector3(0.9, 1.18, 0.95), "square": Vector3(1.0, 1.08, 1.0), "heart": Vector3(0.97, 1.1, 0.97)}.get(_o("face", "oval"), Vector3(0.95, 1.1, 1.0)) as Vector3
	MeshKit.part(_body, MeshKit.sphere(0.13), m_skin, Vector3(0, 1.68, 0), Vector3.ZERO, face_scale)
	_hair()
	_headwear()
	var sc := _o("scarves")
	if sc != "none":
		MeshKit.part(_body, MeshKit.cylinder(0.11, 0.09, 12, 0.12), MeshKit.paint(_c("scarves"), 0.0, 0.9, 0.0), Vector3(0, 1.51, 0))
		if sc == "scarf":
			MeshKit.part(_body, MeshKit.chamfer_box(Vector3(0.07, 0.3, 0.02), 0.01), MeshKit.paint(_c("scarves"), 0.0, 0.9, 0.0), Vector3(0.06, 1.33, -0.14))
	# A soft disc under the feet so the figure reads against the ground.
	MeshKit.part(self, MeshKit.cylinder(0.36, 0.01, 20), MeshKit.overlay_material(Color(0, 0, 0, 0.28)), Vector3(0, 0.01, 0))
	return self


func _o(id: String, fallback: String = "none") -> String:
	return String((look.get("parts", {}) as Dictionary).get(id, {}).get("option", fallback))


func _c(id: String, slot: String = "primary", fallback: String = "#808080") -> Color:
	var p: Dictionary = (look.get("parts", {}) as Dictionary).get(id, {})
	return Color(String(p.get(slot, p.get("primary", fallback))))


func _hair() -> void:
	var style := _o("hair", "short")
	if style == "bald" or _o("hats") in ["helmet", "hood"]:
		return
	var m := MeshKit.paint(_c("hair", "primary", "#3a2518"), 0.0, 0.9, 0.0)
	var cap := Vector3(1.05, 0.7 if style != "buzz" else 0.6, 1.08)
	MeshKit.part(_body, MeshKit.sphere(0.135), m, Vector3(0, 1.73, 0.015), Vector3.ZERO, cap)
	match style:
		"long":
			MeshKit.part(_body, MeshKit.chamfer_box(Vector3(0.26, 0.34, 0.09), 0.03), m, Vector3(0, 1.56, 0.1))
		"braids":
			for sx: float in [-1.0, 1.0]:
				MeshKit.part(_body, MeshKit.cylinder(0.025, 0.32), m, Vector3(sx * 0.12, 1.5, 0.04))
		"bun":
			MeshKit.part(_body, MeshKit.sphere(0.06), m, Vector3(0, 1.84, 0.06))
		"mohawk":
			MeshKit.part(_body, MeshKit.chamfer_box(Vector3(0.04, 0.12, 0.28), 0.01), MeshKit.paint(_c("hair", "secondary"), 0.0, 0.9, 0.0), Vector3(0, 1.85, 0.01))
		"swept":
			MeshKit.part(_body, MeshKit.chamfer_box(Vector3(0.24, 0.06, 0.12), 0.02), m, Vector3(0.02, 1.8, -0.08), Vector3(0, 0, -10))


func _headwear() -> void:
	var c := _c("hats", "primary", "#4a5a6a")
	var m := MeshKit.paint(c, 0.2, 0.6, 0.0)
	match _o("hats"):
		"cap":
			MeshKit.part(_body, MeshKit.sphere(0.14), m, Vector3(0, 1.75, 0), Vector3.ZERO, Vector3(1.04, 0.62, 1.06))
			MeshKit.part(_body, MeshKit.chamfer_box(Vector3(0.18, 0.02, 0.12), 0.005), m, Vector3(0, 1.75, -0.15))
		"beanie":
			MeshKit.part(_body, MeshKit.sphere(0.14), m, Vector3(0, 1.76, 0.0), Vector3.ZERO, Vector3(1.05, 0.8, 1.08))
		"helmet":
			MeshKit.part(_body, MeshKit.sphere(0.165), m, Vector3(0, 1.72, 0.0), Vector3.ZERO, Vector3(1.0, 0.95, 1.05))
			MeshKit.part(_body, MeshKit.chamfer_box(Vector3(0.24, 0.07, 0.06), 0.02), MeshKit.paint(Color(0.15, 0.2, 0.25), 0.6, 0.15, 0.0, Color(0.2, 0.5, 0.7)), Vector3(0, 1.69, -0.14))
		"headset":
			for sx: float in [-1.0, 1.0]:
				MeshKit.part(_body, MeshKit.cylinder(0.04, 0.04), m, Vector3(sx * 0.135, 1.68, 0), Vector3(0, 0, 90))
		"hood":
			MeshKit.part(_body, MeshKit.sphere(0.17), m, Vector3(0, 1.7, 0.03), Vector3.ZERO, Vector3(1.0, 1.05, 1.1))
	match _o("glasses"):
		"visor", "goggles":
			var g := _c("glasses", "primary", "#3a8ac8")
			MeshKit.part(_body, MeshKit.chamfer_box(Vector3(0.24, 0.05, 0.06), 0.01), MeshKit.paint(g, 0.5, 0.2, 0.0, g * 0.8), Vector3(0, 1.7, -0.11))
		"glasses":
			MeshKit.part(_body, MeshKit.chamfer_box(Vector3(0.2, 0.035, 0.02), 0.005), MeshKit.paint(_c("glasses"), 0.6, 0.3, 0.0), Vector3(0, 1.7, -0.125))
