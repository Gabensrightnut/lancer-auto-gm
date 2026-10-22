class_name MechView
extends Node3D
## One unit on the board: its generated model, a team-colored footprint outline, a
## floating name/HP/heat readout, status tags, and (for flyers) a drop line with altitude.
## Shows only what the seat's view contains: missing stats read "??".

const SIDE_COLORS := {"players": Color(0.3, 0.75, 1.0), "enemies": Color(1.0, 0.3, 0.25)}
## Short tags for statuses, shown above the unit.
const STATUS_TAGS := {
	"Lock On": "LOCK", "Jammed": "JAM", "Impaired": "IMP", "Slowed": "SLOW",
	"Immobilized": "IMMOB", "Shredded": "SHRED", "Stunned": "STUN", "Prone": "PRONE",
	"Hidden": "HIDDEN", "Invisible": "INVIS", "Exposed": "EXPOSED", "Danger Zone": "DANGER",
	"Engaged": "ENGAGED", "Burn": "BURN",
}

var unit: Dictionary = {}
var model: MechModel
var battle: BattleView
var cell := Vector2i.ZERO
var level := 0
var destroyed := false

var _ring: MeshInstance3D
var _label: Label3D
var _bars: Label3D
var _status: Label3D
var _drop: MeshInstance3D
var _alt: Label3D
var _burn: Node3D


func setup(unit_dict: Dictionary, view: BattleView) -> void:
	battle = view
	unit = unit_dict.duplicate(true)
	name = "Unit_" + String(unit.get("id", "?"))
	var frame := view.content.frame(unit.get("content_id", "")) if view.content else {}
	if frame.is_empty():
		frame = {"id": unit.get("content_id", ""), "source": "GMS", "mechtype": ["Balanced"], "stats": {"size": unit.get("size", 1)}}
	model = MechBuilder.build(frame, unit.get("loadout", {}), view.content, float(unit.get("size", -1)))
	add_child(model)
	_label = _make_label(40, Vector3.ZERO)
	_bars = _make_label(34, Vector3.ZERO)
	_status = _make_label(30, Vector3.ZERO)
	_status.modulate = Color(1.0, 0.85, 0.3)
	var c: Array = unit.get("cell", [0, 0])
	place(Vector2i(int(c[0]), int(c[1])), int(unit.get("level", 0)))
	refresh()


