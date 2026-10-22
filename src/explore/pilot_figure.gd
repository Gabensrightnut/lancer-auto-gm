class_name PilotFigure
extends Node3D
## A person on foot in a hub: a simple stylized figure built from primitives (our own art),
## colored from the same "look" the portrait uses. About 1.8 m tall; faces -Z. Walks with a
## leg and arm swing while it moves; NPCs idle with a slight sway.

var look: Dictionary = {}
var walking := 0.0
var _t := 0.0
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _body: Node3D
var _label: Label3D
var _ring: MeshInstance3D


func build(l: Dictionary, title: String = "", subtitle: String = "", pilot_suit: bool = false) -> PilotFigure:
	look = PortraitSpec.flatten(l)
	var skin := Color.html(str(look.get("skin", "#c68d66")))
	var hair := Color.html(str(look.get("hair", "#3a2518")))
	var outfit := Color.html(str(look.get("outfit", "#4a5a6a")))
	var accent := Color.html(str(look.get("accent", "#3a8ac8")))
	if pilot_suit:
		outfit = Color(0.24, 0.3, 0.38)
	var cloth := MeshKit.paint(outfit, 0.05, 0.85, 0.15)
	var trim := MeshKit.paint(accent, 0.2, 0.6, 0.0)
	var skin_m := MeshKit.paint(skin, 0.0, 0.7, 0.0)
	var dark := MeshKit.paint(Color(0.12, 0.12, 0.13), 0.3, 0.6, 0.0)
	_body = Node3D.new()
	add_child(_body)
	for sx: float in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(sx * 0.12, 0.92, 0)
		_body.add_child(hip)
		MeshKit.part(hip, MeshKit.chamfer_box(Vector3(0.16, 0.5, 0.18), 0.03), cloth, Vector3(0, -0.26, 0))
		MeshKit.part(hip, MeshKit.chamfer_box(Vector3(0.14, 0.42, 0.15), 0.03), cloth, Vector3(0, -0.62, 0))
		MeshKit.part(hip, MeshKit.chamfer_box(Vector3(0.16, 0.1, 0.26), 0.02), dark, Vector3(0, -0.86, -0.04))
		_legs.append(hip)
	MeshKit.part(_body, MeshKit.chamfer_box(Vector3(0.42, 0.56, 0.24), 0.05, 0.85), cloth, Vector3(0, 1.22, 0))
	MeshKit.part(_body, MeshKit.chamfer_box(Vector3(0.44, 0.08, 0.26), 0.02), trim, Vector3(0, 0.96, 0))
	if pilot_suit:
		MeshKit.part(_body, MeshKit.chamfer_box(Vector3(0.2, 0.06, 0.02), 0.01), trim, Vector3(0.1, 1.36, -0.13))
	for sx: float in [-1.0, 1.0]:
		var sh := Node3D.new()
		sh.position = Vector3(sx * 0.27, 1.45, 0)
		_body.add_child(sh)
		MeshKit.part(sh, MeshKit.chamfer_box(Vector3(0.12, 0.34, 0.13), 0.03), cloth, Vector3(0, -0.17, 0))
		MeshKit.part(sh, MeshKit.chamfer_box(Vector3(0.1, 0.3, 0.11), 0.03), cloth, Vector3(0, -0.47, 0))
		MeshKit.part(sh, MeshKit.sphere(0.06), skin_m, Vector3(0, -0.65, 0))
		_arms.append(sh)
	MeshKit.part(_body, MeshKit.cylinder(0.06, 0.1), skin_m, Vector3(0, 1.54, 0))
	MeshKit.part(_body, MeshKit.sphere(0.13), skin_m, Vector3(0, 1.68, 0), Vector3.ZERO, Vector3(0.95, 1.1, 1.0))
	var style := str(look.get("hair_style", "short"))
	var hair_m := MeshKit.paint(hair, 0.0, 0.9, 0.0)
	if style != "bald":
		var cap_scale := Vector3(1.05, 0.7 if style != "buzz" else 0.6, 1.08)
		MeshKit.part(_body, MeshKit.sphere(0.135), hair_m, Vector3(0, 1.73, 0.015), Vector3.ZERO, cap_scale)
	if style in ["long", "braids"]:
		MeshKit.part(_body, MeshKit.chamfer_box(Vector3(0.24, 0.3, 0.08), 0.03), hair_m, Vector3(0, 1.58, 0.1))
	if style == "bun":
		MeshKit.part(_body, MeshKit.sphere(0.06), hair_m, Vector3(0, 1.84, 0.06))
	if style == "mohawk":
		MeshKit.part(_body, MeshKit.chamfer_box(Vector3(0.04, 0.1, 0.26), 0.01), hair_m, Vector3(0, 1.83, 0.01))
	match str(look.get("extra", "none")):
		"visor":
			MeshKit.part(_body, MeshKit.chamfer_box(Vector3(0.24, 0.05, 0.06), 0.01), MeshKit.paint(accent, 0.5, 0.2, 0.0, accent * 0.8), Vector3(0, 1.7, -0.11))
		"cap":
			MeshKit.part(_body, MeshKit.cylinder(0.14, 0.08), trim, Vector3(0, 1.8, 0))
			MeshKit.part(_body, MeshKit.chamfer_box(Vector3(0.18, 0.02, 0.12), 0.005), trim, Vector3(0, 1.77, -0.15))
		"scarf":
			MeshKit.part(_body, MeshKit.cylinder(0.11, 0.08), trim, Vector3(0, 1.5, 0))
	# A soft disc under the feet so people read against the ground.
	_ring = MeshKit.part(self, MeshKit.cylinder(0.36, 0.01, 20), MeshKit.overlay_material(Color(0, 0, 0, 0.28)), Vector3(0, 0.01, 0))
	if title != "":
		_label = Label3D.new()
		_label.text = title + ("\n" + subtitle if subtitle != "" else "")
		_label.font_size = 40
		_label.outline_size = 10
		_label.pixel_size = 0.006
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.position = Vector3(0, 2.25, 0)
		_label.modulate = Color(0.92, 0.95, 1.0)
		add_child(_label)
	return self


func set_highlight(on: bool, color: Color = Color(1.0, 0.82, 0.4)) -> void:
	if _ring != null:
		_ring.material_override = MeshKit.overlay_material(Color(color, 0.7) if on else Color(0, 0, 0, 0.28))
	if _label != null:
		_label.modulate = color if on else Color(0.92, 0.95, 1.0)


func _process(delta: float) -> void:
	_t += delta * (7.0 if walking > 0.05 else 1.6)
	var swing := sin(_t) * 0.6 * walking
	for i in range(_legs.size()):
		_legs[i].rotation.x = swing * (1.0 if i == 0 else -1.0)
	for i in range(_arms.size()):
		_arms[i].rotation.x = -swing * 0.8 * (1.0 if i == 0 else -1.0)
	if _body != null:
		_body.position.y = absf(sin(_t)) * 0.04 * walking + (sin(_t) * 0.006 if walking <= 0.05 else 0.0)
