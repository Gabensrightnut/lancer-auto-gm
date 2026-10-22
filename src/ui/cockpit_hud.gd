class_name CockpitHUD
extends Control
## First-person HUD: cockpit frame, reticle, your mech's HP / heat / structure, the selected
## weapon and range to target, and a minimap of the grid (cells, units, line to target).
## When your mech is hacked the panels glitch and show the attacker's ID.

var battle: BattleView
var unit_id := ""
var target_id := ""
var weapon_name := ""
var weapon_range := ""

var _glitch_t := 0.0
var _hacker := ""
var _minimap: Minimap


class Minimap extends Control:
	var hud: CockpitHUD
	## The board layer is drawn once into its own canvas item and only redone when the map
	## or the box changes (a 60x60 board is 3600 polygons); units are drawn every time.
	var _board: Control
	var _board_key := ""
	var _k := 1.0

	func _draw() -> void:
		var b := hud.battle
		if b == null or b.map == null:
			return
		if _board == null:
			_board = Control.new()
			_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_board.show_behind_parent = true
			_board.draw.connect(_draw_board)
			add_child(_board)
		_board.size = size
		var key := "%d|%s|%d" % [b.map.get_instance_id(), size, b.map.cells().size()]
		if key != _board_key:
			_board_key = key
			_board.queue_redraw()
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for c in b.map.cells():
			var w := b.map.grid.to_world(c)
			lo = Vector2(minf(lo.x, w.x), minf(lo.y, w.z))
			hi = Vector2(maxf(hi.x, w.x), maxf(hi.y, w.z))
		lo -= Vector2(1, 1)
		hi += Vector2(1, 1)
		var k := minf(size.x / (hi.x - lo.x), size.y / (hi.y - lo.y))
		_k = k
		var off := (size - (hi - lo) * k) / 2.0
		var to_map := func(w: Vector3) -> Vector2: return off + (Vector2(w.x, w.z) - lo) * k
		var me: MechView = b.units.get(hud.unit_id)
		var tgt: MechView = b.units.get(hud.target_id)
		if me and tgt:
			draw_line(to_map.call(me.global_position), to_map.call(tgt.global_position), Color(1.0, 0.85, 0.3, 0.9), 2.0)
		for id: String in b.units:
			var mv: MechView = b.units[id]
			if not mv.visible:
				continue
			var p: Vector2 = to_map.call(mv.global_position)
			# Dots scale with the board: about a space and a half across, 2-6 px.
			var r := clampf(k * 0.75 * maxf(1.0, mv.model.size), 2.0, 6.0)
			var col := Color(0.5, 0.5, 0.5) if mv.destroyed else mv.side_color()
			draw_circle(p, r, col)
			if id == hud.unit_id:
				draw_arc(p, r + 3.0, 0, TAU, 20, Color.WHITE, 2.0)
				var fwd := Vector2(-sin(mv.model.rotation.y), -cos(mv.model.rotation.y))
				draw_line(p, p + fwd * 14.0, Color.WHITE, 2.0)

	func _draw_board() -> void:
		var b := hud.battle
		if b == null or b.map == null:
			return
		_board.draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.05, 0.06, 0.8))
		var shape := MeshKit.cell_shape(b.map.grid)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for c in b.map.cells():
			var w := b.map.grid.to_world(c)
			lo = Vector2(minf(lo.x, w.x), minf(lo.y, w.z))
			hi = Vector2(maxf(hi.x, w.x), maxf(hi.y, w.z))
		lo -= Vector2(1, 1)
		hi += Vector2(1, 1)
		var k := minf(size.x / (hi.x - lo.x), size.y / (hi.y - lo.y))
		var off := (size - (hi - lo) * k) / 2.0
		var to_map := func(w: Vector3) -> Vector2: return off + (Vector2(w.x, w.z) - lo) * k
		for c in b.map.cells():
			var center: Vector2 = to_map.call(b.map.grid.to_world(c))
			var pts := PackedVector2Array()
			for p: Vector2 in shape["corners"]:
				pts.append(center + p * k * 0.92)
			var g := b.map.ground_height(c)
			var col := Color(0.1, 0.25, 0.28).lerp(Color(0.45, 0.85, 0.9), clampf(g / 5.0, 0.0, 1.0))
			_board.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.85))


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap = Minimap.new()
	_minimap.hud = self
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_minimap)


func hacked_by(attacker_name: String) -> void:
	_hacker = attacker_name
	_glitch_t = 2.5


func _process(delta: float) -> void:
	if not visible:
		return
	_glitch_t = maxf(0.0, _glitch_t - delta)
	var vp := get_viewport_rect().size
	_minimap.size = Vector2(260, 200)
	_minimap.position = Vector2(vp.x / 2.0 - 130, vp.y - 220)
	_minimap.queue_redraw()
	queue_redraw()


