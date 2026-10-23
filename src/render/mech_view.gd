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
	"Engaged": "ENGAGED", "Burn": "BURN", "Cascading": "⚠ CASCADE", "Blinded": "BLINDED",
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
var _push := 0.0
var _blind: MeshInstance3D

## Nameplate font sizes in 1080p screen pixels.
const NAME_PX := 24
const BARS_PX := 19
const STATUS_PX := 17


func setup(unit_dict: Dictionary, view: BattleView) -> void:
	battle = view
	unit = unit_dict.duplicate(true)
	name = "Unit_" + String(unit.get("id", "?"))
	var frame := view.content.frame(unit.get("content_id", "")) if view.content else {}
	if frame.is_empty():
		frame = {"id": unit.get("content_id", ""), "source": "GMS", "mechtype": ["Balanced"], "stats": {"size": unit.get("size", 1)}}
	if String(unit.get("kind", "")) == "pilot":
		model = pilot_model(unit)
	elif VisibleParts.is_deployable(unit):
		# Drones, turrets, mines, cover...: their own look (data/game/visible_parts.json), in
		# the owner's colors when the seat knows who that is.
		var owner_mv: MechView = view.units.get(VisibleParts.owner_of(unit))
		model = DeployableBuilder.build(unit, MechStyles.palette(owner_mv.model.manufacturer) if owner_mv and owner_mv.model else {})
	else:
		model = MechBuilder.build(frame, unit.get("loadout", {}), view.content, float(unit.get("size", -1)))
	add_child(model)
	if unit.get("paint") is Dictionary:
		MechPaint.apply(model, unit["paint"])  # cosmetic scheme from the customizer
	# Nameplate: fixed size on screen; LabelDeclutter scales, nudges and fades it.
	_label = _make_label(NAME_PX, Vector3.ZERO)
	_bars = _make_label(BARS_PX, Vector3.ZERO)
	_status = _make_label(STATUS_PX, Vector3.ZERO)
	for l: Label3D in [_label, _bars, _status]:
		l.fixed_size = true
		l.pixel_size = 0.0008
		l.outline_size = 8
		l.outline_modulate = Color(0, 0, 0, 0.95)
	_status.modulate = Color(1.0, 0.85, 0.3)
	var c: Array = unit.get("cell", [0, 0])
	place(Vector2i(int(c[0]), int(c[1])), int(unit.get("level", 0)))
	refresh()
	# A pilot inside a mech isn't on the board.
	visible = not bool(unit.get("mounted", false))


## A pilot on foot: the creator's token figure (their portrait look, or a stable random one),
## shown a bit larger than true scale next to the mechs so it stays readable.
const PILOT_HEIGHT := 0.42


static func pilot_model(u: Dictionary) -> MechModel:
	var m := MechModel.new()
	m.name = "Pilot_" + String(u.get("id", ""))
	m.size = 0.5
	m.height = PILOT_HEIGHT
	m.gait = "tracked"  # no leg rig: the token slides; walk_amount just bobs it
	var body := Node3D.new()
	body.name = "Body"
	m.add_child(body)
	var look: Dictionary = u.get("portrait", {}) if u.get("portrait") is Dictionary else {}
	if look.is_empty():
		look = PortraitArt.look_for_pilot({"id": String(u.get("id", "pilot"))})
	var token := HumanFigure.new().build(look, {"gear": {"pack": true, "rifle": true}})
	token.scale = Vector3.ONE * (PILOT_HEIGHT / HumanFigure.HEIGHT)
	body.add_child(token)
	m.set_meta("human", token)
	m.pelvis = body
	m.torso = body
	var eye := Marker3D.new()
	eye.position = Vector3(0, PILOT_HEIGHT * 0.92, -0.03)
	body.add_child(eye)
	m.eye = eye
	m.collect_meshes()
	return m


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
	if (unit.get("statuses", {}) as Dictionary).has("Cascading"):
		col = Color(1.0, 0.15, 0.1)  # the NHP has it: not your side's color any more
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
	_alt = _make_label(18, Vector3(0.3, -0.15, 0))
	_alt.add_to_group(LabelDeclutter.GROUP_SCREEN_SIZED)
	_alt.outline_size = 8
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
	_bars.text = _bar_text()
	var tags: Array = []
	for s: String in (unit.get("statuses", {}) as Dictionary):
		tags.append(STATUS_TAGS.get(s, s.to_upper()))
	_status.text = "  ".join(tags)
	# Blinded: a dark shroud; it can only see the spaces next to it.
	var blinded := (unit.get("statuses", {}) as Dictionary).has("Blinded")
	if blinded and _blind == null:
		_blind = MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = maxf(0.7, h * 0.75)
		sph.height = sph.radius * 2.0
		_blind.mesh = sph
		_blind.material_override = MeshKit.overlay_material(Color(0.02, 0.02, 0.04, 0.55), false, false)
		_blind.position = Vector3(0, h * 0.55, 0)
		_blind.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_blind)
	elif not blinded and _blind:
		_blind.queue_free()
		_blind = null
	# A cascading NHP: red glitching body, red name, the tag in red.
	var cascading := (unit.get("statuses", {}) as Dictionary).has("Cascading")
	model.set_fx("cascade", 1.0 if cascading else 0.0)
	if cascading != bool(get_meta("cascading", false)):
		set_meta("cascading", cascading)
		_rebuild_ring()
	if cascading:
		_label.modulate = Color(1.0, 0.3, 0.25)
		_status.modulate = Color(1.0, 0.35, 0.3)
	else:
		_status.modulate = Color(1.0, 0.85, 0.3)
	set_plate_push(_push)
	if unit.has("heat") and unit.has("heat_cap"):
		set_heat(int(unit["heat"]), int(unit["heat_cap"]))
	var burning := (unit.get("statuses", {}) as Dictionary).has("Burn")
	if burning and _burn == null:
		_burn = Fx.fire(self, Vector3(0, h * 0.5, 0), 0.6)
	elif not burning and _burn:
		_burn.queue_free()
		_burn = null


## Where the nameplate's bottom edge sits in the world.
func plate_anchor() -> Vector3:
	return global_position + Vector3.UP * (model.height + 0.3)


## Nameplate size in 1080p screen pixels.
func plate_size() -> Vector2:
	var w := 0.0
	var h := 0.0
	for l: Label3D in [_bars, _label, _status]:
		if l.text == "":
			continue
		var font: Font = l.font if l.font else ThemeDB.fallback_font
		var s := font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.font_size)
		w = maxf(w, s.x + l.outline_size)
		h = l.offset.y - _push + s.y
	return Vector2(w, h)


## Lifts the nameplate by `px` screen pixels (1080p) to clear other labels.
func set_plate_push(px: float, dx: float = 0.0) -> void:
	_push = px
	_bars.offset = Vector2(dx, px)
	_label.offset = Vector2(dx, px + BARS_PX + 3)
	_status.offset = Vector2(dx, px + BARS_PX + NAME_PX + 6)


func set_plate_alpha(a: float) -> void:
	for l: Label3D in [_label, _bars, _status]:
		l.modulate.a = a
		l.visible = a > 0.01
		l.outline_modulate.a = 0.95 * a


## Pixel size that makes one font pixel one 1080p screen pixel for the current camera.
func set_plate_scale(ps: float) -> void:
	for l: Label3D in [_label, _bars, _status]:
		l.pixel_size = ps


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
