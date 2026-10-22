class_name ObjectiveMarkers
extends Node3D
## Sitrep objectives drawn on the board so players can see them: zones as a tinted floor
## with a bold animated border and a beacon at the center; extraction pads as a landing ring
## with chevrons and blinking lights; deployment zones as a soft edge tint. All flat on the
## ground (or a thin light column) so they never look like cover. Built from the mission's
## zones (name -> [[x, y]]) and deployment (side -> [[x, y]]); no secrets: show only what
## the seat's view contains (e.g. never mark Recon's True Control Zone).
##   terrain.show_objectives(mission.zones, mission.deployment)

const ZONE_COLOR := Color(1.0, 0.72, 0.15)
const EXTRACT_COLOR := Color(0.25, 1.0, 0.45)
const OBJECTIVE_COLOR := Color(0.3, 0.85, 1.0)
const SIDE_COLORS := {"players": Color(0.3, 0.7, 1.0), "enemies": Color(1.0, 0.3, 0.25)}
const LETTERS := "ABCDEFGH"

var t: TerrainRenderer


func setup(terrain: TerrainRenderer, zones: Dictionary, deployment: Dictionary = {}, show_deployment: bool = true) -> void:
	t = terrain
	name = "Objectives"
	if show_deployment:
		for side: String in deployment:
			_area(_cells(deployment[side]), Color(SIDE_COLORS.get(side, Color.WHITE), 0.16), 0.0, false)
	var names := zones.keys()
	names.sort()
	var letter := 0
	for zname: String in names:
		var cells := _cells(zones[zname])
		if cells.is_empty():
			continue
		if zname == "extraction":
			_area(cells, Color(EXTRACT_COLOR, 0.22), 1.0, true)
			_pad(cells)
			_label(cells, "EXTRACTION", EXTRACT_COLOR)
		elif zname == "objective":
			_area(cells, Color(OBJECTIVE_COLOR, 0.22), 1.0, true)
			_beacon(cells, OBJECTIVE_COLOR)
			_label(cells, "OBJECTIVE", OBJECTIVE_COLOR)
		else:
			_area(cells, Color(ZONE_COLOR, 0.2), 1.0, true)
			_beacon(cells, ZONE_COLOR)
			var text := "ZONE" if zname == "zone" else "ZONE " + LETTERS[letter % LETTERS.length()]
			letter += 1
			_label(cells, text, ZONE_COLOR)


static func _cells(list: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c: Array in list:
		out.append(Vector2i(c[0], c[1]))
	return out


func _center(cells: Array[Vector2i]) -> Vector3:
	var sum := Vector3.ZERO
	var top := 0.0
	for c in cells:
		sum += t.map.grid.to_world(c)
		top = maxf(top, t.top_y(c))
	sum /= cells.size()
	return Vector3(sum.x, top, sum.z)


## A tinted fill over the cells and (if `border`) a bold outline along the area's edge,
## pulsing gently. Sits just above the ground on each cell's own height.
func _area(cells: Array[Vector2i], color: Color, border_alpha: float, border: bool) -> void:
	var inside := {}
	for c in cells:
		if t.map.has_cell(c):
			inside[c] = true
	var fill := SurfaceTool.new()
	fill.begin(Mesh.PRIMITIVE_TRIANGLES)
	fill.set_color(Color.WHITE)
	var line := SurfaceTool.new()
	line.begin(Mesh.PRIMITIVE_TRIANGLES)
	line.set_color(Color.WHITE)
	var shape := MeshKit.cell_shape(t.map.grid)
	var edge_n: Array[Vector2i] = shape["edge_neighbors"]
	for c: Vector2i in inside:
		var y := t.top_y(c) + 0.02
		t.add_cell_fill(fill, c, y, 0.0)
		if not border:
			continue
		var outer := t.cell_corners(c, y + 0.004, 0.0)
		var inner := t.cell_corners(c, y + 0.004, 0.14)
		for i in range(outer.size()):
			if inside.has(c + edge_n[i]):
				continue
			var j := (i + 1) % outer.size()
			MeshKit.add_quad(line, outer[i], outer[j], inner[j], inner[i], Vector3.UP)
	var fm := MeshInstance3D.new()
	fm.name = "ZoneFill"
	fm.mesh = fill.commit()
	fm.material_override = MeshKit.overlay_material(color)
	fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fm)
	if border:
		var lm := MeshInstance3D.new()
		lm.name = "ZoneBorder"
		lm.mesh = line.commit()
		var m := MeshKit.fx_material(Color(color.r, color.g, color.b), 2.0, false)
		lm.material_override = m
		lm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lm)
		var tw := lm.create_tween() if lm.is_inside_tree() else null
		if tw:
			tw.set_loops()
			tw.tween_method(func(a: float) -> void: lm.set_instance_shader_parameter("alpha", a), 1.0, 0.55, 1.2)
			tw.tween_method(func(a: float) -> void: lm.set_instance_shader_parameter("alpha", a), 0.55, 1.0, 1.2)


