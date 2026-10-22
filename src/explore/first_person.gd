class_name FirstPerson
extends Node
## Walking around a hub in first person (V switches, any time, like the mech cockpit view).
## Look at a person or a door and use it: E talks or goes in; while sneaking (C), E on someone
## tries to lift what they carry and on a locked door picks the lock, R puts someone down or
## forces a door. Everything goes through the StoryEngine's town actions (TownLife), so it's
## the same checks and witnesses as anywhere else. The camera sits at eye height (lower while
## sneaking), with a crosshair, a prompt for what you're looking at, a stealth indicator, and
## your arms in view when you use something.

const EYE := 1.62
const CROUCH_EYE := 1.05
const REACH := 3.2
const AIM := 0.22  # how close to the crosshair (radians) something has to be

var enabled := false
var sneaking := false
var pitch := 0.0
var target: Dictionary = {}  # {kind: "npc"|"door", id, spot, name}
var inside_prompt := ""  # inside a building: what's in reach (a door, something to take)

var _ui: Control
var _cross: Control
var _prompt: Label
var _stealth: Label
var _arms: Node3D
var _use_t := 0.0


func _init() -> void:
	name = "FirstPerson"


## The overlay (crosshair, prompt, stealth) on the hub's UI layer.
func attach(ui_layer: CanvasLayer) -> void:
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.visible = false
	ui_layer.add_child(_ui)
	_cross = Control.new()
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cross.draw.connect(_draw_cross)
	_ui.add_child(_cross)
	_prompt = StoryStyle.label("", 16, Color.WHITE)
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ui.add_child(_prompt)
	_stealth = StoryStyle.label("", 15, StoryStyle.GREEN)
	_stealth.add_theme_constant_override("outline_size", 5)
	_stealth.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_ui.add_child(_stealth)


func set_enabled(on: bool, cam: Camera3D) -> void:
	enabled = on
	if _ui != null:
		_ui.visible = on
	if on and _arms == null and cam != null:
		_arms = _make_arms()
		cam.add_child(_arms)
	if _arms != null:
		_arms.visible = on
	if not on:
		sneaking = false
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


## Simple forearms and hands, low in view; they reach forward when you use something.
func _make_arms() -> Node3D:
	var root := Node3D.new()
	var sleeve := MeshKit.paint(Color(0.24, 0.28, 0.3), 0.8)
	var glove := MeshKit.paint(Color(0.12, 0.12, 0.13), 0.7)
	for side: float in [-1.0, 1.0]:
		var arm := Node3D.new()
		arm.name = "Arm%s" % ("L" if side < 0 else "R")
		arm.position = Vector3(0.26 * side, -0.34, -0.42)
		arm.rotation = Vector3(deg_to_rad(-12), deg_to_rad(8 * -side), 0)
		MeshKit.part(arm, MeshKit.chamfer_box(Vector3(0.09, 0.09, 0.42), 0.02), sleeve, Vector3(0, 0, 0.1))
		MeshKit.part(arm, MeshKit.chamfer_box(Vector3(0.08, 0.06, 0.1), 0.02), glove, Vector3(0, 0, -0.15))
		root.add_child(arm)
	return root


func look(rel: Vector2, yaw: float) -> float:
	pitch = clampf(pitch - rel.y * 0.003, deg_to_rad(-60), deg_to_rad(60))
	return yaw - rel.x * 0.003


func eye_height() -> float:
	return CROUCH_EYE if sneaking else EYE


## Puts the camera in the pilot's eyes.
func place_camera(cam: Camera3D, me: Node3D, yaw: float, delta: float) -> void:
	var eye := me.position + Vector3(0, eye_height(), 0)
	cam.position = cam.position.lerp(eye, clampf(delta * 14.0, 0.0, 1.0)) if cam.position.distance_to(eye) < 3.0 else eye
	cam.rotation = Vector3(pitch, yaw, 0)
	me.visible = false
	if _use_t > 0.0:
		_use_t -= delta
	if _arms != null:
		var reach := 0.12 * sin(clampf(_use_t, 0.0, 0.3) / 0.3 * PI)
		for a: Node in _arms.get_children():
			(a as Node3D).position.z = -0.42 - reach


func used() -> void:
	_use_t = 0.3


