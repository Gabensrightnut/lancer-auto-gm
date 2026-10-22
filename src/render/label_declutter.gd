class_name LabelDeclutter
extends Node
## Keeps the floating unit nameplates readable. Every frame, in screen space:
## - nameplates are a fixed size on screen (scaled with the window height, 1080p = 1:1),
## - a nameplate that overlaps another one, a planning label (Label3Ds in group
##   GROUP_PRIORITY, e.g. the move cost) or the active unit's body is pushed up a little,
##   and faded if pushing can't clear it,
## - nameplates under the HUD (visible Controls in group GROUP_KEEPOUT) or right next to the
##   cursor fade out, except the unit under the cursor.
## The active unit and the hovered unit are placed first and keep their spot.
## Presentation only: never reads or changes game state.

const GROUP_KEEPOUT := "label_keepout"
const GROUP_PRIORITY := "label_priority"
## Label3Ds kept at their font size in 1080p screen pixels, whatever the camera distance.
const GROUP_SCREEN_SIZED := "label_screen_sized"
## How far (1080p pixels) a nameplate may be pushed before it fades instead.
const MAX_PUSH := 70.0
const GAP := 3.0
const FADED := 0.2
## Under the HUD: gone.
const HIDDEN := 0.0
## Screen margin plates keep from the window edges (1080p pixels).
const EDGE := 12.0
const NEAR_CURSOR := 0.3
const CURSOR_PAD := 24.0

var battle: BattleView
var active_unit := ""
var hover_unit := ""
## Cursor position for fading; null uses the real mouse.
var cursor: Variant = null
## Smoothed alpha per unit id.
var _alpha: Dictionary = {}


func _init(view: BattleView = null) -> void:
	battle = view
	name = "LabelDeclutter"
	process_priority = 100  # after cameras and units moved this frame


func _process(delta: float) -> void:
	if battle == null or not battle.is_inside_tree():
		return
	var cam := battle.get_viewport().get_camera_3d()
	if cam == null:
		return
	var vp := battle.get_viewport().get_visible_rect().size
	var k := vp.y / 1080.0
	var ps := 2.0 * tan(deg_to_rad(cam.fov) * 0.5) / 1080.0
	var keepout := keepout_rects()
	var placed: Array[Rect2] = []
	for n: Node in battle.get_tree().get_nodes_in_group(GROUP_SCREEN_SIZED):
		var sl := n as Label3D
		if sl:
			sl.fixed_size = true
			sl.pixel_size = ps
	# Planning labels first; screen-sized ones step up past each other (a terrain flag and
	# the move cost on the same space).
	for l: Label3D in _priority_labels():
		if l.is_in_group(GROUP_SCREEN_SIZED):
			l.offset = Vector2.ZERO
		var r := label_rect(l, cam, vp)
		if not r.has_area():
			continue
		if l.is_in_group(GROUP_SCREEN_SIZED):
			var y0 := r.position.y
			for i in range(4):
				var hit: Variant = _first_hit(r, placed)
				if hit == null:
					break
				r.position.y = (hit as Rect2).position.y - r.size.y - GAP * k
			l.offset.y = (y0 - r.position.y) / k
		placed.append(r)
	var mouse: Vector2 = cursor if cursor is Vector2 else battle.get_viewport().get_mouse_position()
	for mv: MechView in _ordered(cam):
		var id := String(mv.unit.get("id", ""))
		mv.set_plate_scale(ps)
		var anchor := mv.plate_anchor()
		if cam.is_position_behind(anchor):
			continue
		var p := cam.unproject_position(anchor)
		var size := mv.plate_size() * k
		var r := Rect2(p.x - size.x * 0.5, p.y - size.y, size.x, size.y)
		# Slide plates at the screen's sides back onto it.
		var base_x := r.position.x
		r.position.x = clampf(r.position.x, EDGE * k, maxf(EDGE * k, vp.x - EDGE * k - r.size.x))
		r.position.y = clampf(r.position.y, EDGE * k, maxf(EDGE * k, vp.y - EDGE * k - r.size.y))
		var base_y := r.position.y
		var target := 1.0
		for i in range(8):
			var hit: Variant = _first_hit(r, placed)
			if hit == null:
				break
			r.position.y = (hit as Rect2).position.y - r.size.y - GAP * k
		# Pushed too far: stay put and fade, except your own unit, which stays readable.
		if base_y - r.position.y > MAX_PUSH * k * (3.0 if id == active_unit else 1.0):
			r.position.y = base_y
			if id != active_unit:
				target = FADED
		mv.set_plate_push((base_y - r.position.y) / k, (r.position.x - base_x) / k)
		if r.position.y < 0.0:
			target = FADED
		placed.append(r)
		if id == active_unit and not mv.destroyed:
			placed.append(_body_rect(mv, cam))  # others' plates keep off the active mech
		for ko: Rect2 in keepout:
			if ko.intersects(r):
				target = minf(target, HIDDEN)
		if id != hover_unit and r.grow(CURSOR_PAD * k).has_point(mouse):
			# Your own plate only dims a little: it carries your HP and heat.
			target = minf(target, 0.6 if id == active_unit else NEAR_CURSOR)
		var a: float = move_toward(float(_alpha.get(id, 1.0)), target, delta * 6.0) if delta > 0.0 else target
		_alpha[id] = a
		mv.set_plate_alpha(a)


