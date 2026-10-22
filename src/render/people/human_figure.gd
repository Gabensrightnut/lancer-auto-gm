class_name HumanFigure
extends Node3D
## A person: the rigged human from tools/blender/human.py (assets/people/human.glb) dressed
## and colored from a v2 portrait (PortraitSpec), so the 3D figure matches the portrait:
## build and face shape, hair, beard, inner/outer outfit (flight suit, jacket, coat, poncho,
## hardsuit), hats, glasses, scarves, dog tags, plus optional field gear (pack, slung rifle,
## rebreather). Stylized shading with ink outlines (the mech paint shader).
## About 1.8 m tall, facing -Z, feet at the origin.
##
##   var fig := HumanFigure.new().build(portrait, {"gear": {"pack": true, "rifle": true}})
##   add_child(fig)
##   fig.play("walk")          # idle, walk, run, talk, sneak, sit, aim, hit, fall
##   fig.set_speed(3.0)        # m/s: picks idle / walk / run by itself
## Same calls work for NPCs (their look from PortraitSpec, or PortraitArt.look_for_npc).

const SCENE := "res://assets/people/human.glb"
const LOOPS := ["idle", "walk", "run", "talk", "sneak"]
const HEIGHT := 1.82

static var _paint_cache: Dictionary = {}
## Face shape-key mixes for the 10 expressions in portraits.json.
const EXPRESSIONS := {
	"neutral": {}, "smiling": {"smile": 0.9}, "angry": {"brow_angry": 1.0, "frown": 0.4},
	"worried": {"brow_worried": 1.0, "frown": 0.3}, "shouting": {"mouth_open": 0.8, "brow_angry": 0.7},
	"sad": {"brow_worried": 0.8, "frown": 0.8}, "surprised": {"brow_up": 1.0, "mouth_open": 0.45},
	"determined": {"brow_angry": 0.5, "frown": 0.15}, "smug": {"smile": 0.5, "brow_up": 0.25},
	"hurt": {"brow_worried": 0.8, "mouth_open": 0.25, "blink": 0.4},
}
const FACE_KEYS := ["blink", "brow_angry", "brow_worried", "brow_up", "mouth_open", "smile", "frown"]

var look: Dictionary = {}
var anim: AnimationPlayer
var state := "idle"
var _root: Node3D
var _meshes: Array[MeshInstance3D] = []


## Drop-in for the hubs' PilotFigure too: build(look, "Title", "Subtitle", pilot_suit) puts a
## name label over the head and a soft disc under the feet; `walking` (0..1) walks.
var walking := 0.0:
	set(v):
		walking = v
		set_speed(v * 1.4)
var _label: Label3D
var _ring: MeshInstance3D
## Face: current expression, speech and blinking.
var expression := "neutral"
var _face_goal: Dictionary = {}
var _face_now: Dictionary = {}
var _talk_left := 0.0
var _talk_t := 0.0
var _blink_in := 2.5
var _blink_t := -1.0
var _look: HeadLook
var _face_mesh: MeshInstance3D