## What's under the crosshair: the nearest person or building door in reach and in view.
func pick(cam: Camera3D, npcs: Dictionary, spots: Array, story: StoryState) -> Dictionary:
	var fwd := -cam.global_transform.basis.z
	var best: Dictionary = {}
	var best_a := AIM
	for id: String in npcs:
		var fig := npcs[id] as Node3D
		if not fig.visible:
			continue
		var to := (fig.position + Vector3(0, 1.3, 0)) - cam.position
		if to.length() > REACH:
			continue
		var a := fwd.angle_to(to)
		if a < best_a:
			best_a = a
			best = {"kind": "npc", "id": id, "name": str(story.npcs.get(id, {}).get("name", ""))}
	for s: Dictionary in spots:
		if not s.has("door") or str(s.get("kind", "")) in ["plaza", "landing"]:
			continue
		var door := Vector3(float(s["door"][0]), 1.2, float(s["door"][1]))
		var to := door - cam.position
		if to.length() > REACH:
			continue
		var a := fwd.angle_to(to)
		if a < best_a:
			best_a = a
			best = {"kind": "door", "id": str(s["id"]), "spot": str(s["id"]), "name": str(s.get("name", s["id"]))}
	target = best
	return best


## The prompt for what you're looking at, and how exposed you are while sneaking.
func show(story: StoryState, me_pid: String, near_room: String) -> void:
	if _ui == null:
		return
	var vp := _ui.get_viewport_rect().size
	_cross.position = Vector2.ZERO
	_cross.size = vp
	_cross.queue_redraw()
	var t := ""
	if target.get("kind", "") == "npc":
		var id := str(target["id"])
		var carries := (story.flags.get("_items", {}) as Dictionary).values().any(func(it: Dictionary) -> bool:
			return str(it["owner"]) == id and str(it["kept"]) == "person" and str(it["holder"]) == "")
		t = "[E] Talk to %s" % target["name"]
		if sneaking:
			t = ("[E] Lift what %s carries   " % target["name"] if carries else "") + "[R] Put them down quietly"
	elif target.get("kind", "") == "door":
		var spot := str(target["spot"])
		var priv: Array = (TownLife.data().get("rooms", {}).get(TownLife.spot_kind(story, spot), {}) as Dictionary).keys().filter(func(r: String) -> bool:
			return not bool(TownLife.room_info(TownLife.spot_kind(story, spot), r).get("public", false)))
		t = "[E] Go into %s" % target["name"]
		if sneaking and not priv.is_empty():
			t = "[E] Slip into %s, %s   [R] Force the door" % [target["name"], TownLife.room_name(story, spot, str(priv[0]))]
	if t == "" and inside_prompt != "":
		t = inside_prompt
	_prompt.text = t
	_prompt.reset_size()
	_prompt.position = Vector2((vp.x - _prompt.size.x) / 2.0, vp.y * 0.5 + 34)
	_stealth.visible = sneaking
	if sneaking:
		var at := TownLife.pilot_at(story, me_pid)
		var seen: Array = TownLife.present(story, str(at["spot"]), near_room if near_room != "" else str(at["room"]))
		var crowd := int(TownLife.data().get("crowd", {}).get(TownLife.period(story), 1))
		if seen.is_empty() and crowd == 0:
			_stealth.text = "◌ SNEAKING · unseen (%s)" % TownLife.period_name(story).to_lower()
			_stealth.add_theme_color_override("font_color", StoryStyle.GREEN)
		else:
			_stealth.text = "◉ SNEAKING · %s could see you" % (story.npcs[seen[0]]["name"] if not seen.is_empty() else "people about")
			_stealth.add_theme_color_override("font_color", StoryStyle.GOLD)
		_stealth.reset_size()
		_stealth.position = Vector2((vp.x - _stealth.size.x) / 2.0, vp.y * 0.5 + 64)


func _draw_cross() -> void:
	var c := _cross.size / 2.0
	var col := StoryStyle.GOLD if not target.is_empty() else Color(1, 1, 1, 0.75)
	_cross.draw_line(c + Vector2(-9, 0), c + Vector2(-3, 0), col, 2.0)
	_cross.draw_line(c + Vector2(3, 0), c + Vector2(9, 0), col, 2.0)
	_cross.draw_line(c + Vector2(0, -9), c + Vector2(0, -3), col, 2.0)
	_cross.draw_line(c + Vector2(0, 3), c + Vector2(0, 9), col, 2.0)
	if not target.is_empty():
		_cross.draw_arc(c, 14, 0, TAU, 24, col, 1.5)
