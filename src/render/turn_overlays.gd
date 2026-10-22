class_name TurnOverlays
extends Node3D
## Planning aids drawn only for the active seat (DESIGN.md "Turn overlays"). Draws exactly
## what it's given; every value (costs, cover, legality) comes from the rules engine.
## See src/render/FORMATS.md for the plan dictionary.

const COLORS := {
	"move": Color(0.35, 0.85, 1.0), "boost": Color(1.0, 0.82, 0.2),
	"provoke": Color(1.0, 0.28, 0.22), "difficult": Color(1.0, 0.55, 0.15),
	"dangerous": Color(1.0, 0.25, 0.65), "over": Color(0.55, 0.55, 0.58),
	"hard": Color(0.3, 0.6, 1.0), "soft": Color(0.45, 1.0, 0.6),
	"footprint": Color(0.35, 0.85, 1.0), "bad": Color(1.0, 0.25, 0.2),
	"blocked": Color(0.08, 0.08, 0.09), "sky": Color(0.55, 0.8, 1.0), "dim": Color(0.0, 0.0, 0.02),
	"area": Color(1.0, 0.5, 0.2), "pick": Color(1.0, 0.82, 0.35), "pick_bad": Color(1.0, 0.25, 0.2),
}
const FLAG_TEXT := {
	"provoke": "PROVOKES", "boost": "BOOST", "difficult": "DIFFICULT",
	"dangerous": "DANGEROUS", "climb": "CLIMB", "fall": "FALL",
}

var battle: BattleView
var plan: Dictionary = {}
var _dimmed_units: Array = []


func _init(view: BattleView) -> void:
	battle = view
	name = "TurnOverlays"


func clear() -> void:
	for c in get_children():
		c.queue_free()
	for id: String in _dimmed_units:
		var mv: MechView = battle.units.get(id)
		if mv and not mv.destroyed:
			mv.model.set_fx("dim", 0.0)
	_dimmed_units.clear()
	plan = {}


## Draws a plan. Any key may be left out. Replaces whatever was drawn before.
func show_plan(new_plan: Dictionary) -> void:
	clear()
	plan = new_plan
	if plan.has("los"):
		_draw_los(plan["los"])
	if plan.has("blocked"):
		_draw_cells(plan["blocked"], -1, COLORS["blocked"], 0.55, false)
	if plan.has("cover"):
		_draw_cover(plan["cover"])
	if plan.has("sky_layer"):
		_draw_sky(plan["sky_layer"])
	if plan.has("path"):
		_draw_path(plan)
	if plan.has("footprint"):
		_draw_footprint(plan["footprint"])
	if plan.has("cover_from"):
		_draw_cover_from(plan["cover_from"])
	# Step-by-step picking: the area an aim would hit, spaces already picked, the hovered one.
	if plan.has("area"):
		_draw_cells(plan["area"], -1, COLORS["area"], 0.32)
	if plan.has("picked"):
		_draw_cells(plan["picked"], -1, COLORS["pick"], 0.55)
	if plan.has("hover_cell"):
		var ok: bool = plan.get("hover_ok", true)
		_draw_cells([plan["hover_cell"]], -1, COLORS["pick"] if ok else COLORS["pick_bad"], 0.4)


# --- helpers ---------------------------------------------------------------------------

func _cell(v: Variant) -> Vector2i:
	var a: Array = v
	return Vector2i(int(a[0]), int(a[1]))