## A thin light column and a slowly turning diamond above the zone's center: visible from
## anywhere on the board, too thin to block or cover anything.
func _beacon(cells: Array[Vector2i], color: Color) -> void:
	var c := _center(cells)
	var pole := MeshKit.part(self, MeshKit.cylinder(0.025, 4.0, 6), MeshKit.fx_material(color, 1.5), c + Vector3.UP * 2.0)
	pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var spin := Spinner.new()
	spin.axis = Vector3.UP
	spin.speed = 1.2
	spin.position = c + Vector3.UP * 4.3
	add_child(spin)
	var diamond := MeshKit.part(spin, MeshKit.sphere(0.22, 4), MeshKit.fx_material(color, 2.5), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.6, 1.0))
	diamond.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.8
	light.omni_range = 4.0
	light.position = c + Vector3.UP * 1.0
	add_child(light)


## Extraction pad: concentric rings and chevrons painted flat, corner lights blinking.
func _pad(cells: Array[Vector2i]) -> void:
	var c := _center(cells)
	var r := 0.0
	for cell in cells:
		r = maxf(r, Vector2(t.map.grid.to_world(cell).x - c.x, t.map.grid.to_world(cell).z - c.z).length())
	if r > 4.5:
		return  # a long strip (e.g. the whole deployment zone): the border and tint say enough
	r = maxf(1.0, r * 0.7)
	var mat := MeshKit.fx_material(EXTRACT_COLOR, 1.6, false)
	for k in range(2):
		var ring := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = r * (0.55 + 0.35 * k)
		tm.outer_radius = r * (0.55 + 0.35 * k) + 0.08
		tm.rings = 48
		tm.ring_segments = 4
		ring.mesh = tm
		ring.material_override = mat
		ring.scale = Vector3(1, 0.05, 1)
		ring.position = c + Vector3.UP * 0.03
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
	for k in range(4):
		var a := TAU * k / 4.0 + PI * 0.25
		var p := c + Vector3(cos(a), 0, sin(a)) * r * 1.05
		var blink := FlickerLight.new()
		blink.light_color = EXTRACT_COLOR
		blink.base_energy = 0.6
		blink.depth = 0.9
		blink.speed = 0.35
		blink.omni_range = 1.5
		blink.position = p + Vector3.UP * 0.2
		add_child(blink)
		MeshKit.part(self, MeshKit.sphere(0.07, 6), MeshKit.fx_material(EXTRACT_COLOR, 3.0), p + Vector3.UP * 0.07)


func _label(cells: Array[Vector2i], text: String, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.outline_size = 14
	l.pixel_size = 0.006
	l.modulate = color.lightened(0.3)
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = _center(cells) + Vector3.UP * 5.0
	add_child(l)
