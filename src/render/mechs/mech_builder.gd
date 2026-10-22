class_name MechBuilder
extends RefCounted
## Generates a mech model from a frame entry and a loadout (Unit.loadout format), all in
## code. Silhouette comes from the frame's manufacturer, mech type and signature features
## (MechStyles); each mount gets an attachment point and every equipped weapon gets its own
## model from WeaponBuilder, so a weapon keeps its maker's look on any frame.
## The body is built about 1 unit tall, then scaled so its height equals the frame's Size.

## Weapon mount priority for placing weapons on the body, by weapon type.
const SLOT_PREFS := {
	"Launcher": ["shoulder_r", "shoulder_l", "back_r", "back_l", "hand_r", "hand_l"],
	"Melee": ["hand_r", "hand_l", "forearm_r", "forearm_l"],
	"Nexus": ["shoulder_l", "shoulder_r", "hand_l", "hand_r", "back_l"],
	"_aux": ["forearm_r", "forearm_l", "hand_l", "hand_r", "shoulder_r", "shoulder_l"],
	"_heavy": ["hand_r", "shoulder_r", "hand_l", "shoulder_l", "back_r"],
	"_default": ["hand_r", "hand_l", "shoulder_r", "shoulder_l", "back_r", "back_l"],
}

var _b: Dictionary
var _pal: Dictionary
var _m: MechModel
var _P: Material
var _S: Material
var _T: Material
var _G: Material


## `frame` is a lancer-data frame entry; `content` is used to look up weapon entries.
## Pass size to override the frame's Size (e.g. for NPCs).
static func build(frame: Dictionary, loadout: Dictionary, content: ContentDB, size_override: float = -1.0) -> MechModel:
	return MechBuilder.new()._build(frame, loadout, content, size_override)


func _build(frame: Dictionary, loadout: Dictionary, content: ContentDB, size_override: float) -> MechModel:
	_b = MechStyles.body(frame)
	var mfr: String = frame.get("source", "GMS")
	_pal = MechStyles.palette(mfr)
	_P = MeshKit.mech_material(_pal["primary"], _pal["metal"], _pal["rough"])
	_S = MeshKit.mech_material(_pal["secondary"], _pal["metal"], _pal["rough"])
	_T = MeshKit.mech_material(_pal["trim"], 0.8, 0.5, Color.BLACK, false)
	_G = MeshKit.mech_material(Color(0.05, 0.05, 0.05), 0.2, 0.2, _pal["glow"], false)
	_m = MechModel.new()
	_m.name = "Mech_" + String(frame.get("id", "unknown"))
	_m.frame_id = frame.get("id", "")
	_m.manufacturer = mfr
	var stats: Dictionary = frame.get("stats", {})
	_m.size = size_override if size_override > 0 else float(stats.get("size", 1))
	_m.gait = MechModel.gait_for(_m.frame_id)
	var body := Node3D.new()
	body.name = "Body"
	_m.add_child(body)
	var sculpted := MechAsset.has(_m.frame_id) or FrameSculpts.has(_m.frame_id)
	if MechAsset.has(_m.frame_id) and MechAsset.build(_m.frame_id, _m, body):
		pass
	elif FrameSculpts.has(_m.frame_id):
		FrameSculpts.sculpt(_m.frame_id, _m, body)
	else:
		_legs(body)
		_torso()
		_head()
		_arms()
	# Scale the body so its height (without antennas, wings...) matches the Size.
	var top := _top_of(body, Transform3D.IDENTITY)
	_m.height = _m.size * 0.95
	_m.root_scale = _m.height / maxf(top, 0.01)
	body.scale = Vector3.ONE * _m.root_scale
	if not sculpted:
		_features()
	if not MechAsset.has(_m.frame_id) and size_override <= 0.0:
		# Same draw-call diet as the Blender frames (the body only: weapons depend on loadout).
		MechAsset._merge(body, "code:" + String(_m.frame_id))
	_weapons(loadout, content)
	_m.collect_meshes()
	return _m


func _top_of(n: Node, xf: Transform3D) -> float:
	var best := 0.0
	for c in n.get_children():
		if not c is Node3D or c.has_meta("no_height"):
			continue
		var cx: Transform3D = xf * (c as Node3D).transform
		if c is MeshInstance3D:
			var aabb: AABB = cx * (c as MeshInstance3D).get_aabb()
			best = maxf(best, aabb.end.y)
		best = maxf(best, _top_of(c, cx))
	return best


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO, taper := 1.0, shear := 0.0) -> MeshInstance3D:
	return MeshKit.part(parent, MeshKit.chamfer_box(size, _b["bevel"], taper, shear), mat, pos, rot)