## Active and hovered units first, then nearest to the camera.
func _ordered(cam: Camera3D) -> Array:
	var list: Array = []
	for mv: MechView in battle.units.values():
		if is_instance_valid(mv) and mv.visible:
			list.append(mv)
	var cp := cam.global_position
	list.sort_custom(func(a: MechView, b: MechView) -> bool:
		var ra := _rank(a)
		var rb := _rank(b)
		if ra != rb:
			return ra < rb
		return a.global_position.distance_squared_to(cp) < b.global_position.distance_squared_to(cp))
	return list


func _rank(mv: MechView) -> int:
	var id := String(mv.unit.get("id", ""))
	if id == active_unit:
		return 0
	if id == hover_unit:
		return 1
	return 3 if mv.destroyed else 2


static func _first_hit(r: Rect2, rects: Array[Rect2]) -> Variant:
	for o: Rect2 in rects:
		if o.intersects(r):
			return o
	return null


## Screen rectangles of the visible HUD panels nameplates shouldn't cover.
func keepout_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for n: Node in battle.get_tree().get_nodes_in_group(GROUP_KEEPOUT):
		var c := n as Control
		if c and c.is_visible_in_tree() and c.size.x > 0.0:
			out.append(c.get_global_rect())
	return out


func _priority_labels() -> Array[Label3D]:
	var out: Array[Label3D] = []
	for n: Node in battle.get_tree().get_nodes_in_group(GROUP_PRIORITY):
		var l := n as Label3D
		if l and l.is_visible_in_tree() and l.text != "":
			out.append(l)
	return out


## Screen box of the unit's body, so other units' plates don't sit on top of it.
static func _body_rect(mv: MechView, cam: Camera3D) -> Rect2:
	var foot := cam.unproject_position(mv.global_position)
	var head := cam.unproject_position(mv.global_position + Vector3.UP * mv.model.height)
	var h := maxf(absf(foot.y - head.y), 10.0)
	return Rect2(head.x - h * 0.35, minf(head.y, foot.y), h * 0.7, h)


## Screen rectangle of any billboard Label3D (world-sized or fixed-size).
static func label_rect(l: Label3D, cam: Camera3D, vp: Vector2) -> Rect2:
	var gp := l.global_position
	if cam.is_position_behind(gp):
		return Rect2()
	var font: Font = l.font if l.font else ThemeDB.fallback_font
	var px := font.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_CENTER, -1, l.font_size)
	px += Vector2.ONE * l.outline_size
	var tn := tan(deg_to_rad(cam.fov) * 0.5)
	var depth := maxf(0.05, -(cam.global_transform.affine_inverse() * gp).z)
	var s := l.pixel_size * vp.y / (2.0 * tn) / (1.0 if l.fixed_size else depth)
	var size := px * s
	var c := cam.unproject_position(gp) + Vector2(l.offset.x, -l.offset.y) * s
	return Rect2(c - size * 0.5, size)