func build(portrait: Dictionary, opts_or_title: Variant = {}, subtitle: String = "", pilot_suit: bool = false) -> HumanFigure:
	var opts: Dictionary = opts_or_title if opts_or_title is Dictionary else {"gear": {"pack": pilot_suit}}
	var title := String(opts_or_title) if opts_or_title is String else ""
	look = PortraitSpec.normalize(portrait) if not portrait.is_empty() else PortraitArt.look_for_pilot({"id": str(get_instance_id())})
	if _root:
		_root.queue_free()
	_root = (load(SCENE) as PackedScene).instantiate() as Node3D
	add_child(_root)
	_meshes.clear()
	for n in _root.find_children("*", "MeshInstance3D", true, false):
		_meshes.append(n as MeshInstance3D)
	anim = _root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim:
		for a: String in LOOPS:
			if anim.has_animation(a):
				anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	_dress(opts)
	_paint()
	_shape(opts)
	play("idle")
	for m in _meshes:
		if m.name == "Body":
			_face_mesh = m
	var sk := _root.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk:
		_look = HeadLook.new()
		sk.add_child(_look)
	set_expression("neutral")
	_ring = MeshKit.part(self, MeshKit.cylinder(0.36, 0.01, 20), MeshKit.overlay_material(Color(0, 0, 0, 0.28)), Vector3(0, 0.01, 0))
	if title != "":
		_label = Label3D.new()
		_label.text = title + ("
" + subtitle if subtitle != "" else "")
		_label.font_size = 40
		_label.outline_size = 10
		_label.pixel_size = 0.006
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.position = Vector3(0, 2.25, 0)
		_label.modulate = Color(0.92, 0.95, 1.0)
		add_child(_label)
	return self


func _o(id: String, fallback: String = "none") -> String:
	return String((look.get("parts", {}) as Dictionary).get(id, {}).get("option", fallback))


func _c(id: String, slot: String = "primary", fallback: String = "#808080") -> Color:
	var p: Dictionary = (look.get("parts", {}) as Dictionary).get(id, {})
	return Color(String(p.get(slot, p.get("primary", fallback))))


## Which pieces show: name prefix -> visible.
func _dress(opts: Dictionary) -> void:
	var outer := _o("outer_outfit")
	var hat := _o("hats")
	var gear: Dictionary = opts.get("gear", {})
	var show := {
		"Body": true, "Suit": true, "Boots": true,
		"Jacket": outer in ["jacket", "uniform"], "Coat": outer == "coat", "Poncho": outer == "poncho",
		"Hardsuit": outer == "hardsuit_collar",
		"Collar": _o("inner_outfit") in ["turtleneck", "flight_suit"] or _o("scarves") == "collar_wrap",
		"Scarf": _o("scarves") == "scarf", "Shemagh": _o("scarves") == "shemagh",
		"Beard": _o("beard") not in ["none", "stubble"] or _o("mustache") in ["full", "handlebar"],
		"Gear_tags": _o("jewelry") == "dog_tags",
		"Gear_pack": bool(gear.get("pack", false)), "Gear_rifle": bool(gear.get("rifle", false)),
		"Gear_rebreather": bool(gear.get("rebreather", false)),
	}
	var hair := _o("hair", "short")
	for m in _meshes:
		var n := String(m.name)
		var vis := false
		if n.begins_with("Hair_"):
			vis = n == "Hair_" + hair and hat not in ["helmet", "hood"]
		elif n.begins_with("Hat_"):
			vis = n == "Hat_" + hat
		elif n.begins_with("Glasses_"):
			vis = n == "Glasses_" + _o("glasses")
		else:
			for key: String in show:
				if n == key or n.begins_with(key + "_") or n.begins_with(key):
					vis = bool(show[key])
					break
		m.visible = vis


## Colors by material role, from the portrait's parts.
func _paint() -> void:
	var outer_on := _o("outer_outfit") != "none"
	var roles := {
		"skin": _c("face", "primary", "#c68d66"), "hair": _c("hair", "primary", "#3a2518"),
		"in_p": _c("inner_outfit", "primary", "#3b4c5e"), "in_s": _c("inner_outfit", "secondary", "#d8a23a"),
		"out_p": _c("outer_outfit", "primary", "#4a5a6a") if outer_on else _c("inner_outfit", "primary", "#3b4c5e"),
		"out_s": _c("outer_outfit", "secondary", "#3a8ac8") if outer_on else _c("inner_outfit", "secondary", "#d8a23a"),
		"hat": _c("hats", "primary", "#4a5a6a"), "accent": _c("glasses", "primary", "#3a8ac8"),
		"scarf": _c("scarves", "primary", "#c83a2a"), "metal": Color(0.55, 0.56, 0.58),
		"dark": Color(0.11, 0.11, 0.12), "eye": Color(0.06, 0.05, 0.05),
	}
	if _o("hats") == "hood":
		roles["out_p"] = _c("hats", "primary", "#4a5a6a") if not outer_on else roles["out_p"]
	for m in _meshes:
		for i in range(m.mesh.get_surface_count()):
			var src := m.mesh.surface_get_material(i)
			var role := src.resource_name if src else "in_p"
			var col: Color = roles.get(role, Color(0.6, 0.6, 0.6))
			m.set_surface_override_material(i, _paint_mat(col, role))


static func _paint_mat(col: Color, role: String) -> Material:
	var key := "%s|%s" % [col.to_html(), role]
	if not _paint_cache.has(key):
		var metal := 0.7 if role == "metal" else (0.3 if role == "accent" else 0.05)
		var rough := 0.35 if role in ["metal", "accent", "eye"] else 0.75
		var emit := col * 0.6 if role == "accent" else Color.BLACK
		_paint_cache[key] = MeshKit.paint(col, metal, rough, 0.0, emit)
	return _paint_cache[key]


## Build and face from the portrait: slim / heavy bodies, female or male frame, face shape.
func _shape(opts: Dictionary) -> void:
	var female: bool = opts.get("female", _guess_female())
	var w := {
		"female": 1.0 if female else 0.0,
		"slim": {"slim": 1.0}.get(_o("body", "average"), 0.0),
		"heavy": {"heavy": 1.0, "broad": 0.55}.get(_o("body", "average"), 0.0),
		"face_round": 1.0 if _o("face", "oval") == "round" else 0.0,
		"face_square": 1.0 if _o("face", "oval") == "square" else 0.0,
		"face_long": 1.0 if _o("face", "oval") == "long" else 0.0,
		"face_heart": 1.0 if _o("face", "oval") == "heart" else 0.0,
	}
	for m in _meshes:
		for k: String in w:
			var idx := m.find_blend_shape_by_name(k)
			if idx >= 0:
				m.set_blend_shape_value(idx, float(w[k]))


## The portrait doesn't say; beards read as male, otherwise a stable coin flip.
func _guess_female() -> bool:
	if _o("beard") != "none" or _o("mustache") != "none":
		return false
	return int(hash(JSON.stringify(look.get("parts", {})))) % 2 == 0


# --- face ----------------------------------------------------------------------------------

## Any expression id from portraits.json (unknown ones use their placeholder face).
func set_expression(e: String) -> void:
	expression = e if EXPRESSIONS.has(e) else PortraitSpec.draw_as(e)
	if not EXPRESSIONS.has(expression):
		expression = "neutral"
	_face_goal = EXPRESSIONS[expression]


## Says a line: the expression, mouth movement for `duration` seconds (about the time to read
## the text when -1), and the talk gesture if standing idle. Returns the duration.
func speak(text: String, expr: String = "", duration: float = -1.0) -> float:
	if expr != "":
		set_expression(expr)
	_talk_left = duration if duration > 0.0 else 0.5 + text.length() * 0.055
	_talk_t = 0.0
	if state == "idle":
		play("talk")
	return _talk_left


func stop_speaking() -> void:
	_talk_left = 0.0
	if state == "talk":
		play("idle")


## Turn the head toward a person or point (a Node3D, a Vector3), or null to look ahead.
func look_at_target(target: Variant) -> void:
	if _look == null:
		return
	if target is Node3D:
		var n := target as Node3D
		var h: float = HEIGHT * 0.92 * n.scale.y if n is HumanFigure else 1.6
		_look.target = n.global_position + Vector3.UP * h
	elif target is Vector3:
		_look.target = target
	else:
		_look.target = null


func _process(delta: float) -> void:
	if _face_mesh == null:
		return
	# Blink every few seconds.
	_blink_in -= delta
	if _blink_in <= 0.0:
		_blink_t = 0.0
		_blink_in = randf_range(2.0, 5.0)
	var blink := 0.0
	if _blink_t >= 0.0:
		_blink_t += delta
		blink = sin(clampf(_blink_t / 0.16, 0.0, 1.0) * PI)
		if _blink_t > 0.16:
			_blink_t = -1.0
	# Mouth: syllable-like flaps while speaking.
	var talk := 0.0
	if _talk_left > 0.0:
		_talk_t += delta
		_talk_left -= delta
		talk = 0.25 + 0.55 * absf(sin(_talk_t * 11.0)) * (0.6 + 0.4 * sin(_talk_t * 3.7))
		if _talk_left <= 0.0:
			stop_speaking()
	var k := clampf(delta * 12.0, 0.0, 1.0)
	for key: String in FACE_KEYS:
		var goal := float(_face_goal.get(key, 0.0))
		if key == "blink":
			goal = maxf(goal, blink)
		elif key == "mouth_open":
			goal = maxf(goal, talk)
		var now := lerpf(float(_face_now.get(key, 0.0)), goal, 1.0 if key == "blink" else k)
		_face_now[key] = now
		var idx := _face_mesh.find_blend_shape_by_name(key)
		if idx >= 0:
			_face_mesh.set_blend_shape_value(idx, now)


func play(name: String, blend: float = 0.2) -> void:
	state = name
	if anim and anim.has_animation(name):
		anim.play(name, blend)


## Moving at `mps` meters per second: idle, walk or run, with the cycle sped to match.
func set_speed(mps: float) -> void:
	var want := "idle" if mps < 0.1 else ("walk" if mps < 2.6 else "run")
	if want != state and state in ["idle", "walk", "run"]:
		play(want)
	if anim:
		anim.speed_scale = 1.0 if want == "idle" else clampf(mps / (1.4 if want == "walk" else 4.0), 0.6, 1.8)


## Highlight ring (hubs: the NPC you can talk to).
func set_highlight(on: bool, color: Color = Color(1.0, 0.82, 0.4)) -> void:
	if _ring:
		_ring.material_override = MeshKit.overlay_material(Color(color.r, color.g, color.b, 0.55) if on else Color(0, 0, 0, 0.28))
	if _label:
		_label.modulate = color if on else Color(0.92, 0.95, 1.0)