func _cyl(parent: Node3D, r: float, h: float, pos: Vector3, mat: Material, rot := Vector3.ZERO, sides := 12, top_r := -1.0) -> MeshInstance3D:
	return MeshKit.part(parent, MeshKit.cylinder(r, h, sides, top_r), mat, pos, rot)


func _pivot(parent: Node3D, name: String, pos: Vector3, rot := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = pos
	n.rotation_degrees = rot
	parent.add_child(n)
	return n


func _r(i: int) -> float:
	return MeshKit.hash01(_b["seed"], 100 + i)


# --- Body --------------------------------------------------------------------------------

func _legs(body: Node3D) -> void:
	var L: float = _b["leg_len"]
	var lt: float = _b["leg_thick"]
	var tw: float = _b["torso_w"]
	_m.pelvis = _pivot(body, "Pelvis", Vector3(0, L, 0))
	_m.pelvis.set_meta("rest_y", L)
	_box(_m.pelvis, Vector3(tw * 0.62, 0.08, _b["torso_d"] * 0.62), Vector3(0, 0.0, 0), _T)
	_box(_m.pelvis, Vector3(tw * 0.5, 0.07, 0.04), Vector3(0, -0.01, -_b["torso_d"] * 0.33), _S)
	for s: float in [-1.0, 1.0]:
		var hip := _pivot(_m.pelvis, "Hip", Vector3(s * tw * 0.3, -0.02, 0))
		_cyl(hip, lt * 0.55, lt * 1.3, Vector3.ZERO, _T, Vector3(0, 0, 90), 10)
		var knee: Node3D
		var ankle: Node3D
		var base: Vector3
		if _b["digi"]:
			var x := (L - 0.04) / 0.983
			var a := 0.4 * x
			var c := 0.3 * x
			hip.rotation_degrees.x = 30.0
			_box(hip, Vector3(lt * 1.1, a, lt * 1.3), Vector3(0, -a / 2.0, 0), _P, Vector3.ZERO, 1.25)
			knee = _pivot(hip, "Knee", Vector3(0, -a, 0), Vector3(-60, 0, 0))
			_cyl(knee, lt * 0.5, lt * 1.1, Vector3.ZERO, _T, Vector3(0, 0, 90), 10)
			_box(knee, Vector3(lt * 0.9, a, lt), Vector3(0, -a / 2.0, 0), _P, Vector3.ZERO, 0.8)
			_box(knee, Vector3(lt * 0.6, a * 0.7, 0.02), Vector3(0, -a * 0.45, lt * 0.55), _S)
			ankle = _pivot(knee, "Ankle", Vector3(0, -a, 0), Vector3(45, 0, 0))
			_box(ankle, Vector3(lt * 0.7, c, lt * 0.7), Vector3(0, -c / 2.0, 0), _T)
			var foot := _pivot(ankle, "Foot", Vector3(0, -c, 0), Vector3(-15, 0, 0))
			_box(foot, Vector3(lt * 1.3, 0.045, lt * 2.4), Vector3(0, -0.015, -lt * 0.5), _S, Vector3.ZERO, 0.8)
			base = Vector3(30, -60, 45)
		else:
			var half := L * 0.5
			_box(hip, Vector3(lt, half * 1.05, lt * 1.15), Vector3(0, -half / 2.0, 0), _T)
			_box(hip, Vector3(lt * 1.15, half * 0.8, lt * 0.5), Vector3(s * 0.005, -half * 0.5, -lt * 0.4), _P, Vector3.ZERO, 1.1)
			knee = _pivot(hip, "Knee", Vector3(0, -half, 0))
			_box(knee, Vector3(lt * 0.95, lt * 0.7, lt * 0.6), Vector3(0, 0, -lt * 0.45), _S)
			var shin := half - 0.04
			_box(knee, Vector3(lt * 1.2, shin, lt * 1.35), Vector3(0, -shin / 2.0, 0), _P, Vector3.ZERO, 0.85)
			ankle = _pivot(knee, "Ankle", Vector3(0, -shin, 0))
			_box(ankle, Vector3(lt * 1.35, 0.05, lt * 2.3), Vector3(0, -0.015, -lt * 0.45), _T, Vector3.ZERO, 0.85)
			_box(ankle, Vector3(lt * 1.1, 0.03, lt * 0.8), Vector3(0, 0.02, -lt * 1.1), _S)
			base = Vector3.ZERO
		_m.legs.append({"hip": hip, "knee": knee, "ankle": ankle, "base": base})


func _torso() -> void:
	var tw: float = _b["torso_w"]
	var th: float = _b["torso_h"]
	var td: float = _b["torso_d"]
	_m.torso = _pivot(_m.pelvis, "Torso", Vector3(0, 0.03, 0), Vector3(-float(_b["hunch"]), 0, 0))
	_box(_m.torso, Vector3(tw * 0.45, 0.07, td * 0.5), Vector3(0, 0.03, 0), _T)
	_box(_m.torso, Vector3(tw, th, td), Vector3(0, 0.06 + th / 2.0, 0), _P, Vector3.ZERO, _b["taper"])
	match _m.manufacturer:
		"IPS-N":
			# Thick chest plate and a lower armored skirt.
			_box(_m.torso, Vector3(tw * 0.75, th * 0.6, 0.05), Vector3(0, 0.06 + th * 0.55, -td / 2.0 - 0.01), _S, Vector3(-8, 0, 0))
			_box(_m.torso, Vector3(tw * 0.9, 0.06, td * 1.05), Vector3(0, 0.08, 0), _S)
		"SSC":
			# Narrow waist, swept chest with a gold keel.
			_box(_m.torso, Vector3(0.03, th * 0.8, td * 0.4), Vector3(0, 0.06 + th * 0.5, -td / 2.0), _S, Vector3.ZERO, 0.5)
		"HORUS":
			# Lopsided plates and an exposed core.
			_box(_m.torso, Vector3(tw * 0.55, th * 0.7, 0.04), Vector3(tw * 0.18, 0.06 + th * 0.55, -td / 2.0 - 0.01), _S, Vector3(0, 12, -6), 0.7)
			_cyl(_m.torso, td * 0.14, 0.03, Vector3(-tw * 0.18, 0.06 + th * 0.45, -td / 2.0 - 0.005), _G, Vector3(90, 0, 0), 6)
		"HA":
			# Wide chest with a glowing reactor vent.
			_box(_m.torso, Vector3(tw * 0.6, th * 0.45, 0.04), Vector3(0, 0.06 + th * 0.6, -td / 2.0 - 0.012), _S, Vector3(-10, 0, 0), 0.8)
			_box(_m.torso, Vector3(tw * 0.35, 0.03, 0.02), Vector3(0, 0.06 + th * 0.3, -td / 2.0 - 0.01), _G)
		_:
			_box(_m.torso, Vector3(tw * 0.6, th * 0.5, 0.035), Vector3(0, 0.06 + th * 0.58, -td / 2.0 - 0.008), _S, Vector3(-6, 0, 0))
	# Back pack: every frame has one, sized by manufacturer.
	_box(_m.torso, Vector3(tw * 0.6, th * 0.65, td * 0.35), Vector3(0, 0.06 + th * 0.55, td / 2.0 + td * 0.12), _T)
	for i in range(2):
		_cyl(_m.torso, 0.025, 0.05, Vector3((i - 0.5) * tw * 0.3, 0.06 + th * 0.35, td / 2.0 + td * 0.3), _T, Vector3(90, 0, 0), 8)


func _head() -> void:
	var th: float = _b["torso_h"]
	var td: float = _b["torso_d"]
	var hs: float = _b["head_size"]
	var y := 0.06 + th
	_m.head = _pivot(_m.torso, "Head", Vector3(0, y, -td * 0.12))
	var eye_pos := Vector3(0, hs * 0.5, -hs * 0.7)
	match String(_b["head"]):
		"sunk":
			_m.head.position.y -= hs * 0.25
			_box(_m.head, Vector3(hs * 1.4, hs * 0.75, hs * 1.2), Vector3(0, hs * 0.38, 0), _P)
			_box(_m.head, Vector3(hs * 1.7, hs * 0.35, hs * 1.3), Vector3(0, hs * 0.1, 0.01), _S)
			_box(_m.head, Vector3(hs * 0.9, hs * 0.12, 0.01), Vector3(0, hs * 0.45, -hs * 0.61), _G)
			eye_pos = Vector3(0, hs * 0.45, -hs * 0.65)
		"long":
			_box(_m.head, Vector3(hs * 0.8, hs * 0.7, hs * 1.7), Vector3(0, hs * 0.4, -hs * 0.2), _P, Vector3(0, 0, 0), 0.7)
			_cyl(_m.head, hs * 0.16, 0.02, Vector3(0, hs * 0.45, -hs * 1.06), _G, Vector3(90, 0, 0), 10)
			_box(_m.head, Vector3(0.012, hs * 0.5, hs * 1.2), Vector3(0, hs * 0.85, 0), _S, Vector3.ZERO, 0.3)
			eye_pos = Vector3(0, hs * 0.45, -hs * 1.1)
		"slit":
			_box(_m.head, Vector3(hs, hs * 1.0, hs), Vector3(0, hs * 0.5, 0), _P, Vector3(0, 45, 0), 0.75)
			for i in range(3):
				var p := Vector3((i - 1) * hs * 0.22 + hs * 0.05, hs * (0.45 + 0.12 * (i % 2)), -hs * 0.72)
				MeshKit.part(_m.head, MeshKit.sphere(hs * 0.08, 8), _G, p)
			eye_pos = Vector3(0, hs * 0.5, -hs * 0.75)
		"crest":
			_box(_m.head, Vector3(hs * 1.1, hs * 0.85, hs * 1.1), Vector3(0, hs * 0.42, 0), _P, Vector3.ZERO, 0.8)
			_box(_m.head, Vector3(0.02, hs * 0.6, hs * 1.3), Vector3(0, hs * 0.95, 0.01), _S, Vector3.ZERO, 0.4)
			_box(_m.head, Vector3(hs * 0.8, hs * 0.1, 0.01), Vector3(0, hs * 0.5, -hs * 0.56), _G)
			_box(_m.head, Vector3(hs * 0.1, hs * 0.35, 0.01), Vector3(0, hs * 0.35, -hs * 0.56), _G)
		_:
			_box(_m.head, Vector3(hs * 1.2, hs, hs * 1.2), Vector3(0, hs * 0.5, 0), _P, Vector3.ZERO, 0.9)
			_box(_m.head, Vector3(hs * 1.05, hs * 0.24, 0.012), Vector3(0, hs * 0.55, -hs * 0.6), _G)
			_box(_m.head, Vector3(hs * 1.3, hs * 0.2, hs * 0.5), Vector3(0, hs * 0.1, hs * 0.2), _S)
	_m.eye = Marker3D.new()
	_m.eye.name = "Eye"
	_m.eye.position = eye_pos
	_m.head.add_child(_m.eye)


func _arms() -> void:
	var tw: float = _b["torso_w"]
	var th: float = _b["torso_h"]
	var td: float = _b["torso_d"]
	var at: float = _b["arm_thick"]
	var al: float = _b["arm_len"]
	var pad: float = _b["pad_size"]
	for s: float in [-1.0, 1.0]:
		var side := "r" if s > 0 else "l"
		var sy := 0.06 + th - 0.05
		var shoulder := _pivot(_m.torso, "Shoulder_" + side, Vector3(s * (tw / 2.0 + at * 0.55), sy, 0))
		_cyl(shoulder, at * 0.6, at * 1.2, Vector3.ZERO, _T, Vector3(0, 0, 90), 10)
		# Shoulder pad, in the manufacturer's shape (fixed to the torso so it doesn't swing).
		var pad_node := _pivot(_m.torso, "Pad_" + side, shoulder.position)
		match String(_b["pad"]):
			"round":
				_cyl(pad_node, at * 0.85 * pad, at * 1.5 * pad, Vector3(s * at * 0.3, at * 0.35, 0), _P, Vector3(0, 0, 90), 14)
				_cyl(pad_node, at * 0.9 * pad, at * 0.3, Vector3(s * at * (0.3 + 0.75 * pad), at * 0.35, 0), _S, Vector3(0, 0, 90), 14)
			"fin":
				_box(pad_node, Vector3(0.02, at * 3.0 * pad, at * 1.8), Vector3(s * at * 0.9, at * 0.9, 0.02), _P, Vector3(0, 0, -s * 18), 0.4)
				_box(pad_node, Vector3(at * 1.4, at * 0.6, at * 1.6), Vector3(s * at * 0.3, at * 0.4, 0), _S, Vector3.ZERO, 0.8)
			"spike":
				_box(pad_node, Vector3(at * 1.8 * pad, at * 0.9, at * 1.9), Vector3(s * at * 0.4, at * 0.5, 0), _P, Vector3(0, 0, -s * 12), 0.7)
				_box(pad_node, Vector3(at * 0.5, at * 1.8 * pad, at * 0.5), Vector3(s * at * 0.9, at * 1.4, 0.0), _S, Vector3(0, 0, -s * 25), 0.1)
			"slab":
				_box(pad_node, Vector3(at * 1.8 * pad, at * 1.0, at * 2.0 * pad), Vector3(s * at * 0.4, at * 0.5, 0), _P, Vector3(0, 0, -s * 10), 0.75, 0.02)
				_box(pad_node, Vector3(at * 0.12, at * 0.35, at * 1.2 * pad), Vector3(s * at * 1.35 * pad, at * 0.35, 0), _G)
			_:
				_box(pad_node, Vector3(at * 2.0 * pad, at * 1.2, at * 2.1 * pad), Vector3(s * at * 0.35, at * 0.45, 0), _P, Vector3(0, 0, -s * 8), 0.85)
				_box(pad_node, Vector3(at * 0.25, at * 0.5, at * 1.6 * pad), Vector3(s * at * 1.4 * pad, at * 0.4, 0), _S)
		_box(shoulder, Vector3(at, al, at), Vector3(0, -al / 2.0, 0), _T)
		_box(shoulder, Vector3(at * 1.15, al * 0.7, at * 1.1), Vector3(s * at * 0.08, -al * 0.45, 0), _P, Vector3.ZERO, 1.1)
		var elbow := _pivot(shoulder, "Elbow", Vector3(0, -al, 0))
		_cyl(elbow, at * 0.5, at * 1.05, Vector3.ZERO, _T, Vector3(0, 0, 90), 10)
		_box(elbow, Vector3(at * 1.25, al, at * 1.3), Vector3(0, -al / 2.0, 0), _P, Vector3.ZERO, 0.85)
		_box(elbow, Vector3(at * 0.3, al * 0.6, at * 0.9), Vector3(s * at * 0.7, -al * 0.5, 0), _S)
		var hand := _pivot(elbow, "Hand", Vector3(0, -al - at * 0.35, 0))
		_box(hand, Vector3(at * 0.9, at * 0.7, at * 0.9), Vector3.ZERO, _T)
		var hand_slot := _pivot(hand, "Slot_hand_" + side, Vector3(0, -at * 0.2, 0), Vector3(-90, 0, 0))
		var forearm_slot := _pivot(elbow, "Slot_forearm_" + side, Vector3(s * at * 0.85, -al * 0.6, 0), Vector3(-90, 0, 0))
		var shoulder_slot := _pivot(pad_node, "Slot_shoulder_" + side, Vector3(s * at * 0.4, at * 1.0 + 0.03, 0))
		var back_slot := _pivot(_m.torso, "Slot_back_" + side, Vector3(s * tw * 0.28, 0.06 + th + 0.04, td * 0.45))
		_m.slots["hand_" + side] = hand_slot
		_m.slots["forearm_" + side] = forearm_slot
		_m.slots["shoulder_" + side] = shoulder_slot
		_m.slots["back_" + side] = back_slot
		var rest_sh := Vector3(4, 0, s * 6)
		var rest_el := Vector3(18, 0, 0)
		shoulder.rotation_degrees = rest_sh
		elbow.rotation_degrees = rest_el
		_m.arms[side] = {"shoulder": shoulder, "elbow": elbow, "hand": hand, "rest_shoulder": rest_sh, "rest_elbow": rest_el}


# --- Weapons -----------------------------------------------------------------------------

func _weapons(loadout: Dictionary, content: ContentDB) -> void:
	var list: Array = []
	for mount: Dictionary in loadout.get("mounts", []):
		for wid: String in mount.get("weapons", []):
			var w := content.weapon(wid) if content else {}
			if not w.is_empty():
				list.append(w)
	var order := {"Superheavy": 0, "Heavy": 1, "Main": 2, "Auxiliary": 3}
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return order.get(a.get("mount"), 2) < order.get(b.get("mount"), 2))
	for w: Dictionary in list:
		var type: String = w.get("type", "")
		var prefs: Array = SLOT_PREFS.get(type, [])
		if prefs.is_empty():
			match String(w.get("mount", "")):
				"Auxiliary":
					prefs = SLOT_PREFS["_aux"]
				"Heavy", "Superheavy":
					prefs = SLOT_PREFS["_heavy"]
				_:
					prefs = SLOT_PREFS["_default"]
		if type == "Melee" and _m.has_meta("melee_hand"):
			var mh: String = _m.get_meta("melee_hand")
			prefs = ["hand_" + mh, "hand_" + ("r" if mh == "l" else "l")]
		elif w.get("mount") == "Auxiliary" and type == "Melee":
			prefs = ["forearm_l", "forearm_r", "hand_l", "hand_r"]
			if _m.has_meta("custom_pose"):
				prefs = ["hand_l", "hand_r", "forearm_l", "forearm_r"]
		var slot := ""
		for p: String in prefs:
			if not _m.slot_weapon.has(p):
				slot = p
				break
		if slot == "":
			continue
		var model := WeaponBuilder.build(w)
		(_m.slots[slot] as Node3D).add_child(model)
		_m.slot_weapon[slot] = w["id"]
		if not _m.weapons.has(w["id"]):
			_m.weapons[w["id"]] = model
		# Hand-held guns: hold the forearm forward, ready to fire. Sculpted frames with their
		# own pose (from their art) keep it.
		if slot.begins_with("hand_") and not _m.has_meta("custom_pose") and type != "Melee":
			var arm: Dictionary = _m.arms[slot.substr(5)]
			arm["rest_shoulder"] = Vector3(8, 0, 0)
			arm["rest_elbow"] = Vector3(78, 0, 0)
			(arm["shoulder"] as Node3D).rotation_degrees = arm["rest_shoulder"]
			(arm["elbow"] as Node3D).rotation_degrees = arm["rest_elbow"]