func _mesh_node(st: SurfaceTool, color: Color, on_top: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = MeshKit.overlay_material(color, on_top, false)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## A floating label. `size` is in world terms; `screen_px` > 0 makes it a fixed size on
## screen instead (1080p pixels) and a label nameplates make room for (LabelDeclutter).
func _label(text: String, pos: Vector3, color: Color, size: int = 40, screen_px: int = 0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.0035
	l.outline_size = 10
	if screen_px > 0:
		l.font_size = screen_px
		l.outline_size = 8
		l.add_to_group(LabelDeclutter.GROUP_PRIORITY)
		l.add_to_group(LabelDeclutter.GROUP_SCREEN_SIZED)
	l.outline_modulate = Color(0, 0, 0, 0.95 if screen_px > 0 else 0.85)
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 6
	l.outline_render_priority = 5
	l.position = pos
	add_child(l)
	return l


## Fills cells (outline + translucent top). level -1 = the cell's ground height.
func _draw_cells(cells: Array, level: int, color: Color, alpha: float, outline: bool = true, lift: float = 0.03) -> void:
	var fill := SurfaceTool.new()
	fill.begin(Mesh.PRIMITIVE_TRIANGLES)
	fill.set_color(Color(1, 1, 1, 1))
	var line := SurfaceTool.new()
	line.begin(Mesh.PRIMITIVE_TRIANGLES)
	line.set_color(Color(1, 1, 1, 1))
	for v: Variant in cells:
		var c := _cell(v)
		var a: Array = v
		var lv := level
		if a.size() > 2:
			lv = int(a[2])
		if lv < 0:
			lv = battle.map.ground_height(c)
		var y := lv * GridLayout.LEVEL_HEIGHT + lift
		battle.terrain.add_cell_fill(fill, c, y, 0.05)
		if outline:
			battle.terrain.add_outline(line, c, y + 0.005, 0.03, 0.04)
	var fc := color
	fc.a = alpha
	_mesh_node(fill, fc)
	if outline:
		_mesh_node(line, Color(color.r, color.g, color.b, 0.95))


func _cell_top(c: Vector2i, level: int) -> Vector3:
	return battle.map.grid.to_world(c, level)


# --- path ------------------------------------------------------------------------------

func _draw_path(p: Dictionary) -> void:
	var path: Array = p["path"]
	if path.size() < 2:
		return
	var info: Array = p.get("path_info", [])
	var speed := int(p.get("speed", 999))
	var boost := int(p.get("boost", 0))
	var size := float(p.get("size", 1))
	var total := 0
	var prev_pt := Vector3.ZERO
	for i in range(path.size()):
		var a: Array = path[i]
		var c := Vector2i(int(a[0]), int(a[1]))
		var lv := int(a[2]) if a.size() > 2 else battle.map.ground_height(c)
		var pt := _footprint_center(c, lv, size) + Vector3.UP * 0.12
		if i == 0:
			prev_pt = pt
			_joint(pt, COLORS["move"], 0.07)
			continue
		var step: Dictionary = info[i] if i < info.size() else {}
		var cost := int(step.get("cost", 1))
		total += cost
		var flags: Array = step.get("flags", [])
		var key := "move"
		if total > speed + boost:
			key = "over"
		elif total > speed:
			key = "boost"
		for f: String in ["dangerous", "difficult", "provoke"]:
			if f in flags:
				key = f
		var col: Color = COLORS[key]
		# Climb or drop at the edge between spaces, so the arrow follows the terrain.
		var pa: Array = path[i - 1]
		var prev_lv := int(pa[2]) if pa.size() > 2 else battle.map.ground_height(Vector2i(int(pa[0]), int(pa[1])))
		if lv != prev_lv:
			var mid_xz := (prev_pt + pt) * 0.5
			var e1 := Vector3(mid_xz.x, prev_pt.y, mid_xz.z)
			var e2 := Vector3(mid_xz.x, pt.y, mid_xz.z)
			if p.get("fly", false):
				# Flying: going up or down costs nothing extra; show the height change.
				_segment(prev_pt, e1, col)
				_segment(e1, e2, COLORS["sky"])
				_segment(e2, pt, col)
				_label("%s %d" % ["▲" if lv > prev_lv else "▼", absi(lv - prev_lv)], e2 + Vector3(0.25, 0.1, 0), COLORS["sky"], 30, 17)
			elif lv > prev_lv:
				_segment(prev_pt, e1, col)
				_segment(e1, e2, col)
				_segment(e2, pt, col)
				_label("+%d CLIMB" % (lv - prev_lv), e2 + Vector3(0.25, 0.1, 0), col, 30, 17)
			else:
				_segment(prev_pt, e1, col)
				_segment(e1, e2, COLORS["provoke"] if "fall" in flags else col)
				_segment(e2, pt, col)
				if "fall" in flags:
					_label("FALL %d" % (prev_lv - lv), (e1 + e2) * 0.5 + Vector3(0.3, 0, 0), COLORS["provoke"], 30, 17)
			_joint(e1, col, 0.05)
			_joint(e2, col, 0.05)
		else:
			_segment(prev_pt, pt, col)
		if i < path.size() - 1:
			_joint(pt, col, 0.06)
			_label(str(total), pt + Vector3.UP * 0.18, col.lightened(0.3), 28)
		for f: String in flags:
			if FLAG_TEXT.has(f) and f != "climb" and f != "fall" and f != "boost":
				_label(FLAG_TEXT[f], pt + Vector3(0, 0.4, 0), COLORS.get(f, col), 30, 17)
		if i == path.size() - 1:
			_arrowhead(prev_pt, pt, col)
			var left := speed - total
			var text := "%d / %d SPEED" % [total, speed]
			if left >= 0:
				text += "  (%d left)" % left
			elif total <= speed + boost:
				text += "  BOOST"
			else:
				text += "  TOO FAR"
			_label(text, pt + Vector3.UP * 0.55, col.lerp(Color.WHITE, 0.5), 40, 21)
		prev_pt = pt


func _footprint_center(c: Vector2i, lv: int, size: float) -> Vector3:
	var cells := battle.map.grid.footprint(c, size)
	var sum := Vector3.ZERO
	for fc in cells:
		sum += battle.map.grid.to_world(fc, lv)
	return sum / cells.size()


func _segment(a: Vector3, b: Vector3, color: Color) -> void:
	if a.distance_to(b) < 0.001:
		return
	for on_top: bool in [false, true]:
		var mi := MeshInstance3D.new()
		mi.mesh = MeshKit.cylinder(0.5, 1.0, 8)
		var c := color
		c.a = 0.95 if not on_top else 0.25
		mi.material_override = MeshKit.overlay_material(c, on_top)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		Fx._orient_between(mi, a, b, 0.07, a.distance_to(b))


func _joint(p: Vector3, color: Color, r: float) -> void:
	var mi := MeshKit.part(self, MeshKit.sphere(r, 10), MeshKit.overlay_material(Color(color.r, color.g, color.b, 0.95)), p)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _arrowhead(from: Vector3, to: Vector3, color: Color) -> void:
	var dir := to - from
	dir.y = 0
	if dir.length() < 0.001:
		dir = Vector3.FORWARD
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.cylinder(0.16, 0.3, 12, 0.0)
	mi.material_override = MeshKit.overlay_material(Color(color.r, color.g, color.b, 1.0))
	add_child(mi)
	Fx._orient_between(mi, to - dir.normalized() * 0.15, to + dir.normalized() * 0.15, 1.0, 1.0)


# --- footprint, cover, sky, LOS ------------------------------------------------------------

func _draw_footprint(fp: Dictionary) -> void:
	var c := _cell(fp["cell"])
	var lv := int(fp.get("level", battle.map.ground_height(c)))
	var ok := bool(fp.get("ok", true))
	var cells: Array = []
	for fc in battle.map.grid.footprint(c, float(fp.get("size", 1))):
		cells.append([fc.x, fc.y, lv])
	_draw_cells(cells, lv, COLORS["footprint"] if ok else COLORS["bad"], 0.3, true, 0.035)
	# In the air: a drop line and shadow to the ground and the height above it.
	var ground := battle.map.ground_height(c)
	if lv > ground:
		var top := _footprint_center(c, lv, float(fp.get("size", 1)))
		var bottom := _footprint_center(c, ground, float(fp.get("size", 1)))
		_segment(top, bottom + Vector3.UP * 0.03, COLORS["sky"])
		var shadow: Array = []
		for fc in battle.map.grid.footprint(c, float(fp.get("size", 1))):
			shadow.append([fc.x, fc.y, ground])
		_draw_cells(shadow, ground, Color(0, 0, 0), 0.35, false, 0.03)
		_label("▲ %d ABOVE GROUND" % (lv - ground), top.lerp(bottom, 0.5) + Vector3(0.35, 0, 0), COLORS["sky"], 30, 17)
	if not ok:
		_label(String(fp.get("reason", "CAN'T STAND HERE")), _footprint_center(c, lv, float(fp.get("size", 1))) + Vector3.UP * 0.4, COLORS["bad"], 34, 19)


func _draw_cover(list: Array) -> void:
	var hard: Array = []
	var soft: Array = []
	for e: Dictionary in list:
		var c := _cell(e["cell"])
		var lv := int(e.get("level", battle.map.ground_height(c)))
		(hard if e.get("kind", "hard") == "hard" else soft).append([c.x, c.y, lv])
	if not hard.is_empty():
		_draw_cells(hard, -1, COLORS["hard"], 0.35, true, 0.04)
		_cover_pillars(hard, COLORS["hard"])
	if not soft.is_empty():
		_draw_cells(soft, -1, COLORS["soft"], 0.25, true, 0.04)


## Glowing edges up the sides of cover terrain, so it reads from any angle.
func _cover_pillars(cells: Array, color: Color) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v: Array in cells:
		var c := Vector2i(int(v[0]), int(v[1]))
		var top := int(v[2]) * GridLayout.LEVEL_HEIGHT
		var corners := battle.terrain.cell_corners(c, 0.0, -0.02)
		for i in range(corners.size()):
			var a := corners[i]
			var b := corners[(i + 1) % corners.size()]
			for k in range(2):
				# Two faint bands per wall face, fading upward.
				var y0 := top - 0.35 + k * 0.18
				st.set_color(Color(1, 1, 1, 0.0))
				var p0 := a + Vector3.UP * y0
				var p1 := b + Vector3.UP * y0
				st.set_color(Color(1, 1, 1, 0.6))
				MeshKit.add_quad(st, p0, p1, p1 + Vector3.UP * 0.06, p0 + Vector3.UP * 0.06, (a + b) * 0.5 - battle.map.grid.to_world(c))
	_mesh_node(st, Color(color.r, color.g, color.b, 0.7))


func _draw_cover_from(list: Array) -> void:
	for e: Dictionary in list:
		var mv: MechView = battle.units.get(e.get("unit", ""))
		if mv == null:
			continue
		var kind := String(e.get("kind", "none"))
		var text := "NO COVER" if kind == "none" else "%s COVER" % kind.to_upper()
		var col: Color = COLORS.get(kind, Color(0.8, 0.8, 0.8))
		_label("◈ " + text + " from here", mv.global_position + Vector3.UP * (mv.model.height + 0.8), col, 34, 19)


func _draw_sky(sky: Dictionary) -> void:
	var lv := int(sky.get("level", 1))
	var cells: Array = []
	for v: Variant in sky.get("cells", []):
		var c := _cell(v)
		cells.append([c.x, c.y, lv])
	var col: Color = COLORS["sky"]
	var fill := SurfaceTool.new()
	fill.begin(Mesh.PRIMITIVE_TRIANGLES)
	fill.set_color(Color(1, 1, 1, 1))
	var line := SurfaceTool.new()
	line.begin(Mesh.PRIMITIVE_TRIANGLES)
	line.set_color(Color(1, 1, 1, 1))
	var y := lv * GridLayout.LEVEL_HEIGHT
	var sum := Vector3.ZERO
	for v: Array in cells:
		var c := Vector2i(v[0], v[1])
		battle.terrain.add_cell_fill(fill, c, y, 0.05)
		battle.terrain.add_outline(line, c, y + 0.003, 0.04, 0.03)
		sum += battle.map.grid.to_world(c, lv)
	_mesh_node(fill, Color(col.r, col.g, col.b, 0.07))
	_mesh_node(line, Color(col.r, col.g, col.b, 0.32))
	if not cells.is_empty():
		var center := sum / cells.size()
		_label("SKY LAYER %d  (R / F to change)" % lv, center + Vector3(0, 0.3, 0), col, 44, 22)


func _draw_los(los: Dictionary) -> void:
	_draw_cells(los.get("dim_cells", []), -1, COLORS["dim"], 0.55, false, 0.025)
	for id: String in los.get("no_los_units", []):
		var mv: MechView = battle.units.get(id)
		if mv == null:
			continue
		mv.model.set_fx("dim", 0.7)
		_dimmed_units.append(id)
		_label("NO LOS", mv.global_position + Vector3.UP * (mv.model.height + 0.8), Color(0.75, 0.75, 0.8), 36, 19)