func _make_label(size: int, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.font_size = size
	l.pixel_size = 0.0035
	l.outline_size = 10
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 5
	l.outline_render_priority = 4
	l.position = pos
	add_child(l)
	return l


func side_color() -> Color:
	return SIDE_COLORS.get(unit.get("side", ""), Color(0.9, 0.9, 0.9))


## World position of a footprint's center at a level (where the model stands).
func footprint_center(at_cell: Vector2i, at_level: int) -> Vector3:
	var cells := battle.map.grid.footprint(at_cell, float(unit.get("size", 1)))
	var sum := Vector3.ZERO
	for c in cells:
		sum += battle.map.grid.to_world(c, at_level)
	return sum / cells.size()


func place(at_cell: Vector2i, at_level: int) -> void:
	cell = at_cell
	level = at_level
	position = footprint_center(cell, level)
	unit["cell"] = [cell.x, cell.y]
	unit["level"] = level
	_rebuild_ring()
	_update_flight()


## Turn to face a world point (rotate about y only).
func face(target: Vector3) -> void:
	var d := target - global_position
	if Vector2(d.x, d.z).length() < 0.01:
		return
	model.rotation.y = atan2(-d.x, -d.z)


func facing_angle_to(target: Vector3) -> float:
	var d := target - global_position
	return atan2(-d.x, -d.z)


func _rebuild_ring() -> void:
	if _ring:
		_ring.queue_free()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(Color(1, 1, 1, 1))
	for c in battle.map.grid.footprint(cell, float(unit.get("size", 1))):
		battle.terrain.add_outline(st, c, level * GridLayout.LEVEL_HEIGHT + 0.02, 0.05, 0.05)
	_ring = MeshInstance3D.new()
	_ring.mesh = st.commit()
	var col := side_color()
	col.a = 0.9
	_ring.material_override = MeshKit.overlay_material(col)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_ring.top_level = true
	_ring.global_transform = Transform3D.IDENTITY
	_ring.visible = not destroyed


## Flyers: a drop line and shadow disc to the ground, with the altitude in levels.
func _update_flight() -> void:
	var ground := battle.map.ground_height(cell)
	var up := level - ground
	if _drop:
		_drop.queue_free()
		_drop = null
	if _alt:
		_alt.queue_free()
		_alt = null
	if up <= 0:
		return
	_drop = MeshInstance3D.new()
	_drop.mesh = MeshKit.cylinder(0.012, up * GridLayout.LEVEL_HEIGHT, 6)
	_drop.material_override = MeshKit.fx_material(side_color(), 1.5)
	_drop.position = Vector3(0, -up * GridLayout.LEVEL_HEIGHT / 2.0, 0)
	add_child(_drop)
	var disc := MeshInstance3D.new()
	disc.mesh = MeshKit.cylinder(0.35, 0.01, 24)
	disc.material_override = MeshKit.overlay_material(Color(0, 0, 0, 0.45))
	disc.position = Vector3(0, -up * GridLayout.LEVEL_HEIGHT / 2.0 + 0.02, 0)
	_drop.add_child(disc)
	_alt = _make_label(36, Vector3(0.3, -0.15, 0))
	_alt.text = "▲ %d" % up
	_alt.modulate = side_color()


func refresh() -> void:
	var h := model.height
	_label.text = String(unit.get("name", unit.get("id", "")))
	_label.modulate = side_color().lightened(0.35)
	# Same anchor, stacked in screen pixels, so they never overlap at steep camera angles.
	for l: Label3D in [_label, _bars, _status]:
		l.position = Vector3(0, h + 0.3, 0)
		l.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_bars.offset = Vector2(0, 0)
	_label.offset = Vector2(0, 46)
	_status.offset = Vector2(0, 92)
	_bars.text = _bar_text()
	var tags: Array = []
	for s: String in (unit.get("statuses", {}) as Dictionary):
		tags.append(STATUS_TAGS.get(s, s.to_upper()))
	_status.text = "  ".join(tags)
	if unit.has("heat") and unit.has("heat_cap"):
		set_heat(int(unit["heat"]), int(unit["heat_cap"]))
	var burning := (unit.get("statuses", {}) as Dictionary).has("Burn")
	if burning and _burn == null:
		_burn = Fx.fire(self, Vector3(0, h * 0.5, 0), 0.6)
	elif not burning and _burn:
		_burn.queue_free()
		_burn = null


func _bar_text() -> String:
	if not unit.has("hp"):
		return "HP ??   HEAT ??"
	var out := "HP %d/%d" % [int(unit["hp"]), int(unit.get("max_hp", unit["hp"]))]
	if int(unit.get("overshield", 0)) > 0:
		out += " +%d" % int(unit["overshield"])
	out += "   HEAT %d/%d" % [int(unit.get("heat", 0)), int(unit.get("heat_cap", 0))]
	var s := int(unit.get("structure", 4))
	out += "   " + "◆".repeat(s) + "◇".repeat(maxi(0, int(unit.get("max_structure", 4)) - s))
	return out


## Heat glow: orange at half heat, near white at the cap.
func set_heat(heat: int, cap: int) -> void:
	var ratio := clampf(float(heat) / maxf(1.0, float(cap)), 0.0, 1.2)
	model.set_fx("heat", maxf(0.0, ratio - 0.25) / 0.75)


func set_stat(key: String, value: Variant) -> void:
	unit[key] = value
	refresh()


func body_center() -> Vector3:
	return global_position + Vector3.UP * model.height * 0.6


## Collapse into a wreck that stays on the board.
func wreck() -> void:
	destroyed = true
	_label.modulate = Color(0.6, 0.6, 0.6)
	_bars.text = "DESTROYED"
	_status.text = ""
	if _ring:
		_ring.visible = false
	model.set_fx("heat", 0.0)
	var tw := create_tween()
	tw.tween_property(model, "rotation_degrees:x", -75.0, Fx.t(0.7)).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(model, "position:y", -model.height * 0.15, Fx.t(0.7))
	await tw.finished
	model.set_fx("dim", 0.55)
	model.set_fx("heat", 0.12)
	_burn = Fx.fire(self, Vector3(0, model.height * 0.2, 0), 0.8)