# --- Signature features ------------------------------------------------------------------

func _features() -> void:
	var tw: float = _b["torso_w"]
	var th: float = _b["torso_h"]
	var td: float = _b["torso_d"]
	var hs: float = _b["head_size"]
	var top := 0.06 + th
	var back := td / 2.0 + td * 0.3
	var t := _m.torso
	var h := _m.head
	for f: String in _b["features"]:
		match f:
			"antenna":
				_cyl(h, 0.005, 0.18, Vector3(hs * 0.5, hs * 1.0, hs * 0.2), _T, Vector3(0, 0, -10), 4)
			"antennae":
				for s: float in [-1.0, 1.0]:
					_cyl(h, 0.005, 0.2, Vector3(s * hs * 0.45, hs * 1.0, hs * 0.2), _T, Vector3(-15, 0, -s * 20), 4)
			"grapple_arms":
				for s: float in [-1.0, 1.0]:
					var g := _pivot(t, "Grapple", Vector3(s * tw * 0.35, top * 0.8, back), Vector3(-30, 0, -s * 30))
					_box(g, Vector3(0.04, 0.22, 0.04), Vector3(0, 0.11, 0), _T)
					_box(g, Vector3(0.07, 0.06, 0.07), Vector3(0, 0.24, 0), _S)
					for k in [-1.0, 1.0]:
						_box(g, Vector3(0.015, 0.08, 0.02), Vector3(k * 0.025, 0.3, 0), _T, Vector3(0, 0, -k * 15), 0.3)
			"spikes", "spike_crown":
				var n := 3 if f == "spikes" else 6
				for i in range(n):
					var a := (i - (n - 1) / 2.0) / maxf(1.0, n - 1.0)
					_box(t, Vector3(0.025, 0.12 if f == "spikes" else 0.18, 0.025), Vector3(a * tw * 0.9, top + 0.04, back * 0.7), _S, Vector3(25, 0, -a * 50), 0.1)
			"tower_shield":
				var arm: Dictionary = _m.arms["l"]
				_box(arm["elbow"], Vector3(0.03, 0.36, 0.22), Vector3(-0.06, -0.12, -0.02), _P, Vector3(0, 0, 0), 0.9)
				_box(arm["elbow"], Vector3(0.035, 0.3, 0.04), Vector3(-0.065, -0.12, -0.02), _S)
			"cargo_crane":
				var c := _pivot(t, "Crane", Vector3(tw * 0.25, top, back), Vector3(-20, 0, 0))
				_box(c, Vector3(0.04, 0.3, 0.04), Vector3(0, 0.15, 0), _S)
				_box(c, Vector3(0.035, 0.035, 0.22), Vector3(0, 0.3, -0.1), _S)
				_cyl(c, 0.003, 0.1, Vector3(0, 0.25, -0.2), _T, Vector3.ZERO, 4)
			"crest":
				_box(h, Vector3(0.015, hs * 0.9, hs * 1.6), Vector3(0, hs * 1.1, hs * 0.2), _S, Vector3(-10, 0, 0), 0.3)
			"spear_fins", "stabilizers":
				for s: float in [-1.0, 1.0]:
					_box(t, Vector3(0.02, 0.06, 0.3), Vector3(s * tw * 0.3, top * 0.75, back + 0.1), _S, Vector3(-25, s * 15, 0), 0.4)
			"cowl":
				_box(h, Vector3(hs * 1.6, hs * 0.5, hs * 1.6), Vector3(0, hs * 1.0, 0.0), _S, Vector3(-8, 0, 0), 0.6)
			"bandolier":
				for i in range(5):
					_box(t, Vector3(0.035, 0.05, 0.03), Vector3(-tw * 0.35 + i * tw * 0.17, top * 0.35 + i * th * 0.12, -td / 2.0 - 0.02), _S, Vector3(0, 0, 35))
			"sensor_mast":
				_cyl(t, 0.008, 0.35, Vector3(-tw * 0.3, top + 0.15, back), _T, Vector3.ZERO, 6)
				_cyl(t, 0.05, 0.01, Vector3(-tw * 0.3, top + 0.32, back), _S, Vector3(60, 0, 0), 12)
			"halo_ring":
				var ring := _pivot(t, "Halo", Vector3(0, top + 0.05, back + 0.06), Vector3(80, 0, 0))
				var tm := TorusMesh.new()
				tm.inner_radius = tw * 0.55
				tm.outer_radius = tw * 0.62
				tm.rings = 32
				tm.ring_segments = 8
				MeshKit.part(ring, tm, _G)
				_m.spinners.append({"node": ring, "axis": Vector3.UP, "speed": 0.8})
			"sniper_head":
				_box(h, Vector3(hs * 0.5, hs * 0.5, hs * 1.6), Vector3(hs * 0.45, hs * 0.55, -hs * 0.5), _S)
				_cyl(h, hs * 0.18, 0.02, Vector3(hs * 0.45, hs * 0.55, -hs * 1.31), _G, Vector3(90, 0, 0), 10)
			"wings":
				for s: float in [-1.0, 1.0]:
					var wpiv := _pivot(t, "Wing", Vector3(s * tw * 0.25, top * 0.85, back), Vector3(-15, s * 20, -s * 35))
					_box(wpiv, Vector3(0.38, 0.02, 0.16), Vector3(s * 0.19, 0, 0), _P, Vector3.ZERO, 0.6)
					_box(wpiv, Vector3(0.36, 0.022, 0.015), Vector3(s * 0.19, 0, -0.07), _G)
			"cloak_fins":
				for i in range(4):
					var a := (i - 1.5) / 1.5
					_box(t, Vector3(0.09, 0.45, 0.015), Vector3(a * tw * 0.35, top * 0.3, back + 0.05), _P if i % 2 else _S, Vector3(18, a * 15, a * 6), 0.5)
			"arm_blades":
				for s: String in ["r", "l"]:
					_box(_m.arms[s]["elbow"], Vector3(0.012, 0.32, 0.04), Vector3(0, -0.2, 0.05), _G, Vector3(0, 0, 0), 0.2)
			"missile_pods":
				for s: float in [-1.0, 1.0]:
					var pod := _pivot(t, "Pod", Vector3(s * tw * 0.42, top + 0.08, back * 0.6))
					_box(pod, Vector3(0.16, 0.12, 0.2), Vector3.ZERO, _S, Vector3(-10, 0, 0))
					for k in range(6):
						_cyl(pod, 0.016, 0.01, Vector3((k % 3 - 1) * 0.045, (k / 3 - 0.5) * 0.05, -0.1), _T, Vector3(90, 0, 0), 6)
			"nanite_cloud", "drone_orbit":
				var cloud := _pivot(t, "Orbit", Vector3(0, top * 0.6, 0))
				var count := 10 if f == "nanite_cloud" else 3
				for i in range(count):
					var ang := TAU * i / count
					var r := tw * (0.95 + 0.25 * _r(i))
					var p := Vector3(cos(ang) * r, (_r(i + 20) - 0.5) * th, sin(ang) * r)
					if f == "nanite_cloud":
						MeshKit.part(cloud, MeshKit.chamfer_box(Vector3.ONE * 0.03, 0.005), _G, p, Vector3(_r(i) * 90, _r(i + 5) * 90, 0))
					else:
						_box(cloud, Vector3(0.08, 0.025, 0.08), p, _P)
						MeshKit.part(cloud, MeshKit.sphere(0.012, 6), _G, p + Vector3(0, -0.015, 0))
				_m.spinners.append({"node": cloud, "axis": Vector3.UP, "speed": 0.6 if f == "drone_orbit" else 1.2})
			"tail":
				var tail := _pivot(_m.pelvis, "Tail", Vector3(0, 0.0, _b["torso_d"] * 0.35), Vector3(-60, 0, 0))
				var parent := tail
				for i in range(6):
					_box(parent, Vector3(0.04 - i * 0.004, 0.07, 0.04 - i * 0.004), Vector3(0, 0.035, 0), _P if i % 2 else _T)
					parent = _pivot(parent, "Seg", Vector3(0, 0.07, 0), Vector3(-14, 0, 0))
				_box(parent, Vector3(0.02, 0.07, 0.02), Vector3(0, 0.035, 0), _G, Vector3.ZERO, 0.1)
			"pylons":
				for i in range(3):
					var x := (i - 1) * tw * 0.3
					_box(t, Vector3(0.03, 0.26, 0.03), Vector3(x, top + 0.05, back), _T, Vector3(-10, 0, (i - 1) * -12))
					MeshKit.part(t, MeshKit.sphere(0.02, 8), _G, Vector3(x * 1.4, top + 0.19, back - 0.02))
			"horns":
				for s: float in [-1.0, 1.0]:
					_box(h, Vector3(0.025, 0.14, 0.025), Vector3(s * hs * 0.6, hs * 0.95, -hs * 0.1), _S, Vector3(-30, 0, -s * 40), 0.15)
			"serpent_heads":
				for s: float in [-1.0, 1.0]:
					var neck := _pivot(t, "Neck", Vector3(s * tw * 0.3, top, back * 0.3), Vector3(-10, 0, -s * 30))
					_box(neck, Vector3(0.04, 0.16, 0.04), Vector3(0, 0.08, 0), _T)
					_box(neck, Vector3(0.06, 0.05, 0.1), Vector3(0, 0.17, -0.03), _P, Vector3(0, 0, s * 30), 0.7)
					MeshKit.part(neck, MeshKit.sphere(0.012, 6), _G, Vector3(0, 0.18, -0.08))
			"orbit_ring":
				var oring := _pivot(t, "Ring", Vector3(0, top * 0.55, 0), Vector3(8, 0, 0))
				var tor := TorusMesh.new()
				tor.inner_radius = tw * 0.82
				tor.outer_radius = tw * 0.88
				tor.rings = 40
				tor.ring_segments = 6
				MeshKit.part(oring, tor, _S)
				_box(oring, Vector3(0.05, 0.04, 0.14), Vector3(tw * 0.85, 0, 0), _T)
				_m.spinners.append({"node": oring, "axis": Vector3.UP, "speed": 0.35})
			"reactor_back", "siege_frame":
				_cyl(t, td * 0.32, th * 0.9, Vector3(0, top * 0.6, back + td * 0.18), _S, Vector3.ZERO, 12)
				_cyl(t, td * 0.33, 0.012, Vector3(0, top * 0.65, back + td * 0.18), _G, Vector3.ZERO, 12)
				if f == "siege_frame":
					for s: float in [-1.0, 1.0]:
						_box(t, Vector3(0.04, th * 1.4, 0.04), Vector3(s * tw * 0.45, top * 0.8, back + 0.05), _T, Vector3(-12, 0, -s * 8))
					_cyl(t, 0.04, 0.2, Vector3(tw * 0.2, top + 0.2, back + 0.08), _T, Vector3.ZERO, 8)
			"fuel_tanks":
				for s: float in [-1.0, 1.0]:
					_cyl(t, 0.05, th * 0.85, Vector3(s * tw * 0.2, top * 0.6, back + 0.04), _S, Vector3.ZERO, 12)
					_cyl(t, 0.052, 0.03, Vector3(s * tw * 0.2, top * 0.75, back + 0.04), _G, Vector3.ZERO, 12)
			"mine_racks":
				for s: float in [-1.0, 1.0]:
					for i in range(3):
						_cyl(_m.pelvis, 0.03, 0.015, Vector3(s * tw * 0.42, -0.03 - i * 0.035, 0), _S, Vector3(0, 0, 90), 10)
			"shield_emitters":
				for i in range(3):
					var x := (i - 1) * tw * 0.35
					_box(t, Vector3(0.025, 0.2, 0.025), Vector3(x, top + 0.06, back), _T, Vector3(-15, 0, (i - 1) * -20))
					MeshKit.part(t, MeshKit.sphere(0.03, 8), _G, Vector3(x * 1.3, top + 0.16, back - 0.02))
			"heat_fins":
				for i in range(5):
					_box(t, Vector3(tw * 0.7, 0.012, 0.09), Vector3(0, top * 0.35 + i * th * 0.15, back + 0.05), _S)
				_box(t, Vector3(tw * 0.5, th * 0.7, 0.01), Vector3(0, top * 0.6, back + 0.02), _G)