func _bar(pos: Vector2, w: float, label: String, value: float, maxv: float, color: Color, text: String) -> void:
	var font := get_theme_default_font()
	draw_string(font, pos + Vector2(0, -6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.9, 1.0, 0.9))
	draw_rect(Rect2(pos, Vector2(w, 14)), Color(0.05, 0.1, 0.12, 0.85))
	draw_rect(Rect2(pos, Vector2(w * clampf(value / maxf(maxv, 1.0), 0.0, 1.0), 14)), color)
	draw_rect(Rect2(pos, Vector2(w, 14)), Color(0.5, 0.8, 0.9, 0.6), false, 1.0)
	draw_string(font, pos + Vector2(w + 8, 12), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)


func _draw() -> void:
	var vp := get_viewport_rect().size
	var font := get_theme_default_font()
	var cyan := Color(0.45, 0.9, 1.0, 0.8)
	var jit := Vector2.ZERO
	if _glitch_t > 0.0:
		jit = Vector2(sin(Time.get_ticks_msec() * 0.05) * 8.0, cos(Time.get_ticks_msec() * 0.07) * 3.0) * minf(1.0, _glitch_t)
	# Cockpit frame: dark struts at the edges.
	var frame_col := Color(0.03, 0.035, 0.04, 0.95)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(vp.x, 0), Vector2(vp.x * 0.82, 48), Vector2(vp.x * 0.18, 48)]), frame_col)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(70, 60), Vector2(110, vp.y * 0.72), Vector2(0, vp.y)]), frame_col)
	draw_colored_polygon(PackedVector2Array([Vector2(vp.x, 0), Vector2(vp.x - 70, 60), Vector2(vp.x - 110, vp.y * 0.72), Vector2(vp.x, vp.y)]), frame_col)
	draw_colored_polygon(PackedVector2Array([Vector2(0, vp.y), Vector2(110, vp.y * 0.72), Vector2(vp.x - 110, vp.y * 0.72), Vector2(vp.x, vp.y)]), Color(0.03, 0.035, 0.04, 0.55))
	# Reticle.
	var c := vp / 2.0
	draw_arc(c, 26, 0, TAU, 40, cyan, 2.0)
	for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_line(c + d * 34, c + d * 52, cyan, 2.0)
	var me: MechView = battle.units.get(unit_id) if battle else null
	if me == null:
		return
	var u := me.unit
	# Left panel: your mech.
	var lp := Vector2(140, vp.y * 0.74) + jit
	draw_string(font, lp + Vector2(0, -40), String(u.get("name", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, cyan)
	_bar(lp, 200, "HP", float(u.get("hp", 0)), float(u.get("max_hp", 1)), Color(0.35, 0.9, 0.55), "%d/%d" % [int(u.get("hp", 0)), int(u.get("max_hp", 0))])
	_bar(lp + Vector2(0, 40), 200, "HEAT", float(u.get("heat", 0)), float(u.get("heat_cap", 1)), Color(1.0, 0.5, 0.15), "%d/%d" % [int(u.get("heat", 0)), int(u.get("heat_cap", 0))])
	var s := int(u.get("structure", 4))
	draw_string(font, lp + Vector2(0, 92), "STRUCTURE  " + "◆".repeat(s) + "◇".repeat(maxi(0, int(u.get("max_structure", 4)) - s)), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	# Right panel: weapon and target.
	var rp := Vector2(vp.x - 420, vp.y * 0.74) - jit
	draw_string(font, rp + Vector2(0, -40), "WEAPON", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.9, 1.0, 0.9))
	draw_string(font, rp + Vector2(0, -14), weapon_name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	draw_string(font, rp + Vector2(0, 12), weapon_range, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.85, 0.9))
	var tgt: MechView = battle.units.get(target_id)
	if tgt:
		var dist := battle.map.grid.footprint_distance(battle.map.grid.footprint(me.cell, me.model.size), battle.map.grid.footprint(tgt.cell, tgt.model.size))
		draw_string(font, rp + Vector2(0, 46), "TARGET  %s" % String(tgt.unit.get("name", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1.0, 0.5, 0.4))
		draw_string(font, rp + Vector2(0, 70), "RANGE  %d" % dist, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		# Bracket the target on screen.
		var cam := get_viewport().get_camera_3d()
		if cam and not cam.is_position_behind(tgt.body_center()):
			var sp := cam.unproject_position(tgt.body_center())
			var r := 40.0
			var red := Color(1.0, 0.35, 0.3, 0.9)
			for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var p := sp + corner * r
				draw_line(p, p - Vector2(corner.x * 14, 0), red, 2.0)
				draw_line(p, p - Vector2(0, corner.y * 14), red, 2.0)
	if _glitch_t > 0.0:
		var a := minf(1.0, _glitch_t)
		for i in range(14):
			var y := fmod(Time.get_ticks_msec() * 0.3 + i * 67.0, vp.y)
			draw_rect(Rect2(0, y, vp.x, 3), Color(0.3, 1.0, 0.5, 0.25 * a))
		draw_string(font, Vector2(vp.x / 2.0 - 220, 110) + jit, "!! SYSTEM INTRUSION: %s !!" % _hacker.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.35, 1.0, 0.5, a))
